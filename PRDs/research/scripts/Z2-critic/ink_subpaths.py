# Ink length per stroke width, split at each M (moveto) so jumps between
# subpaths are not counted; Z closes a subpath back to its start.
# Normalised by the bounding-box diagonal of all path points, as H1's ink.py.
import re, math, sys
def run(fn):
    s = open(fn).read(); xs = []; ys = []; by = {}
    for m in re.finditer(r'<(path|polyline)\b([^>]*)>', s):
        a = m.group(2)
        dm = re.search(r'\bd="([^"]*)"', a) or re.search(r'points="([^"]*)"', a)
        if not dm: continue
        filled = re.search(r'fill="(?!none)', a)
        w = re.search(r'stroke-width="([^"]*)"', a)
        stroked = ('stroke=' in a and 'stroke="none"' not in a) or (w is not None)
        toks = re.findall(r'[MLZmlz]|-?\d+\.?\d*(?:e-?\d+)?', dm.group(1))
        L = 0.0; cur = None; start = None; nums = []; cmd = 'M'
        def flush():
            nonlocal cur, start, L
        i = 0
        while i < len(toks):
            t = toks[i]
            if t in 'MLZmlz':
                cmd = t.upper(); i += 1
                if cmd == 'Z':
                    if cur and start: L += math.dist(cur, start); cur = start
                continue
            p = (float(toks[i]), float(toks[i + 1])); i += 2
            xs.append(p[0]); ys.append(p[1])
            if cmd == 'M': cur = p; start = p; cmd = 'L'
            else:
                if cur is not None: L += math.dist(cur, p)
                cur = p
        if stroked and not filled:
            k = w.group(1) if w else 'unset'
            by[k] = by.get(k, 0) + L
    diag = math.hypot(max(xs) - min(xs), max(ys) - min(ys))
    parts = ', '.join('%s: %.1f' % (k, v / diag) for k, v in sorted(by.items()))
    print('%-40s total %.1f  (%s)' % (fn.split('/')[-1], sum(by.values()) / diag, parts))
for fn in sys.argv[1:]: run(fn)
