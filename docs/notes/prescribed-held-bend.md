# The same grips still permit different bending costs

The [uneven-mesh references](prescribed-uneven-bends.md) moved the original
outer grips. This control retains them: the inner strip stays flat to material
distance `1/8`, then a circular arc joins a straight section ending at the
original outer position. Its tangent, the direction along the profile, joins
continuously at both ends of the arc. No new crease is introduced.

```bash
stack run senbazuru-material-study -- --held-bend build/fold-material
```

Open `held-bend.html` on the study server. The coarse, outer-only, rest-only
and fine meshes still have 64, 72, 120 and 128 triangles. All retain their
original material, passive springs, shared crease and held vertex identities.
Both material panels follow the same profile and touch exactly. This is a
prescribed geometric family, not a material-equilibrium solve or a folding
route.

After the flat inner strip, `3/8` of material remains. Its original endpoint
relative to that strip is `(0.342267166025, 0.141636737774)` in the side view.
For an arc of radius `R`, final angle `θ` and remaining straight length `q`:

```text
x = R sin θ + q cos θ
z = R (1 − cos θ) + q sin θ
available length = R θ + q = 3/8
```

The first two equations give `R` and `q` for each trial angle. Repeatedly
halving an angle bracket solves the last equation, with no energy evaluation.
The common smooth reference has curvature `1/R = 3.058080151255`, arc length
`0.163868215857` and straight length `0.211131784143`. Curvature measures how
quickly the tangent turns per unit material length. The arc ends at material
distance `0.288868215857`, inside a mesh strip rather than on a column.

Three constructions separate length error from changing that reference:

| Construction | Original grips | Material edge lengths | Shape shared across meshes |
| --- | --- | --- | --- |
| Exact samples | Exact | Chords are too short | Same smooth reference |
| Full-length chords | Outer grip drifts | Preserved | Same reference directions; sampled positions differ |
| Full-length, fitted | Exact | Preserved | Curvature and arc length change per mesh |

For the second construction, replace each sampled chord by a vector in the
same direction with the strip's full material length. For the third, fit the
two curve parameters to the two outer-position coordinates before constructing
those vectors. The inner strip stays untouched. The small geometric fit uses
an analytic matrix describing how the endpoint responds to each parameter;
finite differences independently verify that matrix. It never reads spring
costs or contact forces. Coarse and outer-only need five steps; rest-only and
fine need three. All steps and residuals remain in the exported JSON.

Copying a missed outer grip back could stretch the last strip. Here copying
is allowed only after the raw position is within `1e-14` sheet lengths of the
target, and every final edge is measured afterward. The largest copy adjustment
is `7.70e-16`. All four fitted meshes keep both grip regions exactly and their
largest relative edge error is `2.89e-15`, below the unchanged `1e-5` cap.
They have one connected component, shared vertices 0/1/2, original crease-angle
error below `2.45e-16` radians and exactly zero known-order gaps. This accepts
their prescribed geometry, not their equilibrium or a path to reach it.

The controls remain diagnostic. Samples keep the grips but have relative
edge errors `0.00152142` on coarse/outer-only and `0.000380484` on rest-only/fine.
Unfitted full-length chords keep the lengths but miss the outer grip by
`0.000236690` and `0.0000594536` sheet lengths. Length costs at numerical
weight `1e10` stay separate from all angular costs.

Passive bending costs per panel are:

| Mesh | Common curve, sampled or full-length | Fitted full-length polygon | Integral for fitted curve |
| --- | ---: | ---: | ---: |
| Coarse | 0.125641304 | 0.123916895 | 0.150288424 |
| Outer only | 0.125641304 | 0.123916895 | 0.150288424 |
| Rest only | 0.139131537 | 0.138760413 | 0.152484558 |
| Fine | 0.139131537 | 0.138760413 | 0.152484558 |

The common smooth integral is `0.1 κ² A = 0.153247166`, where `κ` is curvature
and `A` the arc length. These are costs of the current rule, not measured
joules. On each mesh, a transverse spring's turn is the difference of its two
neighboring chord directions. If their material widths are `h₀` and `h₁`,
its unit-panel-width cost is `0.1 × turn² / ((h₀ + h₁)/2)`. This formula
reproduces the triangle-normal measurements, including strips cut by the arc's
end. A midpoint-angle approximation would change that mixed strip's direction.
The gallery keeps interval integrals and all non-transverse costs explicit.

Coarse → rest-only increases passive cost by **10.7371% on the same smooth
reference**, even without optimization. Fitting full-length polygons increases
it by **11.9786%**, but also changes their curvature from `2.958134170368` to
`3.032706761541` and their arc lengths from `0.171747250646` to
`0.165792556062`. Their fitted continuous integrals change by only about 1.46%.
The difference of the discrete costs therefore cannot be read directly as a
change of physical stiffness. Adding the outer column at `15/32`, well inside
the straight section, changes either comparison only by numerical roundoff.

Matching material vertices in the fitted coarse/rest-only pair move by at
most `0.000984600` sheet lengths. That is narrowly below the study's `0.001`
position target, while their 11.98% passive-cost difference exceeds its 5%
energy target. Vertex distances do not bound the whole surface between them.
This family does not establish convergence of the solved shapes or explain
all their earlier 8.9857% difference.

A useful next control is to smooth the two curvature changes while retaining
these grips and material length. The current tangent is continuous, but its
turning rate jumps at the arc's ends. Comparing that control on the same four
meshes would test how much of the remaining energy sensitivity comes from
those transitions before changing a material rule or running another large
solve. Width-varying bends, separation, physical calibration and checked
flexible motion remain separate work. See
[#288](https://github.com/avalonalex/senbazuru/issues/288), continuing
[#195](https://github.com/avalonalex/senbazuru/issues/195) and track A of
[#269](https://github.com/avalonalex/senbazuru/issues/269).

Independent coordinate calculations reproduce all twelve exports, 1,416
springs, 2,040 edges, fifteen comparisons and every fit step. Exact triangle
clipping reproduces all contact extrema. All 24 SVGs and 24 browser selections
are checked, and 677 existing archived assets remain unchanged. Seven fast
regressions run in about 0.25 seconds with no material-equilibrium solve.
All 1,551 tests pass after a cold, warning-free build (392.8 seconds for the
suite); formatting, HLint 3.10 and JavaScript checks pass.
