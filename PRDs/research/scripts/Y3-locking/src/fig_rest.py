"""Figures for the wing, strip and sketch-relaxation experiments, and the contact sheet."""
import json
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection

import draw
import sheet as S
import sil

OUT, IMG, D = sys.argv[1], sys.argv[2], sys.argv[3]
which = sys.argv[4:] or ["wing", "strip", "sketch"]


def hinge_bends(X, F, UV, amap={}):
    H, rest, k, kind = S.build_hinges(F, UV, amap)
    return H, kind, np.degrees(np.abs(S.hinge_angles(X, H)))


if "wing" in which:
    f = S.load_fold(f"{D}/rigid.fold")
    amap = S.assignment_map(f)
    w = np.load(f"{OUT}/wing.npz")
    res = {(r["grip"], r["mesh"], float(r["w"])): r for r in json.load(open(f"{OUT}/wing.json"))["runs"]}
    import meshops as M
    F1, UV1, _, A1, _, _ = M.refine(f["F"], f["UV"], f["X"], amap, f["panels"])
    UVs = {"original": f["UV"], "flipped": f["UV"], "refined1": UV1}
    Am = {"original": amap, "flipped": amap, "refined1": A1}
    cols = [("original", 1e8), ("original", 4.3e6), ("flipped", 1e8), ("refined1", 1e8)]
    view = sil.basis((1, 0.45, 0.3), (0, 0, 1))
    fig, axes = plt.subplots(2, 4, figsize=(18, 8.5), dpi=130)
    for row, grip in enumerate(("arc20", "twist")):
        lim = None
        for ax, (mesh, wv) in zip(axes[row], cols):
            key = f"{grip}__{mesh}__{wv:.1e}"
            X = w[key]; F = w["F__" + key]
            if lim is None:
                Pw = X[X[:, 2] < -1e-6] @ view.T
                lo, hi = Pw.min(0), Pw.max(0)
                pad = 0.08 * (hi - lo).max()
                lim = (lo[0] - pad, hi[0] + pad, lo[1] - pad, hi[1] + pad)
            H, kind, bend = hinge_bends(X, F, UVs[mesh], Am[mesh])
            bj = np.where(np.isin(kind, ["J", "F"]), bend, 0)
            lim = draw.shaded(ax, X, F, view, H=H, bend=bj, lim=lim)
            r = res[(grip, mesh, wv)]["stats"]
            ax.set_title(f"{grip} · {mesh} · w={wv:.1e}\nJ>45°: {r['J_over_45']}  J>20°: {r['J_over_20']}  max J {r['J_max_deg']:.1f}°", fontsize=9)
    fig.suptitle("Held crane wing (--crane-spreading fixture), study energy, cropped to the wing, seen along the wing width. Top: the study's grip (+20° arc). "
                 "Bottom: a 30° twisted grip (locking provocation). Red: join >45°, orange >20°", fontsize=10)
    fig.tight_layout(rect=(0, 0, 1, 0.95))
    fig.savefig(f"{IMG}/wing.png")
    print("wing ok")

if "strip" in which:
    from run_strip_lib import strip_mesh
    z = np.load(f"{OUT}/strip.npz")
    zt = np.load(f"{OUT}/strip_tight.npz")
    rt = json.load(open(f"{OUT}/strip_tight.json"))
    r6 = json.load(open(f"{OUT}/strip.json"))
    panels = [("60°, cells '\\' along generators", z, "diag45_16_back_1.0e+08", 16, "back", 60),
              ("60°, cells '/' across generators", z, "diag45_16_fwd_1.0e+08", 16, "fwd", 60),
              ("180°, '\\' along", zt, "t180_16_back_1.0e+08", 16, "back", 180),
              ("180°, '/' across, w=1e8", zt, "t180_16_fwd_1.0e+08", 16, "fwd", 180),
              ("180°, '/' across, w=4.3e6", zt, "t180_16_fwd_4.3e+06", 16, "fwd", 180),
              ("180°, '/' across, refined (32)", zt, "t180_32_fwd_1.0e+08", 32, "fwd", 180)]
    fig, axes = plt.subplots(2, 6, figsize=(22, 6.5), dpi=120, gridspec_kw=dict(height_ratios=[1, 1.4]))
    for j, (title, zz, key, n, dd, turn) in enumerate(panels):
        UV, F, amap, nx = strip_mesh(n, "/" if dd == "fwd" else "\\")
        X = zz[key]
        H, kind, bend = hinge_bends(X, F, UV)
        ax = axes[0, j]
        seg = np.stack([UV[H[:, 0]], UV[H[:, 1]]], 1)
        lc = LineCollection(seg, cmap="magma_r", linewidths=2.0)
        lc.set_array(bend); lc.set_clim(0, 12)
        ax.add_collection(lc)
        ax.set_xlim(-0.02, 1.02); ax.set_ylim(-0.02, 0.27); ax.set_aspect("equal"); ax.set_xticks([]); ax.set_yticks([])
        ax.set_title(f"{title}\nmax join bend {bend.max():.1f}°", fontsize=8)
        ax2 = axes[1, j]
        v = sil.basis((0.3, -1, 0.6), (0, 0, 1))
        draw.shaded(ax2, X, F, v, H=H, bend=bend, thresholds=(8, 20))
    fig.colorbar(lc, ax=axes[0, :].tolist(), shrink=0.8, label="join bend (deg)")
    fig.suptitle("Positive control: held strip bent to an exact cylinder whose generators run at 45°. Top: join bends in material space (0-12° scale). "
                 "Bottom: 3D, joins >8° orange, >20° red", fontsize=10)
    fig.savefig(f"{IMG}/strip.png", bbox_inches="tight")
    print("strip ok")

if "sketch" in which:
    G = "../../../gallery/whole-crane"
    sr = np.load(f"{OUT}/sketch_relax.npz")
    js = json.load(open(f"{OUT}/sketch_relax.json"))
    zc = np.load(f"{OUT}/construction.npz", allow_pickle=True)
    Fo = sr["F_original"]
    UVo = zc["original__UV"]
    amap = {}
    import sheet as S2
    view = sil.basis((-1.0, -1.2, 0.8), (0, -1, 0))
    items = [("spread-0 as built (no solve)\nJ>45°: 15", zc["original__X"], Fo, UVo, zc["original__H"], zc["original__kind"])]
    for r in js:
        key = f"{r['mesh']}_{r['w']:.1e}"
        F = Fo if r["mesh"] == "original" else sr["F_refined1"]
        UV = UVo if r["mesh"] == "original" else sr["UV_refined1"]
        items.append((f"relaxed, anchors held\n{r['mesh']}, w={r['w']:.1e}, J>45°: {r['stats']['J_over_45']}", sr[key], F, UV, None, None))
    fig, axes = plt.subplots(1, len(items), figsize=(5 * len(items), 5.2), dpi=120)
    lim = None
    for ax, (title, X, F, UV, H, kind) in zip(axes, items):
        if H is None:
            b0 = S.load_fold(f"{G}/before.fold")
            am = S.assignment_map(b0)
            if len(UV) != len(b0["UV"]):
                import meshops as M
                _, _, _, am, _, _ = M.refine(b0["F"], b0["UV"], b0["X"], am, b0["panels"])
            H, _, _, kind = S.build_hinges(F, UV, am)
        bend = np.degrees(np.abs(S.hinge_angles(X, H)))
        bj = np.where(np.isin(kind, ["J", "F"]), bend, 0)
        lim = draw.shaded(ax, X, F, view, H=H, bend=bj, lim=lim)
        ax.set_title(title, fontsize=9)
    fig.subplots_adjust(top=0.86, left=0.01, right=0.99, bottom=0.01, wspace=0.05)
    fig.savefig(f"{IMG}/sketch-relax.png")
    print("sketch ok")
