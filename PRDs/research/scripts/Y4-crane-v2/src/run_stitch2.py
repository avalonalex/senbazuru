"""Stitch the torn start back together under IPC with thickness.

python -u run_stitch2.py TORN OUT '{json overrides}'
"""
import sys, json, time
import numpy as np
from sim2 import Sim2
from metrics2 import measure
from crane import EXP, write_obj

torn, out = sys.argv[1], sys.argv[2]
params = dict(k_m=1e5, k_b=1e-2, k_c=1e-3, k_w=1e1, k_g=1e3, dhat=2.5e-4, kappa=1e8, dmin=1e-3,
              ccd='ti', k_anchor=1e-4, kw_schedule=[1e1, 1e2, 1e3, 1e4], max_iter=150)
if len(sys.argv) > 3:
    params.update(json.loads(sys.argv[3]))
d = dict(np.load(f'{EXP}/{torn}.npz'))
reg = json.load(open(f'{EXP}/out/regions.json'))
S = Sim2(d, params, reg)
V = np.load(params['start']) if 'start' in params else S.V0.copy()
log = []
m0, _ = measure(V, S, d)
print('start', json.dumps(m0), flush=True)
log.append(dict(stage='torn start', **m0))
T0 = time.time()
for kw in params['kw_schedule']:
    S.p['k_w'] = kw
    V, info = S.solve(V, max_iter=params['max_iter'], tol=1e-9)
    m, W = measure(V, S, d)
    print(f'k_w={kw:g}: iters {info["iters"]} ({info["seconds"]:.1f}s, ccd-limited {info["ccd_limited"]}, '
          f'backtracks {info["backtracks"]}, |g|inf {info["grad_inf"]:.2e}) ', json.dumps(m), flush=True)
    log.append(dict(stage=f'k_w={kw:g}', info=info, **m))
    np.save(f'{EXP}/out/{out}-kw{kw:g}.npy', V)
    json.dump(dict(params=params, log=log), open(f'{EXP}/out/{out}.json', 'w'), indent=1, default=float)
print(f'total {time.time()-T0:.1f}s')
np.save(f'{EXP}/out/{out}.npy', V)
write_obj(f'{EXP}/out/{out}-welded.obj', W, d['F'], d['M'])
