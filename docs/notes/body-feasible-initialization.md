# Keep lengths within bounds while constructing a separated body

[#381](https://github.com/avalonalex/senbazuru/issues/381) tries a different
initialization after the [weighted construction](body-separated-initialization.md)
reduced its cost by stretching paper beyond the allowed limit. The owner chose
one constraint-first attempt. It starts again from the authenticated
`body-fourth-pair/start.fold`, not that construction's failed endpoint: the same
87 material vertices, 120 triangles, three exact holds, material coordinates,
crease preferences and inherited layer orders.

```bash
stack run senbazuru-material-study -- --body-feasibility build/fold-material/body-fourth-pair build/fold-material
```

A gap deficit is the distance still missing from a contact's target. For example,
a measured gap of `-1e-8` and target `1e-6` have a deficit of `1.01e-6` sheet
units. This construction reduces the **largest** remaining deficit. Every
inherited overlap corner participates together, including newly measured
corners at later candidates. Vertex-disjoint triangles target `1e-6`; triangles
sharing a material vertex target zero so their crease stays connected. The
clearance is numerical, not paper thickness.

One extra scalar initially equals the largest deficit. A linear contact
constraint says its predicted gap plus this scalar must reach the target.
This makes the initial linear problem feasible even though the saved geometry
slightly intersects. The scalar is bookkeeping, never a material vertex.
Reducing it tries to separate the paper. Material edges instead have upper
and lower length bounds at `1e-5` relative error; held coordinates are omitted
from all unknowns, and shared vertices keep one position.

Before the body run, a three-layer translation control exposed poor numerical
conditioning with damping `1e-12`: an essential constraint was treated as
dependent, leaving a normalized violation near one. With damping `1e-8` the
control separates both free layers in one verified correction (16 inner
iterations, largest violation `1.34e-15`). The latter setting was recorded
before the single body run; no body parameter retry is authorized.

The declared quadratic minimizes half the squared remaining scalar, with
`1e-8` damping on normalized increments to stabilize the calculation and
favor small movements. Coordinates and the scalar use `1e-6` sheet units as
one numerical unit. This does not establish the globally smallest possible worst deficit or measure
material energy. The existing original working-set solver, which selects
constraints to treat as touching their limits, gets **200 iterations** per
direction, with no alternate solver retry. Its original-row feasibility,
complementarity and force-balance checks must pass before any geometry trial.
Complementarity means separated constraints exert no force; force balance
means objective, constraint and damping forces sum to zero.

At most **20 corrections** each try `1, 1/2, …, 1/4096`. The linear problem
bounds each coordinate's displacement from the original start; actual trials
also enforce the stronger straight-line (Euclidean) movement limit of `0.001`. Every retained
trial must preserve material identities, exact holds and actual edge errors
at most `1e-5`, and strictly lower the freshly measured largest deficit. A
linear prediction cannot override an actual measurement. Bending preferences
remain unchanged and their energies are reported, but do not drive this
geometric construction.

The same readiness gates as the weighted attempt separately check material,
all-pair contact and inherited orders, disjoint overlap gaps above `5e-7`,
local reference discovery within `0.03`, compatible learned orders, finite
barrier rows with activation range `0.001`, and strict static contact checking.
A retained construction step can still intersect and is not a valid paper
endpoint. Even a ready seed would establish neither equilibrium nor a physical
route from the intersecting start. No barrier material solve runs here.

`body-feasibility.html` shows retained states separately from any unverified
full proposal. Views share cameras and 600 pixels per sheet unit, with 4×
magnification; the original-sheet map uses its own fixed scale. `checks.json`
contains measurements and readiness gates. `trace.json` contains every linear
row, direction, solver residual and tried fraction, including failures. The
input archive and the earlier weighted result are preserved unchanged.

The **2026-09-24 result is a constrained-direction blocker**. The first linear
problem contains 5,812 inequalities: 412 length bounds, 4,894 overlap corners,
504 coordinate bounds and two scalar bounds. The original working-set routine
returns after 115 iterations with 66 selected constraints. Its largest
violation is `4.06889e-8`, complementarity residual `4.10347e-8` and force-balance
residual `2.35765e-16`. The first two exceed their unchanged `1e-12` limits, so
**zero geometry trials run and zero corrections are retained**. The original
start remains the returned state. Construction costs 487.93 CPU seconds
locally, excluding archive authentication, export and independent checking.
This large solve stays outside CI.

These linear residuals use the normalized coordinate units above. A violation
of `4.07e-8` represents about `4.07e-14` sheet units in an inequality; it is not
the actual paper's negative gap. Actual separation still fails independently
of this numerical verification. The returned scalar predicts a remaining
worst deficit of `1.00000000017e-6`, essentially the full clearance target.
No inference of geometric impossibility follows from this numerical stop.

The full proposal is exported **only for inspection**, never as a retained
step or accepted endpoint:

| Measurement | Saved start | Unverified full proposal |
| --- | ---: | ---: |
| Maximum relative edge error (limit `1e-5`) | `6.429154e-6` | `1.000512e-5` |
| Largest clearance deficit | `1.015419e-6` | `1.000873e-6` |
| Smallest disjoint height gap (must exceed `5e-7`) | `-1.541939e-8` | `-8.730510e-10` |
| Body depth, sheet units | 0.0362344417 | 0.0362344417 |
| Crease energy | 0.0116244494 | 0.0116239235 |
| Panel energy | 0.00106211779 | 0.00106693273 |
| Length cost | 0.00004802041 | 0.00244190183 |
| Archived zero-clearance contact cost | 0.000005752730 | 0.0000000272827 |
| Crossing pairs / reversed orders at the existing `1e-7` tolerance | 0 / 0 | 0 / 0 |
| Exact-hold error | 0 | 0 |

Its maximum movement is `5.83535e-6` sheet units, **0.00350 drawing pixels**.
Body depth and the reported neck/tail attachment positions do not change.
Normal-size and enlarged views show no useful opening. The red length marker
identifies a failed check; it is not a newly opened surface. Local discovery
still first refuses triangles 0 and 34, so learned-order compatibility and
barrier rows remain unevaluated. Strict static contact also fails. The older
contact check passing alone does not make a separated start.

Independent calculations reconstruct every length bound, clearance offset and
coordinate bound, and reproduce the original-row feasibility, complementarity
and force-balance residuals. Both exported states were checked against all
7,140 triangle pairs, lengths, separate energies, crease angles, holds, material
identities, landmarks and gaps. Exported FOLD orders agree with inherited
source relationships and current triangle normals; their overlap subset can
change with geometry. All 2,131 copied input files and all 4,289 original/control
files retain their bytes. All sixteen gallery state/view/size combinations
load without browser errors. A warning-free cold build, 1,903 tests, formatting,
HLint 3.10 and the JavaScript checks pass; the eight new small controls take
about three milliseconds together.

Stop at this result under the scoped decision. There is no new barrier-ready
seed, accepted opened body or barrier/penalty comparison. Preserve this failed
joint direction beside the weighted attempt. Another method or model needs a
new bounded decision; do not restart pair repairs or treat reducing these tiny
linear residuals alone as the next illustration deliverable.
