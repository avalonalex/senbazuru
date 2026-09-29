import sys, math, numpy as np
out = "."
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
    s = 150; ox, oy = 170, 175
    lines = [f'<svg xmlns="http://www.w3.org/2000/svg" width="340" height="320" viewBox="0 0 340 320" font-family="sans-serif" font-size="13"><rect width="100%" height="100%" fill="white"/>',
             f'<text x="10" y="20">{title}</text>']
    for _, pts, sh in polys:
        g = int(235 * sh + 10); col = f"rgb({g},{int(g*0.97)},{int(g*0.9)})"
        d = " ".join(f"{ox + s*x:.1f},{oy - s*z:.1f}" for x, z in pts)
        lines.append(f'<polygon points="{d}" fill="{col}" stroke="{col}" stroke-width="0.4"/>')
    lines.append("</svg>")
    open(f"{out}/{fname}", "w").write("\n".join(lines))


n = int(sys.argv[1])
Xc = np.load(f"X_cube_{n}.npy"); Tc = np.load(f"T_cube_{n}.npy")
iso_svg(Xc, Tc, f"cube-tension-field-{n}.svg", f"tension-field cube, {n} cells per edge")
print("ok")
