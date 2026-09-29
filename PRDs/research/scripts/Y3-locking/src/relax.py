"""Staged Gauss-Newton / Levenberg-Marquardt relaxation of the study's energy.

Same residuals as FoldRelaxation.relaxAngularWithPins (length rows
sqrt(w)(l - l0), hinge rows sqrt(k) wrap(theta - rest)), same penalty staging
(1e2, 1e4, 1e6, then the final weight), exact pins, no contact. Differences,
all deliberate: a sparse direct solve instead of conjugate gradients, and
Levenberg-Marquardt damping instead of step halving, so a stage is driven to a
stationary point rather than stopped by the line search.
"""
import time
import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spla

from sheet import hinge_angles, wrap, mesh_edges, edge_rest, principal_strains


class Problem:
    def __init__(self, UV, F, H, rest, k, pinned):
        self.UV, self.F, self.H, self.rest, self.k = UV, F, H, rest, k
        self.Ed = mesh_edges(F)
        self.l0 = edge_rest(UV, self.Ed)
        self.pinned = np.asarray(pinned, bool)
        n = len(UV)
        self.col = -np.ones(n, int)
        free = np.flatnonzero(~self.pinned)
        self.col[free] = np.arange(len(free))
        self.nfree = len(free)
        self.sk = np.sqrt(k)
        # sparsity pattern
        ne, nh = len(self.Ed), len(H)
        self.ne, self.nh = ne, nh

    def residuals(self, X, w):
        d = X[self.Ed[:, 1]] - X[self.Ed[:, 0]]
        l = np.linalg.norm(d, axis=1)
        ang = hinge_angles(X, self.H)
        return np.concatenate([np.sqrt(w) * (l - self.l0), self.sk * wrap(ang - self.rest)])

    def energy(self, X, w):
        # guard: refuse any state with a collapsed triangle (smallest principal
        # stretch below 5% of material length); the study has no such guard,
        # but a collapsed triangle makes hinge angles undefined.
        if principal_strains(X, self.UV, self.F)[0].min() < -0.95:
            return np.inf
        r = self.residuals(X, w)
        return float(r @ r)

    def jacobian(self, X, w):
        d = X[self.Ed[:, 1]] - X[self.Ed[:, 0]]
        l = np.linalg.norm(d, axis=1)
        u = d / l[:, None]
        ang, g = hinge_angles(X, self.H, grad=True)
        r = np.concatenate([np.sqrt(w) * (l - self.l0), self.sk * wrap(ang - self.rest)])
        rows, cols, vals = [], [], []
        sw = np.sqrt(w)
        er = np.arange(self.ne)
        for end, sign in ((0, -1.0), (1, 1.0)):
            v = self.Ed[:, end]
            c = self.col[v]
            ok = c >= 0
            for ax in range(3):
                rows.append(er[ok]); cols.append(3 * c[ok] + ax); vals.append(sign * sw * u[ok, ax])
        hr = self.ne + np.arange(self.nh)
        for corner in range(4):
            v = self.H[:, corner]
            c = self.col[v]
            ok = c >= 0
            for ax in range(3):
                rows.append(hr[ok]); cols.append(3 * c[ok] + ax); vals.append(self.sk[ok] * g[ok, corner, ax])
        J = sp.csr_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))),
                          shape=(self.ne + self.nh, 3 * self.nfree))
        return r, J

    def moved(self, X, delta):
        Y = X.copy()
        free = self.col >= 0
        Y[free] += delta.reshape(-1, 3)
        return Y


def relax_stage(P, X, w, max_iter=400, log=None):
    mu = 1e-3
    E = P.energy(X, w)
    hist = []
    stall = 0
    for it in range(max_iter):
        r, J = P.jacobian(X, w)
        g = J.T @ r
        A = (J.T @ J).tocsc()
        diag = A.diagonal()
        gnorm = float(np.abs(g).max()) if g.size else 0.0
        accepted = False
        for _ in range(30):
            M = A + sp.diags(mu * (diag + 1e-12 * diag.max() + 1e-30))
            try:
                delta = spla.spsolve(M, -g)
            except Exception:
                mu *= 10
                continue
            Y = P.moved(X, delta)
            if not np.all(np.isfinite(Y)):
                mu *= 10
                continue
            try:
                E2 = P.energy(Y, w)
            except FloatingPointError:
                E2 = np.inf
            if np.isfinite(E2) and E2 < E:
                accepted = True
                break
            mu *= 10
        if not accepted:
            hist.append((it, E, gnorm, 0.0, mu))
            break
        step = float(np.abs(delta).max())
        rel = (E - E2) / max(E, 1e-300)
        X, E = Y, E2
        mu = max(mu / 3, 1e-12)
        hist.append((it, E, gnorm, step, mu))
        if log is not None and (it % 25 == 0):
            log(f"    w={w:.2e} it={it} E={E:.6e} |g|={gnorm:.3e} step={step:.2e} mu={mu:.1e}")
        if step < 1e-11 or rel < 1e-14:
            stall += 1
            if stall >= 3:
                break
        else:
            stall = 0
    r, J = P.jacobian(X, w)
    g = J.T @ r
    return X, dict(w=w, iterations=len(hist), energy=E, grad_inf=float(np.abs(g).max()) if g.size else 0.0,
                   last_step=hist[-1][3] if hist else 0.0)


def relax(P, X0, w_final, stages=(1e2, 1e4, 1e6), max_iter=400, log=None):
    X = X0.copy()
    reports = []
    t0 = time.perf_counter()
    for w in list(stages) + [w_final]:
        X, rep = relax_stage(P, X, w, max_iter=max_iter, log=log)
        reports.append(rep)
        if log:
            log(f"  stage w={w:.2e}: {rep['iterations']} it, E={rep['energy']:.6e}, |grad|inf={rep['grad_inf']:.3e}")
    return X, reports, time.perf_counter() - t0
