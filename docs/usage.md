# Using senbazuru

Building it, running it, and every option the four commands take. For what the
commands are *for*, start at the [README](../README.md); for the format they
read, [fold-primer.md](fold-primer.md).

## Building

Requires [Stack](https://docs.haskellstack.org/). The project pins Stackage
`lts-22.44` (GHC 9.6.7).

```bash
stack build
stack test
make check      # formatting, lint and tests: everything CI should run
```

`stack.yaml` sets `system-ghc: true`, so Stack reuses a GHC 9.6.7 already on
your `PATH` rather than downloading its own. If you would rather Stack managed
the compiler, delete that line.

## Running it

```
senbazuru render FILE [-o OUT.svg] [OPTIONS]
senbazuru export FILE [-o OUT.glb] [OPTIONS]
senbazuru check  FILE [--frame N] [--tolerance DEG]
senbazuru info   FILE [--fold] [--layer-budget N]
senbazuru crease FILE --from X,Y --to X,Y (--mountain|--valley|--flat|--unassigned)
                      [--folded] [--frame N] [-o OUT.fold]
senbazuru fold   FILE [--frame N] [--stacking N[,N...]] [--layer-budget N] [-o OUT.fold]
```

Working from source, reach the executable in any of three ways:

```bash
stack run -- render FILE.fold              # everything after -- goes to senbazuru
stack exec -- senbazuru render FILE.fold   # after a stack build
make install                               # puts senbazuru on your PATH
```

The bare `--` matters. Without it, Stack reads `--view` and the rest as options
of its own and complains about them.

## The files it reads

Every command takes any of three formats, chosen by the file's extension:

| Extension | What it is |
| --- | --- |
| `.fold` | [FOLD](https://github.com/edemaine/FOLD), and anything with an extension senbazuru does not recognise |
| `.cp` | The crease patterns Orihime and [Oriedita](https://github.com/oriedita/oriedita) write: one crease to a line of text |
| `.opx` | The crease patterns [ORIPA](https://github.com/oripa/oripa) writes: the same, in XML |

```bash
stack run -- render examples/bird-base.cp -o bird-base.svg
stack run -- check  examples/bird-base.cp
```

The last two are crease patterns and nothing else. Neither format can store a
face, a fold angle or a second frame — but the first two of those are not
losses senbazuru has to live with. The faces are determined by the creases and
are traced from them, and a fold angle follows from a mountain or a valley, so
`--fold` and `export` work on a `.cp` as they do on a `.fold`:

```bash
stack run -- render examples/bird-base.cp --fold -o bird-base-folded.svg
```

What a single frame really cannot give you is a *sequence*: `--arrows` and
`--steps` succeed and draw the pattern, but neither adds anything to it, since
both work by comparing one frame with the next.

One thing this does not change is the flat picture. `render` on a pattern that
records no faces draws a wireframe, as it always has, and filling it is not a
matter of switching the tracing on: some drawings cannot be traced however much
is worked out — a crease that stops in the middle of the paper has no face
round it — and they still have to draw. So the fill follows the file, and
folding does not.

Both formats measure `y` downwards, as the Java editors that write them draw
it, and senbazuru turns that the right way up on the way in. That is a
correction rather than a preference — see
[notes/cp-and-opx.md](notes/cp-and-opx.md) — and it means a pattern read from a
`.cp` is upside down compared with the same `.cp` put through Oriedita's own
FOLD export.

Two things a segment list can describe that a crease pattern cannot, and that
the reader passes through as it finds them: two creases that cross with no
vertex where they meet, and the same crease listed twice.

The first is no longer a problem. `--fold` and `export` cut the creases at the
points where they meet before working out the faces, so a pattern drawn with
crossings folds like any other; `check` still reads it as drawn, so it has one
fewer vertex to look at than the picture suggests — the same under-reporting a
`.fold` file drawn that way gets. The second is refused, naming both creases:
along the stretch two creases share there are two answers to how the paper
folds, and neither is ours to pick.

Output is always FOLD, SVG or glTF. senbazuru does not write `.cp` or `.opx`,
because writing one would silently drop whatever the document held that the
format cannot say.

## `render`

| Option | Meaning |
| --- | --- |
| `-o, --output FILE` | Write to a file instead of stdout |
| `--frame N` | Which frame to render (default `0`, the key frame) |
| `--width`, `--height` | Page size in points (default `400`) |
| `--margin` | Blank border in points (default `16`) |
| `--view NAME` | Viewing angle: `top`, `bottom`, `iso`, `front`, `side`. Defaults to `top` for crease patterns and flat-folded models, `iso` for anything with relief |
| `--rotate DEG` | Turn the drawing anticlockwise on the page (default `0`). A folded model lands whichever way up its crease pattern was drawn, and nothing in the file says which way up it should be read — the traditional crane comes out upside down, so its picture in the README is drawn with `--rotate 180` |
| `--transparent` | Omit the white background rectangle |
| `--hide-flat` | Do not draw flat (`F`) or unassigned (`U`) creases |
| `--no-fill` | Draw every crease and fill nothing: a wireframe. Also the way to render a file whose layers cannot be stacked, since nothing then needs to know which is on top |
| `--fold` | Fold the crease pattern along its fold angles and draw the result |
| `--arrows` | Draw the fold that takes this frame to the next one |
| `--steps` | Lay every frame out as one numbered page of figures, at one scale |
| `--columns N` | Figures across the page, with `--steps` (default `3`) |
| `--stacking N[,N...]` | Which layer order to draw, when a model has several: one index per component that has a choice, in the order `info --fold` lists them (default: the first of each) |
| `--layer-budget N` | How many guesses the layer solver may make in one component before giving up (default `1000`) |
| `--offset PT` | Draw a folded model's layers this far apart on the page, so a stack that lands on one spot reads as a stack (default `0`, off). Buried sheets are drawn finer than the model, so a small step still reads |

Some combinations are refused rather than quietly resolved, because they
describe different pictures: `--steps` with `--frame`, with `--fold`, or with
`--stacking`; `--fold` with `--arrows`; and `--arrows` with `--offset`, since an
arrow is drawn at the coordinates the paper actually has and `--offset` draws
every sheet a step away from those.

`--offset` is the one flag that needs the layers rather than merely using them,
so four things are worth knowing about it.

**How big to make it.** The buried sheets are drawn at 0.35pt against the
model's 1 to 1.6, so even a step of a point or two separates them; the limit is
the page rather than the ink. A model a handful of layers deep takes 4 to 6
comfortably. A deep one — the crane is 32 layers — wants a small step and a wide
margin, and is dense whatever you choose, because it really does have 32 layers.
[tour.md](tour.md#how-many-layers-is-too-many) says what printed books do
instead.

**It never changes the size of the drawing.** The page is fitted to the paper,
and opening a stack does not shrink the model to make room, so a large step on a
model that already fills the page runs off it. The answers are a wider
`--margin`, a bigger `--width`, or a smaller step.

**It does nothing under `--no-fill`**, which is the escape hatch that asks no
questions about layers at all.

**It refuses a model whose layers run in a circle** — a twist — because stepping
them apart needs one order for the whole model and there is none. The ordinary
picture of one still draws fine.

## `export`

Writes one frame as a 3D model, in glTF's binary form (`.glb`), which opens in
Blender, three.js, and the built-in viewers on macOS and Windows. The frame is
chosen the way `render` chooses it, and none of the page options apply — a
model has no page.

| Option | Meaning |
| --- | --- |
| `-o, --output FILE` | Write to a file instead of stdout |
| `--frame N` | Which frame to export (default `0`) |
| `--fold` | Fold the crease pattern along its fold angles and export the result |
| `--stacking N[,N...]` | Which layer order to use, as for `render` |
| `--layer-budget N` | As for `render` |
| `--all-layers` | Export only the complete sheet for inspection; touching layers may flicker |

The default GLB has two selectable scenes. **Visible paper** removes buried
coplanar regions (overlapping paper in the same plane), on both sides, so a
standard viewer can show the exposed paper without depth ties. **Complete
paper** retains every panel. Neither scene moves a layer or opens a gap at a
crease. Both use the same two paper colours as SVG. Viewers that show only the
default scene open Visible paper; use `--all-layers` to open the complete sheet
in such a viewer.

The visible scene uses supplied `faceOrders`, or the existing layer solver for
a whole flat-folded model. An open model with ambiguous coplanar overlaps needs
explicit orders; `--all-layers` remains available for inspection. Cyclic
interleavings such as the pinwheel are supported. Invalid face references and
contradictory pair orders are still errors. Panels must be convex; the visible
scene also requires them to be planar. This is visibility, not a new contact or
collision certificate.

Graphics corners and triangles retain their original material vertex/panel
references in `extras`; the complete topology and supplied layer relationships
are included too. See [the export note](notes/visible-paper-mesh.md) for the
metadata layout and [the preview](../study/gltf/README.md) for a scene selector.
The old `--thickness` display-spacing option has been removed. Physical
thickness remains optional surface metadata and causes no displacement.

Wing spreading and body inflation remain future goals. The
[connected-surface plan](notes/connected-paper-surface.md) describes the
material constraints and opening controls they need.

Library callers can pass `Origami.Surface` to `surfaceDiagram` and
`renderSurfaceGlb`. A surface produced from folding retains its original-sheet
coordinates; a standalone folded file leaves missing material coordinates
unknown. Stored physical thickness is not used by either renderer as a display
offset or by the current contact checks. Shared refinement currently requires
convex planar panels with nondegenerate triangles in their first-corner fan;
it does not triangulate arbitrary concave or curved panels.

Separate pieces at a cut need distinct vertex ids. Refinement refuses a `C`
edge still shared by two panels rather than welding its new midpoints.

`surfaceFromFrame` recognises the study's `senbazuru:material_coords` extension;
`materialFrame` writes it when original-sheet coordinates are known. This map
survives an explicit material export/reload. Physical thickness and directional
requirements are not yet serialised to FOLD.

### Checked flap motion

`Origami.Flap.prepareFlap` takes a crease id, its moving incident face, signed
travel in degrees and the result of `foldFrameWith`. Use ids from that result's
`foldedPattern`, which includes any vertices/faces created by cutting crossings.
`checkFlap defaultSweepSettings` returns an opaque `CheckedFlap` only if the
whole rotation clears the interval contact check. `flapAt checked progress`
supplies a shared surface for progress from 0 to 1, derived from crease angles
with the stationary side fixed. SVG and glTF consume that same surface.

Run the reproducible driver from the repository root:

```bash
stack run senbazuru-material-study -- --flap build/fold-material
npm install --prefix build/fold-material/checked-flap --no-audit --no-fund three@0.186.0
python3 -m http.server 8000 --bind 127.0.0.1 --directory build/fold-material
```

Open [the checked flap demo](http://127.0.0.1:8000/flap.html). Its SVG/FOLD files
need no JavaScript dependencies; the 3D viewer uses the local Three.js install.
`checked-flap/` contains seven SVG/FOLD sequences, twenty-eight GLBs with both
scenes, and `checks.json` with interval counts, length errors, layer orders
and rejected full turns. The sequence folds one third of the square onto the
middle third, lifts both layers together through 90°, then lowers them. The
upper layer's free edge reaches the lifting crease exactly; its corners keep
their distinct material ids. An opposing flap blocks an
attempted full revolution of a two-layer stack. The single fold and its
reopening remain, alongside the original short 105°–121° opposing-flap route.

This supports a fixed hinge separating a rigid flap from stationary paper, with
convex planar panels. A flat touching endpoint is supported when a half-turn
or shorter approach stays on one side of a stationary plane containing the
hinge. Its `faceOrders` record that side. At a touching start, any supplied
orders must agree with departure; if absent, departure selects the unknown
order. Coplanar layers that move together, or both stay still, retain their
supplied orders throughout the motion. Each overlapping pair needs an explicit
nonzero order, and contradictory orders are refused even when the stack is
upright. Other stale orders are discarded. An unjoined edge may rest on the
hinge when its declared partner supplies the shared boundary and the turning
interior stays on one side of the stationary plane. Sliding contact,
unsupported hinge seams, turns requiring different hinge axes, and
exhausted interval work are refused.
The check uses
zero-thickness geometry normalized to sheet scale, with floating-point bounds
and numerical guards, including a `1.42e-14` allowance for rounded endpoint
coplanarity and free hinge boundaries. This does not establish exact separation
below that scale.
A contact parameter is a witness, not the first impact
time. There is no general flap CLI verb or route planning yet. See
[the operation note](notes/checked-flap-operation.md),
[the endpoint rule](notes/flat-flap-endpoints.md),
[moving touching layers](notes/moving-touching-layers.md) and
[free edges on a hinge](notes/free-edges-on-a-hinge.md).

### Checked blintz sequence

A blintz base folds the square's four corners to its centre. This recipe uses
five successive `CheckedFlap` operations: four complete folds, then reopening
the first corner. Each move inherits the accepted endpoint's angles and layer
orders. The central face is first in the recipe's material pattern, so the
folding algorithm anchors it throughout; the recipe also checks every join
for an unintended change of position. See [the handoff note](notes/chaining-checked-folds.md).

```bash
stack run senbazuru-material-study -- --blintz build/fold-material
npm install --prefix build/fold-material/checked-flap --no-audit --no-fund three@0.186.0
python3 -m http.server 8000 --bind 127.0.0.1 --directory build/fold-material
```

Open [the blintz instructions](http://127.0.0.1:8000/blintz.html). The viewer
shares the existing checked-flap Three.js installation. `checked-blintz/`
contains an eleven-figure SVG, its material FOLD sequence, eleven GLBs with
visible/complete scenes, and `checks.json` with whole-turn interval counts,
angles, layer orders and sampled length errors. The SVG has one camera and
scale. It looks from below the source fixture's xy plane, at 45°, so its
mountain folds come towards the viewer and the resting flaps remain visible.
Figure 9 completes the base; figures 10–11 reopen its first corner.

This is a recipe for the existing fixture, with explicit ids in its reordered
material pattern. It is not yet a general instruction format. The same numerical scope and refusals
as the single-flap operation apply to each complete turn.

### Checked helmet sequence

A helmet base folds a square diagonally in half, then brings both corners
of the doubled triangle to its opposite tip. Each corner turns two touching
layers together. `prepareFlapAlong` explicitly selects all crease segments
on the physical hinge; they must separate the moving faces from the fixed
ones and lie on one line in the current folded shape. The first segment
defines the signed travel. Other segments receive the angle signs required
by their stationary faces' orientation.

```bash
stack run senbazuru-material-study -- --helmet build/fold-material
npm install --prefix build/fold-material/checked-flap --no-audit --no-fund three@0.186.0
python3 -m http.server 8000 --bind 127.0.0.1 --directory build/fold-material
```

Open [the helmet instructions](http://127.0.0.1:8000/helmet.html).
`checked-helmet/` contains seven illustrated states as SVG, material FOLD and
GLBs with visible/complete scenes, plus angles, layer orders and measurements
in `checks.json`. The camera looks from the tip side at 45° above the paper.
All three turns pass the continuous hinge-sweep check and carry their accepted
poses and orders into the next move. This remains an explicit fixture recipe
with floating-point numerical guards, not automatic route planning or a
solver for creases on different axes. See [the hinge note](notes/aligned-crease-hinges.md).

### Checked crane-wing movement

The crane study adds a crease across the wing containing the original sheet's
`(0,1)` corner, then lowers its two touching layers through 90°. The crease
lies a quarter sheet-side from the wing tip. The other wing, neck, tail and
body stay fixed. The complete turn passes the continuous contact check;
turning the other way is refused by the starting layer order.
The chosen order tucks the tail between the body layers on both sides; the
fixture's default order exposes its root on one side. See
[choosing the intended stacking](notes/several-stackings.md).

```bash
stack run senbazuru-material-study -- --crane build/fold-material
npm install --prefix build/fold-material/checked-flap --no-audit --no-fund three@0.186.0
python3 -m http.server 8000 --bind 127.0.0.1 --directory build/fold-material
```

Open [the crane-wing demonstration](http://127.0.0.1:8000/crane.html).
`checked-crane/` contains four illustrations at 0°, 30°, 60° and 90°, a material
FOLD sequence, four GLBs with visible/complete scenes, and `checks.json` with
angles, orders, length errors and the rejected direction. The SVG page uses
one camera and scale. These are selected poses from a continuously checked
route, not a contact test limited to those four poses.

The hinge rests across the stationary wing's interior. The moving interior
must stay strictly on one side of that plane throughout the turn, and its
departure must agree with the initial order. No paper is displaced or joined
across the touching layers. See [the contact note](notes/a-wing-resting-on-paper.md).
This fixture recipe does not check the preceding construction of the crane,
return the wing to its flat resting surface, move the second wing or expand
the body. It is a rigid, zero-thickness movement with floating-point numerical
guards, not a flexible-paper solve. The curved wing profile and compatible
body opening are the follow-up mesh study in
[#195](https://github.com/avalonalex/senbazuru/issues/195).

### Controlled wing bending

Hold a triangular sheet's wide root and move a small grip near its tip. The
free paper settles under passive bending resistance and material-length
penalties. The grip angle controls the held region's orientation; there are
no material creases in this experiment.

```bash
stack run senbazuru-material-study -- --wing-bending build/fold-material
npm install --prefix build/fold-material/checked-flap --no-audit --no-fund three@0.186.0
python3 -m http.server 8000 --bind 127.0.0.1 --directory build/fold-material
```

Open [the controlled bending study](http://127.0.0.1:8000/wing-bending.html).
`wing-bending/` contains nine wing and three strip FOLD/GLB pairs, SVG
comparisons and `checks.json`. Select 8, 16 or 24 mesh divisions to compare
flat, 20-degree and 40-degree grip placements. Every SVG comparison has one
camera and scale. The table compares length error, exact held positions,
bending energy, convergence and independent endpoint contact. The known strip
benchmark checks the same solver against an independently constructed shape.

This is one uncreased, zero-thickness sheet with illustrative stiffness,
not the crane fixture. Subdivision edges are joins, with no added crease
strokes. There is no contact correction in these solves; the finished shapes
are checked independently. Numerical iterations can stretch paper and are not
physical motion, so the three grip states have no continuous-motion certificate.
A separate [two-layer experiment](#two-held-touching-layers) adds contact forces.
Compatible crane-body freedom and realistic spreading remain in #195. See [the experiment and refinement measurements](notes/held-wing-bending.md).

### Two held touching layers

```bash
stack run senbazuru-material-study -- --wing-layers build/fold-material
```

Use the same local server and Three.js installation as the controlled bending
page, then open [the two-layer study](http://127.0.0.1:8000/wing-layers.html).
A diamond folded in half has two distinct material layers joined only at its
root crease. Exact root and tip grips shape both layers; a declared order
permits touching and separation while penalizing penetration.

The page compares flat, 20-degree and 40-degree grips at eight divisions, an
initially penetrating guess and a lifted upper grip. Accepted shapes have
SVG/FOLD/GLB exports in `wing-layers/`. The 40-degree bend also runs at 16 and
24 divisions, with a shared-camera comparison in `refinement.svg` and material
position/energy changes in `checks.json`. Only converged shapes passing the
independent endpoint checks appear in the model selector. Each run records its
last equilibrium check when available: original-system linear residual,
threshold and full proposed movement. The incompatible grip is a bounded
diagnostic with eight iterations per penalty stage; regular controls allow
100. Unaccepted runs retain diagnostic FOLD geometry. Generation can take
several minutes.

The complete sheet and stable-view glTF scenes use the same positions and
material identities. These zero-thickness, static shapes do not establish a
physical motion, finite-thickness behavior, friction or a connected crane
body. Refinement now converges with coupled preconditioning; the measured
shape and energy still vary with mesh size. See [the resolution comparison](notes/coupled-touching-layer-solve.md).

### Spreading one connected crane wing

```bash
stack run senbazuru-material-study -- --crane-spreading build/fold-material
```

Use the same local server and Three.js installation as the wing-bending page,
then open [the connected crane study](http://127.0.0.1:8000/crane-spreading.html).
The full crane remains one sheet. Its body, other wing and tucked tail are
held exactly. The selected wing's root strip is held at 30 degrees; its tip
grip is held at either 30 degrees (rigid baseline) or 50 degrees (curved wing).
Only the middle three quarters of its length can bend.

`crane-spreading/` contains complete material FOLDs, SVG comparisons, accepted
GLBs and `checks.json`. The 50-degree grip runs at two refinements, with the
same physical held strips. The incompatible control pushes an upper grip
through its lower partner; its diagnostic FOLD is excluded from the model
selector. Regular controls allow twenty iterations per penalty stage; the
incompatible grip allows two. Generation can take several minutes.

Acceptance checks material lengths, held positions, original crease angles,
all triangle contacts and retained source orders. The coplanar seam check uses
the same `1e-7` model-unit distance margin as normal contact; a narrower seam
sliver does not invent a layer order. No material vertices are welded or
positions offset for display. The GLB has both stable-view and complete-sheet
scenes. A fixed body suffices for this modest controlled bend; this does not
establish an unheld crane's shape or a continuous flexible path. See
[the measurements and next experiment](notes/spreading-connected-wing.md).

### Wing-root holds and material preferences

```bash
stack run senbazuru-material-study -- --crane-root build/fold-material
```

Open [the wing-root study](http://127.0.0.1:8000/crane-root.html) with the same
server and Three.js installation. Its controls share the 50-degree tip grip:
hold the root strip, release it, weaken its spring, prefer a flat root, and
release the four body panels immediately across the root. Any vertex shared
with other body panels stays held. Both sides of the root are subdivided.
The flat-preference control repeats at a finer resolution.

`crane-root/` contains full material FOLDs and per-control measurements, accepted
SVG/GLB shapes, a side-profile comparison and `checks.json`. The independent
checks preserve original creases and all source orders; root spring angles are
reported separately because a preference is not an exact hold. Failed controls
remain diagnostic FOLDs outside the accepted model selector. A physically valid
mesh whose stable-view export fails keeps a complete-sheet GLB and the rendering
error; it is excluded from the stable-view selector.
[#206](https://github.com/avalonalex/senbazuru/issues/206) tracks that export
limitation on the finer root control. The SVG outline path also retains some
buried crease lines here; the stable 3D views show surface occlusion. Forty iterations
per penalty stage are allowed, or two for an intentionally crossed grip.
Body relaxation and the finer mesh can take several minutes.

A flat rest angle still leaves a crease spring at the root; it does not turn
that line into uncreased panel material. These are illustrative static solves,
not measured paper stiffness or a certified spreading route. See
[the findings and remaining limitation](notes/wing-root-holds.md).

### Crane pocket material map

The crane pocket map traces the same starting sheet before a coupled opening
solve:

```bash
stack run senbazuru-material-study -- --crane-pocket build/fold-material
```

Open [the pocket map](http://127.0.0.1:8000/crane-pocket.html) on the same server.
The page selects original-sheet regions and folded x-ray highlights, and lists
shared material interfaces separately from layer orders. `crane-pocket/map.json`
records every source edge's owners and proposed angle role. FOLD and GLB retain
the unchanged crane; no body opening, cavity volume or pressure is computed.
The core's perimeter is internal paper, not an exposed rim. See
[the map note](notes/crane-pocket-map.md).

### Selected body-crease preferences

```bash
stack run senbazuru-material-study -- --crane-body build/fold-material
```

Open [the body-angle study](http://127.0.0.1:8000/crane-body.html) on the same
server. The original, weaker-spring and 170-degree preference trials free the
same four root-neighbour panels with the same tip grip. They select only mapped
candidate creases 21 and 46. The central body core, other wing, neck and tail
stay held. Every solved mesh receives both the old strict-angle verdict and a
verdict allowing the selected angles to vary; neither changes a solved position.

`crane-body/` contains per-trial FOLDs, signed angles by source crease segment,
all independent checks and an aggregate `checks.json`. Only accepted endpoints
with a stable GLB enter the viewer; accepted complete-sheet exports remain
available when visibility fails. The fixed-body reference and incompatible
upper grip bound the comparison. Forty iterations per penalty stage are allowed
for ordinary controls; these released-body solves can take several minutes each.
The negative control allows two. See [the angle-policy note](notes/body-angle-preferences.md).

### Internal body-crease diagnosis

```bash
stack run senbazuru-material-study -- --crane-internal build/fold-material
```

Open [the internal-crease study](http://127.0.0.1:8000/crane-internal.html).
It locates shared creases 26 and 51 on the original sheet and in a folded
x-ray, then compares holding their vertices with removing surrounding contact
forces. The independent whole-sheet check retains every source layer order.
Reduced-force controls remain diagnostics even if their geometry passes.
The fixed-body reference and an eighty-iteration continuation of the original
failed endpoint complete the comparison.

These long static solves run outside the test suite. A single control can be
run as `--crane-internal CONTROL build/fold-material`, with `CONTROL` one of
`original`, `held`, `internal`, `held-internal`, `fixed`, or `continued`.
`continued` reads `crane-internal/original.fold` in the output directory;
run `original` first. It keeps the final penalty weight instead of restarting
the softer stages. `original-short` limits each stage to two iterations for
profiling; it is not an acceptance control.

Per-trial JSON records iteration limits, endpoint checks, contact rows and
energy components for the first and last rejected corrections of each kind.
The endpoint and last rejected correction are saved as diagnostic FOLDs.
The gallery keeps failed meshes out of accepted-model views. No flexible
motion certificate is implied. See [the diagnostic findings](notes/internal-crease-diagnostic.md).

### One nearly closed crease

```bash
stack run senbazuru-material-study -- --closed-crease build/fold-material
```

Open [the small crease experiment](http://127.0.0.1:8000/closed-crease.html).
Seven prescribed controls compare exact touching, opening, crossings and
reversed order on 32- and 64-triangle versions of the same connected sheet.
Side profiles use equal scales; the signed gap plot magnifies its vertical
axis explicitly. Length error, crease angles, raw force gaps and independent
contact reports accompany the exact profile reference. A microscopic crossing
passes the current tolerance check but remains labelled invalid.

The ordinary touching/opening controls have GLBs using the existing
`checked-flap/node_modules` viewer dependencies. Microscopic or invalid controls
retain diagnostic FOLDs and measurements without a misleading rounded GLB.
These shapes are not solved equilibria or certified motion.

To recheck the six retained crane diagnostics without repeating their solves:

```bash
stack run senbazuru-material-study -- --closed-crease --recheck-crane \
  build/fold-material/crane-internal build/fold-material
```

All six endpoint FOLDs must exist; missing or mismatched material is an error.
Results go to `closed-crease/crane-recheck.json`; old reports stay intact.
See [the contact finding](notes/near-closed-crease.md).

### Contact correction beside a crease

```bash
stack run senbazuru-material-study -- --crease-correction build/fold-material
```

Open [the correction comparison](http://127.0.0.1:8000/crease-correction.html).
Five controls at 32 and 64 triangles hold the lower panel and the outer upper
strip while the remaining upper paper settles. Compare contact on/off,
touching and penetrating guesses, and an impossible hold. The corrected
upper need not keep identical cross sections across its width: an exact
triangle-based gap reference checks all of it against the fixed lower panel.

Before/after negative-gap plots enlarge their vertical scales independently.
Convergence, lengths, holds, crease angles and numerical contact acceptance
remain separate from the exact order result. All ten endpoints retain a
negative gap, including the six passing all numerical checks. They are
static diagnostics, not certified folded shapes or a checked motion.

The `crease-correction/` directory holds complete-sheet diagnostic FOLDs and
GLBs, plus exact fractions and bounded solver reports in `checks.json`.
The 3D iframe reuses `checked-flap/node_modules`; GLB coordinate rounding
cannot preserve the microscopic residuals. Use FOLD and measurements for
those. See [the finding](notes/contact-correction-at-a-crease.md).

### Requiring nonnegative crease contact

```bash
stack run senbazuru-material-study -- --crease-inequality build/fold-material
```

Open [the constraint comparison](http://127.0.0.1:8000/crease-inequality.html).
It reruns the same two-resolution penalty controls and constrains the three
compatible starts. All six constrained endpoints have nonnegative exact
lower/upper gaps while passing the original length, angle, hold and whole-sheet
contact checks. Incompatible holds are refused; contact-off stays a baseline.

Select a starting condition and resolution to compare measurements and
negative-gap plots. The initial feasibility repair is a separate numerical
guess, not a folding step. The `crease-inequality/` directory retains original,
penalty, repaired-start and constrained FOLDs/GLBs for successful runs, plus
`checks.json` with exact gaps, repairs and constrained-step diagnostics. Failed
holds have only original and penalty exports. The 3D iframe reuses
`checked-flap/node_modules`; GLB rounding cannot verify the microscopic gaps.

This requires the whole lower panel to stay fixed and a known layer order.
Exact clipping is shared by the constraints and repair; prescribed-profile
tests and the separate whole-sheet check provide additional verification.
No continuous physical motion is checked. See [the finding](notes/nonnegative-crease-contact.md).

### Bending both crease panels

```bash
stack run senbazuru-material-study -- --coupled-crease build/fold-material
```

Open [both panels bending](http://127.0.0.1:8000/coupled-crease.html). Only the
shared crease and both outer strips stay held. Select touching, ordinary or
tiny penetrating starts, an incompatible pair of held rows, or the unchanged
fixed-lower baseline. Each runs at 32 and 64 triangles.

Successful runs offer original, repaired-start and settled shapes; refusals
retain only their original guess. Lower and upper displacement plots share
one magnified scale across all stages of a run, measured from the unperturbed
bent reference. The repair amount is per side, upward on the upper panel and
downward on the lower. It is a numerical correction, not a folding step.

The `coupled-crease/` directory contains 26 complete material FOLDs, 26 GLBs,
52 movement SVGs and `checks.json` with per-step diagnostics and refinement
measurements. The 3D iframe reuses `checked-flap/node_modules`. GLB rounding
cannot verify microscopic gaps; use the FOLD coordinates and exact reports.

All six compatible two-panel endpoints pass lengths, angles, holds, numerical
whole-sheet contact and exact nonnegative lower/upper gaps. The symmetric
conditions leave them almost coincident without welding them. Matching
material positions still change with refinement. This requires known order
along z and both panels to remain height graphs over xy; it does not check
a continuous motion. See [the two-panel finding](notes/coupled-crease-contact.md).

### Giving crease panels unequal controls

```bash
stack run senbazuru-material-study -- --unequal-crease build/fold-material
```

Open [unequal panel controls](http://127.0.0.1:8000/unequal-crease.html).
Compare matched holds, an opened upper grip, an upper bend preference, the
same preference with contact disabled, and incompatible held rows at 32 and
64 triangles. A narrow strip beside the crease and each outer edge stay
held in every case, keeping the crease closed while both interiors respond.

The side drawing projects three material rows from each panel onto x/z with
equal axis scales. The gap plot magnifies all triangle-overlap corner gaps:
positive is separation, negative is crossing. Its scale stays fixed across
the stages of a control. These marks cover the width but do not measure
contact area. The response table compares matching material points with the
matched-holds endpoint; a separate comparison switches only contact on/off.

The `unequal-crease/` directory retains original, numerical-start and endpoint
FOLDs/GLBs plus plots and `checks.json`. A refused control has only its original
guess. The contact-off endpoint remains diagnostic even if its material solve
converges. Its starting guess is unchanged because that mode also disables
contact repairs. The 3D iframe reuses `checked-flap/node_modules`; exact gaps
refer to stored FOLD coordinates, not rounded GLB display positions.

These static checks preserve the original material, crease and contact
tolerances. They assume known order along z, and do not certify the flexible
path or establish mesh independence. See [the finding](notes/unequal-crease-controls.md).

### Refining the unequal panels

```bash
stack run senbazuru-material-study -- --unequal-refinement build/fold-material
```

Open [the refinement comparison](http://127.0.0.1:8000/unequal-refinement.html).
Length × width settings `1×1`, `2×1`, `4×1`, `1×2`, `2×2` refine the
folded side profile and its extrusion independently. They contain 32, 64,
128, 64 and 128 triangles. The held material regions and total upper bend
control strength stay unchanged. Each mesh has a matched reference, upper
bend preference and identical preference with contact disabled.

The additional map samples the same 40 × 40 projected locations on every
mesh. Teal means a nonnegative gap at most `1e-7` sheet lengths, ochre means
more separation, red means crossing, and gray means no common projection.
These samples describe regions; they neither measure exact contact area nor
replace the exact all-triangle overlap check. The table compares maximum
gaps, near-contact counts and bending energies, alongside matching material
positions. Unconverged endpoints remain explicitly diagnostic.

`unequal-refinement/` contains complete FOLDs, GLBs, side/gap/map SVGs and
`checks.json`, including solver stopping information. The same known-z-order,
static-endpoint and uncalibrated-material limitations apply. This more
expensive comparison is opt-in, separate from generating the entire gallery.
See [the refinement study](notes/unequal-crease-refinement.md).

### Measuring prescribed bends without optimization

```bash
stack run senbazuru-material-study -- --prescribed-bend build/fold-material
```

Open [the prescribed-bend comparison](http://127.0.0.1:8000/prescribed-bend.html)
with the existing gallery server. Four known shapes on eight existing meshes
separate passive material bending, the imposed upper-band preference and
length penalties. The weight selector re-evaluates the reported penalty; it
runs no solver. Both layers coincide, the central crease stays closed, and the
old grips are not imposed. Their displacement is explicitly reported.

`prescribed-bend/` retains 32 shared-scale profile SVGs, 32 material FOLDs and
32 detailed JSON files, plus `checks.json`. A sampled smooth cylinder has short
straight chords and fails the unchanged length cap even at `8×2`; it remains
a diagnostic. A companion polygon preserves edge lengths but only approximates
the cylinder. Neither is an equilibrium or a checked motion. No extra model
viewer dependencies or archived solves are needed. See [the measured formulas
and next experiment](notes/prescribed-bend-energy.md).

The same page also compares the existing band rule with an experimental rule
that attributes only the represented fraction of actual turn to a clipped
interval. **Inspect band at length** shows full and partial material intervals;
the JSON download retains both spring encodings and energy derivatives.
The candidate does not change solver defaults. Original shape, length, passive
energy and contact measurements remain unchanged. See [the boundary comparison](notes/band-boundary-fractions.md).

### Solving with both band-boundary rules

```bash
stack run senbazuru-material-study -- --boundary-solves build/fold-material
```

Open `boundary-solves.html` on the same local server. Twelve opt-in solves
compare original and fractional band turns at `2×1` and `2×2`, each with
matched holds, an upper bend band and contact disabled for comparison.
**Mesh + boundary rule** selects a run; the paired profiles always show its
solved endpoints, while **Show** selects a numerical stage in the main viewer.
Both energy rules are evaluated on each band endpoint. Contact-off and failed
endpoints stay diagnostic, with unchanged acceptance limits and no claim of a
continuous folding route. Original commands retain their previous rules.
See [the measured comparison](notes/fractional-band-solves.md).

### Length refinement under both band rules

```bash
stack run senbazuru-material-study -- --boundary-length build/fold-material
```

Open `boundary-length.html` on the same server. This runs twelve opt-in
solves on `2×1` and `4×1`, with both rules and the same three controls.
The width, held material regions, passive stiffness, length schedule, contact
policy and acceptance limits stay fixed. The target table compares each
rule's length doubling separately; paired contact maps use the same projected
locations and report category changes. Both maps and the rule-comparison
profiles always show solved endpoints, independently of **Show**. Failed and
contact-off endpoints remain diagnostic. This does not perform a tighter
solve or certify a flexible route. See [the length study](notes/fractional-band-length.md).

### Locating costs on saved endpoints

```bash
stack run senbazuru-material-study -- --bend-locations \
  build/fold-material/boundary-length build/fold-material
```

This reads the preceding study's `checks.json` and twelve `-after.fold` files;
run `--boundary-length` first only if those saved inputs are unavailable.
Open `bend-locations.html` on the same server. **Control**, **Rule**, **Panel**
and **Energy** select paired material maps, cumulative costs and fixed-region
tables. Turn profiles always show passive edges parallel to the original
crease, dividing each signed turn by its material spacing and retaining the
range across the width. All other edge costs remain in the totals and raw data.
The command rechecks material, holds, crease angles and contact, retains source
convergence, and refuses mismatched saved measurements. Contact-off or failed
endpoints remain diagnostic. It copies the inputs without changing coordinates
or running an optimizer. The maps do not prove a continuous route or satisfy
the refinement criteria; see [the measured locations](notes/bending-energy-locations.md).

### Refining only the strip outside the band

```bash
stack run senbazuru-material-study -- --outer-strip build/fold-material
```

Open `outer-strip.html` on the same server. This opt-in experiment runs 24
solves: four meshes, two band rules, and matched, loaded and contact-off controls.
The uniform meshes have 64 and 128 triangles. Adding only the material column
at `15/32` to coarse gives 72 triangles; removing it from fine gives 120.
Both panels change together; width, material holds, seed shape, physical band
loading and numerical policy stay fixed. On the uneven meshes, spring
coefficients use the actual neighboring strip widths; their supports are
reported explicitly.

The four cards and turn profiles always show solver endpoints. **Mesh** and
**Show** select one numerical state for the detailed checks, FOLD/GLB downloads,
region costs and optional 3D viewer. Missing endpoints are not compared, and
failed or contact-off endpoints cannot pass. Differences at matching vertices
do not bound all material points or certify a flexible motion. No new long
solve is added to the regular test suite. See [the outer-strip study](notes/outer-strip-refinement.md).

To continue only the two exhausted outer-strip endpoints at the same final
weight, keeping their original reports and positions:

```bash
stack run senbazuru-material-study -- --outer-continuation \
  build/fold-material/outer-strip build/fold-material
```

Open `outer-continuation.html`. **Case** compares the saved endpoint with its
continuation, and **State** selects the source, restart feasibility check or
new endpoint. Profiles share a camera and scale; gap plots share one magnified
scale within a case. Separate energies, full proposed movement and both
histories remain available. Only the starting coordinates change on restart;
material, holds, bending preferences, contact policy and all thresholds stay
fixed. Source mismatches are refused before solving; crossing or unfinished
results remain diagnostic. No continuous route or material convergence is
claimed. See [the continuation study](notes/outer-strip-continuation.md).

To locate the remaining matched-hold energy difference using the four saved
outer-strip meshes, without a new solve or contact repair:

```bash
stack run senbazuru-material-study -- --matched-energy \
  build/fold-material/outer-strip build/fold-material
```

Open `matched-energy.html`. **Comparison** and **Panel** select signed maps,
region/direction totals, cumulative costs and transverse angular rates. Maps
use material edge locations, compress panel width equally and share a scale
across all comparisons. Shared, added and removed springs are counted
separately; the full report retains coefficients, turns and each contribution.
Both rule-labelled matched archives must agree, and all four endpoints must
retain convergence and pass fresh checks against the authored material. Missing,
failed or mismatched inputs are refused. Source FOLDs and reports are copied
unchanged; output must not overlap the source directory. This is discrete
energy accounting, not a continuous energy density or evidence of material
convergence. See [the findings](notes/matched-energy-locations.md).

To evaluate known bends on those same four meshes, without optimization:

```bash
stack run senbazuru-material-study -- --uneven-bends build/fold-material
```

Open `uneven-bends.html`. **Shape** selects a cylinder or a bend beginning
at the held-strip boundary; **Construction** selects exact surface samples
or full-length straight segments. **Panel** and **Mesh** expose both layers
and each of the sixteen references. Profile, cumulative-energy and turning-rate
plots share scales. Interval formulas account for missing boundary costs and
transition averaging; FOLD and JSON retain every material edge and spring.
Sampled chords fail the unchanged length cap and remain labelled diagnostic.
Full-length references preserve material lengths but move matching vertices.
Neither construction imposes the original outer grips or represents an
equilibrium; grip displacements, length costs and known-order contact checks
are explicit. No saved endpoint is read or changed. See
[the prescribed comparison](notes/prescribed-uneven-bends.md).

To compare references reaching both original grip regions:

```bash
stack run senbazuru-material-study -- --held-bend build/fold-material
```

Open `held-bend.html`. **Construction** selects samples of a common smooth
arc-and-straight reference, full-length chords with explicit outer-grip drift,
or full-length polygons geometrically fitted to the original grips.
**Panel** and **Mesh** select each layer's costs and all twelve references.
Profiles and plots share scales; FOLD/JSON retain material identities, every
edge and spring, curve parameters and the geometric-fit history. Grip copies
are allowed only within `1e-14` of the target, with final material lengths
checked afterward. Passing geometry does not establish material equilibrium;
the fitted curves change per mesh. Samples failing the length cap and full-length
controls missing their grips stay diagnostic. No material optimizer or contact
repair runs. See [the findings](notes/prescribed-held-bend.md).

To compare the circular reference with continuously varying curvature:

```bash
stack run senbazuru-material-study -- --smooth-bend build/fold-material
```

Open `smooth-bend.html`. **Reference** switches between the original circle
and a fixed cubic tangent transition. Both use the same grips and material;
**Construction**, **Panel** and **Mesh** retain the preceding controls. The
overview compares refinement gaps and errors against each common curve's
analytic cost. A curvature plot exposes the shorter, more concentrated smooth
bend. Both families export fresh results under `smooth-bend/`; existing
archives are not rewritten. This geometric fit does not find equilibrium or
establish that smoothness makes a coarse mesh sufficient. See
[the comparison](notes/smooth-held-bend.md).

To measure approximation error against the same fixed curves:

```bash
stack run senbazuru-material-study -- --bend-refinement build/fold-material
```

Open `bend-refinement.html`. Five nested meshes run from 64 to 1,024 triangles;
the earlier uneven 120-triangle mesh stays a separate reference point. Select
the curve, sampled/full-length construction, panel and mesh. All plots share
scales; percentages against analytic costs are separate from successive-mesh
changes. The command writes 24 FOLDs, 25 JSON files and 28 SVGs under
`bend-refinement/`, preserving prior galleries. Samples retain chord shortening;
full-length segments retain outer-grip drift. No per-mesh fit or material solve
runs. See [the refinement note](notes/fixed-bend-refinement.md).

To compare uniform spacing with more triangles near the two curvature joins:

```bash
stack run senbazuru-material-study -- --transition-refinement build/fold-material
```

Open `transition-refinement.html`. Both layouts start from the same coarse
mesh and match five triangle budgets through 1,024 triangles. Select the fixed
curve, sampled/full-length construction, panel and budget. Common-scale error
plots and column locations accompany side-by-side profiles, grip drift, edge
errors and a whole-material shape comparison. The fixed placement rule reads
only transition locations, never measured energy. The command writes 40 FOLDs,
41 JSON files and 54 SVGs under `transition-refinement/`, preserving prior
galleries. No per-mesh fit, grip copying, contact repair or equilibrium solve
runs. Improved cost accuracy can accompany greater grip drift; the controls
remain diagnostic. See [the findings](notes/transition-refinement.md).

To compare refinement across the complete curved region with both earlier
placements at equal triangle counts:

```bash
stack run senbazuru-material-study -- --whole-bend build/fold-material
```

Open `whole-bend.html`. Three profiles share one scale; select the fixed curve,
construction, panel and budget. The page shows cost errors, actual column
locations, edge errors, grip drift and all three whole-material pairwise
differences. The new rule uses density four across the bend and one outside,
without a fit, grip copy, repair or material solve. It writes 60 FOLDs, 61 JSON
files and 74 SVGs under `whole-bend/`; previous archives remain unchanged.
Whole-bend placement improves geometry, but the join windows still estimate
the circular cost more accurately. See [the note](notes/whole-bend-refinement.md).

### Comparing held-panel equilibria

```bash
stack run senbazuru-material-study -- --held-equilibrium build/fold-material
```

Open `held-equilibrium.html`. This opt-in experiment runs four solves: uniform
and whole-bend placement at 128 and 256 triangles, starting from the same smooth
curve and retaining the original grips. It uses the existing six length-weight
stages with 40 iterations per stage. It preserves shortened sampled edges as
an initial diagnostic, then lets both panels move between their grips.

The page separates solver convergence from static paper acceptance, compares
opening and individual costs, and measures differences across every material
triangle overlap. Numerical states are not folding steps. FOLD files, complete
sheet GLBs, JSON histories and side/gap SVGs live under `held-equilibrium/`.
The optional 3D panel reuses the local Three.js installation described for
[checked flap motion](#checked-flap-motion); the measurements and SVGs need no
npm dependency. There is no width refinement, tighter-solve confirmation or
new material/contact policy. See [the findings](notes/held-panel-equilibrium.md).

### Locating held-panel bending costs

```bash
stack run senbazuru-material-study -- --held-costs \
  build/fold-material/held-equilibrium build/fold-material
```

Open `held-costs.html`. This reads the four saved endpoints; it runs no solver
or contact repair. It refuses changed fixture/policy metadata, incomplete
convergence histories and mismatched measurements before writing any output.
Fresh material, hold,
crease-angle and contact checks accompany the copied source report and
byte-identical FOLDs. Source and output directories must not overlap.

Select either refinement or either equal-budget layout comparison, then a
panel. Signed maps, midpoint sums, cumulative costs, raw transverse angles and
angle/spacing plots share scales across all eight selections. Tables retain
added and removed springs and every edge direction. Fixed/free bins classify
spring midpoints, not physical energy density. The output includes 52 SVGs,
four complete-paper GLBs and detailed JSON under `held-costs/`; prior assets
remain unchanged. There is no new convergence claim or changed acceptance
criterion. See [the findings](notes/held-bending-costs.md).

Confirm only the two saved 256-triangle endpoints at a tighter movement stop:

```bash
stack run senbazuru-material-study -- --held-confirmation \
  build/fold-material/held-equilibrium build/fold-material
```

Open `held-confirmation.html`. Both continuations allow at most 40 additional
iterations at length weight `1e10`, changing only the full repaired proposal
stop from `1e-7` to `1e-8`. All four source archives must validate before any
output or solve; overlapping source/output directories are refused. Original
FOLD/report bytes are retained under `held-confirmation/`. A refusal or
unsettled endpoint remains diagnostic. The 128-triangle cases are remeasured,
not solved. Paper checks, contact policy and stiffness remain unchanged.

The gallery compares original, restart-repair and continued states, separate
costs, material displacement and fixed-bin contributions. Both endpoints settle
with negligible extra motion; the original refinement differences remain.
The eight complete-sheet GLBs use the existing `checked-flap/node_modules`
viewer dependency. Neither the numerical iterates nor the fine-to-coarse
comparison certify a folding route or a global minimum. See
[the stopping confirmation](notes/held-endpoint-confirmation.md).


Compare those confirmed endpoints with two new 512-triangle solves:

```bash
stack run senbazuru-material-study -- --held-refinement \
  build/fold-material/held-confirmation build/fold-material
```

Open `held-refinement.html`. Both layouts retain two width strips, the original
material and exact grips. Each uses the original six-stage length schedule,
then, only if converged and paper-valid, a bounded final-weight confirmation
at `1e-8`. Each stage allows at most 40 iterations. The 256-triangle inputs
are validated and remeasured before any writes or solves; overlapping input
and output directories are refused. Their FOLD bytes and source report are
copied unchanged into `held-refinement/`.

The gallery retains starting, repaired, six-stage and confirmation states as
available, including diagnostic failures. Shared-scale profiles, complete-sheet
GLBs, exact gaps, separate costs and fixed-bin maps compare 256 → 512 and
both layouts at each size. Solver convergence and paper checks determine
eligibility, separately from the shape/cost refinement targets. The costly
solves remain opt-in; CI exercises fixture and archive contracts. The existing
`checked-flap/node_modules` installation supplies the viewer. See
[the refinement results](notes/held-panel-refinement.md). This changes no
production solver policy and certifies no continuous flexible route.


Locate the remaining layout gap using the saved 256/512 endpoints:

```bash
stack run senbazuru-material-study -- --held-layout-costs \
  build/fold-material/held-refinement build/fold-material
```

Open `held-layout-costs.html`. This runs no optimizer or contact repair. Both
source formats must retain their original policies and confirmed histories,
and all four meshes are remeasured before any output. Changed measurements
and overlapping source/output paths are refused. The gallery keeps exact FOLD
copies, source reports, four complete-sheet GLBs and 28 SVGs under
`held-layout-costs/`; it needs no additional browser dependency.

Both panel selectors compare uniform → whole bend at the same triangle count.
Signed maps, cumulative costs and distance/direction tables use separate common
scales for passive bending and length penalties. Added/removed edges remain
visible; shared crease length edges count once. Separate rankings show largest
absolute-error costs and worst relative errors. No threshold or convergence
claim changes. See [the measured locations](notes/held-layout-costs.md).


The [current study milestone](notes/illustration-material-priority.md) prioritizes
plausible crane illustrations and controlled wing/body opening. The commands
above retain their original numerical verdicts; a failed energy-refinement
target stays visible as research evidence. It no longer blocks the illustration
milestone, whose endpoint paper/solver checks and explicit visual review remain
required. No existing failed geometry or unresolved exposed-layer comparison
is automatically accepted.


`stack run senbazuru-material-study -- --body-patch build/fold-material`
writes `body-patch.html`: the central body and both wing collars with a free
outer boundary. The closed reference passes; coarse 5°/10° controls pass geometry
but remain unsettled, and the refined 5° control fails lengths/contact. Failed
endpoints retain FOLD, measurements and solver checkpoints, with explicitly
labelled wire views instead of accepted paper. This is an extracted specimen,
not a whole-crane opening or a flexible motion certificate. See [the bounded
comparison](notes/coupled-body-patch.md).

### Comparing paper at illustration scale

```bash
stack run senbazuru-material-study -- --illustration-refinement \
  build/fold-material/band-refinement-8x2 build/fold-material
```

This postprocesses the saved `checks.json` and nine endpoint FOLD files from
the 8×2 study below. It rechecks geometry and generates SVGs without running
another material solve. Serve the output directory over HTTP and open
[the illustration comparison](http://127.0.0.1:8000/illustration-refinement.html).
The standalone page needs no npm install or 3D viewer dependencies.

Four cameras compare length and width refinement at exactly 600 pixels per
sheet unit, using a provisional two-pixel budget. Switch between paper,
silhouette, visible crease and source-layer views; the overlay marks sampled
differences beyond the budget. Magnification is labelled and does not change
the measurements. “Check all views” runs the pixel audit in the browser;
its JSON can be downloaded or read in the page. Separate lower/upper masks
avoid compositing one layer over the other. Polygon area and maximum vertical
span measure exposure before rasterization; span is not normal strip thickness.
“Audit this comparison on 12 grids” tests three sampling densities and four
offsets, with coverage and outlier counts included in the JSON. Any layer
failure retains review status; incomplete audits cannot confer a pass. See
[the thin-layer investigation](notes/thin-layer-visibility.md).

The geometric table also bounds distance between the filled exposed regions
in both directions, before rounding or sampling. A budget-straddling interval
stays unresolved; a geometric pass never waives a pixel failure. Witness SVGs
join a source point to its nearest target point. A large distance can come
from a tiny remote fragment, rather than a large material displacement. The
JSON includes unrounded polygons, witnesses and termination reasons; see
[the distance study](notes/exposed-layer-distance.md). Missing source files require
generating the earlier study first; this command never starts it implicitly.

The area table measures exposure farther than two pixels from its counterpart
in each direction. It reports source area, outside-area bounds and unclassified
area; JSON also retains split counts and termination. The precision target is
0.00001 px² unclassified, with at most 100,000 splits per direction. A work cap
leaves its interval visible. This is measurement accuracy, not an acceptance
waiver: small area never overrides distance, pixel or material/contact checks.
See [the area study](notes/exposed-area-budget.md).

“Locate the exposed-area difference” shows the contributing regions at 1× beside
32× details. The two shortcut buttons open the above/low-angle length cases;
layer, direction and tile selectors cover the other comparisons. Red is
definitely outside, amber is unclassified. Purple tile frames are optional
navigation aids, not measured area. Each 16×16-pixel tile becomes a 512-pixel
detail plus margins, rendered from unrounded coordinates. These scales stay
fixed when the ordinary inspection zoom changes. Links retain standalone SVGs
and raw contributing triangles; see [the location study](notes/exposed-area-highlights.md).

Paper validity, illustration suitability and material convergence are separate.
Crossing controls remain ineligible and unresolved visibility gets no graded
fallback. Half-pixel mask sampling can miss smaller features, so inspect the
drawings as well as the numbers. See [the study](notes/illustration-scale-refinement.md).
The fast mask regressions run with `make study-js-check` (Node.js 20 or later)
and are included in `make check` and CI.

### The 8 by 2 refinement decision

```bash
stack run senbazuru-material-study -- --band-refinement-8x2 build/fold-material
```

Open [the 8×2 comparison](http://127.0.0.1:8000/band-refinement-8x2.html).
Matched, distributed-band and band contact-off controls run on `4×2`, `8×1`
and `8×2` (256, 256 and 512 triangles). Every run keeps the common six-stage
length schedule through `1e10`, progressive contact exchange, forty iterations
per stage, physical controls and endpoint acceptance caps.

Twenty-seven complete FOLD/GLB states, 81 SVG plots and `checks.json` retain
accepted and failed endpoints. A separate table compares length and width
refinement against the study's 0.1% position, 5% opening and 5% separate-energy
targets. Near-zero references show absolute changes; invalid endpoints cannot
satisfy study targets. Inspect contact maps too. A tighter-solve confirmation
remains a separate requirement; these static experiments do not establish
calibrated material properties or a continuous flexible route. Earlier
commands remain unchanged. This opt-in viewer reuses
`checked-flap/node_modules`; see [the study](notes/band-refinement-8x2.md).

### One more band length doubling

```bash
stack run senbazuru-material-study -- --band-refinement-8 build/fold-material
```

Open [the 8×1 band comparison](http://127.0.0.1:8000/band-refinement-8.html).
Matched holds, the distributed-band preference and its contact-off control
are each solved on `2×1`, `4×1` and `8×1` (64, 128 and 256 triangles).
All nine runs use the same six length weights through `1e10`, progressive
contact exchange and forty iterations per stage. Width, material, holds,
loading and every acceptance cap stay fixed. Earlier commands are unchanged.

The twenty-seven complete FOLD/GLB states, 81 SVG plots and `checks.json`
retain numerical and physical acceptance separately, including crossing or
unconverged diagnostics. Compare matching positions, exact gap extrema,
fixed-grid contact samples and passive/control energies across both length
doublings. These static, known-order controls use illustrative material
parameters; acceptance alone does not establish shape convergence or a
continuous flexible route. This expensive command is opt-in, and its viewer
reuses `checked-flap/node_modules`. See
[the study](notes/band-refinement-8.md) for measurements and the next step.

### Refining the band with one common solver policy

```bash
stack run senbazuru-material-study -- --combined-band-refinement build/fold-material
```

Open [the combined band grid](http://127.0.0.1:8000/combined-band-refinement.html).
All six length × width meshes (`1×1`, `2×1`, `4×1`, `1×2`, `2×2`, `4×2`)
use progressive contact exchange and length weights `1e2`, `1e4`, `1e6`,
`1e8`, `1e9`, `1e10`, with forty iterations per stage. Each has matched holds,
three-line and distributed-band preferences, and contact-off versions of both
loads. Material, held regions, loading and acceptance caps are unchanged.
Earlier commands retain their original numerical policies and results.

The opt-in run exports ninety FOLD/GLB states, 270 SVG plots and `checks.json`
with step histories, matching-material comparisons, fixed-grid gap samples,
and separate passive/control energies. Numerical convergence is reported
separately from physical acceptance; crossing contact-off endpoints remain
diagnostics. The 3D view reuses `checked-flap/node_modules`. These are static
states with known z order and illustrative material parameters, not a
continuously checked flexible route or proof of mesh independence. See
[the study](notes/combined-band-refinement.md) for the measured results.

### Enforcing lengths in the fine band controls

```bash
stack run senbazuru-material-study -- --band-length build/fold-material
```

Open [the fine-band length comparison](http://127.0.0.1:8000/band-length.html).
It compares `4×1` and `4×2` schedules ending at `1e9` or `1e10`, with matched
holds and the distributed preference with contact disabled. The original
failures remain available; all controls, holds, iteration budgets and
acceptance limits stay fixed. Crossing still fails independent contact checks,
even if length enforcement permits numerical convergence.

The page shows per-edge lengths and replays each original failed contact-off
endpoint with a fresh budget at the same weight and at the larger weight.
Downloadable `*-length-replay.json` files retain coordinates, step histories
and endpoint measurements. This isolates additional work from stronger
enforcement. The twenty-four FOLD/GLB states and gap/profile plots are static
numerical states, not a folding route. The expensive comparison is opt-in;
its 3D view reuses `checked-flap/node_modules`. See
[the study](notes/fine-band-length-enforcement.md) for evidence and limits.

### Replaying the failed band contact steps

```bash
stack run senbazuru-material-study -- --band-contact build/fold-material
```

Open [the band contact replay](http://127.0.0.1:8000/band-contact.html).
It compares the single-exchange and progressive-exchange policies on the
`2×1` and `2×2` meshes, keeping all five band-study controls, holds, loading,
length weights and acceptance limits unchanged. The progressive method can
replace several selected contact equalities in succession; each reduces
aggregate gap violation, but only the unchanged final checks permit convergence.

For each width the page replays the original failed band endpoint using
three contact methods. Downloadable `*-contact-step.json` files retain the
equations, proposed steps, constraint/source-row mapping, residuals and
exchange sequence. This replay is separate from the selected paper stage.
The complete comparison saves sixty FOLD/GLB states and their gap/profile
plots. It is opt-in, and reuses `checked-flap/node_modules` for the 3D view.
Known z order, held crease strips, uncalibrated material, and static-endpoint
limitations remain. This is a bounded solver fallback, not a guarantee of
convergence for arbitrary contact. See [the study](notes/several-contact-exchanges.md).

### Distributed bending over a material band

```bash
stack run senbazuru-material-study -- --band-refinement build/fold-material
```

Open [the band comparison](http://127.0.0.1:8000/band-refinement.html).
It compares matched holds, the original three upper line loads and a
preference distributed over the material interval `0.125` to `0.4375` from
the shared crease. Both loading styles have a contact-off diagnostic. All
six meshes use the unchanged combined solver and acceptance limits.

The distributed preference keeps its total desired turn and flat-paper
control energy fixed under refinement. Per-edge interval lengths determine
both preferred angles and stiffnesses; boundary intervals are clipped using
exact fractions. `band-refinement/checks.json` records those intervals, the
band's normalization, achieved turns, energies and endpoint diagnostics.
All stages have complete FOLD/GLB exports and the existing gap/profile plots.
The command is opt-in and reuses `checked-flap/node_modules` for the 3D view.
Known z order, the discrete treatment of band boundaries, static endpoints
and uncalibrated material remain limitations. See
[the study](notes/distributed-bend-preference.md).

### Refinement with one combined solver policy

```bash
stack run senbazuru-material-study -- --combined-refinement build/fold-material
```

Open [the common-policy comparison](http://127.0.0.1:8000/combined-refinement.html).
It extends the original five length/width meshes with `4×2` (256 triangles),
using the same length stages through `1e9` and the contact-exchange method
on every run. Each mesh has
matched, upper-preference and contact-off controls. Holds, control strength,
40-iteration stage budgets and acceptance limits are unchanged.

`combined-refinement/` retains all starting guesses, numerical starts and
endpoints as complete FOLDs and GLBs, side profiles, magnified gap plots and
fixed-grid gap maps. `checks.json` records solver settings, convergence,
material/contact measurements and changes at matching material points.
`bending` separates lower/upper passive energy from imposed control energy
and records achieved/preferred turns, stiffnesses and energies per width
segment at each imposed line. The page shows these turns for the selected
stage and compares endpoint energies across meshes.
The table shows edge error and convergence separately from geometric checks;
an unconverged result remains diagnostic. The 3D view reuses
`checked-flap/node_modules`. This command is opt-in; earlier gallery commands
keep their original policies. Known z order, static endpoints and uncalibrated
material remain limitations. See [the five-mesh comparison](notes/combined-crease-refinement.md)
and [the 4×2 follow-up](notes/two-direction-crease-refinement.md).

### Isolating fine-mesh solver failures

```bash
stack run senbazuru-material-study -- --fine-crease build/fold-material
```

Open [the fine-mesh solver comparison](http://127.0.0.1:8000/fine-crease.html).
The same 128-triangle sheet is tested with the original policy, one extra
length-penalty stage, a contact equality exchange, and both changes together.
Each has matched, upper-preference and contact-off controls. No physical
acceptance cap is changed. The policy selector, convergence row, plots and
endpoint checks distinguish the two failure mechanisms.

`fine-crease/` retains 36 complete FOLDs, 36 GLBs, 108 plot SVGs and
`checks.json`. `contact-step.json` saves the original failed inner problem and
its replay with both contact policies. The 3D view reuses
`checked-flap/node_modules`. Contact-off and unconverged endpoints remain
explicit diagnostics. A single equality exchange is not a general remedy
for dependent constraints; the known-z-order and static-endpoint limits
remain. The command is opt-in, outside the all-gallery run. See
[the finding](notes/fine-crease-solver.md).

<a id="continuously-checked-bird-petal"></a>

### Continuously checked bird base

A petal fold lifts one flap of the square base and folds its sides inward.
This recipe first collapses the prepared open sheet into the square base,
then folds the front petal to 175°, holds it while folding the back petal
underneath to 175°, and presses both to 180°. Seven crease angles per petal
change together; this is a separate study recipe from the single-hinge `CheckedFlap` operation.

```bash
stack run senbazuru-material-study -- --petal build/fold-material
npm install --prefix build/fold-material/checked-flap --no-audit --no-fund three@0.186.0
python3 -m http.server 8000 --bind 127.0.0.1 --directory build/fold-material
```

Open [the petal instructions](http://127.0.0.1:8000/petal.html). `checked-petal/`
contains twenty-three-figure SVGs from above and below, each with a common side
camera at 45°, a FOLD sequence, twenty-three GLBs with visible/complete scenes, and
measurements in `checks.json`. The viewer shares the checked-flap Three.js
installation. Each stage checks all 120 panel pairs and all 28 material edge
lengths using exact arithmetic on the ideal path. Certificates cover full
turns; the route uses their appropriate prefixes or suffix. Touching endpoint
orders and all three stage joins are checked separately.
Each displayed pose is rebuilt from crease angles and compared with that path
within `1e-12` model units, with shared-vertex, achieved-angle and contact checks.

This accepts the known bird fixture and its declared layer order. It does not
find arbitrary coupled motions, simulate thickness, or check how the initial
pre-creases were made. See [the collapse note](notes/checked-square-collapse.md)
and [the two-petal note](notes/checked-bird-base.md)
for why flat endpoint order and the floating-point comparison remain separate
from the exact interval result.

### Experimental bending

For the experimental crease/panel mechanics, run
`stack run senbazuru-material-study -- --bending build/fold-material` and open
`build/fold-material/bending.html`. This compares single/double packets and
diagonal/kite controls with illustrative stiffnesses. The latter use shared
crease ids and independent endpoint contact diagnostics, without contact forces.
The opposing-flap comparison adds corrective forces for declared directional
panel orders. Its unconstrained endpoint crosses; the corrected endpoint keeps
the order while missing the preferred crease angles. The numerical clearance
between unjoined panels is separate from physical thickness. The discovered-contact
variant learns those orders from a separated reference pose and rescans later
shapes; a new pair whose order the reference cannot establish is refused.
**Opposing flaps · first contact** adds a **Folding state** selector for a
supplied approach from 145° / 105° to 145° / 121°. It learns the previously absent
flap relationship at the first sampled overlap, then freezes that history for
correction. Each of its four rigid crease rotations is checked over its angular
interval before accepting the next pose. **Rejected route · full turn** shows
a crossing between valid endpoints. Failed or unresolved motions add no
relationships. This does not check arbitrary bending or the numerical
correction trajectory, or plan an approach automatically.
**Curled panel · self-contact** compares one uncreased strip with and without
local contact correction. Additional bending controls curl the strip while
its passive springs prefer flatness. Supplied triangle pairs keep the returning
end above the starting end without splitting the panel. These contacts are not
discovered automatically, and the check still applies only to saved states.
**Curled panel · discovered contact** removes that pair list. It discovers
nearby triangle partners from a separated 44.5° curl, extending their order
across flat reference patches. Search distance, model direction and numerical
clearance are supplied controls. Uncovered new contacts are refused; it does
not discover or certify a continuous bending route.
**Curled panel · growing contact history** adds separated encounters from accepted
solver steps. Its sixteen-span strip learns six new relationships while keeping
the original four, and passes independent endpoint checks. **Contact history**
selects the reference, learning pose or settled endpoint; the left picture keeps
the stalled fixed-reference result. Rejected trials add nothing. Numerical
iterations still do not certify the continuous bending route.
**Contact between numerical poses** adds a **Correction case** selector for a
connected square's clear endpoints and its rejected numerical shortcut, plus
checked closing and opening strips. The new mode requires whole-interval
separation before accepting any correction or new contact history. The opening
settles; the closing solve reports whether it settles or stalls with remaining
length error, since the numerical route can vary across platforms. Numerical
straight vertex paths can stretch, so these are not physical folding steps.
The checked-strip views include **Why trial corrections were refused**, with
counts and first/last examples for energy, contact-history and motion failures.
The downloaded JSON includes their positions and settings. An exhausted line
search ends its penalty stage as unconverged instead of repeating identical
work; this does not repair the closing strip's remaining material error. See
[the rejection diagnosis](notes/rejected-bending-trials.md).
**Distance barrier · closing** compares that strict solver with an energy that
resists a layer reversal before projected overlap. **Distance barrier · opening**
keeps the opening control. Both settle in the recorded run, with the same path,
material and endpoint contact checks. JSON includes the contact-energy name and
activation range; these are numerical settings, not paper thickness. Retained
directional orders and discovery from separated encounters still limit this
mode. See [the distance formulation](notes/directional-contact-distance.md).
This experiment does not add a general mechanics flag to `render` or `export`. The [study guide](../study/fold-material/README.md#crease-preferences-and-panel-bending)
describes its measurements and contact limits.

## `crease`

Draws a crease on a pattern and writes the whole document back out as FOLD.
The one command that produces a crease pattern rather than a picture of one.

```bash
stack run -- crease examples/quarter-fold.fold --from 0,0 --to 1,1 --valley -o creased.fold
```

| Option | Meaning |
| --- | --- |
| `--from X,Y` | One end of the crease |
| `--to X,Y` | The other end |
| `--mountain` / `--valley` / `--flat` / `--unassigned` | What kind of crease it is. Exactly one, and required |
| `--folded` | Read `--from` and `--to` on the model the pattern folds into, and crease every layer under that line. What is written out is still the pattern |
| `--frame N` | Which frame to crease (default 0). The others are carried through untouched |
| `-o`, `--output` | Where to write. Default is stdout |

The ends join whatever is already at them: a corner they land on, or a crease
they land in the middle of, which is cut there. Anything the new crease crosses
on the way is cut too, and the faces are worked out again afterwards — so what
comes out is a pattern in the same good order as one that was read.

**A negative coordinate needs the `=` form**, because otherwise the argument
parser reads it as an option:

```bash
stack run -- crease examples/bird-base.cp --from=100,-200 --to=100,200 --flat
```

That is not a corner case. Every `.cp` and `.opx` in existence is drawn on the
square from `(-200, -200)` to `(200, 200)`. (The line above is a vertical one
through the right-hand half of the bird base, which crosses five of its creases
and takes it from 26 creases to 37. Its own diagonals are already creased, so
drawing one of those is refused — see below.)

Four creases it will not draw, each refused naming what is wrong: one with no
length, or with two ends the sheet counts as one point; one drawn along a crease
that is already there, where the paper would have two ways to fold along the
stretch they share; one on a folded form, which is `--folded`'s business below;
and one whose end does not land on any edge or corner the pattern already has,
so it would stop there and divide nothing. The last names the point:

```console
$ senbazuru crease square.fold --from 0,0 --to 3,3 --valley
senbazuru: cannot crease square.fold: the end at (3.0, 3.0) does not meet any crease
or edge the pattern already has, so the crease would stop there and divide nothing
```

It says that rather than "that end is off the paper" because the second is not
always true — [the tour](tour.md#what-it-creases) has the case that shows why.
An end part-way *along* an existing crease is not refused: it meets something.

### `--folded`, creasing through the layers

A book almost never gives its instructions on the flat sheet. Step 4 says "fold
the top corner down" about paper that was folded in half in step 2, and the
reader is creasing every layer under their fingers at once. `--folded` is that
move: the two ends are read on the model the pattern folds into, and what comes
back is the pattern with everything that line creases marked on it.

```bash
stack run -- crease examples/diagonal-cp.fold --folded --from 0,0.5 --to 0.5,0 --valley
```

`diagonal-cp.fold` is the unit square with a valley down the diagonal, so it
folds in half onto a triangle. That command draws the triangle's midline, which
reaches both layers, and the pattern comes back with two new creases —
mirror images about the existing fold, and **one of each kind**:

| | |
| --- | --- |
| `(0, 0.5)` to `(0.5, 0)` | valley, as asked |
| `(0.5, 1)` to `(1, 0.5)` | **mountain** |

That is not a bug and it is what paper does. Every layer of a packet creases the
same physical way, but a flap folded over is upside down, so the same fold is a
valley where the sheet is face up and a mountain where it is face down. Fold a
square in half, crease the packet, unfold, and you have one of each. Ask for a
valley across the quarter fold, which is four layers, and the kinds alternate
through the stack: mountain, valley, mountain, valley. Which way up a layer lies
flips across every crease the paper actually folds along, so it is a parity count
of the folds between that layer and whichever face was held still.

A line drawn on a folded model is **one crease per face it crosses**, which is
not the same as one per layer and is usually more: across the folded crane, the
worst line crosses 56 of its 72 faces, where the deepest stack of paper found
over any single point is 24 and the deepest layer number is 32.

**Neither end may be in the middle of a face**, because that layer would then be
creased only part of the way across, and a crease that stops in the middle of
the paper divides nothing:

```console
$ senbazuru crease examples/bird-base.cp --folded --from=-200,150 --to=-100,150 --valley
senbazuru: cannot crease examples/bird-base.cp: --from is inside face 12 of the folded
model rather than on that face's edge, so that layer would be creased only part of the
way across. Each layer the line reaches has to be creased right across, so move this
end onto an edge or clear of the paper
```

An end *on* a face's edge is fine, wherever it is — including well inside the
model's outline. What matters is only that every layer the line reaches gets
creased right across, and an end sitting on the edge of each face it touches
does exactly that. This is why a line can be drawn from one crease of the
quarter fold to another.

How often a crease of a folded model is such a place depends on whether the
layers' edges line up there, and that varies a lot. Of the folded crane's 248
face-edge midpoints, 120 sit on the edge of every face they touch; the other 128
are in the middle of some other layer's paper and are refused. The bird base
splits 24 to 20. The quarter fold, whose four layers land exactly on top of one
another, is 16 to nothing.

Moving that end off the paper creases the bird base through all fourteen of its
layers, and the result folds:

```bash
stack run -- crease examples/bird-base.cp --folded --from=-300,150 --to=-100,150 --valley -o bird.fold
```

Three things it will not do. It creases *every* layer under the line — "fold the
top layer only" is a different instruction, and is part of
[#60](https://github.com/avalonalex/senbazuru/issues/60). It wants a model that
folds *flat*, because a line drawn on the page of a model with paper still in
the air is a ray rather than a point and names no one place on the sheet. And it
takes the **pattern**, not a file that is already a folded form: the line is
mapped back by undoing the motion that placed each face, and those motions exist
only because we did the folding. A file that arrives already folded carries
neither them nor a sheet to map back to, and recovering one is unfolding.

Without `--folded` a folded form is refused outright, as it always was: the
regions between a folded form's creases are not its faces, so there is nothing
to draw a line on.

## `fold`

Folds a crease pattern and writes the folded shape out as FOLD, with the layer
order it worked out. `render --fold` computes all of this and then draws it;
this is the same computation with the answer kept.

```bash
stack run -- fold examples/crane.fold -o crane-folded.fold
stack run -- render crane-folded.fold -o crane.svg     # the same picture, from the file
```

| Option | Meaning |
| --- | --- |
| `--frame N` | Which frame to fold (default 0, the key frame) |
| `--stacking N[,N...]` | Which layer order to write, when the model has several. `info --fold` lists the choices |
| `--layer-budget N` | How many guesses the layer solver may make before giving up |
| `-o`, `--output` | Where to write. Default is stdout |

**One frame comes out, and it is the folded shape.** The other frames of the
input are not carried through, and neither is the pattern: the input file still
holds it, and a file whose first frame is a folded form followed by the flat
sheet is a picture of the model coming undone, since `--steps` draws frames in
file order.

What comes out carries `frame_classes: ["foldedForm"]`, 3D coordinates when the
model leaves the plane, the fold angles it folded by, and `faceOrders` when the
layer order can be worked out. A model the solver does not cover — one not
folded flat, or with a face that is not convex — gets no `faceOrders` rather
than an empty list, because "no two faces overlap" and "nobody knows" are not
the same claim.

Two deliberate omissions. The vendor keys of the input do not survive, which is
[#73](https://github.com/avalonalex/senbazuru/issues/73): folding rewrites every
coordinate, and nothing can judge which unknown keys still hold. And
`file_creator` is left alone, so a file that says another tool made it goes on
saying so; `crease` behaves the same way.

## `check`

Takes `--frame` as well, and one option of its own.

| Option | Meaning |
| --- | --- |
| `--tolerance DEG` | How far Kawasaki's alternating sum may sit from zero and still pass (default `0.000573`, which is 1e-5 radians). Raise it for files whose coordinates are heavily rounded |

It exits non-zero when it finds a violation, so it drops into a build or a hook
without anyone grepping the output.

## `info`

| Option | Meaning |
| --- | --- |
| `--fold` | Report the layers of each frame folded along its own angles, as `render --fold` draws it. A crease pattern has no layers until it is folded, so this is the only way to see what `--stacking` can choose between |
| `--layer-budget N` | As for `render` |

The `layers` line is where to look when a folded form comes out as a wireframe:
it reports the `faceOrders` the file carries, or, for a folded form without any,
whether one could be worked out and if not why. Where a model has more than one
valid layer order, a `stacking` line follows it with the indices `--stacking`
will accept.

```console
$ senbazuru info examples/crane.fold --fold
...
    layers:   (none in the file; 892 overlapping pairs in 2 components, 5 valid orders)
    stacking: 1 component with a choice; --stacking takes 0-4
```

The two counts differ by one on purpose. The first counts components the way
[Flat-Folder](https://github.com/origamimagiro/flat-folder) does, with the pairs
that were settled outright among them, so that its published figures can be
compared with these. The second counts what you can actually choose. See
[notes/several-stackings.md](notes/several-stackings.md).

## Fold-material experiment

`stack run senbazuru-material-study -- build/fold-material` generates a single fold
and two perpendicular folds, with sharp and rounded variants plus a before/after
length and contact correction. It produces a rotatable viewer, baseline SVG previews,
indexed OBJ and FOLD surfaces for each recorded checkpoint, material-length
measurements and solver progress. Open
`build/fold-material/index.html`. The [study guide](../study/fold-material/README.md)
explains how to run and inspect it. The corrected double fold meets both its
edge-length and packet-order targets. The viewer also reports crossings in
unfinished iterations. Bending stiffness, crease-angle preferences, finite
thickness and general collision handling remain unsolved. Solver checkpoints
have no SVG preview because the study painter would hide intermediate crossings. This experiment does not change
`render` or `export`.

The [fish and bird fixtures](../examples/README.md#fish-and-bird-bases-opening-and-reshaping-flaps)
can be drawn with `render examples/fish-base.fold --fold` and
`render examples/bird-base.fold --fold`. Their crease patterns and closed
endpoints are checked. In the study viewer, select **Fish base** for fifteen
states gathering its two rabbit ears in sequence. The first stays at its 175°
inspection state while the second moves; the final view leaves both slightly
open. Select **Bird base** for sixteen states: the square base, the first petal,
the second petal on the underside, and a final press of both petals to the flat
bird base. During the second stage, the first petal stays at 175°. Drag to see
the underside. Continuous collision certification and paper thickness remain
unsupported; see [the study guide](../study/fold-material/README.md#two-petals-form-the-bird-base).

The checked bird sequence is also an ordinary FOLD example for the main CLI:

```bash
stack run -- render examples/bird-base-sequence.fold --steps --columns 4 --view iso --width 1000 --height 1000 -o bird-steps.svg
stack run -- render examples/bird-base-sequence.fold --steps --columns 4 --view bottom --width 1000 --height 1000 -o bird-underneath.svg
stack run -- render examples/bird-base-sequence.fold --frame 12 --view iso -o second-petal.svg
```

Frame zero holds file metadata; frames 1–16 are the folding states, so frame
12 shows the second petal at 90°. These frames already contain folded geometry;
omit `--fold`. The page keeps one camera and scale and adds no arrows unless
requested. Open convex planar panels use depth over projected overlaps to hide
covered paper and creases. Coplanar contact still needs `faceOrders`.
Intersecting depths, unsupported faces and free edge-on outlines retain the
older fallback. `--no-fill` remains available for a wireframe, including a file
whose faces are malformed. See [the visibility note](notes/projected-panel-visibility.md).
