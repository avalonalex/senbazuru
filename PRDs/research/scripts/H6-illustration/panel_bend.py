# H6 research: largest angle between two triangle normals inside one source
# panel (panel = paper between creases), for each saved pose. A developable
# bend has a spread of normals; a spread near 180 degrees means the panel
# folds back on itself where no crease exists.
import json, math, sys, collections, glob, os
def sub(a,b): return [a[i]-b[i] for i in range(3)]
def dot(a,b): return sum(a[i]*b[i] for i in range(3))
def cross(a,b): return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
def unit(a): n = math.sqrt(dot(a,a)); return [x/n for x in a]
for path in sorted(glob.glob(f"{sys.argv[1]}/*.fold")):
    fold = json.load(open(path)); P = fold["vertices_coords"]; F = fold["faces_vertices"]
    panels = fold.get("senbazuru:source_panels")
    if not panels: continue
    by = collections.defaultdict(list)
    for i, (a, b, c) in enumerate(F): by[panels[i]].append(unit(cross(sub(P[b], P[a]), sub(P[c], P[a]))))
    spread = []
    for p, ns in by.items():
        m = 0.0
        for i in range(len(ns)):
            for j in range(i+1, len(ns)):
                m = max(m, math.degrees(math.acos(max(-1, min(1, dot(ns[i], ns[j]))))))
        spread.append(m)
    spread.sort()
    print(f"{os.path.basename(path):14s} panels {len(spread)}: spread >5deg {sum(s>5 for s in spread)}, >30deg {sum(s>30 for s in spread)}, >90deg {sum(s>90 for s in spread)}, max {spread[-1]:.0f}deg")
