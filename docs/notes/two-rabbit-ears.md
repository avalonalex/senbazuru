# The fish's two ears stay on opposite sides of the diagonal

Select **Fish base** in the material-study viewer. The first eight states
gather the south-east corner into a rabbit ear, a pointed flap made by
bringing together a triangular part of the sheet. The next seven gather the
north-west corner the same way. Throughout the second stage the first ear
holds its last pose, with mountain magnitude 175°. This small opening keeps
the layers visible; it is an inspection choice, not a prediction of paper's
spring-back. Both ears are nearly closed in the final view.

The [single-ear derivation](rabbit-ear-motion.md) gives four linked crease
angles for one ear: `[v(m), m, −m, v(m)]`. Here m is the positive mountain
magnitude and v is its paired valley angle; the [glossary](../glossary.md)
defines mountain and valley. The second ear uses the same four angles at
the reflected crease vertex. After the seven boundary/flat-guide zeroes,
the fish's angle list therefore contains two copies of that four-angle
expression, with independently chosen m values. The first stage uses
`(m₁,m₂) = (m,0)`; the second uses `(175°,m)`.

Reflecting the original sheet across its SW–NE diagonal exchanges x and y.
The second ear's folded positions exchange x and y too, while keeping z:
both ears rise above the fixed paper. Its angle signs stay the same because
the folding traversal crosses the reflected panels in the opposite order.
Negating those angles instead would fold the second ear below the paper;
the order test reports that even without a crossing.

For example, with the first mountain at −175° and the second at −90°, the
original north-west corner reaches `(0.670210, 0.722390, 0.170210)`. The first
ear's tip remains at `(0.707138, 0.707033, 0.007840)`. These are rounded
measurements from `StudyCase.buildPose`; `RabbitEarSpec` compares both moving
landmarks with the reflected rotation equations and checks every subdivided
point in the first half against its preceding pose.

Individually valid ears still need an interaction check. For this particular
motion, a plane separates them: all points with `x = y`, at any height,
form the vertical plane through the original diagonal. Using the first ear's
tip B and east-edge shoulder E from the earlier derivation gives:

```text
xB − yB = (1 + cos v) / 2
xE − yE = (1 + cos m) / (2√2)
```

Both quantities are nonnegative for angles between 0° and 180°. The first
ear's other vertices lie on the diagonal or at its fixed crease centre,
where `x−y = √2−1 > 0`. Every panel is a triangle, so every point inside it
is a weighted average of those corners with nonnegative weights. It stays
in `x ≥ y`. Reflection puts the second ear in `y ≥ x`. Their interiors
therefore cannot cross each other in this selected family, even when the
ear angles differ. This argument concerns the two ears' interaction; it
does not check whether panels within either ear cross one another.

The gallery still runs all 28 panel-pair checks on every recorded state.
Six stable order requirements put each ear's three moving panels above its
fixed central panel. There is no order between the ears: they can meet at
the separating plane but their interiors do not overlap. Within an ear,
the vertical order changes during the turn, so the final stacking is checked
separately. At exactly 180° the full chains are:

```text
centre-south < south-panel < ear-tip   < east-panel
centre-north < west-panel  < north-tip < north-panel
```

The production flat-stacking solver finds precisely these two chains and
one valid stacking. The ear tips meet at `(1/√2,1/√2,0)` and the shoulders
at `(½,½,0)`, with distinct material vertices retained at coincident positions.
The final angles equal `fish-base.fold`'s existing endpoint exactly.
Removing the extra within-ear orders leaves six overlapping pairs correctly
reported as unresolved.

Run `stack test --ta='--match rabbit-ear'`. Tests cover both stages, half-degree
contact sweeps including upright panels, independently chosen pairs of ear
angles, material lengths and area, shared vertices, measured crease magnitudes,
and the complete closed endpoint. The separation argument above does not
extend to arbitrary folds or finite paper thickness; continuous self-collision
checks within each ear and the bird's petal-fold motion remain future work.
