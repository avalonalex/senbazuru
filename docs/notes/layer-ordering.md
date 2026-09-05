# The hard part of drawing a folded model

Rendering a crease pattern is easy: the coordinates in the file are already the
coordinates on the page. Rendering a *folded form* is not, and the reason is
layers.

Paper is opaque. To draw a folded model you must know, for every pair of
overlapping faces, which one is on top -- otherwise you cannot decide what to
hide. FOLD stores this in `faceOrders`, as triples `[f, g, s]` recording that
face `f` is above, below, or unordered with respect to face `g`.

Note that `s` is read against **`g`'s normal**, and a face's normal is defined
by the counterclockwise ordering of its own `faces_vertices`. So the sign is a
statement about the paper, not about the reader: turning it into "draw this one
last" needs a viewing direction as well, and a model seen from behind stacks the
other way up. This is also the one place a file's winding has to be taken
exactly as written — the normals and the signs were written against each other,
and recomputing the winding uncancels them.

Computing a valid ordering from scratch, rather than reading it from the file,
is a constraint satisfaction problem. The local conditions have memorable names
-- *taco-taco*, *taco-tortilla*, *tortilla-tortilla* -- each describing a way
two pairs of overlapping faces may or may not interleave without the paper
passing through itself.

## Why it matters here

The two halves are independent, and only one of them is hard. Computing *where*
the paper goes is [folding-by-transforms.md](folding-by-transforms.md) and is
cheap. Deciding *which layer is on top* is this.

Reading an ordering a file already carries is free, and senbazuru does it:
`Senbazuru.Origami.Layers` turns `faceOrders` plus a viewing direction into a
drawing order, so a folded form that comes with one is drawn as paper rather
than as a wireframe. A file without one still gets the wireframe, because the
alternative — painting the faces in the order they happen to appear — is a
confident picture of the wrong thing.

Solving for an ordering when the file supplies none is the deep end of the
roadmap, and worth knowing the shape of before wading in.

## References

- Jacques Justin, "Towards a mathematical theory of origami", 1994.
- Erik Demaine & Joseph O'Rourke, *Geometric Folding Algorithms*, Cambridge
  University Press, 2007.
- The FOLD specification, on `faceOrders` and `edgeOrders`.
