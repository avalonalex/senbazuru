# Count crossing triangle pairs (no shared vertex) by edge-triangle intersection.
import sys, numpy as np
def seg_tri(p, q, a, b, c, eps=1e-12):
    d = q - p; e1 = b - a; e2 = c - a
    h = np.cross(d, e2); det = e1 @ h
    if abs(det) < eps: return False
    f = 1.0 / det; s = p - a; u = f * (s @ h)
    if u < 0 or u > 1: return False
    qq = np.cross(s, e1); v = f * (d @ qq)
    if v < 0 or u + v > 1: return False
    t = f * (e2 @ qq)
    return 0 < t < 1
def count(X, T):
    lo = X[T].min(1); hi = X[T].max(1); m = len(T); n = 0
    for i in range(m):
        ov = np.all(lo[i] <= hi, axis=1) & np.all(hi[i] >= lo, axis=1)
        for j in np.nonzero(ov)[0]:
            if j <= i or set(T[i]) & set(T[j]): continue
            A, B = X[T[i]], X[T[j]]
            hit = any(seg_tri(A[k], A[(k+1)%3], *B) for k in range(3)) or any(seg_tri(B[k], B[(k+1)%3], *A) for k in range(3))
            n += hit
    return n
if __name__ == "__main__":
  for name, xf, tf in [("pillow tfield 16", "X_square_16_tfield.npy", "T_square_16_tfield.npy"),
                     ("pillow sym 12", "X_square_12_sym.npy", "T_square_12_sym.npy"),
                     ("pillow edge1 12", "X_square_12_edge1.npy", "T_square_12_edge1.npy"),
                     ("disc tfield 12", "X_disc_12_tfield.npy", "T_disc_12_tfield.npy"),
                     ("cube tfield 10", "X_cube_10.npy", "T_cube_10.npy")]:
      print(name, "crossing pairs:", count(np.load(xf), np.load(tf)), flush=True)
