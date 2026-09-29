"""Volume at every printed time of a CalculiX tea-bag run (own code). usage: python history.py NAME"""
import re, sys, numpy as np
name = sys.argv[1]
m = np.load(f"runs/{name}.mesh.npz"); X0, tri = m["X"], m["tri"]
txt = open(f"runs/{name}.dat").read()
for blk in re.split(r"\n\s*displacements \(vx,vy,vz\) for set NALL and time\s+", txt)[1:]:
    head, body = blk.split("\n", 1)
    U = np.zeros_like(X0)
    for line in body.splitlines():
        p = line.split()
        if len(p) != 4:
            if p: break
            continue
        U[int(p[0]) - 1] = [float(v) for v in p[1:]]
    x = X0 + U; a, b, c = x[tri[:, 0]], x[tri[:, 1]], x[tri[:, 2]]
    A = 0.5 * ((b[:, 0]-a[:, 0])*(c[:, 1]-a[:, 1]) - (c[:, 0]-a[:, 0])*(b[:, 1]-a[:, 1]))
    print(f"t={float(head.split()[0]):.4f} V={2*np.sum(A*(a[:,2]+b[:,2]+c[:,2])/3):.5f} zmax={x[:,2].max():.4f}")
