# A third pair in the body correction

The [two-pair comparison](body-contact-pairs.md) could take 1/8 of its proposed
correction, but pair **46–70** crossed at 1/4. This experiment adds that pair's
contact inequalities at exactly the same saved blocked shape. It preserves the
archived ordinary proposal, matched unconstrained quadratic, and one-pair and
two-pair calculations as four controls. [#336](https://github.com/avalonalex/senbazuru/issues/336)
tracks the experiment; the [glossary](../glossary.md) defines material
coordinates, panels, contact and layers.

The added pair **does not change the direction at all**. Its four inequalities
are already satisfied by the two-pair proposal, so all four carry zero contact
force. The first usable fraction stays **1/8**, with cost down **1.256878%**;
1/4 still crosses 46–70. This identifies a limit of the local gap prediction,
not a missing contact pair.

```bash
stack run senbazuru-material-study -- --body-third build/fold-material/body-geometry build/fold-material
```

The source still has 87 vertices, 120 triangles and three exact holds. Material,
crease preferences, panel bending, length weight `1e8`, contact weight `1e10`,
damping `1e-3`, the 100-iteration quadratic budget and all 31 trial fractions
are unchanged. A quadratic approximates each error as a linear function of a
small displacement, then minimizes the sum of their squares. Each direction
must pass its own numerical checks before cost descent and independent geometry
checks can select a trial. Full proposed movement, before shortening, still
determines whether the paper has settled.

Pair 46–70 has four corners in its projected overlap. Triangle 70 is declared
above 46. Their signed height gaps are approximately `3.03966e-6`, `-5.69491e-9`,
`8.88596e-5` and `4.47704e-3` sheet units. The second gap is slightly negative
already, within the unchanged contact tolerance. The same guard
`a · d + max(0,g) ≥ 0` applies: `g` is the starting gap and `a` says how it
changes as free coordinates move by `d`, including the motion of the overlap
corner. Negative starting gaps may not worsen to first order; positive gaps
may close to zero. Negative gaps remain in the original objective, and the
actual displaced triangles still receive all geometry checks. A guard is
neither a repair of the starting shape nor a motion certificate.

There are now twelve inequalities, but still only two active contacts: the
same corners at 22–63 and 55–14 as before. “Active” means the local calculation
treats the inequality as an equality. The quadratic converges in three
internal iterations, with zero inequality violation, complementarity residual
`2.45e-20` and force balance `1.45e-8`, below the unchanged `1e-6` cap.
Complementarity means a separated contact exerts no attractive force. Raw
corrections and full proposal positions are exactly equal to the two-pair
control; the new pair's multipliers, or numerical contact forces, are all zero.

The smallest starting gap at 46–70 is `-5.69491e-9`. Its guard predicts a
positive change of `5.67753e-9` for the full proposal. It therefore predicts
less penetration at every fraction. Recomputing the actual overlap tells a
different story:

| Fraction | Predicted smallest signed gap | Actual smallest signed gap | Intersection length | Pair crosses above tolerance? |
| --- | ---: | ---: | ---: | --- |
| Start | -5.69491e-9 | -5.69491e-9 | 1.22940e-6 | No |
| 1/8 | -4.98522e-9 | -7.94888e-9 | 1.43853e-6 | No |
| 1/4 | -4.27553e-9 | -1.61301e-8 | 2.51506e-6 | Yes |
| 1/2 | -2.85614e-9 | -5.02740e-8 | 6.15274e-6 | Yes |
| 1 | -1.73803e-11 | -1.89685e-7 | 1.63368e-5 | Yes |

All lengths and gaps in this table are in sheet units. Each prediction follows
the starting corners using their derivatives; actual gaps come from newly
clipping the displaced triangles. The approximation error is about `2.96e-9`
at 1/8 and `1.19e-8` at 1/4: halving the fraction reduces it roughly fourfold.
That is consistent with an error beyond the first-order approximation. Even
though a numerical trial moves vertices along straight segments, the heights
and corners of their common overlap do not depend linearly on those positions.
This observation does not establish a general error bound.

The independent triangle test asks whether both triangles extend across the
other's plane by more than `1e-7`, with an intersection longer than `1e-7`.
A shallow height error can accompany a longer intersection. The starting
shape and 1/8 have mathematical intersections but pass those existing limits;
1/4 fails the whole-triangle check even though its signed height error is
smaller than the order-reporting tolerance. These are different measurements.
The gap guard cannot replace the final geometry check.

The new direction has 28 geometry-passing fractions and 29 cost-decreasing
fractions, just like the two-pair control. All 31 trial positions, measurements
and acceptance decisions match that control, apart from names identifying the
comparison. The archived and matched ordinary proposals remain blocked at all
fractions; the one-pair control still selects 1/128. See the
[two-pair measurements](body-contact-pairs.md) for their separate energies.
At 1/8, the relative edge error is `2.26002e-6`, all holds stay exact and material
connectivity is unchanged. Movement is below **0.086 drawing pixels** at 600
pixels per sheet unit; full movement remains **11,438 times** the equilibrium
limit. No settled or visibly opened body is established.

The opt-in gallery retains 156 FOLD states and 1,560 SVGs, all five directions,
raw corrections, equations, all-pair refusals and the actual 46–70 overlap
witnesses at every trial. It compares predicted and actual gaps at the selected
fraction and offers all three pairs' fixed overlap and tip views. The 46–70
tip crop includes both the saved start and the two-pair control's refused
quarter-step, so the relevant intersection stays visible at one scale. Larger
trials can leave the crop; the overlap view supplies context. Independent
calculations verify lengths, angles,
separate energies, attachments, crossings, ordered gaps, corner derivatives
and quadratic force balance. The maximum finite-difference error across all
twelve starting corner derivatives is `1.60e-10`. The four previous controls'
original drawings and measurements and every source archive remain unchanged. The existing
analytic guard regressions still run in CI; this fixture adds no costly solve
to the default tests.

Next, try a short continuation of **at most ten corrections**, recomputing the
three pairs' guards at each retained shape and keeping the existing all-pair
geometry gate and fraction search. Stop with the last valid shape if the
quadratic cannot be verified or no fraction passes. A valid short step can
then be followed by a fresh local prediction; it need not make the current
1/4 trial acceptable. This tests whether progress accumulates before changing
the contact formulation. The pair list remains an explicit specimen policy;
automatic discovery, continuous flexible motion and whole-crane inflation are
still separate work.
