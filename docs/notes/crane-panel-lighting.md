# Seeing the tucked crane without triangle lighting seams

The owner selected **More tucked** as the preferred whole-crane shape on
2026-09-27. Both galleries now start there. This chooses the existing slim
body and raised wings as a visual target; it does not accept their stretching
or intersections as valid paper. The drawing comparison starts with the saved
middle-spread pose, so it isolates the wing orientation on the same body.

The 3D view had a second problem besides shape: every small triangle was lit
as a separate flat surface. These triangles approximate a curved
[panel](../glossary.md#origami), a piece of paper between creases. Their lighting
boundaries can resemble extra folds that are not in the crease pattern.

A **normal** is a direction perpendicular to a surface. The renderer uses it
to calculate brightness. `PaperLighting` averages triangle normals at shared
material vertices within each original panel, weighted by triangle area. The
browser interpolates those corner directions when shading a triangle; it never
changes that triangle's positions. For example, two test triangles with area
ratio 1:2 and normals `(0,0,1)` and `(0,1,0)` share the direction
`(0, 2 / sqrt 5, 1 / sqrt 5)`. Their unshared corners retain their own normals.
The Haskell test calculates this example.

Two boundaries remain deliberately sharp. Adjacent original panels get
separate averages even at the same material vertex, preserving creases. Two
folded layers at coincident positions also remain separate: the key is the
original vertex id, not a distance test. If an average cancels or points behind
its own triangle, that corner keeps its flat normal. Lighting must not disguise
a reversed patch as a smoothly curved one.

`whole-crane/spread.html` offers **Paper panels** and **Individual triangles**
lighting at the same camera and pose. Haskell writes a small lighting file per
pose; the viewer joins it to GLB corners through their material references.
Where the visible-paper scene cut a triangle, a corner part-way along it takes
the same weighted blend of its triangle's corner directions as its material
reference records. The two paper sides receive opposite normals. All existing SVG, FOLD and GLB
exports remain unchanged, including their material/contact measurements.
Downloads retain the original flat lighting. This isolates the presentation
experiment from a change in paper shape or a new export policy.

Independent NumPy calculations reproduce the directions for all nine poses
within `1.12e-16` per component. In More tucked, 1,125 of 1,344 triangle corners
change lighting direction; eight retain flat normals because the average would
point behind their triangle. All 232 existing archive, SVG, FOLD and GLB files
retain their hashes. Browser checks compare both lighting modes and paper sides;
small tests exercise unequal triangle areas, creases, coincident layers,
reversed patches and the GLB's differently ordered front/back graphics indices.

This pass addresses subdivision shading only. The distorted wing roots,
sharp source creases through the cushion and intersections still need visual
review in the preferred pose. Smoother brightness cannot repair those joins or
prove a physically achievable body opening. The next shape change should keep
the chosen outer wing arches and slim body as references, with a matched
before/after drawing; it should not return to microscopic contact repairs.
