# Kawasaki's theorem without trigonometry

[Kawasaki's theorem](kawasaki.md) says a vertex folds flat exactly when its
sector angles alternate to zero: `a1 - a2 + a3 - ... - a2n = 0`. The obvious
implementation is the one senbazuru has — take `atan2` of every crease
direction, sort, difference, add up with alternating signs, and compare the
result against a tolerance.

That tolerance is a judgement call, and it can be wrong in either direction:
too tight and a correct pattern written down to six decimal places is rejected,
too loose and a genuinely wrong angle slips through. It turns out the whole
question can be answered in exact arithmetic instead, with no angles, no
tolerance and no `atan2`.

## The identity

Treat each crease direction as a complex number: the crease leaving the vertex
towards `(x, y)` becomes `x + yi`. The one fact needed is that multiplying
complex numbers adds their angles, so `arg(d2 / d1)` is the angle you turn
through going from crease 1 to crease 2 — which is the sector between them.

Number the creases `d1 ... d2n` in rotational order, so sector `a_i` sits
between `d_i` and `d_i+1`. The odd-numbered sectors are then
`arg(d2/d1)`, `arg(d4/d3)`, and so on, and because arguments add:

    a1 + a3 + ... + a(2n-1) = arg( (d2/d1) * (d4/d3) * ... * (d2n/d2n-1) )

The sectors together make one full turn, so `sum of odds = 180°` says exactly
the same thing as `alternating sum = 0`. And `180°` is the argument of a
negative real number. So:

> Kawasaki's condition holds if and only if that product is a negative real.

Division is easy to remove. Multiplying a complex number by the conjugate of
another, rather than dividing, differs only by a factor of `|d|²` — a positive
real, which changes neither "is this real?" nor "is the real part negative?".
So the test is on

    N = (d2 * conj(d1)) * (d4 * conj(d3)) * ... * (d2n * conj(d2n-1))

    Kawasaki holds  <=>  Im(N) = 0  and  Re(N) < 0

and `N` is built from the coordinates with nothing but `+`, `-` and `*`.

## The step that looks like a hole

`arg` only ever tells you an angle *modulo* a full turn, so the identity above
seems to prove `sum of odds ≡ 180° (mod 360°)` and not `sum of odds = 180°`.
The gap closes for a reason that has nothing to do with complex numbers: every
sector is positive, and all `2n` of them add to one full turn, so the odd ones
alone add to something strictly between `0°` and `360°`. Only one number in that
range is congruent to `180°`. Nothing is being waved through.

## A worked example, in integers

Four creases towards `(3,4)`, `(-4,3)`, `(-3,-4)` and `(4,-3)` — each the
previous one turned by a right angle, so the sectors are `90, 90, 90, 90` and
Kawasaki plainly holds. Pairing them off:

    d2 * conj(d1) = (-4+3i)(3-4i) =   25i
    d4 * conj(d3) = ( 4-3i)(-3+4i) =  25i
    N             = (25i)(25i)     = -625

Real, and negative: it passes, and `-625` is exact — no rounding happened
anywhere. Now move the last crease to `(1,-1)`, which tilts it by about 8° and
should break the theorem:

    d4 * conj(d3) = (1-i)(-3+4i) = 1 + 7i
    N             = (25i)(1+7i)  = -175 + 25i

`Im(N) = 25`, so it fails — and again with no tolerance, because the answer is
an integer that is either zero or not. For comparison, the floating-point route
gives an alternating sum of `-16.26°` for this vertex, which is the same verdict
reached by a route that has to be told how close to zero counts as zero.

## What it costs, and why senbazuru does not do it

Two things.

The sort is still comparisons, not arithmetic. Putting creases in rotational
order without `atan2` means a comparator: which half-plane is the direction in,
and then the sign of a cross product — the
[orientation predicate](robust-predicates.md), which is exact for rational
inputs but is a second thing to get right.

And exact means `Rational`. A `Double` coordinate is already an exact binary
fraction, so nothing is lost converting, but `N` multiplies `2n` of them
together and the numerators grow accordingly. For a vertex of degree eight that
is nothing; it is not free.

Against that, `Senbazuru.Origami.FlatFold` uses `atan2` and a tolerance of
`1e-5` radians, defended in the Haddock for `defaultTolerance` and adjustable
with `senbazuru check --tolerance`. The reason is that a tolerance is one line
that any reader understands, and this is a project that prefers the explicit
version. Worth revisiting the day a real file lands on the wrong side of `1e-5`
— the escape hatch is written down above, and it is exact.

## References

- Thomas Hull, *Origametry*, Cambridge University Press, 2020.
- Jonathan Shewchuk, "Adaptive Precision Floating-Point Arithmetic and Fast
  Robust Geometric Predicates", 1997 — the standard treatment of doing this
  kind of thing exactly without paying for it everywhere.
