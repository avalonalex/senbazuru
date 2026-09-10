# One sheet, several folds

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
The viewer breaks near-equal depth ties using the packet order only after its
contact check passes. That convention fixes underside patches without changing
the mesh; see [depth ties at contact](../../docs/notes/depth-ties-at-contact.md).
Use the depth-buffered 3D view to inspect overlaps; the SVG preview is not the
future general curved-surface visibility renderer.

`stack test` includes the geometry checks. `make fmt` and `make lint` include
this experiment. All geometry is generated in Haskell; the browser only displays
those positions and measurements.

## Folding states

All four examples have a **Folding state** selector. Single and double folds
include the unfolded square and the first fold at 90° and 175°. Their final
option returns to the original packet comparison, where **Shape** chooses the
rounded, sharp or length-corrected surface. For the double fold this final
option is **Second fold · packet comparison**. There are no intermediate states
of its second fold yet: that would require a path between its curved panels,
not independent rigid crease angles or interpolated vertices. **Solver iteration**
remains a separate control for numerical correction, not a folding step.

## Authored bases

Choose **Kite base** or **Blintz base**, then a **Folding state**. A base is a
reusable folded starting shape. These examples turn rigid flaps around their
creases, so material lengths stay unchanged without a length correction. They
stop at 175°, leaving a five-degree opening that makes the layers inspectable.
This opening is a chosen angle, not a prediction of how paper springs back.
The state selector jumps between computed poses; it does not interpolate their
vertices or claim to simulate the motion between them.

[cases.json](cases.json) is the reusable case format. Each entry contains:

- `id`, `title`, and `description` for the gallery;
- `source`, an ordinary FOLD crease pattern, relative to the repository root;
- `steps`, each with a `label` and a complete `angles` list in degrees, in the
  source file's `edges_vertices` order (including zeroes for boundary edges).

Positive angles lift a flap towards the front of the original sheet; see the
[glossary](../../docs/glossary.md) for mountain and valley. The angle states
explicitly override the source's angles. In particular, the blintz fixture's
negative angles face the existing SVG camera, whereas this gallery uses positive
angles to open its flaps upwards. The source file is unchanged.

`StudyCase.buildPose` calls the production rigid folding code, uses its returned
cut pattern, holds the largest panel still, and subdivides the resulting convex
panels three times. Material indices are shared across creases; lighting normals
are split by panel. Boundaries and actual creases get lines, triangle subdivisions
do not. Adding another case of this kind needs a FOLD file and a manifest entry,
with no new shape formula or viewer branch.

This first format is limited to a unit square with convex panels and explicitly
supplied angle states. The original single/double final packet formulas remain separate
controls because their rounded or curved panels are not rigid angle states.
For equally large panels the lowest, then leftmost centre is held still, so the
controls’ first-fold states agree with their original right-to-left fold.
**No general contact check runs on the authored bases.** Their measurements report
`packetOrder: null`; the viewer says contact is untested. Do not run the existing
nearly horizontal four-layer packet check on them. They have OBJ/FOLD exports
and generated `cases.json` state metadata, but no SVG preview: the current SVG
painter only knows the original single/double layer orders.

`StudyCaseSpec` checks every named state for connectivity, positive triangle
area, one unit of material area and edge-length preservation. Random angle and
refinement tests exercise the same builder. Independent checks place the kite's
free corners on its diagonal and all four blintz corners at the centre when
folded to 180°; a 90° check verifies the moving flap and its stationary neighbours.
See [the note on sharing material vertices](../../docs/notes/sharing-material-vertices.md).

## Original fold controls

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
