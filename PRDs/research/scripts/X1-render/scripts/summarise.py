import json, glob, os, re, statistics, sys
X = sys.argv[1]
rows = []
for p in sorted(glob.glob(X + '/logs/*.log')):
    n = os.path.basename(p)[:-4]
    s = open(p).read()
    m = re.search(r'STATS (\{.*\})', s)
    if not m:
        continue
    st = json.loads(m.group(1))
    rows.append((n, st.get('render_seconds'), st['mesh'], st.get('px_per_sheet_unit')))
times = {}
for n, t, mesh, px in rows:
    base = n.split('-run')[0]
    times.setdefault(base, []).append(t)
for n, t, mesh, px in rows:
    if '-run' in n or t is None: continue
    print(f"{n:32s} {t:7.2f}s  faces {mesh['faces']:4d} verts {mesh['verts_in']}->{mesh['verts_out']} bridges {mesh.get('bridges')} "
          f"stack faces {mesh['stack_faces']} levels {mesh['max_height']+1} depth {mesh.get('stack_depth_sheet_units',0):.4f}  px/unit {px:.0f}")
print()
for k, v in times.items():
    if len(v) >= 3:
        print(k, 'runs', [round(x, 2) for x in v], 'median', round(statistics.median(v), 2))
