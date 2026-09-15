import os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))  # repository root
import json
from fold import *
d = json.load(open(os.path.join(ROOT, 'examples/quarter-fold-steps.fold')))
V = d['vertices_coords']; E = d['edges_vertices']; F0 = d['faces_vertices']
names = ['F0 [8,4,1,5] br', 'F1 [8,5,2,6] tr', 'F2 [8,6,3,7] tl', 'F3 [8,7,0,4] bl']
for fr in (1, 2):
    angs = d['file_frames'][fr-1]['edges_foldAngle']
    a = [0 if x == 0 else (179.0 if x > 0 else -179.0) for x in angs]
    F, T = fold(V, E, a, F0, root=0)
    print('frame', fr, 'angles 8-11', angs[8:], '(probe +-179, root F0)')
    for i in range(4):
        c = [sum(V[v][0] for v in F[i])/4, sum(V[v][1] for v in F[i])/4]
        print('   ', names[i], 'material centroid', c, '-> placed', r(apply(T[i], c)), 'normal z', round(normalz(T[i]), 3))
    F, T = fold(V, E, angs, F0, root=0)
    pos = {}
    for i, f in enumerate(F):
        for v in f: pos[v] = apply(T[i], V[v])
    target = d['file_frames'][fr-1]['vertices_coords']
    print('    exact angles reproduce file coords:', all(abs(pos[v][0]-target[v][0]) < 1e-9 and abs(pos[v][1]-target[v][1]) < 1e-9 for v in range(9)))
# anchor (1/4,1/4) which face
print('anchor (1/4,1/4) is in F3 bottom-left: material [0,.5]x[0,.5]')
# current positions of top edge (v2-v6, v6-v3) and bottom edge (v0-v4, v4-v1) in frame 1
f1 = d['file_frames'][0]['vertices_coords']
print('frame1 top edge segments', [(f1[a], f1[b]) for a, b in [(2, 6), (6, 3)]], 'bottom', [(f1[a], f1[b]) for a, b in [(0, 4), (4, 1)]])
print('frame1 left edge', [(f1[a], f1[b]) for a, b in [(3, 7), (7, 0)]], 'right', [(f1[a], f1[b]) for a, b in [(1, 5), (5, 2)]])
