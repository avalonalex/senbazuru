# A guarded gap can still lengthen an intersection

The saved **1/4** correction is refused because triangles **14–55** intersect
along a segment longer than `1e-7` sheet units. Both triangles already extend
past the other's plane in the passing start and **1/8** shape. Their four
existing overlap guards predict acceptable gaps, but the actual gap at one
moving corner worsens slightly. This inspection runs no new material solve
and installs no repair. [#366](https://github.com/avalonalex/senbazuru/issues/366)
continues [the nineteen-guard comparison](body-fourth-pair.md) under
[#195](https://github.com/avalonalex/senbazuru/issues/195), track A of
[#269](https://github.com/avalonalex/senbazuru/issues/269).

```bash
stack run senbazuru-material-study -- --body-contact-14-55 build/fold-material/body-fourth-pair build/fold-material
```

Open `build/fold-material/body-contact-14-55.html`. It compares `start.fold`,
`added-3.fold` (passing 1/8) and `added-2.fold` (refused 1/4), all from the same
saved direction. These fractions scale a proposed numerical correction; they
are not physical folding steps. Triangle 14 uses vertices **43, 37, 5** from
patch panel 1, original crane face 2. Triangle 55 uses **30, 29, 38** from patch
panel 5, original face 8. Material coordinates locate both on the original
sheet. The inherited order puts **55 below 14**.

Imagine each triangle's plane extending beyond its edges. The other triangle
*straddles* it when at least one vertex lies more than `1e-7` on each side.
Our crossing check requires both triangles to straddle and their finite
intersection to exceed `1e-7`. Here only that last condition changes:

| Saved shape | Both straddle | Intersection length | Crossing flagged |
| --- | --- | ---: | --- |
| Start | Yes | 2.750186e-8 | No |
| Passing 1/8 | Yes | 5.758939e-8 | No |
| Refused 1/4 | Yes | 1.469532e-7 | Yes |

The gallery records all six signed vertex-to-plane distances. None changes
its straddling classification. A short mathematical intersection already
exists in the accepted shapes; the test tolerates it. At 600 pixels per sheet
unit, even the refused segment is only **0.0000882 pixels** long. The annotated
close-up enlarges it with a fixed crop. Ordinary paper views keep their camera,
scale and bytes. This is a numerical contact diagnosis, not a visible new hole.

A gap is 14's height minus 55's at a corner of their top-view overlap. The four
guards occupy saved rows **4–7**. A positive gap must remain nonnegative; a
negative starting gap must not worsen. **Corner 0**, row 4, starts slightly
negative. Its active guard predicts essentially zero change, while the actual
moving triangles lose more gap:

| Shape | Actual corner-0 gap | Predicted gap | Actual minus predicted |
| --- | ---: | ---: | ---: |
| Start | −1.129149e-11 | −1.129149e-11 | 0 |
| Passing 1/8 | −2.398148e-11 | −1.129149e-11 | −1.268999e-11 |
| Refused 1/4 | −6.205187e-11 | −1.129149e-11 | −5.076038e-11 |

Doubling the correction multiplies this discrepancy by **4.00003**. This
supports a second-order remainder: the local linear prediction includes the
moving corner and both moving triangles, but its remaining error grows roughly
with the square of movement. Independent finite differences agree with the
existing derivatives; this is not evidence of a missing pair or an incorrect
first derivative. All four gap discrepancies show similar square scaling.

Both actual corner-0 gaps are well within the final `1e-7` contact tolerance,
yet both worsen the starting floor by more than the `1e-12` guard residual
tolerance. The original guard tests its *prediction*, not that actual floor.
Actual geometry has its separate crossing test, which catches the 1/4 shape.
The other overlap corners stay positive. A minute gap loss can therefore
lengthen a shallow intersection enough to change the geometric decision.

All material and acceptance settings remain fixed. Relative edge-length errors
are `6.429154e-6`, `6.118133e-6` and `6.803967e-6`; all remain below `1e-5`.
Holds are exact, and no inherited order reverses beyond contact tolerance.
Total costs are `0.012740340282`, `0.012690546844` and `0.012655266833`.
The cheaper 1/4 remains refused. No new endpoint, equilibrium, whole-crane
contact or continuously checked flexible route is claimed.

The archive reader reuses the preceding loop validator and recorded quadratic
force check. It authenticates both directions, all fifteen exported shapes
and their original repair decisions before copying publishable assets. Checking
an old repair formula reconstructs its saved coordinates only; it does not
install another correction. Reads finish before opening the next file.
Independent calculations verify the three inspected shapes' separate energies,
lengths, holds, all 7,140 triangle pairs per shape and **3,705 exported face-order
records**. Sixty-digit arithmetic confirms the plane distances, intersection
lengths and moving-corner gaps. Intersection lengths differ from the ordinary
floating-point calculation by less than `5.4e-15`, far below the `4.7e-8`
refusal margin. Finite differences check all twelve overlap gradients with
maximum error `2.90e-11`. All **2,131** source assets and the selected paper
SVG/FOLD files retain their bytes. A copy with vertex 29 moved by `1e-10` in
`added-2.fold` is rejected before publishing output. Generation and the negative
check both run under a 256-file limit. All eighteen shape/view combinations
load without browser warnings or errors. Ormolu 0.7.2.0, HLint 3.10's exact CI
JSON command, study JavaScript and inline-script syntax checks pass. This adds
no material solve to default CI. The cold build is warning-free; all **1,883
tests pass in 178.8 seconds**.

The next bounded comparison is one refreshed **corner-0 overlap-gap repair**
at the saved refused 1/4. Target its starting gap, preserve all nineteen
original guards and the other refreshed overlap guards, then recheck actual
contact, lengths, holds and total cost. Retain the unmodified refusal as the
control and keep any unsuccessful repair diagnostic. That would test whether
repairing this measured local approximation error permits the larger correction;
it would not justify relaxing tolerances or starting another continuation yet.
