# Check the route, not just its endpoints

Start the opposing-flap sheet at 145° / 105° and rotate the right flap one full
turn around its crease. The endpoint is the starting pose again. Both pass all
276 independent triangle-pair checks, yet the route passes through the other
flap. The new check finds a witness 45° into the turn, with six crossing pairs.
Its largest relative material-edge error is below `9e-16`: the problem is
intersection, not stretched paper. These measurements come from
`stack run senbazuru-material-study -- --bending build/fold-material`; choose
**Opposing flaps · first contact → Rejected route · full turn**.

An endpoint does not specify the route taken to reach it. `HingeSweep` therefore
takes a fixed hinge line, signed angular travel and the material vertex ids that
rotate. Each triangle must move wholly with the flap or stay stationary; shared
vertices lie on the hinge and remain fixed. The private constructor enforces
these conditions. Positions follow the rotation, never interpolation between
endpoints, so the movement preserves the starting triangle shapes.

To check a whole angular interval, project the triangles onto a measuring line.
Disjoint projected ranges imply disjoint triangles: this is the
[separating-axis principle](https://www.geometrictools.com/Documentation/MethodOfSeparatingAxes.pdf).
A rotating vertex's projection has the form `c + a*cos(angle) + b*sin(angle)`.
Its minimum and maximum can occur inside the interval, not just at its ends.
`HingeSweep` includes those interior extrema and tries several measuring
directions. One separated direction is enough to clear a pair for the entire
interval. Failure to find one is not evidence of a collision; subdivide the
interval and try again, using independent static triangle checks for witnesses.

A lawful shared crease prevents strict separation. Here the stationary
triangle's plane can still separate the moving triangle's interior throughout
the interval. This exception requires the hinge to lie in that plane and checks
that boundary overlap contains only shared material. Merely sharing a corner
is insufficient: a rotation axis through that corner can leave the plane, and
an edge can pass through the stationary triangle even while the moving vertex
stays above it. Tests cover both shared-corner cases and subdivided hinges.

The result is **clear**, **collision witness**, or **unresolved**. A witness is
not the first impact time. The default limits are 20 subdivisions along a
branch and 4,096 visited intervals; exhaustion refuses the route. This is a
floating-point check for unit-sheet experiments, with a `1e-10` separation
guard and a `1e-12` hinge-distance tolerance. The bounds are not formally rounded
outwards to account for every floating-point rounding error. Coplanar overlaps
(triangles lying in the same plane) or very close unrelated boundaries can
be blocked or left unresolved. The current path supports one rigid rotation of
at most 360°, not arbitrary bending, several moving axes, or finite thickness.

`ContactDiscovery.observeContactSweep` requires the motion to start at the last
accepted pose. Its endpoint must match the separately crease-angle-derived
pose within `1e-12`, with identical material coordinates and triangles. Only a
clear route proceeds to the existing order and endpoint checks; failure adds
neither relationships nor observations. All four supplied approach rotations
clear, while the full-turn route is rejected. The eight existing gallery runs
retain their meshes and measurements. Raw `observeContactPose` calls still
check sampled poses only, and numerical correction iterates have no checked
motion between them. This bounded step is
[#160](https://github.com/avalonalex/senbazuru/issues/160); general continuous
collision handling remains [#61](https://github.com/avalonalex/senbazuru/issues/61).
