"""Shared loading and geometry helpers for the X3 crane-opening experiment.

Written for this experiment (MIT-compatible, own code). Reads the study's
whole-crane FOLD files, which carry `senbazuru:material_coords` (position of
each vertex on the unit square) alongside the folded 3D positions.
"""
import json
import collections
import numpy as np

SCR = '/private/tmp/claude-501/-Users-yuhanhao-Project-senbazuru/a9814e9f-3bd8-46c3-897f-77c8e8d977fa/scratchpad'
GAL = SCR + '/gallery/whole-crane'
EXP = SCR + '/experiments/Y4-crane-v2'
X3 = SCR + '/experiments/X3-crane-opening'


def load(name):
    d = json.load(open(f'{GAL}/{name}.fold'))
    X = np.array(d['vertices_coords'], float)
    if X.shape[1] == 2:
        X = np.c_[X, np.zeros(len(X))]
    F = np.array(d['faces_vertices'], int)
    M = np.array(d['senbazuru:material_coords'], float)
    Ev = np.array(d['edges_vertices'], int)
    A = list(d['edges_assignment'])
    fo = np.array(d.get('faceOrders', []), int).reshape(-1, 3)
    return dict(X=X, F=F, M=M, E=Ev, A=A, fo=fo, raw=d)


def edge_faces(F, nv):
    """Map sorted vertex pair -> list of (face, local index)."""
    ef = collections.defaultdict(list)
    for fi, (a, b, c) in enumerate(F):
        for (u, v) in ((a, b), (b, c), (c, a)):
            ef[(min(u, v), max(u, v))].append(fi)
    return ef


def normals(X, F):
    n = np.cross(X[F[:, 1]] - X[F[:, 0]], X[F[:, 2]] - X[F[:, 0]])
    return n / np.linalg.norm(n, axis=1)[:, None]


def signed_dihedral(X, F, fi, fj, a, b):
    """Signed fold angle across edge (a,b) shared by faces fi, fj.

    0 = flat, +-pi = folded flat. Sign: + if the fold turns fj towards
    fi's normal side (a valley seen from fi's front)."""
    n1 = np.cross(X[F[fi, 1]] - X[F[fi, 0]], X[F[fi, 2]] - X[F[fi, 0]])
    n2 = np.cross(X[F[fj, 1]] - X[F[fj, 0]], X[F[fj, 2]] - X[F[fj, 0]])
    e = X[b] - X[a]
    e = e / np.linalg.norm(e)
    n1 /= np.linalg.norm(n1)
    n2 /= np.linalg.norm(n2)
    return np.arctan2(np.dot(np.cross(n1, n2), e), np.dot(n1, n2))


def edge_strain(X, M, Ev):
    """Relative change of each edge's length against its material length."""
    L = np.linalg.norm(X[Ev[:, 0]] - X[Ev[:, 1]], axis=1)
    L0 = np.linalg.norm(M[Ev[:, 0]] - M[Ev[:, 1]], axis=1)
    return L / L0 - 1.0


def principal_stretch(X, M, F):
    """Max / min principal stretch per triangle (deformation gradient SVD)."""
    out = np.zeros((len(F), 2))
    for i, (a, b, c) in enumerate(F):
        Dm = np.c_[M[b] - M[a], M[c] - M[a]]            # 2x2
        Ds = np.c_[X[b] - X[a], X[c] - X[a]]            # 3x2
        Fg = Ds @ np.linalg.inv(Dm)
        s = np.linalg.svd(Fg, compute_uv=False)
        out[i] = (s[0], s[1])
    return out


def write_obj(path, X, F, M=None):
    with open(path, 'w') as fh:
        for p in X:
            fh.write(f'v {p[0]:.9f} {p[1]:.9f} {p[2]:.9f}\n')
        if M is not None:
            for m in M:
                fh.write(f'vt {m[0]:.9f} {m[1]:.9f}\n')
        for a, b, c in F:
            if M is not None:
                fh.write(f'f {a+1}/{a+1} {b+1}/{b+1} {c+1}/{c+1}\n')
            else:
                fh.write(f'f {a+1} {b+1} {c+1}\n')


def write_fold(path, X, F, M, Ev, A, title, extra=None):
    d = {
        'file_spec': 1.2,
        'file_creator': 'senbazuru X3 crane-opening experiment (scratch)',
        'file_title': title,
        'frame_classes': ['foldedForm'],
        'frame_attributes': ['3D'],
        'vertices_coords': X.tolist(),
        'edges_vertices': Ev.tolist(),
        'edges_assignment': A,
        'faces_vertices': F.tolist(),
        'senbazuru:material_coords': M.tolist(),
    }
    if extra:
        d.update(extra)
    json.dump(d, open(path, 'w'))
