"""Opening with the Y4 ingredients.

python -u run_open2.py TORN START.npy OUTNAME '{json config}'

Loads (all ramped with the load parameter s = k/N):
  wing grips   (always) torn copies whose CLOSED position is within r of
               (1, root_y) -- mid-wing near the root, X3's "root" grips --
               moved by a scaled rigid (Kabsch) motion to spread-0.
  mouth grips  (mouth=true) all copies of the four boundary midpoints
               (material vertices 20, 1, 55, 28), moved linearly toward
               their spread-0 positions: the underside opened into an X.
  volume floor (k_v > 0) V_core >= V*(s) = V_start + s (vol_frac * V_spread0 - V_start).
  tension field on the core (tf_core=true), set in Sim2.
"""
import sys, json, time
import numpy as np
from sim2 import Sim2
from metrics2 import measure
from crane import EXP, load, write_obj

torn, start, out = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = dict(r=0.08, root_y=0.2, steps=10, iters=40, k_m=1e5, k_b=1e-2, k_c=1e-3, k_w=1e4, k_g=1e3,
           dhat=1e-3, kappa=1e7, dmin=1e-3, ccd='ti', k_anchor=0.0,
           mouth=False, k_v=0.0, vol_frac=1.0, tf_core=False, k_t=1e5, tf_comp=1e-3, wings=True)
if len(sys.argv) > 4:
    cfg.update(json.loads(sys.argv[4]))
d = dict(np.load(f'{EXP}/{torn}.npz'))
reg = json.load(open(f'{EXP}/out/{cfg.get("regions", "regions")}.json'))
S = Sim2(d, cfg, reg)
V = np.load(start)
Vstart = V.copy()
Wstart = S.A @ V
Xc = d['X']
tgt_pose = load('spread-0')['X']
if len(d['M']) > len(tgt_pose):
    # refined mesh: extend spread-0 to the new midpoints (average of the ends)
    R = json.load(open(f'{EXP}/out/refined.json'))
    ext = np.zeros((len(d['M']), 3)); ext[:len(tgt_pose)] = tgt_pose
    for k, v in R['mid'].items():
        a, b = map(int, k.split(','))
        ext[v] = (tgt_pose[a] + tgt_pose[b]) / 2
    tgt_pose = ext
centre = np.array([1.0, cfg['root_y']])
pos = Xc[S.mat, :2]
near = (np.linalg.norm(pos - centre, axis=1) < cfg['r']) & (S.mat < 237)   # original vertices only
sideA = S.Mt[:, 0] > S.Mt[:, 1]
grips = [np.nonzero(near & sideA)[0], np.nonzero(near & ~sideA)[0]] if cfg['wings'] else []
print('wing grip copies', [len(g) for g in grips], 'material', [len(set(S.mat[g])) for g in grips])


def kabsch(P, Q):
    cp, cq = P.mean(0), Q.mean(0)
    Hm = (P - cp).T @ (Q - cq)
    U, _, Vt = np.linalg.svd(Hm)
    dd = np.sign(np.linalg.det(Vt.T @ U.T))
    return Vt.T @ np.diag([1, 1, dd]) @ U.T, cp, cq


def rot_power(R, s):
    ang = np.arccos(np.clip((np.trace(R) - 1) / 2, -1, 1))
    if ang < 1e-12:
        return np.eye(3)
    w = np.array([R[2, 1] - R[1, 2], R[0, 2] - R[2, 0], R[1, 0] - R[0, 1]]) / (2 * np.sin(ang))
    K = np.array([[0, -w[2], w[1]], [w[2], 0, -w[0]], [-w[1], w[0], 0]])
    a = s * ang
    return np.eye(3) + np.sin(a) * K + (1 - np.cos(a)) * K @ K


fits = [kabsch(V[g], tgt_pose[S.mat[g]]) for g in grips]
pts = ([20, 1, 55, 28] if cfg['mouth'] else []) + ([24] if cfg.get('back') else []) + ([0, 57] if cfg.get('necktail') else [])
# back=true: the paper's centre (material (0.5,0.5), the top of the body's back
# in the closed crane) is pressed toward its spread-0 position, a thumb on the back.
# necktail=true: the neck and tail tips (material (0,0), (1,1)) follow spread-0 too.
mouth_idx = np.nonzero(np.isin(S.mat, pts))[0] if pts else np.zeros(0, int)
if pts:
    print('point grip copies', len(mouth_idx), 'material', pts)
v_start = S.core_volume(Wstart, False)[0]
v_s0 = S.core_volume(tgt_pose, False)[0]
v_goal = cfg['vol_frac'] * v_s0
print(f'core volume start {v_start:.3e}, spread-0 {v_s0:.3e}, goal {v_goal:.3e}')
S.grip_idx = np.concatenate(grips + [mouth_idx]).astype(int)
# point grips (mouth/back/neck-tail) may be stiffer than the wing grips: k_p / k_g
S.grip_w = np.r_[np.ones(sum(len(g) for g in grips)), np.full(len(mouth_idx), cfg.get('k_p', cfg['k_g']) / cfg['k_g'])]


def targets(s):
    tg = []
    for g, (R, cp, cq) in zip(grips, fits):
        tg.append((Vstart[g] - cp) @ rot_power(R, s).T + cp + s * (cq - cp))
    if len(mouth_idx):
        m = S.mat[mouth_idx]
        tg.append(Vstart[mouth_idx] + s * (tgt_pose[m] - Wstart[m]))
    return np.concatenate(tg) if tg else np.zeros((0, 3))


if cfg.get('settle', 0):
    # hold every grip at its start and let the stitch settle at this run's k_w
    S.grip_tgt = targets(0.0)
    V, info = S.solve(V, max_iter=cfg['settle'], tol=1e-9)
    print(f'settle: it {info["iters"]} {info["seconds"]:.1f}s ccd-lim {info["ccd_limited"]}', flush=True)
log = []
m, W = measure(V, S, d)
log.append(dict(step=0, s=0.0, **m))
print('step 0', json.dumps(m), flush=True)
np.save(f'{EXP}/out/{out}-step00.npy', V)
T0 = time.time()
N = cfg['steps']
ks = list(range(1, N + 1))
if 'resume' in cfg:
    # convergence check: continue a saved state at one load step for more rounds
    V = np.load(cfg['resume'])
    ks = [cfg['resume_step']] * cfg['rounds']
if cfg.get('hold', 0):
    ks += [N] * cfg['hold']
for k in ks:
    s = k / N
    S.grip_tgt = targets(s)
    S.Vstar = v_start + s * (v_goal - v_start) if cfg['k_v'] > 0 else 0.0
    V, info = S.solve(V, max_iter=cfg['iters'], tol=1e-9)
    m, W = measure(V, S, d)
    gerr = float(np.linalg.norm(V[S.grip_idx] - S.grip_tgt, axis=1).max()) if len(S.grip_idx) else 0.0
    rec = dict(step=k, s=s, grip_err=gerr, vstar=S.Vstar, iters=info['iters'], seconds=info['seconds'],
               ccd_limited=info['ccd_limited'], backtracks=info['backtracks'], grad_inf=info['grad_inf'],
               last_step=info['last_step'], parts=info['parts'], **m)
    log.append(rec)
    print(f'step {k} s={s:.2f}: it {info["iters"]} {info["seconds"]:.1f}s ccd-lim {info["ccd_limited"]} '
          f'|g| {info["grad_inf"]:.1e} grip_err {gerr:.1e} V*={S.Vstar:.2e} ', json.dumps({a: round(b, 5) if isinstance(b, float) else b for a, b in m.items()}), flush=True)
    np.save(f'{EXP}/out/{out}-step{len(log)-1:02d}.npy', V)
    json.dump(dict(cfg=cfg, log=log), open(f'{EXP}/out/{out}.json', 'w'), indent=1, default=float)
write_obj(f'{EXP}/out/{out}-final.obj', W, d['F'], d['M'])
print(f'total {time.time()-T0:.1f}s')
