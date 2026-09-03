# `foldl'` alone does not make a fold strict

`foldl'` forces the accumulator at every step — but only to **weak head normal
form**: far enough to learn the outermost constructor, no further.

For an `Int` that is the whole value, so `foldl' (+) 0` is genuinely constant
space. For a record or a tuple it is only the constructor, and every field
underneath stays an unevaluated thunk. A left fold with a lazy-fielded
accumulator therefore leaks exactly as `foldl` would, however firmly you reached
for `foldl'`.

## Measured

[folds-experiment.hs](folds-experiment.hs), compiled at `-O0`:

| accumulator | peak residency |
| --- | --- |
| `(Int, Int)` tuple | 366 MB |
| `data P = P !Int !Int` | 44 KB |
| four lazy `Double` fields | 198 MB |
| four strict `Double` fields | 44 KB |

Plain `foldl (+) 0` over the same input is 312 MB — so **`foldl'` over a tuple
is worse than not using `foldl'` at all.**

```
ghc -O0 -rtsopts -o folds folds-experiment.hs
./folds lazypair   5000000 +RTS -s
./folds strictpair 5000000 +RTS -s
```

## Where this shows up here

`Senbazuru.Geometry.boxFromPoints` folds a `Box` over the vertex list; the last
two rows above are that fold's exact shape. Without the `!` on the fields of
`V2` and `Box`, the `min` and `max` chains would accumulate — which is why the
Haddock treats `foldl'` and the strictness annotations as one decision rather
than two.

The annotation is **shallow**, which is worth knowing before scattering it.
`!(Maybe Text)` in `Senbazuru.Fold.Types` forces the `Maybe` constructor, not
the `Text` inside it. Those record bangs are cheap discipline, not a measured
win; the ones on `V2` and `Box` are load-bearing.

## The point is not speed

At `-O2` the strictness analyser spots every case above and all six collapse to
44 KB. In an optimised build the bangs buy nothing measurable, which is exactly
why it is worth being precise about what they do buy:

> Space behaviour becomes a property of the type, rather than something the
> optimiser has to notice.

The analyser succeeds here because the folds are small and obvious. Make one
polymorphic, or put it behind a module boundary with no `INLINABLE` pragma, and
it may not. Annotating the type means never having to work out which case you
are in.

GHCi does no strictness analysis at all, so `make repl` behaves like the `-O0`
column.

## References

- Simon Marlow, *Parallel and Concurrent Programming in Haskell*, O'Reilly,
  2013 — evaluation and WHNF.
- The GHC User's Guide on `StrictData`, which turns these annotations on for a
  whole module.
- [folds.md](folds.md) — `foldl` versus `foldl'` versus `foldr`.
