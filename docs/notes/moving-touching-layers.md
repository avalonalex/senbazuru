# Touching layers can travel together

Take a unit square with vertical creases at material x = 0.4 and x = 0.8.
Fold the narrow right panel onto the middle panel, then lift the middle panel
through 90°. The narrow panel travels with it. These are two layers of the
same sheet, still joined at their original crease; they are not two separate
objects or vertices welded because their folded positions coincide.

The original [flap demo](../usage.md#checked-flap-motion) recorded the narrow panel as
face 2 above face 1, against face 1's normal. A normal is the direction
perpendicular to the panel given by its vertex winding; see
[the glossary](../glossary.md). That direction turns with the panel. Keeping
the same FOLD order when the stack becomes upright, or turns over, preserves
which material side touches which. A comparison against world height would
lose that information.

The geometric argument is small. Apply the same rigid rotation and translation
to two triangles: their distances and relative positions cannot change. A
coplanar overlap at the start therefore remains contact throughout the turn.
The same argument covers two stationary layers. It does not apply when one
triangle moves and the other stays still, even if they touch at the start.

`Flap` retains supplied nonzero face orders only within one motion group and
one plane. Each overlapping pair needs an explicit order; this first version
does not infer missing relations through other layers. It checks consistency
on each panel's plane with `Layers.layerDepths`, including upright stacks,
then maps those relations to the shared mesh's triangles.
`HingeSweep.checkSweepWithRigidContacts` separately verifies that each declared
pair is coplanar and has the same motion. Every other pair retains the ordinary
contact check, including different pairs involving either of those triangles.
New contacts at a flat endpoint must also agree with the retained stack order.

In the recorded run, forming, lifting and lowering each clear in one interval
check, with maximum relative material-edge error below `9e-16` in the saved
states. The order `[2,1,1]` survives every lifting and lowering pose and both
glTF scenes. The opposing-flap control adds a narrow layer to the right flap:
its 16° move clears, but a full turn reports both right layers crossing the
fixed left flap at progress 0.125. That is a collision witness, not the first
impact time. Tests also cover a three-layer stack, cyclic orders and closing
the moving stack onto the stationary panel.

Coplanarity uses the same `64 * 2^-52` allowance on a normalized unit sheet as
the [endpoint rule](flat-flap-endpoints.md); positions are not snapped or
separated. This is a zero-thickness numerical model. The narrow demo layer
stops short of the lifting crease. The demo now uses equal-width panels with
the separate [free hinge edge rule](free-edges-on-a-hinge.md). Sliding,
changing internal stack angles, several hinges moving together, and panel
bending remain separate work.
