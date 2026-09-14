# An exhausted solve is not a blocked fold

The [body-angle study](body-angle-preferences.md) left 47 of its 49 crossing
reports between panels joined by two internal creases. Crease 26 joins panels
8 and 27; crease 51 joins panels 7 and 43. Both are mountain folds, with the
paper's front side bending outward. Before freeing more of the body, locate
these shared material lines and separate boundary effects from contact forces.
The ids refer to the study's cut source pattern, which already contains the
wing-root lines; subdivision carries each source id onto its mesh segments.
The [glossary](../glossary.md) defines panels, creases and layer orders.

```bash
stack run senbazuru-material-study -- --crane-internal build/fold-material
```

Each line has nine shared vertices after refinement. The original boundary
holds one endpoint; the other eight vertices can move. The held-line control
fixes those sixteen additional vertices at their original positions. This
keeps each line straight, but does not fix the angle between its sides:
material beside the line can still bend. No coincident layers are welded.

A separate control keeps only the contact forces for 27 below 8 and 43 below 7.
It removes surrounding forces from the solve, but retains all 902 source orders
and every triangle in the independent check. Reduced-force results remain
explicit diagnostics even if geometry passes: they cannot establish equilibrium
with omitted forces present. All controls use the same 609 vertices, 1,176
triangles, 50-degree tip grip, material springs and acceptance tolerances.
The whole-patch-held reference changes only the boundary holds.

The solver tries progressively smaller fractions of a correction until its
objective decreases. Its bounded audit records the first and last refusal of
each kind, including length, angle and contact energy before and after the
proposal. These are numerical proposals, which may stretch or cross paper;
they are not physical folding steps. Recording them reproduces the original
endpoint vertex-for-vertex.

The original reaches 118 iterations without exhausting a line search. It is
still making accepted corrections. Continuing that endpoint for eighty more
iterations at the final length penalty `1e8` avoids softening the material
again by restarting the earlier stages. Its relative edge error falls from
`3.75e-5` to `2.07e-5`, but the largest original-angle error grows slightly from
`0.0187` to `0.0194` radians. More work improves some checks without making the
endpoint valid.

Measured on 2026-09-14; crossing counts below are the unchanged independent
checker's reports, not a measure of penetration depth:

| Control | Held vertices | Force orders | Iterations | Equilibrium | Relative edge error | Original-angle error (rad) | Crossing reports |
| --- | ---: | ---: | ---: | --- | ---: | ---: | ---: |
| Original | 119 | 164 | 118 | No | 3.75e-5 | 0.0187 | 49 |
| Crease lines held | 135 | 164 | 99 | Yes | 8.08e-6 | 7.24e-5 | 19 |
| Internal forces only | 119 | 2 | 80 | No | 3.86e-5 | 0.0180 | 282 |
| Held lines + internal forces | 135 | 2 | 70 | No | 1.69e-5 | 0.00895 | 375 |
| Whole patch held | 495 | 34 | 17 | Yes | 1.73e-7 | 7.48e-8 | 0 |
| Original continued | 119 | 164 | 80 more | No | 2.07e-5 | 0.0194 | 23 |

All holds remain exact. Only the whole-patch-held reference passes acceptance.
Holding the crease lines lets the linear solve and proposed full movement meet
the numerical equilibrium criteria, and passes the `1e-5` length limit. It
still fails the `1e-5`-radian original-angle limit and contact checks. Omitting
surrounding forces worsens the full-sheet result substantially: the two
reduced-force controls have 6,291 and 7,677 reversed order reports respectively.
No control stops a penalty stage because of a failed line search before
reaching equilibrium.

Zero reversed orders does not imply zero intersections. The original's smallest
active signed contact gap is `-3.91e-8` model units, inside the independent
order check's `1e-7` tolerance. The original and continued endpoints nevertheless
have 49 and 23 crossing reports and 18 and 14 unordered contacts. A gap along
the body-height direction and intersection of two sloping triangle planes
measure different things, especially near a nearly closed crease. The contact
penalty also permits small negative gaps. These reports remain grounds for
refusal; changing a drawing offset or relaxing the checker would not repair
material. Very shallow cases need a small, independently understood fixture
before deciding which residual or tolerance should change.

The gallery's JSON exposes those gaps, per-crease errors and reports grouped by
original panel pair. It retains material FOLDs for each endpoint and the last
rejected proposal. Long solves stay outside CI; cheap tests preserve shared
ids, exact added holds, the full independent checker and unchanged solver
results when auditing. A held fixture checks that continuation uses only the
final penalty weight.

An optimized, compiled profile of `original-short` runs two iterations per
penalty stage (eight total). About 68% of the time attributed to the solve is
inside contact-row evaluation, and 31% inside sparse factorization: solving the
coupled linear equations for all free vertices. Contact evaluation computes
both a gap and its derivatives, which say how that gap changes when vertices
move. The scalar energy checks in a line search do not need those derivatives,
but currently pay for them. A value-only evaluation is a bounded performance
follow-up under [#208](https://github.com/avalonalex/senbazuru/issues/208), with
energy equality and unchanged accepted/rejected controls required before any
speed claim.

The complete short profiling process, including setup and diagnostics, reports
65.14 seconds of mutator time (excluding garbage collection) and 281 GB of total
allocation (excluding profiling overhead). This is allocation over time, not
resident memory, and is not a CI benchmark or the full 118-iteration run.
The unprofiled original and held-line solves took 549 and 468 CPU seconds;
the continuation took another 452 CPU seconds. Reproduce the profile without
compiling unrelated gallery modules:

```bash
stack build --profile senbazuru:lib
cat > /tmp/senbazuru-profile-internal.hs <<'HS'
module Main (main) where
import Control.Monad (void)
import CraneInternalGallery (writeInternalTrial)
main :: IO ()
main = void (writeInternalTrial "original-short" "build/internal-profile")
HS
stack --profile exec -- ghc -O2 -prof -fprof-auto -rtsopts \
  -XGHC2021 -XOverloadedStrings -XDerivingStrategies -XLambdaCase -XRecordWildCards \
  -istudy/fold-material -odir /tmp/senbazuru-internal-prof-obj \
  -hidir /tmp/senbazuru-internal-prof-obj /tmp/senbazuru-profile-internal.hs \
  -o /tmp/senbazuru-profile-internal
/tmp/senbazuru-profile-internal +RTS -p -po/tmp/senbazuru-internal -RTS
```


The next geometric experiment should extract one nearly closed shared crease
and its two bending panels, with the same contact order and boundary holds.
Compare signed gaps, triangle intersections and achieved crease angles there,
then carry a verified change back to the retained crane controls. The present
study narrows the numerical failure; it does not prove that the held crane has
no compatible shape. A larger body release, paired wing grips and a continuously
checked flexible route remain separate work under
[#195](https://github.com/avalonalex/senbazuru/issues/195).
