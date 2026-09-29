# Chain the study's book-drawing contour segments into strokes (maximal paths
# through vertices where exactly two segments meet) and report stroke lengths
# at the gallery's 600 px per sheet unit. Also counts sharp turns along chains.
import json, math, sys, collections
d = json.load(open(sys.argv[1]))
ppu = d['pixelsPerSheetUnit']
def key(p, eps=1e-9):
    return (round(p[0]/eps), round(p[1]/eps))
for v in d['views']:
    segs = [(key(a), key(b), a, b) for a, b in v['contours']]
    adj = collections.defaultdict(list)
    for i, (ka, kb, a, b) in enumerate(segs):
        adj[ka].append(i); adj[kb].append(i)
    used = set(); chains = []
    def walk(start_vertex, i):
        pts = []; total = 0.0; v0 = start_vertex; turns = 0; prevdir = None
        while True:
            used.add(i)
            ka, kb, a, b = segs[i]
            nxt = kb if ka == v0 else ka
            p, q = (a, b) if ka == v0 else (b, a)
            total += ppu*math.dist(p, q)
            dvec = (q[0]-p[0], q[1]-p[1]); n = math.hypot(*dvec)
            if n > 0:
                dvec = (dvec[0]/n, dvec[1]/n)
                if prevdir is not None:
                    c = max(-1, min(1, dvec[0]*prevdir[0]+dvec[1]*prevdir[1]))
                    if math.degrees(math.acos(c)) > 30: turns += 1
                prevdir = dvec
            nbrs = [j for j in adj[nxt] if j not in used]
            if len(adj[nxt]) != 2 or not nbrs:
                return total, turns
            v0, i = nxt, nbrs[0]
    for vert, ids in adj.items():
        if len(ids) != 2:
            for i in ids:
                if i not in used: chains.append(walk(vert, i))
    for i in range(len(segs)):
        if i not in used: chains.append(walk(segs[i][0], i))
    L = sorted(c[0] for c in chains)
    print(f"{v['id']:9s} strokes={len(chains):4d}  <2px={sum(l<2 for l in L):3d}  <5px={sum(l<5 for l in L):3d}  <10px={sum(l<10 for l in L):3d}  median={L[len(L)//2]:.1f}px  max={L[-1]:.0f}px  sharp(>30deg) turns inside strokes={sum(c[1] for c in chains)}")
