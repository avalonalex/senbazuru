import json, numpy as np
d = json.load(open('/Users/yuhanhao/Project/senbazuru/examples/puffed-square.fold'))
P = np.array(d['vertices_coords'], float); F = d['faces_vertices']
lmax = []; lmin = []; area3 = 0; area2 = 0
for f in F:
    a, b, c = f
    X = np.stack([P[b]-P[a], P[c]-P[a]], 1)          # 3x2 folded
    D = np.stack([P[b,:2]-P[a,:2], P[c,:2]-P[a,:2]], 1)  # 2x2 flat (xy = material)
    Fm = X @ np.linalg.inv(D)
    s = np.linalg.svd(Fm, compute_uv=False)
    lmax.append(s[0]); lmin.append(s[1])
    area3 += 0.5*np.linalg.norm(np.cross(X[:,0], X[:,1])); area2 += 0.5*abs(np.linalg.det(D))
print("faces", len(F), "max principal stretch", round(max(lmax),4), "min", round(min(lmin),4), "area ratio", round(area3/area2,4))
print("zmax", P[:,2].max())
