"""For each run: the most open state reached within a strain budget.

python budget.py LIMIT {both|tension} run1 run2 ...
(both: stretch and edge error both within LIMIT; tension: stretch only, so the
 tension-field core may gather slack)
A state is within budget when its largest principal stretch (tension) and
its largest relative edge error are both <= LIMIT, and it has no torn-mesh
crossing. Compression is reported, not budgeted (see the report).
"""
import sys, json
from crane import EXP

base = json.load(open(f'{EXP}/out/baselines.json'))
s0 = base['study spread-0']
lim = float(sys.argv[1])
tension_only = sys.argv[2] == 'tension'
runs = sys.argv[3:]
print(f'| run | last s within {lim:.0%} | open med (x s0) | depth (x s0) | tips | stretch % | edge % | core compress % | weld gap / side |')
print('|---|---|---|---|---|---|---|---|---|')
for r in runs:
    try:
        log = json.load(open(f'{EXP}/out/{r}.json'))['log']
    except FileNotFoundError:
        continue
    ok = [m for m in log if m['stretch_max'] <= lim and (tension_only or m['edge_err_max'] <= lim) and m['crossings_torn'] == 0]
    if not ok:
        print(f'| {r} | none | | | | | | | |'); continue
    m = max(ok, key=lambda m: m['body_depth'])
    print(f"| {r} | {m['s']:.1f} | {m['body_open_med']:.4f} ({m['body_open_med']/s0['body_open_med']:.0%}) | "
          f"{m['body_depth']:.4f} ({m['body_depth']/s0['body_depth']:.0%}) | {m['wing_tip_sep']:.3f} | "
          f"{100*m['stretch_max']:.1f} | {100*m['edge_err_max']:.1f} | {100*m.get('compress_max_core', 0):.1f} | {m['weld_gap_max']:.1e} |")
