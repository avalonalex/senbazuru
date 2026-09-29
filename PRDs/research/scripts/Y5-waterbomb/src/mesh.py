"""Build a cut-and-sew cloth mesh of a flat-folded FOLD state (Y5).

usage: mesh.py FOLDED.fold CP.fold OUT.npz [n=6] [gap=0.01] [scale=10]

Each face of the folded state becomes its own flat piece (faces joined by a
flat 'F' crease stay one piece), lifted to a height from the layer order:
level(f) = 1 + max level of the faces it lies above (overlapping ones only),
so a stack of k layers gets k levels. Every piece is subdivided into a
triangle grid (each triangle of the face cut into n^2). Across every folded
crease the two copies of each grid point are joined by a zero-length sewing
spring (a loose edge), which the cloth solver pulls shut.

Triangles are wound so that their normal is the paper's BOTTOM side: cavity.py
showed that the air touching the top side is the inside of the balloon, so
a positive pressure along these normals inflates it.
Material (crease-pattern) coordinates are kept for every vertex.
"""
import json
import sys

import numpy as np

args = [a for a in sys.argv[1:] if "=" not in a]
opt = dict(n=6, gap=0.01, scale=10.0)
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
E = fo["edges_vertices"]
A = fo["edges_assignment"]
nf = len(F)


def sarea(P):
    P = np.asarray(P)
    return 0.5 * np.sum(P[:, 0] * np.roll(P[:, 1], -1) - np.roll(P[:, 0], -1) * P[:, 1])


# ---- layer levels from faceOrders (f above g in +z)
above = {}
for (f, g, s) in fo["faceOrders"]:
    nz = 1 if sarea(X[F[g]]) > 0 else -1
    up = (s > 0) == (nz > 0)
    a, b = (f, g) if up else (g, f)
    above.setdefault(a, set()).add(b)  # a lies above b
level = {}


def lev(f, stack=()):
    if f in level:
        return level[f]
    below = above.get(f, set())
    level[f] = 0 if not below else 1 + max(lev(g) for g in below)
    return level[f]


for f in range(nf):
    lev(f)

# ---- pieces: faces joined by flat creases
edge_faces = {}
for fi, f in enumerate(F):
    for k in range(len(f)):
        a, b = f[k], f[(k + 1) % len(f)]
        edge_faces.setdefault((min(a, b), max(a, b)), []).append(fi)
asg = {(min(a, b), max(a, b)): A[i] for i, (a, b) in enumerate(E)}
parent = list(range(nf))


def find(i):
    while parent[i] != i:
        parent[i] = parent[parent[i]]
        i = parent[i]
    return i


for e, fs in edge_faces.items():
    if len(fs) == 2 and asg[e] == "F":
        assert level[fs[0]] == level[fs[1]], "flat crease across two heights"
        parent[find(fs[0])] = find(fs[1])
piece = [find(i) for i in range(nf)]

# ---- subdivide
n = opt["n"]
verts = []      # 3D position
mat = []        # material coords
pid = []        # piece id
vidx = {}       # (piece, rounded material coord) -> vertex id
tris = []
tri_face = []


def vid(p, m, pos):
    key = (p, round(m[0] * 1e7), round(m[1] * 1e7))
    if key not in vidx:
        vidx[key] = len(verts)
        verts.append(pos)
        mat.append(m)
        pid.append(p)
    return vidx[key]


for fi, f in enumerate(F):
    z = level[fi] * opt["gap"]
    # orientation: does the folded map keep the crease pattern's winding?
    keep = (sarea(C[f]) > 0) == (sarea(X[f]) > 0)
    # CP winding made anticlockwise; then the top side's normal in the folded
    # state is +z if keep else -z.
    ring = list(f) if sarea(C[f]) > 0 else list(f)[::-1]
    for k in range(1, len(ring) - 1):
        a, b, c = ring[0], ring[k], ring[k + 1]
        grid = {}
        for i in range(n + 1):
            for j in range(n + 1 - i):
                w = np.array([n - i - j, i, j], float) / n
                m = w @ C[[a, b, c]]
                x = w @ X[[a, b, c]]
                grid[(i, j)] = vid(piece[fi], m, [x[0], x[1], z])
        for i in range(n):
            for j in range(n - i):
                t1 = (grid[(i, j)], grid[(i + 1, j)], grid[(i, j + 1)])
                tris.append(t1)
                tri_face.append(fi)
                if i + j < n - 1:
                    t2 = (grid[(i + 1, j)], grid[(i + 1, j + 1)], grid[(i, j + 1)])
                    tris.append(t2)
                    tri_face.append(fi)
    # these triangles are anticlockwise in material coords = top side.
    # We want normals on the bottom side: reverse them below.

T = np.array(tris)[:, ::-1]  # bottom side outward
V = np.array(verts) * opt["scale"]
M = np.array(mat)
P = np.array(pid)

# ---- sewing: copies of the same material point in different pieces, along
# folded creases (M or V)
sew = set()
bykey = {}
for (p, mx, my), v in vidx.items():
    bykey.setdefault((mx, my), []).append(v)
for e, fs in edge_faces.items():
    if len(fs) != 2 or asg[e] not in ("M", "V"):
        continue
    f1, f2 = fs
    a, b = e
    for i in range(n + 1):
        m = (C[a] * (n - i) + C[b] * i) / n
        key = (round(m[0] * 1e7), round(m[1] * 1e7))
        v1 = vidx[(piece[f1], key[0], key[1])]
        v2 = vidx[(piece[f2], key[0], key[1])]
        sew.add((min(v1, v2), max(v1, v2)))
S = np.array(sorted(sew))
lv = np.array([level[f] for f in range(nf)])
np.savez(out, V=V, T=T, M=M, P=P, S=S, tri_face=np.array(tri_face), level=lv,
         opt=json.dumps(opt))
print(json.dumps(dict(vertices=len(V), triangles=len(T), sewing=len(S), pieces=len(set(piece)),
                      levels=int(lv.max()) + 1, thickness=float((lv.max()) * opt["gap"] * opt["scale"]),
                      max_sew_len=float(np.linalg.norm(V[S[:, 0]] - V[S[:, 1]], axis=1).max()))))
