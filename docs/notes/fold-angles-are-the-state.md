# Fold angles are the state, not vertex positions

A rigidly folded model — one whose faces stay flat and unstretched — is
described by one angle per crease. Vertex positions are *derived* from those
angles, by the algorithm in
[folding-by-transforms.md](folding-by-transforms.md), not the other way round.

Terms used here are defined in [../glossary.md](../glossary.md); the ideas
behind them are in [../fold-primer.md](../fold-primer.md).

The consequence bites immediately. To show a model half folded, you cannot
interpolate vertex positions between the flat and folded forms. Paper does not
stretch, so straight-line vertex paths change edge lengths and tear the sheet.

Interpolating the *angles* is the right instinct and still not enough.

## Why the angles are constrained

Walk around an interior vertex, crossing each crease in turn, and you arrive
back where you started. The rotations must therefore compose to nothing:

```
R(e₁, θ₁) · R(e₂, θ₂) · … · R(eₙ, θₙ) = I
```

That is the loop-closure condition. Picture every possible assignment of angles
as a point in a space with one dimension per crease: the condition carves out a
curved surface, and only points *on* it are foldable. A straight line between
two points on a curved surface leaves it almost at once — so scaling every angle
by a fraction `t`, the obvious route to a half-folded state, generally lands on
angles no sheet of paper can adopt.

## Why this is easy to ship broken

The folding algorithm reaches every face along a spanning tree, which by
definition contains no cycles — so it cuts exactly these loops. It will
produce tentative positions for any angles you hand it, valid or not: each
vertex takes whichever path the traversal reached it by. Without further
checks, inconsistent angles silently tear the model. Our folding engine checks
both shared positions and the achieved crease angles after the traversal, and
refuses inconsistent states; see [folding-by-transforms.md](folding-by-transforms.md).

## The tractable corner

A degree-4 vertex — four creases meeting — has one degree of freedom: fix any one of its four angles and the other three follow, by
formulas you can write down. That is why the literature singles them out — the
one case where a continuous folding motion has an explicit answer rather than
needing to be solved for.
Our [rabbit-ear example](rabbit-ear-motion.md) works through one such formula,
from the angles on the sheet to checked intermediate folding states.

For larger vertices, a general solution may need a numerical solve for angles
satisfying every loop at once, or a physical simulation that nudges the model
until it settles. Special symmetry can still give an explicit path: our
[square and waterbomb collapse](symmetric-base-collapse.md) links the six
active crease angles through one parameter.
See
[no-sequence-solver.md](no-sequence-solver.md) is the neighbouring problem.

## References

- Belcastro & Hull, "Modelling the folding of paper into three dimensions using
  affine transformations", 2002 — the matrix loop-closure condition.
- Tachi, "Simulation of Rigid Origami", *4OSME*, 2009 — solving for valid states.
- Ghassaei, Demaine & Gershenfeld, "Fast, Interactive Origami Simulation using
  GPU Computation", *7OSME*, 2018 — sidestepping the solve with mass-spring
  relaxation.
