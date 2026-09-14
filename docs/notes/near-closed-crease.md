# Near a plane is not on its intersection line

The [crane diagnosis](internal-crease-diagnostic.md) reports crossings beside
two nearly closed folds. Before changing the material model, use one shared
crease between two bending rectangles whose geometry has a known answer.
The [glossary](../glossary.md) defines material coordinates, panels and creases.

```bash
stack run senbazuru-material-study -- --closed-crease build/fold-material
```

The unit square has material coordinates from `-0.5` to `0.5` on both axes.
It folds at `x=0`. Each half follows four segments of length `1/8` in its
folded side profile, extended along the crease direction. Only three crease
vertices belong to both halves; coincident material elsewhere stays distinct.
The segment directions can turn, representing bending within a panel. They
are not additional authored creases, and there is no physical thickness.

A rational number `t` gives the exact unit direction
`((1-t²)/(1+t²), 2t/(1+t²))`. Rotating segments this way preserves their
lengths; extending them perpendicular to the profile preserves the lengths
of every triangle edge, including diagonals. The lower profile uses
`t = 0, 1/10, 1/5, 3/10`. The flat control uses zero throughout. The upper
profile applies an additional rotation: zero for touching, `1/20` for opening,
and `1/100` on the first segment then `-1/100` on the rest for crossing.
The microscopic controls replace their opening parameter with `1/100000000`.

Both profiles progress in positive folded x. At a given x, subtracting their
heights gives the upper-minus-lower gap. That gap is linear between their
combined segment endpoints, so its extrema and zero crossings can be computed
with exact `Rational` arithmetic, independently of the triangle checker.
The mesh receives `Double` coordinates from those profiles. This separates
the ideal construction from its finite-precision representation.

For the 32-triangle mesh, the bent touching control has exact zero gap.
The ordinary opening reaches about `0.0568` sheet lengths. The crossing starts
above its partner, meets it again at x ≈ `0.2458`, then reaches a minimum gap
of about `-0.00610`. Reversing all upper rotations instead places the upper
panel below the lower without an interior crossing. This is why intersection
and layer order require separate checks.

The microscopic crossing is real in the ideal construction: its minimum gap
is about `-6.21e-9`. The production checker passes it at its existing `1e-7`
distance tolerance. This is an explicit limit, not an accepted shape. Raw
contact-force gaps still record the negative value. Subdividing each segment
gives 64 triangles with exactly the same reference geometry; the tests also
check 128 triangles for material and profile identities. This refinement
checks subdivision sensitivity, not convergence towards a smoother curve.

The investigation exposed a different problem in the crossing predicate.
Consider these two triangles, in `(x,y,z)`:

```text
lower: (-1/4, 0, 0), (1/4, 0, 0), (1/80, 1/2, 0)
upper: (-1/4, 39/80, -2.5e-7), (1/4, 39/80, 2.5e-7), (0, 3/4, 0)
```

Their planes meet on `x=0`. The actual lower triangle ends on that line at
`y=10/21`; the upper starts at `y=39/80`. The intervals are separated by
`19/1680`, so these triangles do not cross. But the lower apex at `y=1/2`
lies only about `1.25e-8` from the upper plane. The old checker included that
nearby corner in the plane cut, incorrectly extending the lower interval to
`1/2` and reporting an overlap.

A small distance to a nearly parallel plane need not mean a small distance
to the planes' intersection line. `Origami.Contact` now constructs the actual
cut from edge-plane intersections and exactly on-plane corners. The existing
tolerances still decide whether each triangle straddles the other plane and
whether their cut intervals overlap substantially. Moving the upper base to
`15/32` creates a real crossing that remains rejected. Regression tests repeat
both cases with reversed winding and a rotated, translated coordinate system.

This is a checker correction, not a contact-force repair. The same change can
be applied to saved crane endpoints without rerunning their long solves:

```bash
stack run senbazuru-material-study -- --closed-crease --recheck-crane \
  build/fold-material/crane-internal build/fold-material
```

The command requires all six FOLDs from the earlier diagnostic and verifies
their material coordinates and triangle identities before checking them.
It writes `closed-crease/crane-recheck.json` without replacing old reports.
Rechecking the saved #215 endpoints on 2026-09-14 gives:

| Control | Previous crossing reports | Corrected reports |
| --- | ---: | ---: |
| Original | 49 | 49 |
| Crease lines held | 19 | 13 |
| Internal forces only | 282 | 280 |
| Held lines + internal forces | 375 | 365 |
| Whole patch held | 0 | 0 |
| Original continued | 23 | 15 |

Reversed and unordered counts are unchanged. Every formerly failed control
still fails contact; the whole-patch-held reference still passes. An independent
rational calculation on the saved coordinates checked all 26 removed reports:
22 have disjoint cut intervals, and four have positive overlap below `1e-7`.
The largest of those four overlaps is about `1.63e-8`. Thus removing an
inflated cut can remove either an invented intersection or a real intersection
smaller than the unchanged interval tolerance. It does not prove that every
remaining or unreported contact is exact.

The small gallery shows same-scale profiles and a separately magnified gap
plot. Only the ordinary touching/opening controls get 3D views: GLB rounds
positions for display and cannot preserve these microscopic separations.
All controls retain diagnostic FOLDs and exact reference fractions in JSON.
No equilibrium solve or checked motion is claimed here. The subsequent
[contact-correction experiment](contact-correction-at-a-crease.md) uses the
held lower panel as a reference for a solved upper mesh. It measures remaining
penetration instead of assuming a small force residual proves nonintersection.
