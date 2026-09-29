"""Write a CalculiX input deck for the square tea bag (experiment Y6, own code).

The tea bag is two unit squares joined at the rim and inflated.  By up-down
symmetry the rim stays in the plane z = 0, so only the TOP sheet is modelled:
every rim node gets u_z = 0 and nothing else (a translational-only constraint
on a CalculiX shell node is a hinge, manual 2.23 sec. 6.2.14), which is the
seam of the real bag.  In-plane rigid motion is removed with two nodes (centre
u_x = u_y = 0; rim midpoint (1, 0.5) u_y = 0), so any wrinkle pattern is
allowed.  Total volume = 2 x the volume between the sheet and z = 0.

Units are X2's: side L = 1, pressure p = 1, so
    ks = E t / (p L)      (membrane stiffness)
    kb = D / (p L^3),  D = E t^3 / (12 (1 - nu^2))   (bending stiffness)
and t, E follow from (ks, kb, nu).

usage: python gen.py NAME [--elem S4|S4R|S8R|M3D4] [--n 32] [--mat iso|tension]
                          [--ks 1e3] [--kb 1e-3] [--nu 0] [--proc static|dynamic] ...
"""

import argparse
import json
import os

import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("name")
ap.add_argument("--elem", default="S4")
ap.add_argument("--n", type=int, default=32)
ap.add_argument("--mat", default="iso")
ap.add_argument("--ks", type=float, default=1e3)
ap.add_argument("--kb", type=float, default=1e-3)
ap.add_argument("--nu", type=float, default=0.0)
ap.add_argument("--proc", default="static")
ap.add_argument("--bump", type=float, default=0.02, help="rest-shape dome height (X2 used 0.02 as its start)")
ap.add_argument("--imp", type=float, default=0.0, help="smooth random z imperfection, amplitude in units of t")
ap.add_argument("--kmax", type=int, default=8, help="highest Fourier mode in the imperfection")
ap.add_argument("--seed", type=int, default=0)
ap.add_argument("--p", type=float, default=1.0)
ap.add_argument("--sign", type=float, default=1.0, help="sign of the *DLOAD P value that pushes the sheet up")
ap.add_argument("--inc", type=float, default=1e-3)
ap.add_argument("--incmin", type=float, default=1e-9)
ap.add_argument("--incmax", type=float, default=0.02)
ap.add_argument("--time", type=float, default=1.0)
ap.add_argument("--hold", type=float, default=0.0, help="dynamic only: extra time at full pressure")
ap.add_argument("--tcomp", type=float, default=1e-4, help="tension-only: transition half-width in strain")
ap.add_argument("--rho", type=float, default=1.0)
ap.add_argument("--freq", type=int, default=100000, help="print displacements every FREQ increments (and at the end)")
ap.add_argument("--alpha", type=float, default=-0.3, help="dynamic: HHT alpha (numerical damping)")
ap.add_argument("--rayleigh", type=float, default=0.0, help="dynamic: mass-proportional damping coefficient")
a = ap.parse_args()

n = a.n
t = float(np.sqrt(12 * (1 - a.nu**2) * a.kb / a.ks))
E = a.ks / t
quad = a.elem in ("S8", "S8R", "M3D8", "M3D8R")

# ---------------------------------------------------------------- nodes
m = 2 * n if quad else n  # node lines per side
xs = np.linspace(0.0, 1.0, m + 1)
ids = -np.ones((m + 1, m + 1), int)
P = []
for j in range(m + 1):
    for i in range(m + 1):
        if quad and i % 2 == 1 and j % 2 == 1:
            continue  # element centre: not a node of an 8-node element
        ids[i, j] = len(P) + 1
        P.append((xs[i], xs[j]))
P = np.array(P)
z = a.bump * np.sin(np.pi * P[:, 0]) * np.sin(np.pi * P[:, 1])
if a.imp > 0:
    rng = np.random.default_rng(a.seed)
    w = np.zeros(len(P))
    for kx in range(1, a.kmax + 1):
        for ky in range(1, a.kmax + 1):
            w += rng.standard_normal() * np.sin(kx * np.pi * P[:, 0]) * np.sin(ky * np.pi * P[:, 1]) / (kx * kx + ky * ky)
    z += a.imp * t * w / np.abs(w).max()
X = np.c_[P, z]

# ---------------------------------------------------------------- elements (anticlockwise from +z: normal +z)
E_ = []
if quad:
    for j in range(0, m, 2):
        for i in range(0, m, 2):
            E_.append([ids[i, j], ids[i + 2, j], ids[i + 2, j + 2], ids[i, j + 2],
                       ids[i + 1, j], ids[i + 2, j + 1], ids[i + 1, j + 2], ids[i, j + 1]])
else:
    for j in range(m):
        for i in range(m):
            E_.append([ids[i, j], ids[i + 1, j], ids[i + 1, j + 1], ids[i, j + 1]])
E_ = np.array(E_)

rim = [ids[i, j] for j in range(m + 1) for i in range(m + 1)
       if ids[i, j] > 0 and (i in (0, m) or j in (0, m))]
centre = ids[m // 2, m // 2]
side = ids[m, m // 2]

# ---------------------------------------------------------------- deck
L = ["*HEADING", f"Y6 tea bag {a.name}", "*NODE, NSET=Nall"]
L += [f"{k + 1}, {x:.10g}, {y:.10g}, {zz:.10g}" for k, (x, y, zz) in enumerate(X)]
L += [f"*ELEMENT, TYPE={a.elem}, ELSET=Eall"]
for e, conn in enumerate(E_):
    L.append(f"{e + 1}, " + ", ".join(str(c) for c in conn))
L += ["*NSET, NSET=Nrim"] + [str(r) for r in rim]
if a.mat == "tension":
    # CalculiX 'TENSION ONLY' user material (manual 6.8.12): constants E and the largest allowed
    # compressive stress E*eps/pi, where eps is the half-width of the switch in principal strain.
    L += ["*MATERIAL, NAME=TENSION_ONLY_PAPER", "*USER MATERIAL, CONSTANTS=2",
          f"{E:.10g}, {E * a.tcomp / np.pi:.10g}"]
    mname = "TENSION_ONLY_PAPER"
else:
    L += ["*MATERIAL, NAME=PAPER", "*ELASTIC", f"{E:.10g}, {a.nu:.10g}"]
    mname = "PAPER"
L += ["*DENSITY", f"{a.rho:.10g}"]
sect = "*MEMBRANE SECTION" if a.elem.startswith("M3D") else "*SHELL SECTION"
L += [f"{sect}, ELSET=Eall, MATERIAL={mname}", f"{t:.10g}"]
if a.proc == "dynamic" and a.rayleigh > 0:
    L += ["*DAMPING, ALPHA=%g, BETA=0." % a.rayleigh]  # mass-proportional (model definition card)
L += ["*BOUNDARY", "Nrim, 3, 3", f"{centre}, 1, 2", f"{side}, 2, 2"]
L += ["*AMPLITUDE, NAME=RAMP", f"0., 0., {a.time:.10g}, 1., {a.time + a.hold + 1:.10g}, 1."]
if a.proc == "static":
    L += ["*STEP, NLGEOM, INC=100000", "*STATIC", f"{a.inc:g}, {a.time:g}, {a.incmin:g}, {a.incmax:g}"]
else:
    L += ["*STEP, NLGEOM, INC=100000", f"*DYNAMIC, ALPHA={a.alpha:g}",
          f"{a.inc:g}, {a.time + a.hold:g}, {a.incmin:g}, {a.incmax:g}"]
# shells take label P; membranes need P1 (label P on M3D4 is silently ignored in 2.23: zero load)
lab = "P1" if a.elem.startswith("M3D") else "P"
L += ["*DLOAD, AMPLITUDE=RAMP", f"Eall, {lab}, {a.sign * a.p:.10g}"]
L += [f"*NODE PRINT, NSET=Nall, FREQUENCY={a.freq}", "U"]
L += ["*NODE FILE, FREQUENCY=100000", "U", "*END STEP", ""]

os.makedirs("runs", exist_ok=True)
with open(f"runs/{a.name}.inp", "w") as fh:
    fh.write("\n".join(L))
# quads -> triangles for post-processing (corner nodes only)
tri = np.r_[E_[:, [0, 1, 2]], E_[:, [0, 2, 3]]] - 1
meta = dict(vars(a), t=t, E=E, nnodes=len(P), nelems=len(E_), D=E * t**3 / (12 * (1 - a.nu**2)))
np.savez(f"runs/{a.name}.mesh.npz", X=X, tri=tri, quad8=int(quad))
json.dump(meta, open(f"runs/{a.name}.meta.json", "w"), indent=1)
print(json.dumps(meta))
