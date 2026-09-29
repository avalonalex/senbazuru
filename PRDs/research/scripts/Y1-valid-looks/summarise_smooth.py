"""One table of the smoothing-safety results (out/*-smooth.json)."""
import json, glob
keys = [('source_pairs_newly_crossing_deeper_1e7', 'new X >1e-7'), ('source_pairs_newly_crossing_deeper_t', 'new X >t'),
        ('new_crossing_depth_max_in_t', 'max depth/t'), ('source_pairs_newly_within_t', 'new <t'),
        ('source_pairs_newly_overlapping_coplanar_vs_control', 'new coplanar overlap'),
        ('max_displacement_in_t', 'max move/t'), ('moved_more_than_t_fraction', 'frac moved >t'), ('crack_width_in_t', 'crack/t')]
print('| run | layers | tags | source pairs X>1e-7 | method | sub-tris | ' + ' | '.join(k[1] for k in keys) + ' |')
for f in sorted(glob.glob('out/*-smooth.json')):
    d = json.load(open(f))
    for m in ('catmull_clark', 'phong'):
        r = d[m]
        vals = []
        for k, _ in keys:
            v = r.get(k, 0)
            vals.append(f'{v:.2f}' if isinstance(v, float) else str(v))
        print(f"| {d['name']} | {d['variant'].split(' ')[0]} | {d.get('crease_kinds') or 'MVFB'} | {d['source'].get('crossing_pairs_deeper_1e7')} | {m} | {r['sub_triangles']} | " + ' | '.join(vals) + ' |')
