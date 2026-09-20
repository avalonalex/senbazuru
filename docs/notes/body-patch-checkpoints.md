# An imperfect starting guess can dominate the opening study

The [body-patch experiment](coupled-body-patch.md) saved positions at selected
numerical corrections. Inspect those positions before spending more work on
its failed refined opening. This audit, [#319](https://github.com/avalonalex/senbazuru/issues/319),
reads the two 5° runs from #318; it performs **no new solves**:

```bash
stack run senbazuru-material-study -- --body-checkpoints build/fold-material/body-patch build/fold-material
```

The command needs the original reports, initial/endpoint FOLD files and
histories. It refuses missing files, changed material or holds, and changed
budgets. It copies their bytes to `body-checkpoints/source` beside the new
measurements. Nothing rewrites the original archive. The gallery marks the
worst strained edge and reversed triangle order in fixed folded views and on
the original sheet. It includes hidden triangles; none of these drawings
certifies a folding motion.

Both supplied guesses already shorten some edges by **0.38053%**, above the
0.001% length limit, and reverse declared layer order. Their worst penetration
is the same `0.0156515` sheet units, between material from original crane faces
20 and 8. Subdividing triangles has not introduced this initial defect. Neither
guess has a strict triangle crossing yet; a wrong above/below relationship can
exist even where two triangles are separated. Crossing first appears in the
saved **0→1 correction**, available without a gap in sampling:

| Mesh | Saved iteration | Maximum length error | Crossing pairs | Reversed pairs |
| --- | ---: | ---: | ---: | ---: |
| Coarse, 30 triangles | 0 | 0.38053% | 0 | 9 |
| Coarse | 1 | 1.63473% | 46 | 56 |
| Coarse | 40 | 3.67893% | 24 | 31 |
| Coarse | 160 | 0.00016210% | 0 | 0 |
| Refined, 120 triangles | 0 | 0.38053% | 0 | 51 |
| Refined | 1 | 1.85954% | 115 | 158 |
| Refined | 40 | 4.74665% | 22 | 278 |
| Refined | 160 | 4.00788% | 124 | 333 |

These pair counts are not comparable measures of physical severity across
meshes: subdivision changes how many triangle pairs represent the same paper.
The independent checker also finds seven touching pairs without a declared
order at refined iteration 40. It checks all triangles, including ones that
belong to the same original panel; the solver's supplied orders alone do not
cover every possible collision.

The coarse run is not simply making steadily smaller useful corrections. From
121→122 the largest vertex moves only `2.081e-8` sheet units, but its length
error is still `2.262e-5`, over the limit. The nearly unchanged positions last
through saved iteration 130, which again has one crossing. It then moves
`5.949e-4` by 140 and another `8.353e-4` by 160. The last is about half a pixel
at the gallery's 600 pixels per sheet unit. Iteration 160 is the **first saved
point** that passes both length and contact checks. The 140→160 interval brackets a recovery, but the archive cannot rule out
earlier unsaved valid states. No additional settling or convergence is
established here.

The refined run has trouble much earlier. Its panel-bending cost jumps from
`0.001363` at iteration 1 to `0.063290` at 2 while length error reaches 8.274%.
By 40 its preferred-angle costs are tiny, but the paper remains strained and
misordered. At 160, the worst length edge is vertices 19–79 inside original
body face 28: a material length `0.04577465` is shortened by `0.00183459`.
The worst reversed pair is triangles 46 and 69, from wing-collar faces 8 and
10, with penetration `9.015e-5`. The solver still makes progress on its chosen
cost: length and contact penalties at that point are `4520.616` and `4899.322`,
compared with crease/panel costs `0.007214` and `0.024755`. Failing geometry
dominates this result, not the previously deferred passive-energy percentage.

A **penalty** assigns a cost to violating lengths or contact. This solver
increases length weight from `100` to `10,000`, `1,000,000` and `100,000,000`
over four blocks of forty corrections; contact weight is always 100 times
larger. Every saved interval decreases the total when both ends are evaluated
at that interval's weight. Comparing different weights would falsely suggest
uphill moves. Reported costs are half the original line-search objective,
matching the existing angular-energy convention; this common factor does not
change which trial decreases cost.

There is also a numerical difference **before any correction**. The initial
contact cost rises from `10.0691` to `65.8321` (6.538×) on subdivision, although
the piecewise-flat shape and worst gap are unchanged. The contact penalty sums
violations at triangle-overlap sample points; more triangles change those
samples without an area normalization. Initial crease cost is unchanged and
panel cost is effectively zero. This makes contact sampling a plausible
contributor to the different trajectories, **not an isolated cause** or a
reason to redesign all material stiffness now.

Independent Python calculations reproduce all fifty snapshots' lengths,
angular energies, holds, body depth, interval displacement and reversed-order
pairs. The Haskell audit uses the existing independent triangle checker for
crossings, and the solver's contact rows for its numerical cost. Source hashes
and copied bytes agree. Regression tests refuse incomplete schedules, changed
policies, holds, material and endpoints, and distinguish stage-weight changes
from corrections. The expensive opening solves stay outside CI.

The archive cannot say how large the full proposed correction was, or why the
line search shortened it: individual proposals and per-step equilibrium
checks were not exported. An empty final equilibrium field follows budget
exhaustion, not success. Small recorded displacement must not replace the
convergence test.

A bounded next experiment is to subdivide the coarse 5° endpoint's **current
triangles**, verify its inherited shape, holds, lengths and contact, then try
one refined continuation at the existing final weight. That starts from the
recovered geometry without reintroducing the strained, misordered guess or
restarting weak penalties. Record the full proposals and refusals this time.
Retain the failed original control and all acceptance limits; if the inherited
start fails its own checks, stop there. This experiment has not been run.
Full-crane loads, pressure, flexible-path certification and cost convergence
remain separate work.
