"""Isometry projection: the nearest (near-)paper to a target pose.

Minimises  1/2 |r(x)|^2  with residual blocks

  membrane  sqrt(ks * A_t) * (E11, E22, sqrt2 E12)        every triangle
  bending   sqrt(kb * 3 L^2 / (A1 + A2)) * (m1/2A1 - m2/2A2)   J edges only
  pull      sqrt(lam * a_v / sum a) * P^T (x_v - target_v)   pulled vertices

E = (F^T F - I)/2 is the triangle's Green strain against its flat-sheet shape
(F = 3x2 deformation gradient), so all-zero membrane residuals mean an exact
isometry. m1, m2 are the two triangles' cross-product normals at a J edge (a
join inside one panel, whose rest shape is flat) divided by twice their REST
areas; on isometric triangles this is n1 - n2, of length 2 sin(theta/2).
Both blocks are polynomial in the positions, so the Jacobian stays finite when
a triangle of the sketch is squashed to nearly nothing (the first version used
unit normals and edge lengths and stalled on exactly that). P is the identity
(pull in 3D) or the upright camera's two screen axes (pull in the picture plane
only; depth free). Crease hinges (M, V, F, U) carry no energy: the most
permissive assumption for reachability.

Solved by Levenberg-Marquardt with an analytic sparse Jacobian and a direct
sparse solve of the normal equations. Written for this experiment.
"""
import time
import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spla


def skew(v):
    z = np.zeros(v.shape[:-1] + (3, 3))
    z[..., 0, 1] = -v[..., 2]; z[..., 0, 2] = v[..., 1]
    z[..., 1, 0] = v[..., 2]; z[..., 1, 2] = -v[..., 0]
    z[..., 2, 0] = -v[..., 1]; z[..., 2, 1] = v[..., 0]
    return z


class Problem:
    def __init__(self, m, target, lam, pulled=None, kb=1e-3, ks=1.0, plane=None, bend_kinds=("J",), membrane="green", weights=None):
        self.m = m
        self.membrane = membrane
        e = m["edges"]
        self.ei, self.ej = e[:, 0], e[:, 1]
        self.L = m["rest"]
        self.sw = np.sqrt(ks * m["eweight"])
        self.target = target
        n = len(m["U"])
        self.n = n
        U, F = m["U"], m["F"]
        self.F = F
        Dm = np.stack([U[F[:, 1]] - U[F[:, 0]], U[F[:, 2]] - U[F[:, 0]]], 2)  # (t, 2, 2) columns
        B = np.linalg.inv(Dm)
        # Fu = sum_k cu_k x_k, Fv = sum_k cv_k x_k over the corners (a, b, c)
        self.cu = np.stack([-(B[:, 0, 0] + B[:, 1, 0]), B[:, 0, 0], B[:, 1, 0]], 1)
        self.cv = np.stack([-(B[:, 0, 1] + B[:, 1, 1]), B[:, 0, 1], B[:, 1, 1]], 1)
        self.sm = np.sqrt(ks * m["area_t"])
        sel = np.isin(m["hkind"], bend_kinds)
        h = m["hinges"][sel]
        self.h = h
        self.sb = np.sqrt(kb * m["hweight"][sel])
        # rest areas of the two triangles at each hinge
        def area(a, b, c):
            p, q = U[b] - U[a], U[c] - U[a]
            return 0.5 * np.abs(p[:, 0] * q[:, 1] - p[:, 1] * q[:, 0])
        if len(h):
            self.A1 = area(h[:, 0], h[:, 1], h[:, 2]); self.A2 = area(h[:, 1], h[:, 0], h[:, 3])
        if pulled is None:
            pulled = np.arange(n)
        self.pv = np.asarray(pulled)
        # pull energy = lam * (area-weighted mean squared displacement of the pulled set)
        self.sp = np.sqrt(lam * m["varea"][self.pv] / m["varea"][self.pv].sum()) if len(self.pv) else np.zeros(0)
        if weights is not None:  # explicit per-vertex pull weights (anchors, reweighting)
            self.sp = np.sqrt(lam * np.asarray(weights)[self.pv])
        self.P = np.eye(3) if plane is None else np.stack(plane, 1)  # (3, k)
        self.k = self.P.shape[1]

    def residual(self, x, jac=True):
        X = x.reshape(-1, 3)
        rows, cols, vals = [], [], []
        r_parts = []
        off = 0
        if self.membrane == "edge":
            # symmetric alternative: engineering strain of every edge
            d = X[self.ei] - X[self.ej]
            ln = np.linalg.norm(d, axis=1)
            r_parts.append(self.sw * (ln / self.L - 1))
            if jac:
                g = (self.sw / self.L)[:, None] * d / ln[:, None]
                ne = len(ln)
                ridx = np.repeat(np.arange(ne), 3)
                for vtx, sgn in ((self.ei, 1.0), (self.ej, -1.0)):
                    rows.append(ridx); cols.append((3 * vtx[:, None] + np.arange(3)).ravel()); vals.append((sgn * g).ravel())
                off += ne
            return self._rest(X, jac, rows, cols, vals, r_parts, off)
        # membrane: Green strain per triangle
        Xt = X[self.F]  # (t, 3, 3)
        Fu = np.einsum("tk,tkj->tj", self.cu, Xt)
        Fv = np.einsum("tk,tkj->tj", self.cv, Xt)
        E11 = 0.5 * ((Fu * Fu).sum(1) - 1); E22 = 0.5 * ((Fv * Fv).sum(1) - 1); E12 = (Fu * Fv).sum(1)
        s2 = np.sqrt(2.0)
        r_parts.append((self.sm[:, None] * np.stack([E11, E22, s2 * E12], 1)).ravel())
        if jac:
            nt = len(self.F)
            for k in range(3):
                g11 = self.cu[:, k, None] * Fu
                g22 = self.cv[:, k, None] * Fv
                g12 = s2 * (self.cu[:, k, None] * Fv + self.cv[:, k, None] * Fu)
                G = self.sm[:, None, None] * np.stack([g11, g22, g12], 1)  # (t, 3 res, 3 xyz)
                rr = (off + 3 * np.arange(nt))[:, None, None] + np.arange(3)[None, :, None]
                cc = 3 * self.F[:, k][:, None, None] + np.arange(3)[None, None, :]
                rows.append((rr * np.ones((1, 1, 3), int)).ravel()); cols.append((cc * np.ones((1, 3, 1), int)).ravel()); vals.append(G.ravel())
            off += 3 * nt
        return self._rest(X, jac, rows, cols, vals, r_parts, off)

    def _rest(self, X, jac, rows, cols, vals, r_parts, off):
        # bending at J edges
        if len(self.h):
            i, j, k, l = self.h.T
            a1 = X[j] - X[i]; b1 = X[k] - X[i]
            a2 = X[i] - X[j]; b2 = X[l] - X[j]
            c1 = 1 / (2 * self.A1); c2 = 1 / (2 * self.A2)
            m1 = np.cross(a1, b1) * c1[:, None]; m2 = np.cross(a2, b2) * c2[:, None]
            r_parts.append((self.sb[:, None] * (m1 - m2)).ravel())
            if jac:
                D1j = -skew(b1) * c1[:, None, None]; D1k = skew(a1) * c1[:, None, None]; D1i = -(D1j + D1k)
                D2i = -skew(b2) * c2[:, None, None]; D2l = skew(a2) * c2[:, None, None]; D2j = -(D2i + D2l)
                s = self.sb[:, None, None]
                blocks = [(i, s * (D1i - D2i)), (j, s * (D1j - D2j)), (k, s * D1k), (l, -s * D2l)]
                nh = len(i)
                rbase = off + 3 * np.arange(nh)
                for vtx, Bk in blocks:
                    rr = (rbase[:, None, None] + np.arange(3)[None, :, None]) * np.ones((1, 1, 3), int)
                    cc = (3 * vtx[:, None, None] + np.arange(3)[None, None, :]) * np.ones((1, 3, 1), int)
                    rows.append(rr.ravel()); cols.append(cc.ravel()); vals.append(Bk.ravel())
                off += 3 * nh
        # pull
        if len(self.pv):
            dv = (X[self.pv] - self.target[self.pv]) @ self.P  # (np, k)
            r_parts.append((self.sp[:, None] * dv).ravel())
            if jac:
                npv = len(self.pv)
                rr = (off + self.k * np.arange(npv))[:, None, None] + np.arange(self.k)[None, :, None]
                cc = 3 * self.pv[:, None, None] + np.arange(3)[None, None, :]
                Bk = self.sp[:, None, None] * self.P.T[None, :, :]
                rows.append((rr * np.ones((1, 1, 3), int)).ravel()); cols.append((cc * np.ones((1, self.k, 1), int)).ravel()); vals.append(Bk.ravel())
                off += self.k * npv
        r = np.concatenate(r_parts)
        if not jac:
            return r
        Jm = sp.csr_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(len(r), 3 * self.n))
        return r, Jm

    def parts(self, x):
        """Energy split (membrane, bending, pull) at x."""
        r = self.residual(x, jac=False)
        nt = len(self.ei) if self.membrane == "edge" else 3 * len(self.F); nb = 3 * len(self.h)
        return (0.5 * r[:nt] @ r[:nt], 0.5 * r[nt:nt + nb] @ r[nt:nt + nb], 0.5 * r[nt + nb:] @ r[nt + nb:])


def lm(prob, x0, max_iter=400, gtol=1e-13, ftol=1e-13, verbose=False):
    x = x0.copy()
    r, J = prob.residual(x)
    cost = 0.5 * r @ r
    mu = 1e-4
    t0 = time.time()
    it = 0
    small = 0
    reason = "max_iter"
    for it in range(1, max_iter + 1):
        g = J.T @ r
        if np.abs(g).max() < gtol:
            reason = "gtol"; break
        H = (J.T @ J).tocsc()
        dg = H.diagonal()
        dfl = np.maximum(dg, 1e-9 * dg.max())
        accepted = False
        for _ in range(40):
            A = H + sp.diags(mu * dfl)
            step = spla.spsolve(A, -g)
            xn = x + step
            rn = prob.residual(xn, jac=False)
            cn = 0.5 * rn @ rn
            if np.isfinite(cn) and cn < cost:
                rel = (cost - cn) / max(cost, 1e-300)
                x, cost = xn, cn
                r, J = prob.residual(x)
                mu = max(mu / 3, 1e-12)
                accepted = True
                small = small + 1 if rel < ftol else 0
                break
            mu *= 4
        if not accepted:
            reason = "no_descent"; break
        if small >= 3:
            reason = "ftol"; break
    info = dict(iterations=it, cost=float(cost), grad_inf=float(np.abs(J.T @ r).max()), seconds=time.time() - t0, stop=reason)
    if verbose:
        print(info)
    return x, info
