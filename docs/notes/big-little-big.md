# The Big-Little-Big lemma

Take an interior vertex — one with paper all the way round it — and let the
creases radiating from it cut that paper into *sectors*, whose angles are
`a1, a2, ... a2n` in rotational order. [Maekawa's theorem](maekawa.md) counts
the mountains and valleys at such a vertex. [Kawasaki's](kawasaki.md) adds up
the sector angles. Neither says anything about *which* crease is which.

This one does:

> If a sector is strictly smaller than the sectors on both sides of it, the two
> creases bounding that sector are one mountain and one valley.

The name is the picture: a little angle sitting between two big ones.

The intuition is a crimp. Fold the vertex flat and watch the little sector: its
two neighbours are wider, so as the paper closes it is swallowed between them,
folded back on itself and covered from both sides. Paper that goes in and comes
straight back out has turned one way and then the other, which is exactly a
mountain and a valley next to each other. If instead both creases turned the
same way, the two wide neighbours would end up on the same side of the little
sector with nothing to separate them, and since neither is narrow enough to be
absorbed by it, they would have to pass through each other. Paper does not do
that. (The proof is in Hull; this paragraph is the picture, not the argument.)

It has to be a *strict* minimum. When a sector ties with a neighbour the lemma
as stated says nothing, and the generalisation to runs of equal angles needs
more care than it looks.

## The gap it closes

Here is a vertex that satisfies both theorems senbazuru checks and still cannot
fold flat. Four creases, at 0°, 90°, 120° and 210°, so the sectors run
`90, 30, 90, 150`:

- **Kawasaki**: `90 - 30 + 90 - 150 = 0`. Passes.
- **Maekawa**: assign three mountains and one valley — the creases at 0°, 90°
  and 120° mountain, the one at 210° valley. `M - V = 2`. Passes.
- **Big-Little-Big**: the 30° sector is strictly smaller than the 90° sectors on
  either side of it, so the creases bounding it — the ones at 90° and 120° —
  must differ. Both are mountains. Fails.

That vertex is `examples/big-little-big.fold`, and senbazuru is happy with it:

```console
$ senbazuru check examples/big-little-big.fold
examples/big-little-big.fold, frame 0
  checked 1 interior vertex; skipped 4 on the border
  no violations found
```

Which is why the tool says *no violations found* rather than *flat-foldable*.

## Why it matters here

It is the third cheap local condition, and unlike the other two it constrains
the mountain-valley *arrangement* rather than the counts or the angles. It needs
nothing senbazuru does not already compute: `Senbazuru.Origami.FlatFold` builds
the sectors in rotational order, and the test is a scan over three consecutive
sectors at a time.

Even with it, a vertex that passes all three is still not proven flat-foldable.
Deciding a single vertex completely is a different algorithm — repeatedly fold
away the smallest sector and see whether the vertex reduces to nothing — and
deciding a whole sheet is
[NP-hard](flat-foldability-is-hard.md).

## References

- Thomas Hull, *Origametry*, Cambridge University Press, 2020 — the
  single-vertex chapters state and prove this alongside Maekawa and Kawasaki.
- Thomas Hull, "The combinatorics of flat folds: a survey", *Origami³*, 2002.
