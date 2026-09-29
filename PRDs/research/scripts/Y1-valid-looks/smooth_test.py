"""Display-smoothing safety test (critic conflict B8).

For one FOLD file: Catmull-Clark (Blender Subdivision Surface, crease 1.0 on
M/V/F/B edges) against Blender's SIMPLE subdivision of the same level, and own
Phong tessellation (alpha 0.75) against the same tessellation at alpha 0. Each
smoothed mesh is compared with its control, which has the identical topology
and parent map but unmoved positions, so every difference is caused by the
smoothing.

Usage: python smooth_test.py NAME FOLD [LEVEL] [PHONG_N]
Writes out/NAME-*.npz and out/NAME-smooth.json.
"""
import json, os, subprocess, sys, time
import numpy as np
import geom

T = 1 / 1500          # 0.1 mm on a 15 cm sheet
HERE = os.path.dirname(os.path.abspath(__file__))
BL = "/Applications/Blender.app/Contents/MacOS/Blender"
name, path = sys.argv[1], sys.argv[2]
level = int(sys.argv[3]) if len(sys.argv) > 3 else 2
pn = int(sys.argv[4]) if len(sys.argv) > 4 else 4
os.makedirs(f"{HERE}/out", exist_ok=True)

variant = sys.argv[5] if len(sys.argv) > 5 else "s0"
kinds = tuple(sys.argv[6]) if len(sys.argv) > 6 else ("M", "V", "F", "B")   # e.g. MVFBU
if variant == "s1":
    # layers separated by 1.1 t along their stack direction, with fold walls (X1's display mesh)
    import layers
    V, F, sharp, s1info = layers.s1_mesh(path, 1.1 * T, kinds=kinds)
    report = dict(name=name, fold=path, crease_kinds="".join(kinds), variant="s1 (layers 1.1 t apart, bridge walls)", vertices=len(V),
                  triangles=len(F), sharp_edges=len(sharp), t=T,
                  s1={k: v for k, v in s1info.items() if k != "orig"})
else:
    fold = geom.load_fold(path)
    V, F = fold["V"], fold["F"]
    sharp = geom.sharp_edge_set(fold, kinds)
    report = dict(name=name, fold=path, crease_kinds="".join(kinds), variant="s0 (zero thickness, coincident layers)", vertices=len(V),
                  triangles=len(F), sharp_edges=len(sharp), t=T)


def compare(label, Pc, Ps, Ft, parent):
    """Pc control corners, Ps smoothed corners (same topology Ft)."""
    t0 = time.perf_counter()
    cand = np.unique(np.vstack([geom.candidate_pairs(Pc, Ft, T), geom.candidate_pairs(Ps, Ft, T)]), axis=0)
    pc_dep = np.zeros(len(cand)); ps_dep = np.zeros(len(cand))
    cc, dc = geom.pair_metrics(Pc, cand, depth_out=pc_dep)
    cs, ds = geom.pair_metrics(Ps, cand, depth_out=ps_dep)
    t1 = time.perf_counter()
    new_cross = cs & ~cc
    new_near = (ds < T) & (dc >= T)
    pp = np.sort(parent[cand], axis=1)
    diff_parent = pp[:, 0] != pp[:, 1]
    # source-level relation of every parent pair that appears
    PP, pinv = np.unique(pp[diff_parent], axis=0, return_inverse=True)
    src_dep = np.zeros(len(PP))
    sc, sd = geom.pair_metrics(V[F], PP, depth_out=src_dep)
    so = geom.coplanar_overlap(V[F], PP)
    oc = geom.coplanar_overlap(Pc, cand[diff_parent])
    os_ = geom.coplanar_overlap(Ps, cand[diff_parent])
    sub_cs, sub_ds = cs[diff_parent], ds[diff_parent]

    def parents(mask):
        return int(len(np.unique(pp[mask & diff_parent], axis=0)))

    def src_count(child_mask, src_mask):
        hit = np.zeros(len(PP), bool)
        np.logical_or.at(hit, pinv.ravel(), child_mask)
        return int((hit & src_mask).sum())
    src_new_cross = src_count(sub_cs, ~sc)
    sub_dep = ps_dep[diff_parent]
    # crossings deeper than the study's contact tolerance (1e-7) / than one paper thickness
    src_new_cross_1e7 = src_count(sub_dep > 1e-7, src_dep <= 1e-7)
    src_new_cross_t = src_count(sub_dep > T, src_dep <= T)
    new_dep = ps_dep[new_cross & diff_parent]
    src_new_near = src_count(sub_ds < T, sd >= T)
    src_new_overlap = src_count(os_ & ~oc, ~so)
    src_new_overlap_vs_source = src_count(os_, ~so)

    disp = np.linalg.norm(Ps - Pc, axis=-1)
    r = dict(sub_triangles=len(Ft), candidate_pairs=int(len(cand)),
             control_crossing_pairs=int(cc.sum()), smoothed_crossing_pairs=int(cs.sum()),
             new_crossing_pairs=int(new_cross.sum()), new_crossing_source_pairs=parents(new_cross),
             control_near_pairs=int((dc < T).sum()), smoothed_near_pairs=int((ds < T).sum()),
             new_near_pairs=int(new_near.sum()), new_near_source_pairs=parents(new_near),
             removed_near_pairs=int(((dc < T) & (ds >= T)).sum()),
             source_pairs_seen=int(len(PP)),
             source_pairs_newly_crossing=src_new_cross,
             source_pairs_newly_crossing_deeper_1e7=src_new_cross_1e7,
             source_pairs_newly_crossing_deeper_t=src_new_cross_t,
             control_crossing_pairs_deeper_1e7=int((pc_dep > 1e-7).sum()),
             smoothed_crossing_pairs_deeper_1e7=int((ps_dep > 1e-7).sum()),
             new_crossing_depth_max_in_t=float(new_dep.max() / T) if len(new_dep) else 0.0,
             new_crossing_depth_median_in_t=float(np.median(new_dep) / T) if len(new_dep) else 0.0,
             source_pairs_newly_within_t=src_new_near,
             source_pairs_newly_overlapping_coplanar=src_new_overlap_vs_source,
             source_pairs_newly_overlapping_coplanar_vs_control=src_new_overlap,
             control_coplanar_overlap_child_pairs=int(oc.sum()), smoothed_coplanar_overlap_child_pairs=int(os_.sum()),
             max_displacement=float(disp.max()), max_displacement_in_t=float(disp.max() / T),
             median_displacement=float(np.median(disp)),
             moved_more_than_t_fraction=float((disp.max(1) > T).mean()),
             seconds=t1 - t0)
    # which source triangles take part in new crossings
    if new_cross.any():
        r["source_triangles_in_new_crossings"] = sorted({int(x) for x in parent[cand[new_cross]].ravel()})[:80]
    np.savez(f"{HERE}/out/{name}-{label}.npz", Pc=Pc, Ps=Ps, Ft=Ft, parent=parent, cand=cand,
             new_cross=new_cross, new_near=new_near)
    print(label, json.dumps({k: v for k, v in r.items() if k != "source_triangles_in_new_crossings"}))
    return r


# ---------------- source mesh baseline (no smoothing)
cand0 = geom.candidate_pairs(V[F], F, T)
dep0 = np.zeros(len(cand0))
c0, d0 = geom.pair_metrics(V[F], cand0, depth_out=dep0)
report["source"] = dict(candidate_pairs=int(len(cand0)), crossing_pairs=int(c0.sum()), near_pairs=int((d0 < T).sum()),
                        crossing_depth_max=float(dep0.max()), crossing_pairs_deeper_1e7=int((dep0 > 1e-7).sum()),
                        zero_distance_pairs=int((d0 < 1e-12).sum()))
print("source", report["source"])

# ---------------- Blender Catmull-Clark vs SIMPLE
np.savez(f"{HERE}/out/{name}-in.npz", V=V, F=F, S=np.array([sorted(s) for s in sharp]))
meshes = {}
for mode in ("SIMPLE", "CATMULL_CLARK"):
    o = f"{HERE}/out/{name}-{mode}.npz"
    t0 = time.perf_counter()
    res = subprocess.run([BL, "-b", "--factory-startup", "--python", f"{HERE}/bl_subdiv.py", "--",
                          f"{HERE}/out/{name}-in.npz", o, mode, str(level)], capture_output=True, text=True)
    line = [l for l in res.stdout.splitlines() if l.startswith("SUBDIV")]
    print(line[0] if line else res.stdout[-2000:] + res.stderr[-2000:])
    report.setdefault("blender", {})[mode] = dict(log=line[0] if line else None, wall=time.perf_counter() - t0)
    z = np.load(o)
    polys = np.split(z["flat"], np.cumsum(z["sizes"])[:-1])
    tris = []
    tpar = []
    for p, par in zip(polys, z["parent"]):
        for i in range(1, len(p) - 1):
            tris.append((p[0], p[i], p[i + 1])); tpar.append(par)
    meshes[mode] = (z["V"], np.array(tris), np.array(tpar))
(Vc, Fc, parc), (Vs, Fs, pars) = meshes["SIMPLE"], meshes["CATMULL_CLARK"]
assert np.array_equal(Fc, Fs) and np.array_equal(parc, pars), "SIMPLE and CC topology differ"
# the parent attribute must point at the right source triangle: SIMPLE children lie inside it
cent = Vc[Fc].mean(1)
P = V[F][parc]
n = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
bary_ok = 0
for k in range(3):
    e = np.cross(P[:, (k + 1) % 3] - P[:, k], cent - P[:, k])
    bary_ok += ((e * n).sum(1) >= -1e-12)
report["parent_map_ok_fraction"] = float((bary_ok == 3).mean())
print("parent map ok fraction", report["parent_map_ok_fraction"])
report["catmull_clark"] = compare("cc", Vc[Fc], Vs[Fs], Fc, parc)

# ---------------- own Phong tessellation vs linear
CN, flat_kept = geom.corner_normals(V, F, sharp)
Pc, Ft, parp, crack0 = geom.phong_tessellate(V, F, CN, pn, 0.0)
Ps, Ft2, parp2, crack = geom.phong_tessellate(V, F, CN, pn, 0.75)
assert np.array_equal(Ft, Ft2)
report["phong"] = compare("phong", Pc, Ps, Ft, parp)
report["phong"].update(crack_width=crack, crack_width_in_t=crack / T, crack_width_alpha0=crack0,
                       corners_kept_face_normal=flat_kept, n=pn, alpha=0.75)
print("phong crack", crack, "=", crack / T, "t; corners kept flat", flat_kept)
json.dump(report, open(f"{HERE}/out/{name}-smooth.json", "w"), indent=1)
