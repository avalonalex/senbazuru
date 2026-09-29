"""Experiment P (positive control): a held strip bent into an exact cylinder
whose generators run either across the strip (aligned with mesh edges) or at
45 degrees (along or against the cell diagonals).

The strip is 1 x 0.25 sheet units, square cells of side h, one diagonal per
cell. Both end columns of cells are held on the exact isometric cylinder of
radius R; everything else starts on it too and is relaxed with the study's
energy (B = 0.2 join bending, edge springs w). If the mesh cannot bend about
the generators without stretching, it must either stretch or bend somewhere
else: that is locking, and this control shows what it looks like in the
metrics used on the crane (J bends, silhouette at 600 px, strain).
"""
import json
import sys
import numpy as np

import sheet as S
import relax as R
import sil

L, Wd = 1.0, 0.25


def strip_mesh(n, diag):
    nx, ny = n, n // 4
    xs = np.linspace(0, L, nx + 1)
    ys = np.linspace(0, Wd, ny + 1)
    UV = np.array([(x, y) for y in ys for x in xs])
    idx = lambda i, j: j * (nx + 1) + i
    F = []
    for j in range(ny):
        for i in range(nx):
            a, b, c, d = idx(i, j), idx(i + 1, j), idx(i + 1, j + 1), idx(i, j + 1)
            if diag == "/":
                F += [(a, b, c), (a, c, d)]
            else:
                F += [(a, b, d), (b, c, d)]
    F = np.array(F, int)
    amap = {}
    return UV, F, amap, nx


def cylinder(UV, gen_deg, turn_deg):
    g = np.array([np.cos(np.radians(gen_deg)), np.sin(np.radians(gen_deg))])
    nrm = np.array([-g[1], g[0]])
    c0 = np.array([L / 2, Wd / 2])
    s = (UV - c0) @ nrm
    t = (UV - c0) @ g
    span = s.max() - s.min()
    Rr = span / np.radians(turn_deg)
    X = (t[:, None] * np.append(g, 0) + (Rr * np.sin(s / Rr))[:, None] * np.append(nrm, 0)
         + (Rr * (1 - np.cos(s / Rr)))[:, None] * np.array([0, 0, 1.0]))
    return X, Rr


