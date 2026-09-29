"""Trade-off curves: how far the picture moves against how much the paper strains."""
import json, os, glob
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

here = os.path.dirname(__file__)
bound = json.load(open(os.path.join(here, "../out/bound.json")))
runs = {os.path.basename(os.path.dirname(f)): json.load(open(f)) for f in glob.glob(os.path.join(here, "../out/*/sweep.json"))}

panels = [("spread-0", "More tucked (spread-0)"), ("narrow", "Narrower body (narrow)"), ("after", "First candidate (after)")]
chosen = [  # (run suffix, label, colour, style)
    ("all3d-kb0.001-L0", "3D pull, fixed bending 1e-3 (panels flatten), 448 tri", "#1f5fa8", "-"),
    ("all3d-kb0.001-L1", "same, 1792 tri", "#1f5fa8", ":"),
    ("plane-kb0.001-L0", "picture-plane pull (depth free), fixed bending", "#8a3fa0", "-"),
    ("all3d-kb0.001-L0-rel", "3D pull, bending 1e-3 x pull", "#2b8a3e", "-"),
    ("all3d-kb0.0001-L0-rel", "3D pull, bending 1e-4 x pull", "#e07b00", "-"),
    ("all3d-kb1e-05-L0-rel", "3D pull, bending 1e-5 x pull (false creases appear)", "#c0392b", "-"),
    ("all3d-kb0.0001-L1-rel", "bending 1e-4 x pull, 1792 tri", "#e07b00", ":"),
    ("all3d-kb1e-05-L1-rel", "bending 1e-5 x pull, 1792 tri", "#c0392b", ":"),
    ("all3d-kb0.0001-L0-rel-anch", "+ strong anchors: tips, body top (false creases)", "0.4", "--"),
]
fig, axs = plt.subplots(2, 3, figsize=(18, 10), sharex=True)
for col, (model, title) in enumerate(panels):
    for suffix, label, c, ls in chosen:
        key = f"{model}-{suffix}"
        if key not in runs:
            continue
        rows = [r for r in runs[key]["rows"][1:]]
        s = np.array([r["max_principal_strain"] for r in rows]) * 100
        for row, metric in enumerate(["sil_mean_px", "sil_hausdorff_px"]):
            y = np.array([r[metric] for r in rows])
            axs[row, col].plot(s, y, ls, color=c, marker="o", ms=3, label=label)
    lb = bound[f"{model}-L2"]["move_lb_picture_px"]
    for row in range(2):
        ax = axs[row, col]
        ax.set_xscale("log")
        ax.invert_xaxis()
        ax.axvline(1, color="0.5", lw=0.8); ax.axvline(0.1, color="0.5", lw=0.8)
        ax.axhline(5, color="k", lw=0.8, ls="--")
        ax.text(ax.get_xlim()[0] if False else 150, 5.5, "5 px", fontsize=8)
        ax.grid(alpha=0.3)
    axs[0, col].set_title(title)
    axs[1, col].axhline(lb, color="#b03030", lw=1.2, ls="-.")
    axs[1, col].text(150, lb * 1.03, f"proven for any paper state: some point of the picture moves >= {lb:.1f} px", color="#b03030", fontsize=8)
    axs[1, col].set_xlabel("largest principal strain anywhere on the sheet (%)  -> more paper-like")
axs[0, 0].set_ylabel("outline movement, mean (px at 600 px/sheet)")
axs[1, 0].set_ylabel("outline movement, Hausdorff (px)")
axs[0, 0].legend(fontsize=7, loc="upper left")
for ax in axs.ravel():
    ax.set_xlim(200, 1e-5)
plt.suptitle("Isometry projection toward each sketch at the gallery's upright camera: outline movement against strain", fontsize=13)
plt.tight_layout()
plt.savefig(os.path.join(here, "../img/tradeoff.png"), dpi=90)
print("ok")
