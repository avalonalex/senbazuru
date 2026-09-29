# Faces turned away and silhouette edges from the repo's iso direction (-1,1,-1).
import json, numpy as np
d = np.array([-1.0, 1.0, -1.0]); d /= np.linalg.norm(d)
def count(X, T, name):
    n = np.cross(X[T[:,1]]-X[T[:,0]], X[T[:,2]]-X[T[:,0]])
    away = (n @ d) > 0
    edges = {}
    for k, t in enumerate(T):
        for a, b in ((t[0],t[1]),(t[1],t[2]),(t[2],t[0])):
            edges.setdefault((min(a,b),max(a,b)), []).append(k)
    sil = sum(1 for fs in edges.values() if len(fs)==2 and away[fs[0]] != away[fs[1]])
    print(f"{name}: faces {len(T)}, turned away {int(away.sum())}, silhouette edges {sil}")
fx = json.load(open('/Users/yuhanhao/Project/senbazuru/examples/puffed-square.fold'))
P = np.array(fx['vertices_coords'], float); F = np.array(fx['faces_vertices'])
# orient faces upward like a folded form viewed from above
nz = np.cross(P[F[:,1]]-P[F[:,0]], P[F[:,2]]-P[F[:,0]])[:,2]
F = np.where(nz[:,None] < 0, F[:, [0,2,1]], F)
count(P, F, "puffed-square.fold (single sheet, normals up)")
X = np.load('X_square_16_tfield.npy'); T = np.load('T_square_16_tfield.npy')
count(X, T, "tension-field pillow 16x16 (closed, normals out)")
