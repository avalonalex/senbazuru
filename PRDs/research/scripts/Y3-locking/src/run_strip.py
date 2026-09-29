"""Experiment P (positive control): a held strip bent into an exact cylinder
whose generators run either across the strip (aligned with mesh edges) or at
45 degrees (along or against the cell diagonals).

The strip is 1 x 0.25 sheet units, square cells of side h, one diagonal per
cell. Both end columns of cells are held on the exact isometric cylinder of
radius R; everything else starts on it too and is relaxed with the study's
energy (B = 0.2 join bending, edge springs w). If the mesh cannot bend about
the generators without stretching, it must either stretch or bend somewhere
else: that is locking, and this control shows what it looks like in the
metrics used on the crane (J bends, silhouette at 600 px, strain).
"""
import json
import sys
import numpy as np

import sheet as S
import relax as R
import sil

OUT = sys.argv[1]
L, Wd = 1.0, 0.25


def strip_mesh(n, diag):
    nx, ny = n, n // 4
    xs = np.linspace(0, L, nx + 1)
    ys = np.linspace(0, Wd, ny + 1)
    UV = np.array([(x, y) for y in ys for x in xs])
    idx = lambda i, j: j * (nx + 1) + i
    F = []
    for j in range(ny):
        for i in range(nx):
            a, b, c, d = idx(i, j), idx(i + 1, j), idx(i + 1, j + 1), idx(i, j + 1)
            if diag == "/":
                F += [(a, b, c), (a, c, d)]
            else:
                F += [(a, b, d), (b, c, d)]
    F = np.array(F, int)
    amap = {}
    return UV, F, amap, nx


def cylinder(UV, gen_deg, turn_deg):
    g = np.array([np.cos(np.radians(gen_deg)), np.sin(np.radians(gen_deg))])
    nrm = np.array([-g[1], g[0]])
    c0 = np.array([L / 2, Wd / 2])
    s = (UV - c0) @ nrm
    t = (UV - c0) @ g
    span = s.max() - s.min()
    Rr = span / np.radians(turn_deg)
    X = (t[:, None] * np.append(g, 0) + (Rr * np.sin(s / Rr))[:, None] * np.append(nrm, 0)
         + (Rr * (1 - np.cos(s / Rr)))[:, None] * np.array([0, 0, 1.0]))
    return X, Rr


results = []
store = {}
for gen, label in ((90, "across"), (-45, "diag45")):
    for n in (16, 32):
        for diag in ("/", "\\"):
            UV, F, amap, nx = strip_mesh(n, diag)
            H, rest, k, kind = S.build_hinges(F, UV, amap)
            Xc, Rr = cylinder(UV, gen, 60)
            h = L / nx
            held = (UV[:, 0] <= h + 1e-9) | (UV[:, 0] >= L - h - 1e-9)
            P = R.Problem(UV, F, H, rest, k, held)
            for w in (1e8, 4.3e6, 4.3e5):
                X, reps, t = R.relax(P, Xc, w, max_iter=800)
                st = S.stats(X, UV, F, H, kind)
                dev = np.linalg.norm(X - Xc, axis=1)
                sv = sil.compare_all(Xc, F, X, F)
                # membrane and bending parts of the energy
                d = X[P.Ed[:, 1]] - X[P.Ed[:, 0]]
                memb = w * float(((np.linalg.norm(d, axis=1) - P.l0) ** 2).sum())
                bend = float((k * S.wrap(S.hinge_angles(X, H) - rest) ** 2).sum())
                bend_ideal = float((k * S.wrap(S.hinge_angles(Xc, H) - rest) ** 2).sum())
                r = dict(generators=label, n=n, diag=diag, w=w, triangles=int(len(F)), R=Rr, stats=st,
                         max_dev_from_cylinder_px=float(dev.max() * 600), silhouette_vs_cylinder=sv,
                         membrane_energy=memb, bending_energy=bend, bending_energy_on_cylinder=bend_ideal,
                         grad_inf=reps[-1]["grad_inf"], iterations=[q["iterations"] for q in reps], seconds=t)
                results.append(r)
                store[f"{label}_{n}_{'fwd' if diag == '/' else 'back'}_{w:.1e}"] = X
                print(label, n, diag, f"{w:.1e}", "Jmax", round(st["J_max_deg"], 2), ">20", st["J_over_20"], ">45", st["J_over_45"],
                      "dev px", round(dev.max() * 600, 2), "haus px", round(sv["max_hausdorff_px"], 2),
                      "stretch", f"{st['max_stretch']:.2e}", "memb", f"{memb:.2e}", "bend", f"{bend:.3e}/{bend_ideal:.3e}",
                      "grad", f"{reps[-1]['grad_inf']:.1e}", "it", [q['iterations'] for q in reps], flush=True)
            store[f"cyl_{label}_{n}_{'fwd' if diag == '/' else 'back'}"] = Xc
            store[f"F_{n}_{'fwd' if diag == '/' else 'back'}"] = F
            store[f"UV_{n}"] = UV

json.dump(results, open(f"{OUT}/strip.json", "w"), indent=1, default=float)
np.savez_compressed(f"{OUT}/strip.npz", **store)
