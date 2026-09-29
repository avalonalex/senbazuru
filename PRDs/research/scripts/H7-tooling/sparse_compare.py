"""Factor the study-shaped normal matrix J^T J + 1e-3 I with several sparse
direct solvers and report wall time (median of 3). The matrix is rebuilt here
with the same deterministic construction as hsbench/app/SparseBench.hs and,
where the Haskell run wrote triplets, checked equal to them."""
import sys, time, os
import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as sla

def lcg(seed):
    x = seed
    while True:
        x = (1103515245 * x + 12345) % 2147483648
        yield x / 2147483648 - 0.5

def build(n):
    vid = lambda i, j: i * n + j
    tris = []
    for i in range(n - 1):
        for j in range(n - 1):
            tris.append((vid(i, j), vid(i + 1, j), vid(i + 1, j + 1)))
            tris.append((vid(i, j), vid(i + 1, j + 1), vid(i, j + 1)))
    opp = {}
    for a, b, c in tris:
        for (u, v), w in (((a, b), c), ((b, c), a), ((c, a), b)):
            k = (min(u, v), max(u, v))
            opp[k] = [w] + opp.get(k, [])  # Haskell fromListWith (++) prepends later values
    edges = sorted(opp.items())
    g = lcg(42)
    rs = [next(g) for _ in range(100000 + len(edges))]
    rows = []
    for (e, _), r in zip(edges, rs):
        a, b = e
        row = {}
        for k in range(3):
            row[3 * a + k] = row.get(3 * a + k, 0) + 1e4 * (r + k * 0.3)
            row[3 * b + k] = row.get(3 * b + k, 0) - 1e4 * (r + k * 0.3)
        rows.append(row)
    for (e, o), r in zip(edges, rs[100000:]):
        if len(o) != 2:
            continue
        a, b = e
        c, d = o
        row = {}
        for w, v in enumerate([a, b, c, d], start=1):
            for k in range(3):
                row[3 * v + k] = row.get(3 * v + k, 0) + r * (k + 1) + w
        rows.append(row)
    N = 3 * n * n
    I, J, V = [], [], []
    for ri, row in enumerate(rows):
        for c, v in row.items():
            I.append(ri); J.append(c); V.append(v)
    Jm = sp.csr_matrix((V, (I, J)), shape=(len(rows), N))
    A = (Jm.T @ Jm + 1e-3 * sp.identity(N)).tocsc()
    return A

def median_time(f, reps=3):
    ts = []
    for _ in range(reps):
        t0 = time.perf_counter(); f(); ts.append(time.perf_counter() - t0)
    return sorted(ts)[len(ts) // 2]

try:
    from sksparse.cholmod import cho_factor, cho_solve as cholesky_solve
    cholesky = cho_factor
except Exception:
    cholesky = None

for n in [int(a) for a in sys.argv[1:]]:
    A = build(n)
    trip = f"hsbench/mats/grid{n}.txt"
    note = ""
    if os.path.exists(trip):
        with open(trip) as fh:
            N = int(fh.readline())
            data = np.loadtxt(fh)
        U = sp.csc_matrix((data[:, 2], (data[:, 0].astype(int), data[:, 1].astype(int))), shape=(N, N))
        H = (U + sp.triu(U, 1).T).tocsc()
        rel = abs(H - A).max() / abs(A).max()
        note = f" haskell-matrix-rel-diff={rel:.1e}"
    b = np.ones(A.shape[0])
    res = {}
    res["superlu"] = median_time(lambda: sla.splu(A).solve(b))
    if cholesky is not None:
        Aa = sp.csc_array(A)
        res["cholmod-default"] = median_time(lambda: cho_factor(Aa).solve(b))
        res["cholmod-amd"] = median_time(lambda: cho_factor(Aa, order="amd").solve(b))
        fac = cho_factor(Aa); note += f" supernodal={fac.is_super} factor-nnz={fac.nnz}"
    x = sla.splu(A).solve(b)
    resid = np.linalg.norm(A @ x - b) / np.linalg.norm(b)
    print(f"n={n} scalars={A.shape[0]} nnz={A.nnz}{note} residual={resid:.1e} " + " ".join(f"{k}={v*1e3:.1f}ms" for k, v in res.items()))
