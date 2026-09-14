# Two touching layers must remain two pieces of material

Start with a diamond whose corners are `(-1,0)`, `(0,-0.3)`, `(1,0)` and
`(0,0.3)`. Fold its left half onto its right half along `x=0`. The resulting
triangle contains two layers of the same connected sheet. A point originally
at `(-0.5,0)` now coincides with `(0.5,0)`, but they remain different material
points. Only points on the real crease are shared vertices. Welding the other
coincident points would glue the two layers and prevent them from opening.
See [material coordinates and layer order](../glossary.md).

`WingLayers` uses the same held regions and grip placements as the
[one-layer experiment](held-wing-bending.md). Both roots remain flat; both tip
grips follow the same prescribed placement. Each half has passive resistance
to bending. The root crease prefers a fully closed angle of 180 degrees.
`relaxPinnedContact` keeps all held positions exact while penalizing a negative
gap wherever the layers' projected triangles overlap. A positive gap has no
contact force, so the layers can separate. The order is measured along the
model's positive z direction, independently of the camera. It is supplied by
the experiment, not inferred from the coincident starting positions.

This is a zero-thickness sheet. Adding positive clearance everywhere between
these two panels would contradict their shared root. The experiment therefore
uses zero clearance, with the existing `1e-7` model-unit contact tolerance.
The full triangle-pair endpoint check also examines pairs within each layer;
the force model only acts on the declared relationship between layers.
A passing endpoint is not a collision-free path through the solver's iterates.

Run `stack run senbazuru-material-study -- --wing-layers build/fold-material`.
At eight divisions, the sheet has 81 vertices and 128 triangles, joined along
nine root vertices. The 0-, 20- and 40-degree controls converge and pass the
independent endpoint check. In the 40-degree case, the largest relative edge
error is about `2.11e-8`; held-point error is zero and root-angle error is below
`1e-12` radians. Its bending energy is about `0.035292`, twice the comparable
single-layer value. These illustrative stiffnesses are not measurements of a
particular paper stock.

Two controls check what contact means. Moving the free upper layer down by
up to `0.002` model units makes an initially penetrating guess; the corrected
endpoint passes. Moving just the upper grip up by `0.01` leaves a real opening
between the layers, with a passing endpoint. Moving that grip down by `0.01`
asks held upper material to lie underneath held lower material. The bounded
solve retains the exact bad targets and reports nonconvergence and reversed
order. It does not silently move the grip to manufacture a valid result.

The original solve exposed a numerical limitation under refinement. A
16-division touching bend has 512 triangles. In a compiled diagnostic with the normal 100-iteration limit
per penalty stage, it took about 701 CPU seconds and still did not converge.
Its independent contact check passed and relative edge error was `5.91e-8`,
but the inner linear solves repeatedly failed their residual test. Small
length error alone therefore cannot be used as an equilibrium test. The
original gallery bounded this finer bent diagnostic at 12 iterations per stage and published its FOLD and measurements without presenting it as
an accepted shape. [The follow-up coupled solve](coupled-touching-layer-solve.md)
resolves that stall and replaces this diagnostic with a three-resolution
comparison. The finer flat control passes. These observations were made on
2026-09-13; runtime and convergence near numerical tolerances can vary by
platform. The experiment has not established independence from mesh size.

The added contact cost appears in two places. The force calculation now
rejects disjoint projected bounds before differentiating the triangle
intersection; it still rechecks those bounds after every move. The independent
checker follows the graph of layer orders instead of comparing every order
with every other order to discover indirect relationships. The eight-division
endpoint check went from roughly `0.133` to `0.007` CPU seconds in compiled
probes. The force calculation changed only modestly, from about `6.0` to `5.7`
seconds for that control. These improvements do not fix the fine-mesh linear
solve. No contact acceptance tolerance was loosened.

Exports keep the exact solved positions. The original two panel ids and root
crease id survive in metadata; subdivision edges are `J` joins, not extra
creases. The upper half's triangle winding reverses when folded: its normal
points down. A FOLD order saying the lower triangle is on that normal's side
therefore represents the lower layer correctly. The adapter emits orders only
for triangles with overlapping projected interiors, avoiding a redundant
Cartesian product. SVG and glTF use that same surface. The default glTF scene
removes buried coplanar paper; the complete scene keeps both touching layers.
Neither applies a display offset or turns numerical iterations into motion.

[#200](https://github.com/avalonalex/senbazuru/issues/200) completes the fine
static solve and compares shape and energy across resolutions. The next step
in [#195](https://github.com/avalonalex/senbazuru/issues/195) is to attach this
wing to the crane. Its exact body constraints, flexible motion, friction and finite-thickness mechanics remain
separate open questions.
