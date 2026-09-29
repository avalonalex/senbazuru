"""Re-implementation of the study's pillow construction (WholeCrane.pillowCraneWith)
from its description in the MIT source, so it can be rerun on other meshes.

  anchors  = core vertices on the cushion formula, wing vertices (single wing
             membership, folded y <= 0.25) on the arch formula;
  the rest = before position + displacement continued by a weighted graph
             Laplacian, weight 1/rest length per edge, normal equations with a
             1e-12 diagonal (SparseSolve.factorNormal 1e-12).
No energy, no lengths, no relaxation.
"""
import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spla

import anchors as A
from sheet import mesh_edges, edge_rest


def panel_regions(F, panels, core, wa, wb):
    """Infer each source panel's region from the anchors of the original mesh."""
    reg = {}
    for p in np.unique(panels):
        vs = np.unique(F[panels == p])
        if core[vs].all():
            reg[p] = "core"
        elif wa[vs].any():
            reg[p] = "wingA"
        elif wb[vs].any():
            reg[p] = "wingB"
        else:
            reg[p] = f"other{p}"
    return reg


def memberships(F, panels, reg, n):
    mem = [set() for _ in range(n)]
    for tri, p in zip(F, panels):
        for v in tri:
            mem[v].add(reg[p])
    return mem


def anchor_targets(UV, Xbefore, mem, amount=0.0):
    n = len(UV)
    target = np.full((n, 3), np.nan)
    kind = np.array([""] * n, dtype=object)
    cush = A.cushion(UV)
    archA = A.arch(Xbefore[:, :2], -1, amount)
    archB = A.arch(Xbefore[:, :2], 1, amount)
    for i in range(n):
        if "core" in mem[i]:
            target[i] = cush[i]; kind[i] = "core"
        elif len(mem[i]) == 1 and Xbefore[i, 1] <= 0.25 + 1e-9:
            r = next(iter(mem[i]))
            if r == "wingA":
                target[i] = archA[i]; kind[i] = "wingA"
            elif r == "wingB":
                target[i] = archB[i]; kind[i] = "wingB"
    return target, kind


def continue_displacements(UV, F, baseline, target):
    anchored = ~np.isnan(target[:, 0])
    free = np.flatnonzero(~anchored)
    col = -np.ones(len(UV), int)
    col[free] = np.arange(len(free))
    Ed = mesh_edges(F)
    w = 1.0 / edge_rest(UV, Ed)
    resid = np.where(anchored[:, None], target - baseline, 0.0)
    rows, cols, vals = [], [], []
    rhs = np.zeros((len(free), 3))
    for e, (a, b) in enumerate(Ed):
        for x, y in ((a, b), (b, a)):
            if col[x] >= 0:
                if col[y] >= 0:
                    rows.append(col[x]); cols.append(col[y]); vals.append(-w[e] ** 2)
                else:
                    rhs[col[x]] += w[e] ** 2 * resid[y]
                rows.append(col[x]); cols.append(col[x]); vals.append(w[e] ** 2)
    N = sp.csc_matrix((vals, (rows, cols)), shape=(len(free), len(free))) + 1e-12 * sp.eye(len(free))
    d = np.column_stack([spla.spsolve(N, rhs[:, k]) for k in range(3)])
    X = baseline.copy()
    X[free] += d
    X[anchored] = target[anchored]
    return X
