# A snapped value has no derivative

The material study measures how far one paper triangle lies above another by
clipping one triangle's shadow by the other's sides (`SurfaceContact`). Each
clipped point carries its value and its derivative with respect to every mesh
vertex, so the solver knows how the gap changes as the paper moves. A corner
within `1e-14` of a clip line is *snapped* onto it: its distance from the line
is set to zero, so rounding cannot put it a hair inside or outside.

Until [#566](https://github.com/avalonalex/senbazuru/issues/566) only the
distance's value was snapped. Its derivative was kept. That looks harmless, and
it is not. Here is the smallest case, from `SurfaceContactSpec`:

- the lower triangle is flat, with one side along y = 0;
- the upper triangle tilts, z = x + 0.1, with one corner at y = 5e-15 and the
  next at y = -1e-13.

The clip finds where that edge crosses y = 0 at the fraction
`t = dp / (dp - dq)` of the way along it, with `dp = 5e-15` snapped to 0 and
`dq = -1e-13`. So `t = 0`, but its derivative is `-∂dp / dq`, about 1e13, and
the contact row's gradient comes out at 3.0e12. Dropping the derivative with
the value makes the snapped distance the constant 0. Then `t` has no derivative
either, and the row's gradient is below 10.

## What it did to the crane wing

Stacked layers of a folded wing have triangle edges that nearly coincide in
projection, so the crane-spreading study met this case. Its solver takes a
Gauss-Newton step: it linearises every penalty about the current positions and
solves the resulting linear system by conjugate gradients, with a sparse factor
of the same system as preconditioner. Its stopping test requires that linear
solve to reach `max(1e-6, 1e-8 · |right-hand side|)`. A slightly penetrating
contact row with a gradient of 1e9 to 1e12 makes the right-hand side 1e4 to
1e7, and the system too ill-conditioned for that: the factor is refused or the
solve stalls near 1% of where it started, for all of its 3000 iterations. The
solve stops only when no such row is penetrating at the end.

That made convergence a matter of luck. With the hinge moved from `wingRoot`
by d, on 2026-10-21 (GHCi probes, one run each):

| d | 0 | +1e-13 | −1e-13 | +3e-13 | −3e-13 | +1e-12 | −1e-12 | +1e-11 | −1e-11 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| before | 24 | **no** | 28 | **no** | **no** | 32 | 23 | 41 | **no** |
| after | 20 | 26 | 22 | 21 | 23 | 24 | 23 | 23 | 23 |

The numbers are the iterations to converge. Every run, before and after, ends
with the same shape: panel energy 0.0131812 to six digits. Only whether the
stopping test passed changed. With the derivative dropped, the largest contact
gradient falls from 1.3e12 to 6.6. The finer mesh at the wing's root, which
[#469](https://github.com/avalonalex/senbazuru/issues/469) found never
converged in 1,004 to 3,343 CPU seconds, converges in 37 iterations and 158
CPU seconds.

Making the factor accept small pivots did not help; the derivative was the
cause.

## Results recorded before the fix

The fix is in `SurfaceContact`, which the material studies share, so any of
them may now solve differently (owner decision 58,
[#566](https://github.com/avalonalex/senbazuru/issues/566)). The crane-spreading
gallery and the quick tier were run again: the quick tier finds the same base
angle, 28.394°, and its picture is byte-identical. The other studies were not.
Notes that report a solve that did not converge, was exhausted or was left
unconverged record runs from before 2026-10-21. Such an outcome may change when
the study is next run, and is to be measured again then, not assumed:
[aligned-crease-hinges](aligned-crease-hinges.md),
[band-refinement-8x2](band-refinement-8x2.md),
[body-angle-preferences](body-angle-preferences.md),
[body-separated-initialization](body-separated-initialization.md),
[checking-numerical-corrections](checking-numerical-corrections.md),
[distributed-bend-preference](distributed-bend-preference.md),
[exposed-area-budget](exposed-area-budget.md),
[held-endpoint-confirmation](held-endpoint-confirmation.md),
[internal-crease-diagnostic](internal-crease-diagnostic.md),
[local-contact-discovery](local-contact-discovery.md),
[outer-strip-refinement](outer-strip-refinement.md),
[quick-tier](quick-tier.md),
[recovered-body-subdivision](recovered-body-subdivision.md),
[reference-contact-discovery](reference-contact-discovery.md),
[several-contact-exchanges](several-contact-exchanges.md) and
[two-held-paper-layers](two-held-paper-layers.md).

## The rule

Wherever a value is replaced by a constant (snapped, clamped, or rounded to a
representable landmark), its derivative must be replaced too. A derivative that
outlives its value describes a point that is no longer there, and the next
division by a small number turns it into a force.
