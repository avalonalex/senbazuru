import os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))  # repository root
import json, math
d = json.load(open(os.path.join(ROOT, 'examples/bird-base.fold')))
V = d['vertices_coords']; E = d['edges_vertices']; A = d['edges_assignment']
def segdist(p, a, b):
    ax, ay = a; bx, by = b; px, py = p
    dx, dy = bx-ax, by-ay; L = dx*dx+dy*dy
    t = max(0, min(1, ((px-ax)*dx+(py-ay)*dy)/L))
    return math.hypot(ax+t*dx-px, ay+t*dy-py)
p = (0.58, 0.4)
print('anchor nearest edges', sorted((round(segdist(p, V[a], V[b]), 5), i, A[i], (a, b)) for i, (a, b) in enumerate(E))[:4])
# triangle v8 v9 v10 containment via barycentric
def bary(p, a, b, c):
    det = (b[1]-c[1])*(a[0]-c[0]) + (c[0]-b[0])*(a[1]-c[1])
    l1 = ((b[1]-c[1])*(p[0]-c[0]) + (c[0]-b[0])*(p[1]-c[1]))/det
    l2 = ((c[1]-a[1])*(p[0]-c[0]) + (a[0]-c[0])*(p[1]-c[1]))/det
    return l1, l2, 1-l1-l2
print('barycentric in (v8,v9,v10)', bary(p, V[8], V[9], V[10]))
print('centre vertex v8', V[8])
# which vertices lie at the petal tips
print('hinge 26', E[26], [V[v] for v in E[26]], 'hinge 27', E[27], [V[v] for v in E[27]])
for h in (26, 27):
    P, Q = E[h]
    nP = {b if a == P else a for a, b in E if P in (a, b)}
    nQ = {b if a == Q else a for a, b in E if Q in (a, b)}
    corners = [v for v in nP & nQ if v < 4]
    print('hinge', h, 'shared corner neighbours', corners, [V[v] for v in corners])
