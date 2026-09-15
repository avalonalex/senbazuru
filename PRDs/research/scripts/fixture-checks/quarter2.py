import os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))  # repository root
import json
from fold import *
d = json.load(open(os.path.join(ROOT, 'examples/quarter-fold-steps.fold')))
V = d['vertices_coords']; E = d['edges_vertices']; F0 = d['faces_vertices']
names = ['F0 br', 'F1 tr', 'F2 tl', 'F3 bl']
for probe in (179.0, 170.0, 90.0):
    a = [0]*8 + [-180, probe, -180, -probe]   # step 1 exact, step 2 partway with the fixture's signs
    for root in (0, 3):
        F, T = fold(V, E, a, F0, root=root)
        out = []
        for i in range(4):
            c = [sum(V[v][0] for v in F[i])/4, sum(V[v][1] for v in F[i])/4]
            out.append((names[i], r(apply(T[i], c), 4), round(normalz(T[i]), 3)))
        print('probe', probe, 'root', names[root], out)
