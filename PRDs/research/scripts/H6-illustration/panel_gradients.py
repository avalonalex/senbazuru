# H6 research: how much does lighting vary inside each source panel of the
# tucked crane, and how much of that variation does one linear gradient in
# page coordinates capture? Uses CraneBookDrawing's light direction and the
# camera-facing side of each triangle (per-triangle normals; no visibility).
import json, math, sys, collections
B = sys.argv[1]
fold = json.load(open(f"{B}/spread-0.fold"))
P = fold["vertices_coords"]; F = fold["faces_vertices"]; panels = fold["senbazuru:source_panels"]
def sub(a,b): return [a[i]-b[i] for i in range(3)]
def dot(a,b): return sum(a[i]*b[i] for i in range(3))
def cross(a,b): return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
def unit(a): n = math.sqrt(dot(a,a)); return [x/n for x in a]
def comb(*terms): return [sum(c*v[i] for c, v in terms) for i in range(3)]
VIEWS = {"upright": ((1, math.sqrt(2), -1), (0,-1,0)), "top": ((0, 1, 0.15), (-1,0,0))}
def solve3(M, b):
    # Cramer's rule for the 3x3 normal equations
    def det(m): return m[0][0]*(m[1][1]*m[2][2]-m[1][2]*m[2][1]) - m[0][1]*(m[1][0]*m[2][2]-m[1][2]*m[2][0]) + m[0][2]*(m[1][0]*m[2][1]-m[1][1]*m[2][0])
    D = det(M)
    if abs(D) < 1e-18: return None
    out = []
    for k in range(3):
        m = [row[:] for row in M]
        for i in range(3): m[i][k] = b[i]
        out.append(det(m)/D)
    return out
for vid, (direction, up) in VIEWS.items():
    f = unit(direction); r = unit(cross(f, up)); u = cross(r, f)
    light = unit(comb((-0.4, r), (0.7, u), (-1.0, f)))
    rows = collections.defaultdict(list)
    for i, (a, b, c) in enumerate(F):
        n = cross(sub(P[b], P[a]), sub(P[c], P[a])); area = 0.5*math.sqrt(dot(n, n)); n = unit(n)
        facing = n if dot(n, f) < 0 else [-x for x in n]
        cx = [(P[a][k]+P[b][k]+P[c][k])/3 for k in range(3)]
        rows[panels[i]].append((area, dot(cx, r), dot(cx, u), dot(light, facing)))
    varied = 0; stats = []
    for p, rs in rows.items():
        W = sum(w for w, *_ in rs); mean = sum(w*s for w, _, _, s in rs)/W
        flat_rms = math.sqrt(sum(w*(s-mean)**2 for w, _, _, s in rs)/W)
        span = max(s for *_, s in rs) - min(s for *_, s in rs)
        M = [[0.0]*3 for _ in range(3)]; bb = [0.0]*3
        for w, x, y, s in rs:
            v = (1.0, x, y)
            for i in range(3):
                bb[i] += w*v[i]*s
                for j in range(3): M[i][j] += w*v[i]*v[j]
        coef = solve3(M, bb) if len(rs) >= 3 else None
        lin_rms = flat_rms if coef is None else math.sqrt(sum(w*(s-(coef[0]+coef[1]*x+coef[2]*y))**2 for w, x, y, s in rs)/W)
        stats.append((p, len(rs), span, flat_rms, lin_rms))
    curved = [s for s in stats if s[2] > 0.05]
    print(f"{vid}: {len(stats)} panels; {len(curved)} have a brightness span above 0.05 (of the 0..1 Lambert scale)")
    fr = sum(s[3] for s in curved)/max(1,len(curved)); lr = sum(s[4] for s in curved)/max(1,len(curved))
    print(f"   over those panels: mean RMS error of one flat tone {fr:.3f}, of one linear gradient {lr:.3f}")
    for s in sorted(curved, key=lambda s: -s[2])[:6]:
        print(f"   panel {s[0]:3d}: {s[1]:3d} triangles, span {s[2]:.2f}, flat-tone RMS {s[3]:.3f}, linear-gradient RMS {s[4]:.3f}")
