"""Weld X3's torn IPC states back onto the 237-vertex sheet (average the copies of
each material vertex) so they can start a projection, and measure them against spread-0."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np, mesh
X3 = os.path.join(os.path.dirname(__file__), '../../X3-crane-opening/')
t = np.load(X3 + 'torn.npz')
s = mesh.load_fold(os.path.join(os.path.dirname(__file__), '../../../gallery/whole-crane/spread-0.fold'))
for name in ['open-root-step10', 'open-tip-step10', 'conv-root10-step10']:
    V = np.load(X3 + name + '.npy')
    W = np.zeros((237, 3)); c = np.zeros(237)
    np.add.at(W, t['mat'], V); np.add.at(c, t['mat'], 1); W /= c[:, None]
    np.save(os.path.join(os.path.dirname(__file__), f'../out/x3-{name}-welded.npy'), W)
    r = mesh.measure(s, W, s['X'])
    print(name, {k: round(r[k], 3) for k in ('max_principal_strain', 'sil_mean_px', 'sil_hausdorff_px', 'proj_vertex_max_px')})
