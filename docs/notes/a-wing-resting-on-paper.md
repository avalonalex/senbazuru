# A wing can lift while its crease keeps touching

The crane fixture has both wings folded flat. Lowering one wing needs a new
crease across it: the fixture describes the crane before that step. In the
fixture's folded coordinates, the wing tip is `(1, 0, 0)`. The study puts the
new hinge on `y = 0.25`. Mapping that line back through each face's fold
transform gives four connected crease segments on the open sheet. They cross
four faces of the wing that contains the sheet's `(0, 1)` corner, forming two
touching layers in the folded crane. The other wing stays still.

The moving hinge lies over the other wing's interior. Earlier checks required
contact at a shared material crease, or a free edge supported by a known
stack's shared crease. Neither describes this contact: the two wings are
different parts of the sheet and their touching points must keep different
material ids. Adding a crease to the stationary wing would subdivide that
surface but would not change the contact that needs checking.

The useful fact is about a plane, the flat surface extended beyond the edges
of a panel. When the hinge lies in that plane, a moving point's signed distance
from it is its initial perpendicular distance from the hinge, multiplied by
`sin(turn angle)`. All the wing's points away from the hinge start on the same
side of it. During this 90-degree turn the sine keeps one sign, so the moving
interior stays strictly on one side of the stationary plane. Only points on
the hinge can keep touching. The stationary panel may extend across both
sides of the hinge without invalidating this argument.

`HingeSweep.checkSweepWithLayerContacts` accepts candidate initially coplanar
pairs for this check. It verifies their different motions and coplanarity,
requires the hinge and moving endpoint in the stationary plane, and checks
one-sided departure over at most a half-turn. Near-axis corners fixed by
preparation must also meet the tighter contact allowance. Naming a pair never
skips those checks. The old entry points keep their stricter policy.

Geometry supplies a departure side; it does not choose the starting stack.
`Flap` compares the resulting orders with the crane's initial layer order.
Turning the selected wing the other way fails that check even though its final
open pose has no crossing. Pairs that only meet along an edge need no invented
order, but still need their separation checked. Orders between layers that
move together remain unchanged. There is no visual displacement or welding.

Reproduce this with `stack run senbazuru-material-study -- --crane
build/fold-material`. `checks.json` records the successful turn and the
wrong-direction refusal. Independent tests measure lengths, shared vertices,
achieved angles, fixed faces and contact at intermediate poses; the sweep
covers the intervals between poses. This remains a guarded floating-point
check of one authored rigid rotation. Returning the wing onto a resting
surface, opening the second wing and coordinating either with body expansion
are separate steps.
