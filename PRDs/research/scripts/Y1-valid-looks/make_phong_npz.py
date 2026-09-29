"""Phong-tessellated S1 display meshes for rendering (own code)."""
import sys
import numpy as np
import geom, layers
T = 1 / 1500
name, path = sys.argv[1], sys.argv[2]
kinds = tuple(sys.argv[3]) if len(sys.argv) > 3 else ("M", "V", "F", "B")
alpha = float(sys.argv[4]) if len(sys.argv) > 4 else 0.75
tag = '' if alpha == 0.75 else f'-a{alpha:g}'
for bridges, suffix in ((True, ''), (False, '-nobridge')):
    V, F, sharp, info = layers.s1_mesh(path, 1.1 * T, bridges=bridges, kinds=kinds)
    CN, kept = geom.corner_normals(V, F, sharp)
    C, Ft, parent, crack = geom.phong_tessellate(V, F, CN, 4, alpha)
    nv = Ft.max() + 1
    Vw = np.zeros((nv, 3))
    Vw[Ft.ravel()] = C.reshape(-1, 3)      # last writer wins where faces disagree (crack)
    np.savez(f'meshes/{name}-s1-phong{tag}{suffix}.npz', V=Vw, F=Ft)
    print(name, suffix or 'bridges', 'tris', len(Ft), 'crack', crack, 'kept-flat corners', kept)
