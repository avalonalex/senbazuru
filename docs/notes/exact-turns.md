# Turns at multiples of 45° need no trigonometry

A fold of 180° is a half turn. Its cosine is −1 and its sine is 0, and both
are exact in a `Double`. Folding used to take them from `cos` and `sin` of the
angle in radians, and `pi` is not π: it is about 1.2e-16 short, so `sin pi` is
1.2246467991473532e-16, not 0. A turn built from that moves paper about 1e-16
off its plane. In the blintz base, a square with its four corners folded to
the centre, the written sequence had 13 of its 144 coordinates at
z = −4.33e-17 instead of 0.

`cos` and `sin` are also where the platform gets a say. IEEE 754 requires
addition, subtraction, multiplication, division and square root to be
*correctly rounded*: the exact result rounded to the nearest `Double`, so
every platform gives the same bits. For sine and cosine it only recommends
that, and libraries differ in the last bit, as macOS and Linux do in
`BirdSequenceSpec`. Even correctly rounded, the two disagree at π/4. The
`Double` nearest π/4 is 3e-17 below it, so its true sine rounds to
0.7071067811865475 and its true cosine to 0.7071067811865476: neighbouring
`Double`s, one unit in the last place apart.

So `Geometry.Rigid.rotationAboutDegrees` takes the angle in degrees, the units
a FOLD file holds, and at an exact multiple of 45° uses 0 and ±1, and ±√½ as
`sqrt 0.5`. √½ is not exact, but `sqrt 0.5` is correctly rounded, so it is the
same `Double` on every platform. The test is exact in degrees: 90 is a
multiple of 45 and 90.00000000000001 is not, so no angle is moved onto a
multiple.

The right cosine and sine are not quite enough. Rodrigues' formula writes
each diagonal entry as (1 − cos θ) x² + cos θ, and at 135°, where cos θ is
−√½, 1 − cos θ is 1 + `sqrt 0.5`, which is not a `Double` and rounds. A turn
about a coordinate axis then had 0.9999999999999999 in its matrix where 1
belongs, so it moved its own axis. Written as x² + (1 − x²) cos θ, the same
number, the matrix of a turn about a coordinate axis holds 0, 1, cos θ and
±sin θ and nothing else, at every multiple of 45°. A point's position still
rounds wherever √½ multiplies it.

A model folded only by such angles then has coordinates made of arithmetic
and square roots alone, the same bits on any platform, and the blintz's
written file is held to the bit. What this does not reach: any other angle,
such as the bird's poses at −165° and 30°; the noise left where a hinge runs
along a diagonal, which comes from normalising its axis with a square root
and a division and so is the same everywhere; and the sweep that checks a
turn and the tracing of faces, which still use `cos`, `sin` and `atan2`.

## References

- IEEE Std 754-2019, *IEEE Standard for Floating-Point Arithmetic*: square root
  is among the operations required to be correctly rounded; sine and cosine
  are among those only recommended to be.
- David Goldberg, "What Every Computer Scientist Should Know About
  Floating-Point Arithmetic", *ACM Computing Surveys* 23(1), 1991.
- [folding-by-transforms.md](folding-by-transforms.md), for where the turn is
  used, and owner decision 10 in `PRDs/decisions.md`, the same choice made for
  `rotate`.
