"""Y4 solver: X3's stitched-garment IPC solver plus the four ingredients.

Own code (MIT), extending X3's sim.py. What is new here:

  1. Thickness. Contact is ipctk's log barrier with a minimum distance
     dmin (C-IPC style: the barrier is infinite at d = dmin and zero from
     d = dmin + dhat), and every step is capped by Tight-Inclusion CCD run
     at that same minimum distance. X3 had dmin = 0 and the Additive CCD.
  2. Body loads.
     (a) volume floor: k_v/2 * max(0, V* - V_core)^2, where V_core is the
         volume enclosed by the 64 body-core triangles closed by a virtual
         fan cap over the core's 32-edge rim (cap apex = rim centroid).
         The cap is not paper: it has no stiffness, is never drawn and is
         not in contact. V_core is evaluated on the welded sheet (copies
         averaged), so it is translation invariant.
     (b) mouth grips: the torn copies of the four boundary midpoints that
         meet under the body (material (0.5,0), (0,0.5), (1,0.5), (0.5,1))
         are moved toward their spread-0 positions -- a hand opening the
         mouth into the X of the photographed method.
  3. Tension-field core: the edge springs of the core are replaced by a
     per-triangle principal-strain energy that is stiff in tension (k_t)
     and soft in compression (k_t * tf_comp), so paper can gather slack.
  4. (not implemented here; see the report.)

Candidates are built once per Newton iteration over the swept segment
V -> V + D (inflated by dmin + dhat), filtered by MATERIAL adjacency (see
X3 contact.py for why), and reused for the CCD, the line search and the
next iteration's gradient. That is standard IPC practice and cuts the
Python-side filtering, the largest cost, from ~6 to 1 per iteration.
"""
import time
import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spla
import ipctk
from sim import dihedral_and_grad


# --------------------------------------------------------------------- contact
class Contact2:
    def __init__(self, V, T, mat, dhat, kappa, dmin=0.0, ccd='ti'):
        self.T = T.astype(np.int32)
        self.E = ipctk.edges(self.T)
        self.mesh = ipctk.CollisionMesh(V, self.E, self.T)
        self.mat = mat
        self.dhat, self.kappa, self.dmin = dhat, kappa, dmin
        self.B = ipctk.BarrierPotential(dhat, kappa)
        self.Emat = mat[self.E]
        self.Tmat = mat[self.T]
        # TI defaults (tol 1e-6, 1e7 iterations) took 13-17 s per call at dmin = t on
        # this mesh; tol 1e-5 with 1e6 iterations took 0.6 s, gave alpha 0.406 against
        # 0.410 from default TI, and stays conservative
        # (TI returns the start of the first unresolved interval).
        self.ccd = ipctk.TightInclusionCCD(1e-5, 1000000) if ccd == 'ti' else ipctk.AdditiveCCD()

    def _filter(self, c):
        fv, ee, ev, vv = c.fv_candidates, c.ee_candidates, c.ev_candidates, c.vv_candidates
        if len(fv):
            a = np.array([(x.vertex_id, x.face_id) for x in fv])
            keep = ~(self.Tmat[a[:, 1]] == self.mat[a[:, 0]][:, None]).any(1)
            c.fv_candidates = [x for x, k in zip(fv, keep) if k]
        if len(ee):
            a = np.array([(x.edge0_id, x.edge1_id) for x in ee])
            p, q = self.Emat[a[:, 0]], self.Emat[a[:, 1]]
            keep = ~((p[:, :1] == q).any(1) | (p[:, 1:] == q).any(1))
            c.ee_candidates = [x for x, k in zip(ee, keep) if k]
        if len(ev):
            c.ev_candidates = [x for x in ev if self.mat[x.vertex_id] not in self.Emat[x.edge_id]]
        if len(vv):
            c.vv_candidates = [x for x in vv if self.mat[x.vertex0_id] != self.mat[x.vertex1_id]]
        return c

    def candidates(self, V0, V1=None, inflate=None):
        c = ipctk.Candidates()
        r = (self.dmin + self.dhat) if inflate is None else inflate
        if V1 is None:
            c.build(self.mesh, V0, r)
        else:
            c.build(self.mesh, V0, V1, r)
        return self._filter(c)

    def collisions(self, V, cands):
        col = ipctk.NormalCollisions()
        col.build(cands, self.mesh, V, self.dhat, self.dmin)
        return col

    def energy_grad_hess(self, V, cands):
        col = self.collisions(V, cands)
        e = self.B(col, self.mesh, V)
        g = self.B.gradient(col, self.mesh, V)
        H = self.B.hessian(col, self.mesh, V, ipctk.PSDProjectionMethod.CLAMP)
        return e, g, H, len(col)

    def energy(self, V, cands):
        return self.B(self.collisions(V, cands), self.mesh, V)

    def step_size(self, V0, V1, cands):
        return cands.compute_collision_free_stepsize(self.mesh, V0, V1, self.dmin, self.ccd)

    def min_distance(self, V, radius):
        """True smallest distance between non-adjacent elements within radius
        (not the distance above dmin)."""
        c = self.candidates(V, inflate=radius)
        col = ipctk.NormalCollisions()
        col.build(c, self.mesh, V, radius, 0.0)
        if len(col) == 0:
            return np.inf
        return float(np.sqrt(col.compute_minimum_distance(self.mesh, V)))


# --------------------------------------------------------------------- helpers
def pair_blocks(rows, cols, vals, a, b, K):
    for (u, su), (v, sv) in (((a, 1), (a, 1)), ((a, 1), (b, -1)), ((b, -1), (a, 1)), ((b, -1), (b, -1))):
        r = (3 * u[:, None, None] + np.arange(3)[None, :, None]).repeat(3, axis=2)
        c = (3 * v[:, None, None] + np.arange(3)[None, None, :]).repeat(3, axis=1)
        rows.append(r.ravel()); cols.append(c.ravel()); vals.append((su * sv * K).ravel())


def tri_blocks(rows, cols, vals, T3, K9):
    """K9: (n, 9, 9) blocks over the 3 vertices x 3 coords of each triangle."""
    idx = (3 * T3[:, :, None] + np.arange(3)[None, None, :]).reshape(len(T3), 9)
    rows.append(np.repeat(idx, 9, axis=1).ravel()); cols.append(np.tile(idx, (1, 9)).ravel())
    vals.append(K9.ravel())


# --------------------------------------------------------------------- solver
class Sim2:
    def __init__(self, torn, params, regions):
        self.p = dict(params)
        d = torn
        self.V0 = d['V'].copy()
        self.T = d['T']
        self.mat = d['mat']
        M = d['M']
        self.M = M
        self.Mt = M[self.mat]
        n = len(self.V0)
        self.n = n
        self.nmat = len(M)
        # welded averaging A: W = A V (nmat x n)
        cnt = np.bincount(self.mat, minlength=self.nmat).astype(float)
        self.A = sp.csr_matrix((1.0 / cnt[self.mat], (self.mat, np.arange(n))), shape=(self.nmat, n))
        # core
        core_tris = np.array(regions['core_tris'])
        self.core_tris = core_tris
        self.core_loop = np.array(regions['core_loop'])
        self.Fm = d['F']                                   # welded faces (material ids)
        use_tf = self.p.get('tf_core', False)
        # Edge springs on every edge, except (with tf_core) edges whose
        # triangles are all core triangles: those are governed by the
        # tension-field energy alone. Rim edges, shared with a non-core
        # triangle, keep their spring.
        coremask = np.zeros(len(self.T), bool); coremask[core_tris] = True
        E, noncore_edges = set(), set()
        for fi, (a, b, c) in enumerate(self.T):
            for u, v in ((a, b), (b, c), (c, a)):
                key = (min(u, v), max(u, v))
                E.add(key)
                if not coremask[fi]:
                    noncore_edges.add(key)
        if use_tf:
            E = E & noncore_edges
        self.E = np.array(sorted(E))
        self.L0 = np.linalg.norm(self.Mt[self.E[:, 0]] - self.Mt[self.E[:, 1]], axis=1)
        # tension-field triangles
        self.tf_tris = core_tris if use_tf else np.zeros(0, int)
        if len(self.tf_tris):
            Tt = self.T[self.tf_tris]
            Dm = np.stack([self.Mt[Tt[:, 1]] - self.Mt[Tt[:, 0]], self.Mt[Tt[:, 2]] - self.Mt[Tt[:, 0]]], axis=2)  # (k,2,2)
            self.tf_B = np.linalg.inv(Dm)
            self.tf_A = 0.5 * np.abs(np.linalg.det(Dm))
            B = self.tf_B
            self.tf_beta = np.stack([-(B[:, 0, :] + B[:, 1, :]), B[:, 0, :], B[:, 1, :]], axis=1)   # (k,3,2)
        # hinges (as X3)
        H = d['hinges']
        self.H = H[:, :4]
        self.isfold = H[:, 6].astype(bool)
        Xw = d['X']
        ma, mb = H[:, 7], H[:, 8]
        m3, m4 = self.mat[H[:, 2]], self.mat[H[:, 3]]
        th0, _ = dihedral_and_grad(Xw[self.mat[H[:, 0]]], Xw[self.mat[H[:, 1]]], Xw[m3], Xw[m4])
        self.th_rest = np.where(self.isfold, th0, 0.0)
        hl = np.linalg.norm(M[ma] - M[mb], axis=1)
        z = np.zeros(len(ma))
        A1 = 0.5 * np.linalg.norm(np.cross(np.c_[M[mb] - M[ma], z], np.c_[M[m3] - M[ma], z]), axis=1)
        A2 = 0.5 * np.linalg.norm(np.cross(np.c_[M[mb] - M[ma], z], np.c_[M[m4] - M[ma], z]), axis=1)
        self.hw = np.where(self.isfold, self.p['k_c'] * hl, self.p['k_b'] * 3 * hl ** 2 / (A1 + A2))
        self.W = d['welds']
        self.grip_idx = np.zeros(0, int)
        self.grip_tgt = np.zeros((0, 3))
        self.Vstar = 0.0
        self.contact = Contact2(self.V0, self.T, self.mat, self.p['dhat'], self.p['kappa'],
                                self.p.get('dmin', 0.0), self.p.get('ccd', 'ti'))
        self.anchor = self.V0.copy()

    # ------------------------------------------------------------ core volume
    def core_volume(self, W, need_grad=True):
        """Volume of core triangles + fan cap over the rim, on welded W."""
        F = self.Fm[self.core_tris]
        a, b, c = W[F[:, 0]], W[F[:, 1]], W[F[:, 2]]
        vol = np.einsum('ij,ij->i', a, np.cross(b, c)).sum() / 6
        L = self.core_loop
        cen = W[L].mean(0)
        P, Q = W[np.roll(L, -1)], W[L]              # cap triangle (cen, b=next, a=this)
        vol += np.einsum('j,ij->i', cen, np.cross(P, Q)).sum() / 6
        if not need_grad:
            return vol, None
        g = np.zeros_like(W)
        np.add.at(g, F[:, 0], np.cross(b, c) / 6)
        np.add.at(g, F[:, 1], np.cross(c, a) / 6)
        np.add.at(g, F[:, 2], np.cross(a, b) / 6)
        gc = np.cross(P, Q).sum(0) / 6                # d/d cen
        np.add.at(g, np.roll(L, -1), np.cross(Q, cen) / 6)
        np.add.at(g, L, np.cross(cen, P) / 6)
        g[L] += gc / len(L)
        return vol, g

    # ------------------------------------------------------------ elastic
    def elastic(self, V, need_hess=True):
        p = self.p
        n = self.n
        g = np.zeros((n, 3))
        rows, cols, vals = [], [], []
        # membrane edge springs
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
            pair_blocks(rows, cols, vals, a, b, K)
        # tension-field core triangles
        e_tf = 0.0
        if len(self.tf_tris):
            e_tf = self._tf(V, g, rows, cols, vals, need_hess)
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
            pair_blocks(rows, cols, vals, wa, wb, np.broadcast_to(kw * np.eye(3), (len(wa), 3, 3)))
        # grips
        kg = p['k_g']
        e_g = 0.0
        if len(self.grip_idx):
            w = getattr(self, 'grip_w', None)
            w = np.ones(len(self.grip_idx)) if w is None else w     # per-grip stiffness factor
            dg = V[self.grip_idx] - self.grip_tgt
            e_g = 0.5 * kg * np.sum(w[:, None] * dg ** 2)
            np.add.at(g, self.grip_idx, kg * w[:, None] * dg)
            if need_hess:
                idx = (3 * self.grip_idx[:, None] + np.arange(3)[None]).ravel()
                rows.append(idx); cols.append(idx); vals.append(np.repeat(kg * w, 3))
        # anchor
        e_a = 0.0
        ka = p.get('k_anchor', 0.0)
        if ka > 0:
            da = V - self.anchor
            e_a = 0.5 * ka * np.sum(da ** 2)
            g += ka * da
            if need_hess:
                idx = np.arange(3 * n)
                rows.append(idx); cols.append(idx); vals.append(np.full(3 * n, ka))
        # volume floor
        e_v = 0.0
        Hv = None
        kv = p.get('k_v', 0.0)
        if kv > 0 and self.Vstar > 0:
            Wd = self.A @ V
            vol, gW = self.core_volume(Wd)
            short = self.Vstar - vol
            if short > 0:
                e_v = 0.5 * kv * short ** 2
                gV = (self.A.T @ gW)                   # (n,3)
                g += -kv * short * gV
                if need_hess:
                    u = sp.csr_matrix(gV.reshape(-1, 1))
                    Hv = kv * (u @ u.T)                # Gauss-Newton rank one
        parts = dict(membrane=e_mem, tf=e_tf, hinge=e_h, weld=e_w, grip=e_g, anchor=e_a, volume=e_v)
        Hm = None
        if need_hess:
            Hm = sp.coo_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))),
                               shape=(3 * n, 3 * n)).tocsr()
            if Hv is not None:
                Hm = Hm + Hv
        return sum(parts.values()), g.ravel(), Hm, parts

    def _tf(self, V, g, rows, cols, vals, need_hess):
        """Principal Green-strain energy, stiff in tension, soft in compression.
        E = A * sum_i k(eps_i) eps_i^2 / 2,  eps_i = (lam_i - 1)/2, lam_i eig of C = F^T F,
        k = k_t for eps > 0 and k_t * tf_comp for eps < 0."""
        kt = self.p['k_t']
        kc = kt * self.p.get('tf_comp', 1e-3)
        Tt = self.T[self.tf_tris]
        X0, X1, X2 = V[Tt[:, 0]], V[Tt[:, 1]], V[Tt[:, 2]]
        Ds = np.stack([X1 - X0, X2 - X0], axis=2)             # (k,3,2)
        Fg = Ds @ self.tf_B                                    # (k,3,2)
        C = np.transpose(Fg, (0, 2, 1)) @ Fg                   # (k,2,2)
        lam, vec = np.linalg.eigh(C)                           # ascending
        eps = 0.5 * (lam - 1)
        kk = np.where(eps > 0, kt, kc)
        Ar = self.tf_A
        e = float(np.sum(Ar[:, None] * 0.5 * kk * eps ** 2))
        # dE/dlam = A k eps * 1/2
        dl = Ar[:, None] * kk * eps * 0.5                      # (k,2)
        # dE/dC = sum_i dl_i v_i v_i^T ; dE/dF = 2 F dE/dC
        S = np.einsum('ki,kai,kbi->kab', dl, vec, vec)          # (k,2,2)
        P = 2 * Fg @ S                                         # (k,3,2)
        beta = self.tf_beta                                    # (k,3,2) per vertex a, column j
        gv = np.einsum('kdj,kaj->kad', P, beta)                # (k,3 verts,3 dims)
        for a_ in range(3):
            np.add.at(g, Tt[:, a_], gv[:, a_])
        if need_hess:
            K9 = np.zeros((len(Tt), 9, 9))
            # (i) 2 S (x) I term, only the PSD part of S
            Sp = np.einsum('ki,kai,kbi->kab', np.maximum(dl, 0), vec, vec)
            blk = 2 * np.einsum('kaj,kjl,kbl->kab', beta, Sp, beta)    # (k,3,3) vertex-vertex scalars
            K9 += np.einsum('kab,de->kadbe', blk, np.eye(3)).reshape(len(Tt), 9, 9)
            # (ii) rank one per eigenvalue: d2E/dlam2 = A k / 4
            for i in range(2):
                w = 2 * np.einsum('kd,kj->kdj', np.einsum('kdj,kj->kd', Fg, vec[:, :, i]), vec[:, :, i])  # dlam/dF (k,3,2)
                gl = np.einsum('kdj,kaj->kad', w, beta).reshape(len(Tt), 9)
                K9 += (Ar * kk[:, i] * 0.25)[:, None, None] * np.einsum('ki,kj->kij', gl, gl)
            tri_blocks(rows, cols, vals, Tt, K9)
        return e

    # ------------------------------------------------------------ totals
    def total(self, V, cands):
        e, _, _, _ = self.elastic(V, need_hess=False)
        if not self.p.get('contact', True):
            return e
        return e + self.contact.energy(V, cands)

    def solve(self, V, max_iter=40, tol=1e-9):
        t0 = time.time()
        info = dict(ccd_limited=0, backtracks=0, filters=0)
        use_contact = self.p.get('contact', True)   # False: a no-contact control
        cands = self.contact.candidates(V) if use_contact else None
        info['filters'] += 1
        alpha, dmax, g = 0.0, 0.0, np.zeros(1)
        it = 0
        for it in range(1, max_iter + 1):
            e, g, H, parts = self.elastic(V)
            if use_contact:
                eb, gb, Hb, ncol = self.contact.energy_grad_hess(V, cands)
                g = g + gb
                H = (H + Hb).tocsc() + sp.identity(3 * self.n, format='csc') * 1e-9
            else:
                eb = 0.0
                H = H.tocsc() + sp.identity(3 * self.n, format='csc') * 1e-9
            try:
                dx = -spla.spsolve(H, g)
            except Exception:
                dx = -g
            if not np.all(np.isfinite(dx)) or np.dot(dx, g) >= 0:
                dx = -g
            D = dx.reshape(-1, 3)
            dmax = np.abs(D).max()
            if dmax < tol or np.abs(g).max() < self.p.get('gtol', 0.0):
                break
            cap = self.p.get('step_cap', 5e-3)      # trust region: bounds the swept candidate set
            if dmax > cap:
                D = D * (cap / dmax); dx = D.ravel(); dmax = cap
                info['capped'] = info.get('capped', 0) + 1
            if use_contact:
                cands = self.contact.candidates(V, V + D); info['filters'] += 1
                alpha = self.contact.step_size(V, V + D, cands)
            else:
                alpha = 1.0
            if alpha < 1.0:
                info['ccd_limited'] += 1
                alpha *= 0.9
            E0 = e + eb
            slope = np.dot(g, dx)
            while True:
                Vn = V + alpha * D
                En = self.total(Vn, cands)
                if En <= E0 + 1e-4 * alpha * slope or alpha < 1e-12:
                    break
                alpha *= 0.5
                info['backtracks'] += 1
            V = Vn
            if self.p.get('verbose') and it % 10 == 0:
                print(f'    it {it} E {En:.4e} |g| {np.abs(g).max():.2e} alpha {alpha:.3g} step {alpha*dmax:.2e}', flush=True)
            if alpha * dmax < tol:
                break
        _, _, _, parts = self.elastic(V, need_hess=False)
        parts['barrier'] = self.contact.energy(V, self.contact.candidates(V)) if use_contact else 0.0
        info.update(iters=it, seconds=time.time() - t0, last_step=float(alpha * dmax),
                    grad_inf=float(np.abs(g).max()), parts=parts)
        return V, info
