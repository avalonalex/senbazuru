"""Where does an opening run jam? Diagnostics on one saved torn state.

python diag.py TORN STATE.npy '{sim params}'   (prints JSON)

 - weld (stitch) gaps: the largest, with material location and region;
 - pressed contacts: collisions closer than dmin + 0.1*dhat (the layers the
   barrier is holding apart), counted by region pair;
 - the four creases through the paper's centre (the body core's own folds):
   their fold angle, 180 deg = closed as in the flat crane, 0 = flat.
Regions: body core (the 49 study core vertices), else the material quadrant
split by the midlines u = 0.5, v = 0.5, named by its corner:
(1,0) wing A, (0,1) wing B, (0,0) and (1,1) neck/tail.
"""
import sys, json, collections
import numpy as np
import ipctk
from sim2 import Sim2
from sim import dihedral_and_grad
from metrics2 import CORE
from crane import EXP

torn, state = sys.argv[1], sys.argv[2]
p = dict(k_m=1, k_b=1, k_c=1, k_w=1, k_g=1, dhat=1e-3, kappa=1, dmin=1e-3)
if len(sys.argv) > 3:
    p.update(json.loads(sys.argv[3]))
d = dict(np.load(f'{EXP}/{torn}.npz'))
reg = json.load(open(f'{EXP}/out/regions.json'))
S = Sim2(d, p, reg)
V = np.load(state)
M = d['M']
coreset = set(CORE.tolist())


def region(m):
    if m in coreset:
        return 'core'
    u, v = M[m]
    if u >= 0.5 and v < 0.5:
        return 'wingA(1,0)'
    if u < 0.5 and v >= 0.5:
        return 'wingB(0,1)'
    if u < 0.5 and v < 0.5:
        return 'corner(0,0)'
    return 'corner(1,1)'


out = {}
gaps = np.linalg.norm(V[S.W[:, 0]] - V[S.W[:, 1]], axis=1)
top = np.argsort(-gaps)[:12]
out['largest_weld_gaps'] = [dict(gap_over_t=float(gaps[i] / 1e-3), material=[round(x, 3) for x in M[S.mat[S.W[i, 0]]]],
                                 region=region(int(S.mat[S.W[i, 0]]))) for i in top]
byreg = collections.defaultdict(list)
for i, gp in enumerate(gaps):
    byreg[region(int(S.mat[S.W[i, 0]]))].append(gp)
out['weld_gap_by_region_max_over_t'] = {k: float(max(v) / 1e-3) for k, v in byreg.items()}
# pressed contacts
dmin, dhat = S.contact.dmin, S.contact.dhat
if True:
    c = S.contact.candidates(V)
    col = ipctk.NormalCollisions()
    col.build(c, S.contact.mesh, V, 0.1 * dhat, dmin)
    cnt = collections.Counter()
    E = S.contact.E
    for k in range(len(col)):
        cc = col[k]
        ids = cc.vertex_ids(E, S.T)
        ids = [i for i in ids if i >= 0]
        r = sorted(set(region(int(S.mat[i])) for i in ids))
        cnt['/'.join(r)] += 1
    out['pressed_contacts'] = len(col)
    out['pressed_by_region'] = dict(cnt.most_common(12))
# centre creases: hinges whose both ends lie on the lines through the centre, inside the core
H = d['hinges']
th, _ = dihedral_and_grad(V[H[:, 0]], V[H[:, 1]], V[H[:, 2]], V[H[:, 3]])
ang = {}
for k, h in enumerate(H):
    if not h[6]:
        continue
    a, b = h[7], h[8]
    if a in coreset and b in coreset:
        ma, mb = M[a], M[b]
        mid = (ma + mb) / 2
        dirn = (mb - ma) / np.linalg.norm(mb - ma)
        # does the crease line pass through the centre?
        rel = np.array([0.5, 0.5]) - ma
        if abs(rel[0] * dirn[1] - rel[1] * dirn[0]) < 1e-6:
            key = 'diag' if abs(abs(dirn[0]) - abs(dirn[1])) < 1e-6 else 'midline'
            ang.setdefault(key, []).append(float(np.degrees(abs(th[k]))))
out['centre_crease_fold_angle_deg'] = {k: dict(n=len(v), min=min(v), median=float(np.median(v)), max=max(v)) for k, v in ang.items()}
print(json.dumps(out, indent=1))
