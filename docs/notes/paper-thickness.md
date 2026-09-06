# Give coincident layers a thickness, and every face its own corners

Terms used here are defined in [../glossary.md](../glossary.md).

A folded model is a three-dimensional object, and a 3D file of one is worth
more than any picture: it can be turned over, and a fold that looks plausible
from one angle is often obviously wrong from another. senbazuru already holds
everything a 3D viewer needs — where each face is, which way it faces, which
layer is over which — so writing it out ought to be a mesh writer and nothing
more.

It is not, for one reason: **paper has no thickness, and a 3D renderer needs it
to.**

## Why a depth buffer cannot draw a flat-folded model

An SVG of a folded form paints faces in an order, and the order *is* the
picture: the face painted last is the one on top. A 3D renderer does not paint
in order. At every pixel it keeps whichever triangle is nearest the camera, by
comparing depths in a *depth buffer*, and that works beautifully for anything
with depth in it.

A flat-folded model has none. Fold a square into quarters and all four faces lie
in the plane `z = 0`, to the last bit. Where two of them overlap — which is
everywhere — the depth buffer finds two triangles at exactly the same depth and
keeps whichever one rounding favours at that pixel. The result is a shimmering
patchwork of both, a phenomenon renderers call **z-fighting**, and it is not a
bug in the viewer. The viewer is being asked which of two coincident things is
in front, and there is no answer.

Real paper does not have this problem because real paper is thick. A face with
three sheets under it is three sheets up.

## The fix is geometry, not draw order

So the export gives the paper a thickness. Each face is lifted along the sheet's
normal by its **layer number** times a small step:

```
height(face) = layer(face) × t
```

The layer number is the one [layer-numbers.md](layer-numbers.md) works out for
the offset view: the longest chain of faces beneath a face, not a count of what
it covers. That distinction matters more here than it did there. Two faces
lying side by side, with nothing between them, should be *level* — the same
sheet of paper continuing across a crease — and longest-chain gives them the
same number. A position in some topological order would not, and the model
would come out with steps at creases that have no paper under them.

The step `t` is a thousandth of the model's own span by default, which is about
the thickness of paper on a hand-sized square and comfortably more than any
depth buffer can fail to resolve. It can be set smaller, down to a floor: the
coordinates are rounded to a millionth of the model before they are written,
which is all single precision can hold, and a step finer than that is refused
rather than rounded away — rounded, some layers would land a step apart and
others on the same height. A step at the floor defeats z-fighting and looks
like zero-thickness paper, which is the thing it is not.

The same `t` is what a schematic side view of the stack would need, and the two
should share it rather than each inventing one.

## Every face has to own its corners

Lifting faces has a consequence that looks like a mistake and is the point. Two
faces meet along a crease and share its two vertices in the file. Lifted to
different heights, that shared vertex has to be in two places at once — one
height for the face on layer 3, another for the face on layer 7.

So the mesh is written with a fresh copy of every corner for every face. Four
quads become sixteen vertices, not nine. The crease between layers 3 and 7
becomes a step of four thicknesses, which is, again, exactly what a stack of
paper does at that crease. The mesh is not *watertight* — its edges are not each
shared by two triangles, so it encloses no volume — and that is correct: a
folded sheet is a surface, not a solid.

## Where this stops

Only a model folded flat is separated this way. Its normal is one direction for
the whole sheet, and its layer order is the one thing senbazuru can solve for or
is given. A model with paper still in the air is written as it stands, and
where two of its faces happen to be coplanar they will fight. The general case
groups faces into coplanar sets and separates each along its own normal — the
same machinery, run once per plane — and is not built.

A twist has no layer numbers at all, because its layers run in a circle. It can
be written with a thickness of zero, exactly as folded, and no other way.

## Two sides, two primitives

Origami paper is coloured on one side and white on the other. glTF has no
material with two colours, but it culls triangles seen from behind by default,
and a triangle's front is the side from which its corners go round
anticlockwise. So every face is written twice — once as the file winds it, in
the paper's colour, and once wound the other way, in the underside's — sharing
one set of positions and differing only in their index lists. Each copy shows
from one side. Origami Simulator does the same thing with two three.js
materials, `FrontSide` and `BackSide`; this is that trick expressed in the file
rather than in the viewer.

## References

- Tomohiro Tachi, "Rigid-Foldable Thick Origami", *Origami⁵* (5OSME), 2011.
  Thickness as offsetting the folded surface along its normal, done for real
  material rather than for a renderer.
- Khronos Group, *glTF 2.0 Specification*: `POSITION` accessors must state
  their bounds; clients must compute flat normals when none are given;
  `doubleSided` defaults to false, which is what makes two single-sided copies
  work.
- Amanda Ghassaei, *Origami Simulator* — two materials for the two sides of the
  paper.
- [layer-numbers.md](layer-numbers.md), for where the layer number comes from.
