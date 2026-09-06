# Drawing what is visible, not what is there

A folded model is opaque, so a drawing of one shows less paper than the model
contains. Painting every face back to front is the usual way to arrange that: put
the far ones down first and let the near ones cover them. It has two problems,
and both are solved by the same change of question.

**It needs one global order, and a twist has none.** The four flaps of a square
twist stack A over B over C over D over A. That is not a contradiction — no
point of the paper lies under all four at once, so nothing has to pass through
anything — but there is no order to paint four whole faces in. A painter's
algorithm reports failure on a model that folds perfectly well.

**It hides nothing.** Faces get covered, but the *creases* are drawn afterwards,
every one of them, including the creases of layers buried ten deep. The picture
is a wireframe with a tint.

## The question to ask instead

Not "in what order do I paint the faces" but "what part of each face can be
seen":

```
visible f  =  f  minus  every face nearer the viewer that overlaps it
```

Over any single point of the page the faces covering that point are totally
ordered — which is exactly the condition the layer solver enforces for three
faces with a patch of paper in common — so one of them is on top there, and the
point belongs to that one's visible part and to no other. The visible parts
therefore tile the model's silhouette with no gaps and no double coverings, and
a cycle among three faces is no obstacle at all, because no point is under the
whole cycle.

An edge falls out of the same idea: a line is worth drawing where the paper
*differs* across it, and not where it does not. Cut each edge wherever a face
boundary crosses it, and keep a stretch only when the topmost face on one side
is not the topmost face on the other. A crease with a layer over it has the same
face on both sides and goes. The outline of that layer has paper on one side and
bare page on the other and stays.

## What this replaces

The textbook route to the same regions is a **planar arrangement**: overlay
every face, cut the plane into *cells* at every crossing of every pair of edges,
work out each cell's top face, then glue neighbouring cells back together where
they agree. It is how ORIPA, Oriedita and Flat-Folder all draw folded forms, and
it needs segment intersection, a [half-edge structure](half-edge.md) to trace
the cells out of, and a rule for deciding which hole belongs inside which outer
ring.

The subtraction reaches the same regions with none of that, and reaches them
already grouped by which face is on top — the gluing step is not skipped so much
as never needed. What it costs is generality: it wants convex faces, because
subtracting a convex shape from a convex shape is one half-plane clip per edge
and nothing else, whereas subtracting a concave one is a general polygon boolean
operation. Kawasaki's theorem makes the faces of a flat-foldable pattern convex
whenever the sheet is, so the restriction is nearly free here and would not be
somewhere else.

The other cost is that a region is no longer one ring. A face minus another face
is not convex — a square with a bite out of one side is the smallest example —
so a region comes back as several convex pieces that abut. That turns out to be
a feature: a region can genuinely have a *hole*, when a flap lands in the middle
of a larger face, and pieces express a hole without anyone having to notice one.

## Why it matters here

`Senbazuru.Origami.Visible` is this, and
`Senbazuru.Geometry.Polygon.subtractConvex` is the one piece of geometry it
needed. For the flat-folded crane it turns 72 faces and 129 creases into 14
pieces of paper in 11 regions and 22 stretches of edge, which is what a book
would print. Nothing draws it yet: `Senbazuru.Render.CreasePattern` still paints
whole faces in the order `Senbazuru.Origami.Layers` sorts them into, which is
why `render --fold examples/thirds-pinwheel.fold` still refuses a twist.

The two-sided part is free once regions exist. A region knows which face it came
from, and a face in a flat-folded model knows which way up it lies from its
winding, so it knows whether the viewer is looking at the front of the paper or
the back — which is a fact about the paper, and a colour is what a renderer
makes of it.

## References

- de Berg, Cheong, van Kreveld & Overmars, *Computational Geometry*, 3rd ed.,
  Springer, 2008 — chapter 2 on arrangements and the map overlay, which is the
  construction this avoids.
- Ivan Sutherland & Gary Hodgman, "Reentrant polygon clipping", *CACM* 17(1),
  1974 — the half-plane clip everything above is built from. See
  [convex-clipping.md](convex-clipping.md).
- Jason Ku, [Flat-Folder](https://github.com/origamimagiro/flat-folder) — solves
  the layer order and then draws by cells, which is the arrangement route done
  properly.
