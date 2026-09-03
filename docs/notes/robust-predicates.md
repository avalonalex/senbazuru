# The orientation test, and why Double breaks it

The fundamental primitive of 2D computational geometry is: given points `a`,
`b`, `c`, is `c` left of the line `ab`, right of it, or exactly on it? It is the
sign of a determinant:

    orient(a, b, c) = (bx - ax)(cy - ay) - (by - ay)(cx - ax)

Evaluated in floating point this returns the **wrong sign** when the three
points are nearly collinear. Subtracting two nearly-equal products leaves
rounding noise, and the sign of noise is arbitrary.

"Wrong" here is worse than it sounds. It is not that the answer is slightly off
-- there is no "slightly" about a sign. It is that an algorithm can ask "is `c`
left of `ab`?" and "is `a` left of `bc`?" and receive answers that no actual
arrangement of three points could produce. Fed contradictions, a convex hull
routine can return a non-convex polygon, crash, or loop forever. Kettner et al.
have a whole paper of worked examples doing exactly this.

Origami is a bad case rather than an average one: crease patterns are full of
exactly collinear points, exact symmetry, and coordinates like `sqrt(2)/2` that
arise the moment you fold a diagonal.

The standard fix is Shewchuk's *adaptive precision* predicates -- compute a
cheap floating-point estimate together with an error bound, and fall back to
exact arithmetic only when the estimate is not provably correct. Fast in the
common case, and never wrong.

## Why it matters here

Nothing in senbazuru evaluates a geometric predicate *yet*. `fitBox` only scales
and translates, which is why `Senbazuru.Geometry` gets away with plain `Double`.
The moment [convex hull](convex-hull.md) arrives for fold arrows, this stops
being background reading.

## References

- Jonathan Shewchuk, "Adaptive Precision Floating-Point Arithmetic and Fast
  Robust Geometric Predicates", *Discrete & Computational Geometry* 18(3), 1997.
- Kettner, Mehlhorn, Pion, Schirra & Yap, "Classroom Examples of Robustness
  Problems in Geometric Computations", *Computational Geometry* 40(1), 2008.
