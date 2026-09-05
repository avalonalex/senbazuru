# Layer order is four local rules

Terms used here are defined in [../glossary.md](../glossary.md); for what a
folded form and `faceOrders` are, start with
[layer-ordering.md](layer-ordering.md).

Take a model folded flat. Every face lies in one plane, and where two faces
cover the same patch of paper one of them is on top. Deciding which, for every
overlapping pair, is the layer-ordering problem, and it looks global: the
answer for one pair seems to depend on everything else. It does not. Every
constraint the paper imposes is about a handful of faces that meet along one
line, and there are only four kinds.

Two faces joined along an edge of the folded form are either a **taco** or a
**tortilla**. A taco is the paper folded back on itself: both faces on the same
side of the edge, like the two halves of a taco shell. A tortilla is paper that
continues flat across the line, like a tortilla lying on the table. Which of the
two an edge is can be read off the coordinates — are the two faces on the same
side of the line or opposite sides? — without consulting the recorded angle.

## The rules

**The crease.** A taco's two faces overlap, and its assignment says which is
on top. A valley brings the two *top* sides of the paper together, so of the
two faces the one now lying top-down is above the one lying top-up. A mountain
brings the undersides together and it is the other way round.

**Taco–tortilla.** A face that runs across a taco's fold line cannot lie
between the taco's two faces. The paper is continuous where the fold line
crosses it, so a fold passing through would tear it. Nor can a face that runs
across a *tortilla's* line lie between the tortilla's two faces, for the same
reason with the roles swapped.

**Taco–taco.** Two tacos folded on the same line, to the same side, must nest
or stay apart: if one face of the first taco is between the faces of the second,
so is its partner. Interleaving them would put one fold through the other.

**Tortilla–tortilla.** Two sheets that both continue flat across one line
cannot cross it in opposite orders. If one is on top on the left of the line it
is on top on the right.

There is one more, and it is about arithmetic rather than paper: three faces
that share a patch of paper are totally ordered over that patch, so their three
pairwise answers may not run in a circle. Note the *share a patch*. Three faces
can overlap pairwise with no point under all three — the flaps of a twist do —
and there a circle is precisely what the paper does.

## Why they are enough

Overlay every face of the folded model and the plane is cut into cells, each
with a stack of faces over it. Along the boundary between two cells, every face
in the stack either continues into the next cell (a tortilla, or a face crossed
by the line), stops (a border), or folds back (a taco). The rules above are
exactly the ways those can interact without paper passing through paper, and
the circle rule is consistency within a cell. Nothing happens anywhere else.

## Why it matters here

`Senbazuru.Origami.Stacking` generates these rules for a flat-folded frame and
satisfies them by propagation and search. It is what lets a folded form that
senbazuru folded itself — which knows where every face went and nothing about
which is in front — be drawn as paper.

The rules also catch what the single-vertex theorems cannot.
`examples/big-little-big.fold` passes Maekawa and Kawasaki and folds without
tearing; its two large sectors fold to the same side of the small one between
them, and each runs across the other's crease, so the two taco–tortilla rules
contradict. `senbazuru render big-little-big.fold --fold` reports exactly that.

## References

- Jacques Justin, "Towards a mathematical theory of origami", *Proceedings of
  the Second International Meeting of Origami Science and Scientific Origami*,
  1994. The taco and tortilla conditions in their original form.
- Erik Demaine & Joseph O'Rourke, *Geometric Folding Algorithms*, Cambridge
  University Press, 2007, §12.
- Thomas Hull, *Origametry*, Cambridge University Press, 2020, on why the
  general problem is hard even though each rule is local.
