# The hard part of drawing a folded model

Rendering a crease pattern is easy: the coordinates in the file are already the
coordinates on the page. Rendering a *folded form* is not, and the reason is
layers.

Paper is opaque. To draw a folded model you must know, for every pair of
overlapping faces, which one is on top -- otherwise you cannot decide what to
hide. FOLD stores this in `faceOrders`, as triples `[f, g, s]` recording that
face `f` is above, below, or unordered with respect to face `g`.

Computing a valid ordering from scratch, rather than reading it from the file,
is a constraint satisfaction problem. The local conditions have memorable names
-- *taco-taco*, *taco-tortilla*, *tortilla-tortilla* -- each describing a way
two pairs of overlapping faces may or may not interleave without the paper
passing through itself.

## Why it matters here

`Senbazuru.Fold.Query.frameVertices` projects folded forms straight down onto
the xy plane, and its documentation says plainly that a top-down view of a
folded model is not a correct picture of it. Everything past that honest
disclaimer needs this. It is the deep end of the roadmap, and worth knowing the
shape of before wading in.

## References

- Jacques Justin, "Towards a mathematical theory of origami", 1994.
- Erik Demaine & Joseph O'Rourke, *Geometric Folding Algorithms*, Cambridge
  University Press, 2007.
- The FOLD specification, on `faceOrders` and `edgeOrders`.
