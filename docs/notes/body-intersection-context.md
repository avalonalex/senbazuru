# An intersection hidden in the body drawing

The [larger-opening experiment](body-larger-opening.md) adds 21.77 drawing
pixels of body depth, but triangles 2 and 39 intersect along **0.23175 px**.
That exceeds its provisional 0.1 px screen. [#395](https://github.com/avalonalex/senbazuru/issues/395)
asks whether this geometric failure affects the illustration, using the saved
forty-correction endpoint with **no new solve or changed tolerance**.

An intersection is a line where two surfaces pass through each other. It is
not necessarily a visible line: another folded layer may cover both. At
600 px per sheet side, the saved line projects to 0.192–0.231 px depending on
the camera. The inspection clips the entire projected segment against the
renderer’s visible pieces, combines their covered intervals, then checks the
covering triangle’s original plane depth. A covered midpoint alone would miss
exposed ends. Depth means distance along the camera direction; it is separate
from distance along the page.

| Camera | Projected segment, px | Visible covering triangle / original crane face | Least cover depth, px |
| --- | ---: | --- | ---: |
| Top | 0.23081 | 105 / 30 | 26.324 |
| 45° above | 0.21607 | 112 / 37 | 0.36630 |
| 45° below | 0.20219 | 116 / 38 | −0.00000000376 |
| 15° above | 0.19239 | 112 / 37 | 1.0234 |

**Other paper covers the entire segment in all four drawings.** None of the
segment belongs to an exposed piece of triangle 2 or 39, and no uncovered
visibility region touches it. The low camera’s earlier coverage residual
elsewhere is gone: cut again with nothing skipped, as production's coverage
check does ([#459](https://github.com/avalonalex/senbazuru/pull/459)), no
more than a speck of it is left uncovered (re-measured 2026-10-02). Triangle ids name this specimen’s refined mesh;
original crane face ids locate the same paper in `examples/crane.fold`.

Drawing coverage is not quite geometric separation. Three views place the
covering triangle nearer the camera over the whole segment. Underneath, the
covering triangle is nearer for most of the segment, then falls behind by up
to **3.76e-9 px** over its final **0.000742 px**. The established 0.1 px depth-tie
policy uses inherited layer order there. This is an explicit rendering
approximation already present in the previous gallery, not a new clearance or
proof of collision-free paper. Depth difference between planes varies linearly
along a segment, so endpoint depths bound it, and interpolation locates where
its sign changes.

The gallery shows ordinary paper unchanged, a separate 24 px location box,
and 4×/64× crops centred on the crossing. Pink crop ink is an x-ray annotation
over the covering layer, not an exposed pink or orange defect. Its length
follows the measured segment; its stroke is deliberately visible. At 4× the
line is still under one pixel long; at 64× it is 12–15 px. Switching markers off
shows the ordinary drawing. Magnification enlarges paper boundary ink too.
Optional cyan/purple outlines expose the two hidden triangles for orientation.

This evidence argues against another individual-pair precision repair **for
these static drawings**. The endpoint still fails strict contact and the
provisional intersection-length screen, and remains unsettled. No acceptance
flag changes. The next decision is explicit illustration acceptance of the
opened specimen, with this recorded exception, before testing how it attaches
to the surrounding crane. Other views, motion, physical thickness and complete
crane response have not been checked by this inspection.

The shared archive reader reconstructs the same material, initial guess and
exact holds, then checks the exported endpoint against the raw checkpoint.
The copied inputs are byte-identical. Independent NumPy plane sections reproduce
the 3D intersection length within `1e-9 px`; Shapely/GEOS confirms full-segment
coverage in all four views. Independently interpolating depth on each original
triangle agrees within `2e-10 px`; the tiny underside sign-change length agrees
within `2e-8 px`. All four ordinary SVGs are byte-identical to the earlier
endpoint drawings. Small tests cover partial/full segment coverage, overlapping
intervals, boundary/degenerate cases and depth-sign changes without a body solve.

From the repository root, with the existing saved archive:

```bash
stack run senbazuru-material-study -- --body-intersection-context build/fold-material/body-larger-opening build/fold-material
```

Open `body-intersection-context.html`. Its `checks.json` records segment ends,
per-triangle visibility pieces, covered intervals, original-plane depth margins
and both drawing and geometric coverage. `source/` retains the endpoint,
initial state and raw run; the source archive itself is not rewritten.
