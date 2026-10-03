# An angle gate is not a crease spring

The [earlier body-release trial](wing-root-holds.md) lets four panels beside
one wing root move, while their outer boundary and the wing tip stay held.
It fails length, original-angle and contact checks. Before enlarging the free
region, distinguish two questions: which angles does the material prefer,
and which angles must a reported endpoint preserve?
With the wing hinged at its root, where the studies now hinge it, all three
trials pass; see [the last section](#with-the-wing-hinged-at-its-root).

Run the matched controls:

```bash
stack run senbazuru-material-study -- --crane-body build/fold-material
```

A crease spring gives an energy cost to departing from its preferred angle.
It contributes forces during the solve. The old `1e-5`-radian angle limit is
instead an acceptance gate applied afterwards. Removing that gate cannot
change a single position. The page evaluates each solved mesh under both
policies, then distinguishes those verdicts from changing the springs.
See the [glossary](../glossary.md) for creases, panels and rest angles.

The [pocket map](crane-pocket-map.md) supplies 22 candidate opening creases.
Two meet the four released root-neighbour panels: source creases 21 and 46,
both valleys connecting Wing A's base strips to the central body core. The
remaining candidates belong to other regions. Selection uses shared material
edges and the map, rather than picking whichever angles happen to fail.
The body patch here is the earlier four root neighbours, not the map's eight
central panels; those central panels still remain held.

The three free-patch trials use the same 609 material vertices, 1,176
triangles, 50-degree tip grip, starting guess and 902 source layer orders:

| Trial | Selected stiffness | Selected preferred angle |
| --- | ---: | ---: |
| Original | unchanged | 180° |
| Weaker | one tenth | 180° |
| Open preference | unchanged | 170° |

All other springs remain identical. In particular, the four authored wing-root
springs retain their flat preference. A rest angle is a preference, not an
imposed rotation, and these stiffness values are illustrative, not a fit to
measured paper. Each normal trial allows forty iterations per penalty stage;
an incompatible upper grip allows two. The fixed-body reference reproduces
the earlier accepted control.

Acceptance under the selective policy still needs solver equilibrium, relative
material edge errors at most `1e-5`, exact remaining holds, whole-sheet contact
and layer-order checks, and original-angle errors below `1e-5` radians on every
unselected fold. The selected angles are measured without that exact gate.
Their departure always uses the original 180-degree target, including in the
170-degree trial; replacing the reference by the new preference would answer
a different question. Refined segments keep their source crease id, so the
reported range can show different turns along one crease.

The four automated tests isolate this policy using unchanged controls, energy
comparisons, a fully held copy of the original flat crane, and an incompatible
grip. The fully held solve supplies a cheap known equilibrium for the acceptance
checks; it is not evidence that a free body can open. The long free-patch
comparisons run in the gallery and retain diagnostic FOLDs and measurements.
Only accepted endpoints enter its 3D selector. Numerical corrections can
stretch or cross paper; none of these trials certifies a physical folding path.

The measurements on 2026-09-14 show that neither spring change fixes the
released patch:

| Free-patch trial | Selected original-angle error (rad) | Retained original-angle error (rad) | Relative edge error |
| --- | ---: | ---: | ---: |
| Original | 1.30e-12 | 0.0187 | 3.75e-5 |
| Weaker | 1.30e-12 | 0.0187 | 3.75e-5 |
| Open preference | 5.99e-11 | 0.0187 | 3.75e-5 |

All three stop unconverged after 118 iterations and have 49 crossing triangle
pairs plus 18 touching pairs without a supplied order. No retained order is
reversed, which also shows why the independent crossing check remains needed.
Remaining holds stay exact. The original run reproduces the earlier diagnostic
vertex-for-vertex; the weaker and 170-degree trials differ from it by at most
`5.46e-12` and `7.10e-10` model units. Each solve took about nine CPU minutes.
The selected folds remain essentially at 180 degrees even with a 170-degree
preference; the fixed-body reference still passes both angle policies. The
incompatible-grip control is rejected, with 18 reversed orders and a relative
edge error of 0.124.

The largest retained-angle error belongs to crease 51, followed by crease 26.
These are internal mountain folds joining pairs of released panels. In the
original result, 47 of the 49 crossings occur between the panel pairs joined
by those two creases. The remaining contacts need their own attention too.
This is a reproducible diagnostic, not proof that the held region has no
compatible shape: the solves fail equilibrium and material/contact checks,
so their positions cannot decide that physical question.

The [follow-up diagnosis](internal-crease-diagnostic.md) inspects contact
and coupled freedom around those internal folds before enlarging the free region.
It distinguishes reaching the iteration budget from an exhausted line search. Merely changing the selected
angle gate cannot repair these endpoints. A broader body release and paired
wing grips should be a distinct experiment, with the current failed trial kept
as a control. Pocket pressure and continuously checked flexible paths remain
later work under [#195](https://github.com/avalonalex/senbazuru/issues/195).

## With the wing hinged at its root

The studies now hinge the wing at its root, folded y = 0.37585
([flap-roots.md](flap-roots.md)). The released patch beside it is eight
panels, 9, 10, 25, 26, 31, 44, 45 and 51. The pocket map now checks the
crane's structure rather than the 1/4 fixture's counts (owner decision 37),
and gives two opening creases beside the patch: 22, joining panels 10 and 2,
and 49, joining panels 9 and 1, both valleys again. The trials use 1,127
material vertices, 2,196 triangles and 978 source layer orders.

Above the wing's widest point its paper is four layers deep, and every trial
turns that base as one piece about the hinge. The fixed-body reference
searches for the angle that leaves the least bending energy and finds
28.383°, the angle `crane-root`'s flat-preference control finds. The three
free-patch trials hold their base there and are solved again 1° either side,
refused if a side ends with less bending energy; the incompatible grip takes
the angle unchecked (owner decision 36).

Measured on 2026-10-03, one run:

| Free-patch trial | Selected original-angle error (rad) | Retained original-angle error (rad) | Relative edge error | Iterations | Strict and selective verdicts |
| --- | ---: | ---: | ---: | ---: | --- |
| Original | 1.45e-14 | 6.66e-6 | 5.02e-6 | 62 | both accept |
| Weaker | 1.45e-14 | 6.66e-6 | 5.02e-6 | 62 | both accept |
| Open preference | 3.44e-11 | 6.66e-6 | 5.02e-6 | 62 | both accept |

All three converge with no crossing report and no touching pair left without
an order, so the released patch that fails at 1/4 passes at the root under
both policies, with its original springs. The original free patch is the same
solve as [crane-internal's original control](internal-crease-diagnostic.md#with-the-wing-hinged-at-its-root),
and ends with the same edge error to every digit. The selected folds stay at
180 degrees whatever their springs, as at 1/4: the weaker trial's edge error
equals the original's to every digit and its retained-angle error to ten, and
the 170-degree preference changes the edge error only in its eighth. Here the selected springs do not decide
acceptance. The fixed-body reference passes both policies, and the
incompatible grip is still refused, with 18 reversed orders and a relative edge
error of 9.59%.

The base check passes for all three: the sides end 1.71% and 1.35% above the
angle's bending energy for the original and weaker trials, and 1.67% and 1.30%
for the 170-degree one, at 27.383° and 29.383°.

The stable 3D view, which leaves out buried paper, cannot be built for the
three accepted free-patch endpoints: their layer orders run in a circle, and
painting one face after another needs an order without one. The gallery keeps
their complete-sheet GLBs instead, as it does for any accepted mesh whose
stable view fails.

The gallery took 11,372 CPU seconds over 3.2 hours, with a peak of 5.9 GB:
526 for the search, 3,834, 3,294 and 3,184 for the three free-patch trials'
three solves each, and 490 for the incompatible grip.

