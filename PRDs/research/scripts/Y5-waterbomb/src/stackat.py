"""Print the stack of layers over sample points of a folded water bomb.

usage: stackat.py SIM.json FOLDED.fold [FOLDED2.fold ...]
Sample points are in the simulation's book coordinates (apex up), mapped to
the file's folded coordinates through the flat faces themselves.
"""
import json
import sys
from functools import cmp_to_key

from compare import load, signed_area


def inside(P, q):
    n = len(P)
    s = None
    for i in range(n):
        x1, y1 = P[i][:2]
        x2, y2 = P[(i + 1) % n][:2]
        c = (x2 - x1) * (q[1] - y1) - (y2 - y1) * (q[0] - x1)
        if abs(c) < 1e-12:
            return False
        if s is None:
            s = c > 0
        elif (c > 0) != s:
            return False
    return True


def sim_to_file_map(sim, fo, fmap):
    """Affine map from book coords to file coords, from one face's vertices."""
    import itertools
    V = sim["V"]
    X = fo["vertices_coords"]
    k = 0
    face = fo["faces_vertices"][k]
    m = sim["faces"][fmap[k]]["m"]  # book = m(sheet) in grid units (1/8)
    a, b, c, d, e, f = m

    def book(p):
        x, y = p[0] * 8, p[1] * 8
        return ((a * x + b * y + e) / 8, (c * x + d * y + f) / 8)
    src = [book(V[v]) for v in face[:3]]
    dst = [X[v][:2] for v in face[:3]]
    # solve dst = A src + t
    (x0, y0), (x1, y1), (x2, y2) = src
    (u0, v0), (u1, v1), (u2, v2) = dst
    det = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
    A11 = ((u1 - u0) * (y2 - y0) - (u2 - u0) * (y1 - y0)) / det
    A12 = ((u2 - u0) * (x1 - x0) - (u1 - u0) * (x2 - x0)) / det
    A21 = ((v1 - v0) * (y2 - y0) - (v2 - v0) * (y1 - y0)) / det
    A22 = ((v2 - v0) * (x1 - x0) - (v1 - v0) * (x2 - x0)) / det
    return lambda p: (A11 * (p[0] - x0) + A12 * (p[1] - y0) + u0,
                      A21 * (p[0] - x0) + A22 * (p[1] - y0) + v0)


def layer_name(fs):
    q, h = fs["q"], fs["hist"]
    ew = q in ("Eu", "El", "Wu", "Wl")
    base = ("1" if ew else "2") if "corner" in h else ("4" if ew else "3")
    tag = ""
    if "tip" in h:
        tag = "tip"
    elif "flap" in h:
        tag = "f"
    elif "side" in h:
        tag = "'"
    half = "F" if q in ("N", "Eu", "Wu") else "B"
    return f"{half}{base}{tag}"


def stack(sim, fo, fmap, q):
    X = fo["vertices_coords"]
    here = [i for i, f in enumerate(fo["faces_vertices"]) if inside([X[v] for v in f], q)]
    rel = {}
    for (f, g, s) in fo["faceOrders"]:
        P = [X[v] for v in fo["faces_vertices"][g]]
        nz = 1 if signed_area(P) > 0 else -1
        up = (s > 0) == (nz > 0)  # f above g in +z
        rel[(f, g)] = 1 if up else -1
        rel[(g, f)] = -1 if up else 1

    def cmp(a, b):
        return -rel.get((a, b), 0)
    here.sort(key=cmp_to_key(cmp))
    return [layer_name(sim["faces"][fmap[i]]) for i in here]


if __name__ == "__main__":
    pts = {"right side triangle, flap part (0.09,0.27)": (0.09, 0.27),
           "right side triangle, lower half (0.10,0.20)": (0.10, 0.20),
           "right, below side triangle (0.03,0.12)": (0.03, 0.12),
           "right, top (0.03,0.42)": (0.03, 0.42)}
    for path in sys.argv[2:]:
        sim, fo, fmap = load(sys.argv[1], path)
        T = sim_to_file_map(sim, fo, fmap)
        print(path)
        for name, p in pts.items():
            print(f"  {name:45s} top->bottom: {' '.join(stack(sim, fo, fmap, T(p)))}")
