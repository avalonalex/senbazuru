# A pre-crease can stay flat in the target state

Fold a square along its diagonals and midlines, then open it again. It now has
four lines crossing at the centre: eight segments extending from that point.
These are **pre-creases**, marks made to guide a later fold. Having a mark does
not mean the paper must bend there in every later state. The opening steps of
the [traditional crane](https://origami.me/crane/) and
[waterbomb](https://origami.me/waterbomb/) illustrate pre-creasing before the
sheet collapses into a base, a reusable folded starting shape.

Our two examples start with the same coordinates: corners `(0,0)`, `(1,0)`,
`(1,1)`, `(0,1)`, four edge midpoints, and centre `(0.5,0.5)`. They differ in
which segments actually close. The square base keeps one diagonal flat; the
waterbomb base keeps the vertical midline flat. Each therefore has six active
crease segments at the centre, with two mountains and four valleys. See the
[glossary](../glossary.md) for those directions and
[examples](../../examples/README.md#square-and-waterbomb-bases-meeting-creases)
for the exact assignments and generated drawings.

In FOLD, `M` with angle −180° and `V` with angle +180° close the paper back on
itself. `F` with angle 0° leaves the two sides of a guide line in the same
plane. The guide still subdivides the drawing into faces, but is omitted when
counting the creases that bend. This distinction matters to
[Maekawa's theorem](maekawa.md): two mountains minus four valleys is −2, as
required. Merely keeping every original pre-crease as an active mountain or
valley describes a different state. Passing that count alone still does not
establish a valid folding.

The independent coordinate expectations in `Senbazuru.Origami.BasePatternSpec`
check what happens when all six active segments close. Run:

```bash
stack test --ta='--match meeting-crease'
```

For the square base, all four original corners meet at `(0,0,0)`, and the
sheet's centre remains at `(0.5,0.5,0)`. The other two corners of the folded
outline are `(0.5,0,0)` and `(0,0.5,0)`: a square of side ½. For the waterbomb
base, the original corners meet in pairs at `(0,0,0)` and `(1,0,0)`, the four
midpoints meet at `(0.5,0,0)`, and the centre is again `(0.5,0.5,0)`: a triangle
of base 1 and height ½. Both cover area ¼ of the original sheet. The tests also
check that each face agrees on its shared vertices, lengths remain unchanged,
and each collapsed form has exactly one valid layer order.

These are endpoint checks. They do not supply a motion from the open sheet to
the collapsed base. Creases meeting at a vertex constrain each other's angles;
an intermediate state must satisfy those constraints and then be checked for
contact. Nor does `F` record the stiffness or memory left by a pre-crease: it
records only that the guide is flat in this state. Those are separate parts of
the material study.
