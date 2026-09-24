# Construct a separated start before applying the body barrier

[#379](https://github.com/avalonalex/senbazuru/issues/379) tests initialization
under the [bounded comparison decision](body-barrier-comparison.md). It starts
from the authenticated `body-fourth-pair/start.fold`: 87 material vertices,
120 triangles and the same three exact held points. Original sheet coordinates,
shared crease vertices, inherited layer relationships and crease preferences
remain unchanged. There is no barrier material solve in this experiment.

```bash
stack run senbazuru-material-study -- --body-initialization build/fold-material/body-fourth-pair build/fold-material
```

Open `body-initialization.html`. The left drawing is always the saved start;
the right selects a retained construction step. Side, top and underside views
use the same camera and 600 pixels per original sheet unit, with optional 4×
magnification. The original-sheet view identifies material. The gallery
separates construction cost from the archived crease/panel/contact costs and
from the checks required to enter the barrier solver.

A barrier needs a positive gap, so it cannot initialize these slightly
intersecting layers itself. This construction minimizes three squared errors
together: length error at weight `1e8`, clearance deficit at `1e10`, and movement
from the saved shape at weight `1`. A deficit is the amount by which an actual
gap falls short of its target. All inherited overlap corners participate,
with a `1e-6` target for triangles sharing no material vertex and zero for
joined triangles. Clearance is assigned per triangle: source panels can share
a crease while their distant triangles separate. A panel-wide exemption would
miss those contacts. The target is numerical, not physical paper thickness.

The coupled linear solve moves all free coordinates together. Exact held
vertices are removed from every equation, and shared vertices have only one
position. A sparse factor speeds the solve; the original equations still
verify its residual. Bending preferences are measured afterward but exert no
force in this geometric construction. Lower construction cost therefore does
not imply a better material equilibrium.

The parameters were recorded before running: at most **20 corrections**, each
trying `1, 1/2, …, 1/4096` of its proposal, with at most 2,000 inner linear
iterations, a residual threshold of `max(1e-6, 1e-8 × starting force norm)`
and `1e-3` damping. Damping stabilizes the
direction and is not included in the construction cost. Retained candidates
must remain within `0.001` sheet units of the original start and strictly lower
that cost. Failed factors, failed linear residuals, exhausted trial fractions
and the correction budget stop the attempt. There is no parameter retry.

Readiness separately requires connected material, exact holds and unchanged
identities, relative length error at most `1e-5`, all-pair contact and inherited
order checks. Local contact discovery must establish separated partners using
clearance `5e-7` and search distance `0.03`; its learned orders must agree with
the inherited ones. The barrier rows must be finite at activation distance
`0.001`. Finally the existing strict correction checker must certify the
static candidate against itself. Intermediate construction steps are not
certified paths from the intersecting start. Readiness is neither material
equilibrium nor a physical folding certificate.

The archive retains every full proposal, tried fraction and refusal, including
steps outside the movement budget. Only decreasing in-budget candidates enter
the displayed history. A failed construction is a reproducible initialization
blocker; it does not show that every possible separated start is impossible.

The **2026-09-24 result is an initialization blocker**. Four corrections
lowered the construction cost; the fifth exhausted all thirteen fractions.
Five linear directions passed their reported residual checks, and all 52
trials are saved: four retained and 48 refused. Construction took 1.05 CPU
seconds locally, excluding archive authentication, export and independent
verification. There was no second parameter attempt or barrier material solve.

| Measurement | Saved start | Last retained construction |
| --- | ---: | ---: |
| Construction cost | 0.7720168173 | 0.7623807602 |
| Maximum relative edge error (limit `1e-5`) | `6.42915e-6` | `3.18038e-5` |
| Minimum disjoint overlap height gap (must exceed `5e-7`) | `-1.54194e-8` | `-7.73649e-9` |
| Body depth, sheet units | 0.0362344417 | 0.0364331814 |
| Crease energy | 0.01162445 | 0.01174146 |
| Panel energy | 0.001062118 | 0.001242902 |
| Length cost | 0.00004802041 | 0.0004796684 |
| Archived zero-clearance contact cost | 0.000005752730 | 0.000002084843 |
| Crossing pairs at the existing `1e-7` tolerance | 0 | 1 (46–70) |
| Exact-hold error / reversed inherited orders | 0 / 0 | 0 / 0 |

The final displacement is at most `0.000471397` sheet units, or **0.283 drawing
pixels**. Depth changes by only 0.119 drawing pixels; the neck and tail
attachments move 0.00664 and 0.0261 pixels. Both wing-root holds and the centre
stay exact. At drawing size and 4× magnification the views show no useful new
body opening. The coloured contact and length highlights identify rejected
geometry; they are not additional opening.

No retained candidate clears the positive-gap requirement. Local discovery
first refuses triangles 0 and 34 as having no resolvable separated order, so
learned-order compatibility and barrier rows cannot be evaluated. The strict
static checker also reports intersections, including in the saved start that
passes the older tolerance-based endpoint check. The final candidate fails
that older check as well, with excess length error and crossing 46–70.
These are separate gates; reducing a penalty does not satisfy them.

Independent calculations checked all 7,140 triangle pairs in each of the five
exported states, lengths, gaps, separate costs, body depth, landmarks and holds,
plus all trial fractions and movement/cost refusals. Construction costs agree
within `4e-13`; joined corners within rounding distance of zero can contribute
different counts of effectively zero penalty rows in the two implementations.
All 2,131 input files remain byte-identical, as do the copied controls. A
`1e-10` change to a copied seed vertex is refused during archive authentication
before initialization. Six small regression tests cover coupled layers, shared
vertices, exact holds, budgets and refusal, without running this archive in CI.

Stop here under the declared decision. This trial establishes that this
bounded construction did not find an admissible start; it says nothing yet
about the barrier's ability to settle the body. Choosing another initialization
method or a different material/contact model needs a new scoped decision, not
another repair of the reported limiting pair. The matched barrier/penalty
comparison remains blocked, and no opened body is accepted.
