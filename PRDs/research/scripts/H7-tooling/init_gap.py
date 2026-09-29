import sys, numpy as np, ipctk
src = open('pillow_ipc.py').read().split('# edges and hinges')[0]
for n in (16, 32, 48):
    sys.argv = ['x', str(n)]
    ns = {}
    exec(src, ns)
    X, F = ns['X'], ns['F']
    E = sorted({(min(a, b), max(a, b)) for t in F for a, b in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0]))})
    m = ipctk.CollisionMesh(X, np.array(E, dtype=np.int32), F)
    c = ipctk.NormalCollisions(); c.build(m, X, 0.01, 0.0)
    print(n, 'initial min distance', np.sqrt(c.compute_minimum_distance(m, X)), 'thickness', 1/1500)
