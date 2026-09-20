# Where held-panel bending costs change

The [four held-panel solves](held-panel-equilibrium.md) pass the paper checks,
but doubling the triangle count changes passive bending cost by **6.49%** on
uniform grids and **8.31%** on grids concentrated in the curved interval.
Passive springs prefer flat paper; their cost measures how far adjacent
triangles turn away from flatness. This analysis locates the differences on
the saved shapes, without solving, repairing contact or changing coordinates.

The cost at the held boundary **falls** after refinement. Increases in the
free paper outweigh that reduction. Both the first free interval and the rest
of the free panel contribute: the discrepancy is not confined to one edge.

Run from the repository root, using the existing four endpoint archives:

```bash
stack run senbazuru-material-study -- --held-costs \
  build/fold-material/held-equilibrium build/fold-material
```

Open `build/fold-material/held-costs.html`. The command binds each report to
its original grid, grips, springs and six-stage solver policy. It reconstructs
every spring and edge measurement from the FOLD, checks exact holds and shared
material vertices, original crease angles, whole-sheet contact and exact
lower/upper order. All four remain valid. Convergence is retained as historical
evidence, not recomputed. The source report and endpoint FOLD bytes are copied
unchanged. All four inputs are checked before any output is written, so a
rejected archive cannot overwrite an accepted gallery. All 5,557 prior FOLD/JSON/SVG/GLB assets remain unchanged on this run.

Distance below means distance from the crease on the original flat sheet,
not on the folded shape. #306 declared four bins before examining costs:
held interior (`d < 1/8`), held boundary (`d = 1/8`), first free interval
(`1/8 < d <= 5/32`), and remaining free paper (`d > 5/32`). The first free bin
is one uniform-128 material interval, `1/32` sheet length. Assign each spring's
whole cost to its edge midpoint. Its neighboring triangles can straddle a
boundary, so these sums are accounting bins, not physical energy densities.

| Lower-panel cost change | Uniform 128 → 256 | Whole bend 128 → 256 |
| --- | ---: | ---: |
| Held interior | 0 | 0 |
| Held boundary | −0.006869803 | −0.003738635 |
| First free interval | +0.007203189 | +0.006997885 |
| Remaining free paper | +0.006723874 | +0.004702459 |
| **Total** | **+0.007057259** | **+0.007961709** |

Upper-panel bin changes agree within `1e-12`; they are exported separately.
At equal triangle counts, switching from uniform to whole-bend placement
reduces costs in all three nonzero bins. Those reductions sum to `−0.012923058`
at 128 triangles and `−0.012018609` at 256. Lower cost alone still does not
identify a more accurate shape or material model.

A shared spring location means the same pair of material edge endpoints,
regardless of vertex numbering or endpoint order. Refinement adds transverse
edges (parallel to the crease) and replaces some diagonals. Removed edges must
remain in the subtraction. For uniform refinement, shared locations contribute
`−0.046399277`, added locations `+0.053701779`, and removed locations
`−0.000245242`. The corresponding whole-bend contributions are `−0.032595852`,
`+0.042762981` and `−0.002205421`. The small final differences are remainders
of larger opposing terms, not the costs of only the newly inserted edges.

Most of the refinement difference is transverse: `+0.006991740` for uniform
and `+0.007015786` for whole-bend placement. Diagonals contribute `+0.000065521`
and `+0.000945966`, respectively. Lengthwise changes stay below `4.3e-8` in
magnitude. The larger whole-bend diagonal contribution is a reason to retain
all directions and width ranges, rather than assuming each panel repeats one
centre-line profile across its width.

Smaller triangle angles do not necessarily mean less bending. At the held
boundary, the lower panel's width-averaged turn changes as follows. “Rate”
divides the angle by the mean distance to the two neighboring material columns;
it is an angular sampling measure, not an independently fitted curvature.

| Layout | Raw turn, radians | Turn / material spacing |
| --- | ---: | ---: |
| Uniform, 128 → 256 | 0.085074 → 0.050453 | 2.722368 → 3.229021 |
| Whole bend, 128 → 256 | 0.085178 → 0.053852 | 2.180565 → 2.757224 |

The gallery shows both measures with ranges across width, cumulative costs,
signed material-edge maps and midpoint sums. Every comparison uses the same
scale for each plot type. For shared springs it also separates coefficient
and angle terms using the [symmetric accounting identity](matched-energy-locations.md).
Those terms are algebra, not independent physical causes: triangle spacing
changes both the coefficient and what the measured angle spans.

Independent Python reconstruction checks 1,352 edge lengths, 952 spring angles,
coefficients and costs, all eight panel comparisons, bin/direction sums and
width profiles. Rational triangle clipping reproduces exact gap extrema and
6,400 projected gap samples. The gallery exports 52 SVGs; no geometry transform
is hidden in SVG attributes. Fast fixture/accounting and archive-refusal tests
run in CI; this analysis adds no material solve to the test suite.

The next bounded check should confirm the two **256-triangle endpoints with
tighter solver stopping tolerances**, retaining these originals, the same final
length weight, material, grips, contact policy and paper acceptance caps.
Compare the extra motion and cost changes with the current mesh differences,
including these fixed bins. That separates numerical stopping sensitivity
before choosing further mesh changes. It is a proposed follow-up, not a solve
performed here. The 5% cost and `0.001` shape targets remain unchanged; width
refinement, material calibration and a checked flexible folding route remain
separate work.
