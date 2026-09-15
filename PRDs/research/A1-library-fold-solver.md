# A1: the library's rigid fold solver as the substrate for a sequence interpreter

Scope: what a fold-sequence interpreter (embedded DSL, file language, or the
material study consuming either) would run on in `src/Senbazuru/Origami/*`,
`src/Senbazuru/Fold/*` and the renderers. Read on branch
`docs/prds-sequence-language` at `568dcb6`. Nothing was built or run except
`jq`, `grep`, `git` and `gh issue view`. No external web sources were
consulted for this slice, so none are cited as fact.

Terms used below: a *crease pattern* is the flat sheet with its fold lines
drawn on it; a *folded form* is where that paper ends up; a *fold angle* is
how far the paper turns at a crease (0 is flat, +180 is a valley closed flat,
-180 a mountain closed flat); *material coordinates* are where a point was on
the unfolded sheet (`docs/glossary.md:81`); a *face* or *panel* is one flat
region between creases.

## Summary

The library's model state is **fold angles on a cut crease pattern**, not
positions. `foldFrameWith` turns a pattern plus angles into a `Folded` (folded
form, the cut pattern the answer refers to, and one rigid motion per face).
`Surface V2` is the shared hand-off to renderers: topology, positions,
material coordinates, optional thickness and directional layer requirements.

There are exactly three "moves" in the library today: add creases on a flat
sheet (`creaseAllAlong`), add creases through the layers of a flat-folded model
(`creaseThroughLayers`), and turn one flap about one fixed hinge line with a
whole-path contact check (`prepareFlapAlong` / `checkFlap` / `flapAt`). Turning
the model over is a rigid `transformSurface`, not a move. There is no library
operation for coupled multi-axis motions (collapse, petal, rabbit ear, reverse
fold); the study has fixture-bound angle formulas and certificates for some.

The naming problem is real and specific: adding creases re-traces every face
and renumbers edges, drops `faceOrders`, and changes which face the fold holds
still. Vertex ids and material coordinates survive; edge and face ids do not.
A DSL must name paper by material geometry and resolve ids afresh each step.

## Findings

### (a) What "the state of a folded model" is today

**1. Angles are the state; positions are derived.** `foldFrameWith` reads one
angle per edge (`Folding.hs:362`, `foldAnglesOf` at `Folding.hs:507-532`),
walks a spanning tree of faces composing one rotation per crease
(`Folding.hs:572-638`), and places vertices from the per-face motions
(`Folding.hs:776-817`). The folded frame it writes carries the angles it used
even where the input had none (`Folding.hs:228-237`, `383`). The project note
`docs/notes/fold-angles-are-the-state.md` states the consequence: interpolating
positions tears paper, and interpolating all angles linearly usually leaves
the loop-closure surface. Newcomer trap: if `edges_foldAngle` is absent, every
`M`/`V` edge folds to -180/+180 at once (`Folding.hs:529-532`). A state that
means "precreased but open" must therefore carry **explicit** angles; the
checked recipes start by writing all zeros (`study/fold-material/BlintzSequence.hs:42`,
`HelmetSequence.hs:41`).

**2. `Folded` has three fields and two frames that disagree on purpose.**
`data Folded = Folded { foldedFrame :: !Frame, foldedPattern :: !Frame,
foldedPlacements :: !(IM.IntMap Rigid) }` (`Folding.hs:283-324`).

- `foldedPattern` is the input *after* `withPlanarFaces` cut crossings and
  traced faces (`Folding.hs:351`, `390`). Face, edge and placement ids refer
  to it, not to the frame the caller passed in (`Folding.hs:286-301`).
- `foldedFrame` has the same vertex/edge ids but moved coordinates, explicit
  `edgesFoldAngle`, rings rewritten counterclockwise, `faceOrders` re-signed
  for every rewound second face, `foldedForm` in its classes, and
  `frameExtras = mempty` (`Folding.hs:380-389`, `reorient` at `482-486`,
  `foldedClasses` at `398-400`).
- The doc comment warns that the two frames can carry opposite `faceOrders`
  signs and different ring start/direction, and says to take both faces and
  orders from `foldedFrame` (`Folding.hs:303-315`).
- `foldedPattern`'s `edgesFoldAngle` is the file's (possibly empty) array;
  only `foldedFrame`'s is guaranteed explicit (`Folding.hs:383` vs `390`).
- The `Folded` constructor is exported (`Folding.hs:80`), so a caller can forge
  one; `Flap` defends by re-folding and comparing (`Flap.hs:169-181`,
  `FlapStartMismatch`).

**3. `Surface material` is the renderer hand-off, with a hidden constructor.**
Fields: `topology :: Frame` (coordinates stripped), `storedSamples ::
[Sample material]` (one material value plus a `V3` position per vertex id),
`materialThickness :: Maybe Double`, `layerRequirements :: Maybe (V3,
[(FaceId, FaceId)])` (`Surface.hs:115-123`); only the type name is exported
(`Surface.hs:26`). `surfaceFromFolded :: Folded -> Either SurfaceError (Surface
V2)` takes material coordinates from the cut pattern and positions from the
folded frame, and refuses if they disagree on graph or the pattern is not at
z = 0 (`Surface.hs:201-210`). `surfaceFromFrame :: Frame -> Either SurfaceError
(Surface (Maybe V2))` for a file: material is known only for a flat crease
pattern, or from the project's own `senbazuru:material_coords` key
(`Surface.hs:179-191`). The `Maybe` exists so a folded file's x/y cannot be
mistaken for undeformed material (`Surface.hs:15-19`); `requireMaterialCoordinates`
is the only way from `Maybe V2` to `V2` (`Surface.hs:215-222`). Constructing a
surface validates references only; it does not certify lengths, angles or
contact (`Surface.hs:21-24`). Its `topology` keeps `edgesFoldAngle`,
`faceOrders` and the `foldedForm` class of the folded frame
(`Surface.hs:237`, `240`).

**4. Two kinds of layer information, and a newcomer will conflate them.**

- `faceOrders` (FOLD): `[f, g, s]` with `s` measured against **g's normal**,
  which is defined by g's ring winding (`Types.hs:342-357`; `Layers.hs:23-47`).
  Because the sign is paper-relative, a rigid turn of the whole model
  (including turning it over) leaves every order valid. `withFaceOrders`
  range-checks and stores them, dropping `frameExtras` (`Surface.hs:260-263`).
  They describe coplanar touching paper only (`Surface.hs:257-259`;
  `StudyCase.hs:187-191` exports only coplanar-contact pairs).
- `layerRequirements`: a direction plus lower/upper face pairs that may
  constrain panels that are apart (`Surface.hs:119-121`, `306-312`).
  `transformSurface` rotates the direction with the model (`Surface.hs:294-296`).
- `layerOrderFor :: Budget -> Frame -> Either FoldError (Maybe [FaceOrder])`
  returns the frame's own orders, or solves them only for flat-folded models
  with convex faces, returning `Nothing` otherwise (`Stacking.hs:386-400`;
  header `Stacking.hs:18-29`). A state with paper in the air gets its orders
  only from a checked flap's endpoint contacts (`Flap.hs:290-301`) or from a
  study declaration (`StudyCase.hs:121-147`).

**5. What the checked recipes thread from one move to the next.** Blintz and
helmet do the same thing (`BlintzSequence.hs:58-75`, `HelmetSequence.hs:55-72`):

1. Take the accepted endpoint `end :: Surface V2 <- flapAt motion 1`.
2. Build `nextPattern = (foldedPattern start) { edgesFoldAngle = edgesFoldAngle
   (surfaceFrame end), faceOrders = faceOrders (surfaceFrame end), frameExtras
   = mempty }`.
3. `next <- foldFrameWith nextPattern`.
4. Refuse if refolded positions differ from `end` by more than `1e-12` of the
   sheet span.

So the threaded state is: **the cut pattern (material coordinates, graph,
assignments) + explicit angles + faceOrders**, with the anchor fixed by face
order. Dropped: `frameExtras` (every transform drops them: `Folding.hs:388`,
`Surface.hs:263`, `292`, `Creasing.hs:267`, `Crossings.hs:314`), the folded
coordinates (derived), and the `foldedForm` class. The reason for not
re-using the folded frame is concrete: its class makes `foldFrameWith` refuse
it with `AlreadyFolded` (`Folding.hs:338-339`), and its coordinates are not
material (`docs/notes/chaining-checked-folds.md`). `CheckedBird` also checks
material coordinates and resolved layer requirements at joins
(`CheckedBird.hs:139-146`).

**6. A latent winding hazard in step 2 above.** Orders are copied from the
folded frame (counterclockwise rings) onto `foldedPattern` (the file's rings).
If the file wound a face clockwise, the next `foldFrameWith` re-winds it and
flips its orders again (`Folding.hs:353-357`, `385`), which would invert those
layers. `StudyCase.buildPoseAt` avoids this by first copying the folded
frame's rings into the pattern (`StudyCase.hs:155`), after which re-winding is
a no-op. Measured with `jq`: `blintz-base`, `bird-base` have no
`faces_vertices` (so faces are traced counterclockwise, `Faces.hs:41-47`), and
`helmet-base`, `quarter-fold`, `crane` have 6, 4 and 72 faces with zero
clockwise rings. No current fixture triggers it; an interpreter should
normalise rings once at initialisation.

### (b) Existing operations that could be primitive moves

| Operation | Exact signature | Preconditions / behaviour | Errors |
| --- | --- | --- | --- |
| Fold to angles | `foldFrameWith :: Frame -> Either FoldingError Folded` (`Folding.hs:331`); `foldFrame :: Frame -> Either FoldingError Frame` (`272`) | Input must be a crease pattern (`338`); cuts and traces first (`351`); faces non-degenerate; angles finite; loops close | `FoldingError` (`Folding.hs:123-171`), wraps `FoldError` |
| Crease a flat sheet | `creaseAlong :: V2 -> V2 -> Assignment -> Frame -> Either FoldError Frame` (`Creasing.hs:90`); `creaseAllAlong :: [(V2, V2, Assignment)] -> Frame -> Either FoldError Frame` (`138`) | Not a folded form (`148`); each end meets an existing edge or corner (`186-190`); nonzero length; no repeated pair; batch refusals are order-independent (`116-120`); ends to new points are interned to one vertex (`109-114`) | `FoldError`: `SheetIsFolded`, `CreaseEndMeetsNothing`, `CreaseWithoutLength`, `CreaseRepeated`, `ArrayLengthMismatch`, plus anything `withPlanarFaces` refuses |
| Crease through layers | `creaseThroughLayers :: V2 -> V2 -> Assignment -> Frame -> Either ThroughError Frame` (`ThroughLayers.hs:227`) | Input is a pattern **with angles**; folds it internally (`229`); result must be flat (`234`); ends not strictly inside any face (`241-247`); every face creased; assignment flipped per face-down layer (`296`, `327-340`); returns a **pattern**, never a folded form | `ThroughError` (`ThroughLayers.hs:111-176`) |
| Cut + trace | `withPlanarFaces :: Frame -> Either FoldError Frame` (`Crossings.hs:150`) | A frame that records faces is returned untouched (`Crossings.hs:128`; `Faces.hs:136-149`) | `FoldError` (`EdgesCross`, `EdgesOverlap`, `CreaseBridge`, `SheetInPieces`, ...) |
| Prepare a flap turn | `prepareFlap :: EdgeId -> FaceId -> Double -> Folded -> Either FlapError FlapMotion` (`Flap.hs:154`); `prepareFlapAlong :: [EdgeId] -> FaceId -> Double -> Folded -> Either FlapError FlapMotion` (`162`) | `Folded` must be exactly what `foldFrameWith` returns (`169-181`); ids from `foldedPattern`; travel finite, at most 360 degrees (`165`); each segment an `M`/`V`/`U` edge with two faces (`187-191`); removing the segments must separate the moving side (`199`); all segments on one line in the folded shape (`215`); orders retained only within one motion group and plane (`223-233`) | `FlapError` (`Flap.hs:98-122`) |
| Check it | `checkFlap :: SweepSettings -> FlapMotion -> Either FlapError CheckedFlap` (`Flap.hs:249`) | Interval check over the whole turn; endpoint orders checked (`273-280`, `303-312`) | `FlapCollision`, `FlapUnresolved`, `FlapEndpointOrder`, `FlapSweep` |
| Pose it | `flapAt :: CheckedFlap -> Double -> Either FlapError (Surface V2)` (`Flap.hs:290`); `flapCheck :: CheckedFlap -> SweepCheck`; `flapMovingFaces :: CheckedFlap -> [FaceId]` | Progress in [0, 1]; each pose re-folded from angles, aligned to the stationary face, compared with the swept path (`338-352`) | `FlapInvalidProgress`, `FlapPathMismatch`, nested |
| Lower-level hinge | `prepareSweep :: V3 -> V3 -> Double -> [Int] -> MaterialMesh -> Either SweepError HingeSweep` (`HingeSweep.hs:146`); `checkSweep`, `checkSweepWithFlatEndpoints`, `checkSweepWithRigidContacts`, `checkSweepWithLayerContacts` (`215-241`) | One fixed axis, radians, at most one full turn (`149`); no triangle mixes moving and fixed vertices off-axis (`173`) | `SweepError` (`HingeSweep.hs:114-127`) |
| Move the whole model | `transformSurface :: Rigid -> Surface material -> Either SurfaceError (Surface material)` (`Surface.hs:287`); build with `rotationAbout :: V3 -> V3 -> Double -> Rigid`, `after`, `inverse` (`Rigid.hs:95`, `114`, `159`) | Rotates requirement direction; keeps material and thickness; drops `frameExtras` (`Surface.hs:284-296`) | `SurfaceError` |
| Attach layer data | `withFaceOrders :: [FaceOrder] -> Surface m -> Either SurfaceError (Surface m)`; `withLayerRequirements :: V3 -> [(FaceId, FaceId)] -> Surface m -> Either SurfaceError (Surface m)`; `withPhysicalThickness :: Maybe Double -> Surface m -> Either SurfaceError (Surface m)` (`Surface.hs:260`, `306`, `301`) | Range checks only | `SurfaceError` (`Surface.hs:125-144`) |
| Solve layers | `layerOrderFor :: Budget -> Frame -> Either FoldError (Maybe [FaceOrder])`; `solveStackingAs :: Budget -> [Int] -> Frame -> Either StackingError [FaceOrder]` (`Stacking.hs:386`, `402`) | Flat, convex models only | `FoldError` / `StackingError` |
| Diff two states | `motionsBetween :: Frame -> Frame -> Either FoldError [Motion]` (`Step.hs:88`) | Both frames must have identical `edges_vertices` and `faces_vertices` (`Step.hs:94-96`) | `FramesDiffer`, `FramesDisagree` |
| Static contact | `checkPanelContact :: V3 -> [(Text, Text)] -> [Panel] -> Either ContactError ContactCheck`; `checkTriangleContact :: V3 -> [(FaceId, FaceId)] -> [FaceId] -> MaterialMesh -> Either ContactError ContactCheck` (`Contact.hs:123`, `98`) | One state, zero thickness, tolerance `1e-7` in input units (`Contact.hs:20-25`, `83-84`) | `ContactError` is a `newtype` over `Text` (`Contact.hs:77`) |
| Export | `materialFrame :: Surface V2 -> Frame` (`Surface.hs:248`); `renderSurfaceGlb :: Budget -> ExportMode -> Maybe Text -> Surface material -> Either GltfError ByteString` (`Gltf.hs:219`); `surfaceDiagram :: Theme -> Budget -> View -> Surface material -> Either FoldError Diagram` (`CreasePattern.hs:156`); `stepPage :: Theme -> Budget -> Grid -> View -> Bool -> [Frame] -> Either StepError (Maybe Diagram)` (`Steps.hs:90-99`) | `stepPage` with arrows calls `motionsBetween` on consecutive frames (`Steps.hs:122-127`) | as named |

Things a newcomer would get wrong about these:

- **`creaseAllAlong` is not a precrease.** New `M`/`V` creases get angle -180/+180
  when the pattern has an angle array (`Creasing.hs:290-292`, `316-320`), and
  all creases fold flat when it does not (`Folding.hs:529-532`). So
  `creaseThroughLayers` followed by `foldFrame` is "fold flat along this line
  through every layer", instantly, with no motion check; its own test says the
  creases are written at plus or minus 180 so the result is the next state
  (`test/Senbazuru/Origami/ThroughLayersSpec.hs:134-146`). A `Flat` assignment
  gives angle 0 but then `Flap` refuses that edge as a hinge (`Flap.hs:187`).
  A precrease-then-fold move needs a caller to set the new edges' angles to 0
  while keeping `M`/`V`, and the new edge ids are not returned.
- **Flap travel is a change in FOLD angle, signed relative to the stationary
  face's winding.** The first segment fixes the sign; others are derived
  (`Flap.hs:10-18`, `208-216`). The helmet recipe gives +180 for a hinge whose
  second segment actually closes to -180 (`docs/notes/aligned-crease-hinges.md`).
  A flat endpoint needs a half-turn or less (`HingeSweep.hs:313`; `Flap.hs:29-30`).
- **Turning over is a rotation, not a reflection.** `Rigid` will hold any 3x3
  matrix and nothing checks (`Rigid.hs:24-26`), and `Rigid (..)` is exported
  (`Rigid.hs:35`), so `transformSurface` would accept a mirror. The study
  turns a model over with `rotationAbout zero (V3 0 1 0) pi`
  (`BasicBaseGallery.hs:125-127`). #95 (open) proposes the same half turn;
  there is no `TurnOver` in `src` (grep for turn-over names found only
  camera/glTF comments).
- **`creaseThroughLayers` reads its points in the coordinates `foldFrameWith`
  produces**, anchored on the first face, and names mountain/valley as seen
  from +z (`ThroughLayers.hs:216-226`). After a presentation turn-over, the
  viewer's valley is +z's mountain.

### (c) Identifiers that do not survive, and the ones that do

**Unstable:**

- **Face ids are re-traced from scratch after any crease is added.**
  `creaseAllAlong` sets `facesVertices = []` (`Creasing.hs:265`) and
  `withTracedFaces` re-traces. Trace order follows the half-edge walk over
  edges in edge-id order (`Faces.hs:192-195`, `368-384`), which has no relation
  to the previous numbering.
- **Edge ids shift when an edge is cut.** `rebuilt` replaces each edge by its
  pieces in order (`Crossings.hs:310`, `343-347`), so every later edge id moves.
  Pieces inherit assignment and angle (`Crossings.hs:352-358`), but no
  parent-to-piece map is returned.
- **`faceOrders` are dropped** by creasing (`Creasing.hs:266`), and layer
  requirement pairs are `FaceId`s (`Surface.hs:121`), so both go stale.
- **The first face is the anchor.** `spanningWalk` holds `faces !! 0` still
  (`Folding.hs:583-585`). After re-tracing, a different face may be first, so
  two individually correct states can differ by a whole-model rigid motion.
  The recipes put a stationary face first once, before any orders exist
  (`BlintzSequence.hs:5-8`, `44-48`; `HelmetSequence.hs:8-10`, `45-48`);
  `Flap` realigns poses to its stationary face (`Flap.hs:346-348`); `StudyCase`
  picks the held face by a material point (`StudyCase.hs:165-172`). Reordering
  faces renumbers them, so it is safe only while `faceOrders` is empty.
- **Placements are keyed by the cut pattern's face ids** (`Folding.hs:317-322`),
  and `Flap` ids must come from `foldedPattern` (`Flap.hs:9-10`, `152-153`).
- **`motionsBetween` refuses frames with different graphs** (`Step.hs:94-96`),
  so `render --steps` arrows cannot span a crease-adding step.

**Stable:**

- **Vertex ids.** `creaseAllAlong` appends (`Creasing.hs:254`); cutting keeps
  every existing vertex row and appends crossings (`Crossings.hs:73-80`,
  `309`, `339`). `Surface` samples are indexed by vertex id and the module says
  ids, never coordinate equality, decide sharing (`Surface.hs:1-5`).
- **Re-folding a pattern that records faces is id-stable.** `splitCrossings`
  and `withTracedFaces` both return such a frame unchanged
  (`Crossings.hs:128`, `Faces.hs:138`), so `foldFrameWith (pattern { angles })`
  keeps vertex, edge and face ids. `Flap` relies on this (`Flap.hs:175-181`).
- **Material coordinates.** The glossary defines them as identity through
  folding (`docs/glossary.md:81`). `creaseThroughLayers` maps folded points
  back to the sheet with `inverse` placements (`ThroughLayers.hs:291-305`).
  `StudyCase` names panels by a material point strictly inside exactly one face,
  "so face renumbering during crease cutting cannot silently change an order's
  meaning" (`StudyCase.hs:117-120`, `141`).
- **Crease identity through mesh refinement** (not through creasing):
  `refineSurfaceWithEdges` carries source `EdgeId`s through midpoint
  subdivision (`Surface.hs:96-106`, `322-348`; `docs/notes/crease-identity-through-refinement.md`),
  and glTF keeps `senbazuru:source_panels` / `senbazuru:source_edges` (`Gltf.hs:25-26`, `241`).

### (d) Checks that exist, and what is refused

- **Fold closure (every `foldFrameWith`).** `TornAt` when faces place a shared
  vertex apart (`Folding.hs:798-811`); `AngleNotAchieved` when a crease that
  closes a loop does not have its angle (`Folding.hs:688-750`, the case from
  #84 at `670-674`); `AngleWithoutPaper` for a nonzero angle on a one-sided
  edge (`712`); `NonFiniteAngle`, `DisconnectedFace`, `DegenerateFace`,
  `DuplicateEdge`. Tolerance is `1e-9 * max 1 sheetSize`, deliberately
  arithmetic-noise only (`Folding.hs:823-854`). Both checks are needed because
  a loop closed by turning nothing leaves shared vertices agreeing
  (`Folding.hs:56-77`).
- **Drawing validity** on every crease and fold: `Faces.checkDrawing` and
  `Crossings` refusals named in `FoldError` (`Query.hs:80-228`).
- **Hinge sweep** (`HingeSweep.hs:1-51`): interval subdivision with sinusoid
  bounds; running out of budget returns `SweepUnresolved`, never clear
  (`HingeSweep.hs:11`, `454-474`; defaults depth 20, budget 4096 at `94-95`); a
  collision is a witness, not the first impact (`Flap.hs:40-43`). Flat
  endpoints must be one-sided within a half-turn (`HingeSweep.hs:21-29`,
  `301-318`). Touching layers may move together only with the same rigid
  motion and a supplied order (`HingeSweep.hs:31-42`, `280-285`); a hinge may
  rest across another panel if the moving interior stays on one side
  (`HingeSweep.hs:43-47`).
- **Static contact** per state: crossings, unordered coplanar overlap, reversed
  orders, uncheckable orders, cyclic orders refused (`Contact.hs:86-91`,
  `132-134`, `143-150`).
- **Layer solving**: flat, convex only; `Unstackable`, `GaveUpStacking`,
  `WindingClash` (`Stacking.hs:18-29`, `386-400`; `Query.hs:124-139`).
- **Endpoint orders** in a flap: supplied starting orders must agree with
  departure; contradictions are `FlapEndpointOrder` / `FlapStackOrder`
  (`Flap.hs:303-329`).

**Refused, by design:**

- Coupled creases: `FlapCoupled` when removing the selected creases leaves
  another path between the sides (`Flap.hs:199`). Tested on every interior
  crease of the quarter fold (`test/Senbazuru/Origami/FlapSpec.hs:327-343`).
- Creases on different axes: `FlapUnalignedCrease` (`Flap.hs:215`).
- Sliding contact and unsupported seams: a declared contact pair with
  different motions is `InvalidRigidContact` (`HingeSweep.hs:280-285`); an
  unjoined stack edge on the hinge needs a declared partner with real shared
  material covering the contact (`HingeSweep.hs:338-367`). The note
  `docs/notes/checked-flap-operation.md` states sliding contact and
  unsupported hinge seams remain refused.
- Non-convex or non-planar panels (`Surface.hs:353-365`), joined cuts
  (`Surface.hs:342`), paper in the air for through-layer creasing and the
  layer solver (`ThroughLayers.hs:63-67`).
- Thickness: stored as metadata; no renderer or contact check reads it
  (`Surface.hs:298-300`; `Gltf.hs:215-218`).
- A refusal refuses a route, not an endpoint
  (`docs/notes/endpoints-and-routes.md`).

### (e) Coupled multi-crease moves

**The library has none.** `grep` for `Jacobian`, `Newton`, `Gauss` or
degree-4 code in `src` finds nothing. `Flap`'s header says it "does not
discover coupled motions" (`Flap.hs:6`).

**The study has three fixture-bound substitutes:**

1. **Angle keyframes.** `StudyCase.PoseSpec` is a label and a complete angle
   list in the source file's edge order (`StudyCase.hs:78-82`), folded and
   checked for static contact per pose (`StudyCase.hs:121-147`). Nothing checks
   the route between poses.
2. **Closed-form angle relations.**
   - square/waterbomb collapse, `valley = 2 atan2(sqrt 2 sin(m/2), cos(m/2))`
     (`CheckedBird.hs:107-115`, `docs/notes/symmetric-base-collapse.md`);
   - petal side folds (`CheckedPetal.hs:103-116`);
   - rabbit ear (`docs/notes/rabbit-ear-motion.md`).
3. **Exact path certificates.** Polynomial certificates over the ideal path,
   refusing any other fixture (`CheckedPetal.hs:50-62`, `CheckedBird.hs:8-14`).

These are recipes, not operations: edge ids and anchors are hard-coded
(`CheckedPetal.hs:53`, `62`).

**What the open issues propose (issue text, not code):**

- #52 (open, study note) proposes deriving the degree-4 closed form.
- #55 (open) proposes a Gauss-Newton walk on loop-closure constraints, starting
  from the unfolded sheet because the flat-folded state is singular.
- #54's checklist still lists "compatible changes at meeting creases" as
  undone.
- #95 proposes the turn-over move; #97 asks how a scheme is written down and
  names references (Huzita-Hatori) as the harder half.
- #60 proposes `data Move`, `apply :: Move -> Frame -> Either MoveError Frame`
  and a `scanl`. Its owner comment notes that the quarter-fold acceptance
  fixture exercises folding, not crease-adding. I confirmed with `jq` that all
  three frames of `examples/quarter-fold-steps.fold` have 9 vertices, 12
  edges, 4 faces and 12 angles.

Reverse, squash and sink folds have no representation anywhere in `src`.

### (f) Sketch: a minimal state and step, using only existing types

**This is a sketch, not a proposal of record, and none of it exists.**

```haskell
-- SKETCH ONLY.
data FoldState = FoldState
  { -- Cut pattern: material coordinates, graph, assignments, EXPLICIT
    -- edgesFoldAngle, rings copied from the folded frame (finding 6), and a
    -- face order with the anchor first. faceOrders written against these rings.
    statePattern :: !Frame,
    -- Derived and cached: foldFrameWith statePattern. Kept because Flap
    -- demands the unmodified result (FlapStartMismatch).
    stateFolded :: !Folded,
    -- The accepted surface for renderers/study: orders, requirements, thickness.
    stateSurface :: !(Surface V2),
    -- Stable name of the held face, re-resolved after every re-trace.
    stateAnchor :: !V2,
    -- Presentation only (turn over, rotate): applied at export, never
    -- folded into statePattern, never a reflection.
    statePresentation :: !Rigid
  }

-- One step: the new state plus what a renderer needs to draw it.
step ::
  SweepSettings ->
  Budget ->
  move ->            -- whatever the DSL's Move type is
  FoldState ->
  Either stepError (FoldState, [Surface V2]) -- checked intermediate poses
```

`stepError` would be a sum over `FoldingError`, `FoldError`, `ThroughError`,
`FlapError`, `SurfaceError`, `StackingError`; all have `Explain` instances
(grep of `instance Explain` in `src`).

How existing operations fill it:

- **Hinge fold.**
  1. Resolve named segments to `EdgeId`s and the moving side to a `FaceId`
     on `foldedPattern stateFolded`.
  2. Run `prepareFlapAlong` then `checkFlap`.
  3. Poses come from `flapAt`.
  4. Thread angles and orders as in finding 5.
- **Crease (flat or through layers).**
  1. Call `creaseAllAlong` or `creaseThroughLayers`.
  2. Re-trace faces, then re-resolve the anchor and every name.
  3. Reset new-crease angles if the move is a precrease.
  4. Re-solve orders with `layerOrderFor`, or refuse if not flat.
  5. Refold.
- **Turn over.** `statePresentation := rotationAbout c axisInPage pi `after` statePresentation`.
- **Coupled keyframe.** `foldFrameWith statePattern { edgesFoldAngle = ... }`
  plus a static contact check. The result must be marked unchecked-route.

## Implications for the design

1. **Make angles-on-a-pattern the canonical state, and derive positions.** Do
   not let a DSL store or interpolate folded coordinates. Every intermediate
   picture comes from `flapAt` (checked) or from a keyframe re-folded by
   `foldFrameWith` (state-checked only).
2. **Name paper by material geometry, not ids.**
   - faces by a material point strictly inside;
   - creases by a material segment, resolved to every current edge collinear
     with and inside it;
   - the anchor by a material point.
   Resolve names to ids against the current cut pattern at each step.
   `EdgeId`/`FaceId` may appear in a DSL only as a resolved, step-local value,
   never across a crease-adding move.
3. **Separate "route checked" from "state checked" in the types.** Only
   `CheckedFlap` certifies a path. A keyframe or a through-layer crease-and-fold
   certifies an endpoint at most. The material study and renderers should be
   able to tell which they were given, so realistic rendering does not imply a
   validated motion.
4. **Crease-adding moves need a policy the library does not supply.**
   - Say whether the new crease is precreased (angle 0) or folded (+/-180).
   - Carry explicit angles.
   - Recompute the anchor.
   - Re-solve or refuse layer orders.
   - Accept that `motionsBetween` cannot diff across the step, so arrows for
     that step come from the interpreter.

   A small library addition (`creaseAllAlong` returning new-edge provenance, or
   a precrease flag) would remove the geometry-based rediscovery. That is a
   library PRD item, not a DSL workaround.
5. **Keep presentation outside `Folded`.** `Flap` refuses anything but raw
   `foldFrameWith` output (`Flap.hs:169-181`). Turn-over and page rotation
   should be a `Rigid` applied at export via `transformSurface`, built only
   from `rotationAbout`.

   A DSL instruction phrased as seen by the reader must be mapped back through
   that presentation before calling `creaseThroughLayers`: the line through the
   inverse motion, and the assignment flipped when the model is face-down.
6. **Normalise the pattern once**: rings copied from the folded frame, anchor
   face first, before any `faceOrders` exist. This avoids the winding hazard
   and the whole-model jump.
7. **Coupled moves (collapse, petal, rabbit ear, reverse, squash) should be
   expressible now as keyframes or angle-relation families.** They should be
   explicitly marked uncertified until #52/#55-style propagation exists. Do
   not design the language around a solver that is not in `src`.
8. **Errors.** Follow the repo rule: a step error carries the step index, the
   move's label and the nested library error, rendered with `explain`.
   `ContactError` is bare text (`Contact.hs:77`), so contact failures cannot
   point at elements without extra context from the interpreter.
9. **For the material study (PRD 3), the contract is `Surface V2` per state
   plus the move record.**
   - `materialFrame` keeps material coordinates (`Surface.hs:248-252`).
   - Thickness and requirements are not serialised by `materialFrame`
     (`Surface.hs:245-247`) but are by the glTF metadata (`Gltf.hs:243`).
   - Refinement preserves crease and panel identity for bending solvers
     (`Surface.hs:96-106`).

## Open questions

- Canonical state: a `Folded` anchored on its first face (what `Flap` needs),
  or a `Surface V2` anchored by a material point (what the study and renderers
  use)? The sketch caches both; is that one representation too many?
- Should an interpreter do a precrease pass: run once to discover every line,
  then re-run on the final pattern with all creases at 0 so ids and
  `motionsBetween` are stable across the whole sequence? The cost: later
  precreases split earlier hinges, so every flap becomes a multi-segment
  `prepareFlapAlong` selection. Is that always resolvable by material segment?
- What tolerance resolves a material segment to the edges a later cut produced?
  `Faces.tolerance` (`1e-9 * diagonal`, `Faces.hs:248-251`) is the natural
  candidate, but merging is order-dependent at the margin (`Creasing.hs:131-137`).
- Where do `faceOrders` come from for a non-flat keyframe state that is not a
  flap endpoint? Today only a study declaration supplies them.
- Should "fold along this line" on a multi-layer model be `creaseThroughLayers`
  plus instant closure (current behaviour), or precrease plus a checked hinge
  turn (which `FlapCoupled` refuses whenever the line does not separate a flap)?
- Is #97's reference vocabulary (points and lines defined by earlier folds)
  resolvable in material coordinates, in folded coordinates, or both?
- Does a sequence document write frames with differing topologies (breaking
  `stepPage` arrows) or require one final topology?

## Unverified

- #52's count of 41 degree-4 interior vertices on the crane, and #55's claims
  that the flat state is singular and that a Gauss-Newton walk will work:
  issue text only, not measured or read in code.
- The literature cited by the notes (Tachi 2009; Foschi, Hull and Ku 2022;
  He and Guest; Chen et al. 2016): not fetched in this slice.
- Finding 6's inversion is reasoned from `Folding.hs:353-357`, `385` and the
  recipe code; no test or fixture exercises a clockwise-wound file through a
  chained recipe.
- That reordering `facesVertices` while `faceOrders` are non-empty corrupts the
  orders is reasoned, not tested.
- The cost of refolding and re-sweeping per step on large patterns was not
  measured (the repo's rule is to measure, not reason).
- The precrease-pass idea is a design hypothesis with no evidence it works on
  any fixture.
