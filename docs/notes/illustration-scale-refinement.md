# Judge the drawing at the size it will be used

The [8×2 band comparison](band-refinement-8x2.md) passes the paper checks but
misses the material-study refinement targets. That does not tell us whether
the difference matters in an illustration. Its 37.74% change in maximum
opening is only 0.00124 of the sheet's side. At 600 pixels per sheet unit,
that distance is 0.744 pixels before projection. A large percentage of a
small opening can coexist with a very similar drawing.

[#247](https://github.com/avalonalex/senbazuru/issues/247) compares the saved
matched-hold, distributed-band and contact-off endpoints on `4×2`, `8×1`
and `8×2`. It runs no material solve and changes no coordinates:

```bash
stack run senbazuru-material-study -- --illustration-refinement \
  build/fold-material/band-refinement-8x2 build/fold-material
```

This requires the saved `checks.json` and nine `*-after.fold` files from
`--band-refinement-8x2`. If they are missing, the earlier study must be run
first; this command never silently starts that expensive calculation.
Serve `build/fold-material` over HTTP and open `illustration-refinement.html`.
The page includes the measurements, complete input FOLD files, source solver
report and 112 SVGs: paper illustrations, silhouette/crease/layer masks and
visible-ink overlays. A mask is a diagnostic drawing showing just one kind
of feature. The [glossary](../glossary.md) defines material coordinates,
creases, panels and layer order.

Keep two different milestones in [#195](https://github.com/avalonalex/senbazuru/issues/195):

| Illustration milestone | Material-study target |
| --- | --- |
| Same connected sheet, material identities, exact holds and unchanged length, crease and contact checks | Same requirements |
| At most two pixels of projected position and sampled silhouette/crease displacement at the declared scale | Position changes below 0.001 sheet lengths under both refinements |
| Inspect exposed layers; report lost features or layer-mask changes explicitly | Stable main contact regions and opening changes below 5% |
| Bending-energy changes remain diagnostics | Each nonzero energy component changes below 5% |
| Inspect the actual drawings from every declared camera | Tighter-solve confirmation and eventual physical calibration remain separate work |

The two-pixel budget is a provisional engineering choice, declared before
judging these images. It does not allow paper penetration or establish a
physical folding route. A mask with no visible crease is reported as such;
it is not evidence that a crease was measured. A feature appearing or
disappearing, or a layer-mask sample beyond the budget, prevents an automatic
all-checks pass. The original material targets are retained, including the
unperformed tighter-solve check.

Four cameras look straight down, from 45° above, from 45° below and from 15°
above the side. Each has one box enclosing all nine poses. SVG dimensions
are chosen to preserve exactly 600 page units per sheet unit, with 20-pixel
margins, subject to the SVG writer’s existing 0.001-page-unit rounding.
The browser displays that size without fitting each image to its
container. A labelled 2× inspection mode enlarges the view without changing
the measured budget. No mesh gets an independent recentering, scale or
alignment that could conceal a difference.

Matching old vertices is insufficient. A finer mesh can bulge between them.
Even checking both vertex sets misses a difference where their subdivision
edges cross. The postprocessor intersects the triangles in original-sheet
coordinates and compares both spatial maps at every overlap corner. On each
overlap both maps are linear, so the maximum length of their difference,
including after projection, occurs at a corner. This gives a bound for the
whole piecewise-flat sheet, subject to the clipper's floating-point
arithmetic. The accepted meshes share the same material domain, independently
checked against the fixture.

The fresh geometry checks confirm the six contact-enabled endpoints still
pass; the three contact-off endpoints still fail. Saved crease/panel/layer
identities and selected report measurements must agree with the loaded
FOLD files. Historical convergence is reported separately. The existing
projected visibility code resolves all 24 accepted endpoint views and
declines the twelve crossing-control views. Unresolved views get no graded
fallback illustration.

The band results are:

| Camera | Maximum projected change, length | Maximum projected change, width | Largest sampled silhouette change |
| --- | ---: | ---: | ---: |
| Top | 0.558 px | 0.133 px | 0 px |
| 45° above | 0.872 px | 0.197 px | 0.707 px |
| 45° below | 0.871 px | 0.197 px | 1.000 px |
| 15° above | 1.071 px | 0.239 px | 0.707 px |

Every accepted comparison meets the position and silhouette budgets. Visible
crease masks agree at the sampled locations. The full-sheet band difference
along length is 0.001831, slightly larger than the earlier shared-vertex
measurement of 0.001770; across width it remains 0.0004075. The matched
control's maximum projected change is 0.389 pixels.

The pixel check draws the SVG masks on a grid with half-pixel spacing,
selecting samples with at least half opacity. It asks, in both directions,
whether each selected sample has the same kind of feature within two pixels.
For layer masks the kind is the original lower or upper panel, independent
of the paper's front/back colour. It counts all outliers and can mark up to
200 per mask in the overlay. Those orange circles are locating aids, not
new paper or a representation of the area of the difference.

Eight matched comparisons and both top-view band comparisons meet every
sampled budget. The six oblique band comparisons flag thin exposed-layer
slivers: length/width comparisons have 21/11 outlying lower-layer samples
from above, 11/16 upper-layer samples from below, and 20/4 lower-layer
samples from the low view. These are small in sampled area, but an outline
alone would miss them. Thresholded sampling of a subpixel strip can produce
isolated samples, so a long distance to the next same-layer sample does not
necessarily mean a similarly wide visible patch. These views need inspection
and remain outside the automatic all-checks budget. Contact-off comparisons
remain diagnostic regardless of image similarity.

The result supports a bounded illustration milestone: the matched controls
and top-view band satisfy the declared screen checks. It does not yet give
an all-camera acceptance of the band, or resolve material convergence. Before
another large solve, inspect the flagged slivers at the intended drawing
size and distinguish visible paper exposure from mask-sampling sensitivity.
Keep any choice to tolerate subpixel layer changes explicit. The separate
prescribed-bend energy experiment remains the next step for material accuracy.

Validation uses seven small Haskell counterexamples, including an unchanged
vertex set with crossed diagonals and a bulge introduced at a new vertex.
The Node.js checks cover shifted masks, lost layers, internal holes, image
boundaries and invalid-paper/visibility gating. Independent rational clipping
reproduces all 24 projected maxima and the complete material-overlap area.
The nine copied FOLD files are byte-identical to their sources; the 112 SVGs
share their declared camera extents and dimensions, within serialization
rounding. Wrong-study input and an altered held vertex are refused. All
24 browser comparisons were exercised, with paper views inspected from all
four cameras. The cold build passes 1458 tests without compiler warnings;
formatting, HLint 3.10 and the JavaScript checks pass. No long solve was added
to CI.
