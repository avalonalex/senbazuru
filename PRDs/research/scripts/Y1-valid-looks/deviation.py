"""Shape change caused by smoothing, as opposed to vertices sliding within
their own panel: distance from each smoothed sub-triangle corner to the
source panel (the union of the source triangles carrying the parent's
senbazuru:source_panels id). Usage: python deviation.py NAME FOLD"""
import sys
import numpy as np
import geom
T = 1 / 1500
name, path = sys.argv[1], sys.argv[2]
f = geom.load_fold(path); V, F, panels = f["V"], f["F"], f["panels"]
for m in ("cc", "phong"):
    z = np.load(f"out/{name}-{m}.npz")
    Ps, parent = z["Ps"], z["parent"]
    pts = Ps.reshape(-1, 3)
    ppanel = np.repeat(panels[parent], 3)
    dev = np.full(len(pts), np.inf)
    for p in np.unique(ppanel):
        sel = np.nonzero(ppanel == p)[0]
        tris = V[F[panels == p]]
        for t in tris:
            d2 = geom._pt_tri(pts[sel], t[0][None], t[1][None], t[2][None])
            dev[sel] = np.minimum(dev[sel], np.sqrt(d2))
    print(f"{name} {m}: off-panel deviation max {dev.max()/T:.2f} t, p99 {np.percentile(dev,99)/T:.2f} t, "
          f"corners off panel by >t: {(dev>T).mean()*100:.2f}%  (>0.1t: {(dev>0.1*T).mean()*100:.2f}%)")
