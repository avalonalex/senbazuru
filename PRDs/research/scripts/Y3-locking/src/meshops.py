"""Triangulation variants: flip join diagonals, or split every triangle in four.

Both keep every source crease and boundary exactly where it was: only J
(join) edges inside a panel are flipped, and a split crease keeps its
assignment on both halves.
"""
import numpy as np
from sheet import edge_key


def _area2(UV, a, b, c):
    p, q, r = UV[a], UV[b], UV[c]
    return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])


def _min_angle(UV, a, b, c):
    P = [UV[a], UV[b], UV[c]]
    out = []
    for i in range(3):
        u = P[(i + 1) % 3] - P[i]
        v = P[(i + 2) % 3] - P[i]
        out.append(np.degrees(np.arccos(np.clip(u @ v / np.linalg.norm(u) / np.linalg.norm(v), -1, 1))))
    return min(out)


def flip_joins(F, UV, amap, panels, order=None, min_area_ratio=0.05, min_angle=20.0):
    """Greedy pass over J edges; flip each one whose quad is strictly convex in
    material space and whose two triangles are in the same source panel.
    Returns new faces, new panels, number flipped, number of J edges seen."""
    tris = {t: tuple(map(int, f)) for t, f in enumerate(F)}
    pan = {t: int(p) for t, p in enumerate(panels)}
    inc = {}
    for t, (i, j, k) in tris.items():
        for a, b in ((i, j), (j, k), (k, i)):
            inc.setdefault(edge_key(a, b), set()).add(t)
    joins = [e for e, ts in inc.items() if len(ts) == 2 and amap.get(e, "J") == "J"]
    if order is not None:
        joins = [joins[i] for i in order]
    flipped = 0
    for e in joins:
        ts = inc.get(e)
        if ts is None or len(ts) != 2:
            continue
        t1, t2 = sorted(ts)
        if pan[t1] != pan[t2]:
            continue
        a, b = e

        def third(t, x, y):
            return [v for v in tris[t] if v not in (x, y)][0]

        # orient: find triangle containing directed a->b
        def has_dir(t, x, y):
            i, j, k = tris[t]
            return (x, y) in ((i, j), (j, k), (k, i))

        if has_dir(t1, a, b):
            tab, tba = t1, t2
        elif has_dir(t2, a, b):
            tab, tba = t2, t1
        else:
            continue
        c = third(tab, a, b)
        d = third(tba, a, b)
        if edge_key(c, d) in inc:
            continue
        A1 = _area2(UV, c, a, d)
        A2 = _area2(UV, d, b, c)
        old = _area2(UV, a, b, c) + _area2(UV, b, a, d)
        if A1 <= min_area_ratio * old or A2 <= min_area_ratio * old:
            continue
        # keep a usable triangulation: no slivers (minimum angle in material space)
        new_min = min(_min_angle(UV, c, a, d), _min_angle(UV, d, b, c))
        old_min = min(_min_angle(UV, a, b, c), _min_angle(UV, b, a, d))
        if new_min < min(min_angle, 0.7 * old_min):
            continue
        # replace
        for t in (tab, tba):
            i, j, k = tris[t]
            for x, y in ((i, j), (j, k), (k, i)):
                inc[edge_key(x, y)].discard(t)
        del inc[edge_key(a, b)]
        tris[tab] = (c, a, d)
        tris[tba] = (d, b, c)
        for t in (tab, tba):
            i, j, k = tris[t]
            for x, y in ((i, j), (j, k), (k, i)):
                inc.setdefault(edge_key(x, y), set()).add(t)
        flipped += 1
    newF = np.array([tris[t] for t in range(len(F))], int)
    newP = np.array([pan[t] for t in range(len(F))], int)
    return newF, newP, flipped, len(joins)


def refine(F, UV, X, amap, panels):
    """1-to-4 midpoint split. Returns F, UV, X (flat midpoints), amap, panels,
    parents (n_new x 2, -1 for original vertices)."""
    UV = list(map(np.asarray, UV))
    X = list(map(np.asarray, X))
    n0 = len(UV)
    mid = {}
    parents = [(-1, -1)] * n0

    def m(a, b):
        e = edge_key(a, b)
        if e not in mid:
            mid[e] = len(UV)
            UV.append((UV[a] + UV[b]) / 2)
            X.append((X[a] + X[b]) / 2)
            parents.append(e)
        return mid[e]

    newF, newP = [], []
    newA = {}
    for (i, j, k), p in zip(F, panels):
        i, j, k = int(i), int(j), int(k)
        a, b, c = m(i, j), m(j, k), m(k, i)
        newF += [(i, a, c), (a, j, b), (c, b, k), (a, b, c)]
        newP += [p] * 4
        for (x, y), mm in (((i, j), a), ((j, k), b), ((k, i), c)):
            s = amap.get(edge_key(x, y), "J")
            if s != "J":
                newA[edge_key(x, mm)] = s
                newA[edge_key(mm, y)] = s
    return (np.array(newF, int), np.array(UV), np.array(X), newA, np.array(newP, int),
            np.array(parents, int))
