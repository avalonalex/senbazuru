# A snap band's edge is a jump in the contact penalty

Terms are in [the glossary](../glossary.md). `SurfaceContact` measures how far
one layer of paper is above another at each corner of the overlap between two
triangles seen from above: one *contact row* per corner. The solver's objective
adds the square of every negative gap, so the *contact penalty* grows as the
layers cross. Before measuring, the clip moves a corner lying within a band of a
clipping line onto it ([snap-edges-along-a-clip-line](snap-edges-along-a-clip-line.md)).

That makes the band's edge a jump. Take two triangles, measured on 2026-10-22
with the band at 1e-12 as a distance (owner decision 62). The first has a side
of length 1 along the x axis and lies on the side y ≥ 0. The second lies 0.01
lower in height, though the order between them says it must be higher, and its
apex points at that side from y < 0.

| Apex below the side's line by | Contact rows |
| --- | --- |
| 1.1e-12 | none |
| 1.0e-12 | none |
| 0.9e-12 | three, each −0.01 |
| 0 | three, each −0.01 |

At 1.0e-12 the apex is outside the first triangle, and the shadows do not
overlap. At 0.9e-12 it is snapped onto the line, where a corner counts as
inside, so the overlap is three copies of the apex. It has no area, and each
copy is a contact row with the whole gap there. Moving the apex 1e-13 adds three
rows' penalty at once.

Without the snap the same jump would sit at the line itself. An overlap that
appears has the full gap at its corners however small its area is;
[rejected-bending-trials](rejected-bending-trials.md) describes that. The snap
moves the jump from the line to the band's edge, and no width of band removes
it.

## The released strip

The crane-root gallery's released strip ([wing-root-holds](wing-root-holds.md))
is the crane wing with the strip at its root free to turn. With the band at 1e-12
of the cross product (owner decision 59), it stopped converging at its own hinge
([#607](https://github.com/avalonalex/senbazuru/issues/607)). The solver takes
Gauss-Newton steps, and a *line search* tries each one at its whole length, then
half, a quarter and so on, and keeps the first that lowers the objective. In the
last penalty stage it refused 26 times at every step and kept 2⁻²⁶ of the step,
until the stage ran out of iterations.

Taking that step apart in GHCi on 2026-10-21 and 2026-10-22 (compiled `-O`, one
run each) found two causes.

- **From 2⁰ to 2⁻⁶ of the step,** the objective rises because the step drives
  contact rows into contact, to −1.7e-7 at its whole length. Some of them sat
  about 8e-10 clear at its start, and others came from overlaps that did not
  exist yet. The solver adds a row to its linear step only once its gap is
  negative, so it saw neither coming.
- **From 2⁻⁷ to 2⁻²⁴,** the objective rises by 3.1e-8 to 5.9e-8 at every
  scale, and 5.93e-8 of that is five rows at −1.09e-9. They are there at 2⁻²⁴,
  where no vertex moves more than 6e-14, and one of them still at 2⁻²⁵. Two
  corners' cross products with a side 0.0129 long shrink from 1.0000005e-12 to
  0.9999926e-12 in size, into the band of 1e-12 of the cross
  product. One pair of triangles gains an overlap
  of three copies of one corner, and two other pairs each gain a second copy of
  a corner they already had.

Leaving out the three pairs of triangles those rows belong to, the objective
falls by 2.7e-8 at 2⁻⁷, a step the line search would keep. The rows a step
cannot foresee cost a few short steps; the band's edge is what held the stage.

With the band as a distance, the same two positions add no rows from 2⁻⁴ down,
and the objective falls by 2.8e-8 at 2⁻⁷. Started from the stalled positions,
the stage keeps 2⁻⁷, then 2⁻⁶, then a whole step, and converges in 20
iterations, though some of its later steps are cut to 2⁻¹⁹. The whole step's
rise in the objective is the same under both bands, 6.03e-3.

Probed at 19 hinges within 1e-9 of its own on 2026-10-22, the released strip
converged at all 19 before #566's fix to the clip, at 14 with decision 59's band,
and at all 19 with the band as a distance. Under each band the 19 runs end in
seven to nine different states, and the five failures end in the same one: one
path, not five. Whether a run meets a band's edge where it hurts depends on
where its corners happen to lie, under any band.

Three changes to the solver, tried at nine of those hinges, added the rows a
step would carry into contact to its linear step, as rows to be pulled toward
zero. They were aimed at the first cause, not the second. The two that let the
released strip converge stopped crease correction's 64-triangle starts from
converging and blocked the body patch's solves; with the third, neither the
released strip nor `curved` converged anywhere.
None was adopted.

The jump is still there, at the new band's edge: the table above was measured
with it. [#617](https://github.com/avalonalex/senbazuru/issues/617) tracks
removing it, by a penalty that grows from zero as an overlap appears.
