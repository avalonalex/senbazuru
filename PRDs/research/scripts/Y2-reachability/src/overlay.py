"""Upright-camera overlay of a projected pose on its sketch.

usage: overlay.py RUN_DIR LAM OUT.png [LEVELS]
Draws the sketch outline (red) and the projected pose (filled, blue outline)
at the gallery's upright camera, 600 px per sheet unit, painter-sorted
triangles shaded by their tilt, plus a second panel: per-vertex displacement
in the picture (px) on the material square.
"""
import sys, os, json
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np, mesh
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection, LineCollection

run, lam, out = sys.argv[1], float(sys.argv[2]), sys.argv[3]
meta = json.load(open(os.path.join(run, "sweep.json")))
G = os.path.join(os.path.dirname(__file__), "../../../gallery/whole-crane/")
m = mesh.load_fold(G + meta["model"] + ".fold")
for _ in range(meta["levels"]):
    m = mesh.subdivide(m)
X0 = m["X"]
row = min([r for r in meta["rows"] if r["lam"] is not None], key=lambda r: abs(np.log10(r["lam"]) - np.log10(lam)))
lam = row["lam"]
X = np.load(os.path.join(run, f"X_lam{lam:.0e}.npy"))
F = m["F"]
b = mesh.upright_basis()


def draw(ax, Xs, face, edge, alpha, lw, crease=True):
    P, depth = mesh.project(Xs, b)
    order = np.argsort(-depth[F].mean(1))
    n = np.cross(Xs[F[:, 1]] - Xs[F[:, 0]], Xs[F[:, 2]] - Xs[F[:, 0]])
    n /= np.linalg.norm(n, axis=1)[:, None]
    shade = 0.55 + 0.45 * np.abs(n @ b[2])
    base = np.array(matplotlib.colors.to_rgb(face))
    cols = np.clip(base[None, :] * shade[:, None], 0, 1)
    ax.add_collection(PolyCollection(P[F[order]] * 600, facecolors=cols[order], edgecolors="none", alpha=alpha))
    if crease:
        segs = [P[[i, j]] * 600 for (i, j), s in zip(m["edges"], m["eassign"]) if s in "MVB"]
        ax.add_collection(LineCollection(segs, colors=edge, linewidths=lw))
    return P


fig, axs = plt.subplots(1, 3, figsize=(21, 7), gridspec_kw=dict(width_ratios=[1, 1, 0.8]))
P0 = draw(axs[0], X0, "#eee6cf", "#b03030", 1.0, 0.5)
axs[0].set_title(f"{meta['model']} sketch (upright camera)\nmax strain {meta['rows'][0]['max_principal_strain']*100:.0f}%, {meta['rows'][0]['crossing_pairs']} crossing pairs")
P = draw(axs[1], X, "#dfe9f3", "#2a5caa", 1.0, 0.5)
# sketch outline on top of the projection
from scipy.ndimage import binary_erosion
allp = np.vstack([P0, P]); pad = 0.02
box = (allp[:, 0].min() - pad, allp[:, 1].min() - pad, allp[:, 0].max() + pad, allp[:, 1].max() + pad)
ppu = 1200
for Xs, c in ((X0, "#d02020"),):
    mk = mesh.raster(m, Xs, box, ppu, b)
    ol = mesh.outline(mk)
    jj, ii = np.nonzero(ol)
    axs[1].scatter((box[0] + (ii + 0.5) / ppu) * 600, (box[3] - (jj + 0.5) / ppu) * 600, s=0.15, c=c, lw=0)
axs[1].set_title(f"projected, pull {lam:.0e}: max strain {row['max_principal_strain']*100:.3g}%\n"
                 f"outline vs sketch (red dots): Hausdorff {row['sil_hausdorff_px']:.0f} px, mean {row['sil_mean_px']:.1f} px; "
                 f"{row['crossing_pairs']} crossings")
for ax in axs[:2]:
    ax.set_aspect("equal"); ax.set_xlim(box[0] * 600, box[2] * 600); ax.set_ylim(box[1] * 600, box[3] * 600)
    ax.set_xlabel("px (600 per sheet side)")
Pd = np.linalg.norm(P - P0, axis=1) * 600
U = m["U"]
tc = axs[2].tripcolor(U[:, 0], U[:, 1], F, Pd, shading="gouraud", cmap="magma_r", vmin=0, vmax=max(40, np.percentile(Pd, 99)))
segs = [U[[i, j]] for (i, j), s in zip(m["edges"], m["eassign"]) if s in "MV"]
axs[2].add_collection(LineCollection(segs, colors="k", linewidths=0.3))
axs[2].set_aspect("equal"); axs[2].set_title("movement in the picture per material point (px)\non the flat sheet; creases in black")
plt.colorbar(tc, ax=axs[2], fraction=0.046)
plt.tight_layout()
plt.savefig(out, dpi=90)
