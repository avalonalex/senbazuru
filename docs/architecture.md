# How senbazuru is put together

The map of the code: what flows where, what each module holds, and the rules
about which module may know about which. Read this before adding a module.

For what the tool *does*, the [README](../README.md); for how to run it,
[usage.md](usage.md); for the vocabulary any of it assumes,
[glossary.md](glossary.md).

## The pipeline

One direction of flow, no cycles:

```
 .fold bytes    .cp / .opx bytes
     |               |               Senbazuru.Import.Cp / .Opx / .Segments
     |               |               a list of segments in, one Frame out:
     |               |               no faces, no fold angles, no second frame
     |  Senbazuru.Fold.Load          I/O boundary: read + decode, errors as
     v               v               values; the extension picks the reader
 FoldFile / Frame                    Senbazuru.Fold.Types
     |                               a faithful, permissive mirror of the format
     |  Senbazuru.Fold.Creasing      draw a new crease: a Frame in, a Frame
     |                               out, and back through the two below
     |                               (Origami.ThroughLayers draws one on the
     |                               folded model instead, and comes back here)
     |  Senbazuru.Fold.Crossings     cut the creases where they meet, so the
     |                               drawing is a planar graph
     |  Senbazuru.Fold.Faces         the faces a file did not record, traced
     |                               from the creases; asked for by whatever
     |                               needs paper rather than lines
     |  Senbazuru.Fold.Query         validate + refine: indices become real points
     v
 [Crease]                            3D geometry that cannot be structurally wrong
     |                               |
     |                               +--> Senbazuru.Origami.FlatFold
     |                               |    origami knowledge, no drawing: is this
     |                               |    pattern locally impossible to fold?
     |                               +--> Senbazuru.Origami.Folding
     |                               |    fold it: a Frame in, a folded Frame
     |                               |    out, straight back into this pipeline
     |                               +--> Senbazuru.Origami.Surface
     |                               |    shared material ids, current positions,
     |                               |    crease topology and optional properties
     |                               +--> Senbazuru.Origami.Layers
     |                               |    which face is in front, and how deep
     |                               |    in the stack, given where the viewer
     |                               |    is standing
     |                               +--> Senbazuru.Origami.Stacking
     |                               |    which face is on top of which, when
     |                               |    the file does not say: faceOrders out
     |                               +--> Senbazuru.Origami.Visible
     |                               |    what of a flat-folded model can be
     |                               |    seen: regions of paper and the edges
     |                               |    that are not buried
     |                               +--> Senbazuru.Origami.Step
     |                                    subtract two frames: which paper moved
     |                                    and where it went, i.e. the arrow
     |  Senbazuru.Render.CreasePattern
     |  + Senbazuru.Render.Camera    orthographic projection to the page
     |  + Senbazuru.Diagram.Style    origami line conventions
     |
     |    Senbazuru.Render.Gltf       the one backend that does not go through
     |      |                         Diagram, because Diagram is 2D: faces in
     |      v                         space, shared positions, two-sided paper
     |    .glb bytes
     v
 Diagram                             Senbazuru.Diagram
     |                               backend-independent: shapes + strokes
     |  Senbazuru.Render.Svg         + Senbazuru.Geometry for the page transform
     v
 SVG text
```

The top of that diagram is the only part that also runs backwards:
`Senbazuru.Fold.Load` encodes and writes as well as reading and decoding, so a
`FoldFile` can go back out as bytes. It is a second door in the same wall rather
than a cycle — nothing further down the page is involved, and the only thing
that reaches for it is a caller holding a `Frame` it built or folded.

`Senbazuru.Fold.Creasing` is the first such caller, and the first module that
goes *in* at the top and comes *out* at the top: a frame in, a frame out, no
picture anywhere.

The fold-sequence language
([#60](https://github.com/avalonalex/senbazuru/issues/60)) was once expected
to be more of the same, each move a frame in and a frame out. It is not going
to be, and the reason is worth having here before the code is. A
[fold sequence](glossary.md#fold-sequences) is the list of instructions that
takes a sheet to a model, and more than a file's reader will want a run of one:
a page of step figures, the [material study](#material-study), and later an
animated 3D export. All of them need what no frame holds: which paper a move
turned, about which line, which way as the reader sees it, and what was
checked along the way. Subtracting one frame from the next cannot recover
that. A fold followed by its unfold leaves every vertex where it was, so two
identical frames come out of it, and a book still draws an arrow there.

So a run will hand back one record for each move, and the drawings will be
made from the records. What reaches this pipeline as a *file* is still plain
FOLD, written from those records, and `Fold.Query` cannot tell it from one
somebody wrote by hand. Where that boundary sits is a layering rule,
[below](#layering-rules); the design is in
[PRDs/01-architecture.md](../PRDs/01-architecture.md#32-a-move-is-not-a-frame-in-a-frame-out).

| Module | Holds |
| --- | --- |
| `Senbazuru.Explain` | The one method every error type in the library answers: turn yourself into a message. No FOLD, no geometry, no drawing — just `Text`. |
| `Senbazuru.Geometry` | `V2`, `Box`, `Transform`. No FOLD, no SVG. |
| `Senbazuru.Geometry.VectorSpace` | The arithmetic 2D and 3D points share. |
| `Senbazuru.Geometry.V3` | Points in space, the cross product, and whether a set of points is flat. |
| `Senbazuru.Geometry.Rigid` | 3×3 matrices and motions that turn and slide but never deform, and the inverses that undo them. |
| `Senbazuru.Geometry.Polygon` | Convex polygons in the plane: area, clipping, and whether two overlap. |
| `Senbazuru.Fold.Types` | The FOLD document model and its JSON instances. |
| `Senbazuru.Fold.Load` | The only I/O in the library, in both directions. Also picks a reader from a file's extension. |
| `Senbazuru.Import.Segments` | A list of line segments → a `Frame`, merging the endpoints that coincide. What the two other-format readers share. |
| `Senbazuru.Import.Cp` | Orihime and Oriedita `.cp` text → segments. |
| `Senbazuru.Import.Opx` | ORIPA `.opx` XML → segments. |
| `Senbazuru.Fold.Query` | Validation and refinement of a `Frame`: `Crease`, `Face`. |
| `Senbazuru.Fold.Faces` | The faces a file does not record, traced from the creases. Refuses a drawing whose regions would not be its faces. Owns `Sheet`, the drawing itself. |
| `Senbazuru.Fold.Crossings` | Cuts creases at the points where they meet, so a drawing `Fold.Faces` refuses becomes one it can trace. `withPlanarFaces` is the pair — cut, then trace — that every backend calls. |
| `Senbazuru.Fold.Creasing` | Draws new creases on a pattern: the one operation that changes a crease pattern rather than reading one. Adds the lines and hands the frame straight back to `Fold.Crossings` — once for the whole batch, because that handing back is nearly all the cost. |
| `Senbazuru.Diagram` | The drawing IR: `Shape`, `Stroke`, `Diagram`. |
| `Senbazuru.Diagram.Style` | Every decision about how diagrams *look*. |
| `Senbazuru.Diagram.Layout` | Several figures on one page, at one shared scale. |
| `Senbazuru.Render.Steps` | A whole folding sequence as one page of figures. |
| `Senbazuru.Origami.Flat` | A model folded flat, as convex polygons in one plane. Shared by the two modules that reason about layers. |
| `Senbazuru.Origami.FlatFold` | Maekawa's and Kawasaki's theorems, vertex by vertex. |
| `Senbazuru.Origami.Folding` | Crease pattern + fold angles → folded form, and the rigid motion that placed each face. |
| `Senbazuru.Origami.Flap` | Selected aligned creases and a moving side → a checked rigid turn → angle-derived surfaces with the stationary side fixed. Refuses incomplete cuts and hinges on different axes. |
| `Senbazuru.Origami.HingeSweep` | Bounds a fixed-axis rotation over angular intervals; returns clear, contact witness or unresolved. Shared by the library flap operation and the study. |
| `Senbazuru.Origami.Contact` | Independent zero-thickness panel/triangle contact diagnostics and directional order checks, before any drawing or solver force. |
| `Senbazuru.Origami.Surface` | Shared material surface with original-sheet coordinates when known, current positions, crease/panel identities, coplanar orders, directional layer requirements and optional physical thickness. Owns the study's mesh types and shared midpoint refinement. |
| `Senbazuru.Origami.Layers` | `faceOrders` + a viewing direction → an order to draw in, how deep in the stack each face is, and which side of the paper it shows. Reads orders; never computes them. |
| `Senbazuru.Origami.Stacking` | A flat-folded frame → its `faceOrders`, solved from taco and tortilla constraints, one independent component at a time. Also `layerOrderFor`, the one policy for *which* orders a frame gets — its own, or solved, or none — shared by the SVG and 3D backends. |
| `Senbazuru.Origami.Step` | Two frames → what moved between them. |
| `Senbazuru.Origami.ThroughLayers` | A line drawn on the model a pattern folds into → the creases it makes on the pattern, one per face it crosses, each of the kind that layer's own way up asks for. |
| `Senbazuru.Origami.Visible` | A flat-folded frame + `faceOrders` + which side it is seen from → the paper that shows and the edges that are not hidden. |
| `Senbazuru.Render.Camera` | Orthographic projection: 3D → the page. |
| `Senbazuru.Render.CreasePattern` | FOLD frame → `Diagram`, and which view to use. |
| `Senbazuru.Render.Projected` | Convex open panels → viewing relations over their overlapping shadows → the existing flat visible-region machinery. Temporary projected frames never become material exports. |
| `Senbazuru.Render.Svg` | `Diagram` → SVG text. |
| `Senbazuru.Render.PaperMesh` | Shared surface → complete panels or exposed pieces on both sides of each plane. Clipped corners retain weighted material vertex references. |
| `Senbazuru.Render.Gltf` | Shared surface → glTF binary with visible and complete scenes, material references and no face displacement. The FOLD entry point prepares faces and constructs a surface. |
| `Senbazuru.Sequence.Syntax` | A fold sequence as a plain value with no functions in it: a header and steps of moves, with paper named by where it lay on the flat sheet and never by id. Both ways of writing a sequence produce it and everything that reads one consumes it. Also `stripSpans` and `canonical`, which let two sequences be compared; `sourceFiles`, which says what file a written path means; and `exactNumber`, how a number of the language is spelled, kept here because the printer and the error messages both need it and the errors sit below the printer. |
| `Senbazuru.Sequence.Error` | `SequenceError`, the one type the parser, the checker and later the runner all refuse with, and every problem type inside it with its words. Also how an error reaches a person, as three pieces kept apart: the message, `sourceLocation`, and `excerpt` with its caret. And `refusalKinds`, the names `expect refused` may use. |
| `Senbazuru.Sequence.Check` | A `Sequence` → a `Checked` one, or the first thing wrong with it that needs no paper to see: a name nothing defines or two things define, a point's name where a line belongs, a step that does nothing, a number out of its range, and the values only Haskell can build and no source can spell. `Checked` is opaque, so whatever takes one cannot be handed an unchecked sequence. It also gives each bare name beside `to` its kind, which the parser could not know. |
| `Senbazuru.Sequence.Build` | Writing a fold sequence in Haskell: a `do` block of steps, each a `do` block of moves, that builds the `Sequence` value. A bind hands back a name and never geometry, so building is pure and cannot fail. Haskell loops run while the value is built, and the value holds what they produced. |
| `Senbazuru.Sequence.Parse` | A sequence source, the text an author writes → a `Sequence`, with a span on every piece a run could later refuse. A failure is a `ParseProblem`: what was found, read as a whole word, what could have been there, and often a hint naming a well-known mistake. Its header is the record of the grammar and of the reserved words. |
| `Senbazuru.Sequence.Pretty` | A `Sequence` → the text an author would write, in the one canonical spelling: canonical words, exact numbers, defaults left out, parentheses only round a fold line named inside another. Total: it prints even a value no source could spell, so that the checker's complaint can show it. |
| `Senbazuru.Cli` (in `app/`) | Flag parsing. Not part of the library. |

## Where the files are

```
src/Senbazuru/     the library, as above
app/               the command-line interface
test/              property, example and golden tests
examples/          sample .fold and .cp files, with their provenance in examples/README.md
docs/              this, and everything else that is prose
docs/notes/        one idea per file: theorems, algorithms, techniques
```

## Layering rules

- `Senbazuru.Geometry` depends on nothing in the project. Keep it that way.
- `Senbazuru.Explain` depends on nothing in the project either, and every layer
  that has an error type may import it. That is the price of one name for
  "print this error": the class has to sit below the error types rather than
  beside them, which is also why it holds no error type of its own. It does not
  reopen the rule above — `Senbazuru.Geometry` has no error type, and giving it
  one is the change to argue about, not the import that would follow.
- `Senbazuru.Diagram` must not know what FOLD is.
- `Senbazuru.Origami.*` is what senbazuru knows about paper, as opposed to what
  it knows about drawing. Nothing in it may mention a diagram, a page or a
  colour; it is a second consumer of `Fold.Query`, not a stage on the way to
  SVG.
- `Senbazuru.Render.Svg` must not know what a mountain fold is.
- Only `Senbazuru.Fold.Load` does I/O, reading and writing alike. Everything
  else takes and returns values, which is what makes the rest testable without a
  filesystem. `Senbazuru.Import.*` is no exception: those modules take `Text`
  and return values, and `Fold.Load` is what turns a path into bytes for them.
- **Whatever needs faces asks `Fold.Faces` for them, and does not refuse a
  frame without any.** Most files record none — no `.cp` or `.opx` can — and
  the creases determine them, so `Origami.Folding` and `Render.Gltf` both call
  `Fold.Crossings.withPlanarFaces`, which is one function rather than a pair of
  calls at each backend precisely so a third backend cannot half-apply it. `Render.CreasePattern` deliberately does
  *neither*, and the reason is not golden churn: tracing can *fail* on a
  drawing no amount of cutting fixes — a crease that stops in the middle of
  the paper has no face round it — and a drawing must not stop working because
  its faces cannot be worked out. Filling optimistically, whenever the trace
  happened to succeed, would make the picture of a pattern depend on a property
  of it nobody looking at the page can see.
- **A new input format becomes a `Frame`, and stops there.** `Senbazuru.Import.*`
  may know what FOLD is, because producing a `Frame` is its whole job; nothing
  downstream may know that a frame came from anywhere but a `.fold` file. Where
  a format cannot say something FOLD can — neither `.cp` nor `.opx` has faces —
  the frame simply does not say it either, and the layer above deals with the
  gap the way it deals with a `.fold` file that left the same key out.
- **A sequence source is the stated exception to that: it is a program, not an
  input format.** A [sequence source](glossary.md#fold-sequences) is the text
  file, `.foldseq`, in which an author writes a fold sequence. It cannot become
  a `Frame` at the door, for two reasons. Running it needs the code that folds
  paper, `Fold.Creasing`, `Origami.Folding` and `Origami.Flap`, and reading it
  in `Fold.Load` would drag all of that to the top of the pipeline. And it
  needs a second file, its [sheet](glossary.md#fold-sequences), the paper it
  starts from, which a reader handed one file's bytes has no way to open.

  So the boundary is drawn somewhere else. `Fold.Load` will read a source as
  text and nothing more, and will import no `Sequence` module to do it.
  `Senbazuru.Sequence.*` turns the text into a `Sequence`, runs it into one
  record for each move, and writes the result as an ordinary multi-frame FOLD
  file. **The rule then holds again on the way out:** nothing that reads the
  written file may know it came from a sequence. Whatever needs more than a
  frame can hold reads the records instead, and the design names each such
  reader: the step page, the material study, and the animated export.

  The 3D backend, two rules down, is a stated exception to a different rule,
  and this one is meant the same way: stated, and not a precedent. A format
  that *describes paper*, however unusual, still becomes a `Frame` and stops
  there. Which parts of `Senbazuru.Sequence.*` are built so far is kept in one
  place, the next rule; the whole plan is in
  [PRDs/01-architecture.md](../PRDs/01-architecture.md#31-a-sequence-source-is-a-program-not-an-input-format).
- `Senbazuru.Sequence.*` is layered inside itself, and `Sequence.Syntax` is the
  bottom of it: it imports no project module. A sequence can be written as
  Haskell or as text, and its checker, runner and printer all read the one
  value, so the type they share can live in none of them. The levels planned
  above it are in
  [PRDs/01-architecture.md](../PRDs/01-architecture.md#13-levels-inside-sequence);
  each is recorded here when it is built. `Sequence.Build`, the Haskell way of
  writing one, imports `Sequence.Syntax` and nothing else from the project. It
  may never import a module that knows paper, such as `Fold.*` or `Origami.*`:
  building a sequence hands out names, never geometry, which is what keeps a
  built sequence printable and lets it be checked without being run.
  `Sequence.Pretty` likewise knows no paper: it imports `Sequence.Syntax` and,
  for printing a whole number, `Explain`.
  `Sequence.Error` is level 2, directly above the tree and below both front
  ends, because the parser, the checker and the runner all return its type. For
  the same reason it may not import the printer: a refusal that quotes a fold
  line carries that text as data, put there by whoever raised it.
  `Sequence.Parse`, the text way of writing one, is the builder's counterpart
  and is held to the same rule: it imports `Sequence.Syntax` and
  `Sequence.Error` and no module that knows paper, so reading a source can
  never fold anything. It is the only module that knows megaparsec.
  `Sequence.Check` is on the same level and knows no paper either, which is
  what lets a whole sequence be checked without its sheet. It imports one of
  its own level, `Sequence.Parse`, for the two facts about text it has to
  agree with: what a name token is and which words are reserved. The arrow
  points that way because those are the grammar's facts, and a checker that
  kept its own copy would drift from them. Not yet built: the pass that
  expands shorthand, the runner, the writer, and the reader in `Fold.Load`.
- New output backends (PDF, PNG) become new consumers of `Diagram`, never a
  second traversal of `Frame`. **The one exception is a 3D backend.** `Diagram`
  is two-dimensional — `V2`, no depth — so `Senbazuru.Render.Gltf` consumes
  `Origami.Surface`. The study and `Render.CreasePattern.surfaceDiagram` use
  that representation too. It still must not import `Render.CreasePattern`:
  what the two share — which layer order to use — is
  `Origami.Stacking.layerOrderFor`.

## Testing

Three kinds, used for different things: property tests for the geometry layer,
example tests for decoding, golden tests for whole-document output. Which, and
why each, is in [AGENTS.md](../AGENTS.md#testing).

## Material study

`Origami.Flap` is the first library operation using the motion checks. Its
input is a `Folded` result and crease/face ids from the returned cut pattern.
Removing the selected crease segments identifies the moving component; every
segment must separate moving from stationary paper on one common folded hinge
line. An alternate connection is a refusal requiring a different selection or
coupled angles. `checkFlap` uses `Origami.HingeSweep`
on a normalized mesh and returns an opaque accepted motion. `flapAt` re-folds
the requested angle state, aligns its stationary face and checks that the
result agrees with the hinge path before handing it to the renderers.
`FlapGallery` is only an executable driver; the library imports no study code.
`BlintzSequence` composes five accepted turns on the existing blintz fixture,
carrying angles and endpoint orders onto its material pattern and checking
position continuity at each join. It puts the stationary central face first
before folding, because the folding walk anchors that face. `BlintzGallery`
exports the resulting sequence through the ordinary renderers; neither module
introduces a second contact checker or a general instruction format.
`HelmetSequence` chains three turns with the same handoff policy, using
`prepareFlapAlong` to select the two segments of its diagonal and the paired
material creases of its doubled corners. `HelmetGallery` exports seven
illustrations through those same renderers; see [aligned hinges](notes/aligned-crease-hinges.md).
`HingeSweep.checkSweepWithFlatEndpoints` returns one-sided endpoint contacts
as triangle ids and signs against stationary normals. `Flap` maps them to
source-face orders and checks supplied initial orders on each contact plane.
`checkSweepWithRigidContacts` also verifies explicitly named coplanar pairs with
the same motion. `Flap` supplies these from consistent, same-motion face orders
and preserves those orders in every pose. The strict `checkSweep` entry point
retains the study's existing contact policy. A declared partner's shared hinge
can also support an unjoined stack boundary, while the same plane separation
check still covers the turning interior. Sliding contact remains unsupported.
See [the operation note](notes/checked-flap-operation.md).

`CraneWing` adds four crease segments to the existing crane fixture, chooses
one wing and checks its 90-degree departure. `CraneGallery` exports four SVG,
FOLD and glTF illustrations. The study owns the fixture selection and crease
recipe. `Flap` and `HingeSweep` own the general rule that a hinge may rest on
another layer while its moving interior separates to one side; the departure
order is checked against the supplied starting order.

`study/fold-material/` is a separate executable experiment, compiled and tested
with the project. Its mesh types now live in `Origami.Surface`, while the
experimental formulas and solvers remain outside the library. It generates
sharp and rounded versions of two prescribed surfaces in `FoldMaterial`. `FoldRelaxation` corrects
their material edge lengths; `FoldContact` supplies separation constraints and
checks for violations of the known packet order. The coupled solve treats paper
as having zero thickness; this original adapter handles nearly flat packets.
`FoldBending` assigns rest angles to their material creases and a zero-angle
preference to internal panel edges. `FoldRelaxation.relaxBending` adds those
energies with staged numerical penalties; `BendingGallery` exports a separate
comparison page and measurements. `relaxPinnedHinges` excludes explicitly held
material vertices from the unknowns of the same solve. `WingBending` supplies
a held-root triangular sheet and a strip with a known bent solution;
`WingBendingGallery` compares independent static solves at three resolutions.
`UncreasedSurface` adapts this single uncreased panel to planar triangle faces,
recording joins instead of creases and retaining original material coordinates
and panel ownership in metadata. Both SVG and glTF consume that surface. This
study adapter does not reconstruct multi-panel crease identities or orders.
See [held wing bending](notes/held-wing-bending.md).
`relaxPinnedContact` combines those exact grips with `SurfaceContact`'s existing
directional inequalities. `WingLayers` constructs a connected folded diamond,
preserves its two material panels and root crease in triangle-surface exports,
and supplies distinct grips for the two layers. `WingLayersGallery` publishes
accepted static shapes separately from failed diagnostics. It does not add
motion certification or general crane-body deformation. `CraneSpread` takes
that held-contact solve back to the existing crane, holding its body exactly
while bending the selected wing. `refineSelectedSurfaceWithEdges` divides those
panels densely and splits adjoining triangles at shared material edges;
`buildSelectedSurfaceHinges` retains the original crease targets. The adapter
exports triangle faces with source panel/edge metadata and expands retained
orders relative to the upper triangle's normal. `CraneSpreadGallery` publishes
only accepted static shapes, with a rigid baseline and an incompatible grip.
See [spreading a connected wing](notes/spreading-connected-wing.md).
`CraneRoot` separates the exact root-strip hold from the four authored root
springs, then releases their four neighbouring body panels. Its comparisons
share refinement, material and tip grips; original mountain/valley angles are
checked separately from the soft root preferences. `spreadContactOrders`
expands inherited source orders before selecting those involving free vertices,
so held intermediate panels cannot hide a needed contact requirement.
`CraneRootGallery` adds measured side profiles and retains failed body/grip
attempts as diagnostics. Rendering failures retain complete-sheet inspection
exports separately from physical acceptance. See [the wing-root study](notes/wing-root-holds.md).
`CranePocket` maps the same unchanged crane into five connected material
regions and classifies candidate opening creases. It includes flat edge
incidence as well as physical crease features, because those edges also connect
the regions. `CranePocketGallery` draws original-sheet and folded x-ray maps
through `Diagram` and exports the unmodified FOLD/GLB. It adds no cavity,
pressure or new motion solver; see [the pocket map](notes/crane-pocket-map.md).
`BodyPatch` extracts the mapped body core and both adjoining wing collars as a
free-boundary specimen, preserving inherited order before removing outside
panels. Three exact holds control opening; neck/tail interface landmarks remain
free. It reuses the existing material/contact solver and triangle exporter.
`BodyPatchGallery` separates accepted paper from failed wire diagnostics and
archives checkpoints; no production solver or whole-crane behavior changes.
See [the coupled patch](notes/coupled-body-patch.md).
`CraneBody` selects the mapped candidate creases incident to the small
`CraneRoot` free patch and changes only their angular preferences. It keeps
original crease targets separately from edited spring targets, so the strict
and selective acceptance policies measure the same reference. `CraneBodyGallery`
publishes matched controls, complete diagnostics and only accepted 3D models.
It introduces no solver changes; see [angle gates and springs](notes/body-angle-preferences.md).
`CraneInternal` makes matched boundary/contact controls around two retained
body folds, preserving shared material ids and all independent checks.
`CraneInternalGallery` records rejected-trial energies and groups crossing
reports by original panel pair. `FoldRelaxation.diagnosePinnedContact` adds the
existing bounded trial audit without changing the held-contact solve;
`continuePinnedContact` resumes only its final penalty stage to distinguish
an exhausted budget from a failed search. Neither provides a physical path.
See [the internal-crease diagnosis](notes/internal-crease-diagnostic.md).
`ClosedCrease` constructs two joined bending panels with exact rational side
profiles. Their height difference independently measures contact and order;
`ClosedCreaseGallery` compares that reference with force gaps and the library
checker, and can recheck saved crane endpoints without solving them again.
The [near-crease note](notes/near-closed-crease.md) explains the corrected plane
section and the remaining tolerance-sized crossing. These are prescribed
static controls, not new material equilibria.
`CreaseCorrection` holds that lower reference fixed while its upper panel
settles with or without contact forces. Its exact triangle clipping measures
the corrected shape without assuming the upper remains a side profile.
`CreaseCorrectionGallery` publishes before/after diagnostic surfaces and
negative-gap plots, separating numerical acceptance from exact order.
[The correction note](notes/contact-correction-at-a-crease.md) records the
remaining finite-penalty residual; the solver itself is unchanged.
`ContactQuadratic` uses `SparseSolve`’s material factor for a small constrained
step, with a dense working set of touching inequalities. It knows no paper.
`CreaseInequality` supplies exact clipped contact weights, restores nonnegative
stored gaps against the fixed lower panel, and measures material energy after
repair. `CreaseInequalityGallery` compares the unchanged penalty baseline,
initial repairs and constrained endpoints. [The constraint note](notes/nonnegative-crease-contact.md)
records why both methods need full endpoint checks and why this fixed-panel
experiment does not yet handle general moving contact.
`CreasePairContact` measures exact directional gaps between both current
triangle surfaces, retaining the derivatives of moving overlap corners.
`CoupledCrease` releases both interiors beside the held shared crease and
repairs penetration by moving them apart. It reuses `ContactQuadratic` and
the material rows extracted from `CreaseInequality`; the fixed-panel solver
keeps its original equations. `CoupledCreaseGallery` compares both panels'
displacements, independent endpoint checks and mesh refinement, reusing the
constrained-step report. [The two-panel note](notes/coupled-crease-contact.md)
records the symmetric controls and the known-order restriction. These remain
study modules; no production surface or material solver changes.
`UnequalCrease` keeps the crease-adjacent strips and outer edges held while
changing only an upper grip or adding explicit upper bend controls. The
control strength is per material line length, so refinement does not double
it. `solveCoupledWith` exposes a contact-off diagnostic with the same material
equations and holds; `solveCoupled` still enforces order by default.
`UnequalCreaseGallery` reuses the endpoint checks and matching-material
refinement comparison, then compares each panel's response and exports
side projections and magnified gap marks. The
[unequal-control note](notes/unequal-crease-controls.md) explains why holding
the crease orientation makes the contact-on/off comparison useful.
The opt-in refinement command uses independent profile and width subdivisions
from `ClosedCrease`. `CreasePairContact.samplePairGaps` samples fixed projected
locations for comparison; the complete overlap audit still decides validity.
The gallery retains unconverged endpoints and separates sampled near-contact
regions from exact maximum gaps. [The refinement note](notes/unequal-crease-refinement.md)
records which changes are observed before returning to the crane body.
The [fine-mesh solver study](notes/fine-crease-solver.md) exposes explicit
length schedules in `CoupledCrease` and an opt-in single-equality exchange in
`ContactQuadratic`. The existing entry points retain their original policies.
`coupledRows` reconstructs a recorded inner problem for replay; the gallery
compares the two changes independently and saves those equations and residuals.
The opt-in [combined refinement](notes/combined-crease-refinement.md) reuses
the original five-mesh grid, now including `4×2`, with both changes on every
mesh. `UnequalCrease.bendBreakdown` measures passive and imposed spring
contributions separately, including achieved turns at each control segment.
The gallery records these diagnostics and the common solver settings alongside
each result; the comparison does not change the material/contact solver.
The [band-loading comparison](notes/distributed-bend-preference.md) also lives
in `UnequalCrease`: a fixed material interval determines preferred turns and
spring stiffnesses, normalized against the original three-line load's total
turn and flat-paper control energy. `bandInterval` clips rational interval
bounds before conversion so refinement cannot invent a microscopic boundary
control. The opt-in gallery retains both loading styles and their contact-off
comparisons without changing `CoupledCrease` or its acceptance policy.
The [band contact replay](notes/several-contact-exchanges.md) adds an opt-in
progressive exchange to `ContactQuadratic`: each replacement reduces summed
squared negative gaps, while the final original-row residual checks stay
unchanged. `constrainedStepDetailed` supplies per-contact residuals, source-row
mapping and an exchange record; the ordinary entry point discards that lazy
detail and retains its compact report. `UnequalCreaseGallery` saves both
failed inner problems and compares complete solves on the two affected meshes.
The [fine-band length comparison](notes/fine-band-length-enforcement.md)
reuses the same solver with an extra penalty stage, retaining its baseline.
`UnequalCreaseGallery` measures every edge's original/current length and
restarts the failed contact-off endpoints at unchanged and larger weights.
Replay coordinates and step histories keep the numerical result inspectable;
independent contact checks still reject crossing endpoints.
The [combined band grid](notes/combined-band-refinement.md) applies both
isolated repairs to every mesh and control through another opt-in gallery
entry point. It reuses the same fixtures, measurements and solver; the old
commands retain their policies and reproducible failures. The
[`8×1` length follow-up](notes/band-refinement-8.md) reuses that gallery and
shares its policy constructor, comparing three controls over two successive
length doublings without adding a new solver path. The
[`8×2` decision study](notes/band-refinement-8x2.md) reuses that same policy,
adding display comparisons of the measured position, opening and energy
changes against explicit study targets. These do not change endpoint
acceptance or claim numerical robustness.
`PrescribedBend` places flat, fixed-corner and cylindrical probes on those
existing meshes and measures per-edge lengths and per-hinge angular costs.
`PrescribedBendGallery` exports shared-scale side profiles, FOLDs and raw
measurements, including the original-grip displacement and exact known-order
contact audit. It calls no optimizer or repair and does not change the material
objective. The [prescribed-bend note](notes/prescribed-bend-energy.md) separates
sampling a smooth surface from preserving every straight material edge.
`BandBoundary` compares the original band controls with fractional actual turns
on those same prescribed shapes. It exposes an equivalent full-angle spring
for checking both energies and derivatives, without changing default fixtures
or calling a solver. `PrescribedBendGallery` retains both policies' per-interval
records and draws their material support. The [boundary note](notes/band-boundary-fractions.md)
records the constant-cylinder check and the still-changing fixed-corner control.
`bandBoundaryFixture` now selects either encoding explicitly for the small
`--boundary-solves` experiment. The existing gallery and solver run both rules
with identical holds and material and retain both band costs on each endpoint, paired
endpoint displacements and width comparisons within each rule. Original
commands retain their policies; [the solve comparison](notes/fractional-band-solves.md)
records the endpoint evidence and remaining refinement question.
`--boundary-length` reuses those rule-specific fixtures and reports for a
fixed-width length doubling. Comparison pairs keep the boundary rule fixed;
the browser selects saved maps and counts category changes from the same
projected samples. No new mechanics or acceptance policy is introduced.
`BendLocations` loads these saved endpoints against the authored material and
reports every spring at its material edge midpoint, with transverse turns
normalized by strip spacing. `BendLocationsGallery` rechecks geometry, binds
source convergence and costs, and draws paired maps and cumulative/rate plots
through `Diagram`. It calls no optimizer or repair. Fixed regions are discrete
spring accounting, not area densities; see [the location study](notes/bending-energy-locations.md).
`OuterStrip` selects nested columns from the existing rational starting profile,
rebuilds the material cells and springs, and assigns band supports using the
actual neighboring columns. The two uniform controls reproduce their existing
fixtures exactly. `OuterStripGallery` reuses the coupled solver, independent
checks, spring bookkeeping and SVG plots for the four-mesh comparison. It
keeps failed states and original solver policies; [the outer-strip study](notes/outer-strip-refinement.md)
separates local resolution effects from material convergence.
`OuterContinuation` validates the two exhausted archives and replaces only
starting positions, retaining the authored rest material, holds and springs.
`OuterContinuationGallery` reuses `OuterStripGallery.writeOuterState` for
identical measurements and exports, preserves the original files, and runs
at most 40 more iterations at the same final weight. See the
[continuation study](notes/outer-strip-continuation.md) for the outcomes and
why a converged contact-off endpoint still cannot pass.
`MatchedEnergy` pairs passive bends by material edge endpoints and accounts for
shared, added and removed locations. Shared edges retain both coefficients and
turns because their neighboring triangles can change. `MatchedEnergyGallery`
binds both matched-rule archives, reuses fresh outer-strip measurements, and
draws signed maps and common-scale plots without a solver or repair. See
[the matched-energy note](notes/matched-energy-locations.md).
`UnevenBend` prescribes two bend profiles on the same four material meshes,
with exact surface samples or full-length segments. Its interval formulas
separate uncovered boundaries from averaging across the flat-to-curved start.
`UnevenBendGallery` measures those references, old-grip displacement and exact
known-order contact, exporting FOLD and shared-scale SVG plots without an
optimizer or repair. See [the prescribed comparison](notes/prescribed-uneven-bends.md).
`HeldBend` constructs a smooth arc-and-straight reference reaching the original
grips. It also fits two curve parameters per mesh to make full-length polygon
approximations reach those grips, using geometric endpoint derivatives rather
than the material solver. `HeldBendGallery` retains raw fit residuals, grip
copy sizes, diagnostic controls and separate energy components; all final
edges and exact touching order are checked. See
[the held-reference note](notes/prescribed-held-bend.md).
The same modules also compare a fixed cubic tangent transition, with analytic
parameter derivatives and mesh-independent numerical integration. The original
circular exports remain reproducible; both families share measurement and
plotting code. See [the smooth-transition control](notes/smooth-held-bend.md).
`BendRefinement` samples those same common curves on a bounded, nested mesh
ladder without fitting them again. `BendRefinementGallery` measures each
approximation through the existing edge, spring and contact checks and compares
its cost with the analytic integral. Full-length segments keep their grip drift;
samples keep their length error. No solver policy or library API changes.
Its validated `ReferenceGrid` also accepts nonuniform material columns, keeping
construction and measurement shared. `TransitionRefinement` allocates equal
triangle budgets using fixed windows around the curvature joins, with no energy
feedback. It compares whole profiles on the union of their material columns;
this relies on profiles repeating unchanged across width.
`TransitionRefinementGallery` reuses `BendRefinementGallery.writeReferenceState`
and adds common-scale cost and column-placement plots. See
[the placement comparison](notes/transition-refinement.md).
The same modules add whole-bend density without reading measured energy.
Both galleries share the measurement and plotting implementation; the three-way
comparison adds every pairwise profile displacement while preserving the
earlier gallery's data and drawings. See
[the whole-bend comparison](notes/whole-bend-refinement.md).
`HeldEquilibrium` turns the fixed smooth reference into four bounded held-panel
fixtures. The original grips are constraints, while the curve is only a seed;
passive springs keep their flat rest angles. `HeldEquilibriumGallery` reuses
`CoupledCrease` without changing solver policy and checks convergence separately
from valid paper. Its whole-sheet comparisons use material-triangle overlaps,
because solved panels need not repeat their profile across width. See
[the equilibrium comparison](notes/held-panel-equilibrium.md).
`HeldCosts` binds saved equilibria to their original policy and defines fixed
material-distance bins plus transverse-angle profiles. `HeldCostsGallery`
reuses `MatchedEnergy` for material-edge pairing and the shared
held-state measurement/export path for fresh checks, without invoking a
solve. Its [signed accounting](notes/held-bending-costs.md) includes replaced
edges and all edge directions; bins describe spring locations, not densities.
`HeldConfirmationGallery` validates the four original held-panel archives before
writing or solving, then restarts only the two finer endpoints with an opt-in
`CoupledCrease.solveCoupledUntil` movement stop. It keeps the authored rest
material and all paper checks, reusing the held-state exporter, fixed cost bins
and material-overlap comparisons. The [confirmation](notes/held-endpoint-confirmation.md)
separates numerical stopping sensitivity from mesh differences; it changes no
default solver policy.
`HeldRefinement` checks that saved 256 endpoints carry both their original
six-stage history and the tighter confirmation. `HeldRefinementGallery`
remeasures both before starting two opt-in 512-triangle solves. It reuses
`HeldConfirmationGallery`'s measured endpoint exporter and whole-material
comparisons, plus the same passive-cost pairing and fixed bins. A failed
primary solve cannot receive a confirmation, and a failed confirmation cannot
enter an eligible refinement comparison. See
[the fixed-width refinement](notes/held-panel-refinement.md).
`HeldLayoutCosts` validates both saved resolutions and accounts for each unique
length edge, keeping the shared crease separate. `HeldLayoutCostsGallery`
reuses those archive-history checks, measured endpoint exports and cost plots
to compare equal-budget layouts without moving paper. Its
[location analysis](notes/held-layout-costs.md) keeps passive and length costs
separate, including replacement edges and region/direction cross-tabulations.
`IllustrationComparison` intersects material triangles from two saved meshes
to bound their positional difference over the entire sheet, then provides
shared drawing extents and diagnostic masks. `IllustrationGallery` reads
the saved endpoints, reruns geometry checks and calls the existing SVG and
projected-visibility pipeline. It performs no solve and does not grade the
renderer fallback when visibility is unresolved. The browser's small
`illustration-metrics.js` compares sampled pixel masks; geometry and SVG
projection remain in Haskell. `IllustrationComparison` also measures exposed
polygon area and maximum vertical column span; isolated layer masks let the
browser test sampling density and phase without colour compositing. See
[the illustration study](notes/illustration-scale-refinement.md) and
[thin-layer follow-up](notes/thin-layer-visibility.md).
`IllustrationDistance` bounds point-to-region distance over unions of filled
convex polygons. It is study-only geometry: it imports no paper or rendering
modules, and returns explicit empty/missing states and finite work-limited
intervals. `IllustrationGallery` supplies projected layer regions and draws
lower-bound witnesses through `Diagram`; the browser only displays the bounds.
It also bounds area beyond a distance budget by classifying whole source
triangles, retaining unclassified area at the work limit. Source pieces must
have disjoint interiors; no area threshold changes the review verdict. See
[the distance study](notes/exposed-layer-distance.md) and
[area follow-up](notes/exposed-area-budget.md).
`IllustrationDistance` can retain the definite and unclassified triangles
behind each area bound. `IllustrationHighlights` partitions them into fixed
page-coordinate tiles, builds unstroked highlights and separate locator ink,
and clips 32× details before SVG formatting. The gallery writes these assets
and their unrounded JSON; the browser selects assets without computing
geometry. See [the location study](notes/exposed-area-highlights.md).
`Render.Gltf` passes its coordinate quantum to `Render.PaperMesh`: visibility
resolves near-coplanar groups at packing precision, then reattaches clipped
points to their original material panels. Contact checks keep their own
geometric tolerance.
`SparseSolve` owns
conjugate gradients and a sparse factor of the coupled normal equations for
held-contact solves. The factor accelerates shared layer movement; the
original row operator still verifies the linear residual. `EquilibriumCheck`
retains that residual and the full proposed movement for the gallery. See
[the coupled-solve note](notes/coupled-touching-layer-solve.md) for the
resolution comparison and memory limits.
`refineSurfaceWithEdges` preserves source edge
ids through subdivision, and `buildSurfaceHinges` attaches explicit signed
rest-angle controls to them. Diagonal and kite controls use `relaxHinges`
without contact forces; `Origami.Contact.checkTriangleContact` independently
checks the resulting triangles and source-panel orders. `SurfaceContact` adds
separation residuals and moving-overlap derivatives for supplied directional
orders; `relaxSurfaceContact` couples them to the same length/angular solve.
`ContactExample` constructs a connected opposing-flap control for tests and the
gallery. Its small numerical clearance applies only to unjoined source panels.
`SurfaceContact.overlapCandidates` also discovers projected triangle overlaps
without a pair list. `ContactDiscovery` infers order from a separated reference
and guards later overlaps against that fixed relation; `relaxDiscoveredContact`
uses it in the same numerical solve. Ambiguous references and new unrelated
pairs are refused during correction. `observeContactPose` can extend that
history at a supplied approach pose after checking old orders, new encounters
and independent triangle contact. It records additions transactionally; solver
trials cannot change them. The shared `Origami.HingeSweep` bounds triangle projections over a
specified fixed-axis rotation, subdividing unresolved angular intervals and
refusing exhausted work limits. `observeContactSweep` checks that motion before
accepting its endpoint; `ContactExample.opposingApproach` uses it for each
right-flap rotation. Raw pose observations and the original numerical solver
modes still have no checked motion between them. The independent triangle check also judges
each accepted endpoint. See [the sweep note](notes/hinge-sweep-contact.md) for the
shared-hinge exception and numerical scope.
`SurfaceContact.prepareTriangleContact` also accepts local lower/upper triangle
requirements without changing their source-panel ownership. `SelfContactExample`
uses these on the two ends of one curled panel. `FoldBending.buildPanelHinges`
supplies passive flatness; separate `BendControl` springs impose its curl without
creating creases. The same `relaxSurfaceContact` solve corrects its endpoint,
and `Origami.Contact.checkLocalTriangleContact` independently checks every pair,
including neighbors. See [local panel contact](notes/local-panel-contact.md).
`LocalContactDiscovery` scans nearby triangles within panels, extends partners
across connected flat reference patches, and freezes their order for
`relaxLocalContact`. Its reference search distance is separate from numerical
clearance; an unknown pair reaching contact blocks a trial. It does not update
history during bending in its fixed mode. `relaxLocalHistory` instead threads
proposed extensions through accepted solver steps and all penalty stages;
rejected trials leave its history unchanged. See [local discovery](notes/local-contact-discovery.md)
and [growing history](notes/growing-local-contact-history.md).
`CorrectionSweep` separately bounds triangle separation and nondegeneracy over
straight numerical vertex paths, using exact rational Bernstein coefficients.
`relaxSweptLocalHistory` gates accepted corrections with it before growing the
contact history, and returns an audit of accepted paths. A separate bounded
`TrialDiagnostics` records first/last refusals and exhausted line-search stages;
none of that data enters accepted contact state. A blocked stage advances its
penalty or returns unconverged, without repeating identical work. See
[rejected trials](notes/rejected-bending-trials.md). `CorrectionExample`
supplies a connected square's unsafe shortcut and a safe strip-opening control.
This verifies an optimizer path, not a length-preserving folding instruction;
the guarded closing strip reports its measured convergence. See [the correction note](notes/checking-numerical-corrections.md).
`DirectionalDistance` measures distance to violating a retained triangle order;
`SurfaceContact` converts that distance into a barrier residual and gradient.
`LocalContactDiscovery` keeps its unknown-pair guard around that energy, while
`relaxBarrierLocalHistory` uses it separately from the raw endpoint contact
measurements. The accepted-motion and history policies are shared with the
older strict mode. See [directional contact distance](notes/directional-contact-distance.md).
Mechanics remain in the study, not the shared `Origami.Surface` representation.
`Main` uses `Camera`, `Diagram` and `Render.Svg` for baseline previews. Corrected
meshes use the depth-buffered viewer because the SVG painter assumes the very
layer order those meshes can violate. Indexed OBJ and FOLD exports inspect the
same samples. Nothing in the library imports these study modules; see
[the study](../study/fold-material/README.md) before treating its double fold as
a physically valid model.

`StudyCase` adds authored rigid cases beside those controls. It consumes a FOLD
`Frame` and an explicit angle state, reuses `Origami.Folding`, and constructs an
`Origami.Surface` from the returned cut pattern and folded frame. The library's
`refineSurface` builds its shared triangle mesh. The gallery's JSON manifest is read
by the study executable; it is not a new library input format. Panel ids travel
with the mesh so the viewer can split lighting at arbitrary crease directions.
These cases do not use the packet-specific contact solver. `Origami.Contact` checks
their whole convex panels for 3D crossings and for declared above/below order.
`StudyCase.buildCasePose` resolves panel names from points on the original sheet,
so the declarations survive face renumbering. A case may also anchor a stationary
panel by a material point instead of holding the largest panel still. Resolved
orders and feature-edge ownership let the viewer break depth ties after contact
passes, without changing exported material. Reports are exported and displayed;
they do not change the prescribed pose or certify motion between states.

`BasicBases` constructs six additional traditional flat endpoints from material
crease segments, using the production crossing cutter and face tracer.
`BasicBaseGallery` verifies their material and contact measurements and passes
the folded frames and solved orders to `Render.CreasePattern` for front/reverse
SVGs. The fixture tests independently identify their material landmarks and
check visible coverage. These modules prescribe endpoints only, with no new
fold-motion machinery in the library. The frog folding guide adds five flat
checkpoints, including an open-page arrangement that exposes the working
petal. `BasicBaseGallery` uses the closed and loose material tips to orient
each packet, then exports an ordinary FOLD sequence. `Render.Steps` draws its
five numbered figures through one camera at one scale, as for the bird page.

The first production handoff is `examples/bird-base-sequence.fold`.
`StudyCase.buildCaseSequence` writes unrefined panels and ordinary coplanar
`faceOrders` after contact passes. The CLI reads that file without importing
the study. `Render.Projected` uses actual depth to order separated panels in
each view, then reuses `Origami.Visible` for visible regions and edges; it
knows nothing about bird petals or the study manifest.

`PetalCertificate` is an exact, fixture-specific check of the bird petals'
known paths. It keeps polynomial coefficients as two rational numbers
representing `a + b*sqrt(2)`, proves material edge-length identities, and bounds
panel separation over the whole turn. Flat endpoints separately check approach
and departure against declared order. `CheckedPetal` binds that certificate
to the bird fixture and rebuilds requested poses through `Folding`, comparing
them with the ideal path. `CheckedBird` continues to the back petal and final
press, checking both joins and retaining the first petal's material and orders.
The stationary base plane is an additional separating-plane candidate, and
endpoint overlap checks first establish coplanarity because the held front
petal is in the air. The same certificate machinery now checks the initial
square-base collapse with a different positive denominator. `CheckedBird`
compares its angle-derived poses and verifies the join to the first petal.
Future landing orders apply at contact, while separated collapse panels use
intersection checks without imposing that order on their shadows.
`PetalGallery` supplies twenty-three SVG/FOLD/glTF states and
above/below SVG views through the existing renderers. These study modules do not extend the library's
single-hinge `Flap` API or claim a general coupled-angle solver.

The shared representation introduced by [#146](https://github.com/avalonalex/senbazuru/issues/146)
is `Origami.Surface`. It stores material identity, current positions, crease
topology and optional physical thickness. Folding provides `Surface V2` with a
known original-sheet map; a standalone folded file can provide only
`Surface (Maybe V2)`. Its missing coordinates stay unknown unless the file
supplies the study's `senbazuru:material_coords` extension. The surface owns
positions once and reconstructs its FOLD frame when a consumer needs one.

`surfaceDiagram` and `renderSurfaceGlb` accept this shared surface. The glTF
FOLD entry point also constructs it after preparing faces. The six-base SVG
gallery and frog guide now consume surfaces directly. The study's mesh types
and refinement no longer have separate implementations.

`Render.PaperMesh` groups coplanar panels and asks `Render.Projected` for
visible pieces from each side. Those pieces are attached back to their source
panels with weighted material vertex references, then packed by `Render.Gltf`.
The default GLB includes this visible scene and a complete scene; neither
applies per-face lifting. The SVG visibility fallbacks remain separate drawing
policies. [The export note](notes/visible-paper-mesh.md) records the metadata
and limits; [the design note](notes/connected-paper-surface.md) records later
bending and opening work.
