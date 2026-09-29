"""Configs for Y1: valid curved shapes at two matched cameras, paper + Line Art."""
import json, math
Y = '/private/tmp/claude-501/-Users-yuhanhao-Project-senbazuru/a9814e9f-3bd8-46c3-897f-77c8e8d977fa/scratchpad/experiments/Y1-valid-looks'
G = '/private/tmp/claude-501/-Users-yuhanhao-Project-senbazuru/a9814e9f-3bd8-46c3-897f-77c8e8d977fa/scratchpad/gallery/whole-crane'
S = Y + '/spread/crane-spreading'
BODY = '/Users/yuhanhao/Project/senbazuru/study/fold-material/fixtures/whole-crane-body.fold'
T = 0.1 / 150
crane_frame = [G + '/before.fold', G + '/spread-0.fold']
cams = {
    # the whole-crane gallery's "upright" camera (X1 used it) and its "oblique" camera,
    # which is also the crane-spreading study's comparison.svg camera
    'upright': dict(forward=[1, math.sqrt(2), -1], up=[0, -1, 0]),
    'oblique': dict(forward=[-1, 1, math.sqrt(2)], up=[0, 0, 1]),
}
shapes = {
    'rigid': (S + '/rigid.fold', crane_frame),
    'curved': (S + '/curved.fold', crane_frame),
    'fine': (S + '/fine.fold', crane_frame),
    'x3tip05': (Y + '/meshes/x3-open-tip-step05.npz', crane_frame),
    'body': (BODY, [BODY]),
    'before': (G + '/before.fold', crane_frame),
    'spread0': (G + '/spread-0.fold', crane_frame),
}
names = []
for sh, (path, frame) in shapes.items():
    for cam, cv in cams.items():
        base = dict(axes='crane', frame_with=frame, fold=path, **cv)
        n = f'{sh}-{cam}'
        c = dict(base, treatment='paper', thickness=T, gap=1.1 * T, samples=128, exposure=-1.0,
                 out=f'{Y}/renders/{n}-paper.png', timing_out=f'{Y}/logs/{n}-paper.json')
        if path.endswith('.npz'):
            c['thickness'] = 0.0   # torn IPC mesh: layers are already apart by less than t
        json.dump(c, open(f'{Y}/configs/{n}-paper.json', 'w'), indent=1)
        la = dict(base, treatment='paper', thickness=0, gap=1.1 * T, samples=1, out='/dev/null',
                  svg_out=f'{Y}/svg/{n}-lineart.svg', intersections=True, no_render=True,
                  bridge_folds=False, timing_out=f'{Y}/logs/{n}-lineart.json')
        json.dump(la, open(f'{Y}/configs/{n}-lineart.json', 'w'), indent=1)
        lt = dict(la, svg_out=f'{Y}/svg/{n}-lineart-overlay.svg', svg_transparent=True,
                  timing_out=f'{Y}/logs/{n}-lineart-overlay.json')
        json.dump(lt, open(f'{Y}/configs/{n}-lineart-overlay.json', 'w'), indent=1)
        names.append(n)
print(' '.join(names))
