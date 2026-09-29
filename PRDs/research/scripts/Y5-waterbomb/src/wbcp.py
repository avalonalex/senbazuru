"""Construct the traditional water-bomb balloon crease pattern (Y5).

Own code and own geometry. The water bomb is a traditional model with no
single author; nothing here is copied from a diagram, tutorial file or GPL
source. The pattern is derived by *simulating the folding sequence* on a
flat-folded sheet: every face of the crease pattern carries an affine map
(a composition of reflections) into the folded plane and a height z. Each
step reflects a chosen set of faces across a line and re-stacks them.
M/V assignments are then read off the final state: a crease is a valley
when the two faces' top sides end up facing each other.

Sequence (book view, waterbomb base with its apex up, apex A=(0,1/2),
base on Y=0, bottom middle M=(0,0), unit square sheet):
  1  waterbomb base (diagonals V, horizontal midline M, vertical midline F)
  2  front and back: bottom corners of the outer flaps up to the apex
  3  front and back: side corners of the resulting diamond to the centre line
  4  front and back: loose top points down along the side triangles' top edge
  5  front and back: tuck those flaps into the side triangles' pockets; the
     part that overhangs the side triangle wraps round its outer fold

Coordinates are integers in units of 1/8 of the sheet side, so every vertex
of the pattern is exact.
"""

import json
import sys
from fractions import Fraction as Fr

# ------------------------------------------------------------------ segments

S = 8  # grid units per sheet side


def ne_quadrant_segments():
    """Crease lines inside the NE quadrant [4,8]^2 (grid units)."""
    segs = []
    segs.append(((4, 4), (8, 8)))  # diagonal (base, V)
    segs.append(((4, 4), (8, 4)))  # horizontal midline half (base, M)
    segs.append(((4, 4), (4, 8)))  # vertical midline half (base, F)
    segs.append(((4, 8), (8, 4)))  # step 2: x+y = 1.5
    # step 3: square [5,7]^2
    segs.append(((5, 5), (5, 7)))
    segs.append(((5, 5), (7, 5)))
    segs.append(((5, 7), (7, 7)))
    segs.append(((7, 5), (7, 7)))
    # step 4: x+y = 1.75 across the corner
    segs.append(((6, 8), (8, 6)))
    # step 5: tuck creases, x = 7/8 and y = 7/8 continued to the edge
    segs.append(((7, 7), (7, 8)))
    segs.append(((7, 7), (8, 7)))
    return segs


def mirror(seg, mx, my):
    (a, b), (c, d) = seg
    f = (lambda x: S - x) if mx else (lambda x: x)
    g = (lambda y: S - y) if my else (lambda y: y)
    return ((f(a), g(b)), (f(c), g(d)))


def all_segments():
    segs = set()
    for mx in (False, True):
        for my in (False, True):
            for s in ne_quadrant_segments():
                p, q = mirror(s, mx, my)
                segs.add(tuple(sorted((p, q))))
    # boundary
    segs.add(((0, 0), (8, 0)))
    segs.add(((8, 0), (8, 8)))
    segs.add(((0, 8), (8, 8)))
    segs.add(((0, 0), (0, 8)))
    return sorted(segs)


def split_segments(segs):
    """Split every segment at every lattice point it passes through that is
    an endpoint or intersection. All lines here are axis-parallel or at 45
    degrees on an integer lattice, so intersections are lattice or
    half-lattice points; we use Fractions to be safe."""
    pts = set()
    for (p, q) in segs:
        pts.add((Fr(p[0]), Fr(p[1])))
        pts.add((Fr(q[0]), Fr(q[1])))
    # pairwise intersections
    L = [((Fr(p[0]), Fr(p[1])), (Fr(q[0]), Fr(q[1]))) for p, q in segs]
    for i in range(len(L)):
        for j in range(i + 1, len(L)):
            (a, b), (c, d) = L[i], L[j]
            r = (b[0] - a[0], b[1] - a[1])
            s = (d[0] - c[0], d[1] - c[1])
            den = r[0] * s[1] - r[1] * s[0]
            if den == 0:
                continue
            t = ((c[0] - a[0]) * s[1] - (c[1] - a[1]) * s[0]) / den
            u = ((c[0] - a[0]) * r[1] - (c[1] - a[1]) * r[0]) / den
            if 0 <= t <= 1 and 0 <= u <= 1:
                pts.add((a[0] + t * r[0], a[1] + t * r[1]))
    out = []
    for (a, b) in L:
        on = []
        for p in pts:
            cr = (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
            if cr != 0:
                continue
            dx, dy = b[0] - a[0], b[1] - a[1]
            t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy)
            if 0 <= t <= 1:
                on.append((t, p))
        on.sort()
        for k in range(len(on) - 1):
            out.append((on[k][1], on[k + 1][1]))
    return sorted(set(tuple(sorted(e)) for e in out)), sorted(pts)


# ------------------------------------------------------------------ faces


def trace_faces(V, E):
    import math
    idx = {v: i for i, v in enumerate(V)}
    adj = {i: [] for i in range(len(V))}
    for (p, q) in E:
        a, b = idx[p], idx[q]
        adj[a].append(b)
        adj[b].append(a)
    ang = lambda a, b: math.atan2(float(V[b][1] - V[a][1]), float(V[b][0] - V[a][0]))  # noqa: E731
    for a in adj:
        adj[a].sort(key=lambda b: ang(a, b))
    used = set()
    faces = []
    for a in adj:
        for b in adj[a]:
            if (a, b) in used:
                continue
            f = [a]
            u, v = a, b
            while True:
                used.add((u, v))
                # next: at v, turn to the edge just clockwise of (v->u)
                lst = adj[v]
                k = lst.index(u)
                w = lst[(k - 1) % len(lst)]
                u, v = v, w
                if (u, v) == (a, b):
                    break
                f.append(u)
            # signed area
            A = 0
            for i in range(len(f)):
                x1, y1 = V[f[i]]
                x2, y2 = V[f[(i + 1) % len(f)]]
                A += x1 * y2 - x2 * y1
            if A > 0:
                faces.append(f)
    return faces


# ------------------------------------------------------------------ affine maps
# A map is (a, b, c, d, e, f): (x, y) -> (a x + b y + e, c x + d y + f),
# acting on sheet coordinates in grid units, output in grid units.


def compose(m2, m1):
    a, b, c, d, e, f = m1
    A, B, C, D, E, F = m2
    return (A * a + B * c, A * b + B * d, C * a + D * c, C * b + D * d,
            A * e + B * f + E, C * e + D * f + F)


def apply(m, p):
    a, b, c, d, e, f = m
    return (a * p[0] + b * p[1] + e, c * p[0] + d * p[1] + f)


def det(m):
    return m[0] * m[3] - m[1] * m[2]


def reflect_line(p, q):
    """Reflection across the line through p and q (Fractions)."""
    dx, dy = q[0] - p[0], q[1] - p[1]
    n2 = dx * dx + dy * dy
    a = (dx * dx - dy * dy) / n2
    b = 2 * dx * dy / n2
    # R = [[a, b], [b, -a]], x' = R (x - p) + p
    e = p[0] - (a * p[0] + b * p[1])
    f = p[1] - (b * p[0] - a * p[1])
    return (a, b, b, -a, e, f)


def centroid(V, f):
    n = len(f)
    return (sum(V[i][0] for i in f) / n, sum(V[i][1] for i in f) / n)


# ------------------------------------------------------------------ simulation


def simulate(V, faces, stage=5):
    """Return per-face (map, z, tag) of the flat-folded water bomb.
    Folded coordinates in grid units: apex A=(0,4), M=(0,0), base Y=0."""
    Fr4 = Fr(4)
    st = []
    for f in faces:
        cx, cy = centroid(V, f)
        ux, uy = cx - Fr4, cy - Fr4
        # which base region?
        if uy >= abs(ux):
            q, L, z, half = "N", (1, 0, 0, -1), 4, "front"
        elif -uy >= abs(ux):
            q, L, z, half = "S", (1, 0, 0, 1), 1, "back"
        elif ux > 0 and uy > 0:
            q, L, z, half = "Eu", (0, 1, -1, 0), 3, "front"
        elif ux > 0:
            q, L, z, half = "El", (0, -1, -1, 0), 2, "back"
        elif uy > 0:
            q, L, z, half = "Wu", (0, -1, 1, 0), 3, "front"
        else:
            q, L, z, half = "Wl", (0, 1, 1, 0), 2, "back"
        a, b, c, d = L
        # f = A + L u, u = p - O ; A = (0, 4), O = (4, 4)
        e = 0 - (a * 4 + b * 4)
        ff = 4 - (c * 4 + d * 4)
        m = tuple(Fr(v) for v in (a, b, c, d, e, ff))
        st.append(dict(m=m, z=Fr(z), q=q, half=half, hist=[]))

    def pos(i):
        return apply(st[i]["m"], centroid(V, faces[i]))

    def fold(sel, line, toward):
        """Reflect faces `sel` across `line`, stacking them on the front
        (toward=+1) or back (toward=-1) of everything, order reversed."""
        R = reflect_line(*[(Fr(p[0]), Fr(p[1])) for p in line])
        zs = [st[i]["z"] for i in sel]
        allz = [s["z"] for s in st]
        if toward > 0:
            top, ztopS = max(allz), max(zs)
            for i in sel:
                st[i]["z"] = top + 1 + (ztopS - st[i]["z"])
        else:
            bot, zbotS = min(allz), min(zs)
            for i in sel:
                st[i]["z"] = bot - 1 - (st[i]["z"] - zbotS)
        for i in sel:
            st[i]["m"] = compose(R, st[i]["m"])

    n = len(faces)
    flaps = {}
    if stage < 2:
        return st, flaps, pos, fold
    # step 2: corners up. Front: right corner (Y < X) of N-right + Eu;
    # left corner (Y < -X) of N-left + Wu. Back: El + S-right, Wl + S-left.
    for half, toward in (("front", +1), ("back", -1)):
        selR = [i for i in range(n) if st[i]["half"] == half and pos(i)[0] > 0 and pos(i)[1] < pos(i)[0]]
        fold(selR, ((0, 0), (1, 1)), toward)
        for i in selR:
            st[i]["hist"].append("corner")
        selL = [i for i in range(n) if st[i]["half"] == half and pos(i)[0] < 0 and pos(i)[1] < -pos(i)[0]]
        fold(selL, ((0, 0), (-1, 1)), toward)
        for i in selL:
            st[i]["hist"].append("corner")
    if stage < 3:
        return st, flaps, pos, fold
    # step 3: side corners to the centre line: X = +-1 (1/8)
    for half, toward in (("front", +1), ("back", -1)):
        selR = [i for i in range(n) if st[i]["half"] == half and pos(i)[0] > 1]
        fold(selR, ((1, 0), (1, 1)), toward)
        for i in selR:
            st[i]["hist"].append("side")
        selL = [i for i in range(n) if st[i]["half"] == half and pos(i)[0] < -1]
        fold(selL, ((-1, 0), (-1, 1)), toward)
        for i in selL:
            st[i]["hist"].append("side")
    # step 4: top flaps (the corner layers above the side triangles' top edge)
    # down along Y = X + 2 (right) / Y = -X + 2 (left)
    if stage < 4:
        return st, flaps, pos, fold
    for half, toward in (("front", +1), ("back", -1)):
        selR = [i for i in range(n) if st[i]["half"] == half and "corner" in st[i]["hist"]
                and "side" not in st[i]["hist"] and pos(i)[0] > 0 and pos(i)[1] > pos(i)[0] + 2]
        fold(selR, ((0, 2), (1, 3)), toward)
        selL = [i for i in range(n) if st[i]["half"] == half and "corner" in st[i]["hist"]
                and "side" not in st[i]["hist"] and pos(i)[0] < 0 and pos(i)[1] > -pos(i)[0] + 2]
        fold(selL, ((0, 2), (-1, 3)), toward)
        for i in selR + selL:
            st[i]["hist"].append("flap")
        flaps[(half, "R")] = selR
        flaps[(half, "L")] = selL
    return st, flaps, pos, fold


def tuck(V, faces, st, flaps, pos):
    """Step 5: move each top flap from on top of its side triangle into the
    pocket between the side triangle's layers 3' and 2', wrapping the part
    that overhangs X = +-1 round the side triangle's outer fold so that it
    lands between the unfolded layers 2 and 3 underneath.

    Heights are assigned explicitly, from the layers named in the header:
      side triangle, front to back: 4' 3' 2' 1'   then   1 2 3 4
      (1 = Eu corner, 2 = N corner, 3 = N upper, 4 = Eu upper)
    The flap's own two layers: 2f above 1f in the pocket; round the wrap the
    order reverses, so the tip has 1f above 2f.
    """
    n = len(faces)
    for (half, side), sel in flaps.items():
        sgn = 1 if side == "R" else -1
        toward = 1 if half == "front" else -1

        def layer_of(i):
            q = st[i]["q"]
            h = st[i]["hist"]
            # 1: E/W corner, 2: N/S corner, 3: N/S upper, 4: E/W upper
            ew = q in ("Eu", "El", "Wu", "Wl")
            if "corner" in h:
                return 1 if ew else 2
            return 4 if ew else 3

        def side_region(i):
            X, Y = pos(i)
            return st[i]["half"] == half and sgn * X > 0

        tri = [i for i in range(n) if side_region(i) and "side" in st[i]["hist"]]
        und = [i for i in range(n) if side_region(i) and "side" not in st[i]["hist"]
               and "flap" not in st[i]["hist"]]
        z3p = [st[i]["z"] for i in tri if layer_of(i) == 3]
        z2p = [st[i]["z"] for i in tri if layer_of(i) == 2]
        z2 = [st[i]["z"] for i in und if layer_of(i) == 2]
        z3 = [st[i]["z"] for i in und if layer_of(i) == 3]
        # pocket between 3' and 2' (in the stacking direction `toward`)
        if toward > 0:
            lo_main, hi_main = max(z2p), min(z3p)
            lo_tip, hi_tip = max(z3), min(z2)
        else:
            lo_main, hi_main = max(z3p), min(z2p)
            lo_tip, hi_tip = max(z2), min(z3)
        assert lo_main < hi_main and lo_tip < hi_tip, (half, side, lo_main, hi_main, lo_tip, hi_tip)
        # the part overhanging the side triangle wraps round X = +-1
        R = reflect_line((Fr(sgn), Fr(0)), (Fr(sgn), Fr(1)))
        for i in sel:
            X, Y = pos(i)
            L = layer_of(i)  # 1 or 2
            if sgn * X > 1:
                st[i]["m"] = compose(R, st[i]["m"])
                st[i]["hist"].append("tip")
                # tip: 1f nearer the front-of-stack side than 2f
                if toward > 0:
                    st[i]["z"] = lo_tip + (hi_tip - lo_tip) * (Fr(2, 3) if L == 1 else Fr(1, 3))
                else:
                    st[i]["z"] = hi_tip - (hi_tip - lo_tip) * (Fr(2, 3) if L == 1 else Fr(1, 3))
            else:
                if toward > 0:
                    st[i]["z"] = lo_main + (hi_main - lo_main) * (Fr(2, 3) if L == 2 else Fr(1, 3))
                else:
                    st[i]["z"] = hi_main - (hi_main - lo_main) * (Fr(2, 3) if L == 2 else Fr(1, 3))
            st[i]["hist"].append("tucked")


def assignments(V, E, faces, st):
    """For each edge: 'B' on the boundary, else F/M/V from the final state."""
    idx = {v: i for i, v in enumerate(V)}
    owner = {}
    for fi, f in enumerate(faces):
        for k in range(len(f)):
            owner[(f[k], f[(k + 1) % len(f)])] = fi
    asg, ang = [], []
    for (p, q) in E:
        a, b = idx[p], idx[q]
        f1 = owner.get((a, b))
        f2 = owner.get((b, a))
        if f1 is None or f2 is None:
            asg.append("B")
            ang.append(0)
            continue
        m1, m2 = st[f1]["m"], st[f2]["m"]
        if m1 == m2:
            asg.append("F")
            ang.append(0)
            continue
        above = st[f2]["z"] > st[f1]["z"]
        valley = above == (det(m1) > 0)
        # consistency from the other face
        above2 = st[f1]["z"] > st[f2]["z"]
        valley2 = above2 == (det(m2) > 0)
        assert valley == valley2, ("inconsistent", p, q)
        asg.append("V" if valley else "M")
        ang.append(180 if valley else -180)
    return asg, ang


def build(stage=5):
    """stage 1..5: the state after that step (5 = tucked balloon). Creases
    of later steps are kept in the pattern as flat (F) lines."""
    segs = all_segments()
    E, pts = split_segments(segs)
    V = sorted(pts)
    faces = trace_faces(V, E)
    st, flaps, pos, fold = simulate(V, faces, stage)
    if stage >= 5:
        tuck(V, faces, st, flaps, pos)
    asg, ang = assignments(V, E, faces, st)
    return V, E, faces, st, asg, ang


def write_fold(path, V, E, asg, ang, title, desc):
    idx = {v: i for i, v in enumerate(V)}
    doc = {
        "file_spec": 1.2,
        "file_creator": "Y5-waterbomb experiment (constructed here, own geometry)",
        "file_title": title,
        "frame_classes": ["creasePattern"],
        "frame_attributes": ["2D"],
        "frame_unit": "unit",
        "frame_description": desc,
        "vertices_coords": [[float(x) / S, float(y) / S] for (x, y) in V],
        "edges_vertices": [[idx[p], idx[q]] for (p, q) in E],
        "edges_assignment": asg,
        "edges_foldAngle": ang,
    }
    with open(path, "w") as fh:
        json.dump(doc, fh, indent=1)


if __name__ == "__main__":
    out = sys.argv[1]
    stage = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    V, E, faces, st, asg, ang = build(stage)
    from collections import Counter
    print("vertices", len(V), "edges", len(E), "faces", len(faces))
    print("assignments", Counter(asg))
    if stage < 5:
        write_fold(out, V, E, asg, ang, f"Water-bomb balloon, state after step {stage}",
                   f"State after step {stage} of the traditional water-bomb sequence (see wbcp.py). "
                   "Creases of later steps are present as flat lines. Constructed here.")
        sys.exit(0)
    write_fold(out, V, E, asg, ang, "Water-bomb balloon (flat, tucked)",
               "Traditional water-bomb balloon, flat-folded with both pairs of top flaps tucked. "
               "Derived by simulating the traditional sequence on the sheet; assignments read "
               "from the simulated final state. Constructed here, no copied data.")
    # also dump the simulated state for comparison with the solver's orders
    sim = [dict(face=[int(v) for v in faces[i]], z=float(st[i]["z"]), det=int(det(st[i]["m"])),
                m=[float(v) for v in st[i]["m"]], q=st[i]["q"], hist=st[i]["hist"])
           for i in range(len(faces))]
    with open(out.replace(".fold", "-sim.json"), "w") as fh:
        json.dump(dict(V=[[float(x) / S, float(y) / S] for x, y in V], faces=sim), fh)
