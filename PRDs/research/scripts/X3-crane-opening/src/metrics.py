"""Measurements on a torn state, reported on the welded sheet (copies averaged)."""
import numpy as np
from crane import edge_strain, principal_stretch
from contact import crossing_pairs

WING_TIPS = (54, 2)       # material corners (1,0) and (0,1)
NECK_TAIL = (0, 57)       # material corners (0,0) and (1,1)


def welded(V, mat, nmat):
    W = np.zeros((nmat, 3)); c = np.zeros(nmat)
    np.add.at(W, mat, V); np.add.at(c, mat, 1)
    return W / c[:, None]


def body_set(Xclosed):
    """Body = material vertices whose CLOSED-crane position lies in the body
    diamond around the spine: 0.8 <= x <= 1.2 and y >= 0.25 (sheet units).
    A fixed, stated set so every pose is measured on the same vertices."""
    x, y = Xclosed[:, 0], Xclosed[:, 1]
    return np.nonzero((x >= 0.8) & (x <= 1.2) & (y >= 0.25))[0]


def mirror_body_pairs(Xclosed, M, centre=(1.0, 0.4), r=0.1):
    """Body opening probe: pairs of material vertices mirrored across the
    square's diagonal m_x = m_y (the crane's symmetry plane) whose CLOSED
    position lies within r of the body centre. Both members coincide in the
    closed crane; their separation measures how far the two body walls
    have parted. 18 pairs for the default centre and radius."""
    key = {tuple(np.round(m, 6)): i for i, m in enumerate(M)}
    out = []
    for i, m in enumerate(M):
        j = key.get(tuple(np.round(m[::-1], 6)))
        if j is not None and m[0] > m[1] + 1e-9 and np.linalg.norm(Xclosed[i, :2] - np.array(centre)) < r:
            out.append((i, j))
    return np.array(out)


def body_opening(W, pairs):
    s = np.linalg.norm(W[pairs[:, 0]] - W[pairs[:, 1]], axis=1)
    return float(np.median(s)), float(s.max())


def measure(V, sim, d, crossings=True):
    mat = sim.mat
    X, F, M, Ev = d['X'], d['F'], d['M'], d['Ev']
    W = welded(V, mat, len(X))
    st = edge_strain(W, M, Ev)
    ps = principal_stretch(W, M, F)
    gaps = np.linalg.norm(V[sim.W[:, 0]] - V[sim.W[:, 1]], axis=1) if len(sim.W) else np.zeros(1)
    out = dict(
        edge_err_max=float(np.abs(st).max()), edge_err_p95=float(np.percentile(np.abs(st), 95)),
        edge_err_p50=float(np.percentile(np.abs(st), 50)),
        stretch_max=float(ps[:, 0].max() - 1), compress_max=float(1 - ps[:, 1].min()),
        weld_gap_max=float(gaps.max()), weld_gap_p95=float(np.percentile(gaps, 95)),
        weld_gap_p50=float(np.percentile(gaps, 50)),
        body_open_med=body_opening(W, mirror_body_pairs(X, M))[0],
        body_open_max=body_opening(W, mirror_body_pairs(X, M))[1],
        wing_tip_sep=float(np.linalg.norm(W[WING_TIPS[0]] - W[WING_TIPS[1]])),
        min_dist_torn=float(sim.contact.min_distance(V, 5 * sim.p['dhat'])),
    )
    if crossings:
        out['crossing_pairs_welded'] = len(crossing_pairs(W, F))
    return out, W
