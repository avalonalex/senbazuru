# H6 research prototype (scratchpad only, not senbazuru code): restyle the
# study's existing book SVG without moving any paper.
#   1. drop the second copy of each doubled contour
#   2. classify contours: outline against empty page vs. interior overlap
#   3. chain strokes; drop short dangling strokes (Benard et al. 2014 style)
#   4. line hierarchy: outline 1.6, interior 1.0, crease 0.5 (Lang's ~2:1)
#   5. halos: trim a stroke's end by HALO px where it stops on another line
#   6. optional: interpolating Catmull-Rom curves through the drawn vertices,
#      split at corners sharper than 30 degrees; report deviation from polyline
# Usage: python3 book_v2_prototype.py IN.svg OUT.svg [--curves] [--report R.json]
import re, sys, math, json, collections
src, out = sys.argv[1], sys.argv[2]
CURVES = "--curves" in sys.argv
REPORT = sys.argv[sys.argv.index("--report")+1] if "--report" in sys.argv else None
MIN_DANGLING, HALO, CORNER = 5.0, 1.5, 30.0
W_OUT, W_IN, W_CREASE = 1.6, 1.0, 0.5
svg = open(src).read()
head = re.match(r'(.*?<g [^>]*>\n)', svg, re.S).group(1)
paths = re.findall(r'<path d="([^"]*)"([^>]*)/>', svg)
fills, contours, creases = [], [], []
def pts(d): return [tuple(map(float, m)) for m in re.findall(r'(-?[0-9.]+) (-?[0-9.]+)', d)]
for d, attrs in paths:
    if 'fill="' in attrs: fills.append((d, re.search(r'fill="([^"]*)"', attrs).group(1)))
    elif '#343d36' in attrs: p = pts(d); contours += list(zip(p, p[1:]))
    elif '#777568' in attrs: p = pts(d); creases += list(zip(p, p[1:]))
TOL = 0.01  # page px; the SVG is rounded to 0.001
def dedup(segs):
    kept, doubled = [], []
    for i, (a, b) in enumerate(segs):
        L = math.dist(a, b)
        if L < 1e-9: continue
        u = ((b[0]-a[0])/L, (b[1]-a[1])/L); cov_prev, cov_any = [], []
        for j, (c, e) in enumerate(segs):
            if j == i: continue
            off = lambda p: abs(u[0]*(p[1]-a[1]) - u[1]*(p[0]-a[0]))
            if off(c) > TOL or off(e) > TOL: continue
            s = lambda p: (p[0]-a[0])*u[0] + (p[1]-a[1])*u[1]
            lo, hi = sorted((s(c), s(e))); lo, hi = max(lo, 0), min(hi, L)
            if hi - lo > TOL:
                cov_any.append((lo, hi))
                if j < i: cov_prev.append((lo, hi))
        def minus(pieces, cov):
            for lo, hi in cov:
                nxt = []
                for p, q in pieces:
                    if hi <= p or lo >= q: nxt.append((p, q)); continue
                    if lo > p: nxt.append((p, lo))
                    if hi < q: nxt.append((hi, q))
                pieces = nxt
            return pieces
        at = lambda t: (a[0]+u[0]*t, a[1]+u[1]*t)
        mine = minus([(0.0, L)], cov_prev)
        for p, q in mine:
            # within what survives, the part also covered by some other copy is interior
            single = minus([(p, q)], cov_any)
            for x, y in single:
                if y - x > TOL: kept.append(((at(x), at(y)), "outline"))
            dbl = minus([(p, q)], [(x, y) for x, y in single])
            for x, y in dbl:
                if y - x > TOL: kept.append(((at(x), at(y)), "interior"))
    return kept
def chain(segs):
    key = lambda p: (round(p[0]/TOL), round(p[1]/TOL))
    adj = collections.defaultdict(list)
    for i, (a, b) in enumerate(segs): adj[key(a)].append(i); adj[key(b)].append(i)
    used, chains = set(), []
    def walk(vk, i):
        line = []
        while True:
            used.add(i); a, b = segs[i]
            if key(a) != vk: a, b = b, a
            if not line: line.append(a)
            line.append(b); nk = key(b)
            nb = [j for j in adj[nk] if j not in used]
            if len(adj[nk]) != 2 or not nb: return line
            vk, i = nk, nb[0]
    for vk, ids in adj.items():
        if len(ids) != 2:
            for i in ids:
                if i not in used: chains.append(walk(vk, i))
    for i in range(len(segs)):
        if i not in used: chains.append(walk(key(segs[i][0]), i))
    return chains, adj, key
def length(line): return sum(math.dist(p, q) for p, q in zip(line, line[1:]))
def seg_dist(x, a, b):
    dx, dy = b[0]-a[0], b[1]-a[1]; L2 = dx*dx+dy*dy
    t = 0 if L2 == 0 else max(0, min(1, ((x[0]-a[0])*dx+(x[1]-a[1])*dy)/L2))
    return math.hypot(x[0]-a[0]-t*dx, x[1]-a[1]-t*dy)
contour_pieces = dedup(contours)
all_contour = [s for s, _ in contour_pieces]
chains, adj, key = chain(all_contour)
kind_of = {}
for s, k in contour_pieces: kind_of[(key(s[0]), key(s[1]))] = k; kind_of[(key(s[1]), key(s[0]))] = k
removed = []
def degree(p): return len(adj[key(p)])
kept_chains = []
for c in chains:
    L = length(c); ends = (degree(c[0]), degree(c[-1]))
    dangling = (1 in ends) or (key(c[0]) == key(c[-1]) and L < MIN_DANGLING)
    if dangling and L < MIN_DANGLING: removed.append(L); continue
    kept_chains.append(c)
# a kept chain takes the weight of its majority kind
def chain_kind(c):
    tot = collections.Counter()
    for p, q in zip(c, c[1:]): tot[kind_of.get((key(p), key(q)), "interior")] += math.dist(p, q)
    return tot.most_common(1)[0][0]
all_lines = [seg for c in kept_chains for seg in zip(c, c[1:])]
def ends_on_other(p, own):
    # T-junction: the end touches the interior of a different drawn line
    for a, b in all_lines:
        if (a, b) in own or (b, a) in own: continue
        if seg_dist(p, a, b) < 0.05 and math.dist(p, a) > 0.5 and math.dist(p, b) > 0.5: return True
    return False
def trim(line, h, at_start, at_end):
    line = list(line)
    for flag, idx in ((at_start, 0), (at_end, -1)):
        if not flag: continue
        need = h
        while len(line) >= 2 and need > 0:
            p, q = (line[0], line[1]) if idx == 0 else (line[-1], line[-2])
            d = math.dist(p, q)
            if d <= need:
                need -= d
                if idx == 0: line.pop(0)
                else: line.pop()
            else:
                t = need/d; n = (p[0]+(q[0]-p[0])*t, p[1]+(q[1]-p[1])*t)
                if idx == 0: line[0] = n
                else: line[-1] = n
                need = 0
    return line if len(line) >= 2 and length(line) > 0.5 else None
styled, haloed = [], 0
for c in kept_chains:
    own = set(zip(c, c[1:]))
    s, e = ends_on_other(c[0], own), ends_on_other(c[-1], own)
    haloed += s + e
    t = trim(c, HALO, s, e)
    if t: styled.append((t, W_OUT if chain_kind(c) == "outline" else W_IN, "#343d36"))
# creases: drop < 2 px fragments, chain, gap both ends where they meet ink
crease_chains, _, _ = chain([s for s in creases if math.dist(*s) > 1e-9])
crease_kept, crease_dropped = [], 0
for c in crease_chains:
    if length(c) < 2.0: crease_dropped += 1; continue
    s = any(seg_dist(c[0], a, b) < 0.05 for a, b in all_lines)
    e = any(seg_dist(c[-1], a, b) < 0.05 for a, b in all_lines)
    t = trim(c, HALO, s, e)
    if t: crease_kept.append((t, W_CREASE, "#6f6d60"))
def fmt(x):
    s = f"{x:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s
max_dev = 0.0
CAP = 0.5
STATS = collections.Counter()
def path_d(line):
    global max_dev
    if not CURVES or len(line) < 3:
        return "M " + " L ".join(f"{fmt(x)} {fmt(y)}" for x, y in line)
    # split at corners, then Catmull-Rom through every drawn vertex
    pieces, cur = [], [line[0]]
    for i in range(1, len(line)-1):
        a, b, c = line[i-1], line[i], line[i+1]
        v1 = (b[0]-a[0], b[1]-a[1]); v2 = (c[0]-b[0], c[1]-b[1])
        n1, n2 = math.hypot(*v1), math.hypot(*v2)
        cur.append(b)
        if n1 > 0 and n2 > 0 and math.degrees(math.acos(max(-1, min(1, (v1[0]*v2[0]+v1[1]*v2[1])/(n1*n2))))) > CORNER:
            pieces.append(cur); cur = [b]
    cur.append(line[-1]); pieces.append(cur)
    d = f"M {fmt(line[0][0])} {fmt(line[0][1])}"
    for pc in pieces:
        for i in range(len(pc)-1):
            p0 = pc[i-1] if i > 0 else pc[i]; p1, p2 = pc[i], pc[i+1]; p3 = pc[i+2] if i+2 < len(pc) else pc[i+1]
            # centripetal Catmull-Rom (alpha 1/2) as a cubic Bezier; keep the
            # chord when the curve would leave it by more than CAP px
            def tj(a, b): return max(math.dist(a, b), 1e-9) ** 0.5
            t01, t12, t23 = tj(p0, p1), tj(p1, p2), tj(p2, p3)
            m1 = [(p2[k]-p1[k]) + t12*((p1[k]-p0[k])/t01 - (p2[k]-p0[k])/(t01+t12)) for k in (0, 1)] if p0 != p1 else [p2[k]-p1[k] for k in (0, 1)]
            m2 = [(p2[k]-p1[k]) + t12*((p3[k]-p2[k])/t23 - (p3[k]-p1[k])/(t12+t23)) for k in (0, 1)] if p2 != p3 else [p2[k]-p1[k] for k in (0, 1)]
            c1 = (p1[0]+m1[0]/3, p1[1]+m1[1]/3); c2 = (p2[0]-m2[0]/3, p2[1]-m2[1]/3)
            dev = 0.0
            for k in range(1, 16):
                t = k/16; mt = 1-t
                bx = mt**3*p1[0]+3*mt*mt*t*c1[0]+3*mt*t*t*c2[0]+t**3*p2[0]
                by = mt**3*p1[1]+3*mt*mt*t*c1[1]+3*mt*t*t*c2[1]+t**3*p2[1]
                dev = max(dev, seg_dist((bx, by), p1, p2))
            STATS["segments"] += 1
            if dev > CAP:
                d += f" L {fmt(p2[0])} {fmt(p2[1])}"; continue
            STATS["curved"] += 1; max_dev = max(max_dev, dev)
            d += f" C {fmt(c1[0])} {fmt(c1[1])} {fmt(c2[0])} {fmt(c2[1])} {fmt(p2[0])} {fmt(p2[1])}"
    return d
body = "".join(f'    <path d="{d}" fill="{f}"/>\n' for d, f in fills)
body += "".join(f'    <path d="{path_d(l)}" stroke="{col}" stroke-width="{w}"/>\n' for l, w, col in crease_kept)
body += "".join(f'    <path d="{path_d(l)}" stroke="{col}" stroke-width="{w}"/>\n' for l, w, col in sorted(styled, key=lambda s: s[1]))
open(out, "w").write(head + body + "  </g>\n</svg>\n")
rep = {"contour_segments_in": len(contours), "unique_pieces": len(contour_pieces),
       "outline_px": round(sum(math.dist(*s) for s, k in contour_pieces if k == "outline"), 1),
       "interior_px": round(sum(math.dist(*s) for s, k in contour_pieces if k == "interior"), 1),
       "strokes_before_cleanup": len(chains), "dangling_removed": len(removed),
       "dangling_removed_px": round(sum(removed), 2), "halo_trims": haloed,
       "crease_strokes": len(crease_kept), "crease_fragments_dropped": crease_dropped,
       "paths_out": body.count("<path"), "paths_in": len(paths),
       "max_curve_deviation_px": round(max_dev, 3), "segments_considered": STATS["segments"], "segments_curved": STATS["curved"]}
print(json.dumps(rep))
if REPORT: json.dump(rep, open(REPORT, "w"), indent=1)
# free ends that remain after cleanup: an end touching no other drawn contour
free = []
for c in kept_chains:
    for p in (c[0], c[-1]):
        if degree(p) == 1:
            free.append(round(length(c), 1))
print("free contour ends after cleanup:", len(free), "on strokes of length (px):", sorted(free, reverse=True)[:12])
crease_segs = [s for s in creases if math.dist(*s) > 1e-9]
loose = []
for c in kept_chains:
    for p in (c[0], c[-1]):
        if degree(p) == 1 and not any(seg_dist(p, a, b) < 0.05 for a, b in crease_segs):
            loose.append(round(length(c), 1))
print("free contour ends touching no crease either:", len(loose), sorted(loose, reverse=True)[:12])
if "--loose" in sys.argv:
    pts = []
    for c in kept_chains:
        for p in (c[0], c[-1]):
            if degree(p) == 1 and not any(seg_dist(p, a, b) < 0.05 for a, b in crease_segs):
                pts.append(p)
    json.dump(pts, open(sys.argv[sys.argv.index("--loose")+1], "w"))
