"""Contact sheet: Blender renders (sketch, ~1% strain, ~0.1% strain) per model, same camera per row."""
import json, os, sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.image as mpimg

here = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
spec = json.load(open(sys.argv[1]))
captions = json.load(open(sys.argv[2]))  # {render name: caption}
rows = spec["groups"]
ncol = max(len(g["states"]) for g in rows)
fig, axs = plt.subplots(len(rows), ncol, figsize=(6 * ncol, 5.2 * len(rows)))
axs = np.atleast_2d(axs)
for i, g in enumerate(rows):
    for j in range(ncol):
        ax = axs[i, j]; ax.axis("off")
        if j >= len(g["states"]):
            continue
        n = f"{g['name']}-{g['states'][j][0]}"
        p = os.path.join(here, "renders", n + ".png")
        if os.path.exists(p):
            ax.imshow(mpimg.imread(p))
        ax.set_title(captions.get(n, n), fontsize=10)
plt.suptitle(spec.get("title", ""), fontsize=13, y=0.995)
plt.tight_layout(rect=[0, 0, 1, 0.965])
plt.savefig(os.path.join(here, sys.argv[3]), dpi=80)
print("ok")
