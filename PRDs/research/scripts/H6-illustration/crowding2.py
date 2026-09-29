# H6 research: nearest near-parallel other contour, per 0.5 px sample of
# contour ink, binned: coincident (<0.25 px), doubled (0.25-3 px), clear (>=3 px).
# Samples within 3 px of their own segment's ends are skipped (joins, corners).
import json, math, sys
d = json.load(open(sys.argv[1])); PPU = d["pixelsPerSheetUnit"]
def seg_dist(x, a, b):
    dx, dy = b[0]-a[0], b[1]-a[1]; L2 = dx*dx+dy*dy
    t = 0 if L2 == 0 else max(0, min(1, ((x[0]-a[0])*dx+(x[1]-a[1])*dy)/L2))
    return math.hypot(x[0]-a[0]-t*dx, x[1]-a[1]-t*dy)
for v in d["views"]:
    segs = [((a[0]*PPU, a[1]*PPU), (b[0]*PPU, b[1]*PPU)) for a, b in v["contours"]]
    dirs = [((b[0]-a[0])/math.dist(a,b), (b[1]-a[1])/math.dist(a,b)) for a, b in segs]
    bins = [0.0, 0.0, 0.0]; skipped = 0.0
    for i, (a, b) in enumerate(segs):
        L = math.dist(a, b); n = max(1, int(L/0.5)); w = L/n
        for k in range(n):
            t = (k+0.5)/n; x = (a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t)
            if min(t*L, (1-t)*L) < 3: skipped += w; continue
            best = min([seg_dist(x, c, e) for j, (c, e) in enumerate(segs) if j != i and abs(dirs[i][0]*dirs[j][0]+dirs[i][1]*dirs[j][1]) > math.cos(math.radians(15))] or [99])
            bins[0 if best < 0.25 else 1 if best < 3 else 2] += w
    tot = sum(bins)
    print(f"{v['id']:9s} of {tot:.0f}px sampled contour ink: coincident with another stroke {bins[0]:.0f}px ({100*bins[0]/tot:.0f}%), a separate parallel stroke 0.25-3px away {bins[1]:.0f}px ({100*bins[1]/tot:.0f}%), clear {bins[2]:.0f}px ({100*bins[2]/tot:.0f}%); near-end samples skipped {skipped:.0f}px")
