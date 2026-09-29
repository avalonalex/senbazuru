"""Shared helpers: read a FOLD file, find coincident layer stacks from faceOrders,
and compute a per-face offset so stacked layers get distinct heights.
Written for this experiment (MIT-compatible, no third-party source)."""
import json, collections
import numpy as np

def load(path):
    d = json.load(open(path))
    V = np.array([list(v) + [0.0] * (3 - len(v)) for v in d['vertices_coords']], float)
    F = [list(f) for f in d['faces_vertices']]
    return d, V, F

def face_normals(V, F):
    N = []; A = []; C = []
    for f in F:
        P = V[f]
        n = np.zeros(3)
        for i in range(len(f)):  # Newell's method, works for any polygon
            n += np.cross(P[i], P[(i + 1) % len(f)])
        a = np.linalg.norm(n) / 2
        N.append(n / (2 * a) if a > 0 else n); A.append(a); C.append(P.mean(0))
    return np.array(N), np.array(A), np.array(C)

def stacks(d, V, F, tol=1e-7):
    """Group faces that lie in one plane and are ordered against each other.
    Returns per-face (height rank, stack direction) and stats."""
    N, A, C = face_normals(V, F)
    orders = d.get('faceOrders', [])
    parent = list(range(len(F)))
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]; x = parent[x]
        return x
    coincident = []
    for f, g, s in orders:
        if abs(abs(N[f] @ N[g]) - 1) < 1e-6 and abs(N[f] @ (C[g] - C[f])) < tol:
            coincident.append((f, g, s))
            parent[find(f)] = find(g)
    clusters = collections.defaultdict(list)
    for f, g, s in coincident:
        clusters[find(f)].append((f, g, s))
    height = np.zeros(len(F), int); direction = np.zeros((len(F), 3))
    cycles = 0
    for root, prs in clusters.items():
        faces = sorted({x for f, g, s in prs for x in (f, g)})
        dvec = N[faces[0]]
        # [f,g,s]: s=+1 means f lies on the side g's normal points to (FOLD spec; Origami.Layers header).
        above = collections.defaultdict(set); indeg = collections.Counter()
        for f, g, s in prs:
            f_up = s * np.sign(N[g] @ dvec) > 0
            lo, hi = (g, f) if f_up else (f, g)
            if hi not in above[lo]:
                above[lo].add(hi); indeg[hi] += 1
        # longest-path layering (Kahn)
        h = {x: 0 for x in faces}
        q = [x for x in faces if indeg[x] == 0]; seen = 0
        while q:
            x = q.pop(); seen += 1
            for y in above[x]:
                h[y] = max(h[y], h[x] + 1); indeg[y] -= 1
                if indeg[y] == 0: q.append(y)
        if seen != len(faces): cycles += 1
        for x in faces:
            height[x] = h[x]; direction[x] = dvec
    return dict(N=N, A=A, C=C, height=height, direction=direction,
                n_orders=len(orders), n_coincident=len(coincident),
                n_clusters=len(clusters), cycles=cycles,
                faces_in_stacks=int(sum(1 for x in direction if np.any(x))),
                max_height=int(height.max()) if len(F) else 0)
