# Repairing one contact can disturb another

One tiny repair clears the saved **14–55 crossing**, but the candidate remains
**refused**: it fails two original guards and one refreshed guard at **55–93**.
Actual all-pair contact, lengths, exact holds and cost descent from the original
start pass. This separates a useful local repair from a correction that preserves
all the constraints used to choose its direction.
[#373](https://github.com/avalonalex/senbazuru/issues/373) continues
[#195](https://github.com/avalonalex/senbazuru/issues/195), track A of
[#269](https://github.com/avalonalex/senbazuru/issues/269).

Start with the nineteen-guard comparison's saved **refused 1/4 trial** from
[the added-guard experiment](body-fourth-pair.md).
[The inspection](body-contact-14-55.md) located a discrepancy at corner 0 of
triangles 14 and 55's projected overlap: its actual gap loses more than the
original guard predicts. Triangle 55 is below 14, so the gap is 14's height minus
55's at that corner. A guard is a linear prediction of how that gap changes
with small vertex movements; a negative starting gap must not worsen.

```bash
stack run senbazuru-material-study -- --body-overlap-restoration build/fold-material/body-fourth-pair build/fold-material
```

Open `build/fold-material/body-overlap-restoration.html`. The saved start,
passing 1/8 and unmodified refused 1/4 keep their FOLD and paper SVG bytes.
Only the fourth shape receives a repair. Fractions describe a numerical
correction, not a physical folding step. The gallery compares actual drawing
size and a shared enlarged crop. Orange/purple contact highlights disappear
when no crossing or reversed order is flagged; no paper was removed.

The original corner gap is **−1.129149225e-11** sheet units. At the refused
trial it is **−6.205186878e-11**, a loss of **5.076037653e-11**. Refresh the
corner's derivative there, removing held coordinates. If the derivative is
`g` and the gap loss is `loss`, the smallest summed squared vertex movement
that repairs the predicted loss is `delta = loss * g / dot(g,g)`. A component
perpendicular to `g` adds movement without improving that prediction. The
derivative includes both moving triangles and their moving overlap corner.
The target preserves the slightly negative starting gap; setting it to zero
would be a different experiment.

This computes **one algebraic projection**, with no new material direction,
continuation, retry or safety offset. The maximum installed movement is
**2.644624531e-11** sheet units, or **1.586774718e-8 pixels** at 600 pixels per
unit. Measurements use the installed positions after floating-point addition,
and the export records both raw and installed corrections.

| Measurement | Refused 1/4 | One repair |
| --- | ---: | ---: |
| Corner 0 actual gap | −6.205186878e-11 | −1.129149444e-11 |
| 14–55 intersection length | 1.469531982e-7 | 2.674083656e-8 |
| Crossing pairs flagged | 1 | 0 |
| Reversed orders beyond 1e-7 | 0 | 0 |
| Maximum relative length error | 6.803966528e-6 | 6.803966528e-6 |
| Held-point error | 0 | 0 |
| Crease energy | 0.0115335491394 | 0.0115335491388 |
| Panel-bending energy | 0.00105704833453 | 0.00105704833723 |
| Length cost | 6.013439395e-5 | 6.013438725e-5 |
| Contact cost | 4.534965243e-6 | 4.542969970e-6 |
| Total cost | 0.0126552668332 | 0.0126552748333 |

The actual target misses by only **2.18e-18**, within the unchanged `1e-12`
guard residual tolerance. The repaired intersection is below the existing
`1e-7` crossing-length threshold. The tiny repair raises cost by
**8.000114449e-9**, mainly through contact cost; it remains cheaper than the
original direction's starting cost, **0.0127403402819**. That starting cost is
the unchanged descent gate. Body depth remains **0.0362604780572**; this is no
new visible opening.

The remaining refusal is specific:

| Guard | Predicted margin after repair | Required minimum |
| --- | ---: | ---: |
| Original row 13: 55–93 corner 0 | −3.946793115e-11 | −1e-12 |
| Original row 18: 55–93 corner 5 | −5.076840118e-11 | −1e-12 |
| Refreshed row 17: 55–93 corner 5 | −5.076905346e-11 | −1e-12 |

The original nineteen guards measure total movement from the saved direction's
start. The eighteen refreshed overlap guards measure this repair from the
refused trial. The stronger corner-0 target adds a separate check. Pair 55–93
has 93 below 55. Its actual corner-5 gap worsens from **−7.609776990e-9** to
**−7.660546041e-9**, matching the refreshed guard's predicted loss. Both gaps
remain inside the final `1e-7` geometry tolerance. The original guards also
fail, although this repaired gap is slightly better than its original starting
value: their linear prediction and the actual geometry are different checks.
All other guards pass, including the vertex 27–plane 70 guard. Repairing one
overlap independently therefore does not preserve neighboring contact constraints.
It does not show that a joint repair is impossible.

`BodyFourthArchive` authenticates both source directions, every saved raw trial
and repair, and their preceding archive chain. The shared minimum-movement
routine retains the old plane-repair behavior and error messages. Three fast
new tests exercise a real overlap above a held triangle, repeated material-id
gradient contributions, and invalid held derivatives. Independent calculations
verify the new projection, all **38** guard margins, **72** moving overlap
derivatives (maximum finite-difference error **2.31e-10**), separate costs,
lengths, holds, all **7,140 triangle pairs per shape**, and **4,942** exported
face-order records. Sixty-digit arithmetic confirms the tiny overlap gaps and
14–55 intersection lengths. All **2,131** source assets retain their bytes. A source copy with vertex 29
moved by `1e-10` in `added-2.fold` is refused before publishing output. Generation
and this negative check both run under a 256-file limit. All **24** shape/view
combinations load without browser warnings or errors. Ormolu 0.7.2.0, HLint
3.10's exact CI JSON command, study JavaScript and inline-script syntax checks
pass. The cold build is warning-free; all **1,890 tests pass in 162.5 seconds**.
No material solve is added to default CI.

The next comparison proposed when this experiment finished was **one joint
minimum-movement repair** at this same refused 1/4, protecting the original
nineteen and refreshed eighteen guards while targeting the same 14–55 starting
gap. It would recheck actual geometry, cost and target, retaining this failed
independent repair as a control, without continuation or relaxed tolerances.
The saved full material
proposal remains **5,456 times** above its movement stopping tolerance: a tiny
repair does not establish equilibrium, a continuously checked flexible route,
or whole-crane inflation.

**Superseded on 2026-09-24:** the owner chose to pause this repair sequence.
The [body barrier comparison plan](body-barrier-comparison.md) records the
current blocker and a bounded alternative, including a separate initialization
budget. The joint repair above is deferred; all measurements and refusal
decisions in this note remain unchanged.
