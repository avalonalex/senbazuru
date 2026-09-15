# Contact can push without permitting penetration

The [penalty experiment](contact-correction-at-a-crease.md) leaves the upper
paper about `6e-11` to `8e-11` sheet lengths below its fixed lower partner.
That passes the numerical tolerance but fails exact order. On the same small
crease, replace the penetration cost with a requirement: every upper-minus-
lower gap must be nonnegative. Touching is allowed, without adding thickness.
The [glossary](../glossary.md) defines panels, material coordinates and creases.

```bash
stack run senbazuru-material-study -- --crease-inequality build/fold-material
```

Holds, material lengths, bending springs, crease preferences, damping and
length-weight stages match the baseline. Only contact treatment changes.
The whole lower panel stays fixed; the upper outer quarter and the three
shared crease vertices stay held. Free upper vertices can move in x, y and z.
The three starting guesses are exact touching, penetration by up to `0.002`
sheet lengths, and penetration by up to `2e-8`. The old no-contact solve stays
as a baseline. An upper row deliberately held through the lower panel stays
as an impossible control.

The lower panel is a bent strip with known piecewise-linear heights. Clipping
an upper triangle over each lower strip produces an overlap polygon. Height
difference is linear within that polygon, so its minimum lies at a corner.
Each corner retains **barycentric weights**: fractions of its position supplied
by the triangle's vertices, summing to one. These weights identify how moving
a free vertex changes the corner's gap.

Near a held vertex almost all the weight can belong to the hold. Dividing a
contact row by its total free weight expresses the required movement of the
movable part. Exact fractions avoid turning a rounding error at an almost
entirely held point into an enormous correction. An entirely held negative
corner is impossible, and is refused with the involved vertex ids.

`ContactQuadratic` solves a small constrained quadratic: a squared linear
approximation of the material errors, plus damping. Its **working set** is the
collection of gaps currently treated as touching. It solves those equalities
together, advances until another gap blocks the move, and releases a contact
whose force would pull the layers together. Paper can push but does not glue
itself to another layer. The material matrix uses the existing sparse factor;
only the small contact system is dense. Redundant rows stay in the final
checks even when they cannot enter the working set independently. Convergence
checks every inequality, zero force at separated contacts, and force balance
against the original material equations. This is a small-fixture solver, not
a claim that a dense contact system scales to the crane.

The local inequalities predict a step, but moving vertices changes the
overlap polygons. `CreaseInequality` clips the proposed shape again. If any
gap is negative, it raises every free upper vertex by the smallest **common**
vertical amount covering all negative corners. At fixed x/y, each corner
rises by that amount times its free weight. Heights round toward positive
infinity, and the stored coordinates must pass the exact gap check afterward.
This is a uniform repair, not the nearest feasible shape or a physical motion.
It uses the same exact clipping as the constraints; the separate whole-sheet
checker and tests against prescribed profiles supply additional evidence.

Penetrating inputs need an initial repair, reported separately as a new
starting guess. During solving, a line search accepts a candidate only when
its material cost decreases **after** repair. A shortened or refused step is
not convergence: the full repaired proposal must be at most `1e-7` sheet
lengths and its quadratic solve must pass. Final length error must also be at
most `1e-5`. Early length-weight stages can strain the paper substantially;
their iterates are not accepted folding states.

Measured with the compiled gallery on 2026-09-14, all three compatible starts
give the following results (lengths are relative edge errors):

| Measurement | 32 triangles | 64 triangles |
| --- | ---: | ---: |
| Penalty minimum gap | -5.933e-11 | -8.431e-11 |
| Constrained minimum gap, exact stored coordinates | 0 | 0 |
| Penalty length error | 5.077e-7 | 8.102e-6 |
| Constrained length error | 5.077e-7 | 8.102e-6 |
| Constrained crease error, radians | 7.539e-6 | < 1e-14 |
| Penalty iterations | 32–34 | 79–80 |
| Constrained iterations | 20 | 45 |

All six constrained endpoints retain shared material and exact holds. They
pass the authored-angle cap of `1e-5` radians and the whole-sheet contact check
at its unchanged `1e-7` distance tolerance. Every recorded constrained iterate
has a nonnegative exact lower/upper gap. Zero is a minimum, not a claim that
all free paper touches: the shared crease and held strip already touch.
An impossible held row is refused at both resolutions; no-contact baselines
still penetrate substantially.

The initial common lifts are approximately `0`, `0.002` and `2e-8` sheet
lengths. Subsequent accepted repairs reach about `6.594e-8` and `2.125e-8`
at the two resolutions. Extra height from directed rounding stays below
`7e-18`. These are recorded numerical corrections, not a chosen clearance or
paper thickness. Fewer iterations do not by themselves establish a faster
method; `checks.json` records compiled CPU timings for both solves separately
from export and endpoint measurement.

The page compares negative-gap plots and all four stages: original guess,
penalty endpoint, feasible starting guess and constrained endpoint. Complete
FOLDs retain stored coordinates. GLBs contain all triangles but round for
display, so a clean view cannot establish exact contact. Focused tests cover
analytic force balances, release and redundant constraints, budget exhaustion,
outward rounding, exact repairs, invalid holds and both mesh resolutions.
The older penalty regressions remain unchanged.

This succeeds because the lower geometry and order are fixed. The
[two-panel follow-up](coupled-crease-contact.md) releases both interiors with
explicit holds and known order. It measures both current triangle surfaces
and repairs them in opposite directions, passing symmetric touching controls
and refusing incompatible holds. Asymmetric bending, general contact discovery,
calibrated paper mechanics and a certificate for continuous flexible motion
remain separate work.
