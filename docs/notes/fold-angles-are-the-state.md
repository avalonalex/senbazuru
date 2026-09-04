# Fold angles are the state, not vertex positions

A rigidly folded model is described by one angle per crease. Vertex positions
are *derived* from those angles — see
[folding-by-transforms.md](folding-by-transforms.md) — not the other way round.

The consequence bites immediately. To show a model half folded, you cannot
interpolate vertex positions between the flat and folded forms. Paper does not
stretch, so straight-line vertex paths change edge lengths and tear the sheet.

Interpolating the *angles* is the right instinct and still not enough.

## Why the angles are constrained

Walk around an interior vertex, crossing each crease in turn, and you arrive
back where you started. The rigid motions must therefore compose to nothing:

```
R(e₁, θ₁) · R(e₂, θ₂) · … · R(eₙ, θₙ) = I
```

That is the loop-closure condition, and it is what makes valid configurations a
*variety* in fold-angle space rather than the whole space. A straight line
between two valid angle sets generally leaves it — so `t × final` is, in
general, not a foldable state at all.

## Why this is easy to ship broken

The spanning tree in the folding algorithm cuts exactly these loops. It will
happily produce positions for any angles you hand it, valid or not: each vertex
simply takes whichever path the traversal reached it by. Inconsistent angles do
not raise an error, they silently tear the model — geometry that looks plausible
at a glance and is wrong.

## The tractable corner

A degree-4 vertex has a single degree of freedom, with closed-form relations
between its four angles. That is why degree-4 vertices are singled out
throughout the literature: they are the case where a continuous folding motion
can be written down rather than solved for.

Everything larger needs either a constraint solve or a physical relaxation, and
[no-sequence-solver.md](no-sequence-solver.md) is the neighbouring problem.

## References

- Belcastro & Hull, "Modelling the folding of paper into three dimensions using
  affine transformations", 2002 — the matrix loop-closure condition.
- Tachi, "Simulation of Rigid Origami", *4OSME*, 2009 — solving for valid states.
- Ghassaei, Demaine & Gershenfeld, "Fast, Interactive Origami Simulation using
  GPU Computation", *7OSME*, 2018 — sidestepping the solve with mass-spring
  relaxation.
