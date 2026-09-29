import json, math, glob
pts = []
for f in glob.glob("sweep_r*.txt"):
    d = json.loads(open(f).read().strip().splitlines()[-1]); pts.append((d["p_over_kb"], d["volume"], d["thickness"]))
pts.sort()
vmax, tmax = 0.1953, 0.4975   # 8-cell tension-field pillow, no bending
W, H = 560, 300
X = lambda r: 60 + (math.log2(r) - 2) / 10 * 440
Y = lambda y: 250 - y * 200
s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="sans-serif" font-size="13"><rect width="100%" height="100%" fill="white"/>',
     f'<line x1="60" y1="{Y(0)}" x2="500" y2="{Y(0)}" stroke="#999"/><line x1="60" y1="{Y(0)}" x2="60" y2="{Y(1)}" stroke="#999"/>',
     f'<line x1="60" y1="{Y(1)}" x2="500" y2="{Y(1)}" stroke="#ccc" stroke-dasharray="4 4"/>',
     f'<text x="8" y="{Y(1)+4}">1.0</text><text x="8" y="{Y(0.5)+4}">0.5</text><text x="8" y="{Y(0)+4}">0</text>']
for r in (4, 16, 64, 256, 1024, 4096):
    s.append(f'<text x="{X(r)-14}" y="{Y(0)+18}">{r/2:g}</text>')
s.append(f'<text x="170" y="{Y(0)+38}">p L³ / B  (pressure in units of bending, log scale)</text>')
for key, col, lab, yy in ((1, "#1f5fa8", "volume / tension-field maximum", 30), (2, "#c0392b", "thickness / tension-field maximum", 48)):
    ref = vmax if key == 1 else tmax
    d = " ".join(("M" if i == 0 else "L") + f"{X(p[0]):.1f},{Y(p[key]/ref):.1f}" for i, p in enumerate(pts))
    s.append(f'<path d="{d}" fill="none" stroke="{col}" stroke-width="2.2"/>')
    for p in pts: s.append(f'<circle cx="{X(p[0]):.1f}" cy="{Y(p[key]/ref):.1f}" r="3" fill="{col}"/>')
    s.append(f'<text x="70" y="{yy}" fill="{col}">{lab}</text>')
s.append('</svg>')
open("sweep.svg", "w").write("\n".join(s))
for p in pts: print(p[0], p[0]/2, round(p[1],4), round(p[1]/vmax,3), round(p[2],4), round(p[2]/tmax,3))
