# The same prescribed bend has different discrete costs

The [saved matched shapes](matched-energy-locations.md) differed in passive
bending energy by 8.9857% after interior refinement. Their shapes also changed.
To test the energy rule without that second effect, prescribe a known bend on
the same four meshes. No optimizer or contact repair runs:

```bash
stack run senbazuru-material-study -- --uneven-bends build/fold-material
```

Open `uneven-bends.html` on the study server. It compares 64, 72, 120 and
128 triangles: coarse, outer-only, rest-only and fine. Outer-only adds the
material column at 15/32; rest-only refines everywhere except that column.
The sheet, triangle identities, passive spring coefficients and original
closed crease come from the matched-hold fixtures. There is no imposed band.

Both panels follow the same reference, keeping their separate material
vertices and shared crease. A cylindrical bend turns its tangent by 1.2
radians per unit material length. The second reference stays flat to distance
1/8 from the crease, then bends at the same rate. Its tangent joins
continuously: the change in curvature introduces no finite corner or new
crease. Every mesh has a column at that transition.

Each reference has two constructions. **Exact surface samples** put each
material vertex on the formula's surface. Their straight edges are chords,
shorter than the arcs they replace. **Full-length straight edges** keep each
strip's original length and its chord's direction, adding those vectors from
the crease outward. On an uneven mesh the shortening differs per strip, so
the single scale used by the [uniform cylinder](prescribed-bend-energy.md)
would be incorrect. The full-length construction changes sampled positions
slightly but preserves the turns between triangles.

The measured passive energy of **each panel** is:

| Mesh | Cylinder | Bend starts at 1/8 |
| --- | ---: | ---: |
| Coarse | 0.063000 | 0.047250 |
| Outer only | 0.065250 | 0.049500 |
| Rest only | 0.065250 | 0.048375 |
| Fine | 0.067500 | 0.050625 |
| Continuous comparison | 0.072000 | 0.054000 |

Both constructions give these costs, within floating-point error. Coarse →
rest-only rises by **3.5714%** for the cylinder and **2.3810%** for the second
reference. Coarse → outer-only rises by 3.5714% and 4.7619%, respectively.
The rule changes cost even before an optimizer chooses a shape. These are
model costs, not measured joules or evidence that the finer sheet is stiffer.

For the unit-width panel, the continuous comparison is `0.1 κ² L`, where
`κ = 1.2` is the tangent's turning rate and `L` the bent material length.
The coefficient follows the existing passive rule; it does not calibrate
paper. A transverse spring lies along an edge parallel to the shared crease.
Its interval extends halfway toward each neighboring material column. Call
the interval length `H` and its curved portion `A`. Summed across the panel's
two width segments:

```text
measured turn magnitude       = κ A
discrete spring cost          = 0.1 (κ A)² / H
reference integral on interval = 0.1 κ² A
```

Two terms account for the difference from the continuous comparison. The
first and last half-strips have no passive transverse spring. The actual
central crease has its own retained angle and cost; it is not a substitute
for that missing panel bend. Also, an interval spanning flat and curved paper
squares an averaged turning rate. This loses `0.1 κ² A (1 − A/H)` compared
with averaging the squared rate. The loss is zero on fully flat or curved
intervals.

For the bend starting at 1/8, missing outer-boundary costs are
`0.0045 / 0.00225 / 0.0045 / 0.00225` in mesh order. Transition losses are
`0.00225 / 0.00225 / 0.001125 / 0.001125`. Subtract both from `0.054` to
recover every measured cost. The cylinder has no transition loss; its missing
boundary costs are `0.009 / 0.00675 / 0.00675 / 0.0045`. Every diagonal and
lengthwise spring remains in the measured totals, even when its cost is zero.

All eight exact-sample references exceed the unchanged `1e-5` relative
material-length cap: their largest error is `2.34359e-4`, or `5.85927e-5`
on the fully fine mesh. Full-length references keep every material edge,
including diagonals, within `8.89e-16` relative error. Their largest vertex
distance from the smooth reference is `1.155e-4` sheet lengths. Vertex
comparisons do not bound the whole surface between vertices. Length costs
at weight `1e10` stay separate from angular costs; no numerical solve occurs.

All references have one connected component, shared crease vertices 0/1/2,
original crease-angle error below `2.45e-16` radians, and exactly touching
known-order triangle pairs. These static references have no layer separation
or variation across the width. The bend-start reference keeps the original
inner grips, but its outer grips move about `0.06206` sheet lengths. The
cylinder moves both. None is an equilibrium of the original held-paper problem
or a checked flexible route, and the sampled length failures remain visible.

This accounts for the prescribed references, **not the entire 8.9857% change
in solved shapes**. The [held-reference follow-up](prescribed-held-bend.md)
also retains the original outer grips on these meshes, with sampling and
length errors still separated. That removes the changed boundary positions
before revisiting the solved response. This comparison does not justify a new
default material law, another large grid or weaker acceptance criteria.
See [#284](https://github.com/avalonalex/senbazuru/issues/284), continuing
[#195](https://github.com/avalonalex/senbazuru/issues/195) and track A of
[#269](https://github.com/avalonalex/senbazuru/issues/269).

Independent coordinate calculations reproduce 1,888 spring measurements,
2,720 material edges, 20 comparisons and exact triangle-clipped gap extrema.
All 32 SVGs and 32 browser selections are checked; 612 existing archived
assets remain byte-for-byte unchanged. Seven analytic regressions run in
about 0.35 seconds and introduce no optimizer work to the regular suite.
All 1,544 tests pass in a cold warning-free build (391.4 seconds for the
suite); formatting, HLint 3.10 and JavaScript checks pass.
