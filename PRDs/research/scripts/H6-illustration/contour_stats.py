# Measure fragmentation of the study's book-drawing contours (H6 research).
# Reads book-checks.json written by senbazuru-material-study --whole-crane-start.
import json, math, sys, collections
d = json.load(open(sys.argv[1]))
ppu = d['pixelsPerSheetUnit']
def key(p, eps=1e-7):
    return (round(p[0]/eps), round(p[1]/eps))
for v in d['views']:
    segs = v['contours']
    lens = [ppu*math.dist(a, b) for a, b in segs]
    # chain segments that share endpoints (degree-2 vertices joined)
    adj = collections.defaultdict(list)
    for i, (a, b) in enumerate(segs):
        adj[key(a)].append(i); adj[key(b)].append(i)
    deg = collections.Counter({k: len(x) for k, x in adj.items()})
    # connected components of the segment graph
    parent = list(range(len(segs)))
    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]; i = parent[i]
        return i
    for ids in adj.values():
        for j in ids[1:]:
            parent[find(j)] = find(ids[0])
    comps = collections.defaultdict(list)
    for i in range(len(segs)): comps[find(i)].append(i)
    clen = sorted((sum(lens[i] for i in c) for c in comps.values()), reverse=True)
    ends = sum(1 for k, n in deg.items() if n == 1)
    junctions = sum(1 for k, n in deg.items() if n >= 3)
    total = sum(lens)
    print(f"{v['id']:9s} segs={len(segs):4d} total={total:7.1f}px  <1px={sum(l<1 for l in lens):3d} <2px={sum(l<2 for l in lens):3d} <5px={sum(l<5 for l in lens):3d} "
          f"median={sorted(lens)[len(lens)//2]:.2f}px  components={len(comps):3d} (<5px total: {sum(c<5 for c in clen)}) "
          f"dangling-ends={ends} junctions(deg>=3)={junctions}  longest3={[round(x,1) for x in clen[:3]]}")
    cf = v["omittedCreases"] if isinstance(v["omittedCreases"], list) else []
    cl = [ppu*math.dist(a, b) for a, b in cf]
    print(f"          creases={len(cf)} <2px={sum(l<2 for l in cl)} <5px={sum(l<5 for l in cl)} total={sum(cl):.1f}px")
