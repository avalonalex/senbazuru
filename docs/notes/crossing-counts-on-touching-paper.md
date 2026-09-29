# Counting crossings on paper that touches itself

A folded crane body at rest is paper lying on paper. The material study gives
paper no [thickness](../glossary.md#this-project), so wherever one layer rests
on another, a corner or an edge of the upper triangle lies in the plane of the
triangle below. It lies there only up to rounding and the solver's last step:
a few ten-millionths of the sheet above that plane, or below it. A test that
asks "do these two triangles pass through each other?" is then answering, pair
by pair, which way that residue fell. **Count how deep paper goes, not how many
pairs cross.**

## Three checkers, three answers

The saved body `study/fold-material/fixtures/whole-crane-body.fold` has 120
triangles, so 7,140 pairs. Three checkers were run on it, and none of the pairs
they flag share a vertex.

| Checker | A pair crosses when | Pairs |
| --- | --- | ---: |
| The study, `Senbazuru.Origami.Contact` | each triangle reaches more than `1e-7` past the other's plane, and their cuts along the planes' meeting line overlap by more than `1e-7` | 2 |
| PRD 11's Y1 counter | an edge of one passes through the inside of the other, by more than `1e-9` of the edge's length | 48 |
| ipctk 1.6.0, `is_edge_intersecting_triangle` | an edge of one meets the other, by ipctk's own test | 58 |

The Y1 counter reported 13 of its 48 "deeper than `1e-7`", 5 "deeper than a
thickness" and the deepest at "31 t", where t is 1/1500 of the sheet's side
(0.1 mm on 15 cm). [PRD 11](../../PRDs/11-prd-refined-final-forms.md) carried
those numbers.

Neither count is stable. Loosen the study's `1e-7` to `1e-8` and its 2 pairs
become 4; at `1e-9`, 17. At `3e-7`, none remain. The Y1 counter finds 58, 48,
14 and 3 pairs at `1e-12`, `1e-9`, `1e-7` and `1e-6`. Add uniform noise of at
most `1e-8` to every coordinate, which is 0.000006 px at the study's 600 px per
sheet side, and over three seeds the study's count is 0–2 and the Y1 counter's
28–47. With noise of at most `1e-9`, its count "deeper than a thickness" is 2,
4 or 6, although the noise is at most 1.5 millionths of a thickness.

## Reach-through

The number that does not move is the **reach-through** of a pair of triangles.
For each triangle, find how far its corners go on each side of the other
triangle's plane, and keep the shorter of the two: that is how far the triangle
reaches past the plane. The reach-through is the **smaller** of the two
triangles' reaches. Move the triangle with the smaller reach that far along
the other's [normal](../glossary.md#geometry), towards the side it mostly lies
on, and it ends on one side of the other's plane, touching it at most. So no
pair passes further through than its reach-through.

*The smaller* can look like a typo, since depth usually means the larger. Take
a card standing on a table with its bottom edge sunk `1e-9` into the top. The
table reaches far past the card's plane, on both sides. The card reaches only
`1e-9` past the table's plane, and lifting the card by that much frees it. The
larger reach measures how big the table is.

On the fixture, the largest reach-through over all 7,140 pairs is **`2.42e-7`
of the sheet side**, at pair 46–70:

| | Value |
| --- | ---: |
| At the study's 600 px per side | 0.000145 px |
| On a 15 cm sheet | 36 nm |
| As a fraction of a thickness | 0.00036 t |

Moving one triangle of each of the Y1 counter's 48 pairs by its reach-through,
plus `1e-12`, separated all 48. An independent segment test and ipctk both
agreed. Under the noise above, the largest reach-through stayed between
`8.4e-8` and `2.5e-7`.

## Why the other two measures looked deep

The Y1 counter's "depth" belongs to the edge that passes through. It is the
shorter of that edge's two parts on either side of the other triangle's plane.
On 46–70 that edge is 20–81 of triangle 70. It runs 0.0208 on one side of
triangle 46's plane and 0.0247 on the other. It meets triangle 46 just inside
its boundary: the meeting point's smallest barycentric coordinate, its
distance from the nearest edge as a fraction of the triangle's height over that
edge, is `1.7e-8`. So the "31 t" measures triangle 70, the table. Triangle 46
is the card: its corner at vertex 27 reaches `2.42e-7` past triangle 70's
plane.

The study reports the **length** of each crossing pair's intersection segment,
the line where the two triangles pass through each other.
[body-larger-opening.md](body-larger-opening.md) correctly calls this a
distance along paper. Where two layers touch at a shallow angle, that line can
be long with almost nothing through it. Triangles 2 and 37 lie 2.1° apart. They
cut each other along a 29.76 px segment, with a reach-through of `1.06e-9`.

So the study's "longest failing intersection" depends on its tolerance:

| Tolerance | Longest failing intersection |
| --- | --- |
| `1e-9` | 29.76 px (2–37) |
| `1e-8` | 0.579 px (22–61) |
| `1e-7` | 0.23175 px (2–39, reach-through `1.91e-7`, 0.000115 px) |

## What this changes

- **The study's check misses no crossing on this body.** Nothing on the body
  goes deeper than `2.42e-7`. The weakness is elsewhere. On touching paper the
  check's verdict is a verdict on rounding. The 0.1 px intersection-length
  screen that rejects the endpoint is measuring a contact line 0.23 px long and
  0.000115 px deep. A screen on reach-through would ask how far paper passes
  through paper. Neither the count nor the length asks that.
- **The body is still not accepted.** It fails the `1e-5` relative-length check
  (body-larger-opening.md). Nor is it a start for a barrier method such as
  IPC, which keeps triangles apart with an energy that grows without bound as
  they approach, and so needs every pair a positive distance apart before it
  begins. Touching pairs are at distance zero, so ipctk's `has_intersections`
  returning true is the right answer to the question it asks.
- **The fixed-direction layer-height test in `Contact` played no part.**
  `crosses` never uses the direction, and body-larger-opening.md reports no
  order that the test could not judge.
- No tolerance or solver default changed.

## Reproduce

The study's count, from the library as it stands, in `stack ghci
senbazuru:lib` with `OverloadedStrings`:

```haskell
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Surface
Right file <- loadFoldFile "study/fold-material/fixtures/whole-crane-body.fold"
let fr = keyFrame file; Right points = frameVertices fr
let tri [VertexId a, VertexId b, VertexId c] = (a, b, c)
let mesh = Mesh [Sample (V2 0 0) p | p <- points] (map tri (facesVertices fr))
fmap crossingPanels (checkLocalTriangleContact (V3 0 0 1) [] mesh)
-- Right [("triangle-2","triangle-39"),("triangle-46","triangle-70")]
```

Reach-through, for two triangles given as 3×3 NumPy arrays of corners:

```python
def reach(a, b):
    n = np.cross(b[1] - b[0], b[2] - b[0]); n /= np.linalg.norm(n)
    d = (a - b[0]) @ n
    return max(0.0, min(-d.min(), d.max()))

def reach_through(a, b):
    return min(reach(a, b), reach(b, a))
```

Apply it only to pairs whose intersection segment has positive length. Two
triangles far apart can each reach past the other's *plane* without meeting.
The Y1 counter is `pair_metrics` in
`PRDs/research/scripts/Y1-valid-looks/geom.py`. ipctk is the IPC Toolkit's
Python binding, installed from PyPI into a scratch environment and not
vendored ([related-projects.md](../related-projects.md)).
