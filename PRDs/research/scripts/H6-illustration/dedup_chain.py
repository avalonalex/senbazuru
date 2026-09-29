# H6 research: drop the second copy of each doubled contour (the opposite-
# direction edge of the piece across the same boundary), then chain what is
# left into strokes through points where exactly two pieces meet.
import json, math, sys, collections
d = json.load(open(sys.argv[1])); PPU = d["pixelsPerSheetUnit"]
for v in d["views"]:
    segs = [(tuple(a), tuple(b)) for a, b in v["contours"]]
    kept = []
    for i, (a, b) in enumerate(segs):
        L = math.dist(a, b); u = ((b[0]-a[0])/L, (b[1]-a[1])/L); cov = []
        for j, (c, e) in enumerate(segs[:i]):
            off = lambda p: abs(u[0]*(p[1]-a[1]) - u[1]*(p[0]-a[0]))
            if off(c) > 1e-6 or off(e) > 1e-6: continue
            s = lambda p: (p[0]-a[0])*u[0] + (p[1]-a[1])*u[1]
            lo, hi = sorted((s(c), s(e))); lo, hi = max(lo, 0), min(hi, L)
            if hi - lo > 1e-9: cov.append((lo, hi))
        pieces = [(0.0, L)]
        for lo, hi in cov:
            nxt = []
            for p, q in pieces:
                if hi <= p or lo >= q: nxt.append((p, q)); continue
                if lo > p: nxt.append((p, lo))
                if hi < q: nxt.append((hi, q))
            pieces = nxt
        for p, q in pieces:
            if q - p > 1e-9: kept.append(((a[0]+u[0]*p, a[1]+u[1]*p), (a[0]+u[0]*q, a[1]+u[1]*q)))
    key = lambda p: (round(p[0]*1e7), round(p[1]*1e7))
    adj = collections.defaultdict(list)
    for i, (a, b) in enumerate(kept): adj[key(a)].append(i); adj[key(b)].append(i)
    used = set(); chains = []
    def walk(vk, i):
        tot = 0.0
        while True:
            used.add(i); a, b = kept[i]; tot += PPU*math.dist(a, b)
            nk = key(b) if key(a) == vk else key(a)
            nb = [j for j in adj[nk] if j not in used]
            if len(adj[nk]) != 2 or not nb: return tot, len(adj[nk])
            vk, i = nk, nb[0]
    ends = collections.Counter(len(x) for x in adj.values())
    for vk, ids in adj.items():
        if len(ids) != 2:
            for i in ids:
                if i not in used: chains.append(walk(vk, i))
    for i in range(len(kept)):
        if i not in used: chains.append(walk(key(kept[i][0]), i))
    L = sorted(c[0] for c in chains); tot = sum(L)
    print(f"{v['id']:9s} unique contour {tot:.0f}px in {len(kept)} pieces -> {len(chains)} strokes; strokes <2px {sum(l<2 for l in L)}, <5px {sum(l<5 for l in L)}, <10px {sum(l<10 for l in L)}; median {L[len(L)//2]:.1f}px; "
          f"free ends (degree 1) {ends[1]}, junctions (degree>=3) {sum(n for k,n in ends.items() if k>=3)}")
