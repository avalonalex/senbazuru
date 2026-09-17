# One sheet, several folds

An executable geometric study for #114: a unit square folded once, then in half
again at right angles. It compares sharp creases, exaggerated rounded bends,
and a length/contact correction of the sharp examples. The original double folds are
**prescribed shapes with measured distortion**. The corrected double fold
meets its length and packet-order tolerances. It still does not solve paper
bending stiffness, crease angles or finite thickness. The separate
[bending experiment](#crease-preferences-and-panel-bending) now adds the first two
as energy preferences; it does not replace the original controls.

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

## Crease preferences and panel bending

For the library's separate fixed-crease operation, see
[One checked flap](../../docs/usage.md#checked-flap-motion):
`stack run senbazuru-material-study -- --flap build/fold-material` writes
`flap.html`, SVG steps, FOLD states, GLBs and interval-check reports. It checks
angle-defined motion; the numerical bending corrections below serve a
different purpose.

`stack run senbazuru-material-study -- --petal build/fold-material` checks the
square-base collapse, both bird petals and their final pressing. It writes `petal.html`
and `checked-petal/` with twenty-three SVG/FOLD/glTF states and SVG views from above
and below, sharing the checked-flap
viewer's Three.js installation. Exact signs check the ideal motion continuously;
each illustrated pose is independently rebuilt from angles. See
[usage](../../docs/usage.md#continuously-checked-bird-base) and
[the two-petal derivation](../../docs/notes/checked-bird-base.md). The
[initial collapse](../../docs/notes/checked-square-collapse.md) has the same
continuous check and a verified join to the first petal.

`stack run senbazuru-material-study -- --blintz build/fold-material` composes
four complete corner folds and a reopening into the [blintz sequence](../../docs/usage.md#checked-blintz-sequence).
It writes `blintz.html` and `checked-blintz/`, sharing the checked-flap viewer's
local Three.js installation.

`stack run senbazuru-material-study -- --crane build/fold-material` lowers
one wing of the existing crane fixture through a checked 90-degree turn.
It writes four SVG/FOLD/GLB states and contact measurements to `checked-crane/`,
plus `crane.html`. See [the crane instructions](../../docs/usage.md#checked-crane-wing-movement)
for the supported contact and remaining limits.

`stack run senbazuru-material-study -- --crane-spreading build/fold-material`
spreads the existing crane wing with the body fixed. `crane-spreading.html`
compares the rigid baseline, a curved 50-degree grip at two refinements and
an incompatible upper grip. Complete material FOLDs and measurements are
retained for every control; only accepted endpoints get SVG/GLB views. See
[the instructions](../../docs/usage.md#spreading-one-connected-crane-wing) and
[the study note](../../docs/notes/spreading-connected-wing.md). These static
shapes do not certify the flexible path between them.

`stack run senbazuru-material-study -- --band-refinement-8 build/fold-material`
writes `band-refinement-8.html`: matched, band and band contact-off controls
on `2×1`, `4×1` and `8×1`, under the same stronger length/contact policy.
Twenty-seven complete states compare successive length doublings with width,
physical controls and acceptance caps fixed. Failed endpoints remain
diagnostics. The expensive comparison is opt-in; see
[usage](../../docs/usage.md#one-more-band-length-doubling) and
[the study](../../docs/notes/band-refinement-8.md).

`stack run senbazuru-material-study -- --combined-band-refinement build/fold-material`
writes `combined-band-refinement.html`: all six meshes and five band-study
controls under the same six-stage length schedule through `1e10` and
progressive contact exchange. Earlier commands retain their policies.
Ninety exported states retain independent checks, solver histories, gap maps,
matching positions and passive/control energies. Crossing controls remain
diagnostics. The expensive solves are opt-in; see
[usage](../../docs/usage.md#refining-the-band-with-one-common-solver-policy)
and [the study](../../docs/notes/combined-band-refinement.md).

`stack run senbazuru-material-study -- --band-contact build/fold-material`
writes `band-contact.html`: the two failed middle band meshes, their saved
inner equations, and single/progressive contact-exchange comparisons with
unchanged loading and acceptance limits. All five controls retain complete
exports and replay diagnostics. See
[usage](../../docs/usage.md#replaying-the-failed-band-contact-steps) and
[the study](../../docs/notes/several-contact-exchanges.md).

`stack run senbazuru-material-study -- --band-length build/fold-material`
writes `band-length.html`: fine `4×1` / `4×2` matched and band contact-off
controls with schedules through `1e9` or `1e10`. It also restarts each original
failed contact-off endpoint at the same and stronger weights, retaining
per-edge lengths, coordinates and step histories. Crossing remains a failure
even when the numerical solve converges. This comparison is opt-in; see
[usage](../../docs/usage.md#enforcing-lengths-in-the-fine-band-controls) and
[the study](../../docs/notes/fine-band-length-enforcement.md).


`stack run senbazuru-material-study -- --band-refinement build/fold-material`
writes `band-refinement.html`, comparing the original line loads with a
preference spread across a fixed material band. Total preferred turn and
flat-paper control energy stay fixed under refinement. Five controls on six
meshes retain all diagnostic states; the solver and acceptance limits are
unchanged. See [usage](../../docs/usage.md#distributed-bending-over-a-material-band)
and [the study](../../docs/notes/distributed-bend-preference.md).

`stack run senbazuru-material-study -- --combined-refinement build/fold-material`
writes `combined-refinement.html`: the original five length/width meshes plus
`4×2`, each with the same extra length stage and contact exchange. It retains the
matched and contact-off controls, exact endpoint checks and fixed-grid gap
maps, with identical holds, control strength and acceptance limits. This
comparison remains opt-in. The diagnostics separate passive/control energies
and show achieved turns at the three imposed lines. See [usage](../../docs/usage.md#refinement-with-one-combined-solver-policy)
and [the measurements](../../docs/notes/two-direction-crease-refinement.md).

`stack run senbazuru-material-study -- --fine-crease build/fold-material`
writes `fine-crease.html`: the same fine mesh under the original policy, an
extra length stage, a near-parallel contact exchange, and both together.
Recorded equations replay the failed inner step independently of the route.
This opt-in comparison preserves the earlier defaults and all acceptance caps.
See [usage](../../docs/usage.md#isolating-fine-mesh-solver-failures) and
[the finding](../../docs/notes/fine-crease-solver.md).

`stack run senbazuru-material-study -- --unequal-refinement build/fold-material`
writes `unequal-refinement.html`: five independently refined length/width
meshes with matched, upper-preference and contact-off controls. A fixed-grid
separation map complements exact maximum gaps and matching material points.
Unconverged endpoints remain diagnostics. This opt-in study is not included
in the all-gallery command. See [usage](../../docs/usage.md#refining-the-unequal-panels)
and [the finding](../../docs/notes/unequal-crease-refinement.md).

`stack run senbazuru-material-study -- --unequal-crease build/fold-material`
writes `unequal-crease.html`: an upper grip or bend preference differs from
its partner, with a held strip beside the crease keeping it closed. Side
drawings, magnified exact gaps and matching-material comparisons distinguish
separation from contact changing the other panel. Contact-off and impossible
holds remain explicit diagnostics. See
[usage](../../docs/usage.md#giving-crease-panels-unequal-controls) and
[the finding](../../docs/notes/unequal-crease-controls.md).

`stack run senbazuru-material-study -- --coupled-crease build/fold-material`
writes `coupled-crease.html`: both interiors bend while the shared crease and
outer strips stay held. Touching and two penetrating starts pass at two
resolutions; incompatible held rows are refused. The old fixed-lower solver
remains a baseline. Shared-scale displacement plots, complete FOLDs/GLBs and
per-step measurements show both panels moving and the remaining refinement
difference. See [usage](../../docs/usage.md#bending-both-crease-panels) and
[the two-panel finding](../../docs/notes/coupled-crease-contact.md).

`stack run senbazuru-material-study -- --crease-inequality build/fold-material`
writes `crease-inequality.html`: the same two-resolution controls compare the
penalty baseline with explicit nonnegative gaps. Six constrained endpoints
pass lengths, angles, holds and contact with exact lower/upper order. Initial
repairs remain separate from endpoints; incompatible holds are refused.
Complete FOLDs/GLBs and per-step diagnostics retain the evidence. See
[usage](../../docs/usage.md#requiring-nonnegative-crease-contact) and
[the constraint finding](../../docs/notes/nonnegative-crease-contact.md).

`stack run senbazuru-material-study -- --crease-correction build/fold-material`
writes `crease-correction.html`: five contact-correction controls at two
resolutions, before/after negative-gap plots, exact gap measurements and
complete-sheet diagnostic FOLDs/GLBs. The lower panel stays fixed; the upper
can warp across its width. Numerical passes still have negative exact gaps.
See [usage](../../docs/usage.md#contact-correction-beside-a-crease) and
[the finite-penalty finding](../../docs/notes/contact-correction-at-a-crease.md).

`stack run senbazuru-material-study -- --closed-crease build/fold-material`
writes `closed-crease.html`, seven prescribed contact controls at two mesh
resolutions, exact side profiles, gap plots and diagnostic FOLDs. The ordinary
touching/opening controls have 3D views; microscopic gaps remain in the
measurements because display packing would round them away. This is an
independent geometry reference, not a relaxation or motion experiment.
See [usage](../../docs/usage.md#one-nearly-closed-crease) for rechecking saved
crane endpoints without repeating their solves, and [the finding](../../docs/notes/near-closed-crease.md).

`stack run senbazuru-material-study -- --crane-internal build/fold-material`
locates creases 26/51 and compares shared-line holds with internal-only contact
forces. Every endpoint keeps the independent whole-sheet checks. A continuation
separates reaching the iteration limit from exhausting the line search.
These slow controls stay outside CI; see [usage](../../docs/usage.md#internal-body-crease-diagnosis)
and [findings](../../docs/notes/internal-crease-diagnostic.md).

`stack run senbazuru-material-study -- --crane-body build/fold-material`
compares original, weaker and opened preferences at two body creases while
retaining the same small free patch and tip grip. `crane-body.html` reports
both angle policies, signed crease measurements and unchanged length/contact
requirements. Released-body controls can take several minutes each.

`stack run senbazuru-material-study -- --crane-pocket build/fold-material`
writes `crane-pocket.html`: an original-sheet region map, folded x-ray
highlights, material-interface and candidate-crease tables, and the unchanged
crane FOLD/GLB. This identifies candidate body and attachment regions, not a
closed cavity or an opening motion. See [the map note](../../docs/notes/crane-pocket-map.md).

`stack run senbazuru-material-study -- --crane-root build/fold-material`
compares the root-strip hold, released and weakened root springs, a flat-angle
preference and a small free body region. `crane-root.html` includes side profiles,
accepted 3D shapes and a refinement comparison; failed attempts keep diagnostic
FOLDs and measured failures. Both sides of the root share their inserted material
vertices. See [the instructions](../../docs/usage.md#wing-root-holds-and-material-preferences)
and [the study note](../../docs/notes/wing-root-holds.md).

`stack run senbazuru-material-study -- --wing-layers build/fold-material`
adds two touching layers joined along the root crease of one folded diamond.
`wing-layers.html` compares exact-grip bends, correction of an initially
penetrating guess and a lifted upper grip. The 40-degree bend now converges at
three mesh resolutions, with position and energy comparisons; incompatible
grips remain a diagnostic. See [the instructions](../../docs/usage.md#two-held-touching-layers)
and [the coupled-solve measurements](../../docs/notes/coupled-touching-layer-solve.md).
The generated SVG, FOLD and glTF use the same positions; this is static contact,
not a checked flexible motion or finite-thickness mechanics.

`stack run senbazuru-material-study -- --wing-bending build/fold-material`
solves a separate uncreased wing-shaped sheet held at its root and tip.
`wing-bending.html` compares three grip placements at three resolutions, with
a known bent-strip benchmark and independent endpoint measurements. SVG, FOLD
and glTF share the solved triangles; the 3D viewer uses the same local Three.js
installation as the checked-flap pages. See [the instructions](../../docs/usage.md#controlled-wing-bending)
and [the measurements](../../docs/notes/held-wing-bending.md). These static
shapes do not certify a flexible folding motion or realistic crane spreading.

`stack run senbazuru-material-study -- --helmet build/fold-material` checks
three turns to the [helmet base](../../docs/usage.md#checked-helmet-sequence),
including paired creases on touching layers. It writes seven SVG/FOLD/glTF
states in `checked-helmet/` and the illustrated page `helmet.html`.

```bash
stack run senbazuru-material-study -- --bending build/fold-material
```

Open `build/fold-material/bending.html`, or
[the served page](http://127.0.0.1:8000/bending.html) with the server above.
It compares shapes from a shared camera 45° above the side. Choose the single fold, either double-fold stiffness,
diagonal/kite examples, opposing flaps with authored or discovered contact,
or the curled-panel controls with authored or discovered local contact.
The contact comparisons show unconstrained and corrected endpoints from the same
starting pose. **Opposing flaps · first contact** also has a **Folding state**
selector for its angle-defined approach, at the same camera and scale.
The page works offline; `bending.json` contains the indexed meshes, original
material coordinates, signed achieved/rest angles and numerical measurements.

The single fold's preferred angle is 150°, with panels that prefer to stay flat.
Both double folds prefer 170° at each crease; their panel stiffnesses are 0.2
and 5, with crease stiffness 1. These are illustrative values. A rest angle is
what an angular spring prefers, not a hard constraint: the double fold balances
missing that angle against bending inside its connected panels.

The original three packet examples meet their length and packet-order
tolerances. A separate small-movement test establishes numerical convergence.
The penalty weights tighten in four stages, with at most 100 iterations per
stage; earlier states are numerical attempts, not physical motion.

The diagonal starts at 60° and settles at 120°. The kite flaps start at 75° and
110°, then settle at their separate 150° and 165° preferences. These examples
use actual source crease ids carried through shared refinement, with explicit
rest angles independent of the starting pose. Their triangles retain source
panel ids; mesh diagonals are panel bends, not new creases. The JSON includes
source crease ids, signed controls/achieved angles, feature edges and declared
layer requirements. The viewer draws those edges without guessing coordinates.

The diagonal and kite solves have no contact forces. Independent diagnostics
inspect every triangle pair in each saved state, including within a panel, and check the
declared source-panel orders. Both final endpoints pass; this neither repairs
a failed contact nor certifies collision-free motion between saved states.
The opposing-flap control now adds correction for supplied source-panel orders
along a fixed material direction. Both creases prefer 150°, which would make
the flaps cross. Starting at 145° / 105°, the correction settles near 160° / 139°
with no endpoint crossings and maximum relative edge error below `9e-8`.
A `1e-6` numerical clearance applies between unjoined panels; shared creases
keep zero clearance. This is not physical thickness. Its independent check
still examines every triangle pair. See the
[contact note](../../docs/notes/ordered-flap-contact.md) for measurements and
why a different starting order can stall the solve.
**Opposing flaps · discovered contact** starts at 145° / 125°, where geometry
can establish the three panel relationships without an authored pair list.
The viewer reports 46 reference triangle overlaps and 78 at the corrected
endpoint. Learned orders stay fixed; a new overlap must have an order already
implied by the reference. Ambiguous or crossed references are errors. The
correction matches explicit orders on that same pose and passes all endpoint
checks. See the [discovery note](../../docs/notes/reference-contact-discovery.md).

**Opposing flaps · first contact** starts at 145° / 105° with two known orders:
the middle panel below both flaps. Closing the right crease through 110°, 115°,
120° and 121° establishes the left flap below the right at the first sampled
projected overlap. Each accepted pose preserves prior orders and passes an
independent triangle check. The JSON includes the observation history; the
solver then uses its final relationships without changing them. Re-contact on
the opposite side is refused. See the [history note](../../docs/notes/first-contact-history.md).

Each of those four approach rotations now also passes a check over its entire
angular interval before the endpoint is accepted. **Rejected route · full turn**
shows why that matters: a full turn has a valid endpoint but crosses the other
flap during its motion. The viewer shows an interior witness 45° into the turn,
not the first impact time. Collision and unresolved results leave history
unchanged. This check covers one specified rigid hinge rotation of at most
360°; see the [sweep note](../../docs/notes/hinge-sweep-contact.md) for its
separation bounds, shared-hinge handling and numerical limits.

**Curled panel · self-contact** keeps one source panel while allowing its
returning end to contact its starting end. Eight spans form a connected strip
with no material creases. Passive panel springs prefer flatness; separate bend
controls prefer 60° with four times the passive stiffness. Without contact,
their combined preference is 48° and the strip crosses itself. Four supplied
local triangle requirements correct that contact without renaming panels or
moving their display layers. The endpoint passes all 120 triangle pairs and
has maximum relative edge error below `1e-7`. The JSON includes local triangle
orders and their smallest separation residual. See the
[local contact note](../../docs/notes/local-panel-contact.md) for the control,
finer-mesh comparison and numerical scope.

**Curled panel · discovered contact** replaces the pair list with a scan of a
separated 44.5° reference curl. The search distance is `0.03` along model
direction `(-3, 0, 1)`, while numerical clearance remains `1e-6`. Flat reference
patches share their discovered partners, keeping an order as contact slides
across triangle diagonals. The JSON records both detected overlaps and expanded
triangle orders. See [local discovery](../../docs/notes/local-contact-discovery.md).

**Curled panel · growing contact history** compares the fixed reference with a
history that learns new separated encounters during correction. The sixteen-span
strip grows from four to ten relationships and settles; the fixed reference
stalls. **Contact history** selects the reference, learning pose or endpoint.
The JSON records each accepted encounter's iteration, new orders, measured gap
ranges and unchanged material mesh. Earlier checkpoints carry only the orders
known at their iteration. See the [history note](../../docs/notes/growing-local-contact-history.md).

**Contact between numerical poses** starts with four **Correction case** views:
the safe endpoints of a diagonal-fold shortcut, its interior collision witness,
the closing strip with strict motion checks, and a safe opening control. The
new solver mode checks whole straight correction paths before accepting a pose
or learning contact. Exact separation bounds also cover shared neighbors and
triangle collapse; exhausted checks refuse the trial. The opening settles. The
closing control reports its measured outcome; it stalls with material error on
the recorded macOS run but can settle on another numerical platform. Its
JSON includes every accepted correction's endpoints and interval report.
See [checking numerical corrections](../../docs/notes/checking-numerical-corrections.md).
The rejection table separates energy, contact-history, invalid-trial and motion
failures. JSON retains counts and the first/last witness per category, including
positions, known orders and numerical settings. A fully refused line search
ends that penalty stage without claiming convergence. On the recorded Mac this
removes repeated work, with the same closing endpoint; it does not solve the
abrupt layer-penalty change when projected triangles begin overlapping. See
[rejected bending trials](../../docs/notes/rejected-bending-trials.md).

Two further views, **Distance barrier · closing** and **Distance barrier · opening**,
use distance to violating a retained triangle order. This supplies a force
before projected overlap appears, while keeping the same accepted-path check.
The closing comparison puts the old strict solver on the left and the new
energy on the right. Both new controls settle in the recorded run; the closing
strip has relative material-edge error `1.18e-8`, no failed endpoint triangle
checks and 99 accepted, checked paths. The activation range is `0.001` model
units beyond clearance, not physical thickness. JSON identifies the energy and
range so rejected-trial energies can be replayed. This still requires separated
encounters and retained directional orders; see
[the distance formulation](../../docs/notes/directional-contact-distance.md).

Physical thickness, paper calibration, automatic approach selection and general
continuous collision checking remain open. Raw sampled observations and the
original numerical modes still have no motion check. The new mode checks its
specified numerical paths; it does not preserve lengths throughout them. See the [energy note](../../docs/notes/crease-and-panel-energy.md) and
[crease identity note](../../docs/notes/crease-identity-through-refinement.md).

## Folding states

All eight examples have a **Folding state** selector. Single and double folds
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
- optional `fixedPanel: [u, v]`, a point strictly inside the material panel
  to hold still instead of the largest panel;
- optional `contact` requirements, with named panels, an ordering direction,
  and pairs written `[lower, upper]`.

Positive angles lift a flap towards the front of the original sheet; see the
[glossary](../../docs/glossary.md) for mountain and valley. The angle states
explicitly override the source's angles. In particular, the blintz fixture's
negative angles face the existing SVG camera, whereas this gallery uses positive
angles to open its flaps upwards. The source file is unchanged.

`StudyCase.buildPose` calls the production rigid folding code and builds an
`Origami.Surface` from its returned cut pattern and folded frame. The shared
library representation owns material coordinates, current positions and crease
identities; its `refineSurface` subdivides the convex panels three times.
The study holds the largest panel still; `buildCasePose` can instead hold the panel selected by
`fixedPanel` still. Material indices are shared across creases; lighting normals
are split by panel. Boundaries and actual creases get lines, triangle subdivisions
do not. A source guide also gets a line when the current state bends it. Adding another case of this kind needs a FOLD file and a manifest entry,
with no new shape formula or viewer branch.

The shared `Surface V2` is available as `poseSurface`; `poseFrame` and the
viewer's order pairs are derived from it. Named contact requirements still go
through the study's checker, then their resolved material panel ids are stored
on the surface. Its optional physical thickness is data only: it neither changes
these zero-thickness contact tests nor becomes a viewer depth adjustment.

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

`StudyCase.buildCasePose` runs `Origami.Contact` on the original rigid polygons,
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

## Two rabbit ears form the fish base

Choose **Fish base** to gather the south-east corner into the first rabbit ear,
then the north-west corner into the second. A rabbit ear gathers a triangular
region into a pointed flap. Fifteen states cover the unfolded sheet followed
by mountain magnitudes 15°, 30°, 60°, 90°, 120°, 150° and 175° for each ear.
The second half stays flat during the first stage. During the second stage,
the first ear holds its 175° inspection state. Each ear links four crease angles.
Two valleys fold further than the other valley and mountain, so the ear begins
laying over while it rises. At mountain −30°, those two valleys are already
at +97.585148°. The [angle derivation](../../docs/notes/rabbit-ear-motion.md)
explains this relation and provides independent corner positions.

This uses the existing FOLD fixture and explicit angle-list format. All eight
panels are named, and six order requirements keep each ear's moving panels above
its fixed central panel. Within each ear the order along +z changes during the
turn, so the final stack cannot be imposed throughout. The ears stay on opposite
sides of the diagonal and need no order between them. With both ears at exactly
180°, the partial requirements leave six contacts unresolved; `RabbitEarSpec`
checks the complete endpoint order against the unique flat stacking separately.
The viewer stops with both mountains at −175° to leave room to inspect the layers.
The case retains its original `rabbit-ear` id and export prefix.

`RabbitEarSpec` checks all fifteen angle lists, random angles and refinements,
shared vertices, measured crease magnitudes, independent tip and shoulder
positions, and that the first ear stays fixed during the second stage.
All 28 panel pairs pass in a half-degree sweep of each stage, including both
upright-panel configurations. Random pairs of independently chosen ear angles
also check that each stays on its own side of the diagonal's vertical plane.
The closed fish endpoint passes with its complete order and matches the source
fixture's angles and landmarks. Tests reject changing either ear's crease
independently, uniformly scaling the final angles, and folding towards the wrong
side. See [the two-ear construction](../../docs/notes/two-rabbit-ears.md).
These checks do not certify continuous self-collision freedom within an ear
or finite thickness. The first bird petal is described below.

## Fish and bird endpoints

The complete fish and bird bases have
[crease patterns and verified closed endpoints](../../examples/README.md#fish-and-bird-bases-opening-and-reshaping-flaps),
with SVG previews and layer inspection views. `FlapPatternSpec` checks material
lengths, shared vertices, achieved crease magnitudes, contact and flat layer
orders. The fish has both rabbit-ear stages in the gallery; the bird has the
two-petal sequence below as well as its complete endpoint preview. See
[the endpoint note](../../docs/notes/fish-and-bird-endpoints.md) for why the bird
needs two additional hinges beyond our old CP fixture.

## Two petals form the bird base

Select **Bird base**. Sixteen states start with the collapsed square base, fold
the first petal, fold the second underneath the packet, then press both flat.
The first eight states lift the south-east corner. In the next seven, the
north-west corner forms the second petal while the first hinge stays at 175°.
Drag to look underneath during this second stage. The final **Completed bird
base · press both petals flat** state brings both hinges to 180°; it matches
the source bird-base endpoint exactly.

Each petal changes seven crease angles together: four side creases close as
two old square-base folds open towards zero. The same signed angles send the
two petals to opposite sides of the stationary base plane. This case uses
`fixedPanel: [0.58, 0.4]` to hold that base still. See the
[first-petal derivation](../../docs/notes/petal-fold-motion.md) and the
[two-petal construction](../../docs/notes/two-petals.md).

`PetalFoldSpec` checks independent landmarks, stationary first-petal and body
material during the second stage, shared vertices, achieved crease magnitudes,
material lengths and area, and all 120 panel pairs in half-degree sweeps and
at random states. The declared orders agree with the square, one-petal and
complete bird endpoints' unique stackings. The viewer uses those checked
orders to break depth ties between touching faces and their feature lines,
reversing the adjustment when viewed from underneath. Contact failures and the
original-sheet view disable the adjustment. Exported geometry stays unchanged.
These sampled checks do not certify motion between states or finite paper
thickness. The separate `petal.html` route now checks both petals and final
pressing continuously; see [its certificate](../../docs/notes/checked-bird-base.md).

The **SVG folding sequence** link opens `bird-sequence.html`, with side views
at 45° above and below the paper, rendered through the main `Render.Steps`
pipeline. The above view is the default: looking across the petal shows its
lift apart from the paper beneath it. Expand the below view to follow the
second petal. The isometric and directly-underneath projections remain linked
for comparison. Each page uses one camera and scale for all sixteen states.
The ordinary FOLD sequence
keeps thirteen material vertices and sixteen panels per state. The other
per-state FOLD downloads remain subdivided surface inspection meshes.
To regenerate just the SVG handoff without the packet solver, run:

```bash
stack run senbazuru-material-study -- --bird-svg build/fold-material
stack run -- render examples/bird-base-sequence.fold --steps --columns 4 --view iso --width 1000 --height 1000 -o bird-steps.svg
```

The [visibility note](../../docs/notes/projected-panel-visibility.md) records
the distinction between material layer order and viewing order, and the
current limits of projecting open panels to SVG.

## Six additional base endpoints

The **Six more bases** link opens `basic-bases.html`: helmet, organ, frog,
boat, pig and diamond crease patterns beside their closed forms. Switch
front/reverse views to expose the flaps; the optional layer spread is only
a drawing aid. FOLD downloads retain shared material vertices and explicit
layer orders. These examples establish endpoints before attempting their
folding motions.

```bash
stack run senbazuru-material-study -- --basic-bases build/fold-material
stack test --ta='--match "six basic-base"'
```

Open `basic-bases.html` from the same local server as the main viewer.
The fast command generates the six constructions, their front/reverse SVGs,
layer-spread SVGs, crease and folded FOLD files, and
`basic-base-measurements.json`. It also runs during normal gallery generation.
`BasicBaseSpec` compares the constructions with the committed examples, then
checks all material landmarks, shared vertices, lengths and area at three
refinements, achieved crease magnitudes, one complete stacking per base,
all 638 panel contact pairs and visible coverage from three cameras.
The [construction note](../../docs/notes/six-more-base-endpoints.md) explains
why identical outlines do not imply identical folds. Frog is the largest of
these cases, with 32 panels and 14 active creases at its centre.

The frog card's **Folding instructions** link opens `frog-instructions.html`,
in the bird sequence's style: a numbered SVG page viewed from 45° above,
an expandable reverse view and written instructions keyed to its five figures.
The square base, one/four squash folds and one/four petal folds each keep the
closed point above the loose corners. The whole packet is rigidly oriented
before `Render.Steps` uses one camera and scale. A straight-on SVG is linked
for comparison. Their individual FOLD exports, `frog-base-sequence.fold`,
three `frog-sequence-*.svg` pages and `frog-guide-measurements.json` are
generated by the same fast command. Fifteen additional tests check the intended
midpoint movements, material preservation and all 879 checkpoint panel pairs;
an export regression verifies the rigid turns, retained orders and production
SVG output against a reviewed golden page. The
written instructions describe hand movements; these five flat models do not
simulate or certify the motion between them. The guide exposed a fixture error
that material checks alone missed: the small petals were tucked into the
packet. Their corrected crease directions lift them outward, and a regression
now requires visible edges at the raised tip on both opened working faces.

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
