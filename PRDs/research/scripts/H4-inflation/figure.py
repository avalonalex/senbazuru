# Two figures for the note: mid-line profiles, and a shaded iso view of the
# tension-field pillow next to the sin-sin bump of examples/puffed-square.fold.
import json, math, numpy as np
out = "."
res = json.load(open("res_square_16_tfield.json"))
prof_tf = res["mid_profile_top"]
prof_sym = json.load(open("res_square_12_sym.json"))["mid_profile_top"]
# Blender 32x32 run
P = np.load("blender_stiff32long.npy"); n = 32
row = [P[(n // 2) * (n + 1) + i] for i in range(n + 1)]
prof_bl = [[float(p[0]), float(p[2])] for p in row]
xs = np.linspace(0, 1, 41)
prof_bump = [[float(x), 0.25 * math.sin(math.pi * x)] for x in xs]

W, H = 640, 320
def X(x): return 40 + x * 560
def Y(z): return 270 - z * 700
def path(pts, colour, dash=""):
    d = " ".join(("M" if k == 0 else "L") + f"{X(x):.1f},{Y(z):.1f}" for k, (x, z) in enumerate(pts))
    return f'<path d="{d}" fill="none" stroke="{colour}" stroke-width="2.2" {dash}/>'
svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="sans-serif" font-size="13">',
       '<rect width="100%" height="100%" fill="white"/>',
       f'<line x1="{X(0)}" y1="{Y(0)}" x2="{X(1)}" y2="{Y(0)}" stroke="#999"/>',
       f'<text x="{X(0)}" y="{Y(0)+18}">0</text><text x="{X(1)-8}" y="{Y(0)+18}">1</text>',
       f'<text x="{X(0.5)-150}" y="{Y(0)+36}">position across the middle of a unit-side pillow (top sheet)</text>',
       path(prof_bump, "#888", 'stroke-dasharray="6 4"'),
       path(prof_tf, "#1f5fa8"),
       path(prof_bl, "#c0392b", 'stroke-dasharray="2 3"'),
       path(prof_sym, "#2e8b57", 'stroke-dasharray="10 3 2 3"'),
       f'<text x="{X(0.02)}" y="84" fill="#2e8b57">green: no shortening allowed, no bending cost, 12x12 (folds along mesh edges)</text>',
       f'<text x="{X(0.02)}" y="30" fill="#888">grey dashed: 0.25 sin(pi x), the puffed-square bump (26% stretch)</text>',
       f'<text x="{X(0.02)}" y="48" fill="#1f5fa8">blue: tension-field solve, 16x16 (stretch below 0.01%)</text>',
       f'<text x="{X(0.02)}" y="66" fill="#c0392b">red dotted: Blender cloth pressure, 32x32, compression 0.1, frame 300</text>',
       '</svg>']
open(f"{out}/profiles.svg", "w").write("\n".join(svg))

# shaded iso view
def iso_svg(Xv, tris, fname, title):
    Xv = Xv - Xv.mean(0)
    az, el = math.radians(35), math.radians(30)
    Rz = np.array([[math.cos(az), -math.sin(az), 0], [math.sin(az), math.cos(az), 0], [0, 0, 1]])
    Rx = np.array([[1, 0, 0], [0, math.cos(el), -math.sin(el)], [0, math.sin(el), math.cos(el)]])
    V = Xv @ Rz.T
    # camera looks along +y after rotation; tilt down
    V = V @ Rx.T
    light = np.array([-0.4, -0.6, 0.7]); light /= np.linalg.norm(light)
    polys = []
    for t in tris:
        a, b, c = V[t]
        nrm = np.cross(b - a, c - a); ln = np.linalg.norm(nrm)
        if ln == 0: continue
        nrm /= ln
        if nrm[1] > 0:  # facing away from a viewer on -y
            continue
        depth = (a[1] + b[1] + c[1]) / 3
        shade = 0.35 + 0.65 * max(0.0, float(np.dot(Rx @ Rz @ np.zeros(3) + nrm, light)))
        polys.append((depth, [(p[0], p[2]) for p in (a, b, c)], shade))
    polys.sort(key=lambda q: -q[0])
    s = 260; ox, oy = 170, 170
    lines = [f'<svg xmlns="http://www.w3.org/2000/svg" width="340" height="320" viewBox="0 0 340 320" font-family="sans-serif" font-size="13"><rect width="100%" height="100%" fill="white"/>',
             f'<text x="10" y="20">{title}</text>']
    for _, pts, sh in polys:
        g = int(235 * sh + 10); col = f"rgb({g},{int(g*0.97)},{int(g*0.9)})"
        d = " ".join(f"{ox + s*x:.1f},{oy - s*z:.1f}" for x, z in pts)
        lines.append(f'<polygon points="{d}" fill="{col}" stroke="{col}" stroke-width="0.4"/>')
    lines.append("</svg>")
    open(f"{out}/{fname}", "w").write("\n".join(lines))

Xt = np.load("X_square_16_tfield.npy"); Tt = np.load("T_square_16_tfield.npy")
iso_svg(Xt, Tt, "pillow-tension-field.svg", "tension-field pillow, unit side")
# bump: mirror the fixture's single sheet into a closed pillow for a like-for-like view
d = json.load(open("/Users/yuhanhao/Project/senbazuru/examples/puffed-square.fold"))
Pb = np.array(d["vertices_coords"], float); Fb = np.array(d["faces_vertices"])
Pbot = Pb.copy(); Pbot[:, 2] *= -1
Xb = np.vstack([Pb, Pbot]); Tb = np.vstack([Fb, Fb[:, [0, 2, 1]] + len(Pb)])
# make top faces point up
x0, x1, x2 = Pb[Fb[:, 0]], Pb[Fb[:, 1]], Pb[Fb[:, 2]]
if np.cross(x1 - x0, x2 - x0)[:, 2].mean() < 0:
    Tb = np.vstack([Fb[:, [0, 2, 1]], Fb + len(Pb)])
iso_svg(Xb, Tb, "pillow-sin-bump.svg", "puffed-square bump, mirrored")
print("ok")
