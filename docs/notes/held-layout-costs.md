# Locating the saved layout gap beside length errors

**98.32% of the remaining 512-triangle passive-cost gap lies in the free
paper.** The held boundary contributes only 1.68%. Most additional length
penalty also lies in the free paper, but the worst relative length error sits
just outside the grip. These are different measurements, with different
largest contributors. Passive cost penalizes bending within the initially flat
panels; length penalty penalizes changes to their original edge lengths.

This is an accounting pass over the four saved endpoints from
[the 256 → 512 experiment](held-panel-refinement.md), fixed by
[#313](https://github.com/avalonalex/senbazuru/issues/313). Uniform spacing is
compared with whole-bend placement, which concentrates the same triangle
budget throughout the original curved interval. **No optimizer or contact
repair runs.** Material, positions, holds, stiffness, contact policy, histories
and acceptance thresholds remain unchanged.

```bash
stack run senbazuru-material-study -- --held-layout-costs \
  build/fold-material/held-refinement build/fold-material
```

Open `build/fold-material/held-layout-costs.html`. Select either triangle count
and either panel. The maps show signed changes on the unfolded paper; rust is
an increase, teal a decrease. Each metric has its own common scale across all
four comparisons. Cumulative plots add complete edge costs in order of distance
from the crease. Detailed JSON keeps every edge, including added and removed
ones, alongside the unchanged source reports and byte-identical FOLD files.

Material coordinates identify points on the original flat sheet, as defined
in [the glossary](../glossary.md). Here `u` measures distance away from the
shared crease and `v` runs along it. The two panels use positive and negative
`u`. The inner strip `|u| ≤ 1/8` and outer edge `|u| = 1/2` are held exactly.
Both layouts retain two strips across the width.

The numbers below are for the lower panel; upper-panel region and direction
costs agree within `2.2e-12` and are exported separately. All signed changes
mean whole bend minus uniform, with percentages divided by the uniform value.

| Triangles | Passive: uniform → whole bend | Passive change | Length penalty: uniform → whole bend |
| --- | ---: | ---: | ---: |
| 256 | 0.115741253 → 0.103722649 | −10.384027% | 0.000033093 → 0.000243340 |
| 512 | 0.120078602 → 0.107642678 | −10.356486% | 0.000148314 → 0.001433142 |

The original distance bins classify edge midpoints: held interior below `1/8`,
held boundary at `1/8`, first free interval through `5/32`, and remaining free
paper. Each bin receives an edge's complete cost. This is discrete accounting,
not a physical energy density assigned to surrounding triangles.

| Lower-panel region | Δ passive, 256 | Δ passive, 512 | Δ length penalty, 512 |
| --- | ---: | ---: | ---: |
| Held interior | 0 | 0 | 0 |
| Held boundary | −0.001434221 | −0.000208931 | 0 |
| First free interval | −0.004727600 | −0.005602875 | +0.000224740 |
| Remaining free paper | −0.005856782 | −0.006624118 | +0.001060088 |

Free-paper bins already contribute 88.07% of the 256 gap, rising to 98.32%
at 512. At 512, transverse edges (parallel to the original crease) reduce
passive cost by `0.016562906`. Diagonals increase it by `0.004126982`, mostly
in the remaining free paper, offsetting about a quarter of that reduction.
Lengthwise edges, which run away from the crease, contribute only `4.30e-10`
to the passive change. The gallery also crosses each distance bin with each
direction, so the two separate summaries cannot conceal different locations.

Matching by unordered material endpoints gives 120 shared passive springs,
198 added and 198 removed at 512 triangles, per panel. Shared springs change
cost by `−0.047174792`; added and removed contributions are `+0.042196849`
and `−0.007457980`. Comparing only shared springs would overstate the decrease.
For a shared spring, the symmetric algebraic split of `kθ²/2` attributes
`+0.041891672` to the changed coefficient `k` and `−0.089066464` to the changed
angle `θ`. Adjacent triangles determine the coefficient, so retaining the same
edge does not retain its coefficient. These terms are an accounting identity,
not independent physical causes.

Length penalty uses **absolute** length error: `1e10 × (actual − rest)² / 2`
per unique material edge. It is a numerical restraint, not calibrated paper
stretching energy. Boundary edges count too; the two shared crease edges count
once in a separate category and contribute zero here. Whole-sheet totals are
therefore the two panel totals plus that category, without doubling the crease.

At 512, 82.51% of the extra length penalty lies in the remaining free paper;
91.61% is on transverse and diagonal edges combined. Its largest lower-panel
cost is `1.47686e-5` on the whole-bend diagonal from `(0.28125, −0.5)` to
`(0.296875, 0)`. That edge is about `0.500244` long and shortens by `5.43481e-8`,
a relative error of only `1.08643e-7`.

The worst relative error instead lies on the short lengthwise edge from
`(0.125, −0.5)` to `(0.12890625, −0.5)`, immediately outside the grip. Its
original length is `0.00390625`; shortening by `2.33182e-8` gives relative
error `5.96945e-6`, but a smaller cost of `2.71868e-6`. It still passes the
unchanged `1e-5` edge-error cap. Ranking by cost alone would miss that location;
ranking by relative error alone would misidentify the dominant penalty cost.

Fresh measurements reproduce all four accepted endpoints, with exact holds,
shared crease vertices, original crease-angle error below `2.45e-16` radians,
and exact minimum panel gap zero. No paper test is waived. Separate reconstruction
from FOLD checks 2,696 unique edge lengths and 1,912 spring angles, coefficients
and costs. Rational triangle clipping reproduces all gap extrema, 6,400 contact
samples and both equal-budget whole-material comparisons. Every region,
direction, crossed bin and edge-membership sum reconciles. Four complete-paper
GLBs retain every triangle with both windings; packing changes positions by
at most `8.44e-7`, while measurements use unrounded FOLD coordinates. All 28 SVGs
parse without geometry transforms, and 5,769 older assets remain unchanged.
Changed histories, changed endpoint measurements and overlapping source/output
paths are refused before overwriting the accepted gallery. CI adds four small
accounting/archive regressions, without any new full material solve. All 1,774
tests pass after a cold warning-free build (393.58 seconds of test time);
formatting, HLint 3.10 and JavaScript checks pass.

The evidence narrows the next question to distributed, direction-dependent
costs in the free paper. It does **not** establish that the length penalty
causes the passive gap, or that either layout is more physically accurate.
A useful next control is width subdivision of the saved surfaces made of flat triangles: put new vertices on the existing triangles, preserve their shape,
and remeasure both costs before solving again. That would isolate a change
in cost accounting from a change in the chosen equilibrium; it would not
establish width convergence. More length triangles or a different penalty
weight are not justified by these maps alone. Production defaults, physical
stiffness calibration and continuously checked flexible motion remain separate.

Continues [#195](https://github.com/avalonalex/senbazuru/issues/195) and track A
of [#269](https://github.com/avalonalex/senbazuru/issues/269).
