# One panel can meet itself

Take an uncreased strip, one model unit long and 0.3 wide, and curl it back
towards its starting edge. All its triangles belong to one panel: a panel is
the paper between deliberate crease lines. Saying that this panel is above
itself is meaningless. We need to distinguish the two **material regions**
that meet, without inventing a crease or splitting the panel's identity.

`SelfContactExample.curledPanel` divides the strip into eight spans along its
length, each containing two triangles. It starts with a 40° bend between spans.
Each span is positioned using its original length and a turned direction,
preserving the starting triangles' lengths. Passive bending springs prefer
0°, as for ordinary flat paper. Additional `BendControl` springs prefer 60°
and have four times the passive stiffness. These represent an imposed curl:
they are explicit experimental controls, not natural crease memory. Without
contact, the two preferences balance at `(0 + 4 * 60) / 5 = 48` degrees.
That curl makes the end cross the beginning.

`SurfaceContact.prepareTriangleContact` supplies lower/upper triangle ids
directly to the existing directional separation solver. Here the first eighth
of the strip stays below the last eighth along the model's vertical direction.
There are four triangle pairs, all inside the same source panel. The prepared
model retains their ids and original material coordinates; changing triangle
numbering requires preparing a new model. Overlap corners and their gradients
(how the gap changes when vertices move) use the existing clipping arithmetic.
The solver therefore responds to moving contact points rather than positions
saved at the start.

As with whole-panel orders, this bounded model refuses cycles (a chain of
below/above requirements returning to its starting triangle) and includes
transitive relationships: if A is below B and B below C, it also requires A
below C. Each resulting pair must have disjoint material vertices. Neighboring
triangles stay governed by their shared connection and bending springs, and
the independent endpoint check still inspects them. A `1e-6` numerical
clearance keeps tolerated residual error from becoming penetration. It is
separate from physical thickness; coincident positions never weld distinct
material ids.

Run `stack run senbazuru-material-study -- --bending build/fold-material` and
select **Curled panel · self-contact**. From the same initial mesh and controls,
the unconstrained solve settles at 48° with three crossing triangle pairs and
about `0.01505` model units of reversed separation. With local contact, the
solve settles in 40 iterations. All 120 independent triangle-pair checks pass;
the largest relative material-edge error is `9.37e-8`, and the smallest local
gap is about `9.999e-7`. The controlled bends range from 47.69° to 48.32°, with
small bends across the span diagonals too. The endpoint retains one connected
mesh and one source panel. The viewer uses the actual positions and draws only
the material boundary unless the triangle overlay is enabled.

The test with sixteen spans exposes another kind of contact: its unconstrained
24° bends complete a fifteen-sided loop, then overlay the first span. The
independent check reports coplanar overlap, meaning two triangles occupy area
in the same plane. The local correction separates these ends too. Tests also
compare gap gradients against finite differences, check rotated coordinates,
refuse neighboring requirements and changed material, and distinguish imposed
bending controls from creases. All eight previous gallery results are unchanged.

This is [#162](https://github.com/avalonalex/senbazuru/issues/162). The triangle
pairs and their direction are supplied, not discovered from arbitrary bending.
At least one triangle in each pair must admit a height along that direction;
the existing solver refuses pairs standing parallel to it. Acyclic directional
orders cannot represent every self-contact arrangement. The result establishes
an endpoint under illustrative controls, not a calibrated material law or a
collision-free route. General bending motion is still outside the
[rigid hinge-sweep check](hinge-sweep-contact.md).

[Local discovery](local-contact-discovery.md) in #164 adds a separate control
that learns nearby triangle partners from a separated reference pose.
