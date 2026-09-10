# One sheet, two bends

An executable geometric study for #114: a unit square folded once, then in half
again at right angles. It compares sharp creases, exaggerated rounded bends,
and a length/contact correction of the sharp examples. The original double folds are
**prescribed shapes with measured distortion**. The corrected double fold
meets its length and packet-order tolerances. It still does not solve paper
bending stiffness, crease angles or finite thickness.

```bash
stack run senbazuru-material-study -- build/fold-material
python3 -m http.server 8000 --bind 127.0.0.1 --directory build/fold-material
```

Open http://127.0.0.1:8000 or `build/fold-material/index.html`. The source file
`study/fold-material/viewer.html` is a template, with no model data until generation.
The generated viewer works offline and lets you rotate both surfaces and inspect stretch on the
original sheet. Its default **Lengths + layer order** view shows the starting and
corrected sharp folds with a shared camera, scale and strain colour range.
Choose a recorded solver iteration to inspect convergence; these are computed
meshes, not an animation of the fold. The single fold correctly finishes at
iteration zero. The generated OBJ files use shared vertex indices; FOLD files
carry the same mesh and original material coordinates. The SVG previews reuse
Senbazuru's camera and SVG backend, with the known packet layer order and
depth-sorted triangles within each layer. Only the original examples have SVGs:
that painter would hide layer-order violations in unfinished solver iterations.
Use the depth-buffered 3D view to inspect overlaps; the SVG preview is not the
future general curved-surface visibility renderer.

`stack test` includes the geometry checks. `make fmt` and `make lint` include
this experiment. All geometry is generated in Haskell; the browser only displays
those positions and measurements.

The rounded bend radius is 0.015 times the original square's side. The resulting layer
separation of 0.03 is exaggerated for inspection, not a measured paper thickness.
The single bend reserves a material band of width pi times the radius. The
second fold uses that same band for a larger outer radius and therefore stretches
it. The red original-sheet map exposes exactly where. There is no elasticity,
contact, gravity, plastic crease history or equilibrium solve in this baseline.

The sharp single fold is a rigid hinge with a narrow wedge opening. In the sharp
double fold, gaps taper to zero at the creases and panels are not parallel. Its
0.538% maximum mesh-edge extension remains a failure to preserve material, even
though it is much smaller than the rounded example's 199.880%. The sharp heat map
uses a 0–1% range, the rounded map 0–200%; the viewer labels this difference.

`FoldRelaxation` reduces the sharp double fold's maximum absolute edge-length
error from 0.538% to 0.000852% in 69 iterations, below its 0.001% target. It
keeps the original material coordinates and triangle connectivity. The
before/after map measures triangle strains directly and uses −1% to +1% for
both images. `relaxation.json` records iteration counts, errors and whether the
length and contact targets were reached; `measurements.json` includes edge and principal strains,
area, connectivity and packet-order checks. Each recorded checkpoint has its
own OBJ and FOLD export.

`FoldContact` checks the known order of these nearly flat layers and supplies
separation constraints to the solver. A length-only correction lets layers
cross near the crease intersection; the coupled correction reduces the maximum
reversal to about `3.24e-9` model units, below the `1e-7` contact tolerance. The
viewer reports both targets and flags crossings in unfinished iterations. No
paper bending stiffness, crease-angle preference, finite thickness or general
collision handling is solved.

The derivations and measurements are recorded in
[the rounded-bend note](../../docs/notes/two-bends-need-more-than-radii.md),
[the sharp-crease note](../../docs/notes/sharp-creases-and-opening-panels.md), and
[the length-correction note](../../docs/notes/restoring-material-lengths.md).

On this Mac, building required the Command Line Tools linker to match its SDK:
`DEVELOPER_DIR=/Library/Developer/CommandLineTools stack test`. This is a command
setting, not a required project configuration or a global toolchain change.
