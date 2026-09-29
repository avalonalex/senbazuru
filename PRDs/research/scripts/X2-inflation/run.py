"""Driver: python run.py SHAPE RES MODE KS KB [TAG]
SHAPE in {teabag, mylar, puff}; MODE in {tension, full}. Side / radius = 1, p ramps to 1.
"""
import json
import os
import sys
import time

import numpy as np

import shell as s

shape, res, mode, ks, kb = sys.argv[1], int(sys.argv[2]), sys.argv[3], float(sys.argv[4]), float(sys.argv[5])
tag = sys.argv[6] if len(sys.argv) > 6 else ""
name = f"{shape}-{mode}-r{res}-ks{ks:g}-kb{kb:g}{tag}"
os.makedirs("out", exist_ok=True)
rng = np.random.default_rng(0)

if shape in ("teabag", "mylar"):
    P, T, bnd = s.grid_square(res) if shape == "teabag" else s.disk(res)
    rest2, F, sheet, top, bot = s.pillow(P, T, bnd)
    if shape == "teabag":
        bump = np.sin(np.pi * rest2[:, 0]) * np.sin(np.pi * rest2[:, 1])
    else:
        bump = 1 - np.sum(rest2 ** 2, axis=1)
    z = 0.02 * bump * (top.astype(float) - bot.astype(float))
    fixed = None
else:  # puff: one sheet, rim clamped, the plane z=0 closes the volume
    P, T, bnd = s.grid_square(res)
    rest2, F, sheet = P, T, np.zeros(len(T), int)
    z = 0.02 * np.sin(np.pi * P[:, 0]) * np.sin(np.pi * P[:, 1])
    fixed = bnd.copy()

x0 = np.c_[rest2, z]
if fixed is None:
    # pin nothing; remove rigid motion by fixing nothing (pressure is translation-free)
    pass
noise = 1e-3 * rng.standard_normal(x0.shape)
if fixed is not None:
    noise[fixed] = 0
x0 = x0 + noise

m = s.Model(rest2, F, sheet, ks=ks, kb=kb, mode=mode, fixed=fixed)
h = 1.0 / res
pressures = [0.1, 0.3, 1.0]
t0 = time.perf_counter()
x, stats = s.solve(m, x0, pressures, tol=1e-4, maxiter=40000, scale=1.0 / (h * h),
                   log=lambda d: print(json.dumps(d), flush=True))
wall = time.perf_counter() - t0
met, lam = s.measure(m, x, rest2)
met.update(name=name, shape=shape, res=res, mode=mode, ks=ks, kb=kb,
           nverts=int(len(x)), ntris=int(len(F)), nhinges=int(len(m.H)),
           seconds=wall, steps=stats)
if shape == "mylar":
    rim = np.isclose(np.linalg.norm(rest2, axis=1), 1.0)
    r = float(np.mean(np.linalg.norm(x[rim, :2] - x[:, :2].mean(0), axis=1)))
    met.update(rim_radius=r, tau_over_2r=met["thickness"] / (2 * r), V_over_a3=met["V"],
               ref=dict(rim_radius=1 / 1.3110287771, tau_over_2r=0.5990701173,
                        V_over_a3=2 / 3 * np.pi * (1 / 1.3110287771) ** 2))
if shape == "teabag":
    mid = np.where(np.isclose(rest2[:, 0], 0.5) & np.isclose(rest2[:, 1], 0.0))[0]
    corner = np.where(np.isclose(rest2[:, 0], 0.0) & np.isclose(rest2[:, 1], 0.0))[0]
    if len(mid):
        met.update(edge_mid_pull_in=float(x[mid[0], 1] - x[corner[0], 1]))
    met.update(ref=dict(V_lower=0.2055, V_upper=0.217, robin=0.2017))
if shape == "puff":
    met.update(ref=dict(drawn_bump_V=0.25 * (2 / np.pi) ** 2))
print(json.dumps({k: v for k, v in met.items() if k != "steps"}, indent=1))
json.dump(met, open(f"out/{name}.json", "w"), indent=1)
np.savez(f"out/{name}.npz", x=x, F=F, rest2=rest2, lam=lam, sheet=sheet)
s.write_obj(f"out/{name}.obj", x, F)
