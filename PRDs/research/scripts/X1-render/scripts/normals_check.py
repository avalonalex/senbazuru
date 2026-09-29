"""Compare panel-smooth corner normals computed the way Blender does it
(smooth across edges not marked sharp, corner-angle weighted) with the study's
PaperLighting normals (area weighted, per panel) in *-lighting.json."""
import sys, json, numpy as np
sys.path.insert(0, sys.argv[1]); import foldlayers as fl
for fold, light in zip(sys.argv[2::2], sys.argv[3::2]):
    d, V, F = fl.load(fold)
    L = json.load(open(light))
    tri = L["vertices"]; nrm = np.array(L["normals"])
    same_order = all(list(t) == list(f) for t, f in zip(tri, F))
    # glTF axes -> FOLD axes: (x, y, z)_gltf = (x, z, -y)_fold  =>  fold = (x, -z, y)
    nf = np.stack([nrm[..., 0], -nrm[..., 2], nrm[..., 1]], -1)
    N, A, C = fl.face_normals(V, F)
    panel = d["senbazuru:source_panels"]
    acc = {}
    for fi, f in enumerate(F):
        P = V[f]
        for i, v in enumerate(f):
            e1 = P[(i + 1) % 3] - P[i]; e2 = P[(i - 1) % 3] - P[i]
            ang = np.arccos(np.clip(e1 @ e2 / (np.linalg.norm(e1) * np.linalg.norm(e2)), -1, 1))
            acc[(v, panel[fi])] = acc.get((v, panel[fi]), 0) + ang * N[fi]
    errs = []
    for fi, f in enumerate(F):
        for i, v in enumerate(f):
            b = acc[(v, panel[fi])]; b = b / np.linalg.norm(b)
            errs.append(np.degrees(np.arccos(np.clip(b @ nf[fi][i], -1, 1))))
    errs = np.array(errs)
    print(fold.split('/')[-1], 'triangle order matches FOLD:', same_order, 'corners', len(errs),
          'angle-weighted vs PaperLighting: median %.3f deg, p95 %.3f, max %.3f' % (np.median(errs), np.percentile(errs, 95), errs.max()))
    behind = 0; big = 0
    k = 0
    for fi, f in enumerate(F):
        for i, v in enumerate(f):
            b = acc[(v, panel[fi])]; b = b / np.linalg.norm(b)
            behind += (b @ N[fi]) <= 0
            big += errs[k] > 30; k += 1
    print('   corners whose angle-weighted average points behind their own triangle:', behind, '; corners differing by >30 deg:', big)
