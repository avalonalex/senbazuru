# One material surface, with thickness as an optional property

A folded sheet is still the same piece of paper. Points on opposite sides of a
crease remain joined, while two layers that happen to touch remain different
parts of the sheet. The shared representation preserves both facts. The
[material coordinates](../glossary.md) identify where a point came from on the
original sheet; its current position says where it is now. Joining points just
because their current positions coincide would weld a folded packet shut.

A connected surface can have sharp creases. It can also approximate a curved
panel with small triangles whose directions change gradually. Edges introduced
for that approximation are not new physical creases: they need different
bending behaviour and should not appear as crease lines in the diagram.
Rendering may duplicate a corner to give its two incident faces different
lighting normals, but those copies must still refer to the same material point.

Thickness answers a different question: how much space does each layer occupy?
It matters for stack height, clearance and material calibration. A surface can
carry those properties without representing the sheet as a solid volume. Our
first shared representation supports zero-thickness geometry and explicit
layer order. A rendering depth adjustment must not silently become a material
parameter. Ordinary glTF viewers cannot read FOLD's layer orders, so stable
viewing of coincident surfaces needs an explicit export policy. Our
[visible glTF scene](visible-paper-mesh.md) removes buried coplanar regions;
a second scene keeps the complete sheet, with neither moving the paper.

Connectivity alone does not say how the sheet should move. The corrected double
fold already preserves lengths and packet order within its declared tolerances,
but many shapes satisfy those checks. Bending resistance within panels and
preferred angles at creases can select among them; a folding instruction supplies
the part being moved and its target. The [length-correction note](restoring-material-lengths.md)
records what is missing. Liu and Paulino's
[bar-and-hinge model](https://pmc.ncbi.nlm.nih.gov/articles/PMC5666233/)
separates stretching, panel bending and crease folding. It is a useful reference
for that separation, not an implementation we have adopted.

This also changes our scope for opening folded bodies. Flat panels can surround
volume, as the walls of a box do. A folded pocket surrounds interior space,
possibly with openings or overlapping flaps. Whether it can open while its
panels stay rigid depends on its crease pattern. Allowing panel
bending expands the possible shapes; merely connecting its vertices does not.
Spreading a crane's wings and opening its body are intended future operations.
The traditional waterbomb balloon, distinct from its triangular starting base,
is another target. Neither operation is implemented by the shared representation.

Start with a controlled opening, such as increasing the distance between two
selected material points while preserving lengths and contact. That gives a
way to specify the intended motion before introducing pressure. A volume target
or pressure force additionally needs a defined cavity and an explicit treatment
of openings, overlapping flaps and closures. One connected square is not a
sealed vessel. If a mathematical cap is used to measure volume across an
opening, it must not become extra paper in the exported model. Predicting air
flow or leakage is further work. The
[pressure-deployed structures of Melancon et al.](https://www.nature.com/articles/s41586-021-03407-4)
show that stiff faces and inflation are compatible in designed assemblies; they
do not establish a folding path for our traditional balloon or crane.

[Issue #146](https://github.com/avalonalex/senbazuru/issues/146) tracks sharing
this representation across the study, SVG projection and 3D export.
The first stage is now `Origami.Surface`: known material coordinates are typed
separately from a folded file's possibly missing map, and the study uses the
library's shared midpoint refinement. Both renderer interfaces accept the
surface. glTF now derives visible pieces without displacing panels, retains a
complete inspection scene, and records material identities in graphics extras.
[Issue #106](https://github.com/avalonalex/senbazuru/issues/106) tracks later
pocket opening. The earlier [schematic puff](the-puff-is-a-drawing.md) remains
an illustration of what a drawing can fake, not a substitute for the material
checks. Senbazuru has no released compatibility contract to protect: replace
obsolete internal paths as the verified cases pass through their replacements.
Keep useful exact folding algorithms and FOLD interchange, rather than retaining
two competing models of the same paper.
