# Maekawa's theorem

At every interior vertex of a crease pattern that folds flat, the number of
mountain creases and the number of valley creases differ by exactly two.

    M - V = +/- 2

One proof, in a sentence: shrink a circle around the vertex and look at what it
becomes when the paper is folded. It flattens into a zigzag; each mountain turns
the path one way by 180 degrees and each valley turns it the other way, and the
path has to close up, which forces `180(M - V) = +/- 360`.

A corollary falls straight out. `M + V` is the number of creases at the vertex,
and `M - V = +/- 2` forces it to be even. So **no flat-foldable vertex has an odd
number of creases** -- a three-crease vertex cannot fold flat, whatever the
angles are.

One odd count is worth separating out, because it is barely about this theorem:
a vertex with exactly **one** crease at it. The corollary covers it, one being
odd, but nothing about the arrangement is the problem — such a crease divides no
paper, so no angles could fold it, and it is a mistake in the drawing rather
than in the fold. `senbazuru check` says so separately for that reason. Note
too that the count is of creases that *fold*: flat and join lines are dissolved
first, so three lines on the page can leave one crease.

## Why it matters here

This is the cheapest possible origami-aware check, and it is what
`senbazuru check` does. It needs only the rotational order of edges at each
vertex and `edges_assignment` -- no coordinates, no trigonometry, no tolerances,
and not much more than what `Senbazuru.Fold.Query` already produces.

Note it is *necessary*, not sufficient. See [kawasaki.md](kawasaki.md).

## References

- Jun Maekawa, and independently Jacques Justin -- hence "Maekawa-Justin".
- Thomas Hull, "On the mathematics of flat origamis", *Congressus Numerantium*
  100, 1994.
- Thomas Hull, *Origametry: Mathematical Methods in Paper Folding*, Cambridge
  University Press, 2020.
