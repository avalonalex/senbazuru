"""Displacement of the same piece of paper between two meshes of one sheet.

For every vertex of mesh B, find the triangle of mesh A that holds its
material coordinates and interpolate A's 3D positions there. The distance,
times 600 px per sheet unit, bounds how far that point of the drawing moves
in any orthographic view. Unlike a rasterised silhouette it is not fooled by
surfaces seen edge-on.
"""
import numpy as np

PX = 600.0


def locate(UVa, Fa, pts, eps=1e-9):
    a, b, c = UVa[Fa[:, 0]], UVa[Fa[:, 1]], UVa[Fa[:, 2]]
    v0 = b - a
    v1 = c - a
    den = v0[:, 0] * v1[:, 1] - v0[:, 1] * v1[:, 0]
    tri = np.full(len(pts), -1)
    bary = np.zeros((len(pts), 3))
    for s in range(0, len(pts), 256):
        p = pts[s:s + 256]
        d = p[:, None, :] - a[None]
        l1 = (d[..., 0] * v1[None, :, 1] - d[..., 1] * v1[None, :, 0]) / den[None]
        l2 = (v0[None, :, 0] * d[..., 1] - v0[None, :, 1] * d[..., 0]) / den[None]
        l0 = 1 - l1 - l2
        ok = (l0 >= -eps) & (l1 >= -eps) & (l2 >= -eps)
        # pick the triangle with the largest minimum barycentric (most inside)
        score = np.where(ok, np.minimum(np.minimum(l0, l1), l2), -np.inf)
        t = np.argmax(score, axis=1)
        good = np.isfinite(score[np.arange(len(p)), t])
        tri[s:s + 256] = np.where(good, t, -1)
        bary[s:s + 256] = np.stack([l0[np.arange(len(p)), t], l1[np.arange(len(p)), t], l2[np.arange(len(p)), t]], 1)
    return tri, bary


def material_displacement(Xa, UVa, Fa, Xb, UVb):
    tri, bary = locate(UVa, Fa, UVb)
    assert (tri >= 0).all(), "a material point of B is outside A"
    Pa = (bary[:, :, None] * Xa[Fa[tri]]).sum(axis=1)
    return np.linalg.norm(Pa - Xb, axis=1) * PX
