"""One-piece (welded) thick start of a flat-folded FOLD state (Y5).

usage: mesh_welded.py FOLDED.fold CP.fold OUT.npz [n=6] [gap=0.001] [scale=10]

Same triangle grid and layer levels as mesh.py, but one vertex per material
point. A face's interior grid points sit at its level; a point on a crease
between faces at levels l1 and l2 sits at the mean height and is pushed
outwards in the plane (away from both faces) by |l1-l2|*gap/2, so nested folds
become nested U-wraps. A point where several faces meet (a pattern vertex)
takes the mean height of its faces and no push: the one place this start can
intersect itself. Vertex group weight 1 marks crease points (for crease
bending stiffness), 0 panel points.
"""
import json
import sys

import numpy as np

args = [a for a in sys.argv[1:] if "=" not in a]
opt = dict(n=6, gap=0.001, scale=10.0)
for a in sys.argv[1:]:
    if "=" in a:
        k, v = a.split("=")
        opt[k] = type(opt[k])(v)
fo = json.load(open(args[0]))
cp = json.load(open(args[1]))
out = args[2]
X = np.array(fo["vertices_coords"], float)[:, :2]
C = np.array(cp["vertices_coords"], float)
F = fo["faces_vertices"]
nf = len(F)


def sarea(P):
    P = np.asarray(P)
    return 0.5 * np.sum(P[:, 0] * np.roll(P[:, 1], -1) - np.roll(P[:, 0], -1) * P[:, 1])


above = {}
for (f, g, s) in fo["faceOrders"]:
    nz = 1 if sarea(X[F[g]]) > 0 else -1
    up = (s > 0) == (nz > 0)
    a, b = (f, g) if up else (g, f)
    above.setdefault(a, set()).add(b)
level = {}


def lev(f):
    if f not in level:
        below = above.get(f, set())
        level[f] = 0 if not below else 1 + max(lev(g) for g in below)
    return level[f]


for f in range(nf):
    lev(f)

n, gap = opt["n"], opt["gap"]
key2v, pos_acc, mat, faces_of = {}, [], [], []
tris = []


def vid(m):
    key = (round(m[0] * 1e7), round(m[1] * 1e7))
    if key not in key2v:
        key2v[key] = len(mat)
        mat.append(m)
        pos_acc.append([])
        faces_of.append(set())
    return key2v[key]


xy = {}
for fi, f in enumerate(F):
    ring = list(f) if sarea(C[f]) > 0 else list(f)[::-1]
    cen = X[f].mean(0)
    for k in range(1, len(ring) - 1):
        a, b, c = ring[0], ring[k], ring[k + 1]
        grid = {}
        for i in range(n + 1):
            for j in range(n + 1 - i):
                w = np.array([n - i - j, i, j], float) / n
                m = w @ C[[a, b, c]]
                x = w @ X[[a, b, c]]
                v = vid(m)
                xy[v] = x
                pos_acc[v].append((fi, level[fi], cen))
                faces_of[v].add(fi)
                grid[(i, j)] = v
        for i in range(n):
            for j in range(n - i):
                tris.append((grid[(i, j)], grid[(i + 1, j)], grid[(i, j + 1)]))
                if i + j < n - 1:
                    tris.append((grid[(i + 1, j)], grid[(i + 1, j + 1)], grid[(i, j + 1)]))

nv = len(mat)
V = np.zeros((nv, 3))
crease = np.zeros(nv)
for v in range(nv):
    fs = {}
    for fi, l, cen in pos_acc[v]:
        fs[fi] = (l, cen)
    ls = [l for l, _ in fs.values()]
    x = np.array(xy[v], float)
    z = np.mean(ls) * gap
    if len(fs) == 2 and max(ls) != min(ls):
        crease[v] = 1.0
        # outward: away from both faces' centroids, perpendicular-ish
        (l1, c1), (l2, c2) = fs.values()
        d = x - (c1 + c2) / 2
        d = d / (np.linalg.norm(d) + 1e-12)
        x = x + d * abs(l1 - l2) * gap / 2
    elif len(fs) > 2:
        crease[v] = 1.0
    V[v] = [x[0], x[1], z]
T = np.array(tris)[:, ::-1]  # normals on the paper's bottom side (outwards)
V *= opt["scale"]
np.savez(out, V=V, T=T, M=np.array(mat), P=np.zeros(nv, int), S=np.zeros((0, 2), int),
         crease=crease, opt=json.dumps(opt))
print(json.dumps(dict(vertices=nv, triangles=len(T), crease_vertices=int(crease.sum()),
                      levels=max(level.values()) + 1)))
