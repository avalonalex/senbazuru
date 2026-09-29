"""Configs for the smoothing renders: S1 display mesh, unsmoothed vs Catmull-Clark
(Blender subsurf level 2, crease 1.0 on M/V/F/B copies) vs own Phong (npz)."""
import json, math
Y = '/private/tmp/claude-501/-Users-yuhanhao-Project-senbazuru/a9814e9f-3bd8-46c3-897f-77c8e8d977fa/scratchpad/experiments/Y1-valid-looks'
G = '/private/tmp/claude-501/-Users-yuhanhao-Project-senbazuru/a9814e9f-3bd8-46c3-897f-77c8e8d977fa/scratchpad/gallery/whole-crane'
S = Y + '/spread/crane-spreading'
T = 0.1 / 150
frame = [G + '/before.fold', G + '/spread-0.fold']
cams = {'upright': dict(forward=[1, math.sqrt(2), -1], up=[0, -1, 0]),
        'oblique': dict(forward=[-1, 1, math.sqrt(2)], up=[0, 0, 1])}
variants = {
    'curved-cc': dict(fold=S + '/curved.fold', subsurf=2),
    'curved-phong': dict(fold=Y + '/meshes/curved-s1-phong.npz'),
    'before-cc': dict(fold=G + '/before.fold', subsurf=2),
    'fine-cc': dict(fold=S + '/fine.fold', subsurf=2),
}
for v, extra in variants.items():
    for cam, cv in cams.items():
        n = f'{v}-{cam}'
        base = dict(axes='crane', frame_with=frame, **cv, **extra)
        c = dict(base, treatment='paper', thickness=T, gap=1.1 * T, samples=128, exposure=-1.0,
                 out=f'{Y}/renders/{n}-paper.png', timing_out=f'{Y}/logs/{n}-paper.json')
        if extra['fold'].endswith('.npz'):
            c['thickness'] = 0.0   # the npz already carries the 1.1 t layer separation
        json.dump(c, open(f'{Y}/configs/{n}-paper.json', 'w'), indent=1)
        la = dict(base, treatment='paper', thickness=0, gap=1.1 * T, samples=1, out='/dev/null',
                  svg_out=f'{Y}/svg/{n}-lineart.svg', intersections=True, no_render=True,
                  bridge_folds=False, timing_out=f'{Y}/logs/{n}-lineart.json')
        json.dump(la, open(f'{Y}/configs/{n}-lineart.json', 'w'), indent=1)
print('ok')
