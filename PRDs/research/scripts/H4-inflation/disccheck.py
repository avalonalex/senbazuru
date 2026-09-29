import numpy as np
from crossings import seg_tri
from pillow import disc_sheet, pillow
P2, T0, B = disc_sheet(12)
X0, tris, rest2, n, interior, bottom_id = pillow(P2, T0, B)
X = np.load("X_disc_12_tfield.npy"); T = np.load("T_disc_12_tfield.npy")
rc = np.linalg.norm(rest2.mean(1), axis=1)   # rest radius of each triangle's centroid
lo = X[T].min(1); hi = X[T].max(1); rs = []
for i in range(len(T)):
    ov = np.all(lo[i] <= hi, axis=1) & np.all(hi[i] >= lo, axis=1)
    for j in np.nonzero(ov)[0]:
        if j <= i or set(T[i]) & set(T[j]): continue
        A, Bt = X[T[i]], X[T[j]]
        if any(seg_tri(A[k], A[(k+1)%3], *Bt) for k in range(3)) or any(seg_tri(Bt[k], Bt[(k+1)%3], *A) for k in range(3)):
            rs += [rc[i], rc[j]]
print("crossing triangles' rest radius: min", round(min(rs),3), "max", round(max(rs),3), "count", len(rs)//2)
