"""Measure how far a saved study mesh is from IPC's starting requirement.

IPC (Li et al. 2020, p.12) needs every non-incident primitive pair
(vertex-triangle with the vertex not a corner of the triangle; edge-edge
with no shared endpoint) at strictly positive distance, and no crossings.
C-IPC with thickness xi needs every such distance > xi.

Pure Python, no NumPy. Coordinates are in sheet units (unit square sheet).
Usage: python3 ipc_precondition.py FILE.fold [FILE.fold ...]
"""

import json
import sys
import time
from itertools import combinations

EPS = 1e-12


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def mul(s, a):
    return (s * a[0], s * a[1], s * a[2])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def norm(a):
    return dot(a, a) ** 0.5


def closest_point_triangle(p, a, b, c):
    # Ericson, Real-Time Collision Detection, 5.1.5
    ab, ac, ap = sub(b, a), sub(c, a), sub(p, a)
    d1, d2 = dot(ab, ap), dot(ac, ap)
    if d1 <= 0 and d2 <= 0:
        return a
    bp = sub(p, b)
    d3, d4 = dot(ab, bp), dot(ac, bp)
    if d3 >= 0 and d4 <= d3:
        return b
    vc = d1 * d4 - d3 * d2
    if vc <= 0 and d1 >= 0 and d3 <= 0:
        v = d1 / (d1 - d3)
        return add(a, mul(v, ab))
    cp = sub(p, c)
    d5, d6 = dot(ab, cp), dot(ac, cp)
    if d6 >= 0 and d5 <= d6:
        return c
    vb = d5 * d2 - d1 * d6
    if vb <= 0 and d2 >= 0 and d6 <= 0:
        w = d2 / (d2 - d6)
        return add(a, mul(w, ac))
    va = d3 * d6 - d5 * d4
    if va <= 0 and (d4 - d3) >= 0 and (d5 - d6) >= 0:
        w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        return add(b, mul(w, sub(c, b)))
    denom = 1.0 / (va + vb + vc)
    v, w = vb * denom, vc * denom
    return add(a, add(mul(v, ab), mul(w, ac)))


def pt_distance(p, a, b, c):
    return norm(sub(p, closest_point_triangle(p, a, b, c)))


def clamp(x, lo, hi):
    return lo if x < lo else hi if x > hi else x


def ee_distance(p1, q1, p2, q2):
    # Ericson 5.1.9
    d1, d2, r = sub(q1, p1), sub(q2, p2), sub(p1, p2)
    a, e, f = dot(d1, d1), dot(d2, d2), dot(d2, r)
    if a <= EPS and e <= EPS:
        return norm(r)
    if a <= EPS:
        s, t = 0.0, clamp(f / e, 0, 1)
    else:
        c = dot(d1, r)
        if e <= EPS:
            t, s = 0.0, clamp(-c / a, 0, 1)
        else:
            b = dot(d1, d2)
            den = a * e - b * b
            s = clamp((b * f - c * e) / den, 0, 1) if den > EPS * a * e else 0.0
            t = (b * s + f) / e
            if t < 0:
                t, s = 0.0, clamp(-c / a, 0, 1)
            elif t > 1:
                t, s = 1.0, clamp((b - c) / a, 0, 1)
    c1 = add(p1, mul(s, d1))
    c2 = add(p2, mul(t, d2))
    return norm(sub(c1, c2))


def segment_triangle_point(p, q, a, b, c, tol=1e-12):
    """Proper crossing point of segment pq with triangle abc, or None.

    Coplanar or grazing cases return None: they are touching, not a
    transversal crossing, and the study treats coincident layers by order.
    """
    n = cross(sub(b, a), sub(c, a))
    nn = norm(n)
    if nn < 1e-18:
        return None
    dp = dot(n, sub(p, a)) / nn
    dq = dot(n, sub(q, a)) / nn
    if (dp > tol and dq > tol) or (dp < -tol and dq < -tol):
        return None
    if abs(dp) <= tol and abs(dq) <= tol:
        return None  # coplanar
    if abs(dp - dq) < 1e-30:
        return None
    s = dp / (dp - dq)
    x = add(p, mul(s, sub(q, p)))
    # barycentric inside test, strict up to tolerance
    v0, v1, v2 = sub(b, a), sub(c, a), sub(x, a)
    d00, d01, d11 = dot(v0, v0), dot(v0, v1), dot(v1, v1)
    d20, d21 = dot(v2, v0), dot(v2, v1)
    den = d00 * d11 - d01 * d01
    if den <= 0:
        return None
    v = (d11 * d20 - d01 * d21) / den
    w = (d00 * d21 - d01 * d20) / den
    u = 1 - v - w
    btol = 1e-9
    if u < -btol or v < -btol or w < -btol:
        return None
    return x


def load(path):
    d = json.load(open(path))
    V = [tuple(v) + (0.0,) * (3 - len(v)) for v in d["vertices_coords"]]
    F = [tuple(f) for f in d["faces_vertices"]]
    return d, V, F


def aabb(points, pad):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    zs = [p[2] for p in points]
    return (min(xs) - pad, min(ys) - pad, min(zs) - pad, max(xs) + pad, max(ys) + pad, max(zs) + pad)


def overlap(b1, b2):
    return not (b1[3] < b2[0] or b2[3] < b1[0] or b1[4] < b2[1] or b2[4] < b1[1] or b1[5] < b2[2] or b2[5] < b1[2])


def analyse(path, dmax=0.01, thresholds=(1e-9, 1e-6, 1e-4, 6.7e-4, 1e-3, 3e-3, 1e-2)):
    t0 = time.time()
    d, V, F = load(path)
    tri = [tuple(V[i] for i in f) for f in F]
    boxes = [aabb(t, dmax / 2) for t in tri]
    edges = sorted({tuple(sorted(e)) for f in F for e in ((f[0], f[1]), (f[1], f[2]), (f[2], f[0]))})
    near_tri_pairs = [(i, j) for i, j in combinations(range(len(F)), 2) if overlap(boxes[i], boxes[j])]
    pt, ee = {}, {}
    crossing = set()
    for i, j in near_tri_pairs:
        fi, fj = F[i], F[j]
        shared = set(fi) & set(fj)
        for (A, B) in ((fi, fj), (fj, fi)):
            for v in A:
                if v in B:
                    continue
                key = (v, B)
                if key not in pt:
                    pt[key] = pt_distance(V[v], *(V[k] for k in B))
        for e1 in ((fi[0], fi[1]), (fi[1], fi[2]), (fi[2], fi[0])):
            for e2 in ((fj[0], fj[1]), (fj[1], fj[2]), (fj[2], fj[0])):
                if set(e1) & set(e2):
                    continue
                key = (tuple(sorted(e1)), tuple(sorted(e2)))
                key = tuple(sorted(key))
                if key not in ee:
                    ee[key] = ee_distance(V[e1[0]], V[e1[1]], V[e2[0]], V[e2[1]])
        if len(shared) >= 2:
            continue  # joined along an edge: a crossing there is an inversion, not counted
        sv = [V[k] for k in shared]
        hit = False
        for (A, B) in ((fi, fj), (fj, fi)):
            for e in ((A[0], A[1]), (A[1], A[2]), (A[2], A[0])):
                x = segment_triangle_point(V[e[0]], V[e[1]], *(V[k] for k in B))
                if x is None:
                    continue
                if any(norm(sub(x, s)) < 1e-9 for s in sv):
                    continue
                hit = True
                break
            if hit:
                break
        if hit:
            crossing.add((i, j))
    dists = list(pt.values()) + list(ee.values())
    out = {
        "file": path.split("/")[-1],
        "vertices": len(V),
        "triangles": len(F),
        "edges": len(edges),
        "triangle_pairs_total": len(F) * (len(F) - 1) // 2,
        "triangle_pairs_within_dmax_box": len(near_tri_pairs),
        "pt_pairs_checked": len(pt),
        "ee_pairs_checked": len(ee),
        "min_primitive_distance": min(dists) if dists else None,
        "crossing_triangle_pairs": len(crossing),
        "primitive_pairs_at_or_below": {str(t): sum(1 for x in dists if x <= t) for t in thresholds},
        "seconds": round(time.time() - t0, 2),
    }
    return out


if __name__ == "__main__":
    for p in sys.argv[1:]:
        print(json.dumps(analyse(p)))
