# One sheet, two bends

An executable geometric study for #114: a unit square folded once, then in half
again at right angles. It compares sharp creases with exaggerated rounded bends.
Both single folds preserve surface lengths. Both double folds are **prescribed shapes with measured
distortion**, not physical solutions.

```bash
stack run senbazuru-material-study -- build/fold-material
python3 -m http.server 8000 --bind 127.0.0.1 --directory build/fold-material
```

Open http://127.0.0.1:8000 or `build/fold-material/index.html`. The source file
`study/fold-material/viewer.html` is a template, with no model data until generation.
The generated viewer works offline and lets you rotate both surfaces and inspect stretch on the
original sheet. The generated OBJ files use shared vertex indices; FOLD files
carry the same mesh and original material coordinates. The SVG previews reuse
Senbazuru's camera and SVG backend, with the known packet layer order and
depth-sorted triangles within each layer.
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

The derivations and measurements are recorded in
[the rounded-bend note](../../docs/notes/two-bends-need-more-than-radii.md) and
[the sharp-crease note](../../docs/notes/sharp-creases-and-opening-panels.md).

On this Mac, building required the Command Line Tools linker to match its SDK:
`DEVELOPER_DIR=/Library/Developer/CommandLineTools stack test`. This is a command
setting, not a required project configuration or a global toolchain change.
