import os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))  # repository root
import json, math
from fold import *
d = json.load(open(os.path.join(ROOT, 'examples/crane.fold')))
V = d['vertices_coords']; E = d['edges_vertices']; A = d['edges_assignment']; F0 = d['faces_vertices']
ang = [{'M': -180, 'V': 180}.get(a, 0) for a in A]
print('assignments', {a: A.count(a) for a in set(A)})
def segdist(p, a, b):
    ax, ay = a; bx, by = b; px, py = p
    dx, dy = bx-ax, by-ay; L = dx*dx+dy*dy
    t = max(0, min(1, ((px-ax)*dx+(py-ay)*dy)/L))
    return math.hypot(ax+t*dx-px, ay+t*dy-py)
def inside(p, poly):
    x, y = p; c = False
    for i in range(len(poly)):
        x1, y1 = poly[i]; x2, y2 = poly[(i+1) % len(poly)]
        if (y1 > y) != (y2 > y) and x < x1 + (y-y1)*(x2-x1)/(y2-y1): c = not c
    return c
for p in [(0.5, 0.5), (0.02, 0.97)]:
    near = sorted((math.hypot(V[i][0]-p[0], V[i][1]-p[1]), i) for i in range(len(V)))[:3]
    ed = sorted((segdist(p, V[a], V[b]), i) for i, (a, b) in enumerate(E))[:3]
    fs = [i for i, f in enumerate(F0) if inside(p, [V[v] for v in f])]
    print('point', p, 'nearest vertices', [(round(dd, 6), i, V[i]) for dd, i in near], 'nearest edges', [(round(dd, 6), i, A[i]) for dd, i in ed], 'faces containing', fs)
print('face 0 ring', F0[0], [V[v] for v in F0[0]])
print('vertex 0', V[0], 'vertex 2', V[2])
F, T = fold(V, E, ang, F0, root=0)
pos = {}
for i, f in enumerate(F):
    for v in f:
        p = apply(T[i], V[v])
        if v in pos and max(abs(p[k]-pos[v][k]) for k in range(3)) > 1e-9: print('TORN', v)
        pos[v] = p
xs = [p[0] for p in pos.values()]; ys = [p[1] for p in pos.values()]; zs = [p[2] for p in pos.values()]
print('folded extent x', min(xs), max(xs), 'y', min(ys), max(ys), 'z', min(zs), max(zs))
print('tip v2 folded', r(pos[2], 9), 'v0 folded', r(pos[0], 9))
for fid in [2, 3, 6, 7]:
    poly = [pos[v] for v in F[fid]]
    print('face', fid, 'material', [V[v] for v in F[fid]], 'folded', [r(q, 4)[:2] for q in poly], 'normal z', round(normalz(T[fid]), 3))
    # clip y=0.25 in folded, map back
    pts = []
    n = len(poly)
    for k in range(n):
        p1, p2 = poly[k], poly[(k+1) % n]
        m1, m2 = V[F[fid][k]], V[F[fid][(k+1) % n]]
        if (p1[1]-0.25)*(p2[1]-0.25) < 0 or abs(p1[1]-0.25) < 1e-12:
            t = 0 if abs(p1[1]-0.25) < 1e-12 else (0.25-p1[1])/(p2[1]-p1[1])
            pts.append((round(m1[0]+t*(m2[0]-m1[0]), 6), round(m1[1]+t*(m2[1]-m1[1]), 6)))
    print('    material wing-crease segment', sorted(set(pts)))
    cen = [sum(V[v][0] for v in F[fid])/len(F[fid]), sum(V[v][1] for v in F[fid])/len(F[fid])]
    print('    seed (0.02,0.97) in this face:', inside((0.02, 0.97), [V[v] for v in F[fid]]), ' seed folded', r(apply(T[fid], (0.02, 0.97)), 4) if inside((0.02, 0.97), [V[v] for v in F[fid]]) else '')
print('tail faces (contain v0):', [i for i, f in enumerate(F) if 0 in f])
for fid in [i for i, f in enumerate(F) if 0 in f] + [27, 65, 29, 66]:
    poly = [V[v] for v in F[fid]]
    cen = (sum(p[0] for p in poly)/len(poly), sum(p[1] for p in poly)/len(poly))
    md = min(segdist(cen, V[F[fid][k]], V[F[fid][(k+1) % len(F[fid])]]) for k in range(len(F[fid])))
    print('  face', fid, 'material centroid', (round(cen[0], 5), round(cen[1], 5)), 'min dist to own ring', round(md, 5), 'folded centroid', r(apply(T[fid], cen), 4), 'normal z', round(normalz(T[fid]), 2))
