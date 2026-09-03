# Andrew's monotone chain

The convex hull is the smallest convex polygon containing a set of points.
Andrew's monotone chain computes it in `O(n log n)`, and the algorithm is short
enough to hold in your head:

1. Sort the points by `x`, breaking ties by `y`.
2. Sweep left to right building the lower hull: push each point, and while the
   last three make a non-left turn, pop the middle one.
3. Sweep right to left the same way to build the upper hull.
4. Concatenate the two, dropping the duplicated endpoints.

The sort dominates the cost; each sweep is linear, because every point is pushed
once and popped at most once.

It is preferable to the Graham scan that usually gets taught. There is no
angular sort, so no `atan2` and no comparing angles for equality, and the
degenerate cases -- duplicate points, three collinear points, all points on a
line -- are much easier to get right.

The "non-left turn" test is exactly the orientation predicate. This is the
algorithm that misbehaves spectacularly when that predicate lies, so read
[robust-predicates.md](robust-predicates.md) alongside this.

## Why it matters here

Placing a fold arrow needs the outline of the sheet. The usual approach is to
take the hull of the vertices, find a segment across it perpendicular to the
fold line, and draw the arrow's arc along that segment. That makes convex hull
the first real piece of computational geometry senbazuru will need.

## References

- A. M. Andrew, "Another efficient algorithm for convex hulls in two
  dimensions", *Information Processing Letters* 9(5), 1979.
- de Berg, Cheong, van Kreveld & Overmars, *Computational Geometry: Algorithms
  and Applications*, 3rd ed., Springer, 2008.
