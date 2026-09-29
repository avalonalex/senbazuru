"""Side view of the three-layer stack before and after pressing (own code)."""
import re, numpy as np, matplotlib
matplotlib.use("Agg"); import matplotlib.pyplot as plt
name = "stack-g2-contact"
d = np.load(f"runs/{name}.stack.npz"); pts, tag, ns, ny, t = d["pts"], d["tag"], int(d["ns"]), int(d["ny"]), float(d["t"])
blk = re.split(r"displacements \(vx,vy,vz\) for set NALL and time\s+", open(f"runs/{name}.dat").read())[-1]
U = {}
for line in blk.split("\n", 1)[1].splitlines():
    p = line.split()
    if len(p) != 4:
        if p: break
        continue
    U[int(p[0])] = np.array([float(v) for v in p[1:]])
j = ny // 2
X0 = np.array([[pts[s, 0], pts[s, 1]] for s in range(ns)])
X1 = np.array([[pts[s, 0] + U[j * ns + s + 1][0], pts[s, 1] + U[j * ns + s + 1][2]] for s in range(ns)])
fig, axs = plt.subplots(2, 2, figsize=(9, 4.2), gridspec_kw=dict(width_ratios=[3, 1]))
for r, (X, lab) in enumerate([(X0, "start: built thick, layers 2t apart"), (X1, "pressed, with contact")]):
    for c, (lo, hi) in enumerate([(-0.02, 1.02), (0.9, 1.01)]):
        a = axs[r, c]
        # draw the strip as a band of thickness t around its centre line
        dx = np.gradient(X[:, 0]); dz = np.gradient(X[:, 1]); nrm = np.c_[-dz, dx] / np.hypot(dx, dz)[:, None]
        up, dn = X + nrm * t / 2, X - nrm * t / 2
        a.fill(np.r_[up[:, 0], dn[::-1, 0]], np.r_[up[:, 1], dn[::-1, 1]] / t, color="#d9cfb8", ec="#6b5d45", lw=0.5, alpha=0.8)
        a.plot(X[:, 0], X[:, 1] / t, "k-", lw=0.6)
        a.set_xlim(lo, hi); a.set_ylim(-1, 5.2)
        a.set_ylabel("z / t" if c == 0 else "")
        a.set_title(lab if c == 0 else "fold root, x 0.9-1", fontsize=8)
axs[1, 0].set_xlabel("x"); axs[1, 1].set_xlabel("x")
fig.suptitle("CalculiX S4 shells, penalty surface-to-surface contact between layers (arcs not in contact); z stretched by 1/t", fontsize=8)
fig.tight_layout(); fig.savefig("img/stack.png", dpi=150); print("wrote img/stack.png")
