"""Step 1: build an intersection-free thick start from the flat closed crane.

Method (own construction):
  * the closed crane is flat (all z ~ 1e-17); faceOrders give, for every pair
    of overlapping triangles, which one is higher in world z;
  * nested folds: a 180-degree crease that wraps other layers touching its
    line cannot be separated by moving z alone (the two faces meet at the
    crease, the wrapped layer sits between them at the same xy). So every
    vertex on such a crease is first shifted OUTWARD in xy by
    (number of wrapped layers) * delta;
  * then per-vertex z is chosen by a linear program: for every pair of
    faces whose (shifted) footprints meet, the upper face must be at least
    t above the lower at every corner of their footprint intersection,
    except at a vertex the two faces share (there the gap is 0 by
    construction). Triangles are planar, so z-separation is linear over the
    convex intersection and corners suffice. Objective: minimise the sum of
    |dz| / rest length over edges (keep faces flat).

Usage: python build_start.py T DELTA_FACTOR OUTNAME
"""
import sys, time, json, collections
import numpy as np
from shapely.geometry import Polygon, LineString
from shapely.strtree import STRtree
import scipy.sparse as sp
from scipy.optimize import linprog
from crane import *

t = float(sys.argv[1]) if len(sys.argv) > 1 else 1e-3
dfac = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
out = sys.argv[3] if len(sys.argv) > 3 else 'start'
delta = dfac * t

D = load('before')
X, F, M, Ev, A, fo = D['X'], D['F'], D['M'], D['E'], D['A'], D['fo']
nv, nf = len(X), len(F)
ef = edge_faces(F, nv)
sz = np.sign(np.cross(X[F[:, 1]] - X[F[:, 0]], X[F[:, 2]] - X[F[:, 0]])[:, 2])

# ---- world-z order of overlapping pairs (FOLD: sign read against g's normal)
upper = {}
for f, g, s in fo:
    upper[(min(f, g), max(f, g))] = f if s * sz[g] > 0 else g

# ---- a total level order (longest path) for pairs that only touch
succ = collections.defaultdict(set)
for (a, b), u in upper.items():
    lo = b if u == a else a
    succ[lo].add(u)
indeg = np.zeros(nf, int)
for g in range(nf):
    for f in succ[g]:
        indeg[f] += 1
lvl = np.zeros(nf, int); q = [i for i in range(nf) if indeg[i] == 0]; topo = []
while q:
    g = q.pop(0); topo.append(g)
    for f in succ[g]:
        lvl[f] = max(lvl[f], lvl[g] + 1); indeg[f] -= 1
        if indeg[f] == 0:
            q.append(f)
assert len(topo) == nf
rank = np.empty(nf, int); rank[topo] = np.arange(nf)


def is_above(a, b):
    k = (min(a, b), max(a, b))
    if k in upper:
        return upper[k] == a
    return (lvl[a], rank[a]) > (lvl[b], rank[b])


# ---- nesting depth of each fold edge and outward shift
polys0 = [Polygon(X[f, :2]) for f in F]
depth = {}
outward = {}
for i, (a, b) in enumerate(Ev):
    if A[i] not in 'MV':
        continue
    f, g = ef[(min(a, b), max(a, b))]
    if not is_above(f, g):
        f, g = g, f
    seg = LineString(X[[a, b], :2])
    cnt = 0
    for h in range(nf):
        if h in (f, g):
            continue
        kf, kg = (min(f, h), max(f, h)), (min(g, h), max(g, h))
        if kf not in upper or kg not in upper or upper[kf] != f or upper[kg] != h:
            continue
        inter = polys0[h].intersection(seg)
        if inter.is_empty:
            continue
        if inter.length < 1e-9 and inter.geom_type == 'Point':
            p = np.array(inter.coords[0])
            shared = [v for v in F[h] if v in (a, b) and np.linalg.norm(X[v, :2] - p) < 1e-9]
            if shared:
                continue
        cnt += 1
    depth[i] = cnt
    e = X[b, :2] - X[a, :2]
    n = np.array([-e[1], e[0]]) / np.linalg.norm(e)
    c = [v for v in F[f] if v not in (a, b)][0]
    if np.dot(X[c, :2] - X[a, :2], n) > 0:
        n = -n
    outward[i] = n

rows = collections.defaultdict(list)
for i, dpt in depth.items():
    if dpt > 0:
        for v in Ev[i]:
            rows[v].append((outward[i], dpt * delta))
shift = np.zeros((nv, 2))
for v, lst in rows.items():
    N = np.array([r[0] for r in lst]); d = np.array([r[1] for r in lst])
    s, *_ = np.linalg.lstsq(N, d, rcond=None)
    cap = 3 * d.max()
    if np.linalg.norm(s) > cap:
        s *= cap / np.linalg.norm(s)
    shift[v] = s
Xs = X.copy(); Xs[:, :2] += shift
print(f'fold edges: {len(depth)}, nested (depth>0): {sum(1 for d in depth.values() if d)}, '
      f'max depth {max(depth.values())}, shifted vertices {len(rows)}, max shift {np.linalg.norm(shift,axis=1).max():.3e}')

# ---- pair constraints on shifted footprints
polys = [Polygon(Xs[f, :2]) for f in F]
tree = STRtree(polys)
Fset = [set(f) for f in F]


def bary(p, tri):
    a, b, c = tri
    T = np.c_[b - a, c - a]
    l = np.linalg.solve(T, p - a)
    return np.array([1 - l.sum(), l[0], l[1]])


r_i, r_j, r_v, rhs = [], [], [], []
ncon = 0; npairs = 0; meta = []
for fi in range(nf):
    for fj in tree.query(polys[fi]):
        if fj <= fi:
            continue
        inter = polys[fi].intersection(polys[fj])
        if inter.is_empty:
            continue
        sharedv = Fset[fi] & Fset[fj]
        if len(sharedv) == 2 and inter.area < 1e-14:
            continue  # neighbours across a flat edge
        if inter.area < 1e-14 and len(sharedv) == 1:
            continue  # meet only at the shared vertex
        up, lo = (fi, fj) if is_above(fi, fj) else (fj, fi)
        # corners of the intersection
        geoms = getattr(inter, 'geoms', [inter])
        pts = []
        for gm in geoms:
            if gm.geom_type == 'Polygon':
                pts += list(gm.exterior.coords)[:-1]
            else:
                pts += list(gm.coords)
        npairs += 1
        for p in pts:
            p = np.array(p)
            w = 1.0
            for v in sharedv:
                if np.linalg.norm(Xs[v, :2] - p) < 1e-10:
                    w = 0.0
            bu = bary(p, Xs[F[up], :2]); bl = bary(p, Xs[F[lo], :2])
            # z_up(p) - z_lo(p) >= w t   ->   -(bu.z_up) + bl.z_lo <= -w t
            coef = collections.defaultdict(float)
            for k in range(3):
                coef[F[up][k]] -= bu[k]
                coef[F[lo][k]] += bl[k]
            for v, cv in coef.items():
                if abs(cv) > 1e-15:
                    r_i.append(ncon); r_j.append(v); r_v.append(cv)
            rhs.append(-w * t)
            atv = [v for v in set(F[up]) | set(F[lo]) if np.linalg.norm(Xs[v, :2] - p) < 1e-10]
            meta.append((up, lo, w, len(sharedv), len(atv), (min(fi, fj), max(fi, fj)) in upper))
            ncon += 1
print(f'constrained pairs {npairs}, corner constraints {ncon}')

# objective: min sum |z_a - z_b| / L0 over edges  (aux u_e >= +-(z_a - z_b))
ne = len(Ev)
L0 = np.linalg.norm(M[Ev[:, 0]] - M[Ev[:, 1]], axis=1)
Ai = sp.coo_matrix((r_v, (r_i, r_j)), shape=(ncon, nv + ne))
rows2 = []; cols2 = []; vals2 = []
for e, (a, b) in enumerate(Ev):
    for sgn, base in ((1, 2 * e), (-1, 2 * e + 1)):
        rows2 += [base, base, base]; cols2 += [a, b, nv + e]; vals2 += [sgn, -sgn, -1]
Ae = sp.coo_matrix((vals2, (rows2, cols2)), shape=(2 * ne, nv + ne))
Aub = sp.vstack([Ai, Ae]).tocsr()
bub = np.r_[rhs, np.zeros(2 * ne)]
c = np.r_[np.zeros(nv), 1.0 / L0]
bounds = [(None, None)] * nv + [(0, None)] * ne
bounds[0] = (0, 0)
t0 = time.time()
res = linprog(c, A_ub=Aub, b_ub=bub, bounds=bounds, method='highs')
print('LP status', res.status, res.message, f'{time.time()-t0:.2f}s')
if res.status != 0:
    # find minimal slack
    Asl = sp.hstack([Aub, -sp.vstack([sp.eye(ncon), sp.coo_matrix((2 * ne, ncon))])]).tocsr()
    c2 = np.r_[np.zeros(nv + ne), np.ones(ncon)]
    res2 = linprog(c2, A_ub=Asl, b_ub=bub, bounds=bounds + [(0, None)] * ncon, method='highs')
    sl = res2.x[nv + ne:]
    print('min total slack', sl.sum() / t, '(units of t); violated corners', (sl > 1e-9 * t).sum())
    bad = [meta[k] + (sl[k] / t,) for k in np.nonzero(sl > 1e-9 * t)[0]]
    print('violations by (shared verts, corner-at-a-vertex, in faceOrders):',
          collections.Counter((b[3], b[4] > 0, b[5]) for b in bad))
    print('largest:', sorted(bad, key=lambda b: -b[-1])[:8])
    json.dump([[int(x) if not isinstance(x, float) else x for x in b] for b in bad], open(f'{EXP}/{out}-violations.json', 'w'))
    sys.exit(1)
z = res.x[:nv]
Z = Xs.copy(); Z[:, 2] = z - z.min()
np.save(f'{EXP}/{out}.npy', Z)
st = edge_strain(Z, M, Ev)
ps = principal_stretch(Z, M, F)
print(f'z range {Z[:,2].max():.4e}; edge strain max {st.max()*100:.3f}% min {st.min()*100:.3f}% ; '
      f'principal stretch max {(ps[:,0].max()-1)*100:.3f}% min {(ps[:,1].min()-1)*100:.3f}%')
json.dump(dict(t=t, delta=delta, depth={int(k): int(v) for k, v in depth.items()}, levels=lvl.tolist()),
          open(f'{EXP}/{out}-meta.json', 'w'))
