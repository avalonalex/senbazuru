#!/usr/bin/env python3
"""Scratch analysis for the layer-selective-fold research note.

An independent re-implementation (written from the ideas in the repo's own
module headers, not from any GPL source) of: tracing faces, folding a
flat-folded pattern by reflections over a spanning walk, clipping a folded-space
line to each face, and splitting the face graph along that line to find the
component a material seed point belongs to.

Flat folds only: every angle must be 0 or +-180.
"""
import json
import math
import sys
import os
from collections import defaultdict, deque

# Restrict which crossed faces are cut, e.g. CUT=6,7 (default: every crossed face).
CUT = set(int(x) for x in os.environ["CUT"].split(",")) if os.environ.get("CUT") else None


def load(path):
    d = json.load(open(path))
    V = [tuple(float(x) for x in c[:2]) for c in d["vertices_coords"]]
    E = [tuple(e) for e in d["edges_vertices"]]
    A = d.get("edges_assignment") or ["U"] * len(E)
    ang = d.get("edges_foldAngle")
    if not ang:
        ang = [-180 if a == "M" else 180 if a == "V" else 0 for a in A]
    F = d.get("faces_vertices") or trace_faces(V, E)
    return V, E, A, ang, F


def signed_area(pts):
    s = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % len(pts)]
        s += x0 * y1 - x1 * y0
    return s / 2


def trace_faces(V, E):
    nbr = defaultdict(list)
    for a, b in E:
        nbr[a].append(b)
        nbr[b].append(a)
    for v in nbr:
        nbr[v].sort(key=lambda w: math.atan2(V[w][1] - V[v][1], V[w][0] - V[v][0]))
    used = set()
    faces = []
    for a, b in E:
        for u, v in ((a, b), (b, a)):
            if (u, v) in used:
                continue
            ring = []
            cu, cv = u, v
            while (cu, cv) not in used:
                used.add((cu, cv))
                ring.append(cu)
                ns = nbr[cv]
                i = ns.index(cu)
                w = ns[(i - 1) % len(ns)]  # next clockwise from the way we came
                cu, cv = cv, w
            if signed_area([V[i] for i in ring]) > 1e-12:
                faces.append(ring)
    return faces


def compose(p, q):
    # p after q : x -> p(q(x)); affine as (M 2x2 tuple, t)
    (pa, pb, pc, pd, ptx, pty), (qa, qb, qc, qd, qtx, qty) = p, q
    return (
        pa * qa + pb * qc,
        pa * qb + pb * qd,
        pc * qa + pd * qc,
        pc * qb + pd * qd,
        pa * qtx + pb * qty + ptx,
        pc * qtx + pd * qty + pty,
    )


IDENT = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)


def reflection(p0, p1):
    ux, uy = p1[0] - p0[0], p1[1] - p0[1]
    n = math.hypot(ux, uy)
    ux, uy = ux / n, uy / n
    a, b, c, d = 2 * ux * ux - 1, 2 * ux * uy, 2 * ux * uy, 2 * uy * uy - 1
    tx = p0[0] - (a * p0[0] + b * p0[1])
    ty = p0[1] - (c * p0[0] + d * p0[1])
    return (a, b, c, d, tx, ty)


def apply(m, p):
    a, b, c, d, tx, ty = m
    return (a * p[0] + b * p[1] + tx, c * p[0] + d * p[1] + ty)


def inverse(m):
    a, b, c, d, tx, ty = m
    det = a * d - b * c
    ia, ib, ic, id_ = d / det, -b / det, -c / det, a / det
    return (ia, ib, ic, id_, -(ia * tx + ib * ty), -(ic * tx + id_ * ty))


def det(m):
    return m[0] * m[3] - m[1] * m[2]


def fold(V, E, A, ang, F):
    F = [f if signed_area([V[i] for i in f]) > 0 else list(reversed(f)) for f in F]
    key = lambda a, b: (min(a, b), max(a, b))
    eid = {key(a, b): i for i, (a, b) in enumerate(E)}
    along = defaultdict(list)
    for fi, f in enumerate(F):
        for i in range(len(f)):
            along[key(f[i], f[(i + 1) % len(f)])].append(fi)
    place = {0: IDENT}
    frontier = [0]
    while frontier:
        reached = []
        for fi in frontier:
            f = F[fi]
            for i in range(len(f)):
                a, b = f[i], f[(i + 1) % len(f)]
                k = key(a, b)
                others = [g for g in along[k] if g != fi]
                if not others:
                    continue
                th = ang[eid[k]]
                if abs(abs(th) - 180) < 1e-9:
                    turn = reflection(V[a], V[b])
                elif abs(th) < 1e-9:
                    turn = IDENT
                else:
                    raise SystemExit("not a flat fold at edge %d (%s)" % (eid[k], th))
                for g in others:
                    if g not in place:
                        reached.append((g, compose(place[fi], turn)))
        new = []
        for g, m in reached:
            if g not in place:
                place[g] = m
                new.append(g)
        frontier = new
    # closure check: every face agrees on shared vertices
    pos = {}
    worst = 0.0
    for fi, f in enumerate(F):
        for v in f:
            p = apply(place[fi], V[v])
            if v in pos:
                worst = max(worst, math.hypot(p[0] - pos[v][0], p[1] - pos[v][1]))
            else:
                pos[v] = p
    return F, along, eid, place, pos, worst


def cross2(u, v):
    return u[0] * v[1] - u[1] * v[0]


def clip_segment(poly, p, q):
    d = (q[0] - p[0], q[1] - p[1])
    t0, t1 = 0.0, 1.0
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        e = (b[0] - a[0], b[1] - a[1])
        at = cross2(e, (p[0] - a[0], p[1] - a[1]))
        slope = cross2(e, d)
        if slope == 0:
            if at < 0:
                return None
        elif slope > 0:
            t0 = max(t0, -at / slope)
        else:
            t1 = min(t1, -at / slope)
    if t0 <= t1:
        return (t0, t1)
    return None


def distance_outside(poly, x):
    best = -float("inf")
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        e = (b[0] - a[0], b[1] - a[1])
        ln = math.hypot(*e)
        if ln > 0:
            best = max(best, -cross2(e, (x[0] - a[0], x[1] - a[1])) / ln)
    return best


def analyse_line(path, p, q, seed=None, verbose=True):
    V, E, A, ang, F0 = load(path)
    F, along, eid, place, pos, worst = fold(V, E, A, ang, F0)
    xs = [c[0] for c in pos.values()]
    ys = [c[1] for c in pos.values()]
    scale = max(1.0, max(xs) - min(xs), max(ys) - min(ys))
    hair = 1e-9 * scale
    panels = {}
    up = {}
    for fi, f in enumerate(F):
        ring = [pos[v] for v in f]
        u = det(place[fi]) > 0
        up[fi] = u
        panels[fi] = ring if signed_area(ring) > 0 else list(reversed(ring))
    L = math.hypot(q[0] - p[0], q[1] - p[1])
    out = {"faces": len(F), "closure_error": worst}
    ends_inside = [(w, fi) for w, x in (("from", p), ("to", q)) for fi in panels if distance_outside(panels[fi], x) < -hair]
    crossed = {}
    for fi, ring in panels.items():
        c = clip_segment(ring, p, q)
        if not c:
            continue
        t0, t1 = c
        u = (p[0] + t0 * (q[0] - p[0]), p[1] + t0 * (q[1] - p[1]))
        v = (p[0] + t1 * (q[0] - p[0]), p[1] + t1 * (q[1] - p[1]))
        if math.hypot(v[0] - u[0], v[1] - u[1]) <= hair:
            continue
        mid = ((u[0] + v[0]) / 2, (u[1] + v[1]) / 2)
        if not distance_outside(ring, mid) < -hair:
            continue
        back = inverse(place[fi])
        crossed[fi] = {"t": (t0, t1), "folded": (u, v), "sheet": (apply(back, u), apply(back, v)), "up": up[fi]}
    out["ends_strictly_inside"] = ends_inside
    out["crossed"] = crossed

    def side(x):
        s = cross2((q[0] - p[0], q[1] - p[1]), (x[0] - p[0], x[1] - p[1])) / L
        return 0 if abs(s) <= hair else (1 if s > 0 else -1)

    cut = set(crossed) if CUT is None else (set(crossed) & CUT)
    out["cut"] = sorted(cut)

    def node(fi, s):
        return (fi, s) if fi in cut else (fi, 0)

    links = []
    on_line = []
    for k, fs in along.items():
        if len(fs) != 2:
            continue
        f, g = fs
        sa, sb = side(pos[k[0]]), side(pos[k[1]])
        sides = {s for s in (sa, sb) if s != 0}
        if not sides:
            # an existing edge lying along the folded line
            tvals = [((pos[v][0] - p[0]) * (q[0] - p[0]) + (pos[v][1] - p[1]) * (q[1] - p[1])) / (L * L) for v in k]
            if max(tvals) > 1e-9 and min(tvals) < 1 - 1e-9:
                on_line.append((eid[k], A[eid[k]], ang[eid[k]], f, g))
                continue
            links.append(((f, 0), (g, 0)))
            continue
        for s in sides:
            links.append((node(f, s), node(g, s)))
    # uncut faces lying on one side keep side 0 nodes; that is fine for connectivity
    adj = defaultdict(set)
    for a, b in links:
        adj[a].add(b)
        adj[b].add(a)
    out["on_line_edges"] = on_line
    if seed is not None:
        home = [fi for fi, f in enumerate(F) if distance_outside([V[v] for v in f], seed) < -1e-10]
        out["seed_faces"] = home
        if len(home) == 1:
            fi = home[0]
            sp = apply(place[fi], seed)
            start = node(fi, side(sp))
            seen = {start}
            dq = deque([start])
            while dq:
                x = dq.popleft()
                for y in adj[x]:
                    if y not in seen:
                        seen.add(y)
                        dq.append(y)
            selected = sorted({fi for (fi, s) in seen if fi in crossed})
            both = sorted({fi for fi in crossed if (fi, 1) in seen and (fi, -1) in seen})
            out["seed_folded"] = sp
            out["component_faces"] = sorted({fi for (fi, s) in seen})
            out["selected"] = selected
            out["not_separated"] = both
            out["hinge_existing"] = [e for e in on_line if (((e[3], 0) in seen) != ((e[4], 0) in seen))]
    return out, panels, up, place, F, pos, A, eid, along, ang


def fmt(x):
    return "(%.6g, %.6g)" % x


if __name__ == "__main__":
    cmd = sys.argv[1]
    path = sys.argv[2]
    if cmd == "fold":
        V, E, A, ang, F0 = load(path)
        F, along, eid, place, pos, worst = fold(V, E, A, ang, F0)
        print("faces", len(F), "closure", worst)
        for fi, f in enumerate(F):
            print(fi, f, "up" if det(place[fi]) > 0 else "down", [fmt(pos[v]) for v in f])
        for v in sorted(pos):
            print("v", v, fmt(V[v]), "->", fmt(pos[v]))
    elif cmd == "tacos":
        # The one stacking rule that needs nothing but the crease itself: two
        # faces joined by a closed crease overlap, and a valley puts the face
        # lying top-down above (+z) the one lying top-up; a mountain the reverse.
        V, E, A, ang, F0 = load(path)
        F, along, eid, place, pos, worst = fold(V, E, A, ang, F0)
        only = set(int(x) for x in sys.argv[3].split(",")) if len(sys.argv) > 3 else None
        for k, fs in sorted(along.items(), key=lambda kv: eid[kv[0]]):
            if len(fs) != 2 or abs(abs(ang[eid[k]]) - 180) > 1e-9:
                continue
            f, g = fs
            if only is not None and not ({f, g} & only):
                continue
            upf, upg = det(place[f]) > 0, det(place[g]) > 0
            if upf == upg:
                print("edge", eid[k], k, A[eid[k]], "faces", f, g, "both same way up?!")
                continue
            down, upface = (f, g) if not upf else (g, f)
            valley = ang[eid[k]] > 0
            hi, lo = (down, upface) if valley else (upface, down)
            print("edge %d %s %s angle %g: face %d above face %d (world +z)" % (eid[k], k, A[eid[k]], ang[eid[k]], hi, lo))
    elif cmd == "line":
        p = tuple(map(float, sys.argv[3].split(",")))
        q = tuple(map(float, sys.argv[4].split(",")))
        seed = tuple(map(float, sys.argv[5].split(","))) if len(sys.argv) > 5 else None
        out, panels, up, place, F, pos, A, eid, along, ang = analyse_line(path, p, q, seed)
        print("faces", out["faces"], "closure", out["closure_error"])
        print("ends strictly inside a face:", out["ends_strictly_inside"])
        print("crossed faces:", sorted(out["crossed"]))
        for fi in sorted(out["crossed"]):
            c = out["crossed"][fi]
            print("  face %d ring %s %s t=[%.4f,%.4f] sheet %s-%s" % (fi, F[fi], "up" if c["up"] else "down", c["t"][0], c["t"][1], fmt(c["sheet"][0]), fmt(c["sheet"][1])))
        print("existing edges along the line:", out["on_line_edges"])
        for k in ("seed_faces", "seed_folded", "component_faces", "selected", "not_separated", "hinge_existing"):
            if k in out:
                print(k, out[k])
