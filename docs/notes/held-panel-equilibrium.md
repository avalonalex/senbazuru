# Let the held paper settle

The [whole-bend comparison](whole-bend-refinement.md) placed more triangles
through a prescribed curved region. That improved geometric approximation,
but the curve was supplied in advance. This experiment lets the paper change
shape between its grips. All four solves settle and pass the paper checks;
neither placement meets the separate 5% bending-cost refinement target.

The unit square is folded in half into two touching panels. Hold both panels
flat within `1/8` sheet length of the shared crease, and hold their outer edges
at the original [held-bend target](prescribed-held-bend.md). Everything between
the grips can move in all three directions. **Passive bending** is the cost
of bending inside a panel, whose springs prefer flat paper. Its coefficient
stays `0.2`; the original crease keeps its `pi` target and `0.5` stiffness.
There is no imposed bend preference or new external load.

Both layouts have two strips across the width and either 128 or 256 triangles
over the complete sheet. Uniform spacing divides material length evenly.
Whole-bend placement retains density four from `1/8` through `1/8 + A`, and
one outside, where `A = 0.14302268438467985` is the fixed smooth reference's
curved length. The rule from #301 is fixed before solving; it does not follow
the eventual bend or consult its cost. #303 records the four-case design.

Every seed samples that same smooth curve. Straight triangle edges shorten
its curved arcs, so the seed deliberately fails the length cap. It retains
the original material lengths rather than making the shortened edges the
new rest lengths. All four seed positions reproduce the previous sampled
archives exactly on this run. The common curve's endpoint roundoff correction
is zero; the constructor permits at most `1e-12` before imposing the exact
authored grip. It never pins a drifting full-length polygon's endpoint.

Run the opt-in experiment from the repository root:

```bash
stack run senbazuru-material-study -- --held-equilibrium build/fold-material
```

Open `build/fold-material/held-equilibrium.html`. The unchanged solver uses
`ProgressiveContactExchange`, length weights
`1e2, 1e4, 1e6, 1e8, 1e9, 1e10`, and at most 40 iterations per stage.
Its existing quadratic residual, movement and line-search checks are unchanged.
Final paper acceptance additionally requires exact holds and material identities,
relative edge error at most `1e-5`, original crease error at most `1e-5` radians,
the independent whole-sheet contact check at `1e-7`, and exact nonnegative
lower/upper gaps. Numerical contact repairs and the full histories are exported.
These are solver corrections, not a continuously checked folding motion.

| Layout | Triangles | Iterations | CPU seconds | Largest relative edge error | Passive cost per panel |
| --- | ---: | ---: | ---: | ---: | ---: |
| Uniform | 128 | 63 | 21.18 | `1.44e-7` | 0.108683989 |
| Whole bend | 128 | 86 | 34.66 | `3.37e-7` | 0.095760931 |
| Uniform | 256 | 60 | 48.14 | `4.73e-7` | 0.115741248 |
| Whole bend | 256 | 63 | 55.69 | `1.52e-6` | 0.103722640 |

Lower and upper costs agree within `1.1e-13`; both are exported separately.
The panels move about `0.0080–0.0087` sheet lengths from their starting curve.
Exact minimum gaps are zero and maximum opening stays below `7.44e-14`.
All four endpoints classify the same 1,480 fixed projected sample locations
as touching within `1e-7`; the remaining 120 lie outside the overlap.
Those counts are not exact areas. Shared crease vertices remain `0/1/2`,
all grips stay exact, and original crease error is below `2.45e-16` radians.

The whole-material comparison intersects triangles in their original sheet
coordinates, then measures the positional difference at every overlap corner.
The difference is linear inside each overlap, so its largest length is at a
corner. This includes unmatched vertices and remains valid when the solved
shape varies across width; comparing only a centre profile would miss that.

| Comparison | Largest displacement, sheet lengths | Passive cost change per panel |
| --- | ---: | ---: |
| Uniform 128 → 256 | 0.000703753 | +6.4934% |
| Whole bend 128 → 256 | 0.001170025 | +8.3142% |
| Uniform → whole bend, 128 | 0.001115741 | −11.8905% |
| Uniform → whole bend, 256 | 0.000739557 | −10.3840% |

Signs show the direction of the cost change; target checks use its absolute
value divided by the first case's cost. Uniform refinement meets the `0.001`
shape target, but whole-bend refinement does not. Both miss the 5% passive-cost
target. Opening is essentially zero, so the report uses absolute changes
instead of percentages. Original-crease and imposed costs remain essentially
zero. Final length costs are `2.73e-5 / 5.18e-5 / 6.62e-5 / 4.87e-4` in table
order, separate from bending. These are model costs, not calibrated joules.

A lower discrete cost is not evidence of a more accurate equilibrium. The
meshes offer different places to bend, and the solver can choose different
shapes there. The prescribed smooth curve's analytic cost is therefore not
the target for these solved shapes. This does not resolve the old 8.99%
comparison, establish a global energy minimum, or select a default grid.
Width refinement and a tighter-solve confirmation also remain untested here.

Independent reconstruction verifies 12 FOLD/GLB states, 4,056 material edges,
2,856 springs and all four whole-sheet comparisons. Exact rational triangle
clipping reproduces every gap extremum and all 19,200 projected samples.
All 36 SVGs parse, all twelve browser selections work, and 4,604 previously
generated JSON/FOLD/SVG assets remain
byte-for-byte unchanged. Five fixture regressions take 0.18 seconds; the four
material solves stay opt-in rather than extending the CI test sweep.

Next, locate the passive costs and bend angles on these four saved endpoints,
especially near the fixed/free boundary, without new solves. That can show
whether the difference is concentrated at the hold or spread across the free
paper before choosing another solver or mesh experiment. Keep tighter-solve
confirmation, width refinement and any default-policy decision separate.

Tracked in [#303](https://github.com/avalonalex/senbazuru/issues/303), continuing
[#195](https://github.com/avalonalex/senbazuru/issues/195) and track A of
[#269](https://github.com/avalonalex/senbazuru/issues/269).
