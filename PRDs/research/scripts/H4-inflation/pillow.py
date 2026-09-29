"""Inflate a sealed two-sheet pillow (square or disc) with a hand-written
L-BFGS on  E = stretch(x) - p * V(x).

Stretch models (all per material triangle, rest area A0, stiffness k):
  tfield : A0 k sum_i max(0, lam_i - 1)^2        (tension field: free to shorten)
  sym    : A0 k sum_i (lam_i - 1)^2               (resists shortening as much as stretching)
  edge1  : per edge  k L max(0, l/L - 1)^2        (one-sided edge springs only)
lam_i are the principal stretches of the triangle's deformation gradient.
V is the enclosed volume by the divergence theorem, V = 1/6 sum x0.(x1 x x2).

Research script for the H4 inflation note; not repository code.
"""
import sys, json
import numpy as np


# ---------------------------------------------------------------- meshes
def square_sheet(n):
    xs = np.linspace(0.0, 1.0, n + 1)
    P = np.array([[x, y] for y in xs for x in xs])
    idx = lambda i, j: j * (n + 1) + i
    T = []
    for j in range(n):
        for i in range(n):
            a, b, c, d = idx(i, j), idx(i + 1, j), idx(i + 1, j + 1), idx(i, j + 1)
            # alternate diagonals so the mesh has no preferred shear direction
            if (i + j) % 2 == 0:
                T += [(a, b, c), (a, c, d)]
            else:
                T += [(a, b, d), (b, c, d)]
    boundary = np.array([k for k, (x, y) in enumerate(P) if x in (0.0, 1.0) or y in (0.0, 1.0)])
    return P, np.array(T), boundary


def disc_sheet(rings):
    """Concentric rings; ring r has 6r vertices; radius 1."""
    P = [[0.0, 0.0]]
    ring_start = [0]
    for r in range(1, rings + 1):
        ring_start.append(len(P))
        m = 6 * r
        for k in range(m):
            t = 2 * np.pi * k / m
            P.append([r / rings * np.cos(t), r / rings * np.sin(t)])
    P = np.array(P)
    T = []
    for r in range(1, rings + 1):
        inner = [0] if r == 1 else list(range(ring_start[r - 1], ring_start[r - 1] + 6 * (r - 1)))
        outer = list(range(ring_start[r], ring_start[r] + 6 * r))
        # walk both rings by angle and zip them into triangles
        ai = [np.arctan2(*P[v][::-1]) % (2 * np.pi) for v in inner]
        ao = [np.arctan2(*P[v][::-1]) % (2 * np.pi) for v in outer]
        i = o = 0
        ni, no = len(inner), len(outer)
        if r == 1:
            for k in range(no):
                T.append((0, outer[k], outer[(k + 1) % no]))
            continue
        while i < ni or o < no:
            ci, co = inner[i % ni], outer[o % no]
            nxt_i = ai[(i + 1) % ni] + (2 * np.pi if i + 1 >= ni else 0)
            nxt_o = ao[(o + 1) % no] + (2 * np.pi if o + 1 >= no else 0)
            if o < no and (i >= ni or nxt_o <= nxt_i):
                T.append((ci, co, outer[(o + 1) % no])); o += 1
            else:
                T.append((ci, co, inner[(i + 1) % ni])); i += 1
    T = np.array(T)
    # orient every triangle anticlockwise in the plane
    for k, (a, b, c) in enumerate(T):
        u, v = P[b] - P[a], P[c] - P[a]
        if u[0] * v[1] - u[1] * v[0] < 0:
            T[k] = (a, c, b)
    boundary = np.arange(ring_start[rings], len(P))
    return P, T, boundary


def pillow(P2, T, boundary, bump=0.02):
    """Top and bottom copies of a flat sheet, sharing boundary vertices."""
    n = len(P2)
    interior = np.setdiff1d(np.arange(n), boundary)
    bottom_id = np.arange(n)
    bottom_id[interior] = n + np.arange(len(interior))
    X = np.zeros((n + len(interior), 3))
    X[:n, :2] = P2
    X[n:, :2] = P2[interior]
    # tiny initial bump so the two sheets have a side to go to
    c = P2.mean(axis=0)
    rmax = np.max(np.linalg.norm(P2 - c, axis=1))
    w = 1 - (np.linalg.norm(P2 - c, axis=1) / rmax) ** 2
    X[:n, 2] = bump * w
    X[n:, 2] = -bump * w[interior]
    top = T.copy()
    bot = bottom_id[T][:, [0, 2, 1]]  # reversed so its normal points down (outward)
    tris = np.vstack([top, bot])
    rest2 = np.vstack([P2[T], P2[T][:, [0, 2, 1]]])  # rest coordinates per triangle
    return X, tris, rest2, n, interior, bottom_id


# ---------------------------------------------------------------- energies
def prep(tris, rest2):
    e1 = rest2[:, 1] - rest2[:, 0]
    e2 = rest2[:, 2] - rest2[:, 0]
    Dm = np.stack([e1, e2], axis=2)  # (m,2,2) columns are edges
    area = 0.5 * np.abs(Dm[:, 0, 0] * Dm[:, 1, 1] - Dm[:, 0, 1] * Dm[:, 1, 0])
    Dinv = np.linalg.inv(Dm)
    return Dinv, area


def stretches(X, tris, Dinv):
    x0, x1, x2 = X[tris[:, 0]], X[tris[:, 1]], X[tris[:, 2]]
    Ds = np.stack([x1 - x0, x2 - x0], axis=2)  # (m,3,2)
    F = Ds @ Dinv  # (m,3,2)
    C = np.transpose(F, (0, 2, 1)) @ F  # (m,2,2)
    w, V = np.linalg.eigh(C)  # ascending
    lam = np.sqrt(np.maximum(w, 1e-30))
    return F, lam, V


def energy_grad(X, tris, Dinv, area, k, p, model, edges=None, L=None):
    F, lam, V = stretches(X, tris, Dinv)
    if model == "tfield":
        g = np.maximum(0.0, lam - 1.0)
    elif model == "sym":
        g = lam - 1.0
    else:
        g = np.zeros_like(lam)
    Es = np.sum(area[:, None] * k * g * g)
    # dE/dlam_i = 2 A k g_i ; dlam_i/dF = F n_i n_i^T / lam_i
    coef = 2 * area[:, None] * k * g / lam  # (m,2)
    dEdF = np.zeros_like(F)
    for i in range(2):
        n = V[:, :, i]  # (m,2)
        dEdF += coef[:, i, None, None] * (F @ (n[:, :, None] * n[:, None, :]))
    H = dEdF @ np.transpose(Dinv, (0, 2, 1))  # (m,3,2) = dE/d(x1-x0), d(x2-x0)
    G = np.zeros_like(X)
    np.add.at(G, tris[:, 1], H[:, :, 0])
    np.add.at(G, tris[:, 2], H[:, :, 1])
    np.add.at(G, tris[:, 0], -H[:, :, 0] - H[:, :, 1])
    if model == "edge1":
        d = X[edges[:, 1]] - X[edges[:, 0]]
        l = np.linalg.norm(d, axis=1)
        s = np.maximum(0.0, l / L - 1.0)
        Es += np.sum(k * L * s * s)
        ge = (2 * k * s)[:, None] * d / l[:, None]
        np.add.at(G, edges[:, 1], ge)
        np.add.at(G, edges[:, 0], -ge)
    # volume
    x0, x1, x2 = X[tris[:, 0]], X[tris[:, 1]], X[tris[:, 2]]
    vol = np.sum(np.einsum("ij,ij->i", x0, np.cross(x1, x2))) / 6.0
    GV = np.zeros_like(X)
    np.add.at(GV, tris[:, 0], np.cross(x1, x2) / 6.0)
    np.add.at(GV, tris[:, 1], np.cross(x2, x0) / 6.0)
    np.add.at(GV, tris[:, 2], np.cross(x0, x1) / 6.0)
    return Es - p * vol, G - p * GV, vol, lam


def lbfgs(fun, x0, iters=4000, m=12, tol=1e-9):
    x = x0.copy()
    f, g = fun(x)
    S, Y = [], []
    for it in range(iters):
        q = g.copy()
        al = []
        for s, y in reversed(list(zip(S, Y))):
            a = np.dot(s, q) / np.dot(y, s)
            al.append(a)
            q -= a * y
        if S:
            q *= np.dot(S[-1], Y[-1]) / np.dot(Y[-1], Y[-1])
        for (s, y), a in zip(zip(S, Y), reversed(al)):
            b = np.dot(y, q) / np.dot(y, s)
            q += (a - b) * s
        d = -q
        if np.dot(d, g) >= 0:
            d = -g; S, Y = [], []
        t = 1.0
        while True:
            xn = x + t * d
            fn, gn = fun(xn)
            if np.isfinite(fn) and fn <= f + 1e-4 * t * np.dot(g, d):
                break
            t *= 0.5
            if t < 1e-14:
                return x, f, it, "line search failed"
        s, y = xn - x, gn - g
        if np.dot(s, y) > 1e-16:
            S.append(s); Y.append(y)
            if len(S) > m:
                S.pop(0); Y.pop(0)
        x, f, g = xn, fn, gn
        if np.max(np.abs(g)) < tol:
            return x, f, it, "converged"
    return x, f, iters, "iteration limit"


def unique_edges(tris):
    e = np.vstack([tris[:, [0, 1]], tris[:, [1, 2]], tris[:, [2, 0]]])
    e = np.sort(e, axis=1)
    return np.unique(e, axis=0)


def run(shape, size, model, p=1.0, ks=(1e2, 1e3, 1e4)):
    if shape == "square":
        P2, T, B = square_sheet(size)
    else:
        P2, T, B = disc_sheet(size)
    X, tris, rest2, n, interior, bottom_id = pillow(P2, T, B)
    Dinv, area = prep(tris, rest2)
    edges = unique_edges(tris)
    # rest length of an edge from any triangle's rest coordinates: rebuild from flat sheet
    flat = np.zeros((len(X), 2)); flat[:n] = P2; flat[n:] = P2[interior]
    L = np.linalg.norm(flat[edges[:, 1]] - flat[edges[:, 0]], axis=1)
    x = X.ravel()
    status = []
    for k in ks:
        fun = lambda z: (lambda E, G, v, lam: (E, G.ravel()))(*energy_grad(z.reshape(-1, 3), tris, Dinv, area, k, p, model, edges, L))
        x, f, it, st = lbfgs(fun, x)
        status.append((k, it, st))
    Xf = x.reshape(-1, 3)
    E, G, vol, lam = energy_grad(Xf, tris, Dinv, area, ks[-1], p, model, edges, L)
    lmax = float(lam.max()); lmin = float(lam.min())
    l = np.linalg.norm(Xf[edges[:, 1]] - Xf[edges[:, 0]], axis=1)
    top_c = Xf[:n][np.argmin(np.linalg.norm(P2 - P2.mean(0), axis=1))]
    bot_c = Xf[bottom_id[np.argmin(np.linalg.norm(P2 - P2.mean(0), axis=1))]]
    area_now = 0.5 * np.linalg.norm(np.cross(Xf[tris[:, 1]] - Xf[tris[:, 0]], Xf[tris[:, 2]] - Xf[tris[:, 0]]), axis=1).sum()
    out = dict(shape=shape, size=size, model=model, vertices=len(Xf), triangles=len(tris),
               volume=float(vol), thickness=float(top_c[2] - bot_c[2]),
               max_principal_stretch=lmax, min_principal_stretch=lmin,
               max_edge_strain=float((l / L - 1).max()), min_edge_strain=float((l / L - 1).min()),
               area_ratio=float(area_now / area.sum()), status=status)
    if shape == "square":
        # waist: how far the midpoint of a side moves inward
        mids = [k for k, (a, b) in enumerate(P2) if abs(a - 0.5) < 1e-9 and b == 0.0]
        out["side_midpoint_inward"] = float(Xf[mids[0]][1] - 0.0) if mids else None
        corners = [k for k, (a, b) in enumerate(P2) if a in (0.0, 1.0) and b in (0.0, 1.0)]
        out["corner_to_corner_diagonal"] = float(np.linalg.norm(Xf[corners[0]] - Xf[corners[-1]]))
        # profile across the middle (top sheet, y = 0.5)
        row = [k for k, (a, b) in enumerate(P2) if abs(b - 0.5) < 1e-9]
        out["mid_profile_top"] = [[round(float(Xf[k][0]), 4), round(float(Xf[k][2]), 4)] for k in row]
    else:
        rim = Xf[B]
        out["rim_radius_mean"] = float(np.linalg.norm(rim[:, :2] - rim[:, :2].mean(0), axis=1).mean())
    np.save(f"X_{shape}_{size}_{model}.npy", Xf)
    np.save(f"T_{shape}_{size}_{model}.npy", tris)
    return out


if __name__ == "__main__":
    shape, size, model = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    res = run(shape, size, model)
    print(json.dumps(res))
