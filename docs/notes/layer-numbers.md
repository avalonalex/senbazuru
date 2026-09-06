# The layer a face is in is the longest chain below it

Terms used here are defined in [../glossary.md](../glossary.md).

A drawing of a folded model sometimes has to say *how many sheets deep* a face
is, and not merely which faces are in front of it. The reason is the **offset
view**: layers that land on the same patch of page are drawn a small distance
apart so that a stack reads as a stack rather than as one silhouette. Each face
is nudged by its layer number times a fixed step, so the number has to be a
number and not an ordering.

What senbazuru has is `faceOrders`: a set of pairs saying *this face is above
that one*, recorded for exactly the pairs whose faces share a patch of paper.
Which of a pair is nearer the *reader* needs the viewing direction as well, since
FOLD's "above" is a fact about the paper —
[layer-ordering.md](layer-ordering.md) is that half, and the layer numbers turn
over when the model does. Once it is settled, the pairs are a partial order, and
turning one into layer numbers is a question with two plausible answers and only
one right one.

## Counting what is underneath is wrong

The tempting answer is: the layer number of a face is how many faces are below
it. On the quarter fold it gives 0, 1, 2, 3, which is correct, and it stays
correct on anything that is a simple pile.

It breaks as soon as the paper does anything else. Suppose face `A` is under
`B`, and `B` is under `C`, but `A` and `C` have no entry between them — which is
what a file writes when `C` has slid clear of `A` and the two no longer share
any paper. Counting gives `A = 0`, `B = 1`, `C = 1`. So `B` and `C` are drawn at
the same offset, and they *do* overlap, so the picture puts one on top of the
other with nothing to say which. The whole point of the view is lost precisely
where there was something to see.

The failure is not a rounding case or a rare model. It is any stack that fans
out, which is most of them.

## Taking the longest chain is right

Give each face one more than the deepest face it is above:

```
layer(f) = 0                              if nothing is below f
layer(f) = 1 + max { layer(g) : f above g }   otherwise
```

`C` above is now `2`, because reaching it means passing through `B` and then
`A`. The number is the length of the longest chain of "above" relations
descending from the face, which is exactly what a reader counting sheets from
the table upwards would say.

The property that makes it the right answer is one line: **the number strictly
increases along every relation.** If `f` is above `g` then `layer(f) > layer(g)`
by construction, so two faces that overlap never share a layer number, and
sorting the faces by layer number is itself a valid painting order. That is what
lets the drawing paint a whole layer at a time — one fill for all the paper at
that depth, then its lines, then the next layer over the top — instead of
sorting faces individually and hoping.

Computing it is one pass. Put the faces in a topological order, which senbazuru
already does to decide what to paint first, and read the layer numbers off in
that order: every face a given face sits on has been settled before the face is
reached, so nothing is ever revisited.

This is not an origami idea. It is the *layer assignment* step of layered graph
drawing, where the same longest-path numbering puts the nodes of a directed
acyclic graph into rows so that every edge points down at least one row.
Sugiyama's method opens with it, and it is provably as compact as such a
numbering can be: a chain of *k* relations needs *k+1* distinct increasing
numbers, so no assignment that steps up at every relation can use fewer layers
than the longest chain has links.

## What it costs

Being the most compact numbering *of the relations* is not the same as being the
number of sheets a reader would count, and the gap is worth knowing about. Each
link of a chain is a real overlap, but the chain as a whole need not lie over any
single point: `A` under `B` under `C` is three links deep even where `C` has slid
clear of `A` and only two sheets are ever over the table at once. So the layer
numbers can run higher than the paper is thick, and an offset view spreads
further than the model is deep.

On the traditional crane the gap is mild. Sampling its folded footprint on a
199 × 199 grid and counting the faces over each point finds **24** sheets at the
thickest place, and its longest chain of "above" relations is **31**: about a
third further, which is a knob-shaped problem — pick a smaller step.

Closing it means asking, for each face, the longest chain of faces that all
share one patch of paper. That is a clique-flavoured question about geometry
rather than a walk over the relations, and it would buy a slightly more compact
picture.

## How deep is too deep to draw

The layer count is what decides whether a model has an offset view worth
looking at, so it is worth having the numbers side by side. Drawn at
`--offset 4`, counting the SVG paths each picture emits:

| Model | Layers | Paths, ordinary | Paths, offset | of those, fine |
| --- | --- | --- | --- | --- |
| Letter fold | 3 | 6 | 22 | 12 |
| Quarter fold | 4 | 5 | 24 | 16 |
| Kabuto | 12 | 9 | 75 | 56 |
| Crane | 32 | 23 | 311 | 242 |

The ordinary picture stays flat because hidden-line removal throws away
everything buried — for the crane, all but 23 of its edges. The offset view
throws away nothing, because everything is what the reader asked to see.

The first attempt at making that legible was to throw some of it away again:
draw only the silhouette of each sheet and drop the creases inside it. Measured,
that removes **6 of the crane's 242** edge copies, because almost every crease
in a folded model separates two faces at different depths and so is a silhouette
for both of them. There was nothing to delete.

What was wrong was the weight, not the count. A sheet edge drawn at 1.6pt among
a dozen others three points away is a black band; the same edges at 0.35pt are a
hatch that reads as thickness. So the stack is drawn fine and the model is drawn
over it at full weight, and the count went *up* — 311 paths for the crane, since
the top sheet is now drawn twice — while the picture got clearer.

## What books do instead

None of which makes a 32-layer model a good subject for an exploded plan, and
printed diagrams have never pretended otherwise. Robert Lang's diagramming
conventions offer three tools, in order of how much paper is in the way:
**x-ray lines** for a few hidden edges, and only as many as the current step
needs, because too many clutter the drawing; a **cut-away** when those stop
working — a heavy circle with the obscuring layers removed inside it, and edges
offset where they cross the boundary; and, when there are simply too many layers
to draw and keep clarity, a schematic **side view** of the stack with a hooking
arrow.

`--offset` is the cut-away's offsetting applied to a whole sheet rather than
inside a circle. That makes it the right tool for a model a handful of layers
deep and an honest but crowded one for anything deeper. A cut-away confined to a
region, and a side view, are both real features and neither is built.

## Where the relations run in a circle

Three faces of a twist can lie `A` over `B` over `C` over `A`. That is a
perfectly good stacking of real paper — no point of the sheet lies under all
three, so nothing passes through anything — and it has no layer numbers at all,
because the recursion above has nowhere to start. So a twist has no offset view,
and senbazuru says so rather than drawing one. The ordinary picture of it is
unaffected: [visible-regions.md](visible-regions.md) never needs a global order,
which is exactly why it exists.

## References

- Kozo Sugiyama, Shojiro Tagawa & Mitsuhiko Toda, "Methods for visual
  understanding of hierarchical system structures", *IEEE Transactions on
  Systems, Man and Cybernetics* 11(2), 1981. The layered drawing framework
  whose first step is this numbering.
- Giuseppe Di Battista, Peter Eades, Roberto Tamassia & Ioannis Tollis, *Graph
  Drawing: Algorithms for the Visualization of Graphs*, Prentice Hall, 1999,
  chapter 9, on layer assignment and on why the compact alternatives are
  harder.
- Robert J. Lang, "Origami Diagramming Conventions", on x-ray lines, cut-away
  views and the schematic side view — the three ways a printed diagram shows
  paper that is in the way.
- [several-stackings.md](several-stackings.md), for where the `faceOrders` this
  numbers come from when the file supplies none.
