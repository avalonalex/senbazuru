# Locating a subpixel exposed-area difference

The [area study](exposed-area-budget.md) found about 0.4411 and 0.6165 square
pixels of finer-mesh exposure beyond the coarser mesh's two-pixel allowance.
These totals came from the 45°-above and 15°-above length comparisons. They
could describe an isolated fleck or a long thin strip, which would matter
differently in an origami instruction drawing. This follow-up, tracked in
[#255](https://github.com/avalonalex/senbazuru/issues/255), locates the actual
contributions using the same saved meshes and the same area calculation.

The dominant contribution is a **thin strip along the lower outline**. It is
hard to see in the full drawing at 1×; the 32× details reveal it without
widening the highlighted paper. Most of its area falls into two adjacent
16×16-pixel tiles. Smaller, separated fragments remain elsewhere on the
sheet, including the ones responsible for the earlier large maximum distances.

| Finer → coarser length view | Definitely outside area (px²) | Largest tile (px²) | Second tile (px²) | Share in these two tiles |
| --- | ---: | ---: | ---: | ---: |
| 45° above | 0.441086 | 0.330752 | 0.101097 | 97.9% |
| 15° above | 0.616486 | 0.451080 | 0.144754 | 96.7% |

The first view has seven occupied tiles, the second eleven. A tile is a
rectangle on the drawing grid, not a connected paper feature; two adjacent
tiles can contain one strip. No polygon is dropped for being small, and a
percentage here is a share of definitely outside area, not of the whole sheet.
The unchanged full-area intervals still include less than 0.00001 px² of
unclassified area per direction. This is a location result, not an area-based
acceptance exception. All eight band comparisons remain in review.

Regenerate the gallery from the saved endpoints:

```bash
stack run senbazuru-material-study -- --illustration-refinement \
  build/fold-material/band-refinement-8x2 build/fold-material
```

In `illustration-refinement.html`, use **Inspect 45° above · length** or
**Inspect 15° above · length** under **Locate the exposed-area difference**.
The buttons choose the lower layer and the finer-to-coarser direction. The
full-sheet diagnostic stays at 1×: one page unit is one CSS pixel at normal
browser zoom. A selected 16-pixel tile occupies 512 pixels in the 32× detail,
plus margins. The ordinary inspection zoom elsewhere on the page does not
resize either of these views. The camera and refinement controls still apply.

Grey supplies the source sheet's silhouette; pale blue shows the matching
layer's target exposure. Red marks triangles proven wholly beyond the
allowance, and amber marks the still-unclassified triangles. Neither fill
has a stroke. Optional purple dashed frames and numbers locate the detail
tiles; these marks are navigation aids and are not included in the area.
Tiles are ordered by the sum of outside and unclassified area, largest first.
The selector and caption give each tile's contribution in square pixels at
1×, even while the drawing is enlarged. Empty source exposure, zero outside
area and invalid paper have explicit display states.

The measurement now offers `areaRegionsBeyondBudget` alongside
`areaBeyondBudget`. Both use the same subdivision and stopping policy; the
former retains the triangles that established the interval. It returns the
original area weights as well as coordinates, since repeatedly subdividing a
thin triangle can accumulate coordinate roundoff. Outside and unclassified
cells stay separate, including when the work limit is reached. The former
scalar API simply reads the bounds from this richer result.

`IllustrationHighlights` clips these regions to a fixed 16-pixel grid in
Haskell. Source cells have disjoint interiors; clipping partitions them into
tiles whose geometric areas reproduce the measured totals within roundoff.
The scalar interval remains authoritative. The unrounded contributing
triangles and their area weights are available as separate JSON files; the
compact comparison report links those files, the overview and each detail.
Across all accepted comparisons there are 64 directed diagnostics, 25,649
retained triangles and 41 occupied detail tiles. The postprocessor adds 169
SVGs: 64 overviews, 64 optional locator drawings and 41 details, for 361 total.
It does not run the material solver.

A detail must be rendered **before** rounding the overview. Our SVG writer
rounds page coordinates to three decimal places. Enlarging an already rounded
SVG can therefore miss a sliver that collapsed to a line at 1×. Instead, each
detail clips the unrounded coordinates to its tile, applies the declared 32×
scale in the normal Haskell projection, then formats the result. The backend
still supplies the only y-axis reversal: geometry is y-up, SVG is y-down.
No SVG transform changes coordinates or stroke widths. Each colour is one
`Fill` with multiple rings, preventing seams between adjacent source triangles.
Rasterization and coordinate rounding still limit what a viewer can see; the
unrounded data is retained even when a contribution remains too faint to see.

Four small regressions check retained-cell weights and locations, work-limited
uncertainty and missing targets, grid-edge/negative-coordinate partitioning,
and clipped 32× projection with exactly one y flip. An independent
Python/Shapely check verifies every retained cell is in the source, every red
triangle is more than two pixels from the target within 1e-8-pixel roundoff,
and tile area sums agree with the existing bounds within 1e-8 px². It also
checks crop dimensions and unstroked fill coordinates. All prior scalar
measurements, original SVGs and copied FOLD files remain unchanged.

This gives a concrete visual example for choosing an illustration-specific
rule, but does not choose that rule. A narrow strip may be acceptable in a
particular drawing; a missing layer or important fold feature cannot be waived
by small total area alone. The next material-accuracy experiment remains
prescribed bends on the existing meshes, comparing their energies without
optimization, before another larger mesh or crane-body solve.
