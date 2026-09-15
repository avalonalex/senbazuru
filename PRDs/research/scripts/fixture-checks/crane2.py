import os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))  # repository root
import json, math
from fractions import Fraction as Fr
d = json.load(open(os.path.join(ROOT, 'examples/crane.fold')))
V = d['vertices_coords']; E = d['edges_vertices']; A = d['edges_assignment']; F = d['faces_vertices']
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
cands = {'anchor face0': (0.95, 1/3), 'tail face10': (0.25, 0.2), 'body27 below': (3/8, 5/9), 'body65 below': (0.3, 0.39), 'body29 above': (4/9, 3/8), 'body66 above': (0.49, 0.065), 'spine anchor': (0.5, 0.5), 'seed': (0.02, 0.97)}
for name, p in cands.items():
    faces = [i for i, f in enumerate(F) if inside(p, [V[v] for v in f])]
    md = min(segdist(p, V[a], V[b]) for a, b in E)
    nv = min(math.hypot(V[i][0]-p[0], V[i][1]-p[1]) for i in range(len(V)))
    print(f'{name:14s} {p} faces {faces} min edge distance {md:.5f} nearest vertex {nv:.2e}')
