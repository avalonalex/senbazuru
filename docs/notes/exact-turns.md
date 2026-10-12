# Exact turns at multiples of 45°

A fold of 180° is a half turn. Its cosine is −1 and its sine is 0, and both
are exact in a `Double`. Folding used to take them from `cos` and `sin` of the
angle in radians, and `pi` is not π: it is about 1.2e-16 short, so `sin pi` is
1.2246467991473532e-16, not 0. A turn built from that moves paper about 1e-16
off its plane. The blintz's written sequence had 13 of its 144 coordinates at
z = −4.33e-17 instead of 0.

`cos` and `sin` are also where the platform gets a say. IEEE 754 requires
addition, subtraction, multiplication, division and square root to round
correctly, so they give the same bits everywhere. It only recommends correct
rounding for sine and cosine, and libraries differ in the last bit, as macOS
and Linux do in `BirdSequenceSpec`. Even correctly rounded, the two disagree at
π/4. The `Double` nearest π/4 is 3e-17 below it, so its true sine rounds to
0.7071067811865475 and its true cosine to 0.7071067811865476, one unit apart.

So `Geometry.Rigid.rotationAboutDegrees` takes the angle in degrees, the units
a FOLD file holds, and at an exact multiple of 45° uses exact values instead:
0 and ±1, and ±√½ as `sqrt 0.5`, the `Double` nearest √½ on every platform.
The test is exact in degrees: 90 is a multiple of 45 and 90.0000001 is not, so
no angle is moved onto a multiple. A model folded only by multiples of 45° then
has positions made of arithmetic and square roots alone, the same bits on any
platform. The blintz's written file is now held to the bit, and CI checks it
on Linux.

What it does not change: any other angle still goes through `cos` and `sin`,
such as the bird's poses at −165° or the crane's creases at 22.5°. And a hinge
along a diagonal still rounds when its axis is normalised, though by square
root and division, which round the same everywhere.

## References

- IEEE Std 754-2019, *IEEE Standard for Floating-Point Arithmetic*: square root
  is among the operations required to round correctly; sine and cosine are
  among those only recommended to.
- David Goldberg, "What Every Computer Scientist Should Know About
  Floating-Point Arithmetic", *ACM Computing Surveys* 23(1), 1991.
- [folding-by-transforms.md](folding-by-transforms.md), for where the turn is
  used, and owner decision 10 in `PRDs/decisions.md`, the same choice made for
  `rotate`.
