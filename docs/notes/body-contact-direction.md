# Contact can guide the next body correction

The [previous continuation](body-geometry-continuation.md) ended at a valid
but unsettled body-patch shape. Every fraction of its next proposed correction
crossed triangle pair **22–63**. [#329](https://github.com/avalonalex/senbazuru/issues/329)
changes the direction calculation at that saved shape: ask the four corners of
this pair's projected overlap to respect their current separation, then check
the actual paper again. The first usable fraction is **1/128**, lowering cost
**0.085385%** with all existing geometry checks passing. The next larger
fraction instead crosses **14–55**. This fixes one local obstruction, without
establishing a settled or visibly opened body. See the [glossary](../glossary.md)
for material coordinates, panels, contact and layers.

```bash
stack run senbazuru-material-study -- --body-direction build/fold-material/body-geometry build/fold-material
```

The starting archive has 87 vertices, 120 triangles and three exact holds.
Original crease preferences, panel bending, length weight `1e8`, contact weight
`1e10` and damping `1e-3` remain unchanged. A quadratic is the simple local
cost obtained by approximating each length, angle and gap error as a linear
function of a proposed displacement `d`. `ContactQuadratic` minimizes that
cost with additional inequalities; it has a budget of 100 internal iterations.
This is one direction test, not a nonlinear continuation.

The four signed gaps are approximately `4.53e-10`, `5.52e-4`, `2.50e-4` and
`-2.42e-12` sheet units. Positive means the declared upper layer is above the
lower. The last corner is already very slightly on the wrong side, within the
unchanged reporting tolerance. If its derivative is `a`, the new guard is
`a · d + max(0,g) ≥ 0`. For a negative starting gap `g`, the correction may not
make it worse to first order. For a positive gap, it may close to zero. Thus
zero displacement remains feasible without moving the starting paper or
claiming it has been repaired. The actual negative gap still contributes its
full penalty to the original cost. The derivatives include movement of the
clipped corners, not just movement of the triangle planes.

The comparison retains two controls. The archived proposal is read unchanged.
A matched unconstrained quadratic uses the same equations and factorization
as the new constrained calculation, isolating the effect of the inequalities.
It differs from the archived proposal by at most `1.59e-10` sheet units. Both
controls fail geometry at all 31 fractions; both reduce cost at 29 fractions.

The constrained quadratic converges in two internal iterations with one active
contact: the negative-gap corner prevents further closing. Its inequality
violation and complementarity residual are zero, and its force-balance residual
is `1.59e-8`, below `1e-6`. Complementarity means separated paper does not exert
an attractive contact force. These checks establish a solved local quadratic,
not equilibrium of the nonlinear paper. Raw correction vectors are exported
alongside rounded proposal positions: subtracting those positions loses low
bits that the large penalty weights can amplify in a force-balance check.

| Measurement | Saved blocked shape | Selected 1/128 trial |
| --- | ---: | ---: |
| Original crease cost | 0.0119682881 | 0.0119615003 |
| Panel bending cost | 0.0012017776 | 0.0011973314 |
| Length cost | 0.0000158226 | 0.0000158029 |
| Contact cost | 0.000000576159 | 0.000000570634 |
| Total cost | 0.0131864645 | 0.0131752053 |
| Maximum relative edge error | 1.63680e-6 | 1.64285e-6 |
| Body depth | 0.0361928140 | 0.0361931870 |
| Pair 22–63 intersection length | 9.99997e-8 | 7.65916e-8 |

Cost is half the squared-error solver objective, excluding numerical damping.
All 24 fractions from 1/128 through `2^-30` pass geometry; 29 of the 31 reduce
cost. At **1/64**, pair 22–63's intersection is shorter still (`6.00174e-8`),
but **14–55 crosses**. Guarding one pair is therefore not permission to skip
the independent all-pair check. That check, connected material, exact holds
and the original `1e-5` length / `1e-7` contact limits still gate selection.
Passing can permit smaller mathematical intersections; no clearance or paper
thickness has been added.

The selected displacement is `8.88722e-6` sheet units, at most **0.00533 pixels**
at 600 pixels per unit. The full proposed movement remains `1.13756e-3`, about
**11,376 times** the equilibrium limit. Neck and tail landmarks move
`1.29894e-6` and `2.35598e-6`; all three holds stay exact. The largest crease-angle
change is `0.0109302°`. Neither control nor the new trial is an accepted settled
body opening. The patch omits the surrounding crane's loads, and no continuous
flexible motion or pressure response is certified.

The gallery retains 94 FOLD states, separate costs, all directions and equations,
all 93 trial decisions, actual-size views and matched overlap/tip close-ups.
Independent calculations check the costs, lengths, angles, attachment positions,
all-pair crossings and declared-order gaps, plus the quadratic force balance.
The source archive stays byte-for-byte unchanged. Only three small analytic
contact-guard regressions enter CI; this experiment remains opt-in.

Next, compare a direction guarding **both 22–63 and 14–55** from this same saved
shape. Keep the two controls, quadratic budget and final gates. That isolates
whether addressing the newly exposed obstruction permits a larger useful
correction before committing to another continuation.
