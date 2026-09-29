"""Experiment S: relax spread-0 itself with the study's energy, holding exactly
the construction's anchors (cushion core + wing arches), on the study mesh and
the once-refined mesh, at w = 1e8 and 4.3e6. No contact.

This asks: once lengths and bending are allowed to act, do the joins bent
past 45 degrees disappear (a soft, fine membrane smooths them) or stay (the
anchors force them)?"""
import json
import sys
import numpy as np

import sheet as S
import anchors as A
import construct as C
import meshops as M
import relax as R
import metrics as Mt

G, OUT = sys.argv[1], sys.argv[2]
m = S.load_fold(f"{G}/spread-0.fold")
b = S.load_fold(f"{G}/before.fold")
amap = S.assignment_map(b)
core, wing, wa, wb = A.find_anchors(m["X"], m["UV"], b["X"])
reg = C.panel_regions(b["F"], b["panels"], core, wa, wb)
z = np.load(f"{OUT}/construction.npz", allow_pickle=True)

variants = {
    "original": (b["F"], b["UV"], m["X"], core | wing, amap),
}
F1, UV1, X1, A1, P1, par1 = M.refine(b["F"], b["UV"], b["X"], amap, b["panels"])
mem = C.memberships(F1, P1, reg, len(UV1))
T1, k1 = C.anchor_targets(UV1, X1, mem)
variants["refined1"] = (F1, UV1, z["refined1__X"], ~np.isnan(T1[:, 0]), A1)

out = []
store = {}
for name, (F, UV, X0, pinned, am) in variants.items():
    H, rest, k, kind = S.build_hinges(F, UV, am)
    st0 = S.stats(X0, UV, F, H, kind, rest)
    P = R.Problem(UV, F, H, rest, k, pinned)
    for w in (1e8, 4.3e6):
        X, reps, t = R.relax(P, X0, w, max_iter=600)
        st = S.stats(X, UV, F, H, kind, rest)
        d = Mt.material_displacement(m["X"], m["UV"], b["F"], X, UV)
        r = dict(mesh=name, w=w, triangles=int(len(F)), pinned=int(pinned.sum()), start=st0, stats=st,
                 displacement_from_sketch_px=dict(max=float(d.max()), p95=float(np.percentile(d, 95)), median=float(np.median(d))),
                 stages=reps, seconds=t)
        out.append(r)
        store[f"{name}_{w:.1e}"] = X
        print(name, f"{w:.1e}", "start J>45", st0["J_over_45"], "-> J>45", st["J_over_45"], "J>20", st["J_over_20"],
              "Jmax %.1f" % st["J_max_deg"], "stretch %.3f squash %.3f" % (st["max_stretch"], st["min_squash"]),
              "a10 %.3f" % st["area_strained_over_10pct"], "disp px max %.0f p95 %.0f" % (d.max(), np.percentile(d, 95)),
              "grad %.1e" % reps[-1]["grad_inf"], "it", [q["iterations"] for q in reps], "t %.1f" % t, flush=True)
json.dump(out, open(f"{OUT}/sketch_relax.json", "w"), indent=1, default=float)
np.savez_compressed(f"{OUT}/sketch_relax.npz", **store, F_original=b["F"], F_refined1=F1, UV_refined1=UV1)
