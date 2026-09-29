"""Can the closed crane be given paper thickness naively, so that an IPC
solve could start from it? Separate coplanar layers by t per layer along
their plane normal (ranks from faceOrders by longest path), move each shared
vertex by the mean of its faces' offsets, then ask ipctk about intersections
and the smallest gap."""
import json, sys, collections
import numpy as np, ipctk

d = json.load(open(sys.argv[1]))
X = np.array(d["vertices_coords"]); F = np.array(d["faces_vertices"], dtype=np.int32)
t = float(sys.argv[2]) if len(sys.argv) > 2 else 1 / 1500
flip = len(sys.argv) > 3 and sys.argv[3] == "flip"
n = np.cross(X[F[:, 1]] - X[F[:, 0]], X[F[:, 2]] - X[F[:, 0]])
n /= np.linalg.norm(n, axis=1)[:, None]
# plane groups: faces in one faceOrders pair are coplanar; union them
parent = list(range(len(F)))
def find(a):
    while parent[a] != a:
        parent[a] = parent[parent[a]]; a = parent[a]
    return a
for f, g, s in d["faceOrders"]:
    parent[find(f)] = find(g)
groups = collections.defaultdict(list)
for f in range(len(F)): groups[find(f)].append(f)
canon = {r: n[fs[0]] for r, fs in groups.items()}
sigma = np.array([1.0 if np.dot(n[f], canon[find(f)]) > 0 else -1.0 for f in range(len(F))])
above = collections.defaultdict(set)   # lower -> uppers along the canonical normal
for f, g, s in d["faceOrders"]:
    if flip: s = -s
    f_up = (s * sigma[g]) > 0            # FOLD: s=+1 puts f on the side of g's normal
    lo, hi = (g, f) if f_up else (f, g)
    above[lo].add(hi)
# longest path ranks (Kahn); a cycle leaves faces unranked
indeg = collections.Counter(h for l in above for h in above[l])
rank = np.zeros(len(F)); queue = [f for f in range(len(F)) if indeg[f] == 0]; seen = 0
while queue:
    l = queue.pop(); seen += 1
    for h in above[l]:
        rank[h] = max(rank[h], rank[l] + 1); indeg[h] -= 1
        if indeg[h] == 0: queue.append(h)
# centre each group's ranks so the stack straddles the original plane
for r, fs in groups.items():
    rank[fs] -= (rank[fs].max() + rank[fs].min()) / 2
disp = np.zeros_like(X); cnt = np.zeros(len(X))
for f in range(len(F)):
    for v in F[f]:
        disp[v] += rank[f] * t * canon[find(f)]; cnt[v] += 1
Y = X + disp / cnt[:, None]
E = np.array(sorted({(min(a, b), max(a, b)) for tri in F for a, b in ((tri[0], tri[1]), (tri[1], tri[2]), (tri[2], tri[0]))}), dtype=np.int32)
m = ipctk.CollisionMesh(Y, E, F)
c = ipctk.NormalCollisions(); c.build(m, Y, t, 0.0)
print(f"{sys.argv[1]} t={t:.2e} flip={flip}: plane groups={len(groups)} ordered faces={seen}/{len(F)} "
      f"max layers in a group={int(max(rank[fs].max()-rank[fs].min() for fs in groups.values()))+1} "
      f"intersections={ipctk.has_intersections(m, Y)} stencils within t={len(c)} "
      f"min distance={np.sqrt(c.compute_minimum_distance(m, Y)) if len(c) else float('inf'):.2e}")
