# Test overlap by clipping, not by predicates

Terms used here are defined in [../glossary.md](../glossary.md).

Two polygons overlap if there is a patch of the plane inside both. The layer
solver has to ask this of every pair of faces in a folded model, and the obvious
way to answer is a pair of predicates: do any two edges properly cross, or is
any vertex of one strictly inside the other?

A flat-folded model breaks that at once. Fold a square into quarters and all
four faces land on the *same* quadrant. No edge properly crosses any other; no
vertex is strictly inside anything; the four faces overlap completely. Add a
case for identical polygons and the next fixture has a triangle whose three
corners sit exactly on a square's edges. Every degenerate arrangement a folded
model produces — and it produces them constantly, since everything lands on
crease lines and old corners — is another case.

## Clip instead

Compute the intersection and measure it. Sutherland–Hodgman clips one convex
polygon by another: for each edge of the clipping polygon in turn, walk round
the other one, keep what is on the inner side of that edge's line, and insert
the crossing point wherever the ring steps over it. What is left after every
edge has had its turn is the intersection. Take its area; overlap means the
area is above a tolerance.

```
clip by edge 1     clip by edge 2     ...    result
  ┌────┐             ┌────┐                  ┌──┐
  │  ┌─┼──┐   →      │  ┌─┤          →       │  │
  └──┼─┘  │          └──┼─┘                  └──┘
     └────┘             └─
```

Every case above is now the same three lines. Identical squares clip to the
square. Squares sharing an edge clip to a sliver whose area is a rounding error.
The inscribed triangle clips to itself. Nothing is being *tested*, so there is
nothing to get wrong; the only judgement is the tolerance, and it is made once.

The same routine, applied twice, answers whether three faces share a patch:
clip the first two, then clip the result by the third. That is what the
transitivity rule in [taco-taco.md](taco-taco.md) needs, and it is not implied by
pairwise overlap — three long strips can pairwise overlap in a triangle
arrangement with no point under all three.

## The catch

Sutherland–Hodgman keeps a half-plane per edge, so the result is the polygon's
interior only when the polygon *is* the intersection of its edges' half-planes,
which is what convex means. Clipping by a concave polygon quietly keeps too much.
The faces of a flat-foldable pattern are convex whenever the sheet is —
Kawasaki's theorem keeps every sector at an interior vertex under 180° — so the
solver checks convexity and declines the rare face that fails, rather than
answering wrongly.

## The line that dropped constraints

The crossing point in Sutherland–Hodgman is `p + t (q − p)`, and the textbook
gives

```
t = cross(b − a, a − p) / cross(b − a, q − p)
```

with the remark that the denominator cannot be zero, because the step is only
taken when `p` and `q` are on opposite sides of the line. In floating point it
can. A subject edge that runs *along* a clip edge — which every shared crease of
a folded model is — can have one end a rounding hair outside the line and the
other exactly on it, while `q − p` rounds to exactly parallel. Then `t` is
infinite, or `0/0`, the "crossing" is nowhere, and the area of the result is
NaN.

NaN fails every comparison, including "is this area above the tolerance", so
the effect is not a crash but a face pair or triple quietly losing its rule.
A cross-check against an independent solver's constraint counts found six such
triples in an eighteen-face model.

The fix is not a guard but a different formula. The side test has already
computed how far inside the line each end is, `d_p` and `d_q`, and the crossing
is where that distance interpolates to zero:

```
t = d_p / (d_p − d_q)
```

The step only runs when one of the two is non-negative and the other strictly
negative, so the denominator is a sum of two same-sign magnitudes: it cannot be
zero, and `t` lies in `[0, 1]` by the monotonicity of rounding. Nothing is
clamped and nothing is special-cased; the ill-conditioned input simply lands
the point on whichever end is on or nearest the line, which is where the true
crossing is to within that hair. It reads like a needless rewrite of one line
and is the whole fix.

## Why it matters here

`Senbazuru.Geometry.Polygon` is this note as code, and a property test drives
it against random integer-cornered boxes, whose intersection area can be worked
out by hand as overlap-in-x times overlap-in-y. Integer corners are the point:
they make shared edges and coincident corners common rather than measure-zero.

## References

- Ivan Sutherland & Gary Hodgman, "Reentrant polygon clipping",
  *Communications of the ACM* 17(1), 1974.
- Mike Cyrus & Jay Beck, "Generalized two- and three-dimensional clipping",
  *Computers & Graphics* 3(1), 1978. The segment-against-convex-polygon
  version, used to tell a crease running through a face from one running along
  its edge.
- de Berg, Cheong, van Kreveld & Overmars, *Computational Geometry*, 3rd ed.,
  Springer, 2008, on why predicates on doubles lie
  ([robust-predicates.md](robust-predicates.md)).
