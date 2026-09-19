# A tiny exposed fragment can dominate a distance measurement

The [thin-layer investigation](thin-layer-visibility.md) left six oblique
comparisons in review. Their pixels differed, but that did not establish how
far the exposed paper regions differed. [#251](https://github.com/avalonalex/senbazuru/issues/251)
compares those filled regions directly, before SVG rounding or pixel sampling,
using the same saved endpoints and two-pixel illustration budget. No paper
coordinates, material checks or solver settings change.

For each point of the coarser mesh's visible lower layer, find the nearest
point in the finer mesh's visible lower layer. Take the largest distance,
then exchange the two meshes and repeat. Do the same for the upper layer.
This measures proximity of exposure, not movement of corresponding material
points. A newly exposed, very narrow strip far from the old exposure can
therefore give a large distance while the whole sheet moves less than a pixel.
The [glossary](../glossary.md) defines material coordinates and layer order.

Corners alone do not suffice. Consider a filled square from `(0,0)` to `(4,4)`
and the same square with its central `(1,1)`–`(3,3)` square missing. Every
outer corner agrees, but the centre is one unit from the remaining region.
Likewise, an extra strip from `(10,0)` to `(11,0.000001)` beside an unchanged
unit square contributes almost no area but gives a ten-unit distance to that
square. Both are executable counterexamples in `IllustrationComparisonSpec`.

`IllustrationDistance` treats each visible layer as a union of convex pieces.
A triangle's corners and centre supply sampled distances and a lower bound
with a witness: a source point and its nearest target point. For an upper
bound, first consider one convex target piece. Distance to that piece is
convex, so its largest value over a source triangle occurs at a corner.
The smallest of these per-piece maxima bounds distance to the target union.
Taking the nearest target at each corner and *then* the largest value is
only a lower bound: the nearest piece can change inside the triangle.

The algorithm bisects the longest edge of the triangle with the largest
remaining upper bound. It stops when the global interval is entirely inside
or outside the two-pixel budget, its width reaches 0.01 pixels, or 20,000
splits have been used. A budget decision can have a wide interval; it does
not claim the maximum was located precisely. An interval straddling the
budget remains unresolved. Empty exposure is explicit; disappearance of a
whole layer cannot pass. No positive-area piece is discarded by an area
threshold. These bounds use floating-point geometry and inherit the visible
polygons' numerical limits; they are not exact-arithmetic certificates.

The minority layer—the source panel with less visible area—gives these
results at 600 pixels per sheet unit. Distances below combine both directions;
values are rounded, and the full intervals are in `comparison.json`.

| View | Length refinement, 4×2 → 8×2 | Width refinement, 8×1 → 8×2 |
| --- | ---: | ---: |
| Top | About 9.573 px: outside | About 3.885 px: outside |
| 45° above | About 211.418 px: outside | About 105.070 px: outside |
| 45° below | Between 0.844 and 0.883 px: within | About 210.763 px: outside |
| 15° above | About 100.462 px: outside | About 90.568 px: outside |

The 211-pixel value does **not** mean that the sheet moved 211 pixels. The
witness sits on an exposed source piece with area only about 0.000384 px².
The corresponding large width-comparison witnesses occupy pieces around
0.000441–0.000597 px². These pieces exist in the unrounded visible polygons
but are far too thin to appear reliably as selected pixels. Their coordinates
and the witness endpoints are exported so the result can be inspected rather
than attributed vaguely to rendering. We have not identified them as numerical
noise or established a principled threshold for discarding them.

All majority-layer distances are bounded within two pixels, as are all eight
matched-control comparisons. Every nonempty direction reaches a budget
decision before exhausting its work limit. The 45°-below length pair is a
useful counterexample: **both geometric layer comparisons pass**, but its
sampled layer mask still fails. Thresholding a thin connected exposure can
leave separated sampled points. The two top-view band pairs show the opposite:
their pixel masks pass because the tiny minority exposure disappears in both,
while the continuous geometric comparisons fail.

The gallery therefore reports eight matched comparisons passing the combined
checks, eight band comparisons requiring layer review, and eight contact-off
comparisons remaining diagnostic. Neither kind of pass overrides the other's
failure. The material/convergence targets and independent contact tolerances
are unchanged. This study diagnoses the disagreements; it does not establish
all-camera illustration readiness or a physical folding route.

Use the existing `--illustration-refinement` command and page. Each geometric
comparison has a witness SVG: cyan shows coarser exposure, magenta shows finer
exposure painted afterward, and black segments join sampled source points to
their nearest target points. The drawing only illustrates the lower-bound
witnesses; measurements use the separate unrounded regions. The postprocessor
now writes 192 SVGs and exports the projected polygons, intervals, witnesses,
split counts and termination reasons. Pixel JSON also retains the geometric
results. Invalid or unresolved paper receives no geometric comparison.

Validation covers interior maxima, alternate subdivision, reversed winding,
repeated corners, thin and distant strips, empty/lost layers, invalid inputs,
work exhaustion and early budget decisions. Independent rational nearest-point
calculations on the exported coordinates reproduce all 48 nonempty-direction
witness distances and check source/target membership within 1e-8 pixels. All
saved source hashes and nine copied FOLD files remain unchanged. Browser
checks exercise all 24 comparisons and both directions of pixel/geometric
disagreement. The long material solve remains outside CI.

For illustration quality, the next bounded experiment is to measure how much
exposed area lies farther than two pixels from its counterpart, with an
explicit unresolved-area bound. Retain the maximum distance alongside it:
an area statistic alone could hide a lost but important feature. This would
put the microscopic fragments and larger visible differences on a common
scale without adopting an arbitrary waiver. The independent material-accuracy
next step remains evaluating prescribed bends on the existing meshes, without
optimization or higher resolution.
