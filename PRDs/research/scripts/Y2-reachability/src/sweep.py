"""Trace the trade-off between staying on the sketch and being paper.

usage: sweep.py MODEL VARIANT KB [LEVELS] [TAG]
  MODEL    spread-0 | after | narrow (gallery/whole-crane/MODEL.fold)
  VARIANT  all3d  (every vertex pulled toward the sketch in 3D)
           plane  (every vertex pulled in the upright camera's picture plane; depth free)
           anchors (only wing tips, neck/tail tips and body top pulled, in 3D)
  KB       bending weight on J edges (membrane weight is 1); with TAG containing
           "rel" the weight is KB * lam, i.e. relative to the pull
  LEVELS   material-space 1-to-4 subdivisions of the mesh (default 0)

The pull weight lam runs from 1e3 down to 1e-9 in half-decade steps, each
solve warm-started from the previous one (continuation from the sketch).
"""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
import mesh, solve

model, variant, kb = sys.argv[1], sys.argv[2], float(sys.argv[3])
levels = int(sys.argv[4]) if len(sys.argv) > 4 else 0
tag = sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] != "_" else ""
membrane = "edge" if "edge" in tag else "green"
start = sys.argv[6] if len(sys.argv) > 6 else None  # optional: start the sweep at this lam (no continuation above it)
G = os.path.join(os.path.dirname(__file__), "../../../gallery/whole-crane/")
m = mesh.load_fold(G + model + ".fold")
for _ in range(levels):
    m = mesh.subdivide(m)
target = m["X"].copy()
ANCHORS = [0, 2, 54, 57, 24]  # neck/tail tips, wing tips, body top (paper centre)
plane = None
pulled = None
if variant == "plane":
    r, u, f = mesh.upright_basis(); plane = (r, u)
elif variant == "anchors":
    pulled = ANCHORS
# "-anch": extra pull on the anchor vertices (wing tips, neck/tail tips, body top)
# worth ANCHOR_W times the whole sheet's pull; "-anchbody" adds the pillow rim ends.
# "-p8": iteratively reweighted pull that approximates minimising the 8-norm of the
# displacement (closer to "smallest largest movement" than the mean square).
w0 = m["varea"] / m["varea"].sum()
extra = []
if "anch" in tag:
    extra = ANCHORS + ([13, 35] if "anchbody" in tag else [])
    w0 = w0.copy(); w0[extra] += 20.0 / len(extra)
name = f"{model}-{variant}-kb{kb:g}-L{levels}{tag}"
outdir = os.path.join(os.path.dirname(__file__), "../out", name)
os.makedirs(outdir, exist_ok=True)
lams = [10 ** (3 - 0.5 * k) for k in range(25)]  # 1e3 ... 1e-9
if start is not None:
    lams = [l for l in lams if l <= float(start) * 1.0001]
x = target.ravel().copy()
if os.environ.get("Y2_X0"):  # optional different starting state (e.g. X3's IPC-opened crane, welded)
    x = np.load(os.environ["Y2_X0"]).ravel().copy()
rows = []
t_all = time.time()
m0 = mesh.measure(m, target, target, silhouette=False, cross=(levels == 0))
m0.update(lam=None, iterations=0, seconds=0.0)
rows.append(m0)
print(name, "sketch", json.dumps(m0), flush=True)
for lam in lams:
    # "-rel": bending scales with the pull (kb * lam), so as lam -> 0 the solve tends to
    # "closest shape plus kb * bending, subject to isometry" instead of letting a fixed
    # bending weight flatten every panel once the pull has become weak.
    kbv = kb * lam if "rel" in tag else kb
    w = w0
    reps = 4 if "p8" in tag else 1
    for rep in range(reps):
        if rep:
            dv = np.linalg.norm(x.reshape(-1, 3) - target, axis=1)
            ref = max(np.sqrt((w0 * dv ** 2).sum()), 1e-6)
            w = w0 * np.maximum(dv / ref, 1.0) ** 6  # only ever raise a weight
        prob = solve.Problem(m, target, lam, pulled=pulled, kb=kbv, plane=plane, membrane=membrane,
                             weights=w if pulled is None else None)
        x, info = solve.lm(prob, x, max_iter=300)
    X = x.reshape(-1, 3)
    meas = mesh.measure(m, X, target, silhouette=True, cross=True)
    meas.update(lam=lam, **info)
    rows.append(meas)
    np.save(os.path.join(outdir, f"X_lam{lam:.0e}.npy"), X)
    json.dump(dict(model=model, variant=variant, kb=kb, levels=levels, membrane=membrane, start=start, vertices=len(m["U"]),
                   triangles=len(m["F"]), seconds=time.time() - t_all, rows=rows, partial=True),
              open(os.path.join(outdir, "sweep.json"), "w"), indent=1)
    print(name, f"lam={lam:.1e}", f"it={info['iterations']} {info['stop']} {info['seconds']:.1f}s",
          f"strain={meas['max_principal_strain']:.3e} edge={meas['max_edge_error']:.3e}",
          f"sil_H={meas['sil_hausdorff_px']:.1f}px mean={meas['sil_mean_px']:.2f}px vmax={meas['vertex_max_px']:.1f}px",
          f"cross={meas['crossing_pairs']} J45={meas['J_over_45']} def5={meas['defect_over_5']}", flush=True)
json.dump(dict(model=model, variant=variant, kb=kb, levels=levels, membrane=membrane, start=start, vertices=len(m["U"]), triangles=len(m["F"]),
               seconds=time.time() - t_all, rows=rows), open(os.path.join(outdir, "sweep.json"), "w"), indent=1)
