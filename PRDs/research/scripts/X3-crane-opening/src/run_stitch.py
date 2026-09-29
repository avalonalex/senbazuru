"""Stitch phase: close the weld gaps of the torn start under IPC contact.

python run_stitch.py TORN.npz OUTNAME
"""
import sys, json, time
import numpy as np
import ipctk
from sim import Sim
from metrics import measure
from crane import EXP, write_obj

torn = sys.argv[1] if len(sys.argv) > 1 else f'{EXP}/torn.npz'
out = sys.argv[2] if len(sys.argv) > 2 else 'stitch'
params = dict(k_m=1e5, k_b=1e-2, k_c=1e-3, k_w=1e1, k_g=1e3, dhat=1e-4, kappa=1e11, k_anchor=1e-4)
if len(sys.argv) > 3:
    params.update(json.loads(sys.argv[3]))
d = dict(np.load(torn))
S = Sim(d, params)
S.anchor = S.V0.copy()
V = S.V0.copy()
log = []
m0, _ = measure(V, S, d)
print('start', json.dumps(m0))
log.append(dict(stage='torn start', **m0))
T0 = time.time()
for kw in params.get('kw_schedule', [1e1, 1e2, 1e3, 1e4]):
    S.p['k_w'] = kw
    V, info = S.solve(V, max_iter=params.get('max_iter', 150), tol=1e-9)
    m, W = measure(V, S, d)
    print(f'k_w={kw:g}: iters {info["iters"]} ({info["seconds"]:.1f}s, ccd-limited {info["ccd_limited"]}, '
          f'backtracks {info["backtracks"]}, |g|inf {info["grad_inf"]:.2e}) ', json.dumps(m))
    log.append(dict(stage=f'k_w={kw:g}', info={k: v for k, v in info.items()}, **m))
    np.save(f'{EXP}/{out}-kw{kw:g}.npy', V)
print(f'total {time.time()-T0:.1f}s')
np.save(f'{EXP}/{out}.npy', V)
write_obj(f'{EXP}/{out}-welded.obj', W, d['F'], d['M'])
json.dump(dict(params=params, log=log), open(f'{EXP}/{out}.json', 'w'), indent=1, default=float)
