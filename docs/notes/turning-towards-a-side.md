# Which way a turn goes is read from the paper that moves

A hinge turn in `Senbazuru.Origami.Flap` is given as a *travel*: the signed
change in the first hinge crease's FOLD angle. An instruction says something
else. "Fold in front" means the paper that moves sets off towards the reader.
`prepareFlapToward` turns the second into the first, and what it has to read
to do so is this note's one point.

**A positive change moves the face beside a crease towards that face's own
top.** A face's top is the side facing +z on the flat sheet. Its *placement*,
the rigid motion folding gives the face, carries that side wherever the face
goes. The rule holds for either face beside the crease and from any flat
start. From 0, a valley lifts the moving face off its top. At +180 the moving
face lies folded over, upside down, and a further positive change pushes it
down into the paper under it: again towards its own top. So the moving face's
way up alone signs the turn. Towards +z is positive for a moving face lying
top up and negative for one lying upside down.

**The face held still gives the same answer only on an open hinge.** There the
two faces beside the crease are one flat sheet and lie the same way up. The
first version of `prepareFlapToward` read the held face. On a hinge already
folded shut the two faces lie opposite ways up, so it answered the other way.
In the blintz, which folds the four corners of a square to its centre, a
corner folded under the centre comes back out by `TowardMinusZ`, since it sets
off away from the reader. The held-face reading called that turn
`TowardPlusZ`.

**Every hinge crease's moving face is read, and the readings must agree.** A
turn about a line lifts the paper on one side of the line and lowers the paper
on the other, so which way a face sets off depends on which side of the hinge
line it lies. A [page turn](../glossary.md#origami) is where reading the held
face failed, because the page is joined to paper on both sides of the line.

- *The example.* Take `examples/square-base.fold`, with its spine crease
  relabelled so that the flap code will turn it. The bottom page on one side,
  faces 6 and 7, is held by face 5 across the spine (edge 14) and by face 0
  above it (edge 8).
- *The old reading.* Asked to turn the page towards −z, the held-face reading
  turned it away from the reader with edge 14 listed first, but up into face 0
  with edge 8 first.
- *The new reading.* The page's moving faces lie on one side of the spine, so
  reading them gives one turn either way: edge 8 opens and edge 14 closes.

When the moving faces beside the hinge lie on both sides of its line, no one
direction fits them, and the turn is refused as `FlapMovesBothWays`. Only
faces beside the hinge are read. Paper further out that folds back across the
line turns the other way without being refused, since the direction is decided
where the paper leaves the hinge.

**Each of those faces must lie flat.** One standing on edge shows neither side
towards +z. One tilted past vertical has a way up, but it reads the turn that
finishes its own fold as the opposite way: a flap folded in front to 120°
completes that fold by moving down. So a moving face that does not lie flat is
refused as `FlapMovingNotFlat`, judged by the library's usual `hasRelief`.

The cases are pinned in `test/Senbazuru/Origami/FlapSpec.hs` ("turning a
page") and `test/BlintzSequenceSpec.hs`. The decision is owner decision 13,
recorded under D5 in `PRDs/decisions.md`, and
`PRDs/research/E3-formal-fold-semantics.md`, section G, has the argument and
its sources.
