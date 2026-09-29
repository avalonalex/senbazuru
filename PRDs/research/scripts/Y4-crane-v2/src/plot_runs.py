"""Per-step curves for every run: body opening (mirror median, and the
study's body depth) against load s, with edge error and stretch.

python plot_runs.py OUT.png run1:label1 run2:label2 ...
"""
import sys, json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from crane import EXP

base = json.load(open(f'{EXP}/out/baselines.json'))
s0 = base['study spread-0']
out = sys.argv[1]
runs = [a.split(':', 1) for a in sys.argv[2:]]
fig, ax = plt.subplots(1, 5, figsize=(22, 4.6))
colors = plt.cm.tab20(np.linspace(0, 1, 20))
for ci, (name, label) in enumerate(runs):
    kw = dict(marker='o', ms=3, label=label, color=colors[(2 * ci) % 20 if ci < 10 else (2 * ci + 1) % 20])
    log = json.load(open(f'{EXP}/out/{name}.json'))['log']
    s = [r['s'] + (0.02 * i if r['step'] == log[-1]['step'] and i >= len(log) - 1 and False else 0) for i, r in enumerate(log)]
    x = list(range(len(log)))
    ax[0].plot(x, [r['body_open_med'] / s0['body_open_med'] for r in log], **kw)
    ax[1].plot(x, [r['body_depth'] / s0['body_depth'] for r in log], **kw)
    ax[2].plot(x, [100 * r['edge_err_max'] for r in log], **kw)
    ax[3].plot(x, [100 * r['stretch_max'] for r in log], **kw)
    ax[4].plot(x, [100 * r.get('compress_max_core', 0) for r in log], **kw)
ax[0].set_title('body opening (mirror median) / spread-0')
ax[1].set_title('body depth (core z-range) / spread-0')
ax[2].set_title('max edge error, %')
ax[3].set_title('max principal stretch (tension), %')
ax[4].set_title('max compression in the body core, %')
ax[0].axhline(0.40, color='grey', ls='--', lw=1); ax[0].text(0.2, 0.41, 'X3 best', fontsize=7, color='grey')
ax[1].axhline(0.52, color='grey', ls='--', lw=1); ax[1].text(0.2, 0.53, 'X3 best', fontsize=7, color='grey')
for a in ax:
    a.set_xlabel('load step (s = step/10; >10 = extra holds)')
    a.grid(alpha=0.3)
ax[0].axhline(0.7, color='k', ls=':', lw=1)
ax[1].axhline(0.7, color='k', ls=':', lw=1)
ax[2].axhline(3, color='k', ls=':', lw=1)
ax[3].axhline(3, color='k', ls=':', lw=1)
ax[0].legend(fontsize=7, loc='upper left')
fig.tight_layout()
fig.savefig(out, dpi=110)
print(out)
