"""Write the exact meshes the own solver uses, for Blender to load (numpy only there)."""
import sys, numpy as np, shell as s
shape, res = sys.argv[1], int(sys.argv[2])
if shape in ("teabag", "mylar"):
    P, T, bnd = s.grid_square(res) if shape == "teabag" else s.disk(res)
    rest2, F, sheet, top, bot = s.pillow(P, T, bnd)
    pin = np.zeros(len(rest2), bool)
    bump = (np.sin(np.pi*rest2[:,0])*np.sin(np.pi*rest2[:,1]) if shape == "teabag" else 1-np.sum(rest2**2,1))
    z = 0.02*bump*(top.astype(float)-bot.astype(float))
else:  # puff: closed by a pinned flat bottom sheet (Blender pressure wants a closed mesh)
    P, T, bnd = s.grid_square(res)
    rest2, F, sheet, top, bot = s.pillow(P, T, bnd)
    pin = bot | np.r_[bnd, np.zeros(len(rest2)-len(P), bool)]
    z = 0.02*np.sin(np.pi*rest2[:,0])*np.sin(np.pi*rest2[:,1])*top
np.savez(f"out/mesh-{shape}-r{res}.npz", rest2=rest2, F=F, sheet=sheet, x0=np.c_[rest2, z], pin=pin)
print(shape, res, len(rest2), "verts", len(F), "tris", int(pin.sum()), "pinned")
