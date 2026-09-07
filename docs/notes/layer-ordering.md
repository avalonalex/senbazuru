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

One transform does recompute it. `foldFrame` writes every face counterclockwise,
because the direction a ring runs decides which way each fold turns and it has
to measure that anyway. Having moved a winding, it is obliged to move the signs
written against it: every `faceOrders` entry whose **second** face was turned
round comes back with `Above` and `Below` swapped. Only the second — reversing
`f` changes which face is being placed, not the direction the relation is read
in. A winding is not private to its face, which is the whole of why this is
delicate.

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
than as a wireframe. A file without one has an ordering worked out if it is
folded flat (below); otherwise it gets the wireframe, because the alternative —
painting the faces in the order they happen to appear — is a confident picture
of the wrong thing.

Solving for an ordering when the file supplies none is done for models folded
flat, in `Senbazuru.Origami.Stacking`: the constraints turn out to be four
local rules ([taco-taco.md](taco-taco.md)), and finding which faces they apply
to is polygon clipping ([convex-clipping.md](convex-clipping.md)). A model with
paper still in the air is not covered, and stays a wireframe.

Having the ordering is not the same as having a picture. A valid layer order can
run in a circle among three faces that overlap pairwise without sharing a common
patch — the flaps of a twist do exactly that — and then there is no order to
paint whole faces in, however correct the ordering is. Painting whole faces also
cannot hide anything: every crease still gets drawn over the top. Both are the
subject of [visible-regions.md](visible-regions.md), which asks what can be
*seen* rather than what order to paint in.

## References

- Jacques Justin, "Towards a mathematical theory of origami", 1994.
- Erik Demaine & Joseph O'Rourke, *Geometric Folding Algorithms*, Cambridge
  University Press, 2007.
- The FOLD specification, on `faceOrders` and `edgeOrders`.
