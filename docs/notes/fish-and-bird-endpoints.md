# A base needs an endpoint, not just a crease pattern

A **rabbit-ear fold** gathers a triangular region into a pointed flap and lays
it to one side. A **petal fold** lifts a flap while folding its sides inward,
making a longer, narrower flap. The traditional fish base uses two rabbit ears;
the bird base uses two petal folds on a square base. The
[illustrated instructions](https://origami.me/beginners-guide/) show these
operations. Our fixtures establish their finished shapes before we attempt the
motion; the [glossary](../glossary.md) explains the other fold terminology.

For the fish, take a unit square with corners SW `(0,0)`, SE `(1,0)`, NE
`(1,1)` and NW `(0,1)`. Keep the SW–NE diagonal flat. In the triangle on its
SE side, folding either outside edge onto that diagonal bisects the angle at
SW or NE: the crease divides that angle equally. These two lines meet at
`P = (1-r,r)`, where `r = 1 - 1/sqrt(2) = 0.2928932188134525`.
For example, the SW line has slope `tan(22.5°) = sqrt(2)-1`; intersecting it
with the corresponding NE line gives P. The other half of the square has the
reflected point `Q = (r,1-r)`.

Three creases meet at each of P and Q so far: two valleys towards SW and NE,
and a mountain towards the remaining corner. Laying each pointed flap down
adds a fourth crease. We choose valleys from P to `(1,r)` and from Q to
`(r,1)`, laying both ears towards NE. Choosing the other side would describe a
different endpoint. The diagonal remains a flat guide. These segments make
eight triangles sharing eight material vertices in
[`fish-base.fold`](../../examples/fish-base.fold).

For the bird, start from the attributed
[`bird-base.cp`](../../examples/bird-base.cp) fixture, read through our CP
importer. It already changes screen y, which increases downwards, into model y,
which increases upwards. Translating and scaling those coordinates by
`(x,y) -> ((x+200)/400,(y+200)/400)` gives a unit square. Its four inner
midline points sit a distance r from the centre. Replace the original numerical
noise with those constructed coordinates; preserve the reference's provenance.

That normalization alone is **not our lifted-petal endpoint**. Folding the old
assignments brings all four original corners together. To lift two of them,
add valley hinges between the inner south/east points and between the inner
north/west points. Each hinge cuts one of the old four-sided panels into two
triangles, letting its corner turn independently of the sheet's centre. The
four outer midline segments now stay flat instead of closing as valleys. The
result is sixteen triangles: SW and NE meet at one tip, while SE and NW meet
at the other. This is why
[`bird-base.fold`](../../examples/bird-base.fold) deliberately differs from
the old CP. A test compares their graphs after precisely these six changes.

Here are independent endpoint expectations, in a plane chosen with the long
axis horizontal. A **shoulder** here means either of the two widest points of
the folded outline. Coordinates are model units, not fitted SVG page units.

| Material landmark | Fish | Bird |
| --- | --- | --- |
| SW, NE | `(0,0)`, `(sqrt(2),0)` | Both `(0,0)` |
| SE, NW | Both `(1,0)`, the ear tips | Both `(1,0)`, the lifted tips |
| Shoulders | `(1/sqrt(2), ±r)` | `(1/2, ±(1/sqrt(2)-1/2))` |
| Sheet centre | `(1/sqrt(2),0)` on the flat diagonal | `(1/sqrt(2),0)`, vertex 8 |

The fish's diagonal stays the original length sqrt(2). For the bird, the edge
midpoints meet halfway between tips: each original half-edge still has length
1/2, so opposite tips are one unit apart. The petal hinges join the shoulders;
reflecting a corner across that line moves it from one tip to the other.
`FlapPatternSpec` compares distances between all recorded landmarks, so the
choice of fixed face or camera cannot decide whether the endpoint passes.

Run `stack test --ta='--match flap-base'`. Besides those landmarks, the tests
check agreement at every shared vertex, material lengths and area at three mesh
refinements, measured crease magnitudes, and one valid flat stacking per base.
The study contact checker then checks all 28 fish panel pairs and 120 bird
pairs, using the solved orders. Its distance tolerance is `1e-7` of the sheet
side; touching is allowed. Removing the orders must report unresolved overlaps.
At ±180° the geometry cannot distinguish mountain from valley, so the stacking
check supplies information that the measured angles cannot.

These are zero-thickness endpoints. They do not establish a collision-free
route from the unfolded square or predict paper bending. The next step is to
identify one flap by its original material, supply compatible intermediate
crease angles for its rabbit-ear or petal operation, and repeat the same checks
at those states. Moving vertices along straight lines between these endpoints
would change material lengths and would not establish that motion.
