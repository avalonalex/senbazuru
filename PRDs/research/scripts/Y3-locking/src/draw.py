"""Small drawing helpers: painter's-algorithm shaded mesh and material-space bend maps."""
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection, LineCollection

import sil


def shaded(ax, X, F, view, H=None, bend=None, light=(0.3, 0.5, 0.8), lim=None, thresholds=(20, 45)):
    B = sil.VIEWS[view] if isinstance(view, str) else view
    d = np.cross(B[0], B[1])  # towards viewer
    P = X @ B.T
    depth = X @ d
    tri = P[F]
    n = np.cross(X[F[:, 1]] - X[F[:, 0]], X[F[:, 2]] - X[F[:, 0]])
    n /= np.linalg.norm(n, axis=1)[:, None] + 1e-30
    front = (n @ d) >= 0
    L = np.asarray(light, float); L /= np.linalg.norm(L)
    lam = np.abs(n @ L)
    base_front = np.array([0.93, 0.90, 0.81])
    base_back = np.array([0.77, 0.52, 0.27])
    col = np.where(front[:, None], base_front, base_back) * (0.45 + 0.55 * lam[:, None])
    order = np.argsort(depth[F].mean(axis=1))
    ax.add_collection(PolyCollection(tri[order], facecolors=np.clip(col[order], 0, 1), edgecolors=(0, 0, 0, 0.12), linewidths=0.2))
    if H is not None and bend is not None:
        for thr, c, lw in ((thresholds[0], "#f0a020", 1.0), (thresholds[1], "#d01010", 2.0)):
            m = bend > thr
            seg = np.stack([P[H[m, 0]], P[H[m, 1]]], axis=1)
            ax.add_collection(LineCollection(seg, colors=c, linewidths=lw))
    if lim is None:
        lo, hi = P.min(0), P.max(0)
        pad = 0.04 * (hi - lo).max()
        lim = (lo[0] - pad, hi[0] + pad, lo[1] - pad, hi[1] + pad)
    ax.set_xlim(lim[0], lim[1]); ax.set_ylim(lim[2], lim[3])
    ax.set_aspect("equal"); ax.set_xticks([]); ax.set_yticks([])
    return lim


def bend_map(ax, UV, F, H, kind, bend, anchored=None, akind=None, title="", thresholds=(20, 45)):
    E = set()
    for i, j, k in F:
        for a, b in ((i, j), (j, k), (k, i)):
            E.add((min(a, b), max(a, b)))
    E = np.array(sorted(E))
    ax.add_collection(LineCollection(np.stack([UV[E[:, 0]], UV[E[:, 1]]], 1), colors=(0, 0, 0, 0.12), linewidths=0.3))
    cr = np.isin(kind, ["M", "V", "U"])
    ax.add_collection(LineCollection(np.stack([UV[H[cr, 0]], UV[H[cr, 1]]], 1), colors=(0.2, 0.3, 0.8, 0.45), linewidths=0.6))
    J = np.isin(kind, ["J", "F"])
    for thr, c, lw in ((thresholds[0], "#f0a020", 1.2), (thresholds[1], "#d01010", 2.4)):
        m = J & (bend > thr)
        ax.add_collection(LineCollection(np.stack([UV[H[m, 0]], UV[H[m, 1]]], 1), colors=c, linewidths=lw))
    if anchored is not None:
        if akind is not None:
            for kk, c in (("core", "#1060d0"), ("wingA", "#10a040"), ("wingB", "#10a040")):
                m = anchored & (akind == kk)
                ax.scatter(UV[m, 0], UV[m, 1], s=3, c=c, zorder=5)
        else:
            ax.scatter(UV[anchored, 0], UV[anchored, 1], s=3, c="#1060d0", zorder=5)
    ax.set_xlim(-0.02, 1.02); ax.set_ylim(-0.02, 1.02); ax.set_aspect("equal")
    ax.set_xticks([]); ax.set_yticks([])
    ax.set_title(title, fontsize=8)
