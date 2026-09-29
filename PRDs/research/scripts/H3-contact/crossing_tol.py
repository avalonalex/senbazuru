"""Count transversal triangle crossings at several penetration tolerances,
split by whether the pair shares a vertex. Reuses ipc_precondition helpers."""
import json, sys
from itertools import combinations
from ipc_precondition import load, aabb, overlap, segment_triangle_point, norm, sub

def crossings(path, tol):
    d, V, F = load(path)
    boxes = [aabb([V[i] for i in f], 1e-9) for f in F]
    disjoint = one = 0
    for i, j in combinations(range(len(F)), 2):
        if not overlap(boxes[i], boxes[j]):
            continue
        fi, fj = F[i], F[j]
        shared = set(fi) & set(fj)
        if len(shared) >= 2:
            continue
        sv = [V[k] for k in shared]
        hit = False
        for A, B in ((fi, fj), (fj, fi)):
            for e in ((A[0], A[1]), (A[1], A[2]), (A[2], A[0])):
                x = segment_triangle_point(V[e[0]], V[e[1]], *(V[k] for k in B), tol=tol)
                if x is not None and not any(norm(sub(x, s)) < max(1e-9, 10 * tol) for s in sv):
                    hit = True; break
            if hit: break
        if hit:
            if shared: one += 1
            else: disjoint += 1
    return disjoint, one

for p in sys.argv[1:]:
    row = {"file": p.split('/')[-1]}
    for tol in (1e-12, 1e-9, 1e-7, 1e-5):
        dj, on = crossings(p, tol)
        row[str(tol)] = {"vertex_disjoint": dj, "share_one_vertex": on}
    print(json.dumps(row))
