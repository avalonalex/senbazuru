import sys; sys.path.insert(0, 'src')
import numpy as np, mesh, solve
m = mesh.load_fold('../../gallery/whole-crane/spread-0.fold')
rng = np.random.default_rng(0)
tgt = m['X'] + 0.01 * rng.standard_normal(m['X'].shape)
r_, u_, f_ = mesh.upright_basis()
for plane, mem in ((None, "green"), ((r_, u_), "green"), (None, "edge")):
    pr = solve.Problem(m, tgt, lam=0.3, kb=0.01, plane=plane, membrane=mem)
    x = m['X'].ravel() + 0.003 * rng.standard_normal(m['X'].size)
    r, J = pr.residual(x)
    v = rng.standard_normal(x.size)
    h = 1e-6
    fd = (pr.residual(x + h * v, jac=False) - pr.residual(x - h * v, jac=False)) / (2 * h)
    an = J @ v
    print('plane' if plane else '3d', 'residuals', len(r), 'rel err', np.linalg.norm(fd - an) / np.linalg.norm(an))
