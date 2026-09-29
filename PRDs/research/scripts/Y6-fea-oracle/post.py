"""Measure a CalculiX tea-bag result the way X2 measured its own (experiment Y6, own code).

usage: python post.py NAME      (reads runs/NAME.dat, runs/NAME.mesh.npz, runs/NAME.meta.json)
Writes runs/NAME.result.json and runs/NAME.npz (whole pillow: top sheet + its mirror, for rendering).
"""

import json
import re
import sys

import numpy as np

name = sys.argv[1]
mesh = np.load(f"runs/{name}.mesh.npz")
meta = json.load(open(f"runs/{name}.meta.json"))
X0, tri = mesh["X"], mesh["tri"]

# last displacement block in the .dat file
txt = open(f"runs/{name}.dat").read()
blocks = re.split(r"\n\s*displacements \(vx,vy,vz\) for set NALL and time\s+", txt)
if len(blocks) < 2:
    print(json.dumps(dict(name=name, error="no displacement block")))
    sys.exit(1)
last = blocks[-1]
time_str, body = last.split("\n", 1)
U = np.zeros_like(X0)
for line in body.splitlines():
    parts = line.split()
    if len(parts) != 4:
        if parts:
            break
        continue
    k = int(parts[0]) - 1
    U[k] = [float(v) for v in parts[1:]]
x = X0 + U
step_time = float(time_str.split()[0])

# volume between the top sheet and z = 0, doubled for the mirror sheet
a, b, c = x[tri[:, 0]], x[tri[:, 1]], x[tri[:, 2]]
area_xy = 0.5 * ((b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (c[:, 0] - a[:, 0]) * (b[:, 1] - a[:, 1]))
V = 2 * float(np.sum(area_xy * (a[:, 2] + b[:, 2] + c[:, 2]) / 3))

# principal stretches of the mid-surface, per triangle, against the FLAT unit square
# (the rest shape carries a 2% dome; measuring against the flat square matches X2)
P0 = X0[:, :2]
A0 = 0.5 * np.abs(np.cross(P0[tri[:, 1]] - P0[tri[:, 0]], P0[tri[:, 2]] - P0[tri[:, 0]]))
Dm = np.stack([P0[tri[:, 1]] - P0[tri[:, 0]], P0[tri[:, 2]] - P0[tri[:, 0]]], axis=2)  # 2x2
Ds = np.stack([b - a, c - a], axis=2)  # 3x2
F = Ds @ np.linalg.inv(Dm)
C = np.transpose(F, (0, 2, 1)) @ F
lam = np.sqrt(np.linalg.eigvalsh(C))  # ascending
comp = 1 - lam[:, 0]

# dihedral angles between neighbouring triangles (a roughness / wrinkle measure)
nrm = np.cross(b - a, c - a)
nrm /= np.linalg.norm(nrm, axis=1)[:, None]
edges = {}
for f, (i, j, k) in enumerate(tri):
    for u, v in ((i, j), (j, k), (k, i)):
        edges.setdefault((min(u, v), max(u, v)), []).append(f)
pairs = np.array([fs for fs in edges.values() if len(fs) == 2])
cosang = np.clip(np.sum(nrm[pairs[:, 0]] * nrm[pairs[:, 1]], axis=1), -1, 1)
dih = np.degrees(np.arccos(cosang))

# a smooth-surface residual: z minus its 5x5-node moving average, on corner-node grids only
res = None
if not mesh["quad8"]:
    n = meta["n"]
    Z = x[:, 2].reshape(n + 1, n + 1)
    from numpy.lib.stride_tricks import sliding_window_view

    Zp = np.pad(Z, 2, mode="edge")
    Zs = sliding_window_view(Zp, (5, 5)).mean(axis=(2, 3))
    res = float(np.abs(Z - Zs)[2:-2, 2:-2].max())

m = int(round(np.sqrt(len(X0)))) - 1 if not mesh["quad8"] else None
out = dict(
    name=name,
    step_time_reached=step_time,
    V=V,
    thickness=float(2 * x[:, 2].max()),
    max_stretch=float(lam[:, 1].max() - 1),
    max_compression=float(comp.max()),
    area_frac_compressed_1pct=float(A0[comp > 0.01].sum() / A0.sum()),
    area_frac_compressed_5pct=float(A0[comp > 0.05].sum() / A0.sum()),
    max_dihedral_deg=float(dih.max()),
    p95_dihedral_deg=float(np.percentile(dih, 95)),
    z_residual_vs_5x5_mean=res,
)
# edge-midpoint pull-in, as X2: (0.5, 0) moves in y relative to the corner (0, 0)
mid = np.where(np.isclose(X0[:, 0], 0.5) & np.isclose(X0[:, 1], 0.0))[0]
cor = np.where(np.isclose(X0[:, 0], 0.0) & np.isclose(X0[:, 1], 0.0))[0]
if len(mid) and len(cor):
    out["edge_mid_pull_in"] = float(x[mid[0], 1] - x[cor[0], 1])
out.update({k: meta[k] for k in ("elem", "n", "mat", "ks", "kb", "nu", "proc", "t", "E", "nnodes", "nelems", "imp", "seed")})
json.dump(out, open(f"runs/{name}.result.json", "w"), indent=1)

# whole pillow for rendering: top sheet + mirror (bottom faces reversed)
nv = len(x)
xm = x * [1, 1, -1]
xf = np.r_[x, xm]
Ff = np.r_[tri, tri[:, ::-1] + nv]
np.savez(f"runs/{name}.npz", x=xf, F=Ff, top=x, tri=tri, lam=lam)
print(json.dumps(out))
