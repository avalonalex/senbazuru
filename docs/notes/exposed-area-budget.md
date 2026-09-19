# How much exposed paper exceeds the drawing allowance?

The [distance study](exposed-layer-distance.md) compares where a source layer
is visible on two meshes. A fragment smaller than 0.001 square pixels can sit
211 pixels from the nearest exposure on the other mesh. That distance is real
in the projected regions, but says little about how much of the picture is
affected. This follow-up to [#195](https://github.com/avalonalex/senbazuru/issues/195),
tracked in [#253](https://github.com/avalonalex/senbazuru/issues/253), measures
area alongside distance. It reuses the nine saved 8×2-study endpoints, four
cameras, 600 pixels per sheet unit and provisional two-pixel allowance.

Take every point where the coarser mesh exposes the lower layer. Keep the
points farther than two pixels from any lower-layer exposure on the finer
mesh, and measure their area. Then exchange the meshes. These are two different
source regions: the answers are directional and are not summed into a score.
Repeat for the upper layer. A missing target puts all source area outside;
an empty source has zero area. Missing-layer distance remains explicit.

`IllustrationDistance.areaBeyondBudget` divides convex source polygons into
triangles. For each triangle it proves one of three things: all points are
within the allowance, all are outside, or some remain unclassified. Distance
to one convex target polygon reaches its maximum at a source corner; taking
the smallest such maximum over target polygons gives an upper bound for the
union. For the lower bound, start with the centroid's nearest-target distance
and subtract the farthest corner's distance from that centroid. Moving a point
by a distance cannot change its distance to a fixed set by more than that
amount. Thus this lower bound holds for the whole triangle, unlike a sampled
witness that proves only one point is outside.

Bisect the largest unclassified triangle along its longest edge and repeat.
The answer is an interval: definitely outside area, through that area plus
all remaining unclassified area. Shared triangle edges have no area. Source
polygons must have disjoint interiors, as the visible-region pipeline supplies;
this is a caller precondition, not a general polygon-union implementation.
Targets may overlap. Each bisection carries half its parent's area to avoid
repeatedly subtracting almost collinear coordinates. Re-sum the remaining
cells before stopping so accumulated subtraction error does not masquerade
as unclassified paper. All bounds use floating-point arithmetic and retain
its roundoff limits; they are not exact-arithmetic certificates.

The declared precision target is **0.00001 px² of unclassified area per
direction**, with at most **100,000 splits**. Precision controls uncertainty
in the measurement, not how much mismatch we permit. No positive-area polygon
is discarded. A work-limited result retains its interval and cannot claim
the requested precision. Existing maximum-distance checks and pixel verdicts
are unchanged.

Generate the measurements without another material solve:

```bash
stack run senbazuru-material-study -- --illustration-refinement \
  build/fold-material/band-refinement-8x2 build/fold-material
```

The gallery's new area table and `comparison.json` contain both directions,
source area, outside bounds, unclassified area, split counts and termination
reason. The 192 SVGs and saved paper are unchanged. Results for the less-exposed
layer of the band control follow; intervals below are rounded outward to six
decimal places. “Length” compares 4×2 with 8×2; “width” compares 8×1 with 8×2.
The lower layer is less exposed except in the below view, which sees the upper.

| Camera / refinement | Coarser → finer outside area (px²) | Finer → coarser outside area (px²) |
| --- | ---: | ---: |
| Top / length | 0.000110–0.000121 | 0.000984–0.000995 |
| Top / width | 0.000384–0.000395 | 0 |
| 45° above / length | 0.008897–0.008908 | 0.441085–0.441096 |
| 45° above / width | 0.077323–0.077334 | 0.001309–0.001310 |
| 45° below / length | 0 | 0 |
| 45° below / width | 0.000329–0.000339 | 0.000505–0.000506 |
| 15° above / length | 0.002627–0.002638 | 0.616486–0.616497 |
| 15° above / width | 0.104790–0.104801 | 0.001689–0.001690 |

Every one of the 64 directed layer comparisons reaches the precision target;
48 have nonempty sources. The largest split count is 17,945. Matched controls
and the more-exposed layer of each band comparison have zero outside area.
The below-view length pair also has zero outside area for both layers,
consistent with its geometric pass despite a sampled pixel failure.

Some distant fragments affect very little area, but they do not explain all
of the difference. The low-angle length comparison has about 0.6165 px² of
finer exposure outside the coarser region's allowance, versus about 0.00263 px²
in the reverse direction. The above-view length pair similarly reaches about
0.4411 px². Both are still below one square pixel in total, but that area can
be spread along an extended thin feature; this does not establish invisibility.
Neither the maximum distance nor the area alone expresses visual importance.
All eight band comparisons remain in review, eight matched comparisons pass,
and eight invalid contact-off comparisons remain diagnostic.

Six small analytic regressions cover straight boundaries, a hole, disconnected
targets, a circular boundary with known area, tiny distant exposure, alternate
triangulation, winding, empty/lost exposure and exhausted work. An independent
Python/Shapely calculation expands each convex target by an inscribed and a
circumscribed regular 512-sided disk of radius two pixels. Subtracting these
unions from the source gives separate outside-area intervals. All 64 overlap
the Haskell intervals within 1e-8 px² floating-point tolerance; source interiors
are independently checked for overlap. Original distances, geometry checks,
source hashes and all nine copied FOLD files remain unchanged. The browser
checks all 24 comparisons and displays the new measurements without changing
their verdicts. Only the small analytic regressions join CI.

The next illustration decision is to inspect where the remaining outside area
lies at the intended drawing size, especially the two length comparisons
above. An area-based exception needs an explicit visual justification and must
retain missing-layer and material/contact checks; this study introduces none.
The separate material-accuracy next step remains prescribed bends on the
existing meshes, without optimization, to distinguish representation effects
from the solver's chosen shape. No larger mesh or crane-body solve is implied
by a small illustration area.
