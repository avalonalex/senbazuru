"""Build a thickness-offset crane stack for broad-phase timing.

Each triangle of the closed crane (before.fold, 448 triangles) is lifted to
z = level * xi, where level is its longest-path height in the faceOrders
order (g's normal convention). Triangles keep their own vertex copies; each
is then split into 4^k children. Output: one line per triangle,
'level x1 y1 z1 x2 y2 z2 x3 y3 z3'. This tears the sheet at creases: it is a
timing and pair-count fixture, not a valid paper state.
"""
import json, sys
d = json.load(open(sys.argv[1])); k = int(sys.argv[2]); xi = float(sys.argv[3])
V = [tuple(v) for v in d['vertices_coords']]; F = [tuple(f) for f in d['faces_vertices']]
def a2(f):
    (x1,y1,_),(x2,y2,_),(x3,y3,_) = (V[i] for i in f); return (x2-x1)*(y3-y1)-(y2-y1)*(x3-x1)
nrm = [1 if a2(f) > 0 else -1 for f in F]
succ = {i: [] for i in range(len(F))}; indeg = {i: 0 for i in range(len(F))}
seen = set()
for f, g, s in d['faceOrders']:
    f_up = (s == 1) == (nrm[g] == 1)
    lo, hi = (g, f) if f_up else (f, g)
    if (lo, hi) in seen: continue
    seen.add((lo, hi)); succ[lo].append(hi); indeg[hi] += 1
level = {i: 0 for i in F and range(len(F))}; q = [i for i in indeg if indeg[i] == 0]; n = 0
while q:
    g = q.pop(); n += 1
    for f in succ[g]:
        level[f] = max(level[f], level[g] + 1); indeg[f] -= 1
        if indeg[f] == 0: q.append(f)
assert n == len(F), 'cycle'
def split(t):
    a, b, c = t
    m = lambda p, q: tuple((p[i]+q[i])/2 for i in range(3))
    ab, bc, ca = m(a,b), m(b,c), m(c,a)
    return [(a,ab,ca),(ab,b,bc),(ca,bc,c),(ab,bc,ca)]
out = []
for i, f in enumerate(F):
    z = level[i] * xi
    tris = [tuple((V[j][0], V[j][1], z) for j in f)]
    for _ in range(k): tris = [c for t in tris for c in split(t)]
    for t in tris: out.append((level[i], t))
print(len(out), max(level.values()) + 1, file=sys.stderr)
for L, t in out: print(L, *[c for p in t for c in p])
