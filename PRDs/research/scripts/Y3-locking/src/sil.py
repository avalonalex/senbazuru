"""Silhouette comparison at 600 px per sheet unit (the study's drawing scale).

A silhouette is the union of all projected triangles, rasterised with PIL.
Two numbers per pair: pixels that differ (XOR), and the Hausdorff distance
between the two filled regions in pixels (how far the outline moved at worst).
"""
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt

PX = 600.0


def basis(direction, up):
    d = np.asarray(direction, float); d /= np.linalg.norm(d)
    u = np.asarray(up, float); u = u - (u @ d) * d; u /= np.linalg.norm(u)
    r = np.cross(u, d)
    return np.stack([r, u])  # 2x3


VIEWS = {
    "study-camera": basis((-1, 1, np.sqrt(2)), (0, 0, 1)),
    "along-x": basis((1, 0, 0), (0, 0, 1)),
    "along-y": basis((0, 1, 0), (0, 0, 1)),
    "along-z": basis((0, 0, 1), (0, 1, 0)),
}


def masks(meshes, view, pad=8):
    B = VIEWS[view] if isinstance(view, str) else view
    P = [X @ B.T * PX for X, _ in meshes]
    lo = np.min([p.min(0) for p in P], axis=0) - pad
    hi = np.max([p.max(0) for p in P], axis=0) + pad
    W, Hh = (hi - lo).astype(int) + 1
    out = []
    for p, (_, F) in zip(P, meshes):
        img = Image.new("1", (int(W), int(Hh)), 0)
        dr = ImageDraw.Draw(img)
        q = p - lo
        for tri in F:
            dr.polygon([(q[i, 0], Hh - q[i, 1]) for i in tri], fill=1, outline=1)
        out.append(np.array(img, bool))
    return out


def compare(Xa, Fa, Xb, Fb, view):
    a, b = masks([(Xa, Fa), (Xb, Fb)], view)
    xor = int((a ^ b).sum())
    da = distance_transform_edt(~b)  # distance to b
    db = distance_transform_edt(~a)
    h = max(float(da[a].max()) if a.any() else 0.0, float(db[b].max()) if b.any() else 0.0)
    return xor, h


def compare_all(Xa, Fa, Xb, Fb, views=("study-camera", "along-x", "along-y", "along-z")):
    res = {v: compare(Xa, Fa, Xb, Fb, v) for v in views}
    return dict(max_hausdorff_px=max(h for _, h in res.values()),
                max_xor_px=max(x for x, _ in res.values()), per_view=res)
