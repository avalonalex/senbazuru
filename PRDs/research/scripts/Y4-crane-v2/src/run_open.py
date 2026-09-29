"""Opening phase: move two wing grips from the stitched closed crane towards
the study's spread-0 wing pose in N load steps, IPC contact throughout.

python -u run_open.py START.npy OUTNAME '{"grip":"tip","steps":10,...}'

grip = "tip":  torn copies whose CLOSED-crane position is within r of the
               wing tip point (1, 0) -- both wings' tips coincide there --
               split into the two wings by material side (m_x > m_y is the
               wing of corner (1,0)).
grip = "root": copies within r of a point halfway between tip and the body
               spine, i.e. nearer the body (Tamaki's hand position), same split.
Targets: best rigid transform (Kabsch) taking each grip patch from its start
positions to the spread-0 positions of the same material vertices; the
rotation angle and translation are scaled by s = k/N at load step k.
"""
import sys, json, time
import numpy as np
import ipctk
from sim import Sim
from metrics import measure
from crane import EXP, load, write_obj

start = sys.argv[1]
out = sys.argv[2]
cfg = dict(grip='tip', r=0.08, steps=10, iters=40, k_m=1e5, k_b=1e-2, k_c=1e-3, k_w=1e4, k_g=1e3,
           dhat=1e-4, kappa=1e11, k_anchor=0.0, pressure=0.0)
if len(sys.argv) > 3:
    cfg.update(json.loads(sys.argv[3]))
d = dict(np.load(f'{EXP}/torn.npz'))
S = Sim(d, cfg)
V = np.load(start)
Vstart = V.copy()
Xc = d['X']                       # closed crane (welded, flat)
Mt = S.Mt
tgt_pose = load('spread-0')['X']
if cfg['grip'] == 'tip':
    centre = np.array([1.0, 0.0])
else:
    centre = np.array([1.0, cfg.get('root_y', 0.2)])
pos = Xc[S.mat, :2]
near = np.linalg.norm(pos - centre, axis=1) < cfg['r']
sideA = Mt[:, 0] > Mt[:, 1]
grips = [np.nonzero(near & sideA)[0], np.nonzero(near & ~sideA)[0]]
print('grip copies per wing', [len(g) for g in grips],
      'material vertices', [len(set(S.mat[g])) for g in grips])


def kabsch(P, Q):
    cp, cq = P.mean(0), Q.mean(0)
    Hm = (P - cp).T @ (Q - cq)
    U, _, Vt = np.linalg.svd(Hm)
    dd = np.sign(np.linalg.det(Vt.T @ U.T))
    R = Vt.T @ np.diag([1, 1, dd]) @ U.T
    return R, cp, cq


def rot_power(R, s):
    # axis-angle scaling
    ang = np.arccos(np.clip((np.trace(R) - 1) / 2, -1, 1))
    if ang < 1e-12:
        return np.eye(3)
    w = np.array([R[2, 1] - R[1, 2], R[0, 2] - R[2, 0], R[1, 0] - R[0, 1]]) / (2 * np.sin(ang))
    K = np.array([[0, -w[2], w[1]], [w[2], 0, -w[0]], [-w[1], w[0], 0]])
    a = s * ang
    return np.eye(3) + np.sin(a) * K + (1 - np.cos(a)) * K @ K


fits = []
for g in grips:
    P = V[g]; Q = tgt_pose[S.mat[g]]
    R, cp, cq = kabsch(P, Q)
    res = np.linalg.norm((P - cp) @ R.T + cq - Q, axis=1).max()
    ang = np.degrees(np.arccos(np.clip((np.trace(R) - 1) / 2, -1, 1)))
    print(f'grip fit: rotation {ang:.1f} deg, translation {np.linalg.norm(cq-cp):.3f}, fit residual {res:.4f}')
    fits.append((R, cp, cq))

S.grip_idx = np.concatenate(grips)
log = []
m, W = measure(V, S, d)
log.append(dict(step=0, s=0.0, **m))
print('step 0', json.dumps(m), flush=True)
write_obj(f'{EXP}/{out}-step00.obj', W, d['F'], d['M'])
np.save(f'{EXP}/{out}-step00.npy', V)
T0 = time.time()
N = cfg['steps']
ks = range(1, N + 1)
if 'resume' in cfg:          # convergence check: hold one step's targets, iterate more
    V = np.load(cfg['resume']); ks = [cfg['resume_step']] * cfg['rounds']
for k in ks:
    s = k / N
    tg = []
    for g, (R, cp, cq) in zip(grips, fits):
        Rs = rot_power(R, s)
        tg.append((Vstart[g] - cp) @ Rs.T + cp + s * (cq - cp))
    S.grip_tgt = np.concatenate(tg)
    V, info = S.solve(V, max_iter=cfg['iters'], tol=1e-9)
    m, W = measure(V, S, d)
    gerr = float(np.linalg.norm(V[S.grip_idx] - S.grip_tgt, axis=1).max())
    rec = dict(step=k, s=s, grip_err=gerr, iters=info['iters'], seconds=info['seconds'],
               ccd_limited=info['ccd_limited'], backtracks=info['backtracks'], grad_inf=info['grad_inf'],
               last_step=info['last_step'], parts=info['parts'], **m)
    log.append(rec)
    print(f'step {k} s={s:.2f}: iters {info["iters"]} {info["seconds"]:.1f}s ccd-lim {info["ccd_limited"]} '
          f'|g| {info["grad_inf"]:.2e} last {info["last_step"]:.1e} grip_err {gerr:.2e}', json.dumps(m), flush=True)
    write_obj(f'{EXP}/{out}-step{k:02d}.obj', W, d['F'], d['M'])
    np.save(f'{EXP}/{out}-step{k:02d}.npy', V)
    json.dump(dict(cfg=cfg, log=log), open(f'{EXP}/{out}.json', 'w'), indent=1, default=float)
print(f'total {time.time()-T0:.1f}s')
