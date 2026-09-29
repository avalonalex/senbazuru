"""Crease length per wrap class, and a rounded-crease strip triangle estimate.
Imports the analysis from crane_layers.py by re-running it as a module."""
import runpy, sys, json
sys.argv = ['crane_layers.py', '/Users/yuhanhao/Project/senbazuru/examples/crane.fold', 'crane-folded.fold']
import io, contextlib
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    g = runpy.run_path('crane_layers.py')
Vm, E, wraps = g['Vm'], g['E'], g['wraps']
xi = 1/1500  # 0.1 mm on a 150 mm sheet, in sheet units
by = {}
for ei, w in wraps:
    (x1, y1), (x2, y2) = Vm[E[ei][0]], Vm[E[ei][1]]
    L = ((x2-x1)**2 + (y2-y1)**2) ** 0.5
    by.setdefault(w, [0, 0.0]); by[w][0] += 1; by[w][1] += L
rows = {}
for w, (n, L) in sorted(by.items()):
    r = (w + 1) * xi / 2
    rows[w] = {"creases": n, "length": round(L, 4), "fillet_radius_sheet": round(r, 6), "fillet_radius_px_at_600": round(600 * r, 2)}
est = {}
for s in (0.02, 0.05):
    tri = sum((L / s) * (6 if w > 0 else 2) * 2 for w, (n, L) in by.items())
    est[str(s)] = round(tri)
print(json.dumps({"by_wrap": rows, "strip_triangles_estimate_by_along_crease_spacing": est}, indent=1))
