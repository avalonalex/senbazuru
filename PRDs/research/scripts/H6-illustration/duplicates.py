# H6 research: are coincident contour strokes the two sides of one boundary
# (opposite directions, overlapping intervals on one line)?
import json, math, sys
d = json.load(open(sys.argv[1])); PPU = d["pixelsPerSheetUnit"]
for v in d["views"]:
    segs = [(tuple(a), tuple(b)) for a, b in v["contours"]]
    same = opp = 0; overl_same = overl_opp = 0.0; total = sum(PPU*math.dist(a,b) for a,b in segs)
    for i, (a, b) in enumerate(segs):
        L = math.dist(a, b); u = ((b[0]-a[0])/L, (b[1]-a[1])/L)
        cov_same = []; cov_opp = []
        for j, (c, e) in enumerate(segs):
            if j == i: continue
            off = lambda p: abs(u[0]*(p[1]-a[1]) - u[1]*(p[0]-a[0]))
            if off(c) > 1e-6 or off(e) > 1e-6: continue
            s = lambda p: (p[0]-a[0])*u[0] + (p[1]-a[1])*u[1]
            lo, hi = sorted((s(c), s(e))); lo, hi = max(lo, 0), min(hi, L)
            if hi - lo <= 1e-9: continue
            ((cov_same if s(e) > s(c) else cov_opp)).append((lo, hi))
        def union(iv):
            iv.sort(); tot = 0; cur = None
            for lo, hi in iv:
                if cur and lo <= cur[1]: cur = (cur[0], max(cur[1], hi))
                else:
                    if cur: tot += cur[1]-cur[0]
                    cur = (lo, hi)
            return tot + (cur[1]-cur[0] if cur else 0)
        overl_same += PPU*union(cov_same); overl_opp += PPU*union(cov_opp)
    print(f"{v['id']:9s} total {total:.0f}px; overlapped by an opposite-direction contour {overl_opp:.0f}px ({100*overl_opp/total:.0f}%), by a same-direction contour {overl_same:.0f}px ({100*overl_same/total:.0f}%)")
