"""Merge the per-run wing results; add drawing displacement against the study setting."""
import glob, json, sys
import numpy as np
import sheet as S, metrics as Mt, meshops as M, wing as W, sil
OUT, D = sys.argv[1], sys.argv[2]
f = S.load_fold(f"{D}/rigid.fold")
amap = S.assignment_map(f)
F1, UV1, _, _, _, _ = M.refine(f["F"], f["UV"], f["X"], amap, f["panels"])
UVs = {"original": f["UV"], "flipped": f["UV"], "refined1": UV1}
runs, store = [], {}
for j in sorted(glob.glob(f"{OUT}/wing-parts/*.json")):
    r = json.load(open(j))
    z = np.load(j[:-5] + ".npz")
    key = f"{r['grip']}__{r['mesh']}__{r['w']:.1e}"
    store[key] = z["X"]; store["F__" + key] = z["F"]
    runs.append(r)
for r in runs:
    ref = f"{r['grip']}__original__1.0e+08"
    key = f"{r['grip']}__{r['mesh']}__{r['w']:.1e}"
    d = Mt.material_displacement(store[ref], f["UV"], store["F__" + ref], store[key], UVs[r["mesh"]])
    r["drawing_displacement_vs_original_1e8_px"] = dict(max=float(d.max()), p95=float(np.percentile(d, 95)))
    r["silhouette_vs_original_1e8"] = sil.compare_all(store[ref], store["F__" + ref], store[key], store["F__" + key])
    print(key, "Jmax %.1f J>45 %d J>20 %d" % (r["stats"]["J_max_deg"], r["stats"]["J_over_45"], r["stats"]["J_over_20"]),
          "edgeErr %.2e stretch %.3f" % (r["stats"]["max_rel_edge_error"], r["stats"]["max_stretch"]),
          "disp px max %.2f p95 %.2f" % (d.max(), np.percentile(d, 95)), "haus %.2f" % r["silhouette_vs_original_1e8"]["max_hausdorff_px"],
          "grad %.1e" % r["stages"][-1]["grad_inf"], "it", [s["iterations"] for s in r["stages"]], "t", [round(x, 1) for x in r["seconds"]])
json.dump({"runs": runs}, open(f"{OUT}/wing.json", "w"), indent=1, default=float)
np.savez_compressed(f"{OUT}/wing.npz", **store)
