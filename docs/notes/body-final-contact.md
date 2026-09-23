# Two distances at the final body-contact refusal

The [ten-correction run](body-short-corrections.md) ends with a passing
**1/32768** trial. The next larger fraction, **1/16384**, is refused because
triangles **46–70** cross. This inspection uses their saved positions and the
start of attempt ten; it runs no new correction solve.
[#342](https://github.com/avalonalex/senbazuru/issues/342) tracks the work.
[The glossary](../glossary.md) defines material coordinates, panels and contact.

**Vertex 27 crosses the plane-distance threshold even as the overlap gap
improves.** The two checks measure different locations. Triangle 46 contains
vertices `[50,86,27]`; triangle 70 contains `[81,71,20]`. Vertex 27's top-view
position lies about `1.4423e-5` sheet units outside triangle 70's outline. Its
plane distance extends that triangle's flat surface beyond its edges. The
height-gap guard instead acts at a corner inside the triangles' actual
projected overlap, where both layers exist.

```bash
stack run senbazuru-material-study -- --body-final build/fold-material/body-short build/fold-material
```

The crossing check asks whether each triangle has vertices farther than
`1e-7` sheet units on both sides of the other's plane, and whether their
intersection segment exceeds `1e-7`. Triangle 70 already spans both sides of
plane 46. Triangle 46 has two positive distances to plane 70, but its third
vertex, 27, is initially within the negative tolerance. That is the condition
that changes. Signs follow the original face winding, not the declared
upper/lower order.

| Saved state | Vertex 27 → plane 70 | Margin above −1e-7, ×1e-12 | Minimum overlap height gap | Intersection length |
| --- | ---: | ---: | ---: | ---: |
| Start of attempt ten | −9.999883680795e-8 | +1.163192 | −7.73436698e-9 | 1.32982984e-6 |
| Retained 1/32768 | −9.999945711955e-8 | +0.542880 | −7.73413160e-9 | 1.32974878e-6 |
| Refused 1/16384 | −1.000000775425e-7 | **−0.077542** | −7.73389645e-9 | 1.32966777e-6 |

These plane distances come from an independent 60-digit calculation of the
literal saved decimal coordinates. The gallery's double-precision calculation
agrees within `3e-18` sheet units. The refused distance exceeds the negative
threshold by approximately **7.75e-14**; its sign is not just lost digits in
the displayed number. This confirms the decision for these coordinates,
without claiming that such a tiny distance has physical significance.

Both trials already contain a mathematical intersection, and that segment
gets slightly shorter in the refused trial. Their smallest height gap also
improves: it becomes less negative. A negative gap means the declared upper
layer, triangle 70, is locally below triangle 46. The gap stays well inside
the unchanged `1e-7` order tolerance. The refusal is therefore a threshold
transition, not the sudden appearance of a large or visible intersection.
It is not evidence that the geometry checker reported an imaginary collision.

The four overlap-corner guards do not constrain vertex 27's plane distance.
Nor is this mainly a choice of vertical versus perpendicular units: plane 70's
normal has a vertical component of magnitude about `0.99744`. Extending its
height to vertex 27 would give a roughly `-1.0026e-7` vertical gap there, much
larger than the actual overlap minimum of `-7.734e-9`. They are different
points. We must not call the extended-plane value a fifth physical contact.

The gallery marks vertex 27 in blue and the negative-gap overlap corner in
green, with fixed crops shared by all three saved states. Actual-size paper
views keep the same camera and 600 pixels per sheet unit. A separate chart
magnifies the threshold margin numerically; it does not exaggerate paper
positions. JSON retains all six plane distances, intersection endpoints,
overlap witnesses, original linear gap predictions and remeasured geometry
and costs. The reader checks the retained chain and all 310 saved trial
fractions, including unchanged material identities, holds and acceptance
measurements. Source reports and FOLD files are copied byte-for-byte.

A six-vertex regression reproduces the pass/refusal transition, checks the
independent plane distances and shows that the gap and intersection length
improve despite the refusal. It adds no material solve to the default tests.
Independent calculations also check the three full exported meshes and their
measurements. All 19 SVGs parse, the browser controls and fixed crops work,
and 5,369 source files remain unchanged. Corrupting the correction count or
a trial's coordinates is refused before a gallery is written. All 1,830 tests
pass after a warning-free cold build, with clean formatting, HLint 3.10 and
the JavaScript checks.

The next bounded experiment is **one direction comparison at the saved start
of attempt ten**, adding a local guard for vertex 27's signed distance to
plane 70. Keep the original three-pair proposal as a control and retain the
all-pair acceptance checks. Because this vertex is outside the finite
triangle, such a guard may be conservative: it would be a local fixture
policy, not a general contact-discovery algorithm. Do not add more continuation
steps or change tolerances as part of that comparison. The almost-motionless
second correction remains a separate sensitivity diagnostic; no settled body
opening, flexible folding route or whole-crane inflation is established here.
