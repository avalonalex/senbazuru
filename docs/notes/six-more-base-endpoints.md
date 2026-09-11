# The outline cannot identify a folded base

The traditional boat and pig bases both fit the same hexagon: a rectangle
one unit wide and half a unit high with four triangular corners cut away,
each with two perpendicular sides of length 1/4. But boat's original corners meet in pairs at opposite tips, while
pig's four corners all meet at the centre. A silhouette test would accept
either one in place of the other. Checking where the original material points
end up distinguishes them. The [glossary](../glossary.md) explains base,
crease, mountain, valley, squash fold and petal fold.

[`BasicBases`](../../study/fold-material/BasicBases.hs) constructs six closed
endpoints from material creases on a unit square. `BasicBaseSpec` checks the
distances between every pair of recorded material landmarks. Distances do
not depend on the camera or on which panel the folding engine holds still.
Here are the independent expectations; a **shoulder** means a widest point
of the folded outline. All distances use the original square's side as one.

| Base | Construction | Distinguishing landmarks | Panels / contact pairs |
| --- | --- | --- | --- |
| Helmet | Diagonal fold, then both corners of the doubled triangle to its tip | All four original corners coincide; outline is a square of side 1/2 | 6 / 15 |
| Organ | Book fold, then squash its two side flaps | Bottom corners stay one unit apart; top corners meet halfway between them; roof shoulders are at `(1/4,1/2)` and `(3/4,1/2)` | 6 / 15 |
| Frog | Four squash folds and four petal folds on a square base | Original corners meet at the long tip; original centre is `1/sqrt(2)` away; edge midpoints are 1/2 from that tip | 32 / 496 |
| Boat | Cupboard fold, then open both ends into two roofs | Original corners meet in pairs at tips one unit apart | 9 / 36 |
| Pig | Squash the four corners of a cupboard fold | All original corners meet at the centre; opposite edge midpoints make the outer tips | 11 / 55 |
| Diamond | Kite fold, then fold the opposite edges inward through both layers | SW–NE stays length `sqrt(2)`; SE and NW meet one unit from SW | 7 / 21 |

Helmet, organ, boat and pig use only halves and quarters. Their preparatory
creases do not all remain active: for example, pig's two vertical cupboard
guides lie flat after the corners are squashed. Adding closed folds there
would describe a different, incompatible endpoint.

Diamond's kite creases bisect the 45° angles at SW. Write
`d = 1/sqrt(2)` and `h = sqrt(2)-1`. The next two hinges meet them at
`(d,1-d)` and `(1-d,d)`, and continue to NE. The parts through the turned-over
layers run to `(1,h*h)` and `(h*h,1)` and are mountains where the front layer
uses valleys. These coordinates were also checked by applying
`creaseThroughLayers` twice to our kite fixture: the requested line must be
mapped through the held panel's rigid transform, because that panel need not
be the central one.

For frog, consider the triangle from SW to SE to the sheet centre. Its
two new side creases bisect the corner angles. Intersecting those lines with
the centre's angle bisectors gives shoulders
`A = (1/2-r,r)` and `B = (1/2+r,r)`, where
`r = (1-1/sqrt(2))/2 = 0.14644660940672627`.
The petal hinge A–B crosses the old midline at `(1/2,r)`.
Repeat this construction around all four sides. Two opposite original
diagonals remain flat. The inner midlines turn mountain during the squash
folds; their outer parts turn valley when the petals lift. This leaves
fourteen active creases at the centre and twelve interior vertices with
four active creases each. In the folded plane the shoulders are
`(d/2, ±r)`, the four long tips coincide at `(0,0)`, and the centre makes
the shorter tip at `(d,0)`. Its outline area is `d*r`, while the material
area is still one.

The six sources have 638 panel pairs altogether. Tests check shared vertices,
lengths and area at three mesh refinements, achieved crease magnitudes,
and exactly one complete flat stacking per base. At ±180° the normals cannot
distinguish mountain from valley; the stacking test supplies that information.
Those orders then pass the separate panel contact check with a tolerance of
`1e-7` of the sheet side. Removing the orders must expose unresolved contact.
Finally, projected visible pieces must cover the expected outline exactly
once from above, below and obliquely. This checks for hidden overlapping fills
and missing paper as well as the folded geometry.

These are zero-thickness endpoints, not a collision-checked folding route.
The layer-spread SVGs shift faces on the page and do not predict paper
thickness. The next study can open one of frog's squash folds and derive
compatible moving crease angles, as was done for the bird's petals.

Construction references:
[helmet](https://origamiguides.com/helmet-base/),
[organ](https://origami.guide/beginner-origami/origami-base-folds/origami-organ-base/),
[frog](https://origami-resource-center.com/frog-base/),
[frog crease diagram](https://markfiend.wordpress.com/2012/01/27/frog-base-extended/)
(the first, traditional diagram, not the author's extended design),
[boat](https://www.jessieathome.com/origami-boat-base/),
[pig](https://origami-instructions.com/origami-pig-base.html?no_redirect=true),
and [diamond](https://origami.guide/beginner-origami/origami-base-folds/origami-diamond-base/1).
We generated the coordinates and assignments from these traditional
constructions; no tutorial images, diagram files or third-party code are
included.
