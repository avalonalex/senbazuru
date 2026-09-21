# A shallow crossing still crosses

The [subdivided body patch](recovered-body-subdivision.md) starts from valid
geometry but develops three reported crossings at correction 2.
[#323](https://github.com/avalonalex/senbazuru/issues/323) inspects the saved
steps 1 and 2, without solving again. The question is whether the solver missed
a contact partner or sampled the wrong place.

```bash
stack run senbazuru-material-study -- --body-contact build/fold-material/body-subdivision build/fold-material
```

Every affected pair has an inherited lower/upper requirement and **four
contact samples**, including its most negative gap. Samples sit at the corners
of the triangles' overlapping outlines when viewed along the fixed model z
axis. Since the height gap is linear across that overlap, its extrema occur
at these corners. This is not a missing-partner or sparse-sampling failure in
these three pairs. The contact force penalizes every negative gap, including
ones smaller than the reporting tolerance; separated paper is not attracted.

Two distances explain the apparently conflicting checks. The crossing checker
cuts each triangle by the other's plane, then compares those two line segments.
It reports a crossing when both triangles extend more than `1e-7` on each side
of the other's plane and the intersection is longer than `1e-7`. Those plane
distances use the **whole triangles**, including portions outside their common
outline. The order checker measures the **vertical gap inside that outline**
and reports reversal only below `-1e-7`. The same numerical tolerance therefore
does not imply the same verdict.

| Triangle pair at step 2 | Required lower → upper | Original crane faces | Intersection length | Most negative height gap |
| --- | --- | --- | ---: | ---: |
| 14–55 | 55 → 14 | 2 / 8 | 9.80186e-6 | -2.86129e-9 |
| 22–63 | 22 → 63 | 3 / 9 | 9.18477e-6 | -2.69638e-9 |
| 46–70 | 46 → 70 | 8 / 10 | 2.69468e-6 | -1.72110e-8 |

All distances use sheet units. At 600 pixels per sheet unit the intersection
lengths correspond to approximately **0.00588, 0.00551 and 0.00162 pixels**
before projection; the top-view segments are slightly shorter. These are real,
very shallow intersections, not missing colours in the renderer. No paper
positions are offset to hide them. The gallery compares identical crops of
both steps, shows full-scale context and exports every sample with its two
surface positions and gap derivative. Magnified top views show the intersection
line; the separate height chart shows how shallow the penetration is. Its
vertical guides mark ±`1e-7`; larger positive gaps are capped only in that chart
and remain fully recorded in the table and JSON.

Pair 46–70 already has a mathematical intersection of length `1.28521e-6` at
step 1. The crossing check does not report it then: one triangle's most negative
distance to the other's plane is `-8.79986e-8`, within tolerance. At step 2 it
reaches `-1.12160e-7`. Its directional overlap gap is smaller in both states.
Thus “first reported at step 2” does not mean exact separation at step 1.

The candidate uses one quarter of its full proposed movement. Its total cost
falls by **2.12056%**, but the individual terms move in opposite directions:

| Cost | Step 1 | Step 2 |
| --- | ---: | ---: |
| Original creases | 0.01198610 | 0.01176675 |
| Panel bending | 0.001213801 | 0.001100864 |
| Length penalty | 0.0000158921 | 0.0000658625 |
| Contact penalty | 0.000000592825 | 0.00000264617 |

The sum decreases by `0.000280262`; bending savings exceed the two penalty
increases. A finite penalty makes penetration costly, not impossible.
`relaxPinnedContact` keeps descending numerical candidates and checks geometry
separately for convergence/endpoint acceptance. It does not gate every descent
on the independent crossing checker. That is why this correction survives;
this diagnosis neither relaxes that checker nor declares the endpoint settled.
Material, holds, zero clearance, weights and stopping thresholds are unchanged.

The reader checks original material/topology/metadata, exact holds, fresh costs
and contact results, and linkage to the saved full proposal before writing.
It copies source bytes alongside its output. Independent calculations reconstruct
all six pair sections and twenty-four contact witnesses, including endpoints,
plane distances, height extrema, separate costs and archive preservation.
A six-vertex regression reproduces the shallow crossing without a material
solve; all 14,702 contact rows across the seed and both checkpoints also match
the previous implementation exactly, including every gradient. Altered material,
a mismatched trace and overlapping paths are refused before writing.

The [follow-up replay](body-correction-replay.md) tests the second saved
proposal at decreasing fractions with unchanged cost and geometry checks,
without a new solve. At 1/64 both gates pass; at 1/32 one crossing remains.
A bounded continuation can now test whether that progress persists before
adopting a new contact policy. General barriers, clearance at joined creases,
full-crane loads, pressure and a continuously checked flexible route remain separate work.
