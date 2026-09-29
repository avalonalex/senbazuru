import json, glob, numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection

def L(p):
    d = np.load(p); return d

# exact Mylar profile: z(x) = int_x^r t^2/sqrt(r^4-t^4) dt, r = a/1.3110287771
r = 1 / 1.3110287771
xs = np.linspace(0, r, 400)
def zex(x):
    t = np.linspace(x, r, 20001)[:-1]
    f = t**2 / np.sqrt(r**4 - t**4)
    return np.trapz(f, t) + 0.0  # integrable end singularity; truncated
# better: substitute t = r sin^(1/2)... use high-res with endpoint correction
from math import pi
def zex2(x):
    # t = r*s, z = r * int_{x/r}^1 s^2/sqrt(1-s^4) ds ; substitute s = 1 - u^2 near 1
    s0 = x / r
    u0 = np.sqrt(max(1 - s0, 0))
    u = np.linspace(0, u0, 4001)
    s = 1 - u**2
    f = s**2 / np.sqrt((1 + s) * (1 + s**2) * np.maximum(u**2, 1e-300)) * 2 * u  # ds = -2u du; 1-s^4=(1-s)(1+s)(1+s^2), 1-s=u^2
    f[0] = 2 * 1 / np.sqrt(2 * 2)  # limit u->0: s=1 -> 2/sqrt(4)=1
    return r * np.trapz(f, u)
zx = np.array([zex2(x) for x in xs])
print("exact Mylar half-thickness at centre", zx[0], "expected B*r", 0.5990701173 * r)

fig, ax = plt.subplots(1, 3, figsize=(15, 4.2))
a = ax[0]
a.plot(xs, zx, "k-", lw=2.5, label="exact (Paulsen)")
a.plot(xs, -zx, "k-", lw=2.5)
for p, lab, st in [("out/mylar-tension-r10-ks1000-kb0.0001.npz", "own, tension-field, 1200 tris", "C0."),
                   ("out/mylar-tension-r16-ks1000-kb0.0001.npz", "own, tension-field, 3072 tris", "C1."),
                   ("out/mylar-full-r16-ks1000-kb0.0001.npz", "own, full membrane, 3072 tris", "C3."),
                   ("bl/mylar-r16-C0.1.npz", "Blender, compression 0.1, 3072 tris", "C2."),
                   ("bl/mylar-r16-C1000.npz", "Blender, compression 1000, 3072 tris", "C4.")]:
    d = L(p); x = d["x"] - np.r_[d["x"][:, :2].mean(0), 0]
    a.plot(np.linalg.norm(x[:, :2], axis=1), x[:, 2], st, ms=2, alpha=0.6, label=lab)
a.set_title("Mylar balloon (two unit discs): profile")
a.set_xlabel("distance from axis"); a.set_ylabel("z"); a.set_aspect("equal"); a.legend(fontsize=7, loc="lower left")

a = ax[1]
for p, lab, st in [("out/teabag-tension-r24-ks1000-kb0.0001.npz", "own TF kb=1e-4 (V=0.200)", "C0-"),
                   ("out/teabag-tension-r24-ks1000-kb0.001.npz", "own TF kb=1e-3 (V=0.180)", "C1-"),
                   ("out/teabag-tension-r24-ks1000-kb0.01.npz", "own TF kb=1e-2 (V=0.101)", "C5-"),
                   ("out/teabag-full-r24-ks1000-kb0.001.npz", "own full kb=1e-3 (V=0.092)", "C3-"),
                   ("bl/teabag-r24-C0.1.npz", "Blender compr 0.1 (V=0.203)", "C2--"),
                   ("bl/teabag-r24-C1000.npz", "Blender compr 1000 (V=0.174)", "C4--")]:
    d = L(p); x = d["x"]; r2 = d["rest2"]
    sel = np.isclose(r2[:, 0], 0.5)
    xx = x[sel]; o = np.argsort(np.arctan2(xx[:, 2], xx[:, 1] - 0.5))
    xx = xx[o]; xx = np.vstack([xx, xx[:1]])
    a.plot(xx[:, 1], xx[:, 2], st, lw=1.3, label=lab)
a.axhline(0, color="0.8", lw=0.5)
a.set_title("Tea bag (two unit squares): section through the centre")
a.set_xlabel("y (rest edge at 0 and 1)"); a.set_aspect("equal"); a.legend(fontsize=7, loc="lower center", ncol=2)
a.set_ylim(-0.42, 0.3)

a = ax[2]
d = L("out/drawn-puff.npz"); x = d["x"]; s = np.isclose(x[:, 1], 0.5)
a.plot(x[s, 0], x[s, 2], "k-o", ms=3, label="drawn bump, repo example (V=0.100, edge stretch up to 26%)")
for p, lab, st in [("out/puff-tension-r24-ks1000-kb0.001.npz", "own solver (V=0.015, stretch 0.3%)", "C0-"),
                   ("bl/puff-r24-C0.1.npz", "Blender (V=0.018, stretch 0.6%)", "C2--")]:
    d = L(p); x = d["x"]; r2 = d["rest2"]; s = np.isclose(r2[:, 1], 0.5) & (x[:, 2] >= -1e-9)
    s &= ~np.isclose(x[:, 2], 0) | np.isclose(r2[:, 0], 0) | np.isclose(r2[:, 0], 1)
    o = np.argsort(r2[s, 0])
    a.plot(x[s][o, 0], x[s][o, 2], st, lw=1.5, label=lab)
a.set_title("Puffed square, rim clamped: section y = 0.5")
a.set_xlabel("x"); a.set_aspect("equal"); a.set_ylim(-0.02, 0.3); a.legend(fontsize=7, loc="upper right")
plt.tight_layout(); plt.savefig("img/profiles.png", dpi=110)

# compression maps in material coordinates, top sheet
fig, ax = plt.subplots(1, 3, figsize=(15, 5))
for a, p, title in [(ax[0], "out/teabag-tension-r24-ks1000-kb0.001.npz", "tea bag, own TF kb=1e-3: compression 1-λmin"),
                    (ax[1], "out/teabag-full-r24-ks1000-kb0.001.npz", "tea bag, own full membrane kb=1e-3"),
                    (ax[2], "out/mylar-tension-r16-ks1000-kb0.0001.npz", "Mylar, own TF: compression 1-λmin")]:
    d = L(p); x = d["x"]; F = d["F"]; r2 = d["rest2"]; sh = d["sheet"]
    import shell as S
    m = S.Model(r2, F, sh, 1, 0)
    Fd, w, V = m.strains(x)
    lam = np.sqrt(np.maximum(1 + 2 * w, 0))
    comp = 1 - lam[:, 0]
    top = sh == 0
    tp = a.tripcolor(r2[:, 0], r2[:, 1], F[top], facecolors=comp[top], cmap="magma_r", vmin=0, vmax=0.5)
    # predicted wrinkle crests: along the TENSION direction (eigvec of larger strain), where compression > 5%
    c = r2[F[top]].mean(1); vt = V[top][:, :, 1]
    # rest-frame direction: strain eigvecs are in rest (material) coords already
    k = comp[top] > 0.05
    segs = np.stack([c[k] - 0.018 * vt[k], c[k] + 0.018 * vt[k]], 1)
    a.add_collection(LineCollection(segs, colors="c", lw=0.8))
    a.set_aspect("equal"); a.set_title(title, fontsize=9); a.set_xticks([]); a.set_yticks([])
    plt.colorbar(tp, ax=a, fraction=0.046)
plt.tight_layout(); plt.savefig("img/compression-maps.png", dpi=110)

# Blender convergence
fig, a = plt.subplots(figsize=(6, 3.5))
for p in ["bl/teabag-r24-C0.1.npz", "bl/teabag-r24-C1000.npz", "bl/mylar-r16-C0.1.npz", "bl/mylar-r16-C1000.npz"]:
    d = L(p); h = d["hist"]
    ref = 0.2055 if "teabag" in p else 1.2186
    a.plot(h[:, 0], h[:, 1] / ref, "-o", ms=2, label=p.split("/")[1][:-4])
a.axhline(1, color="k", lw=0.8)
a.set_xlabel("frame (quality 10)"); a.set_ylabel("V / reference"); a.legend(fontsize=7); a.set_title("Blender cloth: volume vs frame", fontsize=9)
plt.tight_layout(); plt.savefig("img/blender-convergence.png", dpi=110)
print("ok")
