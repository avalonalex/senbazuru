# Compare saved body poses by what the drawing exposes

[#391](https://github.com/avalonalex/senbazuru/issues/391) follows the
[drawing-scale assessment](body-illustration-tolerances.md). It reads the
recovered subdivided seed and second saved correction. No position, shared
vertex, crease, hold, solver setting or historical verdict changes; no solve
runs. The question is whether tiny numerical contact defects prevent a useful
static illustration, not whether these poses are mechanical equilibria.

A **depth tie** here permits an inherited layer order to override at most
**0.1 drawing pixel of wrong-side depth**, measured along the camera direction
at 600 pixels per sheet side. Suppose two panels are correctly separated by
4 px at one end and overlap incorrectly by 0.00001 px at the other. Only the
0.00001 px contradicts their order; the 4 px separation needs no allowance.
Depth varies linearly across each triangle, so checking the corners of their
projected overlap bounds that entire overlap. Clear separation uses actual
depth. Missing orders and crossings deeper than the allowance remain unresolved.
This is a visibility rule, not physical thickness, displaced geometry or a
contact certificate.

The experiment expands the original source-panel orders to all relevant mesh
triangles. The saved `spreadSurface` frame includes only overlaps in the
world's horizontal plane; using that subset alone can lose an order in an
oblique view. FOLD signs refer to the second face's normal, so both its winding
and the camera direction matter when converting an order into near/far.
`IllustrationVisibility` keeps this policy in the study and reuses the existing
visible-region and hidden-edge subtraction. Production rendering is unchanged.

All eight strict views decline visibility. With the illustration allowance,
**every pairwise overlap resolves in all eight views**. The largest depth
actually overridden is **0.000054 px**, far below the allowance. Five views
cover the sheet to the existing polygon check. Three retain tiny uncovered
patches: seed/top 0.000487 px², second/top 0.000394 px², and seed/below
0.000361 px². Their largest spans are 0.072, 0.038 and 0.045 px. These are
reported coverage residuals, not proof of a cyclic layer order or a new
material defect. The gallery shows them in red and retains uncertainty around
them; it does not patch them by moving paper or inventing a face owner.

The two poses are drawn with one shared extent per camera, at actual size and
4×. Pink masks show the union of changed regions: silhouette, paper colour,
source-panel identity and visible crease ink. A colour switch is counted once;
changes at the silhouette also count. A physical crease is distinct from a
numerical triangle join; joins are not inked. The same 0.8 px square-ended
crease strokes are used in the paper drawing and ink mask.

| Camera | Silhouette difference, px² | Exposed-colour difference, px² | Source-panel difference, px² |
| --- | ---: | ---: | ---: |
| Top | 1.069–1.070 | 1.269–1.270 | 1.980–1.981 |
| Side, 45° above | 10.155 | 20.650 | 26.171 |
| Side, 45° below | 8.75798–8.75834 | 22.53291–22.53327 | 27.90377–27.90413 |
| Side, 15° above | 13.772 | 27.742 | 35.000 |

Ranges exclude uncovered regions from the lower estimate and include their
entire area in the upper estimate. A crease stroke can reach 0.4 px beyond
unknown paper, so its uncertainty uses expanded bounding boxes instead of
borrowing the smaller paper-area bound. The gallery exports those masks and
intervals too. These are floating-point polygon measurements: an independent
polygon engine (Shapely/GEOS) checks all sixteen masks within 0.001 px², not a claim of
exact arithmetic. The complete above/low views have crease-ink differences of
5.558 and 8.022 px².

Area alone does not describe visual importance. A narrow strip along a long
edge can add up to tens of square pixels while staying below a pixel in width.
The [earlier positional assessment](body-illustration-tolerances.md) bounds
corresponding material movement by 0.011–0.169 px in these cameras. The actual
paper previews and magnified masks are the review evidence; neither those
bounds nor small area totals automatically accept an illustration. Strict
geometry still passes for the seed and fails for the second correction.
Neither is a converged solution or a checked flexible motion.

**Next:** review these as approximate static illustration candidates. If their
visible layering is credible, use this drawing-scale policy to assess one
bounded, visibly useful opening from the recovered shape. Do not make repairing
these coverage residuals or strict contact crossings a prerequisite. No new
opened-body result is claimed here; the larger strained and angle-derived
controls from the previous study remain rejected.

Reproduce with the existing archive (the reader validates material and the
saved correction trace before writing):

```bash
stack run senbazuru-material-study -- --body-visible-layers build/fold-material/body-subdivision build/fold-material
```

Open `body-visible-layers.html`. Its JSON retains all pair decisions, projected
regions, difference masks, uncertainty masks and byte-identical source files.
CI exercises small visibility counterexamples without replaying a body solve.
