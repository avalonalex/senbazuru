"""Ingredient 4: one level of refinement of the body core.

Every edge of the 64 core triangles gets its midpoint; core triangles split
1 -> 4, and the non-core triangles on the core's rim are bisected from the
new midpoint (one split edge) so the mesh stays conforming. Halves of an old
edge keep its assignment (so a fold stays a fold); edges new inside an old
triangle are flat ('J'). Closed-crane positions and material coordinates of
a midpoint are the averages of its ends (the closed crane is flat, so the
midpoint lies on both faces). faceOrders are inherited: a child pair gets its
parents' order when the children overlap in the closed crane.

Writes out/refined.json (the refined frame, same keys as crane.load) and
out/regions-refined.json; the original 237 vertex ids are kept, new ones
are appended.
"""
import json, collections
import numpy as np
from shapely.geometry import Polygon
from crane import load, EXP

D = load('before')
X, F, M, Ev, A, fo = D['X'], D['F'], D['M'], D['E'], D['A'], D['fo']
reg = json.load(open(f'{EXP}/out/regions.json'))
core = set(reg['core_tris'])
asg = {(min(a, b), max(a, b)): A[i] for i, (a, b) in enumerate(Ev)}
split = set()
for fi in core:
    a, b, c = F[fi]
    for u, v in ((a, b), (b, c), (c, a)):
        split.add((min(u, v), max(u, v)))
Xn, Mn = [p for p in X], [m for m in M]
mid = {}
for key in sorted(split):
    mid[key] = len(Xn)
    Xn.append((X[key[0]] + X[key[1]]) / 2)
    Mn.append((M[key[0]] + M[key[1]]) / 2)
Xn, Mn = np.array(Xn), np.array(Mn)
newF, parent, newE = [], [], {}


def edge(u, v, kind):
    newE[(min(u, v), max(u, v))] = kind


def old_edge(u, v, m=None):
    k = asg[(min(u, v), max(u, v))]
    if m is None:
        edge(u, v, k)
    else:
        edge(u, m, k); edge(m, v, k)


counts = collections.Counter()
for fi, (a, b, c) in enumerate(F):
    ms = [mid.get((min(u, v), max(u, v))) for u, v in ((a, b), (b, c), (c, a))]
    k = sum(m is not None for m in ms)
    counts[(fi in core, k)] += 1
    for (u, v), m in zip(((a, b), (b, c), (c, a)), ms):
        old_edge(u, v, m)
    if k == 0:
        newF.append((a, b, c)); parent.append(fi)
    elif k == 3:
        mab, mbc, mca = ms
        for t in ((a, mab, mca), (mab, b, mbc), (mca, mbc, c), (mab, mbc, mca)):
            newF.append(t); parent.append(fi)
        edge(mab, mbc, 'J'); edge(mbc, mca, 'J'); edge(mca, mab, 'J')
    elif k == 1:
        # rotate so the split edge is (p, q) with opposite r, keeping the winding
        tri = [a, b, c]
        j = [i for i in range(3) if ms[i] is not None][0]
        p, q, r = tri[j], tri[(j + 1) % 3], tri[(j + 2) % 3]
        m = ms[j]
        newF.append((p, m, r)); parent.append(fi)
        newF.append((m, q, r)); parent.append(fi)
        edge(m, r, 'J')
    else:
        raise SystemExit(f'triangle {fi} has {k} split edges; not handled')
print('split-edge counts (core?, k):', dict(counts))
newF = np.array(newF)
parent = np.array(parent)
# inherit faceOrders
children = collections.defaultdict(list)
for i, pf in enumerate(parent):
    children[pf].append(i)
polys = [Polygon(Xn[f, :2]) for f in newF]
newfo = []
for f, g, s in fo:
    for cf in children[f]:
        for cg in children[g]:
            if polys[cf].intersection(polys[cg]).area > 1e-12:
                newfo.append((cf, cg, int(s)))
Evn = np.array(sorted(newE.keys()))
An = [newE[tuple(e)] for e in Evn]
core_new = [i for i, pf in enumerate(parent) if pf in core]
# core boundary loop
cnt = collections.Counter()
for i in core_new:
    a, b, c = newF[i]
    for u, v in ((a, b), (b, c), (c, a)):
        cnt[(u, v)] += 1
bd = [(u, v) for (u, v) in cnt if (v, u) not in cnt]
nxt = {u: v for u, v in bd}
loop = [bd[0][0]]
while nxt[loop[-1]] != loop[0]:
    loop.append(nxt[loop[-1]])
assert len(loop) == len(bd)
print(f'refined: {len(Xn)} vertices, {len(newF)} triangles, {len(Evn)} edges, {len(newfo)} faceOrders '
      f'(from {len(fo)}), core triangles {len(core_new)}, core rim {len(loop)} edges')
json.dump(dict(X=Xn.tolist(), F=newF.tolist(), M=Mn.tolist(), E=Evn.tolist(), A=An, fo=newfo, parent=parent.tolist(),
               mid={f'{k[0]},{k[1]}': v for k, v in mid.items()}),
          open(f'{EXP}/out/refined.json', 'w'))
json.dump(dict(core=reg['core'], core_tris=core_new, core_loop=[int(x) for x in loop]),
          open(f'{EXP}/out/regions-refined.json', 'w'))
