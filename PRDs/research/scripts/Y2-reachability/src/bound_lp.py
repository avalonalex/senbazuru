"""LP lower bounds from the no-stretch pair condition (see bound.py).

For every pair with excess e_ij = |P x*_i - P x*_j| - |u_i - u_j| > 0, any paper
state has t_i + t_j >= e_ij where t_i = |P d_i| is vertex i's movement in the
picture. Minimising sum a_i t_i (a = vertex area share) over t >= 0 under these
constraints is a linear programme whose optimum is a lower bound on the
area-weighted mean picture movement of the mesh vertices, for ANY paper state
(any mesh refinement between them, any creasing or crumpling, contact ignored).
With threshold constraints (t_i + t_j >= 1 where e_ij > 10 px) the LP optimum
bounds from below the area share of vertices that must move at least 5 px.
"""
import sys, json
sys.path.insert(0, 'src')
import numpy as np, mesh
from scipy.optimize import linprog
import scipy.sparse as sp
G = '../../gallery/whole-crane/'
out = {}
for name in ['spread-0', 'narrow', 'after']:
    m = mesh.load_fold(G + name + '.fold')
    X, U, a = m['X'], m['U'], m['varea'] / m['varea'].sum()
    P, _ = mesh.project(X)
    n = len(X)
    I, J = np.triu_indices(n, 1)
    du = np.linalg.norm(U[I] - U[J], axis=1)
    res = {}
    for label, Y in (('picture', P), ('3d', X)):
        e = (np.linalg.norm(Y[I] - Y[J], axis=1) - du) * 600
        k = e > 1e-9
        rows = np.repeat(np.arange(k.sum()), 2)
        cols = np.stack([I[k], J[k]], 1).ravel()
        A = sp.csr_matrix((-np.ones(len(rows)), (rows, cols)), shape=(k.sum(), n))
        lp = linprog(a, A_ub=A, b_ub=-e[k], bounds=(0, None), method='highs')
        k5 = e > 10
        rows5 = np.repeat(np.arange(k5.sum()), 2)
        cols5 = np.stack([I[k5], J[k5]], 1).ravel()
        A5 = sp.csr_matrix((-np.ones(len(rows5)), (rows5, cols5)), shape=(k5.sum(), n))
        lp5 = linprog(a, A_ub=A5, b_ub=-np.ones(k5.sum()), bounds=(0, 1), method='highs') if k5.sum() else None
        res[label] = dict(pairs_stretched=int(k.sum()), mean_move_lb_px=float(lp.fun), max_move_lb_px=float(e.max() / 2),
                          area_share_moving_5px_lb=float(lp5.fun) if lp5 is not None else 0.0, status=lp.status)
    out[name] = res
    print(name, json.dumps(res))
json.dump(out, open('out/bound_lp.json', 'w'), indent=1)
