"""Rebuild the study's --crane-spreading wing problem from its own outputs.

From CraneSpread.hs: the body and a root strip (first 1/8 of the wing span)
are held, a grip strip (last 1/8) is held on an arc turned a further 20
degrees, and the rest starts on that arc (bentPoint) and is relaxed.
The rigid control is the same wing turned 30 degrees about the root, so its
z gives each wing vertex's span position: len = -z / sin 30.
Crease rest angles are read from the accepted rigid endpoint (acceptance
requires every crease within 1e-5 rad of its rest).
"""
import numpy as np
import sheet as S

ROOT = np.radians(30)


def bent_point(x, y, degrees):
    ln = 0.25 - y
    start, stop = 0.25 * 0.125, 0.25 * 0.875
    turn = np.radians(degrees)
    arc = stop - start
    middle = np.clip(ln - start, 0, arc)
    before = np.minimum(start, ln)
    after = np.maximum(0, ln - stop)
    if degrees == 0:
        dy = middle * np.cos(ROOT); dz = middle * np.sin(ROOT)
    else:
        c = turn / arc
        dy = (np.sin(ROOT + c * middle) - np.sin(ROOT)) / c
        dz = (np.cos(ROOT) - np.cos(ROOT + c * middle)) / c
    return np.stack([x, 0.25 - before * np.cos(ROOT) - dy - after * np.cos(ROOT + turn),
                     -(before * np.sin(ROOT)) - dz - after * np.sin(ROOT + turn)], axis=-1)


def load_problem(rigid_path, degrees=20):
    r = S.load_fold(rigid_path)
    amap = S.assignment_map(r)
    X = r["X"]
    wing = X[:, 2] < -1e-12
    ln = np.where(wing, -X[:, 2] / np.sin(ROOT), 0.0)
    frac = ln / 0.25
    start = X.copy()
    start[wing, 1] = 0.25 - ln[wing]
    start[wing, 2] = 0.0
    # body = everything at z=0 in the rigid control (includes the root line)
    held = (~wing) | (frac <= 0.125 + 1e-8) | (frac >= 0.875 - 1e-8)
    grip = wing & (frac >= 0.875 - 1e-8)
    moved = X.copy()
    moved[wing] = bent_point(start[wing, 0], start[wing, 1], degrees)
    # F edges: treat like the whole crane (panel bends), checked below
    H, rest, k, kind = S.build_hinges(r["F"], r["UV"], amap)
    ang_rigid = S.hinge_angles(X, H)
    crease = np.isin(kind, ["M", "V", "U"])
    rest = rest.copy()
    rest[crease] = ang_rigid[crease]
    return dict(fold=r, amap=amap, start=start, X0=moved, held=held, grip=grip, wing=wing,
                frac=frac, H=H, rest=rest, k=k, kind=kind, ang_rigid=ang_rigid)
