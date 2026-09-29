"""Layer depth, crease wrap counts and coincident creases of the flat crane.

Input: the crease pattern (material coordinates) and the output of
`senbazuru fold examples/crane.fold -o crane-folded.fold` (folded
coordinates plus faceOrders). Both share vertex, edge and face ids.

A face's normal in the folded state is +z or -z (flat model). FOLD's
faceOrders [f, g, s]: s = +1 means f lies on the side that g's normal
points to (docs/notes/layer-ordering.md). Heights here are along +z.
"""

import json
import sys
from itertools import combinations

cp = json.load(open(sys.argv[1]))
fo = json.load(open(sys.argv[2]))
Vm = [tuple(v[:2]) for v in cp["vertices_coords"]]
Vf = [tuple(v[:2]) for v in fo["vertices_coords"]]
F = [tuple(f) for f in fo["faces_vertices"]]
E = [tuple(e) for e in fo["edges_vertices"]]
A = fo["edges_assignment"]
assert [tuple(e) for e in cp["edges_vertices"]] == E, "edge ids differ"
assert [tuple(f) for f in cp["faces_vertices"]] == F, "face ids differ"


def area2(poly):
    s = 0.0
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % len(poly)]
        s += x1 * y2 - x2 * y1
    return s


def polyf(f):
    return [Vf[i] for i in f]


normal = [1 if area2(polyf(f)) > 0 else -1 for f in F]


def convex(poly):
    sgn = 0
    n = len(poly)
    for i in range(n):
        (x0, y0), (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % n], poly[(i + 2) % n]
        c = (x1 - x0) * (y2 - y1) - (y1 - y0) * (x2 - x1)
        if abs(c) < 1e-14:
            continue
        s = 1 if c > 0 else -1
        if sgn == 0:
            sgn = s
        elif s != sgn:
            return False
    return True


assert all(convex(polyf(f)) for f in F), "non-convex face"


def inside(p, poly, margin=1e-9):
    s = 1 if area2(poly) > 0 else -1
    n = len(poly)
    for i in range(n):
        (x1, y1), (x2, y2) = poly[i], poly[(i + 1) % n]
        c = ((x2 - x1) * (p[1] - y1) - (y2 - y1) * (p[0] - x1)) * s
        L = ((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5
        if c <= margin * L:
            return False
    return True


# above[(f, g)] = True when f is higher than g along +z
above = {}
for f, g, s in fo["faceOrders"]:
    f_up = (s == 1) == (normal[g] == 1)
    above[(f, g)] = f_up
    above[(g, f)] = not f_up

# Global DAG and compact levels (longest path from the bottom).
succ = {i: [] for i in range(len(F))}
for (f, g), up in above.items():
    if up:
        succ[g].append(f)  # g below f
indeg = {i: 0 for i in range(len(F))}
for g in succ:
    for f in succ[g]:
        indeg[f] += 1
order, queue = [], [i for i in indeg if indeg[i] == 0]
level = {i: 0 for i in range(len(F))}
while queue:
    g = queue.pop()
    order.append(g)
    for f in succ[g]:
        level[f] = max(level[f], level[g] + 1)
        indeg[f] -= 1
        if indeg[f] == 0:
            queue.append(f)
acyclic = len(order) == len(F)


def local_stack(p):
    faces = [i for i, f in enumerate(F) if inside(p, polyf(f))]
    rank = {f: sum(1 for g in faces if g != f and above.get((f, g), False)) for f in faces}
    consistent = sorted(rank.values()) == list(range(len(faces)))
    return faces, rank, consistent


# Maximum number of layers: sample a grid over the folded footprint.
xs = [v[0] for v in Vf]
ys = [v[1] for v in Vf]
N = 240
best, best_p, inconsistent = 0, None, 0
for a in range(N):
    for b in range(N):
        p = (min(xs) + (max(xs) - min(xs)) * (a + 0.5) / N, min(ys) + (max(ys) - min(ys)) * (b + 0.5) / N)
        faces, rank, ok = local_stack(p)
        if not ok:
            inconsistent += 1
        if len(faces) > best:
            best, best_p = len(faces), p

# Crease wrap counts at quarter points of every M/V crease.
edge_faces = {}
for fi, f in enumerate(F):
    for k in range(len(f)):
        e = tuple(sorted((f[k], f[(k + 1) % len(f)])))
        edge_faces.setdefault(e, []).append(fi)

wraps = []
rankgaps = []
for ei, (u, v) in enumerate(E):
    if A[ei] not in ("M", "V"):
        continue
    fs = edge_faces.get(tuple(sorted((u, v))), [])
    if len(fs) != 2:
        continue
    f, g = fs
    (x1, y1), (x2, y2) = Vf[u], Vf[v]
    L = ((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5
    nx, ny = -(y2 - y1) / L, (x2 - x1) / L
    cx = sum(Vf[k][0] for k in F[f]) / len(F[f])
    cy = sum(Vf[k][1] for k in F[f]) / len(F[f])
    if (cx - x1) * nx + (cy - y1) * ny < 0:
        nx, ny = -nx, -ny
    per_edge = []
    for t in (0.25, 0.5, 0.75):
        p = (x1 + t * (x2 - x1) + 1e-5 * nx, y1 + t * (y2 - y1) + 1e-5 * ny)
        faces, rank, ok = local_stack(p)
        if f not in rank or g not in rank:
            continue
        lo, hi = sorted((rank[f], rank[g]))
        per_edge.append(hi - lo - 1)
        rankgaps.append(abs(level[f] - level[g]))
    if per_edge:
        wraps.append((ei, max(per_edge)))

hist = {}
for _, w in wraps:
    hist[w] = hist.get(w, 0) + 1


# Coincident creases: pairs of distinct M/V edges whose folded segments
# overlap along a positive length on the same line.
def overlap_len(e1, e2):
    (ax, ay), (bx, by) = Vf[e1[0]], Vf[e1[1]]
    (cx, cy), (dx, dy) = Vf[e2[0]], Vf[e2[1]]
    L = ((bx - ax) ** 2 + (by - ay) ** 2) ** 0.5
    ux, uy = (bx - ax) / L, (by - ay) / L
    for px, py in ((cx, cy), (dx, dy)):
        if abs((px - ax) * uy - (py - ay) * ux) > 1e-9:
            return 0.0
    t1 = (cx - ax) * ux + (cy - ay) * uy
    t2 = (dx - ax) * ux + (dy - ay) * uy
    lo, hi = max(0.0, min(t1, t2)), min(L, max(t1, t2))
    return max(0.0, hi - lo)


creases = [i for i in range(len(E)) if A[i] in ("M", "V")]
coincident = [(i, j) for i, j in combinations(creases, 2) if overlap_len(E[i], E[j]) > 1e-9]

crease_len = sum(((Vm[E[i][0]][0] - Vm[E[i][1]][0]) ** 2 + (Vm[E[i][0]][1] - Vm[E[i][1]][1]) ** 2) ** 0.5 for i in creases)

print(json.dumps({
    "faces": len(F),
    "faceOrders": len(fo["faceOrders"]),
    "global_order_acyclic": acyclic,
    "compact_levels_max": max(level.values()) + 1,
    "max_layers_at_a_point": best,
    "at_point": best_p,
    "grid_points_with_inconsistent_local_order": inconsistent,
    "creases_MV": len(creases),
    "crease_wrap_count_histogram": dict(sorted(hist.items())),
    "max_wrap": max(w for _, w in wraps),
    "max_compact_level_gap_across_a_crease": max(rankgaps),
    "coincident_crease_pairs": len(coincident),
    "total_MV_crease_length_sheet_units": round(crease_len, 4),
}, indent=1))
