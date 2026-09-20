# Put more triangles where the bend changes

The [uniform refinement ladder](fixed-bend-refinement.md) approaches known
bending costs on two fixed curves. Can the same number of triangles do better
if more of them sit near the joins between flat and curved paper? This study
compares a fixed placement rule with uniform spacing. Neither curve changes,
and no material-equilibrium solve runs.

Both layouts start with material columns `0, 1/16, …, 1/2`, giving 64 triangles
across two touching panels. A material column locates a line across the
original unfolded paper. The local layout repeatedly bisects the interval with
the largest weighted length: density four within `1/32` sheet length of either
join, one elsewhere. Equal scores choose the interval nearer the shared
crease. The two windows are fixed for each curve; their union counts overlap
only once. This rule was recorded in
[#298](https://github.com/avalonalex/senbazuru/issues/298) before evaluating it.
It never reads measured energy or selects a best-performing grid.

Five budgets match the uniform ladder exactly: 64, 128, 256, 512 and 1,024
triangles. Each grid retains every column from its preceding level and the
original coarse grid. Both width strips, grip regions, shared crease and
material coefficient `0.2` stay unchanged. The common circular and smooth
curves are those from the preceding study, without another fit.

Run from the repository root:

```bash
stack run senbazuru-material-study -- --transition-refinement build/fold-material
```

Open `build/fold-material/transition-refinement.html`. The gallery shows the
actual column locations beside cost errors on common scales. **Samples** put
vertices on the reference curve, leaving straight edges shorter than the
material arcs. **Full-length segments** restore each chord's material length
without changing its direction, allowing the outer grip to drift. Their
angular costs agree within roundoff; their geometric errors do not.

Percentage error is `100 * abs(measured - analytic) / analytic`. The analytic
cost integrates squared curvature, meaning squared turning per material
length, with the same material coefficient. Its per-panel values remain
`0.153247166460` for the circle and `0.196258506440` for the smooth curve.
These are model costs, not calibrated joules.

| Triangles | Circular uniform error | Circular local error | Smooth uniform error | Smooth local error |
| ---: | ---: | ---: | ---: | ---: |
| 64 | 18.0139% | 18.0139% | 20.1163% | 20.1163% |
| 128 | 9.2110% | 4.4699% | 6.4071% | 3.0689% |
| 256 | 4.4699% | 2.3824% | 1.7817% | 0.9581% |
| 512 | 2.3824% | 1.1892% | 0.4724% | 0.3431% |
| 1,024 | 1.1892% | 0.5912% | 0.1213% | 0.0960% |

Local placement improves cost accuracy at every refined budget in these two
examples. It helps the circular curve more: that curve has an abrupt change
in curvature at each join. This is evidence about one prescribed rule on two
known shapes, not proof of an optimal mesh or mesh-independent mechanics.

There is a geometric tradeoff. At 1,024 triangles, circular full-length grip
drift rises from `9.64967e-7` to `2.35878e-6` sheet lengths under local placement;
smooth drift rises from `1.23817e-6` to `4.21517e-6`. Most refined local controls
have more drift; the smooth 128-triangle case is the exception. Concentrating
triangles near the joins leaves larger intervals in the middle of the bend.
No grip is copied back to hide the difference.

The shape comparison covers every original-paper location, including vertices
present in only one mesh. Take the union of both sets of material columns.
Between consecutive columns, both profiles are straight, so their positional
difference is a linear vector. Its length cannot exceed the larger endpoint
length. Checking all union columns therefore finds the largest difference
over the profiles; these profiles repeat unchanged across the sheet's width.
This argument is specific to the present construction, not arbitrary meshes.

At 1,024 triangles the largest full-length uniform/local difference is
`2.33396e-5` sheet lengths for the circle and `3.85153e-5` for the smooth curve.
The smooth difference actually grows from `2.36083e-4` at 128 triangles to
`6.06929e-4` at 256, even as both cost errors fall. Energy improvement alone
does not establish shape improvement. Sampled vertices shared by the meshes
agree exactly, but their connecting straight segments can still differ.

Full-length local meshes preserve material edges to relative error below
`1.2e-14`, comfortably within the unchanged `1e-5` numerical cap. Sampled
length errors remain reported separately: the finest local circle/smooth
errors are `2.37828e-5` / `6.51659e-5`, both outside that cap. The finest uniform
circle passes it, so better cost accuracy can even accompany losing a length
check. Both layers remain one connected
sheet sharing only original crease vertices 0/1/2, with zero inner-grip motion
and exact zero touching gaps across triangles. Passive, length, original-crease
and imposed costs stay separate. These static touching references do not test
separation, sliding, equilibrium response or a continuous folding route.

The next useful comparison would also resolve the middle of the curved region:
compare a fixed density across the whole bend with these transition windows
at equal budgets. The [whole-bend follow-up](whole-bend-refinement.md) improves
geometry while retaining an angular-cost tradeoff for the circle. Retain both
errors before choosing a mesh policy for a material solve. This study does not settle the old solved
8.99% gap or change the #195 acceptance criteria.

Independent reconstruction checks all 40 FOLDs, 27,856 edges, 19,760 springs
and 20 whole-profile comparisons. It regenerates the placement grids from
exact weighted intervals, integrates smooth positions with Simpson's rule,
and recomputes costs from triangle normals and original material heights.
Matching triangulated layers with opposite winding establish zero contact
gaps everywhere. Uniform controls reproduce the old meshes exactly. All 54
SVGs parse, all 40 browser selections work, and 810 archived assets remain
byte-for-byte unchanged after regenerating the original ladder.

Tracked in [#298](https://github.com/avalonalex/senbazuru/issues/298), continuing
[#195](https://github.com/avalonalex/senbazuru/issues/195) and track A of
[#269](https://github.com/avalonalex/senbazuru/issues/269).
