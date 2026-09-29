"""Y4 measurements: X3's set plus the study's body depth, the core volume
and a crossing count on the torn mesh (the guarantee IPC gives)."""
import json
import numpy as np
import ipctk
from crane import edge_strain, principal_stretch, GAL
from contact import crossing_pairs
from metrics import mirror_body_pairs, body_opening, WING_TIPS

CORE = np.array(sorted(set(p[0] for p in json.load(open(f'{GAL}/checks.json'))['pins']) - {2, 54}))


def torn_crossings(V, T, mat):
    """Pairs of torn triangles that share no MATERIAL vertex and intersect
    (an edge of one passes through the other)."""
    P = V[T]
    lo, hi = P.min(1), P.max(1)
    ov = np.all((lo[:, None, :] <= hi[None, :, :]) & (lo[None, :, :] <= hi[:, None, :]), axis=2)
    iu, ju = np.nonzero(np.triu(ov, 1))
    Tm = mat[T]
    share = (Tm[iu][:, :, None] == Tm[ju][:, None, :]).any((1, 2))
    iu, ju = iu[~share], ju[~share]
    out = []
    for i, j in zip(iu, ju):
        for (a, b) in ((0, 1), (1, 2), (2, 0)):
            if ipctk.is_edge_intersecting_triangle(P[i, a], P[i, b], P[j, 0], P[j, 1], P[j, 2]) or \
               ipctk.is_edge_intersecting_triangle(P[j, a], P[j, b], P[i, 0], P[i, 1], P[i, 2]):
                out.append((int(i), int(j)))
                break
    return out


def welded_measures(W, d, pairs=None):
    X, F, M, Ev = d['X'], d['F'], d['M'], d['Ev']
    if pairs is None:
        pairs = mirror_body_pairs(X, M)
        pairs = pairs[(pairs < 237).all(1)]     # the original mesh's 18 pairs, also on a refined mesh
    st = edge_strain(W, M, Ev)
    ps = principal_stretch(W, M, F)
    bo = body_opening(W, pairs)
    return dict(edge_err_max=float(np.abs(st).max()), edge_err_p95=float(np.percentile(np.abs(st), 95)),
                stretch_max=float(ps[:, 0].max() - 1), compress_max=float(1 - ps[:, 1].min()),
                stretch_p95=float(np.percentile(ps[:, 0], 95) - 1),
                body_open_med=bo[0], body_open_max=bo[1],
                body_depth=float(np.ptp(W[CORE, 2])),
                wing_tip_sep=float(np.linalg.norm(W[WING_TIPS[0]] - W[WING_TIPS[1]])))


def measure(V, sim, d, welded_crossings=False):
    W = sim.A @ V
    out = welded_measures(W, d)
    ps = principal_stretch(W, d['M'], d['F'])
    noncore = np.setdiff1d(np.arange(len(d['F'])), sim.core_tris)
    out['stretch_max_noncore'] = float(ps[noncore, 0].max() - 1)
    out['compress_max_noncore'] = float(1 - ps[noncore, 1].min())
    out['stretch_max_core'] = float(ps[sim.core_tris, 0].max() - 1)
    out['compress_max_core'] = float(1 - ps[sim.core_tris, 1].min())
    gaps = np.linalg.norm(V[sim.W[:, 0]] - V[sim.W[:, 1]], axis=1)
    out.update(weld_gap_max=float(gaps.max()), weld_gap_p95=float(np.percentile(gaps, 95)),
               weld_gap_p50=float(np.percentile(gaps, 50)),
               core_volume=float(sim.core_volume(W, False)[0]),
               min_dist_torn=float(sim.contact.min_distance(V, 5e-3)),
               crossings_torn=len(torn_crossings(V, sim.T, sim.mat)))
    if welded_crossings:
        out['crossings_welded'] = len(crossing_pairs(W, d['F']))
    return out, W
