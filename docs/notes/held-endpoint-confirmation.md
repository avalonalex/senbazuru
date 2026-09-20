# Confirming the held-panel stopping threshold

Tightening the movement stop tenfold barely changes either 256-triangle
[held-panel endpoint](held-panel-equilibrium.md). Extra motion stays below
`8.1e-8` sheet lengths and passive costs change by less than `0.00001%`.
The 6.49% / 8.31% refinement differences survive. This experiment finds no
substantial contribution from the original stopping threshold on these two
fine meshes; it does not establish mesh independence or a global minimum.

Run from the repository root with the original four saved equilibria:

```bash
stack run senbazuru-material-study -- --held-confirmation \
  build/fold-material/held-equilibrium build/fold-material
```

Open `build/fold-material/held-confirmation.html`. #308 fixes the experiment
before either solve: restart only uniform-256 and whole-256, allow at most
40 additional iterations each at final length weight `1e10`, and change the
full repaired proposal stop from `1e-7` to `1e-8` sheet units. A proposal is the
solver's suggested vertex motion before shortening it to reduce cost. Testing
that full motion prevents a tiny accepted fraction from pretending to be rest.
The contact method, inner quadratic settings, material springs, exact grips,
flat rest angles and all paper acceptance caps remain unchanged. Existing
solver callers retain `1e-7`; the new threshold is opt-in.

Saved positions are a starting guess, never a new rest shape. All four input
reports are checked against the authored fixtures, historical convergence and
fresh measurements before any output or solve. Original report and endpoint
FOLD bytes are retained. The 128-triangle endpoints are only remeasured. A
refusal, budget exhaustion or failed paper check remains diagnostic in the
report and gallery rather than becoming an accepted result.

| Continuation | Uniform, 256 triangles | Whole bend, 256 triangles |
| --- | ---: | ---: |
| Additional iterations, including the stopping check | 4 | 3 |
| Final full proposal, sheet lengths | 5.6565e-9 | 9.0381e-9 |
| Largest movement from saved endpoint | 8.0945e-8 | 3.0784e-8 |
| Lower passive cost change | +4.3083e-9 | +9.4198e-9 |
| Lower passive relative change | +0.0000037223% | +0.0000090817% |
| Length-penalty cost change | −8.6335e-9 | −1.8848e-8 |
| Total cost change | −1.7115e-11 | −8.2176e-12 |
| CPU seconds on this run | 3.03 | 2.55 |

The upper passive changes agree with the lower changes within `1.1e-13`;
both remain separately exported. Passive springs prefer flat paper and measure
turns between triangles (see [the glossary](../glossary.md)). Their tiny cost
increase is possible because length-penalty cost falls slightly more than the
sum of both passive increases. The line search minimizes twice the sum of
length, lower passive, upper passive, original crease and imposed costs;
it does not require each component to decrease. Original crease cost is
unchanged and imposed cost remains zero.

Both runs converge and pass unchanged paper checks: exact holds and shared
material identities, relative edge error at most `1.523e-6` against the `1e-5`
cap, original crease error `2.45e-16` radians, whole-sheet contact, and exact
nonnegative panel gaps. Neither restart needs a feasibility displacement.
Maximum opening stays below `6.35e-14` sheet lengths. Each continued state has
1,480 touching samples, 120 outside the projected overlap, and no separated
or crossing samples, using the same 1,600 locations and `1e-7` contact threshold.

The [previous fixed bins](held-bending-costs.md) remain unchanged. Assign each
spring to its material edge midpoint; this accounts for cost without claiming
an energy density over its neighboring triangles. Lower-panel changes are:

| Region | Uniform | Whole bend |
| --- | ---: | ---: |
| Held interior | 0 | 0 |
| Held boundary | +1.2829e-8 | −1.0894e-8 |
| First free interval | +2.1320e-8 | +1.3479e-8 |
| Remaining free paper | −2.9841e-8 | +6.8348e-9 |

These changes are tiny beside the original refinement contributions of roughly
`0.0037–0.0072` per nonzero bin. No springs are added or removed during these
continuations; their material coefficients stay fixed. The changes come from
the measured angles on the slightly moved shapes.

Comparing unchanged coarse endpoints to the continued fine endpoints gives
whole-material displacement `0.000703761` / `0.001170005` and passive changes
`6.493379%` / `8.314162%` for uniform / whole-bend placement. The two continued
fine endpoints differ by `0.000739524` and `10.384027%`. These essentially
reproduce the original comparisons: both refinements still miss the 5% cost
target and whole-bend still misses the `0.001` shape target. The coarse solves
retain their old stop; this is not a claim that both resolutions were confirmed
at `1e-8`. Lower discrete cost alone does not choose the more accurate mesh.

Independent Python reconstruction checks eight FOLD states, 3,152 edge lengths,
2,224 spring angles/coefficient costs, nine whole-material comparisons and
fixed-bin sums. Rational triangle clipping reproduces exact gap extrema and
12,800 samples. All eight complete-sheet GLBs retain both windings and every
triangle; their largest packed-coordinate discrepancy is below `8.44e-7`,
while measurements use unrounded FOLD coordinates. All 28 SVGs parse without
geometry transforms. All 5,631 historical FOLD/JSON/SVG/GLB assets are unchanged.
The gallery exercises both meshes, all three numerical states and both cost
panels. A small CI regression distinguishes the full-proposal stop from a
budget-exhausted accepted step and rejects invalid thresholds; the two full
confirmation solves remain opt-in.

A useful next bounded experiment is **256 → 512 triangles on both layouts**,
keeping the two width strips, material, grips and contact policy. Use the
original six-stage policy followed by the same `1e-8` final confirmation, so
the new endpoints can be compared with these confirmed 256-triangle states.
Retain refusals or exhaustion as diagnostic. This adds a third length resolution
to test whether the cost differences shrink, rather than choosing a layout
because it has lower cost. No such solve runs here. Width refinement, real-paper
stiffness calibration and a continuously checked flexible route remain separate.
