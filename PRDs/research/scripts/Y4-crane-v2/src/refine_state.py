"""Carry a torn state of the 448-triangle mesh onto the refined mesh.

python refine_state.py TORN_OLD TORN_REF STATE.npy OUT.npy
Subdivision does not move the surface: an old vertex copy keeps its
position, and a midpoint copy is the average of its edge's two end copies
in the same piece. So distances, crossings and strains are unchanged.
"""
import sys, json
import numpy as np
from crane import EXP

old = dict(np.load(f'{EXP}/{sys.argv[1]}.npz'))
ref = dict(np.load(f'{EXP}/{sys.argv[2]}.npz'))
V = np.load(sys.argv[3])
R = json.load(open(f'{EXP}/out/refined.json'))
parent = np.array(R['parent'])
mid = {v: tuple(map(int, k.split(','))) for k, v in R['mid'].items()}
# piece of each face
pf_old = old['piece'][old['T'][:, 0]]
pf_ref = ref['piece'][ref['T'][:, 0]]
pmap = {}
for i, pf in enumerate(parent):
    a, b = pf_ref[i], pf_old[pf]
    assert pmap.get(a, b) == b
    pmap[a] = b
copy_old = {(int(m), int(p)): i for i, (m, p) in enumerate(zip(old['mat'], old['piece']))}
Vn = np.zeros((len(ref['mat']), 3))
for i, (m, p) in enumerate(zip(ref['mat'], ref['piece'])):
    po = pmap[int(p)]
    if m in mid:
        a, b = mid[int(m)]
        Vn[i] = (V[copy_old[(a, po)]] + V[copy_old[(b, po)]]) / 2
    else:
        Vn[i] = V[copy_old[(int(m), po)]]
np.save(sys.argv[4], Vn)
print('refined state', Vn.shape)
