# An unguarded overlap at 55–93

The last refused **1/64** trial in [the ten-correction loop](body-restoration-loop.md)
is limited by vertex **30** crossing triangle **93**'s extended plane. The
smaller **1/128** passes. Unlike the earlier 46–70 refusal, the overlap gaps
also worsen here, and their derivatives predict that loss accurately. The
saved direction has no explicit guard for this pair.
[#358](https://github.com/avalonalex/senbazuru/issues/358) records this inspection
under [#195](https://github.com/avalonalex/senbazuru/issues/195) and track A of
[#269](https://github.com/avalonalex/senbazuru/issues/269). No new material solve
or contact repair runs. See [the glossary](../glossary.md) for material
coordinates, panels and contact.

```bash
stack run senbazuru-material-study -- --body-contact-55-93 build/fold-material/body-restoration-loop build/fold-material
```

The source is correction ten's start, `step-9.fold`, and its
`attempt-10-trial-6.fold` and `attempt-10-trial-7.fold`. The fraction multiplies
one saved numerical correction; it is not a fraction of a physical folding
motion. The gallery offers those three states at the same camera and scale,
plus fixed enlarged contact views. All paper drawings and FOLD files keep
their source bytes; new outlines label the pair, vertex 30 and overlap corners.

All ids below are zero-based. Triangle **55** has vertices **30, 29, 38** and
belongs to patch panel **5**, original crane face **8**. Triangle **93** has
vertices **33, 5, 37** and belongs to patch panel **11**, original crane face
**20**. They share no material vertex and none of their six vertices is held.
Their source panels order **93 below 55**. The sign of an overlap gap therefore
comes from 55's height minus 93's height, not from numerical triangle order.

Imagine each triangle's flat surface extended beyond its edges. The crossing
check measures the other triangle's vertices perpendicular to that plane,
using the normal from the original vertex order. It requires vertices farther
than `1e-7` sheet lengths on both sides of **each** plane, plus an intersection
segment longer than `1e-7`. Triangle 93 already spans both sides of plane 55.
Vertex 30 supplies the missing negative distance against plane 93 at 1/64:

| Saved state | Vertex 30 → plane 93 | Margin above −1e-7 | Minimum overlap gap | Intersection length | Crossing flagged |
| --- | ---: | ---: | ---: | ---: | --- |
| Start | +1.023892870e-6 | +1.123892870e-6 | −7.667634706e-9 | 0.000365478487 | No |
| Passing 1/128 | +4.348671263e-7 | +5.348671263e-7 | −7.744158710e-9 | 0.000864222972 | No |
| Refused 1/64 | −1.541585536e-7 | −5.415855359e-8 | −2.092037290e-8 | 0.004548771405 | Yes |

Distances are in sheet lengths. Vertex 29 is slightly negative throughout,
but inside the tolerance; vertex 38 stays clearly positive. Vertex 30 is about
`0.0172935` outside triangle 93's projected outline, measured against its edge
lines. Its extended-plane distance is therefore **not** a physical overlap
sample. The six actual overlap corners all remain within the `1e-7` gap
tolerance, so the layer-order check passes even when the plane test refuses.
A mathematical intersection already exists in the passing controls; the
refusal does not imply a suddenly visible hole or a rounding-sized error.

A contact guard is a local inequality used when choosing a correction. The
existing policy asks a positive gap to remain nonnegative, or a negative gap
to get no worse. Here we evaluate those hypothetical inequalities along the
saved direction, without installing them or choosing another direction. Their
derivatives include both moving triangles and the moving overlap corner.
The six corners retain their identities in these three saved states.

| Corner | Starting gap | Actual at 1/128 | Actual at 1/64 | Predicted at 1/64 |
| --- | ---: | ---: | ---: | ---: |
| 4 | +8.466068725e-8 | +3.186991629e-8 | −2.092037290e-8 | −2.092133645e-8 |
| 5 | −7.667634706e-9 | −7.744158710e-9 | −7.820444217e-9 | −7.820921215e-9 |

Corner **4** would fail its nonnegative-gap guard at 1/64. Corner **5** would
fail its no-worsening guard in **both** fractions: its predicted losses are
`7.66433e-11` and `1.53287e-10`, beyond the `1e-12` guard residual tolerance.
This distinction matters: adding all six guards is stricter than today's
passing-geometry decision, and could constrain useful motion too. The other
four corners satisfy their hypothetical guards.

The largest actual-versus-predicted gap difference is only `9.64e-13` across
these states. Vertex 30's predicted plane distance at 1/64 is
`−1.541586815e-7`, within `1.28e-13` of the saved result. The main issue in this
trial is an unguarded worsening overlap, not a poor derivative prediction.
Pair 55–93 is already included in the soft contact penalty: its cost rises
from `2.93963e-7` to `2.49411e-6` at 1/64. “No explicit guard” does not mean the
solver knows nothing about the pair. That penalty can trade off against other
costs; a guard would instead constrain the local proposal.

All three states preserve one connected sheet, 87 shared vertices, 120
triangles, exact holds and relative length error below `1e-5`. Both fractions
lower total cost, and neither reverses an inherited order beyond tolerance.
Only 1/64 fails the all-pair crossing check. The old vertex 27–plane 70 repair
cannot help because its target distance has not worsened in that trial.

The new archive reader verifies the preceding source chain and all **137**
loop states: 11 retained, 96 raw trials and 30 repairs. It binds coordinates
to recorded fractions or the saved one-repair formula, rebuilds material and
contact rows, checks recorded force balance, and remeasures acceptance before
publishing. This checks saved algebra; it does not run another solver.
Independent calculations verify the three inspection states' costs, lengths,
all 7,140 triangle pairs, material ownership and **3,703** exported face orders.
Sixty-digit plane calculations agree with the threshold classification, and
finite differences verify all eighteen contact derivatives with maximum error
`2.70e-11`. All **2,025** source assets are copied unchanged. Altering vertex 30 by `1e-10`
in a copy of the final refused FOLD is rejected before output. All six gallery
views load for all three states without browser errors. The cold build and
final annotation build have no warnings; all **1,883 tests pass in 170.6 seconds**.
Ormolu 0.7.2.0, HLint 3.10 with the CI JSON command, study JavaScript and the
inline-script syntax check pass. This adds no material solve to default CI.

The next bounded experiment should compare **one matched direction adding the
six 55–93 overlap guards at this same saved start**, keeping the thirteen old
guards, material, holds, weights, damping, budgets and actual acceptance checks.
Compare it with the saved direction and retain every refusal. This will test
whether the extra inequalities permit useful progress; the derivative audit
alone cannot establish that. Do not add a vertex 30 plane guard or weaken the
crossing tolerance in the same comparison. No accepted body-opening endpoint,
continuous flexible route or surrounding-crane response is established here.
