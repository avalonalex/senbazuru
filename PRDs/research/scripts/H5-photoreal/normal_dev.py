# Deviation between PaperLighting-style corner normals (area-weighted sum per
# (source panel, material vertex)) and each triangle's flat normal.
import json, math, sys
d = json.load(open(sys.argv[1]))
P = d['vertices_coords']; F = d['faces_vertices']; panels = d['senbazuru:source_panels']
def sub(a, b): return [a[i] - b[i] for i in range(3)]
def cross(a, b): return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
def norm(a): return math.sqrt(sum(x*x for x in a))
sums = {}
tri = []
for fi, f in enumerate(F):
    a, b, c = (P[i] for i in f)
    n = cross(sub(b, a), sub(c, a))
    tri.append(n)
    for v in f:
        s = sums.setdefault((panels[fi], v), [0.0, 0.0, 0.0])
        for i in range(3): s[i] += n[i]
devs = []
kept_flat = 0
for fi, f in enumerate(F):
    n = tri[fi]; ln = norm(n); u = [x/ln for x in n]
    for v in f:
        s = sums[(panels[fi], v)]; ls = norm(s); w = [x/ls for x in s]
        c = sum(u[i]*w[i] for i in range(3))
        if c <= 0: kept_flat += 1; continue
        devs.append(math.degrees(math.acos(max(-1, min(1, c)))))
devs.sort()
q = lambda p: devs[min(len(devs)-1, int(p*len(devs)))]
print('corners', 3*len(F), 'kept flat (average behind)', kept_flat)
print('deviation deg: median %.1f p90 %.1f p99 %.1f max %.1f' % (q(0.5), q(0.9), q(0.99), devs[-1]))
for t in (30, 45, 60, 75):
    print('corners deviating more than %d deg: %d' % (t, sum(1 for x in devs if x > t)))
