# Local flat-foldability is easy; global is NP-hard

[Kawasaki's theorem](kawasaki.md) decides a single vertex in linear time.
Deciding whether an entire crease pattern folds flat is NP-hard.

The gap between those two sentences is *layers*. Every vertex can satisfy
Kawasaki individually while the sheet still cannot fold, because making all the
folds at once would require faces to pass through each other. Satisfying every
vertex is necessary and nowhere near sufficient.

Later work sharpened the result rather than softening it: flat-foldability stays
hard even for box-pleated patterns, where every crease lies on a square grid at
multiples of 45 degrees.

## Why it matters here

It tells you what is worth building. A per-vertex checker is cheap, exact, and
genuinely useful for catching bad input. A general "does this fold?" oracle is
not a feature to add casually -- and knowing that in advance saves you from
discovering it halfway through.

It also explains why `faceOrders` exists in the FOLD format at all: the layer
ordering is data a file must carry, because recomputing it is hard. See
[layer-ordering.md](layer-ordering.md).

## References

- Marshall Bern & Barry Hayes, "The complexity of flat origami", *SODA*, 1996.
- Akitaya, Cheung, Demaine, Horiyama, Hull, Ku, Tachi & Uehara, "Box pleating is
  hard", *JCDCGG*, 2015.
- Erik Demaine & Joseph O'Rourke, *Geometric Folding Algorithms: Linkages,
  Origami, Polyhedra*, Cambridge University Press, 2007.
