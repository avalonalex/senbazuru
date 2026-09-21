# Refinement can inherit a valid shape without settling it

The [saved-checkpoint audit](body-patch-checkpoints.md) found that the coarse
5° body patch eventually recovered valid geometry, while the refined run kept
its length and contact defects. [#321](https://github.com/avalonalex/senbazuru/issues/321)
tests a better starting point: subdivide the recovered **current triangles**,
then try one continuation. This is still the sixteen-panel specimen with a
free boundary, not a whole crane. Three exact holds prescribe the centre and
opposite wing attachments; neck and tail attachment landmarks remain free.

```bash
stack run senbazuru-material-study -- --body-subdivision build/fold-material/body-patch build/fold-material
```

The reader validates both archived 5° runs and copies their original bytes.
Each coarse triangle becomes four coplanar children. A shared edge has one
midpoint identified by its vertex ids; separate layers are never welded just
because their positions coincide. Material coordinates are subdivided too,
so rest lengths still come from the original sheet. Exact agreement with the
existing fine fixture binds the inherited positions to its crease preferences,
source panels, holds and layer requirements. The original invalid fine control
remains unchanged alongside the new result.

The 30→120 triangle subdivision passes its own checks: one connected specimen,
87 distinct material vertices, exact holds, unchanged body depth, length error
`1.62098e-6`, and no detected crossings, reversed orders or unordered touches.
It preserves the piecewise planar surface exactly. Crease cost stays
`0.0119861`, but panel cost doubles from `0.000606901` to `0.00121380`.
The bending rule is unchanged: subdivision narrows the triangle strips beside
an existing sharp bend without smoothing that bend. Its angular difference
remains concentrated on the old edge while the discrete stiffness changes
with the narrower support. Shape preservation is not energy preservation;
this does not reopen the deferred cost-convergence study.

Only this passing seed permits the new solve: **forty corrections at the
existing final length weight `1e8`**, contact weight `1e10`, with the same
material (`Bending 1 0.2`), holds, preferred angles, zero clearance and stopping
rules. It does not restart the original four-stage schedule or weaken any
acceptance threshold. The result is improved initialization, **not an accepted
opened pose**:

| State | Length error | Crossing pairs | Reversed pairs | Body depth |
| --- | ---: | ---: | ---: | ---: |
| Recovered coarse | 0.00016210% | 0 | 0 | 0.0361920 |
| Inherited refined start | 0.00016210% | 0 | 0 | 0.0361920 |
| New correction 2 | 0.00093413% | 3 | 0 | 0.0362017 |
| New correction 40 | 0.00044009% | 3 | 0 | 0.0363352 |
| Original failed refined endpoint | 4.00788% | 124 | 333 | 0.2030582 |

The length limit is 0.001%. It passes at the new exported checkpoints, but not
every intervening candidate: correction 11 reaches 0.00138692%. The full trace
keeps these positions rather than representing the sparse checkpoint table
as a continuously valid route. Counts across different triangulations are
not measures of physical severity.

All forty linear solves meet their residual checks, and every chosen candidate
reduces the total cost. Nevertheless, the last full proposed movement is
`3.56882e-5` sheet units, about **357 times** the `1e-7` equilibrium limit.
The budget expires unconverged. Across the run there are 456 line-search
refusals, all because cost did not decrease. The first full proposal is
`0.00208926`; twenty-four halvings reduce its actual movement to approximately
`1.24529e-10`. That almost motionless correction is emphatically not equilibrium.
The trace is opt-in and capped at forty steps; ordinary solves keep the old
bounded first/last rejection audit. Regression tests compare traced and
ordinary results, including stationary refusals and moving proposals.

The final maximum displacement from the seed is `0.000953065`, or **0.572 px**
at 600 px per sheet unit. Body depth increases by `0.000143127`.
Crease/panel costs finish at `0.0113395`/`0.00108922`; length/contact penalties
are `0.0000802786`/`0.00000282552`. Total cost falls by 5.3311%. These are
separate measurements, not evidence of a calibrated material response.

An independent triangle checker detects three crossings even though declared
order violations remain below its `1e-7` tolerance. At correction 2 the pairs
are triangles **14–55, 22–63 and 46–70**, belonging to original crane faces
2/8, 3/9 and 8/10. At correction 40 the first two persist; the third is
71–80, from faces 10/13. The gallery highlights the first crossing pair when
there is no reversed order to mark, and uses fixed cameras and scale for all
states. Wire diagrams include hidden paper; no display offsets repair it.

Independent Python calculations reproduce exact midpoint inheritance, lengths,
angular costs, contact penalties, declared-order pairs, holds, body depth and
all forty candidate energies. Every full proposal and shortened/refused position
agrees with its recorded scale; the candidates join to the exported endpoint.
Source hashes and copied bytes remain unchanged. These independent order
calculations do not reimplement the library's general 3D crossing checker.
The expensive opening solve stays opt-in, outside CI.

The bounded next step is to inspect **correction 1→2 and its three crossing
pairs from the saved trace**, without new solves. Locate the intersections and
compare them with the directional contact samples and tolerances; determine
why a descending candidate with small order gaps fails the independent
crossing check. Do not relax that check or call the current endpoint settled.
A larger iteration budget, changed contact policy, full-crane loads, pressure
and a checked flexible route remain separate experiments.
