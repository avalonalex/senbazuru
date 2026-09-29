"""Which side of the paper faces which gap in the flat water bomb.

usage: cavity.py SIM.json FOLDED.fold CP.fold

For points on a fine grid over the folded model, list the layers top to
bottom and classify every gap between consecutive layers (plus the air above
the top layer and below the bottom one) by the two paper sides facing it:
  top|top        both sides are the sheet's top side (the side the crease
                 pattern is drawn on)
  bot|bot        both are the bottom side
  mixed          one of each
If the sheet is a bag whose inside is its top side, every internal gap is
top|top or bot|bot, and the outside air (above and below the stack) touches
only bottom sides.
"""
import json
import sys
from collections import Counter

from compare import load, signed_area
from stackat import inside, layer_name


def main():
    sim, fo, fmap = load(sys.argv[1], sys.argv[2])
    cp = json.load(open(sys.argv[3]))
    C = cp["vertices_coords"]
    X = fo["vertices_coords"]
    F = fo["faces_vertices"]
    # does the top side of face i face +z in the folded state?
    topup = []
    for f in F:
        a_cp = signed_area([C[v] for v in f])
        a_fo = signed_area([X[v] for v in f])
        topup.append((a_cp > 0) == (a_fo > 0))
    rel = {}
    for (f, g, s) in fo["faceOrders"]:
        nz = 1 if signed_area([X[v] for v in F[g]]) > 0 else -1
        up = (s > 0) == (nz > 0)
        rel[(f, g)] = up
        rel[(g, f)] = not up
    xs = [p[0] for p in X]
    ys = [p[1] for p in X]
    n = 60
    counts = Counter()
    outer = Counter()
    mixed_where = []
    npts = 0
    for i in range(n + 1):
        for j in range(n + 1):
            q = (min(xs) + (max(xs) - min(xs)) * (i + 0.5) / (n + 1),
                 min(ys) + (max(ys) - min(ys)) * (j + 0.5) / (n + 1))
            here = [k for k, f in enumerate(F) if inside([X[v] for v in f], q)]
            if not here:
                continue
            npts += 1
            # sort top to bottom: count how many faces each is above
            snap = list(here)  # list.sort empties the list while it runs
            here.sort(key=lambda k: -sum(1 for m in snap if m != k and rel.get((k, m), False)))
            sides_up = ["top" if topup[k] else "bot" for k in here]      # side facing +z
            sides_dn = ["bot" if topup[k] else "top" for k in here]      # side facing -z
            outer[("above", sides_up[0])] += 1
            outer[("below", sides_dn[-1])] += 1
            for a in range(len(here) - 1):
                cls = (sides_dn[a], sides_up[a + 1])
                key = "top|top" if cls == ("top", "top") else "bot|bot" if cls == ("bot", "bot") else "mixed"
                counts[key] += 1
                if key == "mixed":
                    mixed_where.append((q, layer_name(sim["faces"][fmap[here[a]]]),
                                        layer_name(sim["faces"][fmap[here[a + 1]]])))
    print(f"grid points on the model: {npts}")
    print("internal gaps:", dict(counts))
    print("outside air touches:", dict(outer))
    for m in mixed_where[:10]:
        print("  mixed at", m)


if __name__ == "__main__":
    main()
