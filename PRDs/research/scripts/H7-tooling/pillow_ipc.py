"""Prototype: inflate a square paper envelope ("pillow") by pressure, as a
static energy minimisation with an IPC contact barrier from ipctk.

This is a feasibility and cost probe for the H7 research note, not physics
we would ship. Energy = stretching springs + hinge bending (discrete shells,
Gauss-Newton Hessian) - pressure * enclosed volume + ipctk barrier on
(distance - thickness). Newton steps are limited by ipctk's continuous
collision detection so the surface never passes through itself.

usage: pillow_ipc.py N [pressure] [stretch_k]
"""
import json, sys, time
import numpy as np
import scipy.sparse as sp
import ipctk
from sksparse.cholmod import cho_factor

N = int(sys.argv[1]) if len(sys.argv) > 1 else 16
PRESSURE = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
KS = float(sys.argv[3]) if len(sys.argv) > 3 else 1e4
KB = 1e-3
THICK = 1 / 1500          # 0.1 mm on a 15 cm sheet, in sheet lengths
DHAT = THICK              # barrier acts between THICK and 2*THICK
KAPPA = 1.0

# ---------------------------------------------------------------- mesh
# Top and bottom sheets are both the unit square in material coordinates;
# they share the boundary ring (a sewn envelope).
idx = {}
X, U = [], []            # positions, material coords
def vert(side, i, j):
    on_ring = i in (0, N) or j in (0, N)
    key = ("ring", i, j) if on_ring else (side, i, j)
    if key not in idx:
        idx[key] = len(X)
        u, v = i / N, j / N
        bump = 0.05 * np.sqrt(np.sin(np.pi * u) * np.sin(np.pi * v))
        X.append([u, v, bump if side == "top" else -bump])
        U.append([u, v])
    return idx[key]

F = []
for side in ("top", "bot"):
    for i in range(N):
        for j in range(N):
            a, b, c, d = vert(side, i, j), vert(side, i + 1, j), vert(side, i + 1, j + 1), vert(side, i, j + 1)
            if side == "top":        # outward normal +z
                F += [(a, b, c), (a, c, d)]
            else:                    # outward normal -z
                F += [(a, c, b), (a, d, c)]
X = np.array(X); U = np.array(U); F = np.array(F, dtype=np.int32)
nv = len(X)
side_of_face = np.array([0] * (2 * N * N) + [1] * (2 * N * N))

# edges and hinges (edge with its two opposite vertices, oriented)
edge_faces = {}
for fi, (a, b, c) in enumerate(F):
    for (p, q, r) in ((a, b, c), (b, c, a), (c, a, b)):
        edge_faces.setdefault((min(p, q), max(p, q)), []).append((fi, p, q, r))
E = np.array(sorted(edge_faces), dtype=np.int32)
H = []
for (p, q), fs in edge_faces.items():
    if len(fs) == 2:
        (f1, a1, b1, o1), (f2, a2, b2, o2) = fs
        H.append((a1, b1, o1, o2))   # triangle 1 = (x0, x1, x2), triangle 2 contains edge x1->x0 and x3
H = np.array(H, dtype=np.int32)
L0 = np.linalg.norm(np.c_[U, np.zeros(nv)][E[:, 0]] - np.c_[U, np.zeros(nv)][E[:, 1]], axis=1)

def dihedral(Xc):
    x0, x1, x2, x3 = (Xc[H[:, k]] for k in range(4))
    e0 = x1 - x0
    n1 = np.cross(e0, x2 - x0)
    n2 = np.cross(x3 - x0, e0)
    s = np.einsum("ij,ij->i", np.cross(n1, n2), e0) / np.linalg.norm(e0, axis=1)
    c = np.einsum("ij,ij->i", n1, n2)
    return np.arctan2(s, c)

def wrap(a):
    return (a + np.pi) % (2 * np.pi) - np.pi

theta_rest = dihedral(X)                 # rest = start: flat sheets, folded seam
A_rest = np.full(len(F), 0.5 / N**2)
hinge_w = 3 * np.sum((U[H[:, 0]] - U[H[:, 1]]) ** 2, axis=1) / (1 / N**2)   # 3|e|^2/(A1+A2), rest values

def dihedral_grad(Xc, h=1e-7):
    """d theta / d x for every hinge, 12 columns, by central differences."""
    G = np.zeros((len(H), 12))
    for k in range(4):
        for d in range(3):
            # perturb only the k-th vertex of every hinge: do it per hinge
            xp = Xc[H[:, k]].copy(); xp[:, d] += h
            xm = Xc[H[:, k]].copy(); xm[:, d] -= h
            args_p = [Xc[H[:, m]] if m != k else xp for m in range(4)]
            args_m = [Xc[H[:, m]] if m != k else xm for m in range(4)]
            G[:, 3 * k + d] = wrap(dihedral_from(*args_p) - dihedral_from(*args_m)) / (2 * h)
    return G

def dihedral_from(x0, x1, x2, x3):
    e0 = x1 - x0
    n1 = np.cross(e0, x2 - x0)
    n2 = np.cross(x3 - x0, e0)
    s = np.einsum("ij,ij->i", np.cross(n1, n2), e0) / np.linalg.norm(e0, axis=1)
    c = np.einsum("ij,ij->i", n1, n2)
    return np.arctan2(s, c)

def volume(Xc):
    a, b, c = Xc[F[:, 0]], Xc[F[:, 1]], Xc[F[:, 2]]
    return np.einsum("ij,ij->i", a, np.cross(b, c)).sum() / 6

cmesh = ipctk.CollisionMesh(X.copy(), E, F)
barrier = ipctk.BarrierPotential(DHAT, KAPPA)

def energy(Xc, cols=None):
    d = Xc[E[:, 0]] - Xc[E[:, 1]]
    l = np.linalg.norm(d, axis=1)
    es = 0.5 * KS * ((l - L0) ** 2 / L0).sum()
    eb = 0.5 * KB * (hinge_w * wrap(dihedral(Xc) - theta_rest) ** 2).sum()
    ep = -PRESSURE * volume(Xc)
    if cols is None:
        cols = ipctk.NormalCollisions(); cols.build(cmesh, Xc, DHAT, THICK)
    ec = barrier(cols, cmesh, Xc)
    return es + eb + ep + ec

def gradient_and_hessian(Xc, timing):
    t0 = time.perf_counter()
    n3 = 3 * nv
    g = np.zeros(n3)
    rows, cols_, vals = [], [], []
    # stretching springs: exact gradient, PSD-clamped Hessian
    d = Xc[E[:, 0]] - Xc[E[:, 1]]
    l = np.linalg.norm(d, axis=1); u = d / l[:, None]
    f = (KS * (l - L0) / L0)[:, None] * u
    np.add.at(g, (3 * E[:, 0][:, None] + np.arange(3)).ravel(), f.ravel())
    np.add.at(g, (3 * E[:, 1][:, None] + np.arange(3)).ravel(), -f.ravel())
    uu = u[:, :, None] * u[:, None, :]
    shrink = np.clip(1 - L0 / l, 0, None)[:, None, None]
    K = (KS / L0)[:, None, None] * (uu + shrink * (np.eye(3) - uu))
    for (sa, sb, sign) in ((0, 0, 1), (1, 1, 1), (0, 1, -1), (1, 0, -1)):
        r = 3 * E[:, sa][:, None, None] + np.arange(3)[None, :, None]
        c = 3 * E[:, sb][:, None, None] + np.arange(3)[None, None, :]
        rows.append(np.broadcast_to(r, K.shape).ravel()); cols_.append(np.broadcast_to(c, K.shape).ravel()); vals.append((sign * K).ravel())
    # bending: Gauss-Newton
    G = dihedral_grad(Xc)
    err = wrap(dihedral(Xc) - theta_rest)
    wgt = KB * hinge_w
    ids = (3 * H[:, :, None] + np.arange(3)).reshape(len(H), 12)
    np.add.at(g, ids.ravel(), ((wgt * err)[:, None] * G).ravel())
    B = wgt[:, None, None] * G[:, :, None] * G[:, None, :]
    rows.append(np.repeat(ids, 12, axis=1).ravel()); cols_.append(np.tile(ids, (1, 12)).ravel()); vals.append(B.ravel())
    # pressure: gradient only (its Hessian is indefinite; left out)
    a, b, c = Xc[F[:, 0]], Xc[F[:, 1]], Xc[F[:, 2]]
    for k, t in ((0, np.cross(b, c)), (1, np.cross(c, a)), (2, np.cross(a, b))):
        np.add.at(g, (3 * F[:, k][:, None] + np.arange(3)).ravel(), (-PRESSURE / 6 * t).ravel())
    Hm = sp.csc_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols_))), shape=(n3, n3))
    t1 = time.perf_counter()
    # contact barrier from ipctk
    cols = ipctk.NormalCollisions(); cols.build(cmesh, Xc, DHAT, THICK)
    g += barrier.gradient(cols, cmesh, Xc)
    Hm = Hm + barrier.hessian(cols, cmesh, Xc, ipctk.PSDProjectionMethod.CLAMP)
    t2 = time.perf_counter()
    timing["assemble"] += t1 - t0; timing["barrier"] += t2 - t1
    return g, Hm, cols

timing = {"assemble": 0.0, "barrier": 0.0, "solve": 0.0, "ccd": 0.0, "linesearch": 0.0}
Xc = X.copy()
assert not ipctk.has_intersections(cmesh, Xc)
t_start = time.perf_counter()
history = []
for it in range(200):
    g, Hm, cols = gradient_and_hessian(Xc, timing)
    gn = np.linalg.norm(g)
    history.append((it, float(energy(Xc)), float(gn), len(cols)))
    if gn < 1e-6 * (1 + PRESSURE):
        break
    t0 = time.perf_counter()
    shift = 1e-8
    while True:   # Levenberg shift: grow it until the matrix factors
        try:
            fac = cho_factor(sp.csc_array(Hm + shift * sp.identity(3 * nv, format="csc")))
            break
        except Exception:
            shift *= 100
    dx = -fac.solve(g)
    t1 = time.perf_counter()
    X1 = Xc + dx.reshape(-1, 3)
    alpha = min(1.0, 0.9 * ipctk.compute_collision_free_stepsize(cmesh, Xc, X1, THICK))
    t2 = time.perf_counter()
    e0 = energy(Xc)
    while alpha > 1e-12:
        Xt = Xc + alpha * dx.reshape(-1, 3)
        if energy(Xt) <= e0 + 1e-4 * alpha * g.dot(dx):
            break
        alpha *= 0.5
    t3 = time.perf_counter()
    timing["solve"] += t1 - t0; timing["ccd"] += t2 - t1; timing["linesearch"] += t3 - t2
    if alpha <= 1e-12:
        break
    Xc = Xt
wall = time.perf_counter() - t_start

d = Xc[E[:, 0]] - Xc[E[:, 1]]
strain = np.linalg.norm(d, axis=1) / L0 - 1
cmin = ipctk.NormalCollisions(); cmin.build(cmesh, Xc, 0.05, 0.0)
report = {
    "N": N, "vertices": nv, "dof": 3 * nv, "triangles": len(F), "hinges": len(H),
    "pressure": PRESSURE, "stretch_k": KS, "bend_k": KB, "thickness": THICK,
    "iterations": len(history), "final_grad_norm": history[-1][2], "wall_s": wall,
    "timing_s": timing, "height": float(Xc[:, 2].max() - Xc[:, 2].min()),
    "max_edge_strain": float(strain.max()), "min_edge_strain": float(strain.min()),
    "intersections": bool(ipctk.has_intersections(cmesh, Xc)),
    "min_distance": float(np.sqrt(cmin.compute_minimum_distance(cmesh, Xc))) if len(cmin) else None,
}
print(json.dumps(report, indent=1))
np.save(f"pillow_N{N}_p{PRESSURE}_k{KS}.npy", Xc)
with open(f"pillow_N{N}_p{PRESSURE}_k{KS}.obj", "w") as fh:
    for p in Xc: fh.write(f"v {p[0]} {p[1]} {p[2]}\n")
    for t in F: fh.write(f"f {t[0]+1} {t[1]+1} {t[2]+1}\n")
