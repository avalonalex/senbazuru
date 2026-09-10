# Shared paper, separate lighting

A crease changes the direction a sheet faces; it does not divide the sheet into
two pieces. In the kite-base study, two panels share an oblique crease. Their
triangle meshes must use the same vertex ids along that crease, so a later
length correction cannot pull the panels apart.

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

`StudyCase` applies this to panels returned by `Origami.Folding`. Its triangle
panel ids refer to that function's returned cut pattern, since cutting crossings
can change the face numbering. The viewer consumes those ids directly and no
longer needs to guess panel membership from horizontal or vertical crease lines.

The implementation and checks are in
[`StudyCase.hs`](../../study/fold-material/StudyCase.hs) and
[`StudyCaseSpec.hs`](../../test/StudyCaseSpec.hs).
