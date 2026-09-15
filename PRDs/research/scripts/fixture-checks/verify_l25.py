import os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))  # repository root
import json, math
d = json.load(open(os.path.join(ROOT, 'examples/crane.fold')))
V = d['vertices_coords']; F = d['faces_vertices']
def segdist(p, a, b):
    ax, ay = a; bx, by = b; px, py = p
    dx, dy = bx-ax, by-ay
    t = max(0, min(1, ((px-ax)*dx + (py-ay)*dy)/(dx*dx+dy*dy)))
    return math.hypot(px-ax-t*dx, py-ay-t*dy)
def winding(p, ring):
    # nonzero winding number
    w = 0
    for i in range(len(ring)):
        a = V[ring[i]]; b = V[ring[(i+1) % len(ring)]]
        if a[1] <= p[1]:
            if b[1] > p[1] and (b[0]-a[0])*(p[1]-a[1]) - (p[0]-a[0])*(b[1]-a[1]) > 0: w += 1
        else:
            if b[1] <= p[1] and (b[0]-a[0])*(p[1]-a[1]) - (p[0]-a[0])*(b[1]-a[1]) < 0: w -= 1
    return w
for p in [(0.5, 0.5), (19/20, 1/3)]:
    inside = [i for i, r in enumerate(F) if winding(p, r) != 0]
    print(p, 'inside faces', inside)
    for i in inside:
        r = F[i]
        ds = [segdist(p, V[r[k]], V[r[(k+1)%len(r)]]) for k in range(len(r))]
        print('  face', i, 'ring', r, 'edge distances', [round(x, 5) for x in ds])
    nv = min(range(len(V)), key=lambda k: math.hypot(V[k][0]-p[0], V[k][1]-p[1]))
    print('  nearest vertex', nv, math.hypot(V[nv][0]-p[0], V[nv][1]-p[1]))
    # min distance to any edge in the pattern
    E = d['edges_vertices']
    md = min((segdist(p, V[a], V[b]), i) for i, (a, b) in enumerate(E))
    print('  nearest edge', md)
# faces touching vertex 24
print('faces with vertex 24', [i for i, r in enumerate(F) if 24 in r])
r0 = F[0]
xs = [V[k][0] for k in r0]; ys = [V[k][1] for k in r0]
print('face0 ring', r0, 'x', min(xs), max(xs), 'y', min(ys), max(ys))
# face 0 area sign
A = sum(V[r0[i]][0]*V[r0[(i+1)%4]][1] - V[r0[(i+1)%4]][0]*V[r0[i]][1] for i in range(4))/2
print('face0 signed area', A)
# distance from (0.5,0.5) to face 0 polygon
p=(0.5,0.5)
print('dist (0.5,0.5) to face 0 boundary', min(segdist(p, V[r0[k]], V[r0[(k+1)%4]]) for k in range(4)))
# total area check of faces
tot = 0
for r in F:
    tot += abs(sum(V[r[i]][0]*V[r[(i+1)%len(r)]][1] - V[r[(i+1)%len(r)]][0]*V[r[i]][1] for i in range(len(r)))/2)
print('sum |face areas|', tot)
