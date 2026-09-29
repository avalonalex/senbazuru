# Is the follower pressure force the gradient of something? Check symmetry of its Jacobian.
import numpy as np
from pillow import square_sheet, pillow
rng = np.random.default_rng(0)
P2, T, B = square_sheet(4)
X, tris, rest2, n, interior, bottom_id = pillow(P2, T, B, bump=0.2)
X += 0.05 * rng.standard_normal(X.shape)

def force(X, tris):
    f = np.zeros_like(X)
    x0, x1, x2 = X[tris[:, 0]], X[tris[:, 1]], X[tris[:, 2]]
    an = 0.5 * np.cross(x1 - x0, x2 - x0)  # area * normal
    for k in range(3):
        np.add.at(f, tris[:, k], an / 3.0)
    return f.ravel()

def asym(X, tris):
    used = np.unique(tris)
    x = X.copy(); m = X.size; J = np.zeros((m, m)); h = 1e-6
    for j in range(m):
        e = np.zeros(m); e[j] = h
        J[:, j] = (force((x.ravel() + e).reshape(-1, 3), tris) - force((x.ravel() - e).reshape(-1, 3), tris)) / (2 * h)
    idx = np.concatenate([3 * used + k for k in range(3)])
    J = J[np.ix_(idx, idx)]
    return np.linalg.norm(J - J.T) / np.linalg.norm(J)

closed = tris
top_only = tris[: len(tris) // 2]
print("closed pillow: |J-J^T|/|J| =", asym(X, closed))
print("open sheet (top only): |J-J^T|/|J| =", asym(X, top_only))
# translation dependence of the divergence-theorem 'volume' of the open sheet
def vol(X, tris):
    x0, x1, x2 = X[tris[:, 0]], X[tris[:, 1]], X[tris[:, 2]]
    return np.sum(np.einsum('ij,ij->i', x0, np.cross(x1, x2))) / 6
t = np.array([0.3, -0.2, 0.7])
print("closed volume change under translation:", vol(X + t, closed) - vol(X, closed))
print("open 'volume' change under translation:", vol(X + t, top_only) - vol(X, top_only))
