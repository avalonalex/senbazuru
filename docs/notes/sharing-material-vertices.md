# Shared paper, separate lighting

A crease changes the direction a sheet faces; it does not divide the sheet into
two pieces. In the kite-base study, two panels share an oblique crease. Their
triangle meshes must use the same vertex ids along that crease, so a later
length correction cannot pull the panels apart.

The opposite mistake is joining points because folding brought them together.
Run `stack run -- fold examples/quarter-fold.fold -o quarter.fold`: its four
original corners all reach `(1, 0, 0)`, apart from rounding noise. Their ids and
material coordinates remain different:

| Vertex id | Original material coordinates | Folded position |
| --- | --- | --- |
| 0 | `(0, 0)` | `(1, 0, 0)` |
| 1 | `(1, 0)` | `(1, 0, 0)` |
| 2 | `(1, 1)` | `(1, 0, 0)` |
| 3 | `(0, 1)` | `(1, 0, 0)` |

That distinction is represented by `Surface V2`: each vertex has its original
two-dimensional material point and its current three-dimensional position.
Reading a standalone folded file gives `Surface (Maybe V2)` instead, because
the original points may be absent. `requireMaterialCoordinates` checks that
every point is known before returning the stronger type. Geometry can be
rendered without that map, but cannot honestly be measured for stretching by
pretending the folded x/y coordinates were the original sheet.

The study's `senbazuru:material_coords` extension supplies that map explicitly.
`surfaceFromFrame` reads and validates it; `materialFrame` writes it from a
surface with known coordinates. Ordinary `surfaceFrame` exposes geometry and
topology for renderers. Thickness and directional requirements remain library
data, and neither kind of frame export claims that contact has been checked.

Lighting needs a different grouping. A surface normal is a vector perpendicular
to a surface, used to calculate its brightness. Averaging the normals from both
sides of a crease makes the crease look rounded. Instead, keep one normal per
pair of material vertex and panel. The viewer may send two copies of a corner
to the graphics card, with different normals, while the exported material mesh
still contains only one vertex there.

Refinement follows the same distinction. Splitting a triangle into four adds a
midpoint to each of its edges. Key each new midpoint by the two endpoint ids,
sorted into a consistent order, so neighbouring triangles reuse it. Matching
folded coordinates instead would accidentally join distinct layers wherever they
overlap. Original material ids identify paper; spatial coincidence does not.

`Origami.Surface.refineSurface` now applies this to panels returned by
`Origami.Folding`; `StudyCase` uses that shared library implementation. Its triangle
panel ids refer to that function's returned cut pattern, since cutting crossings
can change the face numbering. The viewer consumes those ids directly and no
longer needs to guess panel membership from horizontal or vertical crease lines.

The implementation and checks are in
[`Surface.hs`](../../src/Senbazuru/Origami/Surface.hs),
[`SurfaceSpec.hs`](../../test/Senbazuru/Origami/SurfaceSpec.hs) and
[`StudyCaseSpec.hs`](../../test/StudyCaseSpec.hs).
