"""Three stacked layers under CalculiX contact (experiment Y6, own code).

A strip (width 0.2) Z-folded into three layers, built the airbag way: each fold
is a half circle of radius g/2 joining layers g apart (midplane to midplane),
so the start is thick and non-intersecting by construction.  The bottom layer
is held; a pressure pushes the top layer down.  With CONTACT the three layers
should stop at about one thickness t apart; without it they pass through.

A shell in CalculiX is expanded into a solid of thickness t, so a fold of
radius below t/2 would make inverted solids: g < t cannot be built at all.

usage: python stack_test.py NAME G_OVER_T {contact|none} [P]
"""

import sys

import numpy as np

name, gt, mode = sys.argv[1], float(sys.argv[2]), sys.argv[3]
p = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
ks, kb = 1e3, 1e-3
t = float(np.sqrt(12 * kb / ks))
E = ks / t
g = gt * t
R = g / 2
nx, na, ny, W = 40, 12, 4, 0.2  # elements per layer, per fold arc, across the width

# centre line of the strip as (x, z) along arc length, layer by layer
pts, tag = [], []  # tag: layer index, or -1 for fold arcs
for i in range(nx + 1):  # layer 0, x 0 -> 1, z = 0
    pts.append((i / nx, 0.0)); tag.append(0)
for k in range(1, na):  # fold at x = 1, bulging to +x
    th = -np.pi / 2 + np.pi * k / na
    pts.append((1 + R * np.cos(th), R + R * np.sin(th))); tag.append(-1)
for i in range(nx, -1, -1):  # layer 1, x 1 -> 0, z = g
    pts.append((i / nx, g)); tag.append(1)
for k in range(1, na):  # fold at x = 0, bulging to -x
    th = np.pi / 2 + np.pi * k / na
    pts.append((0 + R * np.cos(th), 1.5 * g + R * np.sin(th))); tag.append(-1)
for i in range(nx + 1):  # layer 2, x 0 -> 1, z = 2g
    pts.append((i / nx, 2 * g)); tag.append(2)
pts, tag = np.array(pts), np.array(tag)
ns = len(pts)
nid = lambda s, j: j * ns + s + 1  # noqa: E731
L = ["*HEADING", f"Y6 stack test {name}", "*NODE, NSET=Nall"]
for j in range(ny + 1):
    for s in range(ns):
        L.append(f"{nid(s, j)}, {pts[s, 0]:.12g}, {j * W / ny:.12g}, {pts[s, 1]:.12g}")
L.append("*ELEMENT, TYPE=S4, ELSET=Eall")
elay = []
e = 0
for j in range(ny):
    for s in range(ns - 1):
        e += 1
        # winding chosen so layer 0's normal is +z; it flips at every fold, as paper does
        L.append(f"{e}, {nid(s, j)}, {nid(s + 1, j)}, {nid(s + 1, j + 1)}, {nid(s, j + 1)}")
        lay = tag[s] if tag[s] == tag[s + 1] else -1
        elay.append(lay)
elay = np.array(elay)
for k in range(3):
    L += [f"*ELSET, ELSET=L{k}"] + [str(i + 1) for i in np.where(elay == k)[0]]
L += ["*NSET, NSET=N0"] + [str(nid(s, j)) for j in range(ny + 1) for s in range(ns) if tag[s] == 0]
L += ["*MATERIAL, NAME=PAPER", "*ELASTIC", f"{E:.10g}, 0.", "*SHELL SECTION, ELSET=Eall, MATERIAL=PAPER", f"{t:.10g}"]
if mode == "contact":
    # layer 0 normal +z: its top is SPOS; layer 1 normal -z: its bottom is SPOS, its top SNEG; layer 2 normal +z: bottom SNEG
    L += ["*SURFACE, NAME=S0TOP, TYPE=ELEMENT", "L0, SPOS",
          "*SURFACE, NAME=S1BOT, TYPE=ELEMENT", "L1, SPOS",
          "*SURFACE, NAME=S1TOP, TYPE=ELEMENT", "L1, SNEG",
          "*SURFACE, NAME=S2BOT, TYPE=ELEMENT", "L2, SNEG",
          "*SURFACE INTERACTION, NAME=SI", "*SURFACE BEHAVIOR, PRESSURE-OVERCLOSURE=LINEAR",
          "1e5",  # contact pressure per unit overclosure: p = 1 closes 1e-5 = 0.3% of t
          "*CONTACT PAIR, INTERACTION=SI, TYPE=SURFACE TO SURFACE", "S1BOT, S0TOP",
          "*CONTACT PAIR, INTERACTION=SI, TYPE=SURFACE TO SURFACE", "S2BOT, S1TOP"]
L += ["*BOUNDARY", "N0, 1, 3",
      "*STEP, NLGEOM, INC=100000", "*STATIC", "0.01, 1., 1e-7, 0.05",
      "*DLOAD", f"L2, P, {p:.6g}",  # positive P pushes along the normal (+z for layer 2): pass P < 0 to push down
      "*NODE PRINT, NSET=Nall, FREQUENCY=100000", "U", "*END STEP", ""]
open(f"runs/{name}.inp", "w").write("\n".join(L))
np.savez(f"runs/{name}.stack.npz", pts=pts, tag=tag, ns=ns, ny=ny, t=t, g=g)
print(name, "t", t, "g", g, "nodes", ns * (ny + 1), "elements", e)
