# How far a sketch is from paper, without solving anything

A pose built by placing vertices can look like a crane and still be a shape no
paper can take. Asking a solver how far it is from paper answers with whatever
the solver finds. A shorter argument answers with a proof.

**Paper cannot stretch, so two of its points never end up further apart than
the shortest way between them along the flat sheet.** On the crane's square
that way is a straight line, so measure every pair of material vertices in the
pose and on the flat square. Where a pair is further apart in the pose, by some
excess *e*, real paper would have to bring those two points *e* closer, and so
some point of the pose must move. That is the *no-stretch floor*
([glossary](../glossary.md#this-project)): the largest such excess over every
pair, halved. On a sheet that is not a convex shape, it is taken over fewer
pairs (below).

On More tucked, the owner's preferred crane sketch:

| Material vertices 37 and 46 | Distance (sheet side = 1) |
| --- | ---: |
| On the flat square | 0.2688 |
| In the sketch | 0.3356 |
| Excess | 0.0668 |

Half of 0.0668 is 0.0334 of the sheet, **20.04 px** at the gallery's 600 px per
side. No other pair is worse. So every shape paper can take, crane or not,
puts some point at least 20 px from where the sketch puts it, if the paper does
not stretch at all. The floor is a lower bound on the distance to every paper
shape, not the distance to the nearest one. Pair 37–46 is not an edge of the
mesh. Taking edges only gives 17.71 px, which is still a bound but not the best
one.

**The halving is not a slip.** The two points can share the correction, each
moving *e*/2 towards the other, so the floor promises only that one of them
moves *e*/2.

**A picture has a floor too.** Projecting onto the page never lengthens a
distance, so the same argument holds for distances measured in the drawing.
In the gallery's upright picture the worst pair is 46–182, at **17.14 px**.
Pair 46–230 gives the same floor to within 2 × 10⁻¹³ px, so either may be
named.

**The straight line has to stay on the paper.** The argument uses the straight
line between two points of the flat sheet, their *chord*
([glossary](../glossary.md#geometry)), because on a convex sheet that is the
shortest way between them along the paper. On a sheet with a notch, a chord
can cross the notch, and then its two ends can end up further apart than the
chord without any stretch. Three unit squares in an L, one arm folded a quarter
turn up and the other a quarter turn down, are paper, yet the arm tips end 2
apart while the chord between them, across the notch, is √2 ≈ 1.41: a floor
over every pair would say some point must move 0.29 of a side. So the floor is
taken over the pairs whose chord stays on the sheet (owner decision 28). Each
pair's excess is a proof on its own, so a floor over fewer pairs is still a
floor; it can only come out smaller. On a convex sheet, such as the crane's
square, every chord stays and nothing changes. A cut sheet is refused instead,
however the cut is stored: a straight line from a point on the cut cannot tell
which side of it the line leaves by.

**Paper may stretch a little.** At a declared strain ε, a pair may be up to
(1 + ε) times its flat distance apart, and the floor shrinks accordingly. At
1% (owner decision 16), More tucked's floor is 19.24 px. PRD 11's target, at
most 1 px, applies to the floor at the declared strain.

The floor is cheap (every pair of 237 vertices) and needs no solver. It says
that no paper comes nearer the sketch than this, not which paper comes nearest
or how near. Finding that takes a solver, and its answer is only as good as the
solver.

`PaperScreen.noStretchFloor` computes it for every pose in the whole-crane
gallery, over the chords `PaperScreen.sheetChords` keeps. The argument is PRD 11's (R-11-3) and its research note
[Y2](../../PRDs/research/Y2-reachability.md).
