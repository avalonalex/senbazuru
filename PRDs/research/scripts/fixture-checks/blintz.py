import os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))  # repository root
import json, math
from fold import *
d = json.load(open(os.path.join(ROOT, 'examples/blintz-base.fold')))
V = d['vertices_coords']; E = d['edges_vertices']
print('vertices', V)
print('centre (0.5,0.5) is a vertex:', [0.5, 0.5] in V, ' nearest vertex distance', min(math.hypot(x-0.5, y-0.5) for x, y in V))
F = [[4, 5, 6, 7], [0, 4, 7], [4, 1, 5], [5, 2, 6], [6, 3, 7]]  # recipe order: centre, then the traced corner faces as BlintzSequenceSpec maps them (edge 8->face2, 9->3, 10->4, 11->1)
for eid, fid in [(8, 2), (9, 3), (10, 4), (11, 1)]:
    a, b = E[eid]
    print('edge', eid, (V[a], V[b]), 'shared with face', fid, F[fid], 'corner', [V[v] for v in F[fid] if v not in (a, b)])
# O2 perpendicular bisector of corner and centre
for corner, eid in [((1, 0), 8), ((1, 1), 9), ((0, 1), 10), ((0, 0), 11)]:
    mx, my = (corner[0]+0.5)/2, (corner[1]+0.5)/2
    nx, ny = corner[0]-0.5, corner[1]-0.5  # normal of fold line
    a, b = E[eid]
    on = [abs((V[v][0]-mx)*nx + (V[v][1]-my)*ny) < 1e-12 for v in (a, b)]
    print('O2 corner', corner, 'to centre: line', f'{nx}*(x-{mx})+{ny}*(y-{my})=0', 'contains both ends of edge', eid, on)
angles = [0]*12
for step, (eid, trav) in enumerate([(8, -180), (9, -180), (10, -180), (11, -180), (8, 180)]):
    angles[eid] += trav
    probe = [0 if x == 0 else (179 if x > 0 else -179) for x in angles]
    Fo, T = fold(V, E, probe, F, root=0)
    zs = []
    for i in range(1, 5):
        c = [sum(V[v][0] for v in Fo[i])/3, sum(V[v][1] for v in Fo[i])/3]
        zs.append(round(apply(T[i], c)[2], 3))
    print('after move', step+1, 'angles 8-11', angles[8:], 'corner-face centroid z (faces1..4, probe 179)', zs)
