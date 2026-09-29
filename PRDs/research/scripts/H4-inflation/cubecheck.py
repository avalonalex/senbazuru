# Where is the cube's sheet shortened, and in which direction relative to the nearest cube edge?
import numpy as np
from cube import cube_mesh
from pillow import prep, stretches
n = 10
X0, tris, rest2 = cube_mesh(n)
Xf = np.load(f"X_cube_{n}.npy")
Dinv, area = prep(tris, rest2)
F, lam, V = stretches(Xf, tris, Dinv)
# rest-state triangle centroids on the flat cube, and the face-local (u,v) centroid
cu = rest2.mean(1)                    # (m,2) in face coordinates
d_edge = np.minimum.reduce([cu[:,0], 1-cu[:,0], cu[:,1], 1-cu[:,1]])
short = lam[:, 0] < 0.99             # shortened by more than 1%
print("triangles", len(tris), "shortened >1%:", int(short.sum()))
print("mean distance to nearest edge (face units): shortened", round(float(d_edge[short].mean()),3), "all", round(float(d_edge.mean()),3))
# direction of shortening in face coordinates (eigenvector of C for smallest eigenvalue)
n2 = V[:, :, 0]
# nearest edge direction: if closest to u=0 or u=1 the edge runs along v (0,1); else along u (1,0)
near_u = np.minimum(cu[:,0], 1-cu[:,0]) < np.minimum(cu[:,1], 1-cu[:,1])
edge_dir = np.where(near_u[:,None], np.array([0.0,1.0]), np.array([1.0,0.0]))
cosang = np.abs(np.sum(n2*edge_dir, axis=1))
sel = short & (d_edge < 0.25)
print("shortened triangles within 0.25 of an edge:", int(sel.sum()), "mean |cos(shortening dir, edge dir)|:", round(float(cosang[sel].mean()),3))
