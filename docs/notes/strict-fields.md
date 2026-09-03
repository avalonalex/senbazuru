# `foldl'` alone does not make a fold strict

`Senbazuru.Geometry.boxFromPoints` accumulates a bounding box with `foldl'`.
That is the well-known advice for avoiding a space leak in a left fold, and on
its own it is not enough.

`foldl'` forces the accumulator at each step only to **weak head normal form** —
far enough to learn which constructor it is, no further. For a `Box` that means
the `Box` constructor. If its fields were lazy, every field would still hold an
unevaluated chain of `min` and `max` thunks, one link longer per point. That is
precisely the leak `foldl'` was reached for to prevent.

What closes it is the strictness annotations on the fields of `V2` and `Box`.
Forcing the constructor then forces the numbers inside it.

## Measured

[`strict-fields-experiment.hs`](strict-fields-experiment.hs) folds one million
points twice with the same `foldl'` and the same function, differing only in
whether the accumulator's fields are strict:

| Build | Strict fields | Lazy fields |
| --- | --- | --- |
| `-O0` | 44 KB peak residency | 198 MB peak residency |
| `-O2` | 44 KB | 44 KB |

```
ghc -O0 -rtsopts -o leak strict-fields-experiment.hs
./leak strict 1000000 +RTS -s
./leak lazy    1000000 +RTS -s
```

## The point is not speed

At `-O2` the strictness analyser spots it and the two are identical. So in an
optimised build the bangs buy nothing measurable — which is exactly why it is
worth being clear about what they *do* buy:

> Space behaviour becomes a property of the type, rather than something the
> optimiser has to notice.

The analyser succeeds here because the fold is small and obvious. Wrap it in a
typeclass, or make it polymorphic, or put it behind a module boundary without an
`INLINABLE` pragma, and it may not. Annotating the type means never having to
work out which of those you are in.

The gap is also not hypothetical in day-to-day use: GHCi does no strictness
analysis at all, so `make repl` behaves like the `-O0` column.

## References

- Simon Marlow, *Parallel and Concurrent Programming in Haskell*, O'Reilly,
  2013 — the chapter on evaluation and WHNF.
- The GHC User's Guide on `-XStrictData`, which turns these annotations on for a
  whole module.
- Johan Tibell, "High Performance Haskell" — the standard treatment of strict
  accumulators.
