"""Experiment C1: rerun the spread-0 construction on flipped and refined meshes.

If the construction's false creases were a mesh artefact they would move or
shrink when the triangulation changes; if the construction makes them, they
stay at the same material places with the same size.
"""
import json
import sys
import numpy as np

import sheet as S
import anchors as A
import construct as C
import meshops as M

G = sys.argv[1]
OUT = sys.argv[2]

m = S.load_fold(f"{G}/spread-0.fold")
b = S.load_fold(f"{G}/before.fold")
amap = S.assignment_map(b)
core, wing, wa, wb = A.find_anchors(m["X"], m["UV"], b["X"])
reg = C.panel_regions(b["F"], b["panels"], core, wa, wb)


def build(F, UV, Xb, panels, amap):
    mem = C.memberships(F, panels, reg, len(UV))
    T, kind = C.anchor_targets(UV, Xb, mem)
    X = C.continue_displacements(UV, F, Xb, T)
    H, rest, k, hk = S.build_hinges(F, UV, amap)
    st = S.stats(X, UV, F, H, hk, rest)
    ang = np.degrees(np.abs(S.hinge_angles(X, H)))
    anchored = ~np.isnan(T[:, 0])
    return X, T, kind, H, hk, ang, st, anchored


results = {}
variants = {}
# original
variants["original"] = (b["F"], b["UV"], b["X"], b["panels"], amap)
# flipped (two different greedy orders to show the order does not matter)
for name, order in (("flipped", None), ("flipped-rev", "rev")):
    joins = None
    Ff, Pf, nflip, nj = M.flip_joins(b["F"], b["UV"], amap, b["panels"],
                                    order=None if order is None else list(range(408))[::-1])
    variants[name] = (Ff, b["UV"], b["X"], Pf, amap)
    results.setdefault("flips", {})[name] = dict(flipped=nflip, joins=nj)
# refined once and twice
F1, UV1, X1, A1, P1, par1 = M.refine(b["F"], b["UV"], b["X"], amap, b["panels"])
variants["refined1"] = (F1, UV1, X1, P1, A1)
F2, UV2, X2, A2, P2, par2 = M.refine(F1, UV1, X1, A1, P1)
variants["refined2"] = (F2, UV2, X2, P2, A2)

saved = {}
for name, (F, UV, Xb, P, am) in variants.items():
    X, T, kind, H, hk, ang, st, anchored = build(F, UV, Xb, P, am)
    st["vertices"] = int(len(UV)); st["triangles"] = int(len(F)); st["anchored"] = int(anchored.sum())
    # where are the big join bends: sample the hinge edge midpoint in material space
    J = hk == "J"
    big = J & (ang > 45)
    mids = (UV[H[:, 0]] + UV[H[:, 1]]) / 2
    st["J_over_45_material_midpoints"] = mids[big].round(4).tolist()
    st["J_over_45_angles"] = ang[big].round(1).tolist()
    # hinges touching an anchored vertex
    touch = anchored[H].any(axis=1)
    st["J_over_45_touching_anchor"] = int((big & touch).sum())
    # F (flat crease) bends as well
    Fk = hk == "F"
    st["F_over_45"] = int((Fk & (ang > 45)).sum()); st["F_max_deg"] = float(ang[Fk].max())
    results[name] = st
    saved[name] = dict(X=X, UV=UV, F=F, H=H, kind=hk, ang=ang, anchored=anchored, P=P)
    print(name, {k: v for k, v in st.items() if not isinstance(v, list)})

json.dump(results, open(f"{OUT}/construction.json", "w"), indent=1)
np.savez_compressed(f"{OUT}/construction.npz", **{f"{n}__{k}": v for n, d in saved.items() for k, v in d.items()})
