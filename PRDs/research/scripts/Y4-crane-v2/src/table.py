"""Markdown table of runs at chosen load steps, as fractions of spread-0.

python table.py STEP run1 run2 ...   (STEP = index into the log, -1 = last)
"""
import sys, json
from crane import EXP

base = json.load(open(f'{EXP}/out/baselines.json'))
s0 = base['study spread-0']
k = int(sys.argv[1])
print('| run | s | open med (x s0) | depth (x s0) | tips | edge err % | stretch % (core / rest) | compress % (core / rest) | weld gap max | min dist | torn crossings | ccd-lim / iters | s/step |')
print('|---|---|---|---|---|---|---|---|---|---|---|---|---|')
for r in sys.argv[2:]:
    try:
        log = json.load(open(f'{EXP}/out/{r}.json'))['log']
    except FileNotFoundError:
        continue
    m = log[k] if abs(k) <= len(log) - (0 if k < 0 else 1) else log[-1]
    print(f"| {r} | {m['s']:.1f} | {m['body_open_med']:.4f} ({m['body_open_med']/s0['body_open_med']:.0%}) | "
          f"{m['body_depth']:.4f} ({m['body_depth']/s0['body_depth']:.0%}) | {m['wing_tip_sep']:.3f} | {100*m['edge_err_max']:.1f} | "
          f"{100*m.get('stretch_max_core', 0):.1f} / {100*m.get('stretch_max_noncore', 0):.1f} | "
          f"{100*m.get('compress_max_core', 0):.1f} / {100*m.get('compress_max_noncore', 0):.1f} | {m['weld_gap_max']:.2e} | "
          f"{m['min_dist_torn']:.1e} | {m['crossings_torn']} | {m.get('ccd_limited', '-')}/{m.get('iters', '-')} | {m.get('seconds', 0):.0f} |")
