"""Mark where smoothing created crossings, on a render from the same camera.

Usage: python overlay_cross.py SMOOTH_NPZ CONFIG.json RENDER.png OUT.png [label]
SMOOTH_NPZ is out/NAME-{cc,phong}.npz from smooth_test.py. The camera is
recomputed exactly as render_y1.py does it (same frame_with, forward, up,
axes and resolution), so the marks land on the render's pixels.
"""
import json, sys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, __file__.rsplit("/", 1)[0] + "/scripts")
import foldlayers as fl

snpz, cfgp, render, out = sys.argv[1:5]
label = sys.argv[5] if len(sys.argv) > 5 else ""
cfg = json.load(open(cfgp))
M = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], float) if cfg["axes"] == "crane" else np.eye(3)
tw = lambda p: np.asarray(p, float) @ M.T
f = tw(cfg["forward"]); f /= np.linalg.norm(f)
u = tw(cfg["up"])
r = np.cross(f, u); r /= np.linalg.norm(r)
tu = np.cross(r, f)
allv = np.vstack([tw(fl.load(p)[1]) for p in cfg["frame_with"]])
pr, pu = allv @ r, allv @ tu
rx, ry = cfg.get("res", [1200, 1000])
cx, cy = (pr.min() + pr.max()) / 2, (pu.min() + pu.max()) / 2
ortho = max(pr.max() - pr.min(), (pu.max() - pu.min()) * rx / ry) * 1.12
scale = rx / ortho

z = np.load(snpz)
Ps, cand, new = z["Ps"], z["cand"], z["new_cross"]
pts = []
for i, j in cand[new]:
    c = tw(np.vstack([Ps[i], Ps[j]]).mean(0))
    pts.append(((c @ r - cx) * scale + rx / 2, ry / 2 - (c @ tu - cy) * scale))
img = Image.open(render).convert("RGB")
d = ImageDraw.Draw(img)
for x, y in pts:
    d.ellipse([x - 5, y - 5, x + 5, y + 5], outline=(215, 30, 30), width=2)
d.text((12, 12), f"{label}  new crossing sub-triangle pairs: {len(pts)}", fill=(20, 20, 20))
img.save(out)
print(out, len(pts))
