# H6 research: how much contour ink runs within D px of another, nearly parallel
# contour stroke (the stacked-layer "hairy" look), at 600 px per sheet unit.
import json, math, sys
d = json.load(open(sys.argv[1])); PPU = d["pixelsPerSheetUnit"]
def samples(p, q, step=0.5):
    L = PPU*math.dist(p, q); n = max(1, int(L/step))
    return [((p[0]+(q[0]-p[0])*(i+0.5)/n)*PPU, (p[1]+(q[1]-p[1])*(i+0.5)/n)*PPU) for i in range(n)], L/n
def seg_dist(x, a, b):
    ax, ay = a; bx, by = b; dx, dy = bx-ax, by-ay; L2 = dx*dx+dy*dy
    t = 0 if L2 == 0 else max(0, min(1, ((x[0]-ax)*dx+(x[1]-ay)*dy)/L2))
    return math.hypot(x[0]-ax-t*dx, x[1]-ay-t*dy)
for v in d["views"]:
    segs = [((a[0]*PPU, a[1]*PPU), (b[0]*PPU, b[1]*PPU)) for a, b in v["contours"]]
    dirs = []
    for a, b in segs:
        L = math.dist(a, b); dirs.append(((b[0]-a[0])/L, (b[1]-a[1])/L) if L > 0 else (0, 0))
    for D in (2.0, 4.0):
        crowded = 0.0; total = 0.0
        for i, (a, b) in enumerate(v["contours"]):
            pts, w = samples(a, b); total += w*len(pts)
            for x in pts:
                for j, (c, e) in enumerate(segs):
                    if j == i: continue
                    # nearly parallel and near, but not merely touching at a shared endpoint
                    if abs(dirs[i][0]*dirs[j][0]+dirs[i][1]*dirs[j][1]) > math.cos(math.radians(15)) and seg_dist(x, c, e) < D and min(math.dist(x, c), math.dist(x, e)) > D:
                        crowded += w; break
        print(f"{v['id']:9s} contour ink within {D:.0f}px of another near-parallel contour: {crowded:.0f} of {total:.0f}px ({100*crowded/total:.0f}%)")
