"""Small quasi-static shell solver for inflated paper (experiment X2).

Own code, written for this experiment. Triangle mesh, flat rest state.
Energy  Pi(x) = E_membrane + E_bending - p * V
  membrane : per-triangle St.Venant-Kirchhoff with nu = 0,
             psi = ks/2 * sum_i g(e_i)^2 over the principal Green strains e_i;
             g(e) = e ("full") or max(e, 0) ("tension-field": compression is
             free, i.e. it is assumed to be absorbed by wrinkles too fine to mesh)
  bending  : discrete-shell hinge energy kb/2 * sum_h 3|e|^2/(A1+A2) * theta_h^2
             over interior hinges of each sheet (seam hinges are free).
  pressure : V = 1/6 sum_t x0.(x1 x x2) over the closed surface.
Minimised with scipy L-BFGS-B in load steps of p.
"""

import json
import sys
import time

import numpy as np
import scipy.optimize as so
from scipy.spatial import Delaunay

# ---------------------------------------------------------------- meshes


def grid_square(n):
    xs = np.linspace(0.0, 1.0, n + 1)
    X, Y = np.meshgrid(xs, xs, indexing="xy")
    P = np.stack([X.ravel(), Y.ravel()], axis=1)
    idx = lambda i, j: j * (n + 1) + i  # noqa: E731
    tris = []
    for j in range(n):
        for i in range(n):
            a, b, c, d = idx(i, j), idx(i + 1, j), idx(i + 1, j + 1), idx(i, j + 1)
            if (i + j) % 2 == 0:
                tris += [(a, b, c), (a, c, d)]
            else:
                tris += [(a, b, d), (b, c, d)]
    T = np.array(tris)
    bnd = (np.isclose(P[:, 0], 0) | np.isclose(P[:, 0], 1) |
           np.isclose(P[:, 1], 0) | np.isclose(P[:, 1], 1))
    return P, T, bnd


def disk(R):
    pts = [(0.0, 0.0)]
    for k in range(1, R + 1):
        m = 6 * k
        off = 0.5 * (k % 2) * 2 * np.pi / m
        for j in range(m):
            t = off + 2 * np.pi * j / m
            pts.append((k / R * np.cos(t), k / R * np.sin(t)))
    P = np.array(pts)
    T = Delaunay(P).simplices.copy()
    # drop slivers on the convex hull (all three vertices on the rim)
    rr = np.linalg.norm(P, axis=1)
    bnd = np.isclose(rr, 1.0)
    T = T[~bnd[T].all(axis=1)]
    # orient CCW
    a, b, c = P[T[:, 0]], P[T[:, 1]], P[T[:, 2]]
    cr = (b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (b[:, 1] - a[:, 1]) * (c[:, 0] - a[:, 0])
    T[cr < 0] = T[cr < 0][:, [0, 2, 1]]
    return P, T, bnd


def pillow(P, T, bnd):
    """Two copies of a flat sheet sharing boundary vertices. Top faces +z,
    bottom faces -z. Returns rest 2D coords, 3D verts (flat), faces, sheet id."""
    nv = len(P)
    interior = np.where(~bnd)[0]
    remap = np.arange(nv)
    remap[interior] = nv + np.arange(len(interior))
    rest2 = np.vstack([P, P[interior]])
    Tb = remap[T][:, [0, 2, 1]]
    F = np.vstack([T, Tb])
    sheet = np.r_[np.zeros(len(T), int), np.ones(len(Tb), int)]
    top = np.r_[np.ones(nv, bool), np.zeros(len(interior), bool)]
    top[np.where(bnd)[0]] = False  # seam belongs to neither sheet
    bot = np.r_[np.zeros(nv, bool), np.ones(len(interior), bool)]
    return rest2, F, sheet, top, bot


def hinges(F, sheet):
    emap = {}
    for t, (a, b, c) in enumerate(F):
        for (u, v, w) in ((a, b, c), (b, c, a), (c, a, b)):
            emap.setdefault((min(u, v), max(u, v)), []).append((t, u, v, w))
    H = []
    for lst in emap.values():
        if len(lst) != 2:
            continue
        (tA, u, v, w), (tB, u2, v2, w2) = lst
        if sheet[tA] != sheet[tB]:
            continue  # seam: a free hinge
        H.append((u, v, w, w2))  # edge u->v in tri A (opp w); tri B has v->u (opp w2)
    return np.array(H, int)


# ---------------------------------------------------------------- model


class Model:
    def __init__(self, rest2, F, sheet, ks, kb, mode="tension", fixed=None):
        self.F = F
        self.ks, self.kb, self.mode = ks, kb, mode
        Dm = np.stack([rest2[F[:, 1]] - rest2[F[:, 0]], rest2[F[:, 2]] - rest2[F[:, 0]]], axis=2)
        self.Bm = np.linalg.inv(Dm)
        self.A0 = 0.5 * np.abs(np.linalg.det(Dm))
        self.H = hinges(F, sheet)
        # hinge rest weights 3|e|^2/(A1+A2)
        tri_of = {}
        for t, (a, b, c) in enumerate(F):
            for (u, v) in ((a, b), (b, c), (c, a)):
                tri_of[(u, v)] = t
        if len(self.H):
            e2 = np.sum((rest2[self.H[:, 1]] - rest2[self.H[:, 0]]) ** 2, axis=1)
            tA = np.array([tri_of[(u, v)] for u, v in self.H[:, :2]])
            tB = np.array([tri_of[(v, u)] for u, v in self.H[:, :2]])
            self.hw = 3 * e2 / (self.A0[tA] + self.A0[tB])
        else:
            self.hw = np.zeros(0)
        self.nv = len(rest2)
        self.Jmin = 0.5
        self.fixed = np.zeros(self.nv, bool) if fixed is None else fixed
        self.p = 0.0

    # principal Green strains per triangle
    def strains(self, x):
        F = self.F
        Ds = np.stack([x[F[:, 1]] - x[F[:, 0]], x[F[:, 2]] - x[F[:, 0]]], axis=2)
        Fd = Ds @ self.Bm
        C = np.transpose(Fd, (0, 2, 1)) @ Fd
        E = 0.5 * (C - np.eye(2))
        w, V = np.linalg.eigh(E)
        return Fd, w, V

    def membrane(self, x, grad):
        Fd, w, V = self.strains(x)
        g = np.maximum(w, 0.0) if self.mode == "tension" else w
        e = 0.5 * self.ks * np.sum(g ** 2, axis=1) * self.A0
        S = self.ks * np.einsum("ti,tai,tbi->tab", g, V, V)
        Pk = Fd @ S
        # area barrier: a triangle may not shrink below Jmin of its rest area
        # (keeps free compression from collapsing elements to zero area)
        lam2 = np.maximum(1 + 2 * w, 1e-12)
        J = np.sqrt(lam2[:, 0] * lam2[:, 1])
        bad = J < self.Jmin
        if np.any(bad):
            kc = self.ks
            e = e + np.where(bad, kc * (self.Jmin - J) ** 2, 0.0) * self.A0
            dEdJ = np.where(bad, -2 * kc * (self.Jmin - J), 0.0)
            C = np.transpose(Fd, (0, 2, 1)) @ Fd
            Cinv = np.linalg.inv(C[bad])
            Pk[bad] += (dEdJ[bad] * J[bad])[:, None, None] * (Fd[bad] @ Cinv)
        Hm = self.A0[:, None, None] * (Pk @ np.transpose(self.Bm, (0, 2, 1)))
        np.add.at(grad, self.F[:, 1], Hm[:, :, 0])
        np.add.at(grad, self.F[:, 2], Hm[:, :, 1])
        np.add.at(grad, self.F[:, 0], -Hm[:, :, 0] - Hm[:, :, 1])
        return e.sum()

    def dihedral(self, x):
        H = self.H
        x1, x2, x3, x4 = x[H[:, 0]], x[H[:, 1]], x[H[:, 2]], x[H[:, 3]]
        E = x2 - x1
        el = np.linalg.norm(E, axis=1)
        nA = np.cross(E, x3 - x1)
        nB = np.cross(x1 - x2, x4 - x2)
        nA2 = np.sum(nA ** 2, axis=1)
        nB2 = np.sum(nB ** 2, axis=1)
        uA = nA / np.sqrt(nA2)[:, None]
        uB = nB / np.sqrt(nB2)[:, None]
        sin = np.sum(np.cross(uA, uB) * (E / el[:, None]), axis=1)
        cos = np.sum(uA * uB, axis=1)
        th = np.arctan2(sin, cos)
        return th, (x1, x2, x3, x4, E, el, nA, nB, nA2, nB2)

    def bending(self, x, grad):
        if len(self.H) == 0 or self.kb == 0:
            return 0.0
        th, (x1, x2, x3, x4, E, el, nA, nB, nA2, nB2) = self.dihedral(x)
        c = self.kb * self.hw * th  # dE/dtheta
        eh = E / el[:, None]
        a = nA / nA2[:, None]
        b = nB / nB2[:, None]
        g3 = el[:, None] * a
        g4 = el[:, None] * b
        g1 = np.sum((x3 - x2) * eh, 1)[:, None] * a + np.sum((x4 - x2) * eh, 1)[:, None] * b
        g2 = -(np.sum((x3 - x1) * eh, 1)[:, None] * a + np.sum((x4 - x1) * eh, 1)[:, None] * b)
        s = -1.0  # sign fixed by the finite-difference check in selftest()
        for k, gk in ((0, g1), (1, g2), (2, g3), (3, g4)):
            np.add.at(grad, self.H[:, k], s * c[:, None] * gk)
        return 0.5 * self.kb * np.sum(self.hw * th ** 2)

    def volume(self, x, grad=None):
        a, b, c = x[self.F[:, 0]], x[self.F[:, 1]], x[self.F[:, 2]]
        if grad is not None:
            np.add.at(grad, self.F[:, 0], np.cross(b, c) / 6)
            np.add.at(grad, self.F[:, 1], np.cross(c, a) / 6)
            np.add.at(grad, self.F[:, 2], np.cross(a, b) / 6)
        return np.sum(np.einsum("ti,ti->t", a, np.cross(b, c))) / 6

    def energy(self, x, want_grad=True):
        g = np.zeros_like(x)
        em = self.membrane(x, g)
        eb = self.bending(x, g)
        gv = np.zeros_like(x)
        v = self.volume(x, gv)
        g -= self.p * gv
        return em + eb - self.p * v, g


def selftest():
    rng = np.random.default_rng(1)
    P, T, bnd = grid_square(3)
    rest2, F, sheet, top, bot = pillow(P, T, bnd)
    for mode in ("full", "tension"):
        m = Model(rest2, F, sheet, ks=3.0, kb=0.7, mode=mode)
        m.p = 1.3
        x = np.c_[rest2, np.zeros(len(rest2))] + 0.1 * rng.standard_normal((len(rest2), 3))
        e0, g = m.energy(x)
        d = rng.standard_normal(x.shape)
        h = 1e-6
        ep, _ = m.energy(x + h * d)
        em, _ = m.energy(x - h * d)
        fd = (ep - em) / (2 * h)
        an = np.sum(g * d)
        print(f"selftest {mode}: fd={fd:.8f} analytic={an:.8f} relerr={abs(fd-an)/abs(fd):.2e}")


# ---------------------------------------------------------------- solve


def solve(model, x0, pressures, tol=1e-5, maxiter=20000, scale=1.0, log=None):
    """tol is on the scaled gradient (max-abs)."""
    free = ~model.fixed
    x = x0.copy()
    stats = []
    for p in pressures:
        model.p = p

        def f(z):
            xx = x.copy()
            xx[free] = z.reshape(-1, 3)
            e, g = model.energy(xx)
            return scale * e, scale * g[free].ravel()

        t0 = time.perf_counter()
        r = so.minimize(f, x[free].ravel(), jac=True, method="L-BFGS-B",
                        options=dict(maxiter=maxiter, maxfun=maxiter * 2, maxcor=30,
                                     ftol=1e-15, gtol=tol))
        dt = time.perf_counter() - t0
        x[free] = r.x.reshape(-1, 3)
        gmax = np.abs(r.jac).max() / scale
        stats.append(dict(p=p, nit=int(r.nit), nfev=int(r.nfev), seconds=dt,
                          gmax=float(gmax), V=float(model.volume(x)), msg=str(r.message)))
        if log:
            log(stats[-1])
    return x, stats


def measure(model, x, rest2):
    Fd, w, V = model.strains(x)
    lam = np.sqrt(np.maximum(1 + 2 * w, 0))  # principal stretches
    A0 = model.A0
    F = model.F
    # edge stretch
    E = np.r_[F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]]
    l0 = np.linalg.norm(rest2[E[:, 1]] - rest2[E[:, 0]], axis=1)
    l1 = np.linalg.norm(x[E[:, 1]] - x[E[:, 0]], axis=1)
    th, _ = model.dihedral(x) if len(model.H) else (np.zeros(0), None)
    comp = 1 - lam[:, 0]
    return dict(
        V=float(model.volume(x)),
        max_stretch=float(lam[:, 1].max() - 1),
        max_edge_stretch=float((l1 / l0).max() - 1),
        max_compression=float(comp.max()),
        area_frac_compressed_1pct=float(A0[comp > 0.01].sum() / A0.sum()),
        area_frac_compressed_5pct=float(A0[comp > 0.05].sum() / A0.sum()),
        thickness=float(x[:, 2].max() - x[:, 2].min()),
        max_abs_dihedral_deg=float(np.degrees(np.abs(th)).max()) if len(th) else 0.0,
        p95_abs_dihedral_deg=float(np.percentile(np.degrees(np.abs(th)), 95)) if len(th) else 0.0,
    ), lam


def write_obj(path, x, F):
    with open(path, "w") as fh:
        for v in x:
            fh.write(f"v {v[0]:.6f} {v[1]:.6f} {v[2]:.6f}\n")
        for t in F:
            fh.write(f"f {t[0]+1} {t[1]+1} {t[2]+1}\n")


if __name__ == "__main__":
    selftest()
