"""Render-time crimp synthesis on a tension-field result (tea bag only; crude).

The tension-field solve says HOW MUCH material is compressed (c = 1 - lambda_min)
but not the wrinkle geometry. Here: 2x midpoint subdivision, then displace along
the vertex normal by A(c) sin(2 pi u / lam), where u is the rest coordinate along
the nearest sheet edge (tea-bag crimps run perpendicular to the seam), and
A = (lam/pi) sqrt(c) is the amplitude whose sinusoid stores excess length c.
Tea-bag specific (the phase field is a hack), for a look test only.
python crimp.py IN.npz OUT.npz LAMBDA
"""
import sys

import numpy as np

import shell as S

inp, outp, lam_w = sys.argv[1], sys.argv[2], float(sys.argv[3])
profile = sys.argv[4] if len(sys.argv) > 4 else "sine"
d = np.load(inp)
x, F, r2, sh = d["x"], d["F"], d["rest2"], d["sheet"]
m = S.Model(r2, F, sh, 1, 0)
Fd, w, V = m.strains(x)
comp = 1 - np.sqrt(np.maximum(1 + 2 * w[:, 0], 0))
# area-weighted vertex compression
cv = np.zeros(len(x)); wv = np.zeros(len(x))
for k in range(3):
    np.add.at(cv, F[:, k], comp * m.A0); np.add.at(wv, F[:, k], m.A0)
cv /= wv
nv0 = len(x)
seam0 = np.isclose(r2[:, 0], 0) | np.isclose(r2[:, 0], 1) | np.isclose(r2[:, 1], 0) | np.isclose(r2[:, 1], 1)


def subdivide(x, r2, cv, F, sh):
    emid = {}
    X, R, C = list(x), list(r2), list(cv)
    newF, newS = [], []

    def mid(a, b):
        k = (min(a, b), max(a, b))
        if k not in emid:
            emid[k] = len(X)
            X.append((X[a] + X[b]) / 2); R.append((R[a] + R[b]) / 2); C.append((C[a] + C[b]) / 2)
        return emid[k]
    for (a, b, c), s in zip(F, sh):
        ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
        newF += [(a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)]
        newS += [s] * 4
    return np.array(X), np.array(R), np.array(C), np.array(newF), np.array(newS)


for _ in range(2):
    x, r2, cv, F, sh = subdivide(x, r2, cv, F, sh)
# smooth positions of new vertices a little (Laplacian, rim fixed) so facets of the coarse mesh fade
nbr = [[] for _ in range(len(x))]
for a, b, c in F:
    nbr[a] += [b, c]; nbr[b] += [a, c]; nbr[c] += [a, b]
seam = np.isclose(r2[:, 0], 0) | np.isclose(r2[:, 0], 1) | np.isclose(r2[:, 1], 0) | np.isclose(r2[:, 1], 1)
for _ in range(6):
    avg = np.array([x[n].mean(0) for n in nbr])
    x = np.where(seam[:, None], x, 0.5 * x + 0.5 * avg)
    cavg = np.array([cv[n].mean() for n in nbr])
    cv = 0.5 * cv + 0.5 * cavg
# vertex normals (area weighted)
n = np.zeros_like(x)
fn = np.cross(x[F[:, 1]] - x[F[:, 0]], x[F[:, 2]] - x[F[:, 0]])
for k in range(3):
    np.add.at(n, F[:, k], fn)
n /= np.linalg.norm(n, axis=1)[:, None] + 1e-12
# phase: rest coordinate along the nearest edge
X, Y = r2[:, 0], r2[:, 1]
dists = np.stack([Y, 1 - Y, X, 1 - X], 1)
near = dists.argmin(1)
u = np.where(near < 2, X, Y)
dedge = dists.min(1)
ramp = np.clip(dedge / 0.03, 0, 1) ** 2 * (3 - 2 * np.clip(dedge / 0.03, 0, 1))
cc = np.clip(cv, 0, 0.5)
if profile == "sine":
    A = (lam_w / np.pi) * np.sqrt(cc)
    wave = np.sin(2 * np.pi * u / lam_w)
else:  # zigzag: straight facets meeting in sharp ridges; excess length c
    cc = np.where(cc > 0.05, cc, 0.0)
    A = (lam_w / 4) * np.sqrt((1 + cc) ** 2 - 1)
    ph = (u / lam_w) % 1.0
    wave = 4 * np.abs(ph - 0.5) - 1  # triangle wave in [-1, 1]
x = x + (A * wave * ramp)[:, None] * n
np.savez(outp, x=x, F=F, rest2=r2, sheet=sh)
print("crimped", len(x), "verts", len(F), "tris; max amplitude", A.max(), "V", S.Model(r2, F, sh, 1, 0).volume(x))
