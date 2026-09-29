import sys, collections, numpy as np
sys.path.insert(0, sys.argv[1])
import foldlayers as fl
for p in sys.argv[2:]:
    d, V, F = fl.load(p)
    s = fl.stacks(d, V, F)
    ea = collections.Counter(d['edges_assignment'])
    print(p.split('/')[-1], 'V', len(V), 'F', len(F), 'E', len(d['edges_vertices']), dict(ea),
          'zrange', np.ptp(V[:, 2]).round(4), 'bbox', V.min(0).round(3), V.max(0).round(3))
    print('   orders', s['n_orders'], 'coincident', s['n_coincident'], 'clusters', s['n_clusters'],
          'faces in stacks', s['faces_in_stacks'], 'max height', s['max_height'], 'cyclic clusters', s['cycles'])
    if 'senbazuru:source_panels' in d:
        sp = d['senbazuru:source_panels']
        # map edges to adjacent faces
        ef = collections.defaultdict(list)
        for fi, f in enumerate(F):
            for i in range(len(f)):
                ef[frozenset((f[i], f[(i + 1) % len(f)]))].append(fi)
        c = collections.Counter()
        for ei, (a, b) in enumerate(d['edges_vertices']):
            fs = ef[frozenset((a, b))]
            same = len(fs) == 2 and sp[fs[0]] == sp[fs[1]]
            c[(d['edges_assignment'][ei], 'samePanel' if same else ('boundary' if len(fs) < 2 else 'diffPanel'))] += 1
        print('   assignment vs panel:', dict(c), 'panels', len(set(sp)))
