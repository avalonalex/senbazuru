# Notes

Short notes on ideas worth knowing for this project. **One idea per file**, each
a few minutes to read, each with references if you want to go deeper.

These are background and direction, not documentation of the code. For the code,
read the Haddock module headers; for the domain, start with
[../fold-primer.md](../fold-primer.md).

## Origami and geometry

| Note | Idea |
| --- | --- |
| [maekawa.md](maekawa.md) | At a flat-foldable vertex, mountains minus valleys is always ±2 |
| [kawasaki.md](kawasaki.md) | Alternating angles decide single-vertex flat-foldability exactly |
| [flat-foldability-is-hard.md](flat-foldability-is-hard.md) | One vertex is linear time; the whole sheet is NP-hard |
| [robust-predicates.md](robust-predicates.md) | Why `Double` gets the left-of-line test *wrong*, not just imprecise |
| [convex-hull.md](convex-hull.md) | Andrew's monotone chain, in four steps |
| [half-edge.md](half-edge.md) | The structure FOLD's array format is already shaped for |
| [layer-ordering.md](layer-ordering.md) | Why drawing a folded model is hard and a crease pattern isn't |
| [huzita-hatori.md](huzita-hatori.md) | Paper folding is strictly stronger than straightedge and compass |
| [no-sequence-solver.md](no-sequence-solver.md) | Nobody can turn a crease pattern into folding instructions, and why |

## Haskell

| Note | Idea |
| --- | --- |
| [phantom-units.md](phantom-units.md) | Turning the model-units/page-units rule from a comment into a type error |
| [envelopes.md](envelopes.md) | A support function beats a bounding box for laying out a step sequence |
| [shrinking.md](shrinking.md) | A property test is only as useful as its counterexample is small |
| [folds.md](folds.md) | `foldl` builds a tower, `foldl'` flattens it, `foldr` produces lazily |
| [strict-fields.md](strict-fields.md) | `foldl'` forces only to WHNF, so lazy fields leak anyway — measured |

## Where to start

If you want one thing to build next, [maekawa.md](maekawa.md) and
[kawasaki.md](kawasaki.md) together are the smallest change that makes senbazuru
understand origami rather than just draw lines — no new geometry machinery, and
they give the CLI a second verb that catches genuinely bad input.
