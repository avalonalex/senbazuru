# Refining held panels from 256 to 512 triangles

Both 256 → 512 refinements now meet the `0.001` shape target and the 5%
passive-cost target: their cost changes shrink to **3.75% / 3.78%**. That is
progress, not mesh independence. Equal-budget layouts still differ by **10.36%**
in passive cost, and length-penalty costs increase substantially. Both finer
endpoints nevertheless converge and pass unchanged paper checks.

This experiment continues [the stopping confirmation](held-endpoint-confirmation.md)
with two new length resolutions. Uniform spacing and whole-bend placement
(the same budget concentrated throughout the curved region) retain two strips
across the width. The saved 256-triangle endpoints are remeasured, not solved
again. The original four-case command and every solver default stay unchanged.

```bash
stack run senbazuru-material-study -- --held-refinement \
  build/fold-material/held-confirmation build/fold-material
```

Open `build/fold-material/held-refinement.html`. [#311](https://github.com/avalonalex/senbazuru/issues/311)
fixes the protocol before either solve: sample the same smooth starting curve
on each 512-triangle grid, keep the exact original inner-strip and outer-edge
grips, and run length weights `1e2, 1e4, 1e6, 1e8, 1e9, 1e10`, at most 40
iterations each, with full repaired movement stop `1e-7`. Only a converged,
paper-valid endpoint receives at most 40 further iterations at `1e10` with
movement stop `1e-8`. A proposal means the complete suggested vertex motion,
before reducing its size to lower cost. Refusal or exhaustion stays diagnostic;
there is no larger budget, alternate seed or retuned criterion on failure.

The original material coordinates identify points on the unfolded sheet (see
[the glossary](../glossary.md)). They and the passive springs' flat rest angles
remain fixed during each solve. The sampled curve supplies starting positions,
not a new rest shape. Both panels may move in three dimensions; the same
contact constraints preserve their order. Archive checks bind both 256 inputs
to the original six-stage histories and tighter confirmations, and fresh
measurements must agree before any output or solve. Original report and FOLD
bytes are retained separately.

Each new mesh has 387 vertices and 512 triangles. All original material edges,
crease identities and shared vertices survive each solve. The original crease
is the sharp fold joining the two panels; passive hinges between triangles
approximate bending within each panel.

| 512-triangle result | Uniform | Whole bend |
| --- | ---: | ---: |
| Six-stage iterations | 57 | 76 |
| Confirmation iterations, including the stopping check | 4 | 4 |
| Final full proposal, sheet lengths | 6.2122e-9 | 3.7623e-9 |
| Confirmation's extra whole-material movement | 1.1517e-7 | 3.8341e-8 |
| Lower passive cost | 0.120078602 | 0.107642678 |
| Length-penalty cost at weight 1e10 | 0.000296628 | 0.002866284 |
| Largest relative edge error | 1.7449e-6 | 5.9694e-6 |
| Maximum opening, sheet lengths | 1.6002e-14 | 1.6080e-14 |
| CPU seconds: original schedule + confirmation | 115.05 + 8.40 | 184.70 + 10.15 |

Upper passive costs agree with lower costs within `6.3e-14` but remain
separately exported. Both initial and confirmation repairs move no vertices.
Held-position error is exactly zero, original crease error is `2.45e-16`
radians, and whole-sheet contact passes with exact minimum panel gap zero.
The edge-error cap is still `1e-5`, as is the crease-error cap in radians.
Both final maps have 1,480 touching samples and 120 outside the overlap, with
no separated or crossing samples at the unchanged `1e-7` contact threshold.
These counts describe 1,600 fixed sample locations, not contact areas.

| Confirmed endpoints compared | Largest displacement | Lower passive change | Length-cost change |
| --- | ---: | ---: | ---: |
| Uniform 256 → 512 | 0.000586748 | +3.747453% | +348.18% |
| Whole bend 256 → 512 | 0.000501080 | +3.779337% | +488.95% |
| Uniform → whole bend, 256 | 0.000739524 | −10.384027% | +635.33% |
| Uniform → whole bend, 512 | 0.000849586 | −10.356486% | +866.29% |

Displacement is measured over every overlap between triangles in the original
flat sheet, including points absent from the other mesh. All four comparisons
meet the shape target. The two length refinements improve on the earlier
6.49% / 8.31% passive changes. But neither layout's small refinement change
explains away their persistent equal-budget difference. Comparing only
successive resolutions within one layout would miss it.

The length penalty is half `1e10` times the sum of squared absolute edge-length
errors. It is a numerical restraint, not a calibrated physical stretching
energy. Its positive baseline is above the declared near-zero cutoff `1e-12`,
so the large relative changes remain failed component targets, even though the
absolute edge errors pass. At 512 triangles it is about 0.12% / 1.31% of total
cost. Total cost changes under refinement are only 3.85% / 4.91%; those totals
must not hide a separate component's failure. Crease cost stays approximately
`3e-32`, imposed cost stays zero, and opening changes are compared absolutely.

The same material-distance bins explain the passive refinement change below.
They assign each spring's entire cost to its material edge midpoint, rather
than claiming a physical energy density across neighboring triangles.

| Lower-panel bin | Uniform signed change | Whole-bend signed change |
| --- | ---: | ---: |
| Held interior | 0 | 0 |
| Held boundary | −0.006309246 | −0.005083956 |
| First free interval, up to distance 5/32 | +0.006061923 | +0.005186648 |
| Remaining free paper | +0.004584672 | +0.003817336 |

As before, reduced cost at the held boundary is outweighed by increases in the
free paper. Per panel, each comparison has 62 shared springs, 256 new springs
and 96 removed springs. Their material-edge identities, coefficient and angle
contributions are retained; comparing only shared springs would lose most of
the positive contribution. The common-scale signed maps show both panels.

Independent reconstruction checks 12 FOLD states, 9,880 edge lengths, 7,016
spring angles and costs, six whole-material comparisons and fixed-bin sums.
Exact rational triangle clipping reproduces every gap extremum and all 19,200
projected samples. Twelve complete-sheet GLBs retain both windings and every
triangle; packed coordinates differ by at most `8.44e-7` sheet lengths, while
measurements use unrounded FOLD coordinates. All 40 SVGs parse without geometry
transforms, and all 5,688 historical assets remain unchanged. Both layouts,
ten numerical-state selections and four cost-map selections work in the
gallery. A corrupted last input and overlapping input/output directories are
refused before overwriting accepted results. Fast fixture/archive regressions
run in CI; the two full solves and confirmations remain opt-in. All 1,770
tests pass after a cold warning-free build (391.8 seconds of test time);
formatting, HLint 3.10 and JavaScript checks pass.

Next, use these saved 256- and 512-triangle meshes to locate the **equal-budget
layout gap and length errors together**, by material distance and edge direction,
without another solve. That can separate where the extra numerical restraint
cost appears from where passive bending differs before choosing more triangles,
a different length weight, or a width experiment. Nothing here establishes a
global minimum, calibrated stiffness, width convergence or a checked flexible
folding route. No production mesh or solver policy changes.

Continues [#195](https://github.com/avalonalex/senbazuru/issues/195) and track A
of [#269](https://github.com/avalonalex/senbazuru/issues/269).
