"""Core shape of saved states: head-tail extent (x-range) and depth (z-range)
of the 49 study core vertices, and the fold angles of the 12 crease segments
through the paper's centre. python core_shape.py TORN state.npy [...]"""
import sys, json
import numpy as np
from crane import EXP, X3, load
from metrics2 import CORE
from sim import dihedral_and_grad

torn = sys.argv[1]
d = dict(np.load(f'{EXP}/{torn}.npz'))
H, M, mat = d['hinges'], d['M'], d['mat']
cs = set(CORE.tolist())
if len(M) > 237:   # refined mesh: core = every vertex of a core triangle (midpoints included)
    reg = json.load(open(f'{EXP}/out/regions-refined.json'))
    cs = set(int(v) for t in reg['core_tris'] for v in d['F'][t])
sel = {'midline': [], 'diag': []}
for k, h in enumerate(H):
    if h[6] and h[7] in cs and h[8] in cs:
        ma, mb = M[h[7]], M[h[8]]
        dirn = (mb - ma) / np.linalg.norm(mb - ma); rel = np.array([.5, .5]) - ma
        if abs(rel[0] * dirn[1] - rel[1] * dirn[0]) < 1e-6:
            sel['diag' if abs(abs(dirn[0]) - abs(dirn[1])) < 1e-6 else 'midline'].append(k)


def report(name, W, V=None):
    xr, zr = np.ptp(W[CORE, 0]), np.ptp(W[CORE, 2])
    out = f'{name:28s} core x-range {xr:.3f} z-range {zr:.3f}'
    if V is not None:
        th, _ = dihedral_and_grad(V[H[:, 0]], V[H[:, 1]], V[H[:, 2]], V[H[:, 3]])
    else:
        th, _ = dihedral_and_grad(W[mat[H[:, 0]]], W[mat[H[:, 1]]], W[mat[H[:, 2]]], W[mat[H[:, 3]]])
    for k, ids in sel.items():
        a = np.degrees(np.abs(th[ids]))
        out += f'  {k} fold {np.median(a):5.1f} (min {a.min():5.1f})'
    print(out)


for n in (['before', 'after', 'spread-0', 'pillow'] if len(M) == 237 else []):
    report('study ' + n, load(n)['X'])
for f in sys.argv[2:]:
    V = np.load(f)
    W = np.zeros((len(M), 3)); c = np.zeros(len(M)); np.add.at(W, mat, V); np.add.at(c, mat, 1); W /= c[:, None]
    report(f.split('/')[-1].replace('.npy', ''), W, V)
