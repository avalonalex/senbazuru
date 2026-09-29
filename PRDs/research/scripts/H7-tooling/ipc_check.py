"""Independent checks on the study's whole-crane FOLD candidates with ipctk.

Reads a FOLD file (triangle faces), builds an ipctk CollisionMesh and reports:
  - whether ipctk finds any intersecting edge/triangle pair,
  - the minimum unsigned distance over candidate collision pairs at a small dhat,
  - how many collision stencils sit closer than a paper thickness.
"""
import json, sys, time
import numpy as np
import ipctk

def load(path):
    d = json.load(open(path))
    V = np.array(d["vertices_coords"], dtype=float)
    F = np.array(d["faces_vertices"], dtype=np.int32)
    return V, F

def edges_of(F):
    E = set()
    for a, b, c in F:
        for u, v in ((a, b), (b, c), (c, a)):
            E.add((min(u, v), max(u, v)))
    return np.array(sorted(E), dtype=np.int32)

for path in sys.argv[1:]:
    V, F = load(path)
    E = edges_of(F)
    mesh = ipctk.CollisionMesh(V, E, F)
    t0 = time.perf_counter()
    inter = ipctk.has_intersections(mesh, V)
    t1 = time.perf_counter()
    thickness = 1 / 1500  # 0.1 mm on a 15 cm sheet, in sheet units
    cols = ipctk.NormalCollisions()
    cols.build(mesh, V, thickness)
    t2 = time.perf_counter()
    dmin = cols.compute_minimum_distance(mesh, V) if len(cols) else float("inf")
    print(f"{path}: V={len(V)} F={len(F)} E={len(E)} has_intersections={inter} "
          f"({(t1-t0)*1e3:.1f} ms); stencils within 1/1500={len(cols)}; "
          f"min distance={dmin:.3e} (sqrt {np.sqrt(dmin) if np.isfinite(dmin) else dmin:.3e})")
