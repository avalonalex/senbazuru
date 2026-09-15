import math
from collections import deque

def matmul(A, B):
    return [[sum(A[i][k]*B[k][j] for k in range(4)) for j in range(4)] for i in range(4)]

def eye():
    return [[1.0 if i == j else 0.0 for j in range(4)] for i in range(4)]

def rot(p, axis, deg):
    n = math.sqrt(sum(c*c for c in axis)); a = [c/n for c in axis]
    t = math.radians(deg); c, s = math.cos(t), math.sin(t)
    x, y, z = a
    R = [[c+x*x*(1-c), x*y*(1-c)-z*s, x*z*(1-c)+y*s],
         [y*x*(1-c)+z*s, c+y*y*(1-c), y*z*(1-c)-x*s],
         [z*x*(1-c)-y*s, z*y*(1-c)+x*s, c+z*z*(1-c)]]
    M = eye()
    for i in range(3):
        for j in range(3): M[i][j] = R[i][j]
        M[i][3] = p[i] - sum(R[i][j]*p[j] for j in range(3))
    return M

def area(poly):
    return 0.5*sum(poly[i][0]*poly[(i+1)%len(poly)][1]-poly[(i+1)%len(poly)][0]*poly[i][1] for i in range(len(poly)))

def fold(V, E, angles, F, root=0):
    V3 = [[x, y, 0.0] for x, y in V]
    F = [list(f) if area([V[i] for i in f]) > 0 else list(reversed(f)) for f in F]
    ekey = {frozenset((a, b)): i for i, (a, b) in enumerate(E)}
    adj = {}
    for fi, f in enumerate(F):
        for k in range(len(f)):
            a, b = f[k], f[(k+1) % len(f)]
            adj.setdefault(frozenset((a, b)), []).append(fi)
    T = {root: eye()}
    q = deque([root])
    while q:
        fi = q.popleft(); f = F[fi]
        for k in range(len(f)):
            a, b = f[k], f[(k+1) % len(f)]
            key = frozenset((a, b)); ang = angles[ekey[key]]
            for fj in adj[key]:
                if fj != fi and fj not in T:
                    R = rot(V3[a], [V3[b][i]-V3[a][i] for i in range(3)], -ang)
                    T[fj] = matmul(T[fi], R)
                    q.append(fj)
    return F, T

def apply(M, p):
    q = [p[0], p[1], p[2] if len(p) > 2 else 0.0, 1.0]
    return [sum(M[i][j]*q[j] for j in range(4)) for i in range(3)]

def normalz(M):
    return M[2][2]

def r(v, n=4):
    return [round(x, n) + 0.0 for x in v]
