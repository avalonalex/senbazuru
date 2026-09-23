# Why the moving-plane guard misses a finite loss

[The extra plane guard](body-plane-guard.md) predicts almost no change in
vertex 27's distance to triangle 70, yet the saved **1/128** trial crosses
46–70. The **1/256** trial passes. This inspection accounts for that difference
using both archived directions and all 62 saved trials; **no new solve runs**.
[#347](https://github.com/avalonalex/senbazuru/issues/347) tracks the work.
[The glossary](../glossary.md) defines panels, material coordinates and contact.

**The main missed term is the interaction of relative vertex movement with
plane rotation.** At 1/128 it accounts for about **98%** of the loss missing
from the additional guard's linear prediction. The remaining roughly 2% comes
from the plane normal departing from its initial rotation rate. These shares
use the triangle centroid as the reference point. They are geometric accounting
terms, not unique physical forces or independently possible paper movements.

```bash
stack run senbazuru-material-study -- --body-plane-loss build/fold-material/body-plane build/fold-material
```

The centroid is the average of triangle 70's three corners, `[81,71,20]`.
A normal is a unit-length arrow perpendicular to its plane. Write `r` for the
vector from the centroid to vertex 27 and `n` for that normal. The signed
distance is `n·r`: the component of the relative position along the normal.
The normal keeps the triangle's original winding. Referencing the centroid
makes the accounting independent of which corner is listed first, although
choosing a different reference could redistribute the individual terms.

At the rejected 1/128 trial, the linear prediction contains approximately
`-5.000068006e-7` sheet units from relative movement and
`+5.000068006e-7` from initial plane rotation. They cancel. But the plane turns
about **0.001076°** during the trial, and that changed normal also acts on the
changed relative position. The linear prediction omits this product.

The finite identity is exact before rounding. Subscript `0` means the start,
`dr = r-r0`, and `dn = n-n0`:

```text
d - d0 = n0·dr + dn·r0 + dn·dr
         motion  rotation  interaction
```

Subtract the initial linear prediction from this identity. What remains is
`(dn - s*n1)·r0`, the normal's departure from its initial rate `n1`, plus the
interaction `dn·dr`. A small separate term records rounding of the relative
position along the saved numerical path. The final reconciliation residual
is also exported rather than assigned to a physical effect.

| Additional-guard fraction | Rotation remainder, ×1e-12 | Interaction, ×1e-12 | Actual distance loss, ×1e-12 | Margin above −1e-7, ×1e-12 | 46–70 crosses |
| --- | ---: | ---: | ---: | ---: | --- |
| 1/512 | −0.005756 | −0.282478 | −0.288235 | +0.874957 | No |
| 1/256 | −0.023031 | −1.129907 | −1.152939 | +0.010253 | No |
| 1/128 | −0.092173 | −4.519583 | −4.611757 | −3.448565 | Yes |

The starting margin is only **1.163192e-12** sheet units. Doubling the fraction
nearly quadruples the loss, so 1/128 exhausts that margin despite its essentially
zero linear distance change. The table uses independent 60-digit arithmetic
on the literal saved coordinates. Double-precision accounting agrees within
`5.24e-18` sheet units across both directions and all fractions. Centroid and
corner-based distance formulas can differ in their last digits through rounding;
the saved pass/refusal decisions do not change.

A second-order estimate adds terms proportional to `s²`. Both the rotation
remainder and the interaction contribute, with normalization of the normal
included. For 1/128 its distance differs from the high-precision saved result
by about **4.3e-19** sheet units; for 1/256, about **5.8e-19**. This local estimate
explains the refusal well. It is not a replacement acceptance rule, proof of
finite-step feasibility or a certificate for the intervening motion. At the
tiniest fractions, rounding dominates the remaining difference and percentage
shares are not meaningful. The unguarded control retains its nonzero negative
linear term as well as a smaller finite remainder.

The gallery keeps the original FOLD files and all 378 paper SVGs byte-for-byte.
Both directions display the same fraction, camera and crop. The 31 new bar
charts magnify numerical losses, with one shared scale per fraction; paper
positions are unchanged. Every trial's accounting, normal vectors, second-order
terms, reconciliation residual and original report remains in JSON. The reader
validates the preceding 310-trial archive, both proposals, all 62 trial meshes,
material identities, holds, selected fractions and geometry/cost measurements.
Archived quadratic reports are retained; no quadratic solution is recomputed.

Seven fast coordinate tests cover exact translation, a fixed plane, cancelling
linear terms with a known finite loss, cyclic corner order, rigid coordinate
changes, reversed winding, rounding and invalid input. Independent 60-digit
calculations check every decomposition and its distance-threshold decision.
Source copies and 4,692 earlier assets remain unchanged. All 1,869 tests pass
after a warning-free cold build (160.2 seconds of test time), with clean
formatting, HLint 3.10 including CI's JSON command, and JavaScript checks.
The seven new tests take 0.0007 seconds; no material solve is added to CI.
An altered saved fraction is refused before any output is written. All 31
fractions and six paper views work in the browser; the charts keep both
directions on one scale and remain readable at the smallest fractions.

A useful next bounded experiment is **one small contact-restoration correction
at the refused 1/128 trial**: adjust its positions to recover the finite distance
loss, with exact holds and the existing overlap guards, then apply the same
all-pair geometry and actual-cost checks. Keep the original trial as a control.
That would test whether the missed second-order term can be repaired without
shrinking the main step again; it must not assume success or start a continuation.
The current endpoint remains unsettled. No whole-crane opening or flexible
folding route is established, and this outside-triangle plane guard remains
a local fixture policy.
