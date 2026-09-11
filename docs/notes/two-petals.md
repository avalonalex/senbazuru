# Two petals fold on opposite sides of the packet

Select **Bird base** in the material-study viewer. Its sixteen states begin
with the square base, fold the first petal, fold the second on the underside,
and finally press both flat. A **petal fold** lifts a pointed flap while folding
its sides inward. The [first-petal derivation](petal-fold-motion.md) gives the
angle relationship; the [glossary](../glossary.md) covers the other fold terms.

The original south-east corner makes the first petal. The north-west corner
makes the second. After the square-base collapse these corners coincide, but
they remain different material vertices. The second flap lies at the back of
the packet, so its motion goes below the stationary base plane while the first
petal stays above. It is easier to see that second stage after dragging the
viewer to look underneath. The geometry stays in one reference frame throughout.

Both petals use the same signed angles. If t is a petal's hinge angle, its
four side creases are at -s, where
`tan(s/2) = sin(22.5°)*tan(t/2)`. Its two outer midline folds open from -180 to
zero as `t-180`. For the second petal, the side creases are source edges 20,
21, 24 and 25; the opening folds are edges 19 and 23; its hinge is edge 27.
The second petal's material already faces the other way in the square base.
Negating its crease angles would therefore send it towards the wrong side,
not compensate for that orientation.

During the seven second-petal states, the first hinge stays at 175° and all
its other angles stay fixed too. Tests compare every refined point belonging
to the first petal or stationary body with its position before the second stage.
The final **Completed bird base · press both petals flat** state changes both
hinges from 175° to 180° using their linked angles. The first petal is fixed
during the second-petal stage, not during this final pressing step.

For an independent position check, put `d = 1/sqrt(2)`. In coordinates fixed
to the base, the first tip is
`(1-d/2+d*cos(t)/2, d/2-d*cos(t)/2, sin(t)/2)`.
The second tip has the same x and y at its own angle u, and opposite height:

```
second tip at u = 30°:  (0.952632827254623,  0.047367172745377, -0.25)
second tip at u = 90°:  (0.6464466094067263, 0.3535533905932737, -0.5)
both tips at 180°:     (0.2928932188134525, 0.7071067811865475,  0)
```

These numbers are compared with the folding engine in `PetalFoldSpec`. At the
finished endpoint, the other two original corners still meet at `(1,0,0)`.
The four original edge midpoints meet halfway between `(1,0,0)` and the shared
petal-tip position. The sheet's original centre stays at `(0.5,0.5,0)`.
Tests check all thirteen material vertices against independent coordinates,
and the complete angle list equals
`bird-base.fold`'s endpoint exactly.

The tips' heights are not enough to check the whole flap. The first side
midpoint has height `sin(22.5°)*sin(s)/2`, and the opposite side has the same
height. These are nonnegative for the entire chosen angle range. Every moving
triangle has only these points and vertices in the stationary plane as corners,
so the first petal stays above that plane. The second has the reflected heights
and stays below. This separates the two petals' interiors while they move;
contacts within each petal and with the flat body still need their own checks.

Twenty declared lower/upper relations cover the square, one-petal and complete
bird endpoints after redundant relations are removed. At each flat endpoint,
their implied orders agree with the production solver's unique stacking.
All 120 panel pairs pass a half-degree sweep of the second stage and of the
final press, plus random independent petal angles and mesh refinements.
Removing a second-petal relation exposes an unresolved overlap at the closed
endpoint. Touching is permitted for this zero-thickness model.

The original material lengths and area, shared vertices and achieved crease
angles are checked for both stages. Display-depth ties reuse those checked
orders and leave exported material untouched. This completes the two-petal
study; it does not certify continuous self-collision freedom within a petal,
model paper thickness, or provide a general folding-sequence solver.
