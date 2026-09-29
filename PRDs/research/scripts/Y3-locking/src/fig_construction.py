import json
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

import draw
import sil

OUT = sys.argv[1]
IMG = sys.argv[2]
z = np.load(f"{OUT}/construction.npz", allow_pickle=True)
res = json.load(open(f"{OUT}/construction.json"))
names = ["original", "flipped", "refined1", "refined2"]
labels = {"original": "study mesh (448 tri)", "flipped": "J diagonals flipped", "refined1": "refined x1 (1,792 tri)",
          "refined2": "refined x2 (7,168 tri)"}

fig, axes = plt.subplots(1, 4, figsize=(16, 4.4), dpi=150)
for ax, n in zip(axes, names):
    UV, F, H, kind, ang, anch = (z[f"{n}__{k}"] for k in ("UV", "F", "H", "kind", "ang", "anchored"))
    r = res[n]
    draw.bend_map(ax, UV, F, H, kind, ang, anchored=anch,
                  title=f"{labels[n]}\nJ>45°: {r['J_over_45']}  J>20°: {r['J_over_20']}  max J {r['J_max_deg']:.0f}°")
fig.suptitle("Construction of 'More tucked' (spread-0) rerun on other meshes, material space. "
             "Red: join bent >45°, orange >20°, blue lines: M/V creases, dots: anchors", fontsize=9, y=0.995)
fig.tight_layout(rect=(0, 0, 1, 0.93))
fig.savefig(f"{IMG}/construction-bendmaps.png")

# 3D: same camera, original vs refined2
view = sil.basis((-1.0, -1.2, 0.8), (0, -1, 0))  # fixture: negative y is up
fig, axes = plt.subplots(1, 2, figsize=(12, 6), dpi=150)
lim = None
for ax, n in zip(axes, ["original", "refined2"]):
    X, F, H, kind, ang = (z[f"{n}__{k}"] for k in ("X", "F", "H", "kind", "ang"))
    Jm = np.isin(kind, ["J", "F"])
    b = np.where(Jm, ang, 0)
    lim = draw.shaded(ax, X, F, view, H=H, bend=b, lim=lim)
    ax.set_title(f"{labels[n]}: construction output, joins >45° red, >20° orange", fontsize=9)
fig.tight_layout()
fig.savefig(f"{IMG}/construction-3d.png")
print("ok")
