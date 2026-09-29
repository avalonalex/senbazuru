#!/bin/sh
# summarise run logs: summ.sh RUN...
Y=/private/tmp/claude-501/-Users-yuhanhao-Project-senbazuru/a9814e9f-3bd8-46c3-897f-77c8e8d977fa/scratchpad/experiments/Y4-crane-v2
for f in "$@"; do echo "== $f"; grep -v "^    it" $Y/out/$f.log | $Y/venv/bin/python -c "
import sys,json
for l in sys.stdin:
    if '{' in l and ('step' in l or 'k_w' in l):
        h,j=l.split('{',1); m=json.loads('{'+j)
        keys=['body_open_med','body_depth','wing_tip_sep','edge_err_max','stretch_max','compress_max','weld_gap_max','core_volume','min_dist_torn','crossings_torn']
        print(h[:62].strip(), ' '.join(f'{k[:9]}={m[k]:.4g}' for k in keys if k in m))
    elif 'EXIT' in l or 'Error' in l or 'total' in l: print(l.strip())
"; done
