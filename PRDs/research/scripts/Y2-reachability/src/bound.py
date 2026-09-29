"""Solver-free lower bound on how far a pose must move to become paper.

Paper can bend, crease and crumple but not stretch, and the flat sheet is a
convex square, so in ANY paper state two material points are at most as far
apart in space as they are on the flat sheet: |x_i - x_j| <= |u_i - u_j|.
A pose with |x*_i - x*_j| = |u_i - u_j| + e therefore needs |d_i| + |d_j| >= e,
so some point moves at least e/2. Orthographic projection cannot lengthen a
distance, so the same holds for the picture with |P x*_i - P x*_j|.
Compression gives no such bound: paper can bring points closer by folding.
"""
import sys, json
sys.path.insert(0, 'src')
import numpy as np, mesh
G = '../../gallery/whole-crane/'
res = {}
for name in sys.argv[1:] or ['spread-0', 'after', 'narrow', 'before']:
    m = mesh.load_fold(G + name + '.fold')
    for lev in (0, 1, 2):
        if lev:
            m = mesh.subdivide(m)
        X, U = m['X'], m['U']
        P, _ = mesh.project(X)
        n = len(X)
        best3 = (0, None); best2 = (0, None)
        cnt3 = 0
        for s in range(0, n, 400):
            i = np.arange(s, min(n, s + 400))
            du = np.linalg.norm(U[i, None, :] - U[None, :, :], axis=2)
            d3 = np.linalg.norm(X[i, None, :] - X[None, :, :], axis=2) - du
            d2 = np.linalg.norm(P[i, None, :] - P[None, :, :], axis=2) - du
            cnt3 += int((d3 > 5 / 600 * 2).sum())
            k = np.unravel_index(np.argmax(d3), d3.shape)
            if d3[k] > best3[0]: best3 = (d3[k], (int(i[k[0]]), int(k[1])))
            k = np.unravel_index(np.argmax(d2), d2.shape)
            if d2[k] > best2[0]: best2 = (d2[k], (int(i[k[0]]), int(k[1])))
        r = dict(points=n, max_excess_3d=best3[0], pair3d=best3[1], move_lb_3d_px=300 * best3[0],
                 max_excess_picture=best2[0], pair_picture=best2[1], move_lb_picture_px=300 * best2[0],
                 ordered_pairs_needing_over_5px=cnt3)
        res[f'{name}-L{lev}'] = r
        print(name, lev, json.dumps(r))
json.dump(res, open('out/bound.json', 'w'), indent=1)
