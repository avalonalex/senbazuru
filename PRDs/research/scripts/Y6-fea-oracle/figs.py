"""Figures for Y6 (own code): mid-section profiles against X2, and per-run maps.

usage: python figs.py RUN [RUN ...]
  img/profiles.png : section y = 0.5 (rest coordinates) of the top sheet, CalculiX runs vs X2
  img/maps.png     : per run, compression 1 - lambda_min and wrinkle residual z - smooth(z), top view
"""

import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.collections import PolyCollection

runs = sys.argv[1:]
X2 = "../X2-inflation/out/"
x2 = [("teabag-tension-r24-ks1000-kb0.0001", "X2 tension-field kb=1e-4", "k:"),
      ("teabag-tension-r24-ks1000-kb0.001", "X2 tension-field kb=1e-3", "k-"),
      ("teabag-full-r24-ks1000-kb0.001", "X2 plain membrane kb=1e-3", "k--")]


def section(x, rest, tol=1e-9):
    sel = (np.abs(rest[:, 1] - 0.5) < tol) & (x[:, 2] >= -1e-9)
    o = np.argsort(rest[sel, 0])
    return x[sel][o]


fig, ax = plt.subplots(figsize=(7.5, 3.6))
for name, lab, sty in x2:
    d = np.load(X2 + name + ".npz")
    s = section(d["x"], d["rest2"])
    x0, z0 = (s[0, 0] + s[-1, 0]) / 2, (s[0, 2] + s[-1, 2]) / 2  # rim ends of the section
    ax.plot(s[:, 0] - x0, s[:, 2] - z0, sty, lw=1.3, label=lab)
cols = plt.rcParams["axes.prop_cycle"].by_key()["color"]
for i, r in enumerate(runs):
    d = np.load(f"runs/{r}.npz")
    m = np.load(f"runs/{r}.mesh.npz")
    s = section(d["top"], m["X"][:, :2])
    ax.plot(s[:, 0] - 0.5, s[:, 2], "-", color=cols[i % len(cols)], lw=1.6, label=f"CalculiX {r}")
ax.set_aspect("equal")
ax.set_xlabel("x (sheet side = 1)")
ax.set_ylabel("height of top sheet")
ax.set_title("Tea bag, section through the middle (rest y = 0.5); X2 z shifted so its rim is at 0", fontsize=9)
ax.legend(fontsize=6.5, loc="upper right", ncol=1, frameon=False)
ax.set_ylim(-0.02, 0.4)
fig.tight_layout()
fig.savefig("img/profiles.png", dpi=150)

# maps
n = len(runs)
fig, axs = plt.subplots(2, n, figsize=(2.6 * n, 5.4), squeeze=False)
for j, r in enumerate(runs):
    d = np.load(f"runs/{r}.npz")
    m = np.load(f"runs/{r}.mesh.npz")
    P0, tri, top = m["X"][:, :2], d["tri"], d["top"]
    lam = d["lam"]
    comp = 1 - lam[:, 0]
    pc = PolyCollection(P0[tri], array=comp, cmap="magma_r", edgecolors="none")
    pc.set_clim(0, 0.2)
    axs[0, j].add_collection(pc)
    axs[0, j].set_title(r.replace("-", " "), fontsize=7)
    k = int(round(np.sqrt(len(P0)))) - 1
    Z = top[:, 2].reshape(k + 1, k + 1)
    Zp = np.pad(Z, 2, mode="edge")
    from numpy.lib.stride_tricks import sliding_window_view

    R = Z - sliding_window_view(Zp, (5, 5)).mean(axis=(2, 3))
    im = axs[1, j].imshow(R, origin="lower", extent=(0, 1, 0, 1), cmap="coolwarm", vmin=-0.01, vmax=0.01)
    for a in axs[:, j]:
        a.set_xlim(0, 1)
        a.set_ylim(0, 1)
        a.set_aspect("equal")
        a.set_xticks([])
        a.set_yticks([])
axs[0, 0].set_ylabel("compression 1-lambda_min\n(0 to 0.2)", fontsize=7)
axs[1, 0].set_ylabel("z minus 5x5 mean\n(-0.01 to 0.01)", fontsize=7)
fig.tight_layout()
fig.savefig("img/maps.png", dpi=130)
print("wrote img/profiles.png img/maps.png")
