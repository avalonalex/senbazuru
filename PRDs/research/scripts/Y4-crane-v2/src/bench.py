"""Time the pieces of one Newton iteration, 3 repeats each.

python bench.py TORN STATE.npy '{params}' LABEL
"""
import sys, json, time
import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spla
from sim2 import Sim2
from crane import EXP

torn, state, params, label = sys.argv[1], sys.argv[2], json.loads(sys.argv[3]), sys.argv[4]
p = dict(k_m=1e5, k_b=1e-2, k_c=1e-3, k_w=1e2, k_g=1e3)
p.update(params)
d = dict(np.load(f'{EXP}/{torn}.npz'))
reg = json.load(open(f'{EXP}/out/regions.json'))
S = Sim2(d, p, reg)
V = np.load(state)
C = S.contact
for rep in range(3):
    t0 = time.perf_counter(); c = C.candidates(V); t1 = time.perf_counter()
    e, g, H, _ = S.elastic(V); t2 = time.perf_counter()
    eb, gb, Hb, ncol = C.energy_grad_hess(V, c); t3 = time.perf_counter()
    Hs = (H + Hb).tocsc() + sp.identity(3 * S.n, format='csc') * 1e-9
    dx = -spla.spsolve(Hs, g + gb); t4 = time.perf_counter()
    D = dx.reshape(-1, 3); cap = p.get('step_cap', 5e-3)
    if np.abs(D).max() > cap:
        D *= cap / np.abs(D).max()
    c2 = C.candidates(V, V + D); t5 = time.perf_counter()
    a = C.step_size(V, V + D, c2); t6 = time.perf_counter()
    print(json.dumps(dict(label=label, rep=rep, candidates_s=t1 - t0, elastic_s=t2 - t1, barrier_s=t3 - t2,
                          linsolve_s=t4 - t3, swept_candidates_s=t5 - t4, ccd_s=t6 - t5, collisions=ncol,
                          swept=len(c2.fv_candidates) + len(c2.ee_candidates), alpha=a)), flush=True)
