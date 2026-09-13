# Two petals can share a stationary separating plane

The [first-petal certificate](checked-petal.md) checks a pointed flap lifted
from the square base while its sides fold inward. The complete bird-base route
uses three stages: the front petal reaches 175°, the back petal folds underneath
to 175° while the front stays still, then both reach 180° together. The small
opening before pressing makes the layers easier to see. This starts with an
already collapsed square base; its initial collapse is separate work.

In figure 11 of `--petal`, the held front tip is approximately
`(0.2942385962, 0.7057614038, 0.0435778714)`. The back tip is
`(0.6464466094, 0.3535533906, -0.5)`. These are original model coordinates from
`checked-petal/sequence.fold`, not page coordinates. They show why the back
petal needs its own material identity and why an underside view helps: it is
below the packet even though its crease angles have the same signs as the
front petal's. The [two-petal construction](two-petals.md) derives that geometry.

Each petal moves three vertices. The back tip is material vertex 3; its
shoulders 6 and 7 follow reflected copies of front vertices 5 and 4. Reflecting
height preserves lengths, but the checker still verifies all 28 material edge
lengths as exact polynomial identities. There is one path per material vertex,
so neighbouring triangles stay joined. The remaining seven vertices stay fixed
during the final press.

The same positive-denominator construction as the first petal checks all 120
panel pairs in each stage. The original candidate separating planes came from
the triangles and their edges. Eleven pairs between opposite petals could not
be resolved by those candidates over the whole second turn. Adding the
stationary plane `z = 0` resolves them: every front-petal vertex has nonnegative
height and every back-petal vertex nonpositive height. At least one corner of
each moving triangle is strictly away from the plane throughout the open turn.
Consequently every point strictly inside that triangle is also away from it.
The code proves those signs with the same exact polynomial bounds; it does not
skip pairs based on a petal label. A failed bound still refuses the route.

The held front petal is represented by the exact rational value of the
computed parameter `u = tan(175°/2)/(1 + tan(175°/2))`. This is a precise ideal
pose close to the floating-point angle-derived one, not the exact mathematical
value of that trigonometric expression. Its coordinates retain exact material
lengths because the rational path identities hold for every parameter value.
The comparison tolerance remains `1e-12` of the unit sheet's side.

Each certificate covers a full 0°–180° turn. The route uses the first two
certificates' 0°–175° prefixes, and the simultaneous-turn certificate's
175°–180° suffix. This avoids inventing a vertex interpolation for pressing.
The certificates check 71, 48 and 92 overlapping panel pairs across their
respective endpoint configurations. These counts include the unused ends of
the larger certified intervals; they are not counts of extra route stages.

For the second certificate, some endpoint panels are still in the air. An
overlap of their shadows does not imply contact. The checker first establishes
that two panels occupy the same plane, then clips their projections and checks
their approach or departure against the required order. Endpoint panels must
have nonzero projected area. Fixed pairs also need a separation proof or a
coplanar ordered contact; they are no longer assumed to belong to a flat body.

`CheckedBird` retains the fixture and requirements accepted by `CheckedPetal`.
At both stage joins it compares positions, crease angles, connectivity,
original material coordinates and resolved layer requirements. Requested poses
are rebuilt by the folding engine, which checks shared vertices and achieved
angles, then compared with the certified ideal positions and checked for
contact. Removing the back petal's landing order leaves the first certificate
valid but refuses the complete sequence. Sending the back petal above the
packet is another rejected control.

`--petal` exports sixteen FOLD states, sixteen GLBs and two SVG pages with a
common camera and scale per page. All geometry remains zero-thickness paper.
The exact result covers these known paths, not arbitrary paired angles,
finite-thickness contact, or an algorithm to discover folding instructions.
