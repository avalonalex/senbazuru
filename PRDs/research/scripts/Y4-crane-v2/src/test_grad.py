"""Finite-difference checks of the new energies (tension field, volume floor)."""
import json
import numpy as np
from sim2 import Sim2
from crane import EXP, X3

d = dict(np.load(f'{X3}/torn.npz'))
reg = json.load(open(f'{EXP}/out/regions.json'))
p = dict(k_m=1e5, k_b=1e-2, k_c=1e-3, k_w=1e4, k_g=1e3, dhat=1e-4, kappa=1e11, dmin=0.0,
         tf_core=True, k_t=1e5, tf_comp=1e-3, k_v=1e6)
S = Sim2(d, p, reg)
rng = np.random.default_rng(1)
V = np.load(f'{X3}/open-root-step05.npy') + 1e-3 * rng.normal(size=S.V0.shape)
S.Vstar = 5e-3
e, g, H, parts = S.elastic(V)
print('parts', {k: f'{v:.3e}' for k, v in parts.items()})
h = 1e-7
idx = np.concatenate([S.T[S.core_tris[:5]].ravel(), rng.integers(0, S.n, 5)])
err = 0; scale = 0
for i in idx:
    for k in range(3):
        Vp = V.copy(); Vp[i, k] += h
        Vm = V.copy(); Vm[i, k] -= h
        fd = (S.elastic(Vp, False)[0] - S.elastic(Vm, False)[0]) / (2 * h)
        err = max(err, abs(fd - g[3 * i + k])); scale = max(scale, abs(fd))
print(f'gradient check: max abs err {err:.3e} (largest component {scale:.3e})')
# Hessian check on the tension-field term only (directional)
p2 = dict(p); p2.update(k_m=0, k_b=0, k_c=0, k_w=0, k_g=0, k_v=0)
S2 = Sim2(d, p2, reg)
e0, g0, H0, _ = S2.elastic(V)
dv = rng.normal(size=V.shape) * 1e-6
g1 = S2.elastic(V + dv)[1]
print('TF: |g(V+dv)-g(V)|', np.linalg.norm(g1 - g0), ' |H dv|', np.linalg.norm(H0 @ dv.ravel()),
      ' |diff|', np.linalg.norm(g1 - g0 - H0 @ dv.ravel()))
W = S.A @ V
v0, gW = S.core_volume(W)
errv = 0
for i in range(len(W)):
    for k in range(3):
        Wp = W.copy(); Wp[i, k] += h
        Wm = W.copy(); Wm[i, k] -= h
        fd = (S.core_volume(Wp, False)[0] - S.core_volume(Wm, False)[0]) / (2 * h)
        errv = max(errv, abs(fd - gW[i, k]))
print(f'volume {v0:.4e}, gradient max err {errv:.3e}, translation invariance',
      abs(S.core_volume(W + np.array([0.3, -0.2, 0.7]), False)[0] - v0))
