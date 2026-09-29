"""Measure X3's saved states and the study's poses with the Y4 metric set.

python remeasure2.py  -> out/baselines.json
"""
import json
import numpy as np
from sim2 import Sim2
from metrics2 import measure, welded_measures
from crane import EXP, X3, load

reg = json.load(open(f'{EXP}/out/regions.json'))
d = dict(np.load(f'{X3}/torn.npz'))
S = Sim2(d, dict(k_m=1, k_b=1, k_c=1, k_w=1, k_g=1, dhat=1e-4, kappa=1, dmin=0.0), reg)
out = {}
for name in ['before', 'after', 'spread-0', 'pillow']:
    X = load(name)['X']
    m = welded_measures(X, d)
    m['core_volume'] = float(S.core_volume(X, False)[0])
    out['study ' + name] = m
for name in ['stitch', 'open-root-step05', 'open-root-step10', 'open-tip-step10', 'conv-root10-step10']:
    V = np.load(f'{X3}/{name}.npy')
    m, _ = measure(V, S, d)
    out['X3 ' + name] = m
for k, v in out.items():
    print(f'{k:24s} open med {v["body_open_med"]:.4f} max {v["body_open_max"]:.4f} depth {v["body_depth"]:.4f} '
          f'tips {v["wing_tip_sep"]:.3f} edge {v["edge_err_max"]:.4f} stretch {v["stretch_max"]:.4f} '
          f'comp {v["compress_max"]:.4f} V {v["core_volume"]:.2e} cross_torn {v.get("crossings_torn","-")}')
json.dump(out, open(f'{EXP}/out/baselines.json', 'w'), indent=1)
