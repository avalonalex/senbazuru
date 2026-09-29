"""Table of every sweep at the first pull weight whose result meets each strain target."""
import json, glob, os, sys
rows = []
for f in sorted(glob.glob(os.path.join(os.path.dirname(__file__), "../out/*/sweep.json"))):
    d = json.load(open(f))
    run = os.path.basename(os.path.dirname(f))
    sk = d["rows"][0]
    for target in (0.01, 0.001):
        hit = [r for r in d["rows"][1:] if r["max_principal_strain"] <= target]
        if not hit:
            rows.append((run, target, None)); continue
        r = hit[0]
        rows.append((run, target, r))
    rows.append((run, "final", d["rows"][-1]))
    rows.append((run, "meta", dict(tris=d["triangles"], secs=d["seconds"], sketch_cross=sk.get("crossing_pairs"))))
out = []
hdr = "| run | target | lam | max strain | area>0.1% | sil Hausdorff px | sil mean px | sil p95 px | XOR % | proj vertex max px | proj vertex mean px | 3D vertex max px | crossings | J>45 | J>20 | defect>5 | defect>1 | LM its | stop |"
out.append(hdr); out.append("|" + "---|" * (hdr.count("|") - 1))
for run, t, r in rows:
    if t == "meta":
        continue
    if r is None:
        out.append(f"| {run} | {t} | not reached |" + " |" * 16); continue
    out.append(f"| {run} | {t} | {r['lam']:.1e} | {100*r['max_principal_strain']:.3g}% | {100*r['area_over_01pct']:.0f}% | {r['sil_hausdorff_px']:.1f} | {r['sil_mean_px']:.1f} | {r['sil_p95_px']:.1f} | {100*r['sil_xor_fraction']:.1f} | {r['proj_vertex_max_px']:.1f} | {r['proj_vertex_mean_px']:.1f} | {r['vertex_max_px']:.1f} | {r['crossing_pairs']} | {r['J_over_45']} | {r['J_over_20']} | {r['defect_over_5']} | {r['defect_over_1']} | {r['iterations']} | {r['stop']} |")
print("\n".join(out))
open(os.path.join(os.path.dirname(__file__), "../out/summary.md"), "w").write("\n".join(out) + "\n")
