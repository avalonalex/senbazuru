"""The 'S1' display mesh: X1's stacked-layer separation without Blender.

Every face in a coincident stack is moved gap * height along the stack
direction (heights from faceOrders, X1's foldlayers.stacks), vertices are
copied per height, and a flat wall ('bridge') joins the two copies of each
crease whose faces ended at different heights. Adapted from X1's
render.build_arrays (same experiment series, own code), returning FOLD
coordinates and triangles only.
"""
import os, sys
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "scripts"))
import foldlayers as fl


def s1_mesh(path, gap, bridges=True, kinds=("M", "V", "F", "B")):
    d, V, F = fl.load(path)
    st = fl.stacks(d, V, F)
    off = st["height"][:, None] * gap * st["direction"]
    key, verts, orig, faces = {}, [], [], []
    for fi, f in enumerate(F):
        nf = []
        for v in f:
            k = (v, tuple(np.round(off[fi], 12)))
            if k not in key:
                key[k] = len(verts); verts.append(V[v] + off[fi]); orig.append(v)
            nf.append(key[k])
        faces.append(nf)
    nb = 0
    nbase = len(faces)
    if bridges:
        by_edge = {}
        for fi, f in enumerate(F):
            for i in range(len(f)):
                a, b = f[i], f[(i + 1) % len(f)]
                by_edge.setdefault(frozenset((a, b)), []).append((a, faces[fi][i], b, faces[fi][(i + 1) % len(f)]))
        for ek, uses in by_edge.items():
            if len(uses) != 2:
                continue
            (a, a1, b, b1), (c, c2, e, e2) = uses
            second = {c: c2, e: e2}
            a2, b2 = second[a], second[b]
            ring = [a1, b1] + ([b2] if b2 != b1 else []) + ([a2] if a2 != a1 else [])
            if len(ring) >= 3:
                faces.append(ring); nb += 1
    assign = {frozenset(map(int, e)): s for e, s in zip(d["edges_vertices"], d["edges_assignment"])}
    tris, tparent = [], []
    for pi, f in enumerate(faces):
        for i in range(1, len(f) - 1):
            tris.append((f[0], f[i], f[i + 1])); tparent.append(pi)
    tris = np.array(tris)
    sharp = set()
    # every edge of a bridge wall is a fold: the wall stands in for paper wrapping round it
    for f in faces[nbase:]:
        for i in range(len(f)):
            sharp.add(frozenset((f[i], f[(i + 1) % len(f)])))
    for t in tris:
        for k in range(3):
            a, b = int(t[k]), int(t[(k + 1) % 3])
            if assign.get(frozenset((orig[a], orig[b]))) in kinds:
                sharp.add(frozenset((a, b)))
    return np.array(verts), tris, sharp, dict(bridges=nb, polygons=len(faces), max_height=int(st["max_height"]),
                                              faces_in_stacks=st["faces_in_stacks"], orig=np.array(orig))
