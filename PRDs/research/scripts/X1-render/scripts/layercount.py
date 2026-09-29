"""Largest number of faces covering one point of a flat-folded FOLD, versus the
longest-path stack height used for rendering."""
import sys, numpy as np
sys.path.insert(0, sys.argv[1]); import foldlayers as fl
for path in sys.argv[2:]:
    d, V, F = fl.load(path)
    st = fl.stacks(d, V, F)
    xs = np.linspace(V[:, 0].min(), V[:, 0].max(), 400); ys = np.linspace(V[:, 1].min(), V[:, 1].max(), 400)
    X, Y = np.meshgrid(xs, ys); P = np.stack([X.ravel(), Y.ravel()], 1)
    count = np.zeros(len(P), int)
    for f in F:
        poly = V[f][:, :2]
        inside = np.zeros(len(P), bool)
        j = len(poly) - 1
        for i in range(len(poly)):   # even-odd ray test
            xi, yi = poly[i]; xj, yj = poly[j]
            cond = ((yi > P[:, 1]) != (yj > P[:, 1])) & (P[:, 0] < (xj - xi) * (P[:, 1] - yi) / (yj - yi + 1e-300) + xi)
            inside ^= cond; j = i
        count += inside
    print(path.split('/')[-1], 'max faces over one point', count.max(), 'longest-path levels', st['max_height'] + 1)
