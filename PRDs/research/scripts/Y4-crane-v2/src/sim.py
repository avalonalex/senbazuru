"""Quasi-static IPC-style solver for the stitched crane (own code, MIT).

Energy (sheet side = 1):
  membrane  : edge springs  k_m/2 (L-L0)^2/L0, rest from material coords
  bending   : k_b * 3 L0^2/(A1+A2) * dtheta^2 on non-fold hinges (rest flat)
  crease    : k_c * L0 * dtheta^2 on fold hinges (rest = closed-crane angle, +-pi)
  weld      : k_w/2 |x_i - x_j|^2 between copies of one material vertex
  grip      : k_g/2 |x_i - p_i|^2 on gripped copies
  contact   : ipctk log barrier (dhat, kappa) on candidates filtered by
              material adjacency (see contact.py)
Solver: projected Newton (PSD-projected / Gauss-Newton Hessians), step
capped by ipctk continuous collision detection (Tight Inclusion) on the same
filtered candidates, then Armijo backtracking.
"""
import time
import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spla
from contact import Contact


def dihedral_and_grad(P1, P2, P3, P4):
    """Signed dihedral angle (0 = flat, +-pi = folded) and its gradient.

    Hinge x1->x2; x3 opposite in face A (x1,x2,x3); x4 opposite in face B.
    Vectorised over hinges. Gradient formula checked against finite
    differences in test_grad()."""
    e = P2 - P1
    le = np.linalg.norm(e, axis=1)
    eh = e / le[:, None]
    n1 = np.cross(e, P3 - P1)
    n2 = np.cross(P4 - P1, e)
    s = np.einsum('ij,ij->i', eh, np.cross(n1, n2))
    c = np.einsum('ij,ij->i', n1, n2)
    th = np.arctan2(s, c)
    q1 = np.einsum('ij,ij->i', n1, n1)
    q2 = np.einsum('ij,ij->i', n2, n2)
    g3 = -(le / q1)[:, None] * n1
    g4 = -(le / q2)[:, None] * n2
    a3 = np.einsum('ij,ij->i', P3 - P1, e) / le**2
    a4 = np.einsum('ij,ij->i', P4 - P1, e) / le**2
    g1 = -(1 - a3)[:, None] * g3 - (1 - a4)[:, None] * g4
    g2 = -a3[:, None] * g3 - a4[:, None] * g4
    return th, np.stack([g1, g2, g3, g4], axis=1)


def test_grad():
    rng = np.random.default_rng(0)
    P = rng.normal(size=(5, 4, 3))
    th, g = dihedral_and_grad(P[:, 0], P[:, 1], P[:, 2], P[:, 3])
    h = 1e-7
    err = 0
    for k in range(4):
        for d in range(3):
            Q = P.copy(); Q[:, k, d] += h
            th2, _ = dihedral_and_grad(Q[:, 0], Q[:, 1], Q[:, 2], Q[:, 3])
            fd = (np.angle(np.exp(1j * (th2 - th)))) / h
            err = max(err, np.abs(fd - g[:, k, d]).max())
    return err


class Sim:
    def __init__(self, torn, params):
        self.p = dict(params)
        d = torn
        self.V0 = d['V'].copy()
        self.T = d['T']
        self.mat = d['mat']
        M = d['M']
        self.Mt = M[self.mat]                       # material coords per torn vertex
        n = len(self.V0)
        self.n = n
        # membrane edges within faces
        E = set()
        for a, b, c in self.T:
            for u, v in ((a, b), (b, c), (c, a)):
                E.add((min(u, v), max(u, v)))
        self.E = np.array(sorted(E))
        self.L0 = np.linalg.norm(self.Mt[self.E[:, 0]] - self.Mt[self.E[:, 1]], axis=1)
        # hinges
        H = d['hinges']
        self.H = H[:, :4]
        self.isfold = H[:, 6].astype(bool)
        Xw = d['X']                                  # closed crane, welded
        ma, mb = H[:, 7], H[:, 8]
        m3, m4 = self.mat[H[:, 2]], self.mat[H[:, 3]]
        # rest angles from the closed crane (welded positions)
        th0, _ = dihedral_and_grad(Xw[self.mat[H[:, 0]]], Xw[self.mat[H[:, 1]]], Xw[m3], Xw[m4])
        self.th_rest = np.where(self.isfold, th0, 0.0)
        hl = np.linalg.norm(M[ma] - M[mb], axis=1)
        A1 = 0.5 * np.linalg.norm(np.cross(np.c_[M[mb] - M[ma], [0] * len(ma)], np.c_[M[m3] - M[ma], [0] * len(ma)]), axis=1)
        A2 = 0.5 * np.linalg.norm(np.cross(np.c_[M[mb] - M[ma], [0] * len(ma)], np.c_[M[m4] - M[ma], [0] * len(ma)]), axis=1)
        self.hw = np.where(self.isfold, self.p['k_c'] * hl, self.p['k_b'] * 3 * hl**2 / (A1 + A2))
        self.W = d['welds']
        self.grip_idx = np.zeros(0, int)
        self.grip_tgt = np.zeros((0, 3))
        self.contact = Contact(self.V0, self.T, self.mat, self.p['dhat'], self.p['kappa'])
        self.stats = []

    # ---------------------------------------------------------------- energy
    def elastic(self, V, need_hess=True):
        p = self.p
        n = self.n
        g = np.zeros((n, 3))
        rows, cols, vals = [], [], []
        # membrane
        a, b = self.E[:, 0], self.E[:, 1]
        dvec = V[a] - V[b]
        L = np.linalg.norm(dvec, axis=1)
        nrm = dvec / L[:, None]
        km = p['k_m']
        e_mem = 0.5 * km * np.sum((L - self.L0) ** 2 / self.L0)
        f = (km * (L - self.L0) / self.L0)[:, None] * nrm
        np.add.at(g, a, f); np.add.at(g, b, -f)
        if need_hess:
            c1 = km / self.L0
            c2 = np.maximum(km * (L - self.L0) / (self.L0 * L), 0.0)
            K = c1[:, None, None] * np.einsum('ij,ik->ijk', nrm, nrm) + \
                c2[:, None, None] * (np.eye(3)[None] - np.einsum('ij,ik->ijk', nrm, nrm))
            self._add_pair_blocks(rows, cols, vals, a, b, K)
        # hinges
        Hh = self.H
        th, gr = dihedral_and_grad(V[Hh[:, 0]], V[Hh[:, 1]], V[Hh[:, 2]], V[Hh[:, 3]])
        dth = np.angle(np.exp(1j * (th - self.th_rest)))
        e_h = np.sum(self.hw * dth ** 2)
        for k in range(4):
            np.add.at(g, Hh[:, k], (2 * self.hw * dth)[:, None] * gr[:, k])
        if need_hess:
            G = gr.reshape(len(Hh), 12)
            Kh = (2 * self.hw)[:, None, None] * np.einsum('ij,ik->ijk', G, G)
            idx = (3 * Hh[:, :, None] + np.arange(3)[None, None, :]).reshape(len(Hh), 12)
            rows.append(np.repeat(idx, 12, axis=1).ravel()); cols.append(np.tile(idx, (1, 12)).ravel()); vals.append(Kh.ravel())
        # welds
        kw = p['k_w']
        wa, wb = self.W[:, 0], self.W[:, 1]
        dw = V[wa] - V[wb]
        e_w = 0.5 * kw * np.sum(dw ** 2)
        np.add.at(g, wa, kw * dw); np.add.at(g, wb, -kw * dw)
        if need_hess and len(wa):
            K = np.broadcast_to(kw * np.eye(3), (len(wa), 3, 3))
            self._add_pair_blocks(rows, cols, vals, wa, wb, K)
        # grips
        kg = p['k_g']
        e_g = 0.0
        if len(self.grip_idx):
            dg = V[self.grip_idx] - self.grip_tgt
            e_g = 0.5 * kg * np.sum(dg ** 2)
            np.add.at(g, self.grip_idx, kg * dg)
            if need_hess:
                idx = (3 * self.grip_idx[:, None] + np.arange(3)[None]).ravel()
                rows.append(idx); cols.append(idx); vals.append(np.full(len(idx), kg))
        # anchor (only used when no grips): weak spring of every vertex to its start
        e_a = 0.0
        ka = p.get('k_anchor', 0.0)
        if ka > 0:
            da = V - self.anchor
            e_a = 0.5 * ka * np.sum(da ** 2)
            g += ka * da
            if need_hess:
                idx = np.arange(3 * n)
                rows.append(idx); cols.append(idx); vals.append(np.full(3 * n, ka))
        parts = dict(membrane=e_mem, hinge=e_h, weld=e_w, grip=e_g, anchor=e_a)
        Hm = None
        if need_hess:
            Hm = sp.coo_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))),
                               shape=(3 * n, 3 * n)).tocsr()
        return sum(parts.values()), g.ravel(), Hm, parts

    @staticmethod
    def _add_pair_blocks(rows, cols, vals, a, b, K):
        # [K -K; -K K]
        for (u, su), (v, sv) in (((a, 1), (a, 1)), ((a, 1), (b, -1)), ((b, -1), (a, 1)), ((b, -1), (b, -1))):
            r = (3 * u[:, None, None] + np.arange(3)[None, :, None]).repeat(3, axis=2)
            c = (3 * v[:, None, None] + np.arange(3)[None, None, :]).repeat(3, axis=1)
            rows.append(r.ravel()); cols.append(c.ravel()); vals.append((su * sv * K).ravel())

    def total(self, V):
        e, _, _, parts = self.elastic(V, need_hess=False)
        eb = self.contact.energy(V)
        return e + eb

    # ---------------------------------------------------------------- solve
    def solve(self, V, max_iter=200, tol=1e-9, label=''):
        t0 = time.time()
        it = 0
        info = dict(ccd_limited=0, backtracks=0)
        for it in range(1, max_iter + 1):
            e, g, H, parts = self.elastic(V)
            eb, gb, Hb, ncol = self.contact.energy_grad_hess(V)
            g = g + gb
            H = (H + Hb).tocsc()
            H = H + sp.identity(3 * self.n, format='csc') * 1e-9
            try:
                dx = -spla.spsolve(H, g)
            except Exception:
                dx = -g
            if np.dot(dx, g) >= 0:
                dx = -g
            D = dx.reshape(-1, 3)
            dmax = np.abs(D).max()
            if dmax < tol:
                break
            alpha = self.contact.step_size(V, V + D)
            if alpha < 1.0:
                info['ccd_limited'] += 1
            alpha *= 0.9 if alpha < 1.0 else 1.0
            E0 = e + eb
            slope = np.dot(g, dx)
            while True:
                Vn = V + alpha * D
                En = self.total(Vn)
                if En <= E0 + 1e-4 * alpha * slope or alpha < 1e-12:
                    break
                alpha *= 0.5
                info['backtracks'] += 1
            V = Vn
            if alpha * dmax < tol:
                break
        _, _, _, parts = self.elastic(V, need_hess=False)
        parts['barrier'] = self.contact.energy(V)
        info.update(iters=it, seconds=time.time() - t0, last_step=float(alpha * dmax) if it else 0.0,
                    grad_inf=float(np.abs(g).max()), parts=parts)
        return V, info
