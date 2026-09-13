# Check the turn before handing out its poses

The single-fold demo starts at 15° and ends at 165°. Those numbers describe
the crease angle, not a straight path for each corner. Linear interpolation
between the endpoints shortens the paper; rotation about the crease preserves
distances throughout the turn.

`Origami.Flap` takes the result of `foldFrameWith`, a crease id, an incident
face on the moving side, and signed angular travel in degrees. The ids refer
to the returned cut pattern: cutting a crossing may have renumbered the input.
Removing that crease from the face graph identifies the entire moving flap,
including faces already folded relative to one another. If another path still
joins the two sides, other crease angles must change too. The operation names
the crease and its endpoint vertices and refuses that case.

Only a successful interval check constructs `CheckedFlap`, whose constructor
is hidden. `flapAt` requires that value, so exported poses belong to an accepted
motion. Each pose is re-folded from angles, checking both shared vertices and
achieved angles, then aligned to the original stationary face. Comparing it
with the specified hinge path catches a subtle mistake: when the moving side
contains the folding algorithm's usual anchor, fixing that anchor would export
a different motion from the one checked.

The [fixed-hinge checker](hinge-sweep-contact.md) now lives in
`Origami.HingeSweep`, with static diagnostics in `Origami.Contact`; the study
uses those same implementations. Flap preparation normalizes their geometry
by the original sheet's span so numerical guards do not change meaning with
model units. Exported surfaces keep their original units and material ids.
The interval bounds use floating-point arithmetic with a separation guard,
not formally rounded interval arithmetic.

Run the [demo](../usage.md#checked-flap-motion). The recorded single fold clears
in seven interval checks, with relative edge-length error below `3e-16` in its
four saved states. The opposing-flap route, 105° to 121° with the other flap
held at 145°, clears in one check. A full turn returns to its starting position
but is refused: faces 0 and 2 cross at progress 0.125. That is a witnessed
collision, not a guarantee of the earliest impact time.

This first operation accepts separated, convex planar panels. Flat touching
endpoints remain refused; it does not infer their layer order or exempt them
from interval checking. Stale face orders are discarded. Physical thickness,
several creases moving together, and a checked complete bird sequence remain
separate work under #54/#55/#61. This handoff is
[#175](https://github.com/avalonalex/senbazuru/issues/175).
