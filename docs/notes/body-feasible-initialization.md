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
one numerical unit. This is not an exact global minimax method or a material
energy. The existing original working-set solver gets **200 iterations** per
direction, with no alternate solver retry. Its original-row feasibility,
complementarity and force-balance checks must pass before any geometry trial.
Complementarity means separated constraints exert no force; force balance
means objective, constraint and damping forces sum to zero.

At most **20 corrections** each try `1, 1/2, …, 1/4096`. The linear problem
bounds each coordinate's displacement from the original start; actual trials
also enforce the stronger Euclidean movement limit of `0.001`. Every retained
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
