"""Inflate a closed unit cube of inextensible, compressible (tension-field)
sheet: the 'Mylar cube' and the nearest cheap stand-in for a waterbomb.
Research script for the H4 note; not repository code."""
import sys, json
import numpy as np
from pillow import prep, energy_grad, lbfgs

def cube_mesh(n):
    faces = [  # origin, u axis, v axis ; u x v points outward
        ((0,0,0),(0,1,0),(1,0,0)), ((0,0,1),(1,0,0),(0,1,0)),
        ((0,0,0),(1,0,0),(0,0,1)), ((0,1,0),(0,0,1),(1,0,0)),
        ((0,0,0),(0,0,1),(0,1,0)), ((1,0,0),(0,1,0),(0,0,1))]
    key = {}; X = []; tris = []; rest = []
    def vid(p):
        k = tuple(np.round(p, 9))
        if k not in key:
            key[k] = len(X); X.append(p)
        return key[k]
    s = np.linspace(0, 1, n + 1)
    for o, u, v in faces:
        o, u, v = map(np.array, (o, u, v))
        ids = {}; uv = {}
        for j in range(n + 1):
            for i in range(n + 1):
                ids[(i, j)] = vid(o + s[i] * u + s[j] * v); uv[(i, j)] = (s[i], s[j])
        for j in range(n):
            for i in range(n):
                a, b, c, d = (i, j), (i+1, j), (i+1, j+1), (i, j+1)
                tl = [(a, b, c), (a, c, d)] if (i + j) % 2 == 0 else [(a, b, d), (b, c, d)]
                for t in tl:
                    tris.append([ids[q] for q in t]); rest.append([uv[q] for q in t])
    return np.array(X, float), np.array(tris), np.array(rest, float)

def run(n, p=1.0, ks=(1e2, 1e3, 1e4)):
    X, tris, rest2 = cube_mesh(n)
    c = X.mean(0)
    X = c + (X - c) * 1.0
    X += 0.001 * (X - c)  # nudge outward
    Dinv, area = prep(tris, rest2)
    x = X.ravel()
    for k in ks:
        fun = lambda z: (lambda E, G, v, lam: (E, G.ravel()))(*energy_grad(z.reshape(-1, 3), tris, Dinv, area, k, p, "tfield"))
        x, f, it, st = lbfgs(fun, x, iters=4000)
    Xf = x.reshape(-1, 3)
    E, G, vol, lam = energy_grad(Xf, tris, Dinv, area, ks[-1], p, "tfield")
    cc = Xf.mean(0)
    face_centre = Xf[np.argmin(np.linalg.norm(X - np.array([0.5, 0.5, 1.0]), axis=1))]
    corner = Xf[np.argmin(np.linalg.norm(X - np.array([1.0, 1.0, 1.0]), axis=1))]
    edge_mid = Xf[np.argmin(np.linalg.norm(X - np.array([0.5, 1.0, 1.0]), axis=1))]
    r = lambda q: float(np.linalg.norm(q - cc))
    np.save(f"X_cube_{n}.npy", Xf); np.save(f"T_cube_{n}.npy", tris)
    return dict(n=n, volume=float(vol), face_centre_radius=r(face_centre), edge_mid_radius=r(edge_mid),
                corner_radius=r(corner), flat_face_centre=0.5, flat_edge_mid=float(np.sqrt(0.5)), flat_corner=float(np.sqrt(0.75)),
                max_stretch=float(lam.max()), min_stretch=float(lam.min()), status=st)

if __name__ == "__main__":
    print(json.dumps(run(int(sys.argv[1]))))
