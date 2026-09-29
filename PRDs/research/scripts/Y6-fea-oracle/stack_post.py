"""Layer spacing in a stack_test result (own code). usage: python stack_post.py NAME"""
import re, sys, numpy as np
name = sys.argv[1]
d = np.load(f"runs/{name}.stack.npz"); pts, tag, ns, ny, t = d["pts"], d["tag"], int(d["ns"]), int(d["ny"]), float(d["t"])
txt = open(f"runs/{name}.dat").read()
blk = re.split(r"displacements \(vx,vy,vz\) for set NALL and time\s+", txt)[-1]
U = {}
for line in blk.split("\n", 1)[1].splitlines():
    p = line.split()
    if len(p) != 4:
        if p: break
        continue
    U[int(p[0])] = np.array([float(v) for v in p[1:]])
out = []
for j in range(ny + 1):
    X = np.array([[pts[s, 0], j * 0.2 / ny, pts[s, 1]] + U[j * ns + s + 1] for s in range(ns)])
    lay = [X[tag == k] for k in range(3)]
    # layers share x stations; sort each by x and compare heights
    z = [l[np.argsort(l[:, 0])] for l in lay]
    d10 = z[1][:, 2] - z[0][:, 2]; d21 = z[2][:, 2] - z[1][:, 2]
    out.append((d10.min(), d21.min(), z[2][:, 2].min(), np.abs(z[1][:, 0] - z[0][:, 0]).max()))
o = np.array(out)
print(f"{name}: smallest midplane spacing L1-L0 {o[:,0].min()/t:.3f} t, L2-L1 {o[:,1].min()/t:.3f} t; "
      f"lowest point of top layer {o[:,2].min()/t:.3f} t; largest x drift between stacked nodes {o[:,3].max():.4f}")
