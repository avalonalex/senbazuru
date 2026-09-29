"""Step 1b: a TORN ("stitched garment") start for the flat closed crane.

The study mesh is split into its 52 flat pieces (faces connected across
non-fold edges). Every vertex on a fold therefore has one copy per piece
that uses it. Each piece is lifted rigidly to height h_P * t, with h_P from
an LP: pieces whose faces overlap (faceOrders) or touch must differ by >= 1
in the right direction; minimise sum over fold edges of L0 * |h_a - h_b|
so that copies to be stitched start close. Rigid lifting costs zero strain;
the price is a gap between copies of the same material point (the "weld
gap"), which the stitch phase then tries to close.

Writes torn.npz with: V (torn positions), T (torn faces), mat (material
vertex id of each torn vertex), piece, welds (pairs of copies), and the
hinge lists used by the simulator.
"""
import sys, collections, json
import numpy as np
from shapely.geometry import Polygon
from shapely.strtree import STRtree
from scipy.optimize import linprog
import scipy.sparse as sp
from crane import *


def build(t=1e-3, out='torn', D=None):
    if D is None:
        D = load('before')
    X, F, M, Ev, A, fo = D['X'], D['F'], D['M'], D['E'], D['A'], D['fo']
    nv, nf = len(X), len(F)
    ef = edge_faces(F, nv)
    asg = {}
    for i, (a, b) in enumerate(Ev):
        asg[(min(a, b), max(a, b))] = A[i]
    # pieces
    par = list(range(nf))

    def find(a):
        while par[a] != a:
            par[a] = par[par[a]]; a = par[a]
        return a
    for key, fs in ef.items():
        if len(fs) == 2 and asg[key] not in 'MV':
            par[find(fs[0])] = find(fs[1])
    _, piece = np.unique([find(i) for i in range(nf)], return_inverse=True)
    npc = piece.max() + 1
    sz = np.sign(np.cross(X[F[:, 1]] - X[F[:, 0]], X[F[:, 2]] - X[F[:, 0]])[:, 2])
    order = set()
    for f, g, s in fo:
        u = f if s * sz[g] > 0 else g
        l = g if u == f else f
        order.add((piece[l], piece[u]))
    # topological rank of pieces for orienting touching pairs
    succ = collections.defaultdict(set)
    for l, u in order:
        succ[l].add(u)
    indeg = np.zeros(npc, int)
    for l, u in order:
        indeg[u] += 1
    q = [i for i in range(npc) if indeg[i] == 0]; rank = np.zeros(npc, int); k = 0
    while q:
        a = q.pop(0); rank[a] = k; k += 1
        for b in succ[a]:
            indeg[b] -= 1
            if indeg[b] == 0:
                q.append(b)
    assert k == npc
    polys = [Polygon(X[f, :2]) for f in F]
    tree = STRtree(polys)
    touch = set()
    for i in range(nf):
        for j in tree.query(polys[i], predicate='dwithin', distance=1e-9):
            if j <= i or piece[i] == piece[j]:
                continue
            if set(F[i]) & set(F[j]):
                continue
            if polys[i].distance(polys[j]) < 1e-9:
                a, b = piece[i], piece[j]
                touch.add((a, b) if rank[a] < rank[b] else (b, a))
    cons = order | touch
    # LP: vars h (npc) + u per fold edge
    folds = [(key, fs) for key, fs in ef.items() if len(fs) == 2 and asg[key] in 'MV']
    nfold = len(folds)
    rows, cols, vals, rhs = [], [], [], []
    r = 0
    for l, u in cons:            # h_l - h_u <= -1
        rows += [r, r]; cols += [l, u]; vals += [1, -1]; rhs.append(-1); r += 1
    w = []
    for k2, (key, fs) in enumerate(folds):
        a, b = piece[fs[0]], piece[fs[1]]
        for sg in (1, -1):
            rows += [r, r, r]; cols += [a, b, npc + k2]; vals += [sg, -sg, -1]; rhs.append(0); r += 1
        w.append(np.linalg.norm(M[key[0]] - M[key[1]]))
    Aub = sp.coo_matrix((vals, (rows, cols)), shape=(r, npc + nfold)).tocsr()
    c = np.r_[np.zeros(npc), w]
    bounds = [(0, None)] * npc + [(0, None)] * nfold
    res = linprog(c, A_ub=Aub, b_ub=rhs, bounds=bounds, method='highs')
    assert res.status == 0, res.message
    h = np.round(res.x[:npc], 9)
    print(f'pieces {npc}, ordered piece pairs {len(order)}, touching-only pairs {len(touch - order)}, '
          f'height levels 0..{h.max():.0f}, LP objective {res.fun:.3f}')
    # torn mesh
    V, mat, pc = [], [], []
    T = np.zeros_like(F)
    copy = {}
    for f in range(nf):
        for k2, v in enumerate(F[f]):
            key = (v, piece[f])
            if key not in copy:
                copy[key] = len(V)
                p = X[v].copy(); p[2] = h[piece[f]] * t
                V.append(p); mat.append(v); pc.append(piece[f])
            T[f, k2] = copy[key]
    V = np.array(V); mat = np.array(mat); pc = np.array(pc)
    welds = []
    bym = collections.defaultdict(list)
    for i, m in enumerate(mat):
        bym[m].append(i)
    for m, lst in bym.items():
        # chain copies: weld every copy to the first (star) -- all pairs for small groups
        for i in range(len(lst)):
            for j in range(i + 1, len(lst)):
                welds.append((lst[i], lst[j]))
    welds = np.array(welds, int).reshape(-1, 2)
    # hinges on the torn mesh: (x1, x2 = hinge in face A, x3 = opposite in A, x4 = opposite in B), kind
    hinges = []
    for key, fs in ef.items():
        if len(fs) != 2:
            continue
        fa, fb = fs
        a, b = key
        # orient so that (a,b) appears in fa's winding order a->b
        la = list(F[fa]); ia = la.index(a)
        if la[(ia + 1) % 3] != b:
            a, b = b, a
        c3 = [v for v in F[fa] if v not in (a, b)][0]
        c4 = [v for v in F[fb] if v not in (a, b)][0]
        ta = {F[fa][k2]: T[fa][k2] for k2 in range(3)}
        tb = {F[fb][k2]: T[fb][k2] for k2 in range(3)}
        kind = asg[key]
        hinges.append((ta[a], ta[b], ta[c3], tb[c4], tb[a], tb[b], 1 if kind in 'MV' else 0, a, b))
    hinges = np.array(hinges, int)
    # rest dihedral of each hinge, from the flat folded state (material ids)
    np.savez(f'{EXP}/{out}.npz', V=V, T=T, mat=mat, piece=pc, welds=welds, hinges=hinges,
             h=h, t=t, M=M, X=X, F=F, Ev=Ev)
    gaps = np.linalg.norm(V[welds[:, 0]] - V[welds[:, 1]], axis=1)
    print(f'torn vertices {len(V)} (material {nv}), welds {len(welds)}, weld gap max {gaps.max():.4e} '
          f'= {gaps.max()/t:.0f} t, mean {gaps.mean():.4e}')
    return V, T, mat


if __name__ == '__main__':
    t = float(sys.argv[1]) if len(sys.argv) > 1 else 1e-3
    D = None
    if len(sys.argv) > 3:            # a refined frame from refine.py
        r = json.load(open(sys.argv[3]))
        D = dict(X=np.array(r['X']), F=np.array(r['F']), M=np.array(r['M']), E=np.array(r['E']),
                 A=r['A'], fo=np.array(r['fo']).reshape(-1, 3))
    build(t, sys.argv[2] if len(sys.argv) > 2 else 'torn', D)
