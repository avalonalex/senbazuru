# Visible paper can disappear from a pixel mask

The [illustration comparison](illustration-scale-refinement.md) found six
oblique views whose thin exposed layers missed a two-pixel comparison budget,
even though their outlines and material positions passed. Are those slivers
real paper, or just the sampling grid? [#249](https://github.com/avalonalex/senbazuru/issues/249)
answers the first question and tests the second without another material solve.
It reuses the nine saved endpoints, four cameras and 600-pixel sheet scale.

The slivers exist in the renderer's visible polygons before drawing pixels.
For the distributed bend preference, these are the minority layer's area and
maximum vertical span in three meshes:

| View | Area, 4×2 / 8×1 / 8×2 (px²) | Maximum span, 4×2 / 8×1 / 8×2 (px) |
| --- | ---: | ---: |
| Top | 0.219 / 0.475 / 0.462 | 0.0026 / 0.0049 / 0.0051 |
| 45° above | 45.024 / 76.441 / 76.368 | 1.395 / 1.761 / 1.921 |
| 45° below | 45.120 / 76.636 / 76.564 | 1.394 / 1.761 / 1.921 |
| 15° above | 61.451 / 104.333 / 104.232 | 1.905 / 2.406 / 2.624 |

“Minority layer” means the one with less visible area: the original lower
panel except when viewed from below. The [glossary](../glossary.md) defines
panel, material coordinates and layer order. Span adds the lengths of all
exposed intervals in a vertical column, then takes the largest total across
the image. It excludes gaps but can include several separate strips. It is
camera-dependent: neither perpendicular strip thickness nor a difference
between the meshes. These measurements alone cannot establish that a
same-layer feature moves more than two pixels.

The visible polygons are non-overlapping convex pieces. Their area comes
from their corners. Between successive corner x coordinates, each piece's
top and bottom edges vary linearly; the total vertical span therefore reaches
its largest value at an interval's end. Checking the two one-sided limits
avoids double-counting a shared vertical subdivision edge. This calculation
uses the renderer's floating-point polygons before SVG rounding, with no
opacity threshold or pixel grid.

The previous mask painted the lower panel red, then the upper one blue.
Partially transparent edge pixels can mix, so classifying the resulting
colour can favor the later paint. The postprocessor now also writes each
layer separately in black on transparency. These diagnostic masks retain
the same visibility result and never change the ordinary paper illustration.
The original two-colour measurement remains available for comparison.

The browser repeats the isolated-layer check at 2, 4 and 8 samples per pixel,
each with offsets `(0,0)`, `(0.5,0)`, `(0,0.5)` and `(0.5,0.5)` in raster
samples. Both images receive the same offset. Selection still requires at
least half opacity and searches for the same layer within two page pixels.
It also integrates opacity before thresholding to report coverage area.

All six oblique band comparisons flag the minority layer on **every one of
the twelve grids**. Counts vary with density and alignment:

| View / refinement | Outlier count range at 2 / 4 / 8 samples per pixel |
| --- | ---: |
| 45° above, length | 31–33 / 39–41 / 123–125 |
| 45° above, width | 8–10 / 28–29 / 34–39 |
| 45° below, length | 17–19 / 72–75 / 135–139 |
| 45° below, width | 3–5 / 28–30 / 36–41 |
| 15° above, length | 23–28 / 53–61 / 128–154 |
| 15° above, width | 2–4 / 18–24 / 41–48 |

Raw counts at different densities are not comparable areas: one sample at
8× covers one sixteenth as much area as one at 2×. Coverage itself remains
rasterizer-dependent. For example, the lower layer in the 45°-above length
comparison covers approximately 45.7–45.8 / 74.5 px² at 2× and 44.7 / 76.4 px² at
8×, versus 45.0 / 76.4 px² in the unrounded polygons. SVG coordinates are
rounded to 0.001 page units, which also matters for the extremely thin top
exposure. Twelve grids are evidence about sampling sensitivity, not a
continuous distance proof or an exhaustive rasterizer test.

Both top-view band comparisons pass all twelve grids, although their minority
polygons have positive area: the opacity threshold loses that tiny exposure
in both meshes. The 45°-above matched-hold length control also passes. The
ordinary half-pixel check still gives ten passing comparisons, six requiring
layer review and eight diagnostic contact-off comparisons. Invalid paper
and unresolved visibility never receive a pass.

The policy therefore stays conservative: preserve the existing material,
position, outline and crease checks; any sampled layer failure keeps the
view in review. Small area or one passing grid is not a waiver. Even all
passing grids require inspection of the actual drawings and the polygon
exposure. We have not established all-camera illustration readiness, and
this result does not weaken contact tolerances or the material-study targets.

Run the existing `--illustration-refinement` command, then open
`illustration-refinement.html`. It now writes 160 SVGs, including isolated
layers. The page offers exposure measurements and an optional twelve-grid
audit for the selected comparison; downloadable JSON includes its grids,
coverage, outliers and browser identity. Incomplete audits cannot turn an
otherwise passing view into an audited pass. Analytic Haskell cases cover
subpixel strips, subdivision, separated intervals and a corner maximum;
JavaScript counterexamples cover missing layers and incomplete/failed audits.
The original saved report and all nine endpoint files retain their hashes,
and copied FOLD files remain byte-identical. No long solve is added to CI.

For illustration acceptance, the next bounded measurement is distance directly
between the exposed-layer polygons in the six flagged comparisons. That can
separate an actual geometric displacement from the gaps made by thresholded
samples, without changing the meshes or guessing an area waiver. For material
accuracy, the separate next experiment remains prescribed bends on existing
meshes, comparing energies without optimization. Neither requires immediately
increasing mesh resolution.

The [direct-distance follow-up](exposed-layer-distance.md) now supplies those
bounds. One oblique pixel failure has a geometric pass, while the top view
conceals geometric failures; tiny distant fragments dominate several maxima.
