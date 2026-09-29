import json, sys, math
X='/private/tmp/claude-501/-Users-yuhanhao-Project-senbazuru/a9814e9f-3bd8-46c3-897f-77c8e8d977fa/scratchpad/experiments/X1-render'; G='/private/tmp/claude-501/-Users-yuhanhao-Project-senbazuru/a9814e9f-3bd8-46c3-897f-77c8e8d977fa/scratchpad/gallery/whole-crane'
T=0.1/150      # 0.1 mm on a 15 cm sheet
crane=dict(axes='crane', forward=[1, math.sqrt(2), -1], up=[0,-1,0], frame_with=[G+'/before.fold', G+'/spread-0.fold'])
twist=dict(axes='zup', forward=[1, 1.4, -1.3], up=[0,0,1], frame_with=['/Users/yuhanhao/Project/senbazuru/examples/squaretwist.fold'])
models={'before':dict(crane, fold=G+'/before.fold'), 'spread0':dict(crane, fold=G+'/spread-0.fold'),
        'craneflat':dict(crane, fold=X+'/inputs/crane-flat.fold'),
        'twist':dict(twist, fold='/Users/yuhanhao/Project/senbazuru/examples/squaretwist.fold')}
def cfg(model, treat, name, **kw):
    c=dict(models[model]); c.update(treatment=treat, thickness=T, gap=1.1*T, samples=128, exposure=-1.0,
      out=f'{X}/renders/{name}.png', timing_out=f'{X}/logs/{name}.json'); c.update(kw)
    if treat=='baseline': c['thickness']=0
    json.dump(c, open(f'{X}/configs/{name}.json','w'), indent=1)
for m in models:
    cfg(m,'baseline',f'{m}-1-baseline')
    cfg(m,'paper',f'{m}-2-paper')
    cfg(m,'lines',f'{m}-3-lines')
for m in ['before','spread0']:
    cfg(m,'paper',f'{m}-2b-paper-nothick', thickness=0)
    cfg(m,'paper',f'{m}-2c-paper-thick04', thickness=0.4/150, gap=1.1*0.4/150)
    cfg(m,'paper',f'{m}-2d-paper-flatnormals', smooth=False)
print('ok')
