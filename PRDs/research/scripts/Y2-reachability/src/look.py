import sys; sys.path.insert(0, 'src')
import numpy as np, mesh, matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection
m = mesh.load_fold('../../gallery/whole-crane/spread-0.fold')
X = m['X']; F = m['F']
fig, axs = plt.subplots(1, 3, figsize=(24, 8))
views = [('upright', mesh.upright_basis()), ('side', None), ('head', None)]
def basis_from(f, up):
    f = np.array(f, float); f /= np.linalg.norm(f); r = np.cross(f, up); r /= np.linalg.norm(r); return r, np.cross(r, f), f
bs = [mesh.upright_basis(), basis_from([0, 0, -1], [0, -1, 0]), basis_from([1, 0.25, 0.15], [0, -1, 0])]
col = {'M': 'r', 'V': 'b', 'F': 'g', 'U': 'm', 'B': 'k', 'J': '0.8'}
for ax, (name, _), b in zip(axs, views, bs):
    P, depth = mesh.project(X, b)
    order = np.argsort(-depth[F].mean(1))
    ax.add_collection(PolyCollection(P[F[order]], facecolors='#eee6cf', edgecolors='none', alpha=0.6))
    for (i, j), s in zip(m['edges'], m['eassign']):
        if s != 'J':
            ax.plot(P[[i, j], 0], P[[i, j], 1], col[s], lw=0.6)
    for v in range(len(X)):
        ax.text(P[v, 0], P[v, 1], str(v), fontsize=5)
    ax.set_aspect('equal'); ax.autoscale(); ax.set_title(name)
plt.tight_layout(); plt.savefig('img/diag-labels.png', dpi=110)
# material view
fig, ax = plt.subplots(figsize=(10, 10))
U = m['U']
for (i, j), s in zip(m['edges'], m['eassign']):
    ax.plot(U[[i, j], 0], U[[i, j], 1], col[s], lw=0.6 if s != 'J' else 0.3)
for v in range(len(U)):
    ax.text(U[v, 0], U[v, 1], str(v), fontsize=5)
ax.set_aspect('equal'); plt.savefig('img/diag-cp.png', dpi=110)
