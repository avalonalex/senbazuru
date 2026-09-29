"""Prototype: fold a flat sheet with paper thickness, starting from the flat
sheet (which IS a valid IPC start) and turning crease rest angles in small
increments, one static Newton solve per increment. Contact is ipctk's barrier
on (distance - thickness) with CCD-limited steps, so every accepted state is
intersection-free with layers at least `thickness` apart.

usage: fold_ipc.py N MODE   (MODE = half | double)
  half:   one valley fold along u = 1/2 to 178 degrees.
  double: the half fold, then a second fold of the two-layer packet along
          v = 1/2 (both layers; the outer one must wrap round the inner).
"""
import json, sys, time
import numpy as np
import scipy.sparse as sp
import ipctk
from sksparse.cholmod import cho_factor

N = int(sys.argv[1]) if len(sys.argv) > 1 else 16
MODE = sys.argv[2] if len(sys.argv) > 2 else "half"
KS, KB, KC = 1e4, 1e-3, 1e-1     # stretch, panel bending, crease (illustrative)
THICK = 1 / 1500
DHAT = THICK

# ---- flat sheet, N x N squares, split so both fold lines are mesh edges
X = np.array([[i / N, j / N, 0.0] for i in range(N + 1) for j in range(N + 1)])
vid = lambda i, j: i * (N + 1) + j
F = []
for i in range(N):
    for j in range(N):
        a, b, c, d = vid(i, j), vid(i + 1, j), vid(i + 1, j + 1), vid(i, j + 1)
        F += [(a, b, c), (a, c, d)] if (i < N // 2) == (j < N // 2) else [(a, b, d), (b, c, d)]
F = np.array(F, dtype=np.int32)
nv = len(X)
edge_faces = {}
for fi, (a, b, c) in enumerate(F):
    for (p, q, r) in ((a, b, c), (b, c, a), (c, a, b)):
        edge_faces.setdefault((min(p, q), max(p, q)), []).append((fi, p, q, r))
E = np.array(sorted(edge_faces), dtype=np.int32)
H, kind = [], []
for (p, q), fs in edge_faces.items():
    if len(fs) == 2:
        (f1, a1, b1, o1), (f2, a2, b2, o2) = fs
        H.append((a1, b1, o1, o2))
        up, uq = X[p, 0], X[q, 0]; vp, vq = X[p, 1], X[q, 1]
        kind.append(1 if abs(up - 0.5) < 1e-12 and abs(uq - 0.5) < 1e-12 else
                    2 if abs(vp - 0.5) < 1e-12 and abs(vq - 0.5) < 1e-12 else 0)
H = np.array(H, dtype=np.int32); kind = np.array(kind)
L0 = np.linalg.norm(X[E[:, 0]] - X[E[:, 1]], axis=1)
elen = np.linalg.norm(X[H[:, 0]] - X[H[:, 1]], axis=1)
hinge_w = 3 * elen ** 2 / (1 / N ** 2)

def dihedral_from(x0, x1, x2, x3):
    e0 = x1 - x0
    n1 = np.cross(e0, x2 - x0); n2 = np.cross(x3 - x0, e0)
    s = np.einsum("ij,ij->i", np.cross(n1, n2), e0) / np.linalg.norm(e0, axis=1)
    return np.arctan2(s, np.einsum("ij,ij->i", n1, n2))

def dihedral(Xc):
    return dihedral_from(*(Xc[H[:, k]] for k in range(4)))

def wrap(a):
    return (a + np.pi) % (2 * np.pi) - np.pi

def dihedral_grad(Xc, h=1e-7):
    G = np.zeros((len(H), 12))
    for k in range(4):
        for d in range(3):
            xp = Xc[H[:, k]].copy(); xp[:, d] += h
            xm = Xc[H[:, k]].copy(); xm[:, d] -= h
            ap = [Xc[H[:, m]] if m != k else xp for m in range(4)]
            am = [Xc[H[:, m]] if m != k else xm for m in range(4)]
            G[:, 3 * k + d] = wrap(dihedral_from(*ap) - dihedral_from(*am)) / (2 * h)
    return G

cmesh = ipctk.CollisionMesh(X.copy(), E, F)
barrier = ipctk.BarrierPotential(DHAT, 1.0)
# the half beyond u = 1/2 lies upside down after fold 1, so fold 2 is its mirror
side2 = np.where(0.5 * (X[H[:, 0], 0] + X[H[:, 1], 0]) > 0.5, -1.0, 1.0)
rest = np.zeros(len(H)); stiff = np.where(kind > 0, KC, KB)

def energy(Xc):
    l = np.linalg.norm(Xc[E[:, 0]] - Xc[E[:, 1]], axis=1)
    c = ipctk.NormalCollisions(); c.build(cmesh, Xc, DHAT, THICK)
    return (0.5 * KS * ((l - L0) ** 2 / L0).sum()
            + 0.5 * (stiff * hinge_w * wrap(dihedral(Xc) - rest) ** 2).sum()
            + barrier(c, cmesh, Xc))

def grad_hess(Xc):
    n3 = 3 * nv; g = np.zeros(n3); rows, cols, vals = [], [], []
    d = Xc[E[:, 0]] - Xc[E[:, 1]]; l = np.linalg.norm(d, axis=1); u = d / l[:, None]
    f = (KS * (l - L0) / L0)[:, None] * u
    np.add.at(g, (3 * E[:, 0][:, None] + np.arange(3)).ravel(), f.ravel())
    np.add.at(g, (3 * E[:, 1][:, None] + np.arange(3)).ravel(), -f.ravel())
    uu = u[:, :, None] * u[:, None, :]
    K = (KS / L0)[:, None, None] * (uu + np.clip(1 - L0 / l, 0, None)[:, None, None] * (np.eye(3) - uu))
    for (sa, sb, sg) in ((0, 0, 1), (1, 1, 1), (0, 1, -1), (1, 0, -1)):
        r = 3 * E[:, sa][:, None, None] + np.arange(3)[None, :, None]
        c = 3 * E[:, sb][:, None, None] + np.arange(3)[None, None, :]
        rows.append(np.broadcast_to(r, K.shape).ravel()); cols.append(np.broadcast_to(c, K.shape).ravel()); vals.append((sg * K).ravel())
    G = dihedral_grad(Xc); err = wrap(dihedral(Xc) - rest); w = stiff * hinge_w
    ids = (3 * H[:, :, None] + np.arange(3)).reshape(len(H), 12)
    np.add.at(g, ids.ravel(), ((w * err)[:, None] * G).ravel())
    rows.append(np.repeat(ids, 12, axis=1).ravel()); cols.append(np.tile(ids, (1, 12)).ravel())
    vals.append((w[:, None, None] * G[:, :, None] * G[:, None, :]).ravel())
    Hm = sp.csc_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(n3, n3))
    c = ipctk.NormalCollisions(); c.build(cmesh, Xc, DHAT, THICK)
    g += barrier.gradient(c, cmesh, Xc)
    Hm = Hm + barrier.hessian(c, cmesh, Xc, ipctk.PSDProjectionMethod.CLAMP)
    return g, Hm, len(c)

def solve(Xc, max_it=60):
    for it in range(max_it):
        g, Hm, nc = grad_hess(Xc)
        if np.linalg.norm(g) < 1e-7:
            return Xc, it, nc
        shift = 1e-8
        while True:
            try:
                fac = cho_factor(sp.csc_array(Hm + shift * sp.identity(3 * nv, format="csc"))); break
            except Exception:
                shift *= 100
        dx = -fac.solve(g).reshape(-1, 3)
        alpha = min(1.0, 0.9 * ipctk.compute_collision_free_stepsize(cmesh, Xc, Xc + dx, THICK))
        e0 = energy(Xc)
        while alpha > 1e-12 and energy(Xc + alpha * dx) > e0 + 1e-4 * alpha * g.dot(dx.ravel()):
            alpha *= 0.5
        if alpha <= 1e-12:
            return Xc, it, nc
        Xc = Xc + alpha * dx
    return Xc, max_it, nc

t0 = time.perf_counter(); Xc = X.copy(); log = []
target1 = np.deg2rad(float(sys.argv[3]) if len(sys.argv) > 3 else 178.0)
schedule = [(1, target1 * s / 18) for s in range(1, 19)]
if MODE == "double":
    schedule += [(2, target1 * s / 18) for s in range(1, 19)]
angle = {1: 0.0, 2: 0.0}
for which, a in schedule:
    angle[which] = a
    rest = np.where(kind == 1, angle[1], np.where(kind == 2, angle[2] * side2, 0.0))
    Xc, its, nc = solve(Xc)
    log.append((which, round(float(np.rad2deg(a)), 1), its, nc))
wall = time.perf_counter() - t0
l = np.linalg.norm(Xc[E[:, 0]] - Xc[E[:, 1]], axis=1); strain = l / L0 - 1
cm = ipctk.NormalCollisions(); cm.build(cmesh, Xc, 0.05, 0.0)
th = np.rad2deg(dihedral(Xc))
print(json.dumps({"N": N, "mode": MODE, "dof": 3 * nv, "thickness": THICK, "wall_s": round(wall, 2),
                  "newton_iterations": sum(x[2] for x in log), "increments": len(log),
                  "achieved_crease1_deg": [round(float(th[kind == 1].min()), 2), round(float(th[kind == 1].max()), 2)],
                  "achieved_crease2_deg": [round(float(th[kind == 2].min()), 2), round(float(th[kind == 2].max()), 2)],
                  "max_panel_bend_deg": round(float(np.abs(th[kind == 0]).max()), 2),
                  "max_edge_strain": float(strain.max()), "min_edge_strain": float(strain.min()),
                  "intersections": bool(ipctk.has_intersections(cmesh, Xc)),
                  "min_distance": float(np.sqrt(cm.compute_minimum_distance(cmesh, Xc))),
                  "last_increments": log[-3:]}, indent=1))
with open(f"fold_{MODE}_N{N}.obj", "w") as fh:
    for p in Xc: fh.write(f"v {p[0]} {p[1]} {p[2]}\n")
    for t in F: fh.write(f"f {t[0]+1} {t[1]+1} {t[2]+1}\n")
