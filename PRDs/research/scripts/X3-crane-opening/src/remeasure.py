"""Re-measure saved states (torn .npy) and the study's poses with one metric set.

python remeasure.py RUN_PREFIX NSTEPS  -> RUN_PREFIX-metrics.json
python remeasure.py --study           -> study-metrics.json
"""
import sys, json, glob
import numpy as np
from crane import EXP, load, edge_strain, principal_stretch
from contact import crossing_pairs
from metrics import mirror_body_pairs, body_opening, WING_TIPS

d = dict(np.load(f'{EXP}/torn.npz'))
X, F, M, Ev = d['X'], d['F'], d['M'], d['Ev']
pairs = mirror_body_pairs(X, M)


def welded_measure(W):
    st = edge_strain(W, M, Ev)
    ps = principal_stretch(W, M, F)
    bo = body_opening(W, pairs)
    return dict(edge_err_max=float(np.abs(st).max()), edge_err_p95=float(np.percentile(np.abs(st), 95)),
                stretch_max=float(ps[:, 0].max() - 1), compress_max=float(1 - ps[:, 1].min()),
                body_open_med=bo[0], body_open_max=bo[1],
                wing_tip_sep=float(np.linalg.norm(W[WING_TIPS[0]] - W[WING_TIPS[1]])),
                crossing_pairs_welded=len(crossing_pairs(W, F)))


if sys.argv[1] == '--study':
    out = {}
    for n in ['before', 'after', 'spread-0', 'spread-100', 'pillow']:
        out[n] = welded_measure(load(n)['X'])
        print(n, json.dumps(out[n]))
    json.dump(out, open(f'{EXP}/study-metrics.json', 'w'), indent=1)
else:
    from sim import Sim
    prefix = sys.argv[1]
    files = sorted(glob.glob(f'{EXP}/{prefix}-step*.npy'))
    S = Sim(d, dict(k_m=1, k_b=1, k_c=1, k_w=1, k_g=1, dhat=1e-4, kappa=1))
    out = []
    for f in files:
        V = np.load(f)
        W = np.zeros((len(X), 3)); c = np.zeros(len(X))
        np.add.at(W, S.mat, V); np.add.at(c, S.mat, 1); W /= c[:, None]
        m = welded_measure(W)
        m['min_dist_torn'] = S.contact.min_distance(V, 5e-4)
        m['file'] = f.split('/')[-1]
        out.append(m)
        print(json.dumps(m))
    json.dump(out, open(f'{EXP}/{prefix}-metrics.json', 'w'), indent=1)
