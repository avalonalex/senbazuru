# H6 research: where does the study's book-drawing contour ink come from, and
# what would mesh-edge and interpolated contours look like on the same mesh?
# Inputs: spread-0.fold and book-checks.json from --whole-crane-start (study).
import json, math, sys, collections
B = sys.argv[1]
fold = json.load(open(f"{B}/spread-0.fold"))
checks = json.load(open(f"{B}/book-checks.json"))
P = fold["vertices_coords"]; F = fold["faces_vertices"]; E = fold["edges_vertices"]; A = fold["edges_assignment"]
panels = fold["senbazuru:source_panels"]
PPU = 600.0
def sub(a,b): return [a[i]-b[i] for i in range(3)]
def dot(a,b): return sum(a[i]*b[i] for i in range(3))
def cross(a,b): return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
def unit(a):
    n = math.sqrt(dot(a,a)); return [x/n for x in a]
def basis(direction, up):
    f = unit(direction); r = unit(cross(f, up)); u = cross(r, f); return r, u, f
VIEWS = {"upright": ((1, math.sqrt(2), -1), (0,-1,0)), "opposite": ((1, math.sqrt(2), 1), (0,-1,0)),
         "low": ((1, 0.4, -1), (0,-1,0)), "top": ((0, 1, 0.15), (-1,0,0))}
# face normals (area-weighted), edge->faces
fn = [cross(sub(P[b],P[a]), sub(P[c],P[a])) for a,b,c in F]
edge_faces = collections.defaultdict(list)
for i,(a,b,c) in enumerate(F):
    for x,y in ((a,b),(b,c),(c,a)): edge_faces[frozenset((x,y))].append(i)
assign = {frozenset(e): A[i] for i,e in enumerate(E)}
# panel-local vertex normals, as PaperLighting does (area-weighted, keyed by panel and vertex)
vn = collections.defaultdict(lambda: [0.0,0.0,0.0])
for i,(a,b,c) in enumerate(F):
    for v in (a,b,c):
        s = vn[(panels[i], v)]
        for k in range(3): s[k] += fn[i][k]
for view in checks["views"]:
    vid = view["id"]; r,u,f = basis(*VIEWS[vid])
    proj = lambda p: (dot(p,r), dot(p,u))
    # (1) classify drawn contour segments by the mesh edge they lie along
    pe = []
    for key, fs in edge_faces.items():
        a,b = tuple(key); pe.append((proj(P[a]), proj(P[b]), assign.get(key, "?")))
    def along(p, q):
        best = None
        for a,b,t in pe:
            d = (b[0]-a[0], b[1]-a[1]); L = math.hypot(*d)
            if L < 1e-12: continue
            def off(x): return abs(d[0]*(x[1]-a[1]) - d[1]*(x[0]-a[0]))/L
            def par(x): return ((x[0]-a[0])*d[0] + (x[1]-a[1])*d[1])/L
            if off(p) < 1e-7 and off(q) < 1e-7 and -1e-7 <= par(p) <= L+1e-7 and -1e-7 <= par(q) <= L+1e-7:
                rank = {"B":0,"M":1,"V":1,"F":2,"U":2,"J":3}.get(t,4)
                if best is None or rank < best[0]: best = (rank, t)
        return best[1] if best else "clip"
    kinds = collections.Counter(); lens = collections.Counter()
    for p,q in view["contours"]:
        k = along(p,q); k = {"M":"crease","V":"crease","F":"crease","U":"crease"}.get(k,k)
        kinds[k] += 1; lens[k] += PPU*math.dist(p,q)
    tot = sum(lens.values())
    print(f"{vid:9s} drawn contour by source: " + ", ".join(f"{k} {kinds[k]} segs / {lens[k]:.0f}px ({100*lens[k]/tot:.0f}%)" for k in ("B","crease","J","clip") if kinds[k]))
    # (2) mesh-edge contour generators: facing sign changes across interior edges
    sgn = [dot(n, f) for n in fn]
    mesh = collections.Counter(); meshlen = collections.Counter()
    for key, fs in edge_faces.items():
        if len(fs) == 2 and (sgn[fs[0]] > 0) != (sgn[fs[1]] > 0):
            t = assign.get(key, "?"); t = "J" if t == "J" else "crease"
            a,b = tuple(key); mesh[t] += 1; meshlen[t] += PPU*math.dist(proj(P[a]), proj(P[b]))
    # (3) interpolated contours inside panels (zero set of n_vertex . f, per triangle)
    segs = 0; ilen = 0.0; tri_with = 0
    for i,(a,b,c) in enumerate(F):
        g = {v: dot(unit(vn[(panels[i], v)]), f) for v in (a,b,c)}
        pts = []
        for x,y in ((a,b),(b,c),(c,a)):
            if (g[x] > 0) != (g[y] > 0):
                t = g[x]/(g[x]-g[y]); pts.append([P[x][k] + t*(P[y][k]-P[x][k]) for k in range(3)])
        if len(pts) == 2:
            segs += 1; ilen += PPU*math.dist(proj(pts[0]), proj(pts[1]))
    print(f"          mesh-edge contour generators (before visibility): across creases {mesh['crease']} edges/{meshlen['crease']:.0f}px, across triangle joins {mesh['J']} edges/{meshlen['J']:.0f}px; interpolated (panel-smoothed normals, before visibility): {segs} segments/{ilen:.0f}px")
