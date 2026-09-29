"""Does a CalculiX shell mesh treat a flat fold as a hinge?  (experiment Y6, own code)

A strip (width 0.2, length 1) folded back on itself at x = 1: layer A at z = 0,
layer B returning above it at z = GAP.  Layer A is held; the free end of B is
pushed up.  Two ways to join the layers at the fold line:
  shared : B's fold-line nodes ARE A's nodes.  The two shells meet with normals
           ~170 deg apart, so CalculiX makes each such node a 'knot' (a rigid
           body; manual 2.23 sec. 6.2.14).
  hinge  : B gets its own fold-line nodes, tied to A's by *EQUATION on the
           three translations only (the manual's recipe for an internal hinge).
usage: python fold_test.py {shared|hinge} [GAP]
"""

import sys

import numpy as np

mode = sys.argv[1]
gap = float(sys.argv[2]) if len(sys.argv) > 2 else 0.01
nx, ny, W = 20, 4, 0.2
ks, kb = 1e3, 1e-3
t = float(np.sqrt(12 * kb / ks))
E = ks / t
nodes, ida, idb = [], {}, {}
for j in range(ny + 1):
    for i in range(nx + 1):
        ida[i, j] = len(nodes) + 1
        nodes.append((i / nx, j * W / ny, 0.0))
for j in range(ny + 1):
    for i in range(nx + 1):
        if i == nx and mode == "shared":
            idb[i, j] = ida[i, j]
            continue
        idb[i, j] = len(nodes) + 1
        # B runs back from the fold line; its fold-line row sits on A's (hinge mode: coincident nodes)
        nodes.append((i / nx, j * W / ny, 0.0 if i == nx else gap))
L = ["*HEADING", f"Y6 fold test {mode}", "*NODE, NSET=Nall"]
L += [f"{k + 1}, {x:.10g}, {y:.10g}, {z:.10g}" for k, (x, y, z) in enumerate(nodes)]
L += ["*ELEMENT, TYPE=S4, ELSET=EA"]
e = 0
for j in range(ny):
    for i in range(nx):
        e += 1
        L.append(f"{e}, {ida[i, j]}, {ida[i + 1, j]}, {ida[i + 1, j + 1]}, {ida[i, j + 1]}")
L += ["*ELEMENT, TYPE=S4, ELSET=EB"]
for j in range(ny):
    for i in range(nx):
        e += 1
        # reversed winding: B's normal points down, as a sheet folded over would
        L.append(f"{e}, {idb[i, j]}, {idb[i, j + 1]}, {idb[i + 1, j + 1]}, {idb[i + 1, j]}")
L += ["*ELSET, ELSET=Eall", "EA, EB"]
L += ["*NSET, NSET=NA"] + [str(ida[i, j]) for j in range(ny + 1) for i in range(nx)]  # A minus the fold line
L += ["*NSET, NSET=Ntip"] + [str(idb[0, j]) for j in range(ny + 1)]
L += ["*MATERIAL, NAME=PAPER", "*ELASTIC", f"{E:.10g}, 0.", "*DENSITY", "1.",
      "*SHELL SECTION, ELSET=Eall, MATERIAL=PAPER", f"{t:.10g}"]
if mode == "hinge":
    L += ["*EQUATION"]
    for j in range(ny + 1):
        for dof in (1, 2, 3):
            L += ["2", f"{idb[nx, j]}, {dof}, 1., {ida[nx, j]}, {dof}, -1."]
# the free end of B is lifted by a prescribed 0.3 (static); its reaction force says how hard the fold resists
L += ["*BOUNDARY", "NA, 1, 3",
      "*STEP, NLGEOM, INC=100000", "*STATIC", "0.01, 1., 1e-6, 0.05",
      "*BOUNDARY", "Ntip, 3, 3, 0.3"]
L += ["*NODE PRINT, NSET=Nall, FREQUENCY=100000", "U", "*NODE PRINT, NSET=Ntip, TOTALS=ONLY", "RF", "*END STEP", ""]
open(f"runs/fold-{mode}.inp", "w").write("\n".join(L))
np.save(f"runs/fold-{mode}.nodes.npy", np.array(nodes))
np.save(f"runs/fold-{mode}.ids.npy", np.array([[ida[i, ny // 2], idb[i, ny // 2]] for i in range(nx + 1)]))
print("wrote", mode, "t =", t)
