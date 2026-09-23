# One more guard permits a larger body correction

[The final saved refusal](body-final-contact.md) occurs when vertex 27 crosses
triangle 70's plane-distance threshold outside its projected outline. This
comparison starts at the same saved shape, before attempt ten, and adds one
local guard: the **predicted** signed distance must not become more negative.
The original three-pair proposal remains an archived control.
[#345](https://github.com/avalonalex/senbazuru/issues/345) tracks the experiment;
[the glossary](../glossary.md) defines panels, contact and material coordinates.

**The usable fraction increases from 1/32768 to 1/256, but the next fraction
still crosses 46–70.** The extra guard is active: it limits the new direction.
Its linear prediction removes the first-order worsening of this distance.
The finite movement still changes the plane and consumes almost all the tiny
starting margin. This is progress on a numerical blockage, not a visibly
opened body.

```bash
stack run senbazuru-material-study -- --body-plane build/fold-material/body-short build/fold-material
```

A plane is the flat surface through three vertices, extended beyond the
triangle's edges. For triangle vertices `a,b,c`, the signed distance of `p`
is `n · (p-a)`, with `n` the unit normal from `(b-a) × (c-a)`. The derivative
measures how that distance responds to small vertex displacements. It includes
all four vertices and the normalization of the plane normal: freezing the
triangle would constrain the wrong movement. Signs retain the original winding.

The starting distance is approximately `-9.999883680573e-8` sheet units, just
`1.16319e-12` above the negative crossing threshold. The new guard uses this
starting distance as its floor, following the existing incremental policy;
zero displacement is feasible. It neither pushes the distance to zero nor
adds a material penalty. Vertex 27 is outside the finite triangle, so this
is a conservative fixture policy, **not a newly discovered physical contact**.

The archive reader validates all 310 old trials. Rebuilt material equations
and twelve overlap-corner guards must match the saved attempt exactly. Only
one new quadratic approximation of the material objective is solved, using
the same method, damping, budget, holds and weights. Both directions then
use the same 31 fractions and all-pair geometry and actual-cost checks.
There are no new continuation steps or changed acceptance thresholds.

| Direction | Selected fraction | Active guards | Selected movement, drawing pixels | Total cost decrease |
| --- | ---: | ---: | ---: | ---: |
| Archived three-pair control | 1/32768 | 2 | 0.0000165 | 0.000232% |
| With vertex 27 → plane 70 | 1/256 | 3 | 0.002158 | 0.029558% |

The fractions differ by **128×**, but the directions also differ, so this is
not exactly a 128× displacement. At the new selected trial, maximum relative
length error is `2.25221e-6`, holds remain exact and all crossing/order checks
pass. Full proposed movement is still `0.000920598` sheet units, about **9,206×**
the equilibrium limit. A passing short trial does not meet that limit.

| New direction's fraction | Linear plane-distance prediction | Actual plane distance | Margin above −1e-7, ×1e-12 | 46–70 crosses |
| --- | ---: | ---: | ---: | --- |
| 1/256 | −9.999883680574e-8 | −9.999998974632e-8 | +0.010254 | No |
| 1/128 | −9.999883680574e-8 | −1.000034485664e-7 | −3.448566 | Yes |

The accepted trial's actual distance drops about `1.153e-12` even though the
linear prediction is essentially unchanged. The next larger trial loses
about `4.611e-12`. The overlap height gap improves and the intersection segment
shrinks in both trials, just as in the previous inspection. A local linear
inequality cannot guarantee the distance after a finite displacement.

Separate costs remain visible, including the small rise in length cost:

| Cost | Saved start | Control selected | Plane-guard selected |
| --- | ---: | ---: | ---: |
| Creases | 0.0118278673 | 0.0118278470 | 0.0118252644 |
| Panels | 0.0011241062 | 0.0011240965 | 0.0011228752 |
| Lengths | 0.0000193598 | 0.0000193599 | 0.0000193772 |
| Contact | 0.0000035375 | 0.0000035374 | 0.0000035189 |

The gallery compares the selected trials or a common fraction, with fixed
contact crops and shared actual-size cameras at 600 pixels per sheet unit.
It exports all 63 states, 378 SVGs, raw quadratic rows and corrections, guard
activity, linear predictions and remeasured geometry/costs. Original reports
and meshes are copied unchanged. Failed or unverified directions remain
diagnostic; numerical trial positions are not folding instructions.

Six fast tests check the moving-plane derivative, winding, rigid-motion
invariance, held coordinates and invalid inputs. Independent calculations
check the actual fixture's derivative, both quadratic balances, all exported
mesh measurements, pair intersections and overlap witnesses. The archived
control reproduces exactly; source files remain unchanged. No body solve is
added to the default test suite. All 1,862 tests pass after a warning-free cold
build (171.7 seconds of test time); formatting, HLint 3.10 and JavaScript checks
pass. All gallery fractions and views work in the browser.

[The following saved-data inspection](body-plane-loss.md) separates the finite
loss using the triangle centroid. About 98% of the missed distance change at
1/128 comes from relative movement interacting with the rotated normal; a
second-order estimate closely matches the saved result. It runs no new solve.
The almost-motionless second correction remains a separate sensitivity
diagnostic, and no settled body opening or whole-crane inflation is established.
