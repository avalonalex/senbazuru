# H6 research: do the upright view's loose contour ends lie on the projected
# intersection segment of a crossing triangle pair recorded in checks.json?
import json, math, sys
B = "build/whole-crane"
fold = json.load(open(f"{B}/spread-0.fold")); P = fold["vertices_coords"]; F = fold["faces_vertices"]
checks = json.load(open(f"{B}/checks.json"))
state = [s for s in checks["states"] if s["title"].startswith("More tucked")][0]
pairs = state["contact"]["crossingPanels"]
def sub(a,b): return [a[i]-b[i] for i in range(3)]
def dot(a,b): return sum(a[i]*b[i] for i in range(3))
def cross(a,b): return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
def unit(a): n = math.sqrt(dot(a,a)); return [x/n for x in a]
f = unit([1, math.sqrt(2), -1]); r = unit(cross(f, [0,-1,0])); u = cross(r, f)
proj = lambda p: (dot(p, r)*600 + 741.85, -dot(p, u)*600 + 421.68)   # page transform fitted from the SVG
def clip_to_triangle(a, b, tri):
    # part of segment ab (in tri's plane) inside triangle tri, by half-planes
    n = cross(sub(tri[1], tri[0]), sub(tri[2], tri[0])); lo, hi = 0.0, 1.0
    for i in range(3):
        p, q = tri[i], tri[(i+1)%3]; inward = cross(n, sub(q, p))
        fa, fb = dot(sub(a, p), inward), dot(sub(b, p), inward)
        if fa < 0 and fb < 0: return None
        if fa < 0: lo = max(lo, fa/(fa-fb))
        elif fb < 0: hi = min(hi, fa/(fa-fb))
    if hi <= lo: return None
    return [a[k]+(b[k]-a[k])*lo for k in range(3)], [a[k]+(b[k]-a[k])*hi for k in range(3)]
def tri_line(t, plane_n, plane_d):
    # segment where triangle t crosses the plane n.x = d
    s = [dot(plane_n, v) - plane_d for v in t]; pts = []
    for i in range(3):
        a, b = t[i], t[(i+1)%3]
        if (s[i] > 0) != (s[(i+1)%3] > 0):
            w = s[i]/(s[i]-s[(i+1)%3]); pts.append([a[k]+(b[k]-a[k])*w for k in range(3)])
    return pts if len(pts) == 2 else None
segs = []
for a_name, b_name in pairs:
    ta = [P[v] for v in F[int(a_name.split("-")[1])]]; tb = [P[v] for v in F[int(b_name.split("-")[1])]]
    nb = cross(sub(tb[1], tb[0]), sub(tb[2], tb[0])); line = tri_line(ta, nb, dot(nb, tb[0]))
    if not line: continue
    seg = clip_to_triangle(line[0], line[1], tb)
    if seg: segs.append((proj(seg[0]), proj(seg[1])))
def seg_dist(x, a, b):
    dx, dy = b[0]-a[0], b[1]-a[1]; L2 = dx*dx+dy*dy
    t = 0 if L2 == 0 else max(0, min(1, ((x[0]-a[0])*dx+(x[1]-a[1])*dy)/L2))
    return math.hypot(x[0]-a[0]-t*dx, x[1]-a[1]-t*dy)
print(f"{len(pairs)} crossing pairs, {len(segs)} with a proper intersection segment")
for p in json.load(open(sys.argv[1])):
    d = min(seg_dist(p, a, b) for a, b in segs)
    print(f"loose end at ({p[0]:.1f}, {p[1]:.1f}) px: nearest projected crossing segment {d:.2f} px away")
