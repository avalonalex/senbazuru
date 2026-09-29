"""Assemble the five folded states into one multi-frame FOLD, each frame
moved by an isometry so that face F3 (the part of the N quarter by the sheet
centre, which never moves) lands where it lies in the last frame. An in-plane
reflection is a flip-over of a flat model, so faceOrders stay valid."""
import json

fr = [json.load(open(f"out/stage-{k}-folded.fold")) for k in range(1, 6)]
cp = json.load(open("out/stage-1.fold"))
V0 = cp["vertices_coords"]


def inside(P, q):
    s = None
    for i in range(len(P)):
        x1, y1 = P[i][:2]; x2, y2 = P[(i + 1) % len(P)][:2]
        c = (x2 - x1) * (q[1] - y1) - (y2 - y1) * (q[0] - x1)
        if s is None: s = c > 0
        elif (c > 0) != s: return False
    return True


ref = fr[-1]
face = next(f for f in ref["faces_vertices"] if inside([V0[v] for v in f], (0.55, 0.75)))
a, b, c = face[:3]


def fit(src, dst):
    # affine map (2D) taking src triangle onto dst triangle
    (x0, y0), (x1, y1), (x2, y2) = src
    (u0, v0), (u1, v1), (u2, v2) = dst
    d = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
    A = [[((u1 - u0) * (y2 - y0) - (u2 - u0) * (y1 - y0)) / d, ((u2 - u0) * (x1 - x0) - (u1 - u0) * (x2 - x0)) / d],
         [((v1 - v0) * (y2 - y0) - (v2 - v0) * (y1 - y0)) / d, ((v2 - v0) * (x1 - x0) - (v1 - v0) * (x2 - x0)) / d]]
    return lambda p: [A[0][0] * (p[0] - x0) + A[0][1] * (p[1] - y0) + u0,
                      A[1][0] * (p[0] - x0) + A[1][1] * (p[1] - y0) + v0, 0.0]


titles = ["Waterbomb base", "Corners up to the top", "Side corners to the centre",
          "Top flaps down", "Tuck the flaps into the pockets"]
frames = []
for t, f in zip(titles, fr):
    X = f["vertices_coords"]
    T = fit([X[v][:2] for v in (a, b, c)], [ref["vertices_coords"][v][:2] for v in (a, b, c)])
    d = {"frame_title": t, "frame_classes": ["foldedForm"], "frame_attributes": ["3D"],
         "vertices_coords": [T(p) for p in X]}
    for k in ("edges_vertices", "edges_assignment", "edges_foldAngle", "faces_vertices", "faceOrders"):
        d[k] = f[k]
    frames.append(d)
top = dict(file_spec=1.2, file_creator="Y5-waterbomb experiment (constructed here)",
           file_title="Water-bomb balloon, five flat states", file_classes=["diagrams"])
top.update(frames[0])
top["file_frames"] = frames[1:]
json.dump(top, open("out/waterbomb-steps.fold", "w"))
