"""Shape descriptors for sketches and projected states, comparable with X3.

Body opening: the same definition X3 used (re-implemented): pairs of material
vertices mirrored across the sheet diagonal u = v (the crane's symmetry plane)
whose CLOSED-crane position lies within 0.1 of (x, y) = (1.0, 0.4); median and
max separation. Wing-tip separation: |x(1,0) - x(0,1)|.
"""
import sys, os, json, glob
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np, mesh
G = os.path.join(os.path.dirname(__file__), '../../../gallery/whole-crane/')
closed = mesh.load_fold(G + 'before.fold')
U, Xc = closed['U'], closed['X']
key = {tuple(np.round(u, 6)): i for i, u in enumerate(U)}
pairs = []
for i, u in enumerate(U):
    j = key.get(tuple(np.round(u[::-1], 6)))
    if j is not None and u[0] > u[1] + 1e-9 and np.linalg.norm(Xc[i, :2] - np.array([1.0, 0.4])) < 0.1:
        pairs.append((i, j))
pairs = np.array(pairs)
def stats(X):
    s = np.linalg.norm(X[pairs[:, 0]] - X[pairs[:, 1]], axis=1)
    return dict(body_open_median=float(np.median(s)), body_open_max=float(s.max()),
                wing_tip_sep=float(np.linalg.norm(X[54] - X[2])), body_top_y=float(X[24, 1]),
                rim_ends_distance=float(np.linalg.norm(X[13] - X[35])))
out = {'pairs': len(pairs)}
for name in ['before', 'after', 'narrow', 'spread-0']:
    out[name + ' sketch'] = stats(mesh.load_fold(G + name + '.fold')['X'])
for run, targets in [('spread-0-all3d-kb0.001-L0-rel', (0.01, 0.001)), ('spread-0-all3d-kb0.0001-L0-rel', (0.01, 0.001)),
                     ('spread-0-all3d-kb0.001-L0', (0.01, 0.001)), ('spread-0-all3d-kb0.0001-L0-rel-anch', (0.01, 0.001)),
                     ('spread-0-all3d-kb0.0001-L0-rel-anchbody', (0.01, 0.001)),
                     ('narrow-all3d-kb0.001-L0', (0.01, 0.001)), ('after-all3d-kb1e-05-L0-rel', (0.01, 0.001))]:
    d = json.load(open(f'out/{run}/sweep.json'))
    for t in targets:
        hit = [r for r in d['rows'][1:] if r['max_principal_strain'] <= t]
        if not hit:
            continue
        r = hit[0]
        X = np.load(f"out/{run}/X_lam{r['lam']:.0e}.npy")
        out[f'{run} @{t:g}'] = dict(strain=r['max_principal_strain'], **stats(X))
for k, v in out.items():
    print(k, v if isinstance(v, int) else {a: round(b, 4) for a, b in v.items()})
json.dump(out, open('out/shape_stats.json', 'w'), indent=1)
