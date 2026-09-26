# Judge saved body errors at drawing scale

[#389](https://github.com/avalonalex/senbazuru/issues/389) follows the owner's
2026-09-26 direction: a plausible origami illustration may tolerate numerical
errors. More solver precision is useful when it changes the picture or enables
a useful pose. This assessment reads saved shapes only; it runs no solve and
changes no position, hold, solver setting or historical verdict.

At **600 drawing pixels per sheet unit**, the saved cases separate clearly:

| Saved pose | Maximum local edge strain | Maximum absolute edge error, px | Negative order height, px | Longest strict-failure intersection, px |
| --- | ---: | ---: | ---: | ---: |
| Recovered subdivided seed | 0.00016210% | 0.00005629 | 0.000003454 | None reported |
| First correction | 0.00016210% | 0.00005629 | 0.000003454 | None reported |
| Second correction | 0.00093413% | 0.00027872 | 0.00001033 | 0.005881 |
| Original fine endpoint | 4.00788% | 1.11274 | 0.054089 | 61.9268 |
| Angle-derived seed | 0.000000002184% | 0.000000001430 | 4.71338 | 47.7546 |

An edge's **strain** is its length change divided by its original length.
An **order height** measures how far the required upper layer falls below the
lower one along the fixture's vertical contact direction. An **intersection**
is a line along which two triangles pass through each other. Its length runs
along the paper, not through its depth. Only pairs refused by the original
crossing checker contribute to the last column; a tolerated mathematical
intersection may still exist in a passing pose.

The original fine endpoint demonstrates why loosening the height check alone
would be wrong: its depth error is below 0.1 px, but a crossing extends almost
62 px and its worst local strain exceeds 4%. The angle-derived seed also has
large contact defects despite nearly perfect lengths. It uses different grip
positions, so it is a failure control, not a matched alternative to the recovered
seed. The two controls should not pass merely because one quantity is small.

The second correction is a candidate for illustration review despite failing
strict contact. Relative to the recovered seed, every material point moves by
at most 0.17506 drawing pixels in 3D. The largest projected movement is 0.01114
px from above, 0.12324/0.12471 px at 45° above/below, and 0.16884 px at 15° above.
These bounds hold throughout each triangle because both states use the same
triangles and linearly interpolated positions. They are bounds on corresponding
material points, **not** exposed colour changes at occlusion boundaries. An
individual edge's absolute error, unlike this matched displacement, does not
bound the accumulated shape error.

The gallery compares all five saved states using the same extent for each of
four cameras: top, side 45° above, side 45° below and side 15° above. It shows
actual size and 4× magnification, a recovered-seed toggle, production previews
and mesh edges. Orange annotations locate negative-gap regions at allowances
of 0, 0.1, 0.5 and 1 px. Red strokes locate strict-failure intersection segments;
the strokes are widened for legibility. Neither annotation removes hidden paper.

There is a rendering limit to this assessment: **all twenty production views
use the whole-face/wire fallback**. That path cannot establish hidden-edge or
visible-colour correctness. The saved second correction and seed look close
in these previews, but that is insufficient to approve their exposed layers.
For example, at zero allowance the second correction's top-view negative-gap
footprints sum to 4,427.83 px² even though their maximum depth is only
0.00001033 px. The sum counts overlaps repeatedly and includes buried regions;
it is not thousands of pixels of visible damage. All these footprints disappear
from the diagnostic overlay at the 0.1 px allowance. This changes the overlay,
not the paper. A small gap can cover a broad region; visibility must settle
whether that region matters to the drawing.

**Proposed illustration policy:** start with a 0.1 px distance review screen
at this drawing size, applied separately to absolute edge errors, reversed
order heights and strict-failure intersection lengths. Keep a separate 0.1%
local-strain screen so subdivision cannot make large relative distortion seem
harmless merely by shortening edges. These are provisional screening values,
not calibrated visibility thresholds or new solver defaults. The 0.5 and 1 px
comparisons do not change which of these five cases fit the three distance
screens. The current evidence distinguishes their classes; it does not identify
an optimal cutoff within that range.

A candidate below the screens still needs review of its silhouette, exposed
layers, visible creases and plausible bulging at intended sizes and cameras.
Keep connected material, shared vertices and crease identities. Record strict
residuals separately, and label an approximate static illustration as such;
neither convergence nor a collision-free folding path follows from a good
picture. A 150 mm sheet would make one drawing pixel 0.25 mm and `1e-7` sheet
units 15 nm. That conversion is a scale example, not an assumed physical
thickness or a claim about real measurement precision.

**Next:** make a bounded visible-layer comparison of the recovered seed and
second correction. Use their declared layer orders to resolve small depth ties
under the proposed illustration allowance, keep the original geometry, and
compare silhouette/crease/exposed-colour masks in the four cameras. Report any
unsupported region. Do not start another contact repair or more accurate
constrained solve just to satisfy the old numerical verdict. The original
fine endpoint and angle-derived seed remain useful rejection controls. If the
small-case rendering is credible, review it as an approximate static illustration
and spend further material work on a useful opening rather than on these tiny
crossings. The [body blocker](body-overlap-restoration.md) remains documented;
a useful opened body and its interaction with the full crane are still unfinished.

Reproduce from the existing `body-subdivision/`, `body-patch/` and
`body-crease-seed/` archives, without rerunning their generators:

```bash
stack run senbazuru-material-study -- --body-visual-tolerances build/fold-material build/fold-material
```

Open `build/fold-material/body-visual-tolerances.html`. Its `checks.json` records
all edge errors, contact corners, intersections, camera measurements and source
file names. Twelve source files are copied byte-for-byte. The original archive
readers verify topology, material coordinates, holds and saved measurements;
the angle seed is rebuilt from its saved angles and matched to its saved FOLD
frame without optimization. Independent Python arithmetic reproduced all five
length/contact summaries, 131 reported intersection segments and 80 projected
footprint measurements. Small tests cover clipping at a threshold, exact touching,
and broad but shallow negative regions. No large body solve is added to CI.
