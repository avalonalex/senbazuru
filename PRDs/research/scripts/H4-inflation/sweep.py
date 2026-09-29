"""Pressure sweep with bending: how 'amount of puff' depends on p L^3 / B.
Tension-field stretch (pillow.py) + quadratic (Laplacian) bending per sheet:
  E = stretch + kb * sum_i |(L x)_i|^2 / A_i  - p V
Research script for the H4 note; not repository code."""
import sys, json
import numpy as np
from pillow import square_sheet, pillow, prep, energy_grad, lbfgs, unique_edges

def cotan_laplacian(P2, T, nv):
    Lm = np.zeros((nv, nv)); A = np.zeros(nv)
    for tri in T:
        for k in range(3):
            i, j, o = tri[k], tri[(k + 1) % 3], tri[(k + 2) % 3]
            u, v = P2[i] - P2[o], P2[j] - P2[o]
            cot = np.dot(u, v) / abs(u[0] * v[1] - u[1] * v[0])
            Lm[i, j] += 0.5 * cot; Lm[j, i] += 0.5 * cot
        a = 0.5 * abs(np.cross(P2[tri[1]] - P2[tri[0]], P2[tri[2]] - P2[tri[0]]))
        for v_ in tri: A[v_] += a / 3
    Lm -= np.diag(Lm.sum(1))
    return Lm, A

def run(n, p, kb, k_list=(1e2, 1e3, 1e4)):
    P2, T, Bd = square_sheet(n)
    X, tris, rest2, nsheet, interior, bottom_id = pillow(P2, T, Bd)
    Dinv, area = prep(tris, rest2)
    Lm, Av = cotan_laplacian(P2, T, nsheet)
    # rows only for interior vertices (the seam is free to kink)
    rows = interior
    Q_top = Lm[rows]                       # maps sheet-vertex positions -> Laplacian at interior vertices
    wts = 1.0 / Av[rows]
    top_ids = np.arange(nsheet); bot_ids = bottom_id
    def bend(Xf):
        E = 0.0; G = np.zeros_like(Xf)
        for ids in (top_ids, bot_ids):
            Y = Xf[ids]                    # (nsheet,3)
            LY = Q_top @ Y                 # (ninterior,3)
            E += kb * np.sum(wts[:, None] * LY * LY)
            g = 2 * kb * Q_top.T @ (wts[:, None] * LY)
            np.add.at(G, ids, g)
        return E, G
    x = X.ravel()
    for k in k_list:
        def fun(z):
            Xf = z.reshape(-1, 3)
            E, G, vol, lam = energy_grad(Xf, tris, Dinv, area, k, p, "tfield")
            Eb, Gb = bend(Xf)
            return E + Eb, (G + Gb).ravel()
        x, f, it, st = lbfgs(fun, x, iters=3000)
    Xf = x.reshape(-1, 3)
    E, G, vol, lam = energy_grad(Xf, tris, Dinv, area, k_list[-1], p, "tfield")
    c = np.argmin(np.linalg.norm(P2 - 0.5, axis=1))
    return dict(p_over_kb=p / kb, volume=float(vol), thickness=float(Xf[c, 2] - Xf[bottom_id[c], 2]),
                max_stretch=float(lam.max()), status=st)

if __name__ == "__main__":
    # pressure fixed at 1 so the stretch stiffness stays far above it; vary bending
    n = int(sys.argv[1])
    for ratio in [float(a) for a in sys.argv[2:]]:
        print(json.dumps(run(n, 1.0, 1.0 / ratio)), flush=True)
