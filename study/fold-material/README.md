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

All seven examples have a **Folding state** selector. Single and double folds
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
  source file's `edges_vertices` order (including zeroes for boundary edges);
- optional `contact` requirements, with named panels, an ordering direction,
  and pairs written `[lower, upper]`.

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
Kite and blintz now declare that each flap stays above the central panel, measured
towards the front of the original sheet (`direction: [0, 0, 1]`). No order is
invented between flaps that do not overlap. Each panel name has an `at: [u, v]`
point strictly inside that panel on the original sheet: for example the kite's
`lower-right` name uses `[0.8, 0.1]`. The point identifies material, so changing
face numbering or the viewer's camera cannot change which panel a rule means.
Every material panel must be named exactly once; unknown names and cyclic orders
are rejected.

`StudyCase.buildCasePose` runs `PanelContact` on the original rigid polygons,
independently of mesh subdivision. All pairs are checked for crossings in 3D,
including upright flaps. Declared order is checked wherever the panels' projections
overlap along the ordering direction. Touching is allowed; a coplanar interior
overlap needs an order, possibly implied through other ordered panels. If both
panels stand parallel to the ordering direction, that order is reported as
unchecked rather than passed. The distance tolerance is `1e-7` of the unit sheet.

The viewer reports passed, failed and unresolved checks in **Panel order and
contact**, with named pairs for failures. `measurements.json` and the embedded
viewer data include `panelContact`; FOLD exports include the same report in
`senbazuru:panel_contact`. Generated `cases.json` includes the declarations.
`packetOrder` remains null on authored states: the original curved-packet solver
is a separate check. Single/double first-fold angle states have no declarations
yet and are explicitly marked untested, while their final packet controls retain
their existing solver checks. OBJ exports carry geometry; consult the companion
measurements for checks. No SVG preview is supplied for authored states because
the painter only knows the original single/double layer orders.

These checks report a pose's violations; they do not move its vertices, adjust
crease angles, or add display depth bias. A checked state says nothing about the
path used to reach it. Bending, finite thickness and continuous collision handling
remain outside this milestone. See [panel contact and order](../../docs/notes/panel-contact-and-order.md).

`StudyCaseSpec` checks every named state for connectivity, positive triangle
area, one unit of material area and edge-length preservation. Random angle and
refinement tests exercise the same builder. Independent checks place the kite's
free corners on its diagonal and all four blintz corners at the centre when
folded to 180°; a 90° check verifies the moving flap and its stationary neighbours.
Contact tests cover all 14 kite/blintz states, fully closed 180° states, and
deliberately reversed folds. Independent polygon fixtures check 3D crossings,
hinge contact, coplanar order, upright panels and rotated measuring directions.
See [the note on sharing material vertices](../../docs/notes/sharing-material-vertices.md).

## Square and waterbomb collapse

The [square and waterbomb crease patterns](../../examples/README.md#square-and-waterbomb-bases-meeting-creases)
now have seven gallery states each. Both have a shared centre where six creases
bend and two guide segments stay flat. Select **Square base** or **Waterbomb
base**, then choose the unfolded sheet or mountain magnitudes 30°, 60°, 90°,
120°, 150° and 175°. The last is nearly closed, leaving room to see the layers.

These states follow a symmetric collapse: two equal mountain angles and four
equal valley angles, with the valleys folded further. At mountains −90°, the
valleys are +109.471220634°, not +90°. The explicit angle lists in `cases.json`
come from [this relationship](../../docs/notes/symmetric-base-collapse.md).
The existing folding engine derives positions and refuses states that fail
either shared-vertex closure or the requested crease angles. No vertex
interpolation or change to the case format is involved.

Each case names all eight source triangles, including the pairs on either side
of a flat guide. Names such as `south-west` identify the western triangle along
the original south edge. Six above/below declarations encode two chains of four
triangles from the fixture's final flat stacking; they use the fixed panel's
+z direction and stay independent of the camera. All 28 pairs pass crossing
checks at every recorded state, and the declared orders pass wherever they
overlap. Reports and angles use the same viewer and export fields as the other
authored bases.

`BaseCollapseSpec` checks the formula against the manifest, random intermediate
angles and refinements, an integer-degree sweep including 0° and 180°, and
independently derived distances between material points. It also checks that
uniformly scaling all final angles, or changing one crease independently, is
rejected. `StudyCaseSpec` checks all 14 new viewer states, closed endpoint contact,
and the failures from reversing the folding side. These are sampled states of
a chosen symmetric path; continuous collision certification, paper bending and
finite thickness remain outside this study.

## One rabbit ear towards the fish base

Choose **Rabbit-ear fold** to gather the south-east corner of the fish crease
pattern into a pointed flap. Eight states cover the unfolded sheet and mountain
magnitudes 15°, 30°, 60°, 90°, 120°, 150° and 175°. The four creases around one
interior vertex turn together; the opposite half of the square stays flat.
Two valleys turn faster than the other valley and mountain, so the ear begins
laying over while it rises. At mountain −30°, those two valleys are already
at +97.585148°. The [angle derivation](../../docs/notes/rabbit-ear-motion.md)
explains this relation and provides independent corner positions.

This uses the existing FOLD fixture and explicit angle-list format. All eight
panels are named, and three order requirements keep the moving panels above
the fixed central panel. Their order relative to each other along +z changes
during the turn, so the final stack cannot be imposed throughout. At exactly
180°, the partial requirements leave three contacts unresolved; `RabbitEarSpec`
checks the complete endpoint order against the unique flat stacking separately.
The viewer stops at mountain −175° with room to inspect the layers.

`RabbitEarSpec` checks the eight angle lists, random angles and refinements,
shared vertices, measured crease magnitudes, independent tip and shoulder
positions, and the stationary half. All 28 panel pairs pass in a half-degree
sweep short of closure, including both upright-panel configurations. The
closed endpoint passes with its complete order. Tests reject independently
changing a crease and uniformly scaling the final angles. These sampled
states do not certify continuous collision freedom or finite thickness.
The second rabbit ear and intermediate bird petal folds remain future work.

## Fish and bird endpoints

The complete fish and bird bases have
[crease patterns and verified closed endpoints](../../examples/README.md#fish-and-bird-bases-opening-and-reshaping-flaps),
with SVG previews and layer inspection views. `FlapPatternSpec` checks material
lengths, shared vertices, achieved crease magnitudes, contact and flat layer
orders. The gallery currently moves only the first rabbit ear of the fish;
the complete bases still have endpoint previews only. See
[the endpoint note](../../docs/notes/fish-and-bird-endpoints.md) for why the bird
needs two additional hinges beyond our old CP fixture.

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
