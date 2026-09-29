"""Experiment P2: the positive control at tighter curvature (180 and 270 degree
total turn), where locking should be strongest."""
import json, sys
import numpy as np
import sheet as S, relax as R, metrics as Mt
from run_strip_lib import strip_mesh, cylinder
OUT = sys.argv[1]
res = []
store = {}
for turn in (180, 270):
    for n in (16, 32):
        for diag in ("/", "\\"):
            UV, F, amap, nx = strip_mesh(n, diag)
            H, rest, k, kind = S.build_hinges(F, UV, amap)
            Xc, Rr = cylinder(UV, -45, turn)
            h = 1.0 / nx
            held = (UV[:, 0] <= h + 1e-9) | (UV[:, 0] >= 1 - h - 1e-9)
            P = R.Problem(UV, F, H, rest, k, held)
            for w in (1e8, 4.3e6):
                X, reps, t = R.relax(P, Xc, w, max_iter=1500)
                st = S.stats(X, UV, F, H, kind)
                dev = np.linalg.norm(X - Xc, axis=1) * 600
                d = X[P.Ed[:, 1]] - X[P.Ed[:, 0]]
                memb = w * float(((np.linalg.norm(d, axis=1) - P.l0) ** 2).sum())
                bend = float((k * S.wrap(S.hinge_angles(X, H) - rest) ** 2).sum())
                r = dict(turn=turn, n=n, diag=diag, w=w, R=Rr, stats=st, max_dev_px=float(dev.max()), membrane=memb, bending=bend,
                         grad=reps[-1]["grad_inf"], iterations=[q["iterations"] for q in reps], seconds=t)
                res.append(r)
                store[f"t{turn}_{n}_{'fwd' if diag=='/' else 'back'}_{w:.1e}"] = X
                store[f"cyl_t{turn}_{n}_{'fwd' if diag=='/' else 'back'}"] = Xc
                store[f"F_{n}_{'fwd' if diag=='/' else 'back'}"] = F
                print(turn, n, diag, f"{w:.1e}", "R %.3f" % Rr, "Jmax %.2f" % st["J_max_deg"], ">20", st["J_over_20"], ">45", st["J_over_45"],
                      "dev px %.2f" % dev.max(), "stretch %.1e" % st["max_stretch"], "memb %.2e bend %.2e" % (memb, bend),
                      "grad %.1e" % reps[-1]["grad_inf"], "it", [q["iterations"] for q in reps], "t %.1f" % t, flush=True)
json.dump(res, open(f"{OUT}/strip_tight.json", "w"), indent=1, default=float)
np.savez_compressed(f"{OUT}/strip_tight.npz", **store)
