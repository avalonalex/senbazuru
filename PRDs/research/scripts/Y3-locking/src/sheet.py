"""Mesh, hinge, strain and silhouette tools for the Y3 locking experiment.

Own code. The energy mirrors the study's (FoldRelaxation / FoldBending), read
from the MIT repository's source, re-expressed here:

  E = w * sum_edges (l - l0)^2  +  sum_hinges k_h * wrap(theta_h - rest_h)^2

  k_h = B * 2 * len^2 / (twice area of both triangles)   for a join (J) or flat (F) hinge
  k_h = 1 * len                                           for a crease hinge
  rest: M -> -pi, V -> +pi, F/U/J -> 0.   B = 0.2 in every crane fixture.
"""
import json
import numpy as np

B_PANEL = 0.2
K_CREASE = 1.0


def load_fold(path):
    d = json.load(open(path))
    m = dict(
        X=np.array(d["vertices_coords"], float),
        UV=np.array(d["senbazuru:material_coords"], float),
        F=np.array(d["faces_vertices"], int),
        E=np.array(d["edges_vertices"], int),
        A=list(d["edges_assignment"]),
        panels=np.array(d.get("senbazuru:source_panels", [0] * len(d["faces_vertices"])), int),
    )
    return m


def edge_key(a, b):
    return (a, b) if a < b else (b, a)


def assignment_map(m):
    return {edge_key(int(a), int(b)): s for (a, b), s in zip(m["E"], m["A"])}


def build_hinges(F, UV, amap, B=B_PANEL, kc=K_CREASE):
    """Return arrays (a,b,c,d), rest, stiffness, kind for every interior edge.
    Triangles are wound consistently (counterclockwise in material space)."""
    inc = {}
    for t, (i, j, k) in enumerate(F):
        for a, b, c in ((i, j, k), (j, k, i), (k, i, j)):
            inc.setdefault(edge_key(a, b), []).append((a, b, c))
    H, rest, stiff, kind = [], [], [], []
    for key, lst in inc.items():
        if len(lst) != 2:
            continue
        (a, b, c), (b2, a2, d) = lst
        if not (a == a2 and b == b2):
            raise ValueError(f"inconsistent winding at {key}")
        s = amap.get(key, "J")
        ma, mb, mc, md = (np.append(UV[v], 0.0) for v in (a, b, c, d))
        e = mb - ma
        ln = np.linalg.norm(e)
        twice = np.linalg.norm(np.cross(e, mc - ma)) + np.linalg.norm(np.cross(e, md - ma))
        if s in ("J", "F"):
            # The study treats flat (F) creases as panel bends with rest 0
            # (checked against checks.json stiffnesses for all 660 hinges).
            k, r = B * 2 * ln * ln / twice, 0.0
        else:
            k = kc * ln
            r = -np.pi if s == "M" else (np.pi if s == "V" else 0.0)
        H.append((a, b, c, d)); rest.append(r); stiff.append(k); kind.append(s)
    return np.array(H, int), np.array(rest), np.array(stiff), np.array(kind)


def hinge_angles(X, H, grad=False):
    """Signed dihedral angle, same convention as FoldBending.hingeAngle.
    With grad=True also return d(theta)/d(x) for the 4 corners, shape (h,4,3)."""
    pa, pb, pc, pd = (X[H[:, i]] for i in range(4))
    e = pb - pa
    ln = np.linalg.norm(e, axis=1)
    nL = np.cross(e, pc - pa)
    nR = np.cross(pd - pa, e)
    nl = np.linalg.norm(nL, axis=1)
    nr = np.linalg.norm(nR, axis=1)
    uL = nL / nl[:, None]
    uR = nR / nr[:, None]
    ang = -np.arctan2(np.einsum("ij,ij->i", e / ln[:, None], np.cross(uL, uR)), np.einsum("ij,ij->i", uL, uR))
    if not grad:
        return ang
    gc = (ln / nl**2)[:, None] * nL
    gd = (ln / nr**2)[:, None] * nR
    alc = np.einsum("ij,ij->i", pc - pa, e) / ln**2
    ald = np.einsum("ij,ij->i", pd - pa, e) / ln**2
    gb = -alc[:, None] * gc - ald[:, None] * gd
    ga = -(gb + gc + gd)
    return ang, np.stack([ga, gb, gc, gd], axis=1)


def wrap(x):
    return np.arctan2(np.sin(x), np.cos(x))


def mesh_edges(F):
    s = set()
    for i, j, k in F:
        for a, b in ((i, j), (j, k), (k, i)):
            s.add(edge_key(int(a), int(b)))
    return np.array(sorted(s), int)


def edge_rest(UV, Ed):
    return np.linalg.norm(UV[Ed[:, 0]] - UV[Ed[:, 1]], axis=1)


def principal_strains(X, UV, F):
    """Singular values of the 3x2 deformation gradient minus 1, per triangle."""
    p0, p1, p2 = (X[F[:, i]] for i in range(3))
    u0, u1, u2 = (UV[F[:, i]] for i in range(3))
    Dx = np.stack([p1 - p0, p2 - p0], axis=2)  # (t,3,2)
    Du = np.stack([u1 - u0, u2 - u0], axis=2)  # (t,2,2)
    Fg = Dx @ np.linalg.inv(Du)
    s = np.linalg.svd(Fg, compute_uv=False)
    return s[:, 1] - 1.0, s[:, 0] - 1.0  # (min, max)


def material_areas(UV, F):
    u0, u1, u2 = (UV[F[:, i]] for i in range(3))
    a = u1 - u0
    b = u2 - u0
    return 0.5 * np.abs(a[:, 0] * b[:, 1] - a[:, 1] * b[:, 0])


def stats(X, UV, F, H, kind, rest=None, Ed=None):
    ang = hinge_angles(X, H)
    J = kind == "J"
    bendJ = np.degrees(np.abs(ang[J]))
    if Ed is None:
        Ed = mesh_edges(F)
    l0 = edge_rest(UV, Ed)
    l = np.linalg.norm(X[Ed[:, 0]] - X[Ed[:, 1]], axis=1)
    emin, emax = principal_strains(X, UV, F)
    area = material_areas(UV, F)
    worst = np.maximum(np.abs(emin), np.abs(emax))
    out = dict(
        J_edges=int(J.sum()),
        J_over_45=int((bendJ > 45).sum()),
        J_over_20=int((bendJ > 20).sum()),
        J_max_deg=float(bendJ.max()),
        J_mean_deg=float(bendJ.mean()),
        max_rel_edge_error=float(np.max(np.abs(l - l0) / l0)),
        max_stretch=float(emax.max()),
        min_squash=float(emin.min()),
        area_strained_over_10pct=float(area[worst > 0.10].sum() / area.sum()),
        area_strained_over_1pct=float(area[worst > 0.01].sum() / area.sum()),
    )
    if rest is not None:
        C = kind != "J"
        err = np.degrees(np.abs(wrap(ang[C] - rest[C])))
        out["crease_err_max_deg"] = float(err.max())
    return out
