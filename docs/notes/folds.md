# Which fold, and why it is almost never `foldl`

Summing five million `Int`s, compiled at `-O0`:

| | peak residency | time |
| --- | --- | --- |
| `foldl (+) 0` | 312 MB | 0.70 s |
| `foldl' (+) 0` | 44 KB | 0.03 s |

Same type, same traversal order, same answer. They differ only in **when** the
accumulator gets evaluated.

## `foldl` builds a tower

```haskell
foldl f z (x:xs) = foldl f (f z x) xs
```

Nothing ever demands the accumulator, so nothing is computed until the end:

```
foldl (+) 0 [1,2,3]
  = foldl (+) (0+1)         [2,3]
  = foldl (+) ((0+1)+2)     [3]
  = foldl (+) (((0+1)+2)+3) []
  = (((0+1)+2)+3)              -- only now does any addition happen
```

That nested expression is a chain of *thunks* — one heap closure per `+`, each
holding pointers to its arguments. Five million elements builds a
five-million-deep tower before adding a thing.

## `foldl'` forces as it goes

```haskell
foldl' f z (x:xs) = let z' = f z x in z' `seq` foldl' f z' xs
```

The `seq` evaluates the accumulator before recursing, so it stays a plain
number. Constant space, and ~20x faster here because it never touches the heap.

## `foldr` associates the other way

```haskell
foldr f z [1,2,3] = 1 `f` (2 `f` (3 `f` z))
```

Not tail recursive — but when `f` is lazy in its *second* argument it can
produce output before consuming the whole list. That is why `foldr (:) []`,
`foldr (&&) True` and `map`-as-`foldr` all work on infinite lists and can stop
early. Give `foldr` a strict `f` and a long list and you exhaust the stack
instead of the heap.

## Rule of thumb

| Goal | Fold |
| --- | --- |
| Reduce to one strict value | `foldl'` — and see the catch below |
| Build lazily, short-circuit, or handle infinite input | `foldr` |
| Anything at all | almost never `foldl` |

`foldl` is lazy in its accumulator yet still has to reach the end of the list
before producing anything, so it gets none of the benefits of laziness — no
infinite lists, no short-circuiting — while paying the full space cost.

## The catch

`foldl'` forces only to *weak head normal form*, which for a record or tuple
accumulator means the constructor and nothing inside it. See
[strict-fields.md](strict-fields.md), where `foldl'` over a tuple measures
**worse** than plain `foldl`.

## Footnote

`foldl'` only entered the `Prelude` in `base-4.20` (GHC 9.10). This project is
on GHC 9.6, which is why `Senbazuru.Geometry` opens with
`import Data.List (foldl')`.

## References

- "Foldr Foldl Foldl'", Haskell Wiki — the canonical treatment.
- Simon Marlow, *Parallel and Concurrent Programming in Haskell*, O'Reilly,
  2013 — the chapter on evaluation and WHNF.
- [folds-experiment.hs](folds-experiment.hs) — the numbers above.
