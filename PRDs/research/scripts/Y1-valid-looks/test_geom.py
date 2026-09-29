"""Cross-check geom.py's narrow phase against ipctk on random triangle pairs."""
import numpy as np, ipctk, time
from geom import pair_metrics
rng = np.random.default_rng(1)
n = 3000
V = rng.normal(size=(6 * n, 3)) * np.repeat(rng.uniform(0.05, 1, n), 6)[:, None] + np.repeat(rng.normal(size=(n, 3)) * 0.3, 6, axis=0)
F = np.arange(6 * n).reshape(-1, 3)
pairs = np.stack([np.arange(0, 2 * n, 2), np.arange(1, 2 * n, 2)], 1)
# add near-coplanar and exactly coplanar cases
t0 = time.perf_counter(); cr, d = pair_metrics(V[F], pairs); t1 = time.perf_counter()
bad_d = bad_c = 0
for k, (i, j) in enumerate(pairs):
    A = V[F[i]]; B = V[F[j]]
    ic = any(ipctk.is_edge_intersecting_triangle(A[a], A[(a+1)%3], B[0], B[1], B[2]) for a in range(3)) or \
         any(ipctk.is_edge_intersecting_triangle(B[a], B[(a+1)%3], A[0], A[1], A[2]) for a in range(3))
    if ic != cr[k]: bad_c += 1
    if not ic:
        dd = min([ipctk.point_triangle_distance(A[a], B[0], B[1], B[2]) for a in range(3)] +
                 [ipctk.point_triangle_distance(B[a], A[0], A[1], A[2]) for a in range(3)] +
                 [ipctk.edge_edge_distance(A[a], A[(a+1)%3], B[b], B[(b+1)%3]) for a in range(3) for b in range(3)])
        if abs(np.sqrt(dd) - d[k]) > 1e-9 * max(1, np.sqrt(dd)): bad_d += 1
print(f"pairs {n}, crossing {cr.sum()}, crossing disagreements {bad_c}, distance disagreements {bad_d}, own time {t1-t0:.3f}s")
