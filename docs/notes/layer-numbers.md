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

| Model | Layers | Paths, ordinary | Paths, offset |
| --- | --- | --- | --- |
| Letter fold | 3 | 6 | 15 |
| Quarter fold | 4 | 5 | 20 |
| Kabuto | 12 | 9 | 68 |
| Crane | 32 | 23 | 286 |

The ordinary picture stays flat because hidden-line removal throws away
everything buried — for the crane, all but 23 of its edges. The offset view
throws away nothing, so its ink grows with layers times faces, and the crane is
squeezed between two limits at once: a step small enough to fit the page is
smaller than the 1.6pt line the edge of the paper is drawn with, so consecutive
layers' outlines land on each other and the stack comes out as hatching, while a
step large enough to read fans thirty-two copies of the bird apart.

Four layers and twelve layers are fine. Thirty-two is not, and the honest fix is
not a better layer number: it is to stop drawing the creases inside a buried
sheet, since the sliver of it that shows should be an edge of paper and nothing
else.

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
- [several-stackings.md](several-stackings.md), for where the `faceOrders` this
  numbers come from when the file supplies none.
