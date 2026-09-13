# A rejected correction is not necessarily a collision

The checked closing strip ends with about 1.13% material-length error on the
recorded macOS run. Increasing its iteration budget did not help: after the
last accepted move, the solver kept recomputing the same direction and trying
the same fractions of it. A **line search** is that sequence of shorter trials,
looking for a lower total penalty without violating the motion check.

Run `stack run senbazuru-material-study -- --bending build/fold-material`, open
`bending.html`, and select **Contact between numerical poses → Checked curl**.
The rejection table now records the first failed check for each trial:

| First refusal | Trials on macOS, 12 September 2026 |
| --- | ---: |
| Energy did not decrease | 388 |
| Contact discovery or history | 20 |
| Invalid numerical trial | 0 |
| Witnessed path collision | 58 |
| Witnessed triangle collapse | 0 |
| Motion bounds unresolved | 1 |

A witness is a particular pose where the checker found a crossing. Unresolved
means that its work limit ran out without proving separation or finding such a
pose. These outcomes must remain separate: increasing the checker budget might
resolve the latter, but cannot make a witnessed intersection acceptable. Most
trials above never reached that checker at all, because energy or contact
measurement refused them first.

The important discontinuity is in the current directional layer penalty.
Consider two triangles whose shadows on the xy plane are initially disjoint.
The first has corners `(0,0,0)`, `(1,0,0)`, `(0,1,0)`. The second has corners
`(x,0,-0.05)`, `(x+1,0,-0.05)`, `(x,1,-0.05)`, with `x = 1.00001`.
Suppose a retained requirement says the first triangle must be below the second
wherever their shadows overlap. Moving `x` to `0.99999` introduces a tiny
triangular overlap. The surfaces stay 0.05 units apart throughout the move, but
their new overlap has the forbidden order. With clearance `1e-6`, each new
contact sample has gap `-0.050001`. The current sum of squared negative gaps
adds these samples at full weight, even as their overlap area tends to zero.
Thus physical separation and this retained directional order are different
conditions, and a very short move can add a finite penalty.

`CorrectionSweepSpec` checks that example independently: the whole motion
clears, the earlier contact row list is empty, and the new rows and independent
layer check report the reversed order. The closing strip shows the same
mechanism in an instrumented trial: a largest vertex displacement of about
`3.4e-12` introduced negative gaps around `-0.06317` for retained pairs `(0,30)`
and `(1,30)`, while the motion checker cleared the path. Merely shortening that
direction cannot remove the jump. Separate local experiments with area-weighted
penalties, predicted contacts and stronger movement damping did not reliably
settle the closing fixture. They are not enabled by this change.

The immediate solver change ends a penalty stage after all 31 available step
fractions have been refused. Changing the next stage's length/contact weight
can change the direction; repeating identical inputs within a stage cannot.
The final stage still reports **not settled** when blocked. On this Mac the run
now finishes after 29 numerical iterations rather than 400, retaining exactly
the same 25 accepted paths and endpoint. The opening still settles with three
accepted paths and maximum relative length error `6.56e-8`. Its 31 recorded
energy refusals come from a stationarity check: refusal alone does not
mean failure when the full proposed correction and material constraints already
meet the stopping rules. Earlier endpoint-only modes retain their behavior.

`SweptRelaxation` keeps counts and only the first and last rejected trial in
each of six categories: at most twelve trial records, each with two meshes,
plus at most four blocked-stage labels. The records contain the actual penalty
weight, iteration, step fraction, energies and typed reason. They are separate
from accepted positions and learned orders. Replay tests rebuild the reference
from accepted encounters, recompute energies, and repeat motion or discovery
refusals. The gallery JSON also includes witness positions, known orders,
spring controls and contact settings; material coordinates and triangle ids
come from that view's saved states. An unavailable energy is `null`, not zero.
Counts describe only the first failed check, not every defect of a candidate.

These are measurements of one numerical route, not cross-platform constants.
Linux may take a different route and settle; tests require the same material,
contact and full-path guarantees in either case. A contact formulation that
supplies a useful direction before this overlap boundary is developed in
[directional contact distance](directional-contact-distance.md), while this
original mode remains available for comparison. This increment is [#170](https://github.com/avalonalex/senbazuru/issues/170),
following [the numerical path check](checking-numerical-corrections.md).
