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

`Senbazuru.Render.Camera` can now look at a folded form from any angle, but it
draws every edge regardless of what is in front of what — a wireframe, with no
paper. Everything past that needs this.

Note the two halves are independent: computing *where* the paper goes is
[folding-by-transforms.md](folding-by-transforms.md) and is cheap; deciding
*which layer is on top* is this, and is not. It is the deep end of the roadmap, and worth knowing the
shape of before wading in.

## References

- Jacques Justin, "Towards a mathematical theory of origami", 1994.
- Erik Demaine & Joseph O'Rourke, *Geometric Folding Algorithms*, Cambridge
  University Press, 2007.
- The FOLD specification, on `faceOrders` and `edgeOrders`.
