# Design spine v2 — connecting the fold solver and the material study

> **Historical record.** Part of the design review of the PRD series, kept so its citations resolve. Line numbers cite the draft named in the file; the current decisions are [../../decisions.md](../../decisions.md).

Status: **reviewed decision record**, 2026-09-14, against `568dcb6`. v1 was
reviewed through five lenses (code feasibility, fixture truth, author
ergonomics, conventions, material/rendering honesty) with one skeptic per
serious objection. The reviews are the `review-L*.md` files beside this draft.
Where a decision below says "(L2-4)" it adopts that objection's
*verified* proposal. Every PRD under `PRDs/` is written from this file.

Research notes are published at `PRDs/research/` under their keys (A1, A2, B, C,
D, E1, E2, F, G, Z-critic, gap-*). Cite them by file name and section heading,
e.g. `research/gap-layer-selective-folds.md` "Re-deriving CraneWing by rule".

The request:

1. **Library:** an embedded Haskell DSL to define fold sequences and steps.
2. **CLI:** parse a similarly specified folding-sequence language from a file.
3. **Material:** the material study, when mature, takes what (1) and (2) define
   and produces realistic renderings, as glTF and as an SVG wireframe.

Deliverable: research plus PRDs. No implementation.

---

## 1. The two halves today, and what connecting them means

- **Fold solver (library).** `Fold.Creasing`, `Fold.Crossings`, `Origami.Folding`
  (angles on a cut pattern → `Folded`), `Origami.Flap` + `HingeSweep` (one checked
  hinge turn), `Origami.ThroughLayers`, `Origami.Stacking`, `Origami.Surface`,
  renderers. It folds, checks and draws states and checks one hinge turn. It
  cannot be told a sequence. Every sequence in the repo is a hand-written study
  recipe naming raw ids of a cut pattern (A2 F2–F5).
- **Material study.** `study/fold-material/`: static, zero-thickness,
  held-boundary solver (Gauss–Newton on lengths, crease/panel angular springs,
  penalty contact, sparse factor), fixture experiments (crane wing spreading,
  closed-crease controls), certified coupled routes (`CheckedBird`). Its only
  rigid→material path, `CraneSpread`, consumes one hand-built move
  (gap-study-consumption-contract F1).
- **Shared:** `Origami.Surface`, `Origami.Contact`, `Origami.HingeSweep`.
- **Connecting them** = three contracts that do not exist:
  1. a **sequence** value both front ends produce;
  2. a **run** by the library producing per-step **records** with their evidence;
  3. a **material consumer** taking records (never files) → settled surfaces and
     realistic renders; study first, library after graduation.

## 2. Shape

```
 Haskell author                          text author (.foldseq source)
  Sequence.Build (State, names only)     Fold.Load.readSequenceText -> Text
          \                               Sequence.Parse (megaparsec, pure)
           v                                   v
          Sequence.Syntax : Sequence  (first-order AST, spans)   <-> Sequence.Pretty
                         |
          Sequence.Check (names, kinds, arity, units, finiteness; no geometry)
          Sequence.Elaborate (let, fold-and-unfold sugar; keeps provenance)
                         |
          Sequence.Run  (Budget, RunSettings, sheets) over Fold.* / Origami.*
                         |
          [MoveRecord] + FoldState   (Sequence.Record)     <- contract #1
             |              |               |                     |
   Sequence.Write     Render.Sequence   Render.Gltf        Sequence.Material (study first)
   (state rule,       ([(Frame,StepNote)] (surfaces;         settleStep :: SettleSpec -> MoveRecord
    FoldFile)          -> stepPageWith)   M7 modes)             -> Either SettleError Settled
                                                                 -> Material.Settle (resolved input)  <- contract #2
```

**Module DAG** (an arrow means "may be imported by"; siblings never import each
other) (L4-2):

1. Bottom: `Geometry.*`, `Explain`, `Fold.Types` — none imports outside itself;
   Geometry does not import Explain.
2. `Numeric.*` (new) over `Geometry.*` only; knows no paper.
3. Over `Fold.Types`: siblings `Import.*` and `Fold.{Query,Faces,Crossings,Creasing}`;
   `Fold.Load` over `Import.*` (the only I/O).
4. Siblings `Diagram.*` and `Origami.*`. `Diagram.Style` imports `Fold.Types` for
   `Assignment` — record this as the existing, named exception to "Diagram must not
   know what FOLD is".
5. `Material.*` (new) over `Origami.*` and `Numeric.*`. Takes a resolved input and
   a `Surface V2`; never mentions `MoveRecord` or sequence vocabulary.
6. `Sequence.*` (new) over `Fold.*`, `Origami.*`, `Material.*` (only
   `Sequence.Material` uses Material).
7. `Render.*` over `Diagram.*`, `Origami.*`, `Material.*`, `Sequence.Record`.
8. `app`.

`Numeric` and `Material` are introduced only at graduation (M8); until then the
material consumer lives in `study/`.

## 3. Recorded text this design changes (the follow-ups table) (L4-3)

Every PRD's "follow-ups" point here. Nothing under `PRDs/` edits these files.

| # | Current text | Replacement (summary; the PRD writes it out in full) | Lands |
| --- | --- | --- | --- |
| 1 | `docs/architecture.md:81-86`: #60's moves reach the pipeline as a Frame, "a frame in, a frame out" | `Fold.Creasing` is frame in/frame out; a sequence's moves are not: `Sequence.Run` threads `FoldState` and returns records. What reaches the pipeline as a file is the written `FoldFile`, which `Fold.Query` cannot tell from a hand-written one. `Render.Sequence` and the material consumer read records by design. | M0 |
| 2 | `AGENTS.md` "A new input format becomes a Frame" + `architecture.md:170-175` | Stated exception: a sequence source is a program, not an input format; it becomes a `Sequence` at the boundary and a `FoldFile` + `[MoveRecord]` when run; both record consumers named. | M0, no later than the M1 PR adding `Sequence.Parse` |
| 3 | #60 "What and why"/"Approach": `apply :: Move -> Frame -> Either MoveError Frame`, `[Move]`, `scanl`, "not a free monad: one interpreter" | `runSequence` over `FoldState` returning records; why (presentation, material references, move kinds must reach page and material consumer); plain first-order ADT kept, supersession of the one-interpreter reason stated; `Move` now names a move inside a figure. Done-when amended per D16. | M0 |
| 4 | #95 Approach: half turn `(−x, y, −z)` about x = 0; turn-over as a frame move | Point to D5: presentation, model-intrinsic axis through the current bounding-box centre. | M0 |
| 5 | #97 Done-when: `docs/notes/schemes.md`; quarter-fold reproduction | Note name `docs/notes/sequences.md`; done-when 2 split per D16; #97 closes at M2, not M0. | M0 |
| 6 | #111 table of angle readers | Add the writer's at-rest rule and the two unlisted 1e-10 thresholds (`Origami/Surface.hs:278`, `study/fold-material/StudyCase.hs:208`, the latter the reverse rule); record that they should read `Fold.Query.atRest`. | M0 |
| 7 | #36 done-when 1 (reflection as turn-over); #94 premise and golden; #104 done-when; #114 premises; #56 "transforms discarded"; #64 framing | Corrections listed in §10. | M0 |
| 8 | `AGENTS.md` "Third-party material" | D17's sentence on running external programs. | M0 |
| 9 | `docs/notes/no-sequence-solver.md` first reason | Senbazuru's own vocabulary is now formal; search over it stays a non-goal, for the reasons given. With #96. | M0 |
| 10 | `docs/glossary.md` | Move `PRDs/glossary-additions.md` rows in, rewriting their PRDs-relative links for `docs/`; fix the duplicate rest-angle definition (`:19`, `:83`) and the Flat-folded row (`:21`, "every fold angle is exactly ±180°"), which excludes the precreases-at-0 flat states the design relies on. | M0 (first PR) |
| 11 | `AGENTS.md` "Two unit systems" | One sentence: sequences add sheet lengths and physical lengths, converted to model units in exactly two named places (D2, D14). | with M2 |
| 12 | `AGENTS.md` `--layer-budget` entry-point list | Add `runSequence`. | with M2 |
| 13 | `src/Senbazuru/Origami/Step.hs:30-34` header (turn-over is a motion) | Rewritten with D5's whole-model classification. | with the D5 Step PR |
| 14 | `architecture.md:202-213`, `BlintzSequence`/`HelmetSequence` headers | Updated when the recipes are deleted (D16 deletion PRs), not in M0. | M2+ |

---

## 4. Decisions

Each: **what**, **why** (research or review key), **rejected**, **residue**.

### D1. One first-order AST; a step is a figure holding moves; the builder hands out names only

- **What.** `Sequence.Syntax` is first-order (`Eq`, `Show`, no functions inside).
  `data Sequence = Sequence { seqHeader :: Header, seqSteps :: [Located Step] }`;
  `data Step = Step { stepName :: Maybe Name, stepCaption :: Maybe Text, stepMoves :: [Located Move], stepSettle :: Maybe SettleRequest }`.
  A **step is one figure** (one picture in a book); a figure may hold several
  **moves** (L3-2) — "fold and unfold both diagonals" is one figure of two moves.
  The EDSL is `newtype Build a = Build (State BuildState a)` from
  `Control.Monad.Trans.State.Strict` (transformers; no mtl) whose binds return
  `Ref`s holding **names**, never geometry. `sequenceOf :: Header -> Build () -> Sequence`.
  Interpreters (check, elaborate, run, pretty, page projection, material
  consumption) are ordinary functions.
- **Why.** Several consumers of one value (Gibbons & Wu, F "Embedding styles");
  a file holds only first-order data (F finding 14, D A2); only names flow through
  binds, so the monad is harmless and printing shows unrolled Haskell loops (F
  finding 17).
- **Rejected.** Free/operational monads; tagless final; GADT-indexed AST; shallow
  embedding (F "Rejected alternatives").
- **Supersedes** #60's `apply :: Move -> Frame` and its "one interpreter" reason,
  keeping its plain ADT (§3 row 3).
- **Residue.** `Ref` indexed by empty phantom types (`PointK`, `LineK`, `StepK`),
  no `DataKinds`. Builder function names must avoid Prelude clashes
  (`sequenceOf`, `repeatSteps`, not `sequence`/`repeat`) (L3-17).

### D2. References: named on the sheet, resolved by the slot they fill, evaluated where the paper is now

- **Material names use a sheet compass** (L3-5). Corners `corner south-west |
  south-east | north-east | north-west`; edges `edge south | east | north | west`;
  `centre`. North is +v on the unfolded sheet as the file draws it. Material names
  never change when the model turns or a flap folds over. The words
  left/right/top/bottom/front/behind are **reserved for the view**; the parser
  refuses them where a material feature is expected, with the compass spelling in
  the message. Errors and records also say where the feature currently appears as
  seen ("corner north-west, now at the reader's top-right").
- **Numbers have four kinds** (L4-8), stated once:
  (a) **sheet lengths**: `(u, v)` and lengths. With s the larger side of the
  unfolded sheet's bounding box and (xmin, ymin) its south-west corner,
  `(u, v) = ((x − xmin)/s, (y − ymin)/s)`; a square is [0,1]²; one scale on both
  axes. The resolver converts once and records s; outputs stay in model units.
  (b) **model units**, only inside the `model [...]` escape. (c) **degrees**, always
  written with `°`. (d) **pure ratios** in [0,1] (`fraction r along`, route
  progress). Physical lengths appear only in the `material` block, with unit
  suffixes (D14).
- **Points:** `corner …`, `centre`, `(u, v)` (exact `Rational`), `midpoint of [P, Q]`
  and `fraction r along [P, Q]` (computed in **material** coordinates),
  `meet L1 L2` (current positions), `end of crease of NAME nearest P` (a material
  vertex, distance in material coordinates, ties refused) (L3-6), `mark` names
  (below), `let` names.
- **Lines:** `[P, Q]` (O1, the line through two points); `P to Q` (O2);
  `L1 to L2` (O3); `perpendicular to L through P` (O4); `P to L through Q` (O5);
  `P to L1 and Q to L2` (O6); `P to L1 perpendicular to L2` (O7); `P to L`
  (the fold putting P on L with the fold line parallel to L — the common "fold the
  corner to the crease") (L3-14); `edge S` (the line through its current segments,
  only when they are collinear within `Fold.Faces.tolerance`, else refused naming
  the segments) (L2-15); `crease [P, Q]` (existing crease, Lucero's eighth);
  `hinge of NAME` (segments the named single-move step turned about) and
  `crease of NAME` (segments it created; may be empty) (L3-6);
  `model [(x1, y1), (x2, y2)]` (escape; both ends in the current model's
  coordinates as seen; flat states only; recorded "not a landmark"; depends on the
  anchor) (L3-4, L4-22).
- **Resolution is decided by the slot a point fills, never by its spelling**
  (L2-4 BETTER):
  - **Position** (inputs to O1–O7, both arguments of `P to Q`, `meet`, `model`):
    placed through every face whose closed polygon contains it within
    `Fold.Faces.tolerance`; all placements must agree (join check). No vertex
    needed. Guard for **typed literals only** (`(u, v)`, `model`): a literal not
    within tolerance of a vertex but within `RunSettings.nearMissBand` (default
    1e-3 sheet lengths, an owner question) of one is refused as `NearMiss`,
    naming the vertex and distance. `corner`/`centre`/`midpoint` are exact and
    skip the guard.
  - **Region with a hinge** (`flap containing P`, a move's moving seed): a point
    strictly inside exactly one face; or a vertex (L3-4, L2-11) — after cutting the
    crossed faces along the line, take the pieces containing P; refuse if P lies on
    the line; all those pieces must lie in one component, else refuse naming the
    components. Vertex seeds are preferred over decimal seeds.
  - **Region without a hinge** (`anchor`, `layers A above B`, `mark … in face
    containing S`): strictly inside exactly one face; no vertex exception.
  - **Vertex** (`collapse at`, `rabbit-ear at`, `petal tip`, crease and pose ends,
    `end of crease of`): within tolerance of exactly one vertex; refuse a miss
    naming the nearest vertex and distance; refuse two distinct vertices within
    tolerance (do not trust `Creasing.existingAt`'s first match,
    `Creasing.hs:322-327`).
- **Moving side** (decided only by the move's text, never by the anchor)
  (L3-3, L3-14): for `P to Q` the side containing the named point P; for
  `L1 to L2` the side containing the interior of the first segment (refuse if it
  straddles the fold line); for segment-to-segment O3 prefer the solution mapping
  segment onto segment and ask for `nearest` only if two remain; for `[P, Q]`,
  `crease [P, Q]` and O4 the move must name a seed (`moving P`); a seedless one is
  refused listing both sides with a working seed for each.
- **Which layers** (default changed from v1): an alignment fold (`P to Q`,
  `L1 to L2`, `P to L`) moves the **flap containing its first argument**
  (that component after cutting); `moving P` names another seed; `all layers`
  creases everything under the line; `top layer` = top 1 layer; `top N layers`
  counted at each point along the line from the reader's side; `top flap` = the
  smallest N whose selection is not coupled (L3-9). Viewer-relative selections
  resolve **once** against the accepted layer order and are pinned in the record.
- **Constructions** are evaluated on **flat** states only (flat sheet or
  flat-folded model). With paper in the air, only `crease [P, Q]`, `hinge of`,
  material seeds and macros are allowed; constructions are refused by name.
- **Axioms return lists**: compute all real solutions; report (not drop) off-paper
  ones; require `nearest P` when more than one remains; accept exactly one.
- **Landmarks** (L3-6): `mark A = POINT [in face containing S]` resolves a folded
  position to the distinct material points there, refuses when more than one
  unless S picks exactly one, pins that material point and labels it on the page
  while visible. `let NAME = POINT | LINE` is expanded by `Sequence.Elaborate` and
  re-evaluated at each use; every resolution is recorded. Only `mark` and step
  names enter the landmark table. Names are unique, no shadowing; a mark or crease
  reference that a later step made ambiguous is refused.
- **Why.** The sheet never gains or loses paper, so material coordinates are the
  fixed parameter domain CAD lacks (E2 "The topological naming problem in CAD");
  edge and face ids do not survive creasing (A1 (c)); books name alignments
  (E1, E2); a folded point can name four pieces of paper, a material point one
  (E2 finding 4).
- **Rejected.** Raw ids; typed decimals as the primary form; exact algebraic
  landmark types in the library; `cyclotomic` (GPL-3.0-only, unordered)
  (gap-exact-landmarks F5–F6); view words for material features.
- **Residue.** Unifying the several "hair" formulas is a prerequisite issue
  (gap-exact-landmarks F2). Until then every requirement names the existing
  tolerance it uses by `path:line`; the runner defines no tolerance of its own
  (L4-21).

### D3. The runner owns the state, initialisation and the handoff invariants

- **`FoldState`** (abstract):
  - **working pattern**: the cut crease pattern, material coordinates, rings
    normalised counter-clockwise once, the anchor's face first, **intent
    assignments** and explicit `edges_foldAngle`. It keeps M/V at angle 0 on
    precreased-and-flat creases **on purpose**, departing from `Creasing`'s "a valley
    at 0 is not a valley" (L1-5). Safe because folding reads explicit angles first
    (`Folding.hs:508-511`) and stacking falls back to the assignment only at angle 0,
    a tortilla that orders nothing (`Stacking.hs:637-639, 700-727`). Written frames
    restore the FOLD rule (D4).
  - accepted orders live on the working pattern (`faceOrders`) and directional
    requirements where a move supplied them;
  - **anchor** (material point); **anchor placement** `Rigid` (a proper rotation, may be
    trig-derived, identity at start; called "alignment" in the reviews — renamed so it
    cannot be confused with an alignment fold); **presentation** `Rigid` (D5) (L1-3);
  - landmark table; crease provenance (which step made each material segment);
  - macro bindings (D9).
  Displayed positions = presentation `after` anchor placement `after` raw
  `foldFrameWith workingPattern`.
- **Initialisation** (L1-8, L2-9): a pure library function
  `Sequence.Run.sheetState :: SheetStart -> Frame -> Either SequenceError FoldState`
  (the CLI loads bytes only). The sheet is the file's **key frame**, never a
  `file_frames` entry. Refuse a key frame with no vertices (say how many
  `file_frames` exist) and one whose `Query.frameKind` is `FoldedForm` (the test
  `foldFrameWith` uses for `AlreadyFolded`). Drop `faceOrders` and `frameExtras`;
  `withPlanarFaces`; normalise rings. Intent: M/V kept; an edge with a nonzero angle
  and no M/V takes M below 0, V above; B, C, F, J kept; U stays U. **Plain `sheet`**
  sets every angle to 0 (the blintz/helmet precedent, `BlintzSequence.hs:42`,
  `HelmetSequence.hs:39`). **`start folded`** (a header field) keeps angles as
  `Folding.foldAnglesOf` reads them and chooses a stacking by D11 relations.
  `sheet square` builds the unit square.
- **Default anchor** (L3-3): centroid of the initial pattern's largest face, ties by
  lowest then leftmost centroid (the `StudyCase` rule, `StudyCase.hs:242-248`).
  The header `anchor P` overrides.
- **Re-anchoring** (L3-3, L1-3): when a move's moving side contains the anchor face,
  the runner **re-anchors instead of refusing**: the new anchor is the stationary
  face adjacent to the hinge with the largest material area, ties by lowest then
  leftmost material centroid (never by face id); its centroid becomes the material
  anchor, recorded and printed by `--report`. The explicit move `anchor P` does
  the same on demand. Mechanism: read h = placement of the new root face from the
  current raw fold **before** reordering; anchor placement := anchor placement `after` h; put that
  face first; re-map orders and requirement pairs to new face ids; refold; join
  check on displayed positions. Re-anchoring onto a face whose displayed normal is
  not ±ẑ is refused (keeps the reader's side defined, D5).
- **Invariants** (A2 F11–F19):
  1. carry accepted angles and orders onto the working pattern; never feed folded
     coordinates back as material;
  2. drop `frameExtras` and stale faces on every transform;
  3. re-fold after every handoff; never patch a `Folded` (`FlapStartMismatch`,
     `Flap.hs:169-181`, which does not check orders, so a patch changing only orders
     would pass unnoticed). **Orders reach `Flap` by being on the working pattern
     before the fold**: `foldFrameWith` copies them into `foldedFrame`, re-signing
     any whose second face it re-wound (`Folding.hs:385`), as the blintz and helmet
     recipes do (`BlintzSequence.hs:63-64`). A state's first stacking: fold, solve
     on `foldedFrame`, record the chosen orders on the working pattern, refold. Do
     not attach orders to a `Folded` as `CraneWing.hs:79` does (L1-4, refuted
     objection; its skeptic's wording adopted);
  4. re-resolve every id after a topology change;
  5. anchor by material point; re-anchor as above;
  6. join check at every step: positions within `1e-12 × modelSpan`
     (`BlintzSequence.hs:69`); exact angles, edge lists, face rings (compared as
     `map sort facesVertices`), orders and material coordinates
     (`CheckedBird.hs:145-146`) (L1-13);
  7. never re-solve a stacking silently (D11).
- **Residue.** ~7 `foldFrameWith` per checked step, read from code
  (gap-sequence-cost F6); measure before caching.

### D4. Written frames follow the state rule, in a stated layout

- **At-rest rule, defined once** (L4-6): `Fold.Query.atRest :: Double` (τ) and
  `assignmentAtRest :: Assignment -> Double -> Assignment`: B, C, J pass through;
  otherwise M below −τ, V above τ, F otherwise. When the writer writes F it writes
  the angle as exactly 0, so no written frame has F with a nonzero angle and every
  reader agrees (exact `creaseDirections` and tolerant `Surface` alike).
  `creaseDirections` keeps its exact test; its header says why (#111 permits a
  coarser direction question). Related to #111, not blocked on it.
- **Every emitted frame**: explicit `edges_foldAngle` (refuse to write without);
  never `U`; never M/V at 0.
- **Layout** (L4-7): a **metadata-only key frame**; one state per `file_frames`
  entry, **one frame per figure** at its end state, plus `sample` poses. `--frame N`
  counts states from 1, as `bird-base-sequence.fold`. `senbazuru:material_coords` and
  `senbazuru:assurance` only on `file_frames` entries, written after the last
  transform. The key frame carries none (until #73 splits file and frame keys,
  vertex-indexed data must not sit at the top level).
- **`frame_classes`** (L1-2 BETTER): a frame is `creasePattern` only when every
  angle is 0 **and** every face shows its top side towards +z in the written
  coordinates (the face's material-winding ring has positive signed area in written
  x, y). Every other frame is `foldedForm`, built with `foldedClasses`.
  `faces_vertices` are written in the working pattern's material winding, never
  re-wound from written coordinates, so a turned face draws `paperBack`.
- **File header**: `writeSequence :: FileHeader -> Run -> Either SequenceError FoldFile`
  with `file_spec 1.2`, `file_creator` naming senbazuru, `file_title` from the
  sequence title, `file_classes ["diagrams"]`; optional `file_author` and
  `file_description` passed through by the CLI. The sheet's `file_classes` and
  top-level unknown keys are **not** copied (stated omission until #73).
- **Captions and assurance point in opposite directions, on purpose**:
  `frame_title` of a figure's frame = that figure's caption (the instruction for
  the move **leaving** it, D7); `senbazuru:assurance` on a state = the evidence of
  the step that **produced** it, absent on the first state (absent is not empty).
- **Why the state rule.** Only convention consistent with the FOLD sign rule, the
  `Assignment` haddock and #72's `flatAngleFor`; gives `check` right answers on
  precreases that end flat (writing them M at 0 made a false Maekawa violation on
  the square base); needs no look-ahead (gap-assignment-at-rest F1–F3, F18–F19).
- **Rejected.** M/V at 0; U at 0; target-state direction; J for not-yet-made creases.
- **Consequences.** `examples/quarter-fold-steps.fold` stays as it is; tests per D16.
  Fold-here dashes come from `StepNote` (D7). The material consumer reads intent
  from records (D14), never from written F/M/V.

### D5. Presentation and the reader's side

- **Presentation moves no paper.** `turn over left-right | top-bottom` (page words, never
  compass words, which name material features) and `rotate k/8 turn
  clockwise | anticlockwise` update `FoldState.presentation`. The axis is
  **model-intrinsic** and computed in `Sequence.Run` from `Geometry` only, never
  from a camera (L1-1, L4-1 BETTER):
  - `turn over left-right`: (x, y, z) ↦ (2cx − x, y, 2cz − z);
  - `turn over top-bottom`: (x, y, z) ↦ (x, 2cy − y, 2cz − z);
  - `rotate`: about the line parallel to +z through (cx, cy);
  - (cx, cy) = centre of the xy bounding box of the **current displayed** state;
    cz = middle of its z range.
  Turn-overs, half turns and quarter turns are built from exact 0/±1 entries.
  **Eighth turns** (the book diamond) are allowed and built with `rotationAbout`
  (trig): presentation moves no paper and joins are checked on unpresented
  positions, so exactness is not needed; eighth-turn frames carry platform trig
  bits in written coordinates (stated) (L3-11). A presentation `Rigid` must be a
  proper rotation: det = +1 within 1e-12, checked (`Rigid(..)` is exported and
  unchecked, `Rigid.hs:24-40`).
- **The reader's side is a property of the fold state, never of a render** (L2-7
  BETTER): model +z of the displayed model — the side the flat sheet shows at the
  start (header `coloured side up` default, or `white side up`, which starts with a
  turn-over) (L3-12), flipped by each `turn over`, unchanged by `rotate` and by
  re-anchoring (which is restricted to ±ẑ faces, D3). Every author direction is read
  from it (L4-12): `valley`/`mountain` (aliases `in front`/`behind`), `top N layers`,
  `top flap`, `layers A above B`, `model [...]`, pose angles (D9).
- **The runner converts once, for the whole model** (L1-6 BETTER): raw sense =
  sense negated exactly when `presentation after anchor placement` sends ẑ to −ẑ. That one
  raw sense sets the `Assignment` for new creases and the sign of `Flap`'s travel.
  Each layer's way up (`ThroughLayers.facesUp`) and each hinge segment's sign
  (`Flap.hs:208-216`) stay in the library; the runner never applies them itself.
  Constructions use raw positions (they are invariant); only `model [...]` is mapped
  through the inverse.
- **Render options never change a step's meaning.** `run -o x.foldseq.fold` and
  `run -o x.svg --view V` write identical frames for every V. On a page the arrow kind
  drawn is the stated kind, inverted when the camera looks from the side opposite
  the reader's side; for edge-on views (`front`, `side`) draw the stated kind and
  mark the figure edge-on. Captions are prose and not rewritten; `run` warns once
  when a page is drawn from the opposite side.
- **Page extent**: a turn-over or half turn keeps the figure's extent, the page
  union and the scale **only on top-down or bottom-up pages with roll a multiple of
  90°**, within tolerance; isometric pages may rescale across a turn (measured on
  `bird-base-sequence.fold`, frame 13: 0.4142×0.6118 → 0.9981×0.3335) (L4-1).
  A quarter turn of a non-square figure legitimately changes the union.
- **Written frames are presented.** `Origami.Step` classifies a frame pair related
  by one whole-model proper rigid motion as a **presentation change** and infers no
  arrow (L1-20, L2-13): new `Geometry.Rigid.fitRigid :: [(V3, V3)] -> Maybe Rigid`
  (three non-collinear pairs, every pair within `1e-9 × max 1 modelSpan`, det +1);
  a pair counts only when every vertex moves by more than that tolerance, so an
  identical pair still gives `[]`. The `Step` header paragraph is rewritten in the
  same PR (§3 row 13). **Acceptance:** `render --steps --arrows` output is
  byte-identical for every tracked golden and every multi-frame file under
  `examples/` (L4-23).
- **Rejected.** Turn-over as a frame move (#95); page-axis turns (need a camera in
  the runner, depend on later steps through the auto basis, make written files depend
  on `--view`); reflection (the mirror model); "as seen" from the page camera.

### D6. Crease graphs grow between frames; frames are matched by material identity

- `Origami.Step.motionsAcross :: Frame -> Frame -> Either FoldError [Motion]`:
  `before`'s vertex ids must be a prefix of `after`'s with equal material
  coordinates (confirmed across creasing, cutting, flap turns, presentation and
  re-anchoring, L1 confirmations); added vertices placed on `before` by material
  interpolation along an edge, or by the face's material→position affine map
  located with a **non-convex** point-in-polygon test on material rings; groups
  over `after`'s faces. `motionCreases` reports `after`'s edge ids: each `after`
  edge is matched to a `before` edge whose material segment contains both its
  endpoints; an unmatched edge is new, never "changed" (L1-11).
- `creasesToCome :: Frame -> Frame -> Either FoldError [(EdgeId, V3, V3)]` gives the
  new creases at `before` positions, for the fold-here line.
- `motionsBetween` is unchanged and used when graphs are equal.
- A `checkpoint` (D21) breaks the prefix rule and starts a new figure with no
  inferred motion.
- **Rejected.** Backfill (draws future creases at step 1; the existing golden shows
  it, gap-step-annotation F9).

### D7. A typed step-annotation channel reaches the page; defaults stay byte-identical

- `Render.Steps.stepPageWith :: Theme -> Budget -> Grid -> View -> [(Frame, StepNote)]
  -> Either StepError (Maybe Diagram)`. **No Bool beside the notes** (L1-10):
  `stepPage theme budget grid view arrows = stepPageWith theme budget grid view .
  map (\f -> (f, noteFor arrows))` with `noteFor True = inferNote`,
  `noteFor False = silentNote`. One implementation; `stepPage`'s signature and bytes
  unchanged for its 23 call lines in 15 files (L1-18).
- `StepNote`: caption; arrows (`InferArrows | InferArrowsAs kind | GivenArrows [..] |
  NoArrows`); presentation mark (`Maybe PresentationChange`: **places a `Symbol` and
  suppresses inference on that pair only — frames arrive presented and
  `stepPageWith` never transforms coordinates**); repeat range; layer selection;
  creases to come.
- A figure holding several moves draws **`GivenArrows`, one per move, from the move
  records** (a fold-and-unfold yields identical frames and infers nothing) (L3-2).
- `Diagram` stays FOLD-ignorant: `ArrowPath` gains head (solid = today; hollow half =
  mountain; hollow double = unfold) and body (plain = today; cleft tail = push) with
  defaults emitting today's bytes (`arrowFor` is the one construction site,
  `Style.hs:364-372`); one new `Shape`, `Symbol` (page-unit glyph at a model anchor,
  contributing only its anchor to extents). Wildcard matchers in `LayoutSpec` and
  `CreasePatternSpec` do not catch a new constructor and must be updated by hand.
- Captions are `Label`s placed by `Layout` at the model-space bottom of each cell
  (no page-unit band — the recorded units bug); a trailing gutter only when some
  figure has a caption.
- **Residue** (owner): captions overlap their own figure whenever
  gutter × page scale < label size, including the default 3-column 400pt page
  (arithmetic, L1-18); overflow has no font metrics.

### D8. Folding some layers of folded paper, with a small batched library addition

- **Library** (touches `Fold.Crossings`, `Fold.Creasing`, `Origami.ThroughLayers`,
  `Origami.Visible`) (L1-12, L1-5, L4-16):
  - `data NewCreaseAngle = AtRest | FlatForAssignment`.
  - `Fold.Creasing.creaseAllAlongWith :: NewCreaseAngle -> [(V2, V2, Assignment)] ->
    Frame -> Either FoldError (Frame, [[EdgeId]])`; ids taken from `rebuilt`'s
    chains, not inferred from counts; `creaseAllAlong = fmap fst . creaseAllAlongWith
    FlatForAssignment`.
  - `Origami.ThroughLayers.creaseLayersThrough :: NewCreaseAngle ->
    [(Set FaceId, V2, V2, Assignment)] -> Folded -> Either ThroughError Creased`,
    `Creased { creasedPattern :: Frame, creasedEdges :: [[EdgeId]] }` — one batch, one
    `creaseAllAlongWith` call. `AtRest` writes new pieces at 0 with per-layer intent
    still alternating M/V through `facesUp`/`theOtherWay`; `U` is ruled out as the
    at-rest encoding (it loses that alternation). It takes the `Folded` that
    `foldFrameWith` returns for the working pattern and refuses any other, using
    `Flap`'s start check extracted once and shared. The line is in raw coordinates;
    the assignment is named from raw +z.
  - `creaseThroughLayers` = fold, then `creaseLayersThrough FlatForAssignment` over all
    faces: `crease --folded` output, `CreasingSpec:109-114` and `ThroughLayersSpec`
    unchanged (no golden covers crease output).
  - An ordered-cover query built on `Visible.nearness`, exported, refusing unordered
    overlaps; `carryOrders` mapping accepted orders from parent to child faces,
    exact on `AtRest` output (a crease at 0 moves no paper), undefined otherwise.
- **Selection rule** (library, used by the runner): cut every crossed face along the
  line; `flap containing` selects the seed's component; `top N` counts depth at each
  point along the line; cut only selected faces and walk from the moving side —
  refuse as coupled naming the joining face; refuse if a stationary face is nearer on
  the turning side. Full refusal table in `research/gap-layer-selective-folds.md`.
- **Existing creases**: if the line lies along existing creases covering the selected
  faces, hinge on them without creasing (6 of the crane's 12 some-layer steps: 15, 17,
  18, 20, 21, 23 — L3-16).
- **Unselected layers get no crease.**
- **Evidence status.** The rule reproduces `CraneWing`'s faces `[2,3,6,7]` on
  `crane.fold` in the Python re-implementation (`research/scripts/layer-selection-analyse.py`);
  it must be reproduced in Haskell before a PRD relies on it. Every PRD says so.

### D9. Coupled macro-moves: named angle relations with signatures, pinned bindings

- v1 macros: `collapse at P [keeping [Q1, Q2] flat]`, `rabbit-ear at P`,
  `petal tip P` / `petal top flap` (flat states only, resolved once by nearness and
  pinned) (L3-18). Later: squash, inside/outside reverse, sink, swivel, crimp — each
  only when its relation and signature are derived and tested; until then
  `not modelled "…"` (D21).
- Parts: driving parameter written `until 175°` (an unsigned magnitude, `Rational`
  degrees); closed-form role formulas (one Haskell function each, shared by runner
  and tests); a **signature** matched on a moving star (current angles plus intent
  signs from the working pattern); role extraction; branch/sign choice.
- **Collapse candidates** (L3-1 BETTER): rays at P whose current angle is 0 and whose
  intent is M or V, collinear continuations merged. `keeping [Q1, Q2] flat` removes
  the pair toward Q1 and Q2 (refuse unless they are the far ends of one opposite,
  collinear pair). Then the six-ray signature must match exactly once; with two or
  more, refuse and list every candidate as the `keeping` clause that would pick it
  (the crane's precreased centre gives four). `keeping` is optional where one match
  exists (`square-base.fold`, `bird-base.fold`). The two bases share one sector cycle;
  a base name, if ever added, is checked against where the kept pair ends.
- **Matches vs roles**: roles are unique within a match; matches are not (two fish ears,
  two bird petals); refuse 0 or ≥2 listing candidates; sector comparison uses
  `FlatFold`'s tolerance so `check` and the macro agree.
- **Continuing a macro** (L2-8 BETTER): `continue NAME until A`. Takes the latest
  `MacroBinding` in NAME's line of continuations (refused if NAME is not a single
  macro move); maps each role's material segment onto the current working pattern
  (refuse naming the crease if split or missing); checks the **current state**
  (each role crease at its formula's angle at `reached`, within `FlatFold`'s
  tolerance; no crease inside the macro's rigid sectors folded or moving); requires
  `reached < A ≤ max`; runs from `reached` to A. Signatures are not loosened, because
  recovering t0 from `Double` angles loses the exact parameter.
- `together { … }` advances members' parameters in lockstep.
- `sample 30° 60° …` (a move attribute) chooses illustration poses in the macro's own
  parameter.
- **Pose** escape: `pose { crease [P, Q] at -90°; … }` — signed like FOLD, positive =
  valley as seen from the reader's side (L3-19, L4-12); serialisable; `StateOnly`.
- **Why.** A petal's seven creases turn at three rates; flap turns cannot compose it
  (#60's premise is false, gap-exact-landmarks F15).
- **Residue.** Petal geometry other than 22.5° refused until derived; rabbit-ear
  "rays reach the edge or pass through still vertices" may be too strict.

### D10. Assurance is recorded as evidence values, with pose primitives

- `RouteEvidence` (library): `NoMotion` (crease drawn, nothing moved) | `Presented` |
  `StateOnly` (pose tables, checkpoints, instant flat folds) |
  `Sampled CheckedMacro SampleReport` | `SweptHinge CheckedFlap`. `CheckedMacro` is
  opaque (only the macro checker constructs one), like `CheckedFlap`.
- **Pose primitives** (L5-5 BETTER): `Origami.Flap.flapPoseAt :: CheckedFlap -> Double
  -> Either FlapError RoutePose` reusing `surfaceAt`'s one fold and returning
  placements already multiplied by the stationary correction; `macroPoseAt ::
  CheckedMacro -> Rational -> Either MacroError RoutePose`;
  `data RoutePose = RoutePose { routeAngles :: [Double], routeSurface :: Surface V2,
  routePlacements :: IntMap Rigid }`;
  `data PoseRef = PoseBefore | PoseAfter | PoseOnRoute Rational`;
  `recordPoseAt :: MoveRecord -> PoseRef -> Either MoveFailure RoutePose`
  (`PoseOnRoute` refused as `NoRoute` for `StateOnly`, `NoMotion`, `Presented`).
  No function-valued record field, so `Eq`/`Show` remain derivable.
- Certificates attach **after** the run in the study: a registry keyed by macro name
  **and** fixture fingerprint (`Certified | NoCertificateFor | Refused`), never
  downgraded.
- The CLI prints assurance per step; the writer records it per D4; GLB extras keep
  `senbazuru:assurance` only when present (existing GLB goldens unchanged).
- A figure holding several moves carries the **weakest** evidence of its moves on
  its frame, and the record list keeps each move's.

### D11. Stacking choices are relations, solved in `Origami.Stacking`, with a budget

- `Origami.Stacking.stackingWhere :: Budget -> [(FaceId, FaceId)] -> Frame ->
  Either StackingError Stackings` beside `layerOrderFor`/#110's `withLayerOrder`
  (L4-4 BETTER): pairs mean "first face on the +z side of the second" in the solver's
  sense (`ordersFrom`), not FOLD's `faceOrders` sign; the runner maps "above as seen
  from the reader's side" into it. It **seeds the search with the pairs as decided**
  (cost of one solve), per component (L1-19). Refuses a pair that does not overlap,
  contradictory relations, and exhausted budget as its own error (never as ambiguous).
- The runner decides: unique → orders; two or more → refuse naming the open pairs
  that would split the states; `StackingChoice` records orders and relations (index
  only when cheap).
- No relations and more than one state: refuse with the count and open pairs, unless
  the author writes `stacking first` (records index 0 as a stated default).
  `layerOrderFor`'s silent first choice is never used by the runner.
- Crane example relations (L2-10): tail face 10 at (1/4, 1/5), body face 27 at
  (3/8, 5/9), body face 29 at (4/9, 3/8) — **unverified**: an M4 acceptance test must
  show they leave exactly the tail-tucked state (today's index 2 of 5) and that removing
  either leaves two or more.
- `runSequence` takes a `Budget`; `run` takes `--layer-budget` for every output except
  `--check` (§3 row 12).

### D12. The text syntax

- **Extension** `.foldseq` (placeholder; `.fseq` is the xLights/Falcon Player format;
  owner to confirm) (L3-17). First line `foldseq 1`.
- **Words**: "sequence source" (the `.foldseq` file), "sequence file" (the written
  FOLD), "step" (a figure), "move" (inside a figure). #97's "scheme" is renamed; the
  glossary's existing "sequence" (multi-frame FOLD) is kept and the source/file split
  added (L4-19).
- **Lexical**: `#` comments; newline or `;` separates statements; **braces delimit
  every block** (`step`, `together`, `pose`, `settle`, `material`, `start folded`)
  (L4-13); indentation is not significant; segments are `[P, Q]`; `to` appears **only**
  in alignments; macro parameters `until A°`; pose angles `at ±A°`; degrees always
  carry `°` (ASCII alias `deg`); numbers are exact (integers, decimals, `n/d` →
  `Rational`); `-` is only a sign; hyphenated keywords (`north-west`, `rabbit-ear`)
  are single tokens; a published reserved-word list; `0..1/32` lexes as a range (test)
  (L3-10). Name references parse to untyped references; `Sequence.Check` assigns kinds.
- **Header**: `foldseq 1`, `title "…"`, `sheet square | sheet "path"` (paths relative
  to the source's directory), optional `anchor P`, `coloured side up | white side up`,
  optional `start folded { layers A above B … | stacking first }`, optional
  `material { … }`, optional `closing "…"` (last frame's caption).
- **Moves** (canonical spelling first; pretty-printer prints canonical):
  `fold valley|mountain [A°] LINE [LAYERS] [moving P]` (aliases `fold in front`,
  `fold behind`); `unfold NAME…`; `fold and unfold …` (alias `precrease`);
  `turn over left-right|top-bottom`; `rotate k/8 turn clockwise|anticlockwise`;
  `anchor P`; `mark A = P [in face containing S]`; `let NAME = …`;
  `collapse at P [keeping [Q1, Q2] flat] until A°`; `rabbit-ear at P until A°`;
  `petal tip P until A°` / `petal top flap until A°`; `continue NAME until A°`;
  `together { … }`; `pose { crease [P, Q] at A°; … }`; `sample A° …` (move attribute);
  `repeat NAME[..NAME] [mirrored across [P, Q] | turned k/4 about P]` (D21);
  `checkpoint "path" { layers … }` (D21); `not modelled "…"` (D21);
  `expect refused KIND { move }` (D21); `settle { … }` (D14, inside a step).
- **Parser**: megaparsec 9.5.0 + parser-combinators 1.3.0 + transformers, in the
  **library** stanza (all in the pinned lts-22.44 snapshot, BSD licences; cite the
  snapshot's cabal.config, never a stackage.org package page, which served LTS 24.59).
- **Round trip**: QuickCheck `parse (pretty s) == Right s` on generated ASTs with spans
  stripped, covering every constructor (captions, macros, blocks), `Rational` numbers,
  no NaN; goldens of pretty output and of error text; the EDSL blintz must equal the
  parsed text blintz with spans stripped (L2-12).
- **Rejected.** JSON/YAML authoring (errors are JSON paths); indentation-significant
  syntax; s-expressions; a hand-written reader. A JSON machine encoding of the AST may
  come later.

### D13. CLI and I/O

- `senbazuru run SOURCE.foldseq` with output by `-o` extension: `.fold` (the sequence
  file; stdout default), `.svg` (step page with notes; `--columns --view --width
  --height`), `.glb` (final state, `--frame N`; modes per D19). `--check` (static only,
  no geometry, no `--layer-budget`); `--report` (per-step assurance, resolved references,
  re-anchors, work counts). `--layer-budget` for every geometric output.
- I/O: `Fold.Load.readSequenceText :: FilePath -> IO (Either LoadError Text)` is the only
  `.foldseq` reader (returns Text; imports no `Sequence` module). The CLI loads every
  `sheet`/`checkpoint` path through `Fold.Load` before running and passes a map from
  name to key frame; the runner stays pure. `decodeFile` refuses a `.foldseq` path with
  a message naming `run` (today it would fail as JSON) (L4-20).
- `run` never goes through `withFoldFile`. Existing verbs and their outputs are untouched.
- #58: item 3 (refuse non-finite numbers on write) with M2; item 4 (atomic write, needs
  `directory` in the library) is **not** claimed by M2.
- All logic in the library: the CLI is untested by design (C finding 17).

### D14. Material consumption: records in, illustrations out

- **Records are unpresented** (L5-14): `recordBefore`/`recordAfter` are raw
  `foldFrameWith` geometry of the working pattern (root face at identity); `recordDisplay
  :: Rigid` = presentation `after` anchor placement, applied only by writers and renderers.
- **One record per move** (L5-4 BETTER; supersedes L1-7's two-record split):
  `recordBefore` is the state the paper moves **from** — for a fold that creases, the
  cut, creased, unturned state (faces traced, anchor first, orders carried by
  `carryOrders` or chosen by relations). The uncreased state is the previous record's
  `recordAfter`. **Numbering rule**: every id in a record (hinge, moving, stationary,
  new-crease ids, both halves of angles, stacking) is in `recordBefore`'s numbering;
  `recordAfter` shares it (a flap turn never re-cuts; faces compared as
  `map sort facesVertices`). A move kind that re-cuts after moving must be split or
  record a mapping. `NoMotion` records only a move that creases without turning.
  Records carry `recordFigure` and `recordMove` indices.
- **Orders and requirements are read from the surfaces**, never stored twice
  (`faceOrders (surfaceFrame s)`, `surfaceLayerRequirements s`).
- **Solver surfaces carry intent assignments** (L5-6): the surface `settleStep` gives the
  solver keeps the working pattern's M/V intent, because a crease a move is about to
  fold is at 0 in its before state; the state rule would write it F and
  `surfaceFeatures` would drop it. The state rule stays a `Sequence.Write` concern.
- **MoveRecord fields** (sketch §5): index, figure, move, span, label, macro path,
  move kind, before, after, evidence, hinge (material segments + ids), moving (seeds +
  faces), stationary (seed + face; needs `Flap` to export the stationary face or the
  runner to keep what it resolved), new creases (material segment + ids + assignment),
  angles before/after, stacking choice, anchor, display, resolved references, macro
  binding, cost.
- **Settle requests belong to the moving step they illustrate** (L5-7 BETTER). A
  `settle { … }` block in a step binds to that step's last moving record. It is a static
  solve starting from `recordBefore`, which must be **flat** (every face in one plane;
  contact pairs from its coplanar `faceOrders`; direction = that plane's normal);
  otherwise `SettleStartNotFlat` naming the step. A separated-reference source
  (`ContactDiscovery`) is a later registered option, not a silent fallback.
- **Holds and grips** are named against the record, never by id:
  `side stationary`, `side moving`, `across-hinge S`, `closed R`, `band S d0..d1`
  (distance from the hinge line in the start pose, in sheet lengths), `material-band
  u0..u1`, `crease-line [P, Q]`, `layer upper|lower of R`, `union`/`minus`. Targets:
  `rigid-pose p` (needs `recordPoseAt`; refused as `SettleNoPose` otherwise) or a
  registered generator `arc-grip ROOT° EXTRA°` (range checked: `CraneSpread` accepts
  0–20°). The mapping of every existing crane hold is in
  `research/gap-study-consumption-contract.md` (b); the `rigid-pose 1/3` and band
  equivalences with `CraneSpread.bentPoint` are **unverified** and must be the first M6
  acceptance test (resolved pin set equals `spreadPins`: ids and positions within 1e-12).
- **Rest angles** (L5-6 BETTER): `data RestAngles = RestAtPose PoseRef |
  RestAtPoseExcept PoseRef [(CreaseLine, Rational)]` (degrees as seen); every active
  crease rests at its angle in that pose; never derived from an assignment (delete the
  rule at `CraneSpread.hs:90-94`). A settle with rest pose = start pose, no released
  hold and no moved grip is refused as `NoDifference` (a rigid state is already an
  equilibrium, B finding 6). **Owner decision**: precreased M/V at 0 becomes an active
  crease with rest 0 and crease stiffness; source-file F edges stay panel bends until
  decided.
- **Contract split** (L4-2): `Sequence.Material` holds `SettleSpec`, `Region`,
  `settleStep`; after graduation `Material.Settle` takes only a resolved
  `SettleInput { refinement, stiffness, rest :: Map EdgeId Double, holds, grips,
  contact }` and a `Surface V2`.
- **Physical parameters** (sheet size, thickness, stiffness preset, rest policy) live in
  the optional `material { … }` block with unit suffixes (`15cm`, `0.1mm`; bare numbers
  refused). Model value = physical ÷ sheet size × s. If the sheet file declares a
  physical `frame_unit` that disagrees, refuse naming both. **Thickness is stored, not
  interpreted, in v1**, and `--report` says so. Stiffness presets are named
  illustrative. Display parameters (fidelity modes, exaggeration, colours, camera,
  textures) are render options, never sequence data.
- **Settled geometry is an illustration, never state** (L5-8 BETTER):
  - never replaces a rigid figure, GLB scene or animation key; never enters
    `motionsBetween`/`motionsAcross`, a page basis or extent, or later steps;
  - only steps with a `settle` block are settled (no default settle);
  - each settled step writes its own files named from the `-o` stem plus the step name
    or index (`crane.settled-wing.glb`, `.svg`); rigid outputs stay byte-identical
    whether or not settle blocks exist;
  - settled GLB default scene = complete sheet (a visible scene added only when that
    export succeeds, #206); extras record step, spec, verdict, level;
  - settled SVG page is drawn through the rigid page's camera (chosen from rigid frames)
    with its own extent, never a cell of the step grid;
  - a `Diagnostic` at step k refuses only step k's settled files (nothing written for
    them); other settles still run; rigid outputs are written; the CLI names every
    refused step and exits nonzero, as `check` does; a failure of the rigid run refuses
    everything;
  - `--allow-unsettled` substitutes no geometry: exit 0 and a record of which steps went
    unsettled and why in the rigid outputs' metadata. Diagnostic meshes need their own
    labelled flag and go to FOLD or complete-scene GLB only.

### D15. Graduation from study to library: staged and gated

1. split generic pieces out of fixtures (`ContactRow`, generic measures out of
   `FoldContact`/`FoldMaterial`; delete `PacketContact` from `ContactMode`);
2. `Numeric.Sparse` (from `SparseSolve`) and `DirectionalDistance`;
3. surface-based `FoldBending` → `Material.Bending`;
4. `SurfaceContact` **penalty rows only** → `Material.Contact` (barrier rows are wired only
   into the local-history mode and stay in study until a pinned barrier mode is accepted)
   (L5-18);
5. `relaxPinnedHinges`/`relaxPinnedContact` + bounded diagnostics, structured errors →
   `Material.Relax`;
6. one export adapter (from `spreadSurface`) and one acceptance report (from
   `spreadAccepted`) → `Material.Export`, `Material.Verdict`;
7. `Material.Settle` (resolved input) and `Sequence.Material`.
- **Gates.** #208's value-only line search lands before M6's crane equivalence PR (or that
  PR compares resolved hold sets without re-solving and solves once in the slow job) and
  before M8 (L5-13). `run --settle` refuses more than 1,192 triangles until 3–5 compiled
  runs after #208 justify another number (L5-18). Default-CI settles ≤ 392 triangles.
- **Stays in study**: `ContactQuadratic`, `CreasePairContact`, `CoupledCrease`,
  `UnequalCrease`, `CreaseInequality`, discovery/history/correction-sweep modes, barrier
  rows, `ClosedCrease`, `FoldMaterial` rounded bends, `Crane*`/`Wing*` recipes and
  galleries, `PetalCertificate` and the certificate registry.

### D16. Testing and acceptance

- **Existing 33 tracked goldens stay byte-identical** (`git diff --name-only origin/main --
  test/golden/` lists only goldens a feature adds), plus D5's `examples/` multi-frame check.
- **Quarter fold, two tests** (L2-3 BETTER):
  1. *Folding equivalence*: `sheet "examples/quarter-fold-steps.fold"`, `anchor (3/4, 1/4)`,
     step 1 `fold behind edge west to edge east` (hinges on existing edges 8 and 10, no
     new crease), step 2 `fold in front edge north to edge south` (edges 9 and 11). Ids
     identical. Compare by index: positions within the named tolerance (fixture's 2D
     padded with z = 0), angles within tolerance, assignments by the state rule, face
     rings exactly; not `frame_title`. `render --steps` over these frames is a **new
     reviewed golden** (state-rule variant; gap-assignment-at-rest F18 variant B measured
     4 and 5 changed paths); the existing golden remains the regression for the unchanged
     fixture.
  2. *Authoring*: `sheet square`, same moves, compared by material identity both ways
     (every written edge inside exactly one fixture edge's material segment with the same
     angle; every nonzero fixture edge covered; every written vertex has a fixture vertex
     at its material coordinate with matching position; every unmatched fixture vertex
     lies on a written edge's segment). Its step page is a new reviewed golden.
  - Line that looks like a typo: edge 11 ends at −180 under a valley step because face
    [8,7,0,4] lies upside down.
- **End-to-end table E1–E10** (`research/gap-sequence-cost-and-test-budget.md`
  "Implications"), adapted to the v2 names, on a blintz-sized default-CI sequence with no
  creasing through layers (no trig-derived GLB JSON numbers).
- **Every assertion names the change that turns it red.**
- **Budgets are counted work** (`sweepIntervals` vs 4096, refolds, triangles, pair counts);
  wall-clock guards only after measurement. Measured: any filtered `stack test` run pays
  15–20 s of `runIO` setup (3 runs, loaded M1 Max); crane wing items 1.21–1.25 s and checked
  bird items 12.50–12.52 s by hspec's own timer (addendum) — expensive fixtures move to
  `beforeAll`; crane-sized sequences run in a slow job.
- **Angle equality**: exact only for driving parameters, copied literals, guarded endpoints
  and same-binary outputs; formula-derived angles use one named tolerance that waits on
  the tolerance-unification issue (until then, the existing 1e-12 used by
  `RabbitEarSpec`/`CheckedPetalSpec`, cited).
- **Migration** (gap-study-consumption-contract (d)): blintz then helmet become sequences
  (equivalence PR, then deletion PR); crane wing waits for D8/D11; the bird waits for D9 and
  the registry; frog, six bases and most of `cases.json` stay fixtures.
- **Whole-crane parse/check test**: a 28-step crane source using `not modelled` and
  `checkpoint` parses and checks; red if either constructor is removed (L3-8).

### D17. Third-party and external tools

- Running an external program and reading its output is not vendoring. It needs: a row in
  `docs/related-projects.md` with the licence of the **program as built**; provenance in
  `examples/README.md` for any kept output; no CI or test dependency. Wording goes to
  AGENTS.md at M0 (§3 row 8).
- Origami Simulator (MIT): an oracle via #53, manual or browser-automated (no headless mode
  per its README). ipc-toolkit (MIT): a library, not a solver — a driver is a toolchain
  decision; cite it as its authors ask. Codim-IPC (Apache-2.0): its default build links GPL
  CHOLMOD Supernodal; user-installed only, `WITH_GPL=OFF`/Eigen; copying from it brings
  Apache-2.0 §4 obligations. IPC-family tools cannot start from a zero-thickness flat stack
  without a thickness offset (G finding 13), so they apply only to open states until one
  exists. External solvers are comparison oracles, never ahead of the in-repo path. The
  design-licence rule applies to any pattern fed to any tool (L5-17).
- GPL sources (Doodle GPLv2, Rabbit Ear GPL-3.0, ReferenceFinder GPL-2.0, Creasy GPL-3.0,
  ORIPA GPL-3.0): ideas only. Example sequences fold traditional or generated models only.

### D18. Non-goals

- A sequence solver or search over the vocabulary; a general coupled-angle solver (#55) as
  a prerequisite; sliding contact; automatic hold selection; calibrated paper; pressure or
  inflation (#106); wet folding; thickness as geometry (research).
- Persisting step notes in FOLD; carrying the sheet's vendor keys through a run (both until
  #73); resolving `frame_inherit` (#102).
- Reading OrigamiBench/FoldingAgent/Learn2Fold id-based programs in v1.

### D19. Realistic rendering: independent axes, honest milestones

- **Axes** (L5-11), each output records its position on every axis (glTF
  `extras.senbazuru.fidelity` and SVG `<desc>` via a new optional `Page.pageDescription`,
  only in the new modes; all 33 goldens unchanged) (L5-15):
  - *geometry*: rigid panels | bent zero-thickness (settled, D14) | thickness offsets
    (research only; no G2 "rounded crease" availability claim — a stacked second bend
    stretches 200%, `docs/notes/two-bends-need-more-than-radii.md`; a display spacing
    named `--thickness` was shipped and removed, `docs/notes/paper-thickness.md`);
  - *motion*: static | animated rigid (checked routes) | animated flexible (research);
  - *appearance*: A0 two flat colours (today) | A1 normals split at feature edges, averaged
    within panels | A2a `TEXCOORD_0` from material coordinates (written only for
    `Surface V2`; omitted and recorded for `Surface (Maybe V2)`) | A2b textures (owner
    decision on content first: procedural (ours; PNG via stored deflate blocks + CRC-32 +
    Adler-32 on existing `bytestring`, or `zlib`/`JuicyPixels`, both in lts-22.44) or
    vendored with provenance) | A3 diffuse translucency (release-candidate extension, core
    fallback, never `extensionsRequired`);
  - *lines*: W0 book notation on planar panels (today) | W1 exact line drawing on any
    surface | W2 x-ray lines (quantitative invisibility, #48) and cut-aways (#49).
- **Honesty about rigid sequences** (L5-2 BETTER): on planar panels A1 normals equal the flat
  normals viewers already compute, W1 provenance lines are the edges today's SVG draws, and
  silhouettes can only lie on those creases and boundaries (G finding 21). So for a rigid
  sequence M7 adds animation, optional UVs, optional glTF crease lines — not "realistic
  paper". A1 and W1 matter for non-planar meshes: settled surfaces, future thickness
  offsets, and non-planar FOLD inputs such as `examples/puffed-square.fold` (#104's case).
  **No bent paper is reachable from the senbazuru CLI before M8.**
- **M7a — the smallest visible realistic deliverable** (L5-12): a new GLB mode with A1
  normals and A2a UVs, demonstrated on the existing accepted study meshes (crane-spread
  curved and fine, wing-bending). Free-standing (needs `Surface` only).
- **glTF crease lines — a measured spike before it is a requirement** (L5-3 BETTER): built from
  feature edges clipped to each side's exposed regions with the visible scene's visibility
  code; one copy per side offset along **that side's** panel normal (an averaged normal
  vanishes at a flat-folded crease) by a named display epsilon recorded in
  `extras.senbazuru` beside, never inside, `frame`; no lines in complete-scene exports.
  Spike acceptance: Khronos validator issue counts; a three.js screenshot with the standard
  `GLTFLoader` from `study/gltf` on the quarter fold and the crane from both sides; a headless
  Blender import counting imported loose edges with `bpy` (loose edges do not render).
  Fallback: lines as data in extras, drawn by the study viewer.
- **Feature edges for realistic outputs** = every edge of the written state whose assignment
  is not `J` (creases that exist, whatever their angle, plus boundaries), so `run -o x.glb`
  and `export x.fold` agree; not `surfaceFeatures`, which drops F at 0 (L1-15).
- **W1 exact line drawing** (L5-1 BETTER): candidates = source creases and boundaries by
  provenance, plus silhouettes (shared J edges where the sign of normal·view differs; free
  boundary edges). Visibility computed **exactly**: project each segment, clip against each
  triangle's projected outline (bounding-box broad phase), compare depth gaps at interval
  ends (linear on a planar triangle). Tolerance = `Origami.Contact.panelTolerance` × sheet
  span. Nearer by more than tolerance throughout → hides. Within ±tolerance → triangle-level
  `faceOrders`, closed transitively as `Origami.Contact` does, decide. Triangles incident to
  the segment never occlude. Unordered ties are drawn and their total length recorded. Draw
  the complement of hidden intervals. A filled drawing through `Render.Projected` is
  optional; any `Nothing` or `Left ImpossibleStacking` falls back to the line drawing.
  Acceptance: (0) first record whether `projectedForm` declines on crane-spread curved/fine;
  if not, use crane-root and #206's mesh as the red case; (a) no crease buried in the body
  stack drawn on those meshes and the 4,312-triangle crane-root mesh; (b) two red tests
  (drop the order tie-break; shrink the band to `Projected`'s 1e-9); (c) measure candidate
  × triangle pairs after the broad phase, 3–5 compiled runs at 392, 1,192, 4,312 triangles.
- **"Wireframe"**: owner question — feature lines only, or triangulation too. Offer
  `--lines features|mesh`, default `features`; `mesh` draws visible J edges at the
  buried-sheet weight through the same visibility test (L5-20).
- **G1 animation (M7b)** (L5-9, L5-10, L5-5):
  - one node hierarchy over the run's **final** cut pattern along its spanning walk; each
    earlier state places a final face with its containing face's `Rigid` (exact: cutting
    only subdivides; vertex ids survive); unborn creases sit at 0; their lines omitted or
    STEP-scaled in;
  - presentation is a top node with origin at the D5 axis point and at least 3 keys per half
    turn; each anchor segment gets a sub-hierarchy switched by STEP scale at re-anchor keys;
  - keys come from `recordPoseAt` at a `RunSettings` key density independent of `sample`;
    crease turns ≥ 180° between keys are subdivided or refused; `StateOnly` transitions are
    STEP-keyed and recorded;
  - midpoint checks refold at the angles **interpolated linearly between keys** (what the
    viewer shows), not at the route's midpoint parameter; failures subdivide or refuse;
    for `SweptHinge` the two coincide;
  - `--report` counts key and midpoint refolds.
  Tests: every key's face transforms equal that state's placements within 1e-12×span (red if
  keyed by earlier face ids); in a blintz with a re-anchor, the stationary face moves
  < 1e-9×span at mid-key.
- **#104**: M7b advances it without closing; silhouettes only in W1 mode; its done-when is
  amended to "default render byte-identical; `--lines` draws the dome outline" (L5-16).

### D20. Errors

- **Every new error type has an `Explain` instance in its own module** (L4-5 BETTER):
  `ParseProblem`, `StaticProblem`, `ResolveProblem`, `MoveFailure`, `SelectionError`,
  `MacroBindError`, `StackingChoiceError` (or new `StackingError` constructors),
  `SettleError`, plus `SequenceError`. Verdict `Reason` and registry `Refused` also get
  instances, so `explain` stays the single answer to how the project prints a refusal. The
  PRD tabulates each with a SKETCH example message.
- **Message shape**: `SequenceError` starts with "step N (name)", then the author's reference
  text, then the nested `explain`. Wrappers never reword nested errors. The message carries
  **no location** (a Haskell-built sequence has none); `sourceLocation :: SequenceError ->
  Maybe Text` and `excerpt :: Text -> SequenceError -> Maybe Text` (the caret display) are
  separate; the CLI prints `path:line:col: message` when there is a location, the message
  alone otherwise, never the path twice.
- `ParseProblem` stores a span plus unexpected/expected items as data; its instance joins them
  on one line; only `excerpt` emits several lines.
- **Ids in messages** are written as "(internal edge 37)" so an author knows they did not
  write them.
- **Flag leak fixed at the source** (follow-up issue, lands before the first milestone whose
  runner wraps `ThroughError`, i.e. M4): `ThroughError`'s `LineStopsOnTheModel` carries the
  point given and names the end by it, as `FoldError.CreaseEndMeetsNothing` does; delete
  `creaseEndFlag` or move it to `app/`. The sentence pinned at `ThroughLayersSpec.hs:271-275`
  and quoted in `docs/usage.md` changes in that PR.

### D21. Repeat, checkpoint, not-modelled, expect-refused

- **`repeat NAME[..NAME] [mirrored across [P, Q] | turned k/4 about P]`** (L3-7 BETTER): P, Q
  exact material points (corners, centre, `(u, v)`, `midpoint of` an edge; constructions
  refused); quarter turns only, so mapped points stay `Rational`; the bare form is the
  identity (a restatement at a later state); the isometry must map the sheet to itself. Maps
  only material references; presentation moves kept as written; a step containing `model` or
  `top N` is refused. **Senses are checked in material terms by the runner**: after the move,
  its new creases must equal the isometry's image of the original's with the same
  assignments, else `RepeatNotSymmetric`. One figure carrying D7's repeat range; expanded
  moves get derived names, each checked. `behind` is dropped (two isometries flip every
  layer). Unlocks crane 17, 20, 23 (M4) and 11 (M5), not 14 or 25.
- **`checkpoint "path" { layers … }`** (L3-8 BETTER): replaces the working pattern with a named,
  loaded key frame folded from its assignments; stacking by D11; `StateOnly`; the target must
  share the sheet's outline in material coordinates within `Fold.Faces.tolerance` and may add or
  remove creases (frog milestones); breaks D6's prefix rule, so it starts a new figure with no
  inferred motion; the record carries new and removed creases. `start folded` is a header field
  for the first state only.
- **`not modelled "inside reverse fold"`**: `run --check` accepts it; `run` refuses it by name
  (`NotModelled`), still returns and writes the records before it; the page draws that figure's
  caption with `NoArrows`. Real macro forms are added only when D9's signature exists.
- **`expect refused KIND { move }`**: runs the inner move against the current state, requires
  refusal of the named kind, writes no frame, leaves the state unchanged, records the refusal as
  evidence. It documents which direction is physical (the crane's opposite turn, the blintz
  reopening through the centre).

### D22. Figures holding several moves

- A figure's moves run in order, each checked. Move k is accepted into the figure only if every
  material point of its moving paper is where the figure's drawn state puts it, compared by
  material identity as in D6; otherwise refuse with a hint to start a new `step` (keeps every
  arrow on the figure honest).
- Batching: one `creaseAllAlongWith` per run of consecutive moves on the same state (crane 1 and
  3's precreases share one batch; a move after a turn starts a new one).
- `unfold NAME…` reverses the named figures' net angle changes in reverse move order; moves that
  already returned to flat are skipped. `repeat` names figures.
- `sample` belongs to a macro move; `settle` to the figure's last moving record (D14).

---

## 5. Type sketch (SKETCH; names every PRD uses)

```haskell
-- Senbazuru.Sequence.Syntax
data Span = Span !FilePath !Int !Int !Int !Int | NoSpan
data Located a = Located { locSpan :: !Span, locValue :: !a }
newtype Name = Name Text

data Compass = North | East | South | West
data Corner = SouthWest | SouthEast | NorthEast | NorthWest
data Sense = Valley | Mountain                                -- as seen from the reader's side
data PageAxis = LeftRight | TopBottom
data Turning = Clockwise | Anticlockwise
data Side = ColouredUp | WhiteUp

data Point
  = CornerOf Corner | Centre | AtSheet Rational Rational
  | MidpointOf Point Point | FractionAlong Rational Point Point | Meet Line Line
  | EndOfCreaseOf Name Point | PointNamed Name
data Line
  = EdgeOf Compass | Segment Point Point                      -- [P, Q], O1
  | Onto Point Point                                          -- P to Q, O2
  | LineOnto Line Line (Maybe Point)                          -- O3 (+ nearest)
  | PerpendicularThrough Line Point                           -- O4
  | PointToLineThrough Point Line Point (Maybe Point)         -- O5
  | TwoToTwo Point Line Point Line (Maybe Point)              -- O6
  | PointToLinePerpendicular Point Line Line                  -- O7
  | PointToLine Point Line                                    -- P to L (fold line parallel to L)
  | ExistingCrease Point Point | HingeOf Name | CreaseOf Name
  | ModelSegment (Rational, Rational) (Rational, Rational)     -- escape
  | LineNamed Name
data Layers = FlapOfFirstArgument | AllLayers | TopLayers Int | TopFlap
data Amount = ToFlat | Degrees Rational
data Relation = Above Point Point                             -- as seen from the reader's side

data Move
  = Fold Sense Amount Line Layers (Maybe Point)               -- optional `moving P`
  | Unfold [Name] | FoldAndUnfold Sense Line Layers (Maybe Point)
  | TurnOver PageAxis | Rotate Int Turning                     -- k/8 turn
  | Anchor Point | Mark Name Point (Maybe Point) | Let Name Binding
  | Macro MacroCall [Rational]                                 -- call + sample list
  | Continue Name Rational | Together [Move]
  | Pose [(Point, Point, Rational)]
  | Repeat Name (Maybe Name) (Maybe Isometry)
  | Checkpoint Name [Relation]
  | NotModelled Text | ExpectRefused RefusalKind Move
data MacroCall = Collapse Point (Maybe (Point, Point)) Rational
               | RabbitEar Point Rational | Petal PetalTip Rational
data PetalTip = TipAt Point | TopFlapTip
data Isometry = MirroredAcross Point Point | TurnedQuarters Int Point
data Binding = BindPoint Point | BindLine Line

data Step = Step { stepName :: Maybe Name, stepCaption :: Maybe Text, stepMoves :: [Located Move], stepSettle :: Maybe SettleRequest }
data Header = Header { hTitle :: Maybe Text, hSheet :: SheetSource, hAnchor :: Maybe Point, hSide :: Side
                     , hStart :: Start, hMaterial :: Maybe MaterialSpec, hClosing :: Maybe Text }
data Start = StartFlat | StartFolded [Relation] | StartFoldedFirst
data SheetSource = UnitSquare | SheetFile FilePath
data Sequence = Sequence { seqHeader :: Header, seqSteps :: [Located Step] }

-- Senbazuru.Sequence.Build
newtype Build a = Build (State BuildState a)
newtype Ref k = Ref Name                                      -- k: PointK | LineK | StepK (empty types)
sequenceOf :: Header -> Build () -> Sequence
step :: Name -> Text -> Build () -> Build (Ref StepK)         -- and step_ without a name

-- Senbazuru.Sequence.Parse / Pretty / Check / Elaborate
parseSequence :: FilePath -> Text -> Either SequenceError Sequence
prettySequence :: Sequence -> Text
checkSequence :: Sequence -> Either SequenceError Checked
elaborate :: Checked -> Elaborated

-- Senbazuru.Sequence.Run
data RunSettings = RunSettings { sweep :: SweepSettings, nearMissBand :: Rational, keyDensity :: Int }
data FoldState   -- abstract (D3)
sheetState :: SheetStart -> Frame -> Either SequenceError FoldState
runSequence :: Budget -> RunSettings -> Map FilePath Frame -> Elaborated -> Either SequenceError Run
data Run = Run { runRecords :: [MoveRecord], runFinal :: FoldState }

-- Senbazuru.Sequence.Record
data RouteEvidence = NoMotion | Presented | StateOnly | Sampled CheckedMacro SampleReport | SweptHinge CheckedFlap
data PoseRef = PoseBefore | PoseAfter | PoseOnRoute Rational
data RoutePose = RoutePose { routeAngles :: [Double], routeSurface :: Surface V2, routePlacements :: IntMap Rigid }
recordPoseAt :: MoveRecord -> PoseRef -> Either MoveFailure RoutePose
data MoveRecord = MoveRecord
  { recordFigure :: !Int, recordMoveIndex :: !Int, recordSpan :: !Span, recordLabel :: !(Maybe Text)
  , recordPath :: ![Name], recordKind :: !MoveKind
  , recordBefore :: !(Surface V2), recordAfter :: !(Surface V2)        -- unpresented; one numbering
  , recordEvidence :: !RouteEvidence
  , recordHinge :: ![(MaterialSegment, [EdgeId])], recordMoving :: ![(MaterialPoint, [FaceId])]
  , recordStationary :: !(Maybe (MaterialPoint, FaceId))
  , recordNewCreases :: ![(MaterialSegment, [EdgeId], Assignment)]
  , recordAngles :: !([Double], [Double]), recordStacking :: !(Maybe StackingChoice)
  , recordAnchor :: !MaterialPoint, recordDisplay :: !Rigid
  , recordResolved :: ![ResolvedReference], recordMacro :: !(Maybe MacroBinding), recordCost :: !StepCost }
data MacroBinding = MacroBinding { bindMacro :: MacroName, bindRoles :: [(Role, MaterialSegment)]
                                 , bindBranch :: Branch, bindDisambiguator :: Maybe ResolvedReference, bindReached :: Rational }

-- Senbazuru.Sequence.Write
writeSequence :: FileHeader -> Run -> Either SequenceError FoldFile

-- Senbazuru.Render.Sequence
stepNotes :: Run -> [(Frame, StepNote)]

-- Errors (each type its own Explain instance, D20)
data SequenceError
  = ParseFailed ParseProblem
  | StaticRefused Span StaticProblem
  | ResolveRefused Int (Maybe Name) Span Text ResolveProblem
  | StepRefused Int (Maybe Name) Span MoveFailure
sourceLocation :: SequenceError -> Maybe Text
excerpt :: Text -> SequenceError -> Maybe Text

-- Senbazuru.Sequence.Material (study first)
data SettleSpec = SettleSpec { refinement :: RefineRegion, stiffness :: Bending, rest :: RestAngles
                             , holds :: [Region], grips :: [(Region, GripTarget)], budget :: Settings }
settleStep :: SettleSpec -> MoveRecord -> Either SettleError Settled
data Settled = Settled { settledSurface :: Surface V2, settledReport :: SettleReport, settledVerdict :: Verdict }
data Verdict = Accepted | Diagnostic [Reason]
-- Senbazuru.Material.Settle (after graduation)
settle :: SettleInput -> Surface V2 -> Either SettleError Settled
```

## 6. Grammar sketch (SKETCH; the file PRD writes the full EBNF, cf. review-L3 §L3-10)

```ebnf
source   = header , { step } ;
header   = "foldseq" , "1" , NL , [ "title" , STRING , NL ] , "sheet" , ( "square" | STRING ) , NL ,
           [ "anchor" , point , NL ] , [ ( "coloured" | "white" ) , "side" , "up" , NL ] ,
           [ "start" , "folded" , block(relation | "stacking first") ] , [ "material" , block(mat) ] ,
           [ "closing" , STRING , NL ] ;
step     = "step" , [ NAME ] , STRING , "{" , { move , SEP } , [ "settle" , block(settle) ] , "}" ;
move     = fold | unfold | turn | rotate | anchor | mark | let | macro | continue | together
         | pose | repeat | checkpoint | notmodelled | expect ;
fold     = ( "fold" , sense | "fold" , "and" , "unfold" , sense | "precrease" , sense ) , [ DEG ] , line ,
           [ layers ] , [ "moving" , point ] ;
sense    = "valley" | "mountain" | "in" , "front" | "behind" ;
layers   = "all" , "layers" | "top" , "layer" | "top" , INT , "layers" | "top" , "flap" ;
point    = "corner" , CORNER | "centre" | "(" , NUM , "," , NUM , ")" | "midpoint" , "of" , seg
         | "fraction" , NUM , "along" , seg | "meet" , line , line | "end" , "of" , "crease" , "of" , NAME ,
           "nearest" , point | NAME ;
seg      = "[" , point , "," , point , "]" ;
line     = "edge" , COMPASS | seg | point , "to" , point | line , "to" , line , [ "nearest" , point ]
         | "perpendicular" , "to" , line , "through" , point | point , "to" , line , "through" , point
         | point , "to" , line , "and" , point , "to" , line , [ "nearest" , point ]
         | point , "to" , line , "perpendicular" , "to" , line | point , "to" , line
         | "crease" , seg | "hinge" , "of" , NAME | "crease" , "of" , NAME
         | "model" , "[" , pair , "," , pair , "]" | NAME ;
macro    = ( "collapse" , "at" , point , [ "keeping" , seg , "flat" ] | "rabbit-ear" , "at" , point
           | "petal" , ( "tip" , point | "top" , "flap" ) ) , "until" , DEG , [ "sample" , { DEG } ] ;
continue = "continue" , NAME , "until" , DEG ;
turn     = "turn" , "over" , ( "left-right" | "top-bottom" ) ;
rotate   = "rotate" , INT , "/" , "8" , "turn" , ( "clockwise" | "anticlockwise" ) ;
```

(Ambiguities the file PRD must resolve in its full grammar: `point "to" line` vs
`point "to" point` when the second is a NAME — resolved in `Sequence.Check` by the name's kind;
`line "to" line` left recursion — lines are parsed by alternatives with a leading keyword or
point, not left-recursively.)

## 7. Examples (every PRD example must be run against its fixture with jq/python3 and the command cited, or marked UNVERIFIED)

**Quarter fold (folding equivalence, D16 test 1):**

```text
foldseq 1
title "A square folded into quarters"
sheet "examples/quarter-fold-steps.fold"
anchor (3/4, 1/4)          # south-east quarter, which neither step moves

step half "Fold the left half behind, onto the right." {
  fold behind edge west to edge east
}
step quarter "Fold the top half down in front, onto the bottom." {
  fold in front edge north to edge south
}
closing "Folded into quarters."
```

Facts to cite (L2-1/2/3, verified by skeptics with jq/python): face [8,4,1,5] never moves;
step 1 moves vertices 0, 3, 7 (faces 2 and 3) behind (z < 0); step 2 moves vertices 2, 3, 6
(faces 1 and 2) in front (z > 0); edge 9 +180 and edge 11 −180 (face [8,7,0,4] upside down).

**Blintz (M2 migration):**

```text
foldseq 1
title "Blintz base, then reopen one corner"
sheet "examples/blintz-base.fold"
anchor centre              # a region: strictly inside the traced central square

step c1 "Fold the south-east corner behind, to the centre." {
  fold behind corner south-east to centre      # lies on existing crease (1/2,0)-(1,1/2): no new crease
}
step "Fold the north-east corner behind, to the centre." { fold behind corner north-east to centre }
step "Fold the north-west corner behind, to the centre." { fold behind corner north-west to centre }
step "Fold the south-west corner behind, to the centre." { fold behind corner south-west to centre }
step "Reopen the first corner." { unfold c1 }
```

EDSL (must print to the same AST):

```haskell
blintz :: Sequence
blintz = sequenceOf (header "Blintz base, then reopen one corner" (sheetFile "examples/blintz-base.fold") (Just centre)) $ do
  c1 <- step "c1" "Fold the south-east corner behind, to the centre." $ fold Mountain (cornerOf SouthEast `onto` centre)
  forM_ [(NorthEast, "north-east"), (NorthWest, "north-west"), (SouthWest, "south-west")] $ \(c, word) ->
    step_ ("Fold the " <> word <> " corner behind, to the centre.") $ fold Mountain (cornerOf c `onto` centre)
  step_ "Reopen the first corner." $ unfold [c1]
```

(Whether the recipe's figure-per-corner or a book's one-figure-four-moves is used is a
presentation choice; the migration keeps the recipe's to reuse `checked-blintz.svg`.)

**Bird base from the bird crease pattern (M5):**

```text
foldseq 1
title "Bird base"
sheet "examples/bird-base.fold"
anchor (29/50, 2/5)

step collapse "Collapse into a square base." {
  collapse at centre until 180° sample 30° 60° 90° 120° 150° 175°
}
step front "Petal fold the front flap up." { petal tip corner south-east until 175° }
step back "Petal fold the back flap behind." { petal tip corner north-west until 175° }
step "Press both petals flat." {
  together { continue front until 180°; continue back until 180° }
}
```

(Certificate route, not a book's petal/turn-over/repeat route; a book route sketch may be added,
marked UNVERIFIED for contact at 180°.)

**Crane wing with a settle (M4 + M6):**

```text
foldseq 1
title "Lower one crane wing"
sheet "examples/crane.fold"
anchor (19/20, 1/3)        # strictly inside face 0; model +z below is face 0's frame
start folded {
  layers (1/4, 1/5) above (3/8, 5/9)     # UNVERIFIED: must leave exactly the tail-tucked stacking
  layers (4/9, 3/8) above (1/4, 1/5)
}

step wing "Fold the underneath wing away from you until it stands straight out." {
  fold behind 90° corner north-west to midpoint of edge north
  # corner north-west (material (0,1)) folds to (1,0); midpoint of edge north (1/2,1) to (1,1/2):
  # the fold line is folded y = 1/4; the flap containing corner north-west is wing A, faces [2,3,6,7].
  # Seen from the reader's side (+z, no turn-over): wing A lies under wing B; its tip goes from
  # (1,0,0) to (1,1/4,-1/4). UNVERIFIED in Haskell.
  settle {
    refine moving 3
    hold closed side stationary
    hold band moving 0..1/32 at rigid-pose 1/3    # UNVERIFIED equivalence with CraneSpread.bentPoint
    grip band moving 7/32.. arc-grip 30° 20°
  }
}
expect refused FlapEndpointOrder { fold in front 90° corner north-west to midpoint of edge north }
```

**Crane opening from a square (M5; signs must be re-derived):**

```text
foldseq 1
title "Crane: square base"
sheet square
coloured side up
rotate 1/8 turn anticlockwise         # diamond presentation (book step 0)

step diagonals "Fold and unfold both diagonals." {
  fold and unfold in front [corner south-west, corner north-east] moving corner south-east
  fold and unfold in front [corner south-east, corner north-west] moving corner south-west
}
step "Turn over." { turn over left-right }
step midlines "Fold and unfold both midlines." {
  fold and unfold in front edge south to edge north
  fold and unfold in front edge west to edge east
}
step "Collapse into a square base." {
  collapse at centre keeping [corner south-east, corner north-west] flat until 180°
}
```

UNVERIFIED: which pair `keeping` must name and the senses; the M5 writer derives them with the
runner or python on the working pattern, and the four `keeping` candidates are the refusal test.

## 8. Milestones

| M | Name | Contents | Closes / advances |
| --- | --- | --- | --- |
| M0 | Decisions on record | §3 rows 1–10; `docs/notes/sequences.md`; `PRDs/glossary-additions.md` rows moved to the glossary; follow-up issues filed (tolerance unification, `existingAt`, `check` silent Maekawa skip, flag leak D20, stale-doc corrections §10) | amends #60, #95, #97, #111, #36, #94, #104, #114, #56, #64 |
| M1 | Language without geometry | `Sequence.Syntax/Build/Parse/Pretty/Check/Elaborate`; `Fold.Load.readSequenceText`; `run --check`; round-trip property; whole-crane parse/check test; input-format exception lands | #60 (part) |
| M2 | Rigid runner on flat states and existing creases | `sheetState`; references (D2) on flat states; `fold`/`unfold`/`fold and unfold` along constructions on the flat sheet and along existing creases on flat-folded states; checked hinges; presentation; anchors; D5 `fitRigid`/Step classification; state-rule writer; `Fold.Query.atRest`; `run -o .fold/.glb`; `--report`; `expect refused`; `not modelled`; blintz and helmet equivalence; quarter-fold test 1 | closes #97, #95; advances #60; #58 item 3 |
| M3 | Step pages that read like a book | `StepNote`, `stepPageWith`, arrow heads, `Symbol`, captions, `motionsAcross`, `creasesToCome`, figures with several moves (D22), marks; `run -o .svg`; quarter-fold test 2 page | #36, #94; advances #48 |
| M4 | Folding some layers | `creaseAllAlongWith`, `creaseLayersThrough`, ordered-cover query, `carryOrders`, selectors, `stackingWhere`, `start folded`, `checkpoint`, `repeat`, D20 flag fix; crane-wing prefix as a sequence | #70 revisited; #54 (part); #110 related |
| M5 | Coupled macros | collapse (with `keeping`), rabbit ear, petal, `continue`, `together`, `sample`, `pose`; `CheckedMacro`, `macroPoseAt`; study certificate registry; bird route; crane opening | #54, #61 (part); #55 unblocked, not required |
| M6 | Study consumes records | `MoveRecord` final; `Sequence.Material` in study (`settleStep`, regions, `RestAngles`); `settle`/`material` blocks; settled illustrations and failure scope; crane spreading re-expressed (pin-set equivalence first); `senbazuru-material-study --sequence SOURCE DIR` | #195 follow-ups; #114 rewritten |
| M7a | Realistic GLB mode on existing meshes | A1 normals, A2a UVs, fidelity metadata; demonstrated on crane-spread and wing-bending study meshes | #56 (no), first visible realism |
| M7b | Motion and lines | G1 animation of checked routes (SweptHinge; Sampled after M5); W1 line drawing; `--lines`; glTF lines spike | #56, advances #104, #48 |
| M8 | Graduation | D15 stages 1–7; `run --settle`; `--allow-unsettled` | #208 gate; #106 later |
| R | Research | thickness offsets and crease radii at vertices; unheld equilibrium; calibration; exact contact at scale; springback rest angles; animated flexible routes | #114, #106, #64 |

**Order constraints** (L4-15, L5-12, L5-13): M1 → M2 → {M3, M4} → M5; M4 → M6 → M8;
M2 → M7b (SweptHinge-only animation until M5); M7a free-standing; the `atRest` constant (and
#111's table amendment) before M2's writer; #208's value-only line search before M6's crane
equivalence PR and before M8.

## 9. Owner decisions (every PRD's open questions draw from here)

1. File extension (`.foldseq` placeholder) and the word "sequence source".
2. `nearMissBand` default (1e-3 sheet lengths proposed) for typed literals.
3. Auto re-anchoring (default) vs refusal when a move carries the anchor.
4. Precrease stiffness in the material model (D14).
5. SVG "wireframe": feature lines only or triangulation too (`--lines features|mesh`).
6. Textures (A2b): content and source.
7. Caption overlap/overflow policy (D7).
8. Blintz direction: which of the manifest's up-fold and the recipe's down-fold is canonical
   (A2 F3).
9. Whether `examples/quarter-fold-steps.fold` migrates to the state rule (moves two goldens) or
   stays as the regression.
10. Eighth-turn presentation using trig (written coordinates carry platform bits) vs a
    `sheet square as diamond` starting view.
11. The rule for external tools in AGENTS.md (D17).
12. Default-CI vs slow-job placement of crane-sized sequences; the triangle budget.

## 10. Corrections found by the research and reviews (proposed follow-ups; not filed)

Evidence tags: [code] read at cited lines · [jq] fixture measurement · [py] Python
re-implementation · [bin] prebuilt binary 2026-09-07 · [web] fetched · [measured] timed runs.

1. #95's half turn about x = 0 moves the model across the page and rescales it [jq, py].
2. #36 done-when 1 (reflection classified as turn-over) cannot be met; arrow kind from a changed
   assignment is ambiguous per motion (one quarter-fold motion changes V and M together) [code, jq].
3. #94: "nothing reads frame_title" is half stale (the CLI reads it); captions would move #60's
   golden [code].
4. #114's premises are stale (`--thickness` and face lifting removed; a 3:1 radius stretches a
   stacked bend) [code, notes].
5. #56's "per-face transforms are discarded" is stale (`foldedPlacements`) [code].
6. #104 cites `docs/notes/inflate-outside-draw-inside.md`, which does not exist [ls]; its done-when
   allows default goldens to change [issue].
7. #60's done-when exercises folding, not authoring; coordinates need a tolerance; "macros are
   compositions" is false [jq, code].
8. #96 says three papers, lists four; COrigami builds no move vocabulary [web].
9. `docs/related-projects.md`: Doodle GPLv2; ReferenceFinder GPL-2.0; origami-diagrams moved to
   `amkraft/`, MIT only in package.json; Oriedita `LICENSE.md` is MIT [web].
10. `docs/notes/huzita-hatori.md` dates disagree with Alperin & Lang (Justin and Huzita 1989;
    Hatori 2001/2002) [web].
11. `docs/glossary.md` defines rest angle twice, differently [code].
12. `check` silently skips Maekawa at any vertex touching a `U` edge and its report does not say
    so [code, bin].
13. `Creasing.existingAt` returns the first vertex within tolerance, not the nearest; the batch
    interning path takes the nearest [code].
14. `CraneWing`'s clip copies ThroughLayers' mapping without its length and midpoint guards; its
    "every U edge" hinge recovery works only because crane.fold has no U edges [code, jq].
15. The blintz manifest case folds corners up (+90/+175), the recipe down (−180) [jq, code].
16. `cases.json` literals at rabbit-ear m = 30 and petal t = 175 are one ulp from the documented
    `atan2` formulas; a `tan` form reproduces them [py].
17. At least nine tolerance formulas act as "a hair" [code].
18. `quarter-fold-steps.fold` writes M/V at angle 0, departing from the FOLD sign rule [jq, web].
19. `Rigid(..)` and `Mat3(..)` are exported and nothing checks a proper rotation [code].
20. Any filtered `stack test` run pays 15–20 s of `runIO` fixture setup [measured, 3 runs].
21. `creaseAllAlong` does not return new edge ids, which is why recipes mark new creases `U`
    [code].
22. GLB `extras.senbazuru.frame` writes raw doubles (angles, material coordinates, layer
    direction) that can carry platform trig bits [code].
23. #64's framing ("inflating a body is outside the model") is overtaken by #106 and the README
    [docs].
24. `Origami.Step`'s header says a turn-over is a motion; D5 changes that deliberately [code].
25. The study viewer's paper colours disagree with `Diagram.Style`'s (`viewer.html:168`) [code].
26. `docs/notes/a-crease-is-a-hinge.md` numbers (L* ≈ 200t, 30–40° Mylar rest) are not in the
    abstract of the cited paper (B "Unverified") [web].

## 11. PRD file plan and writing rules

**Files** (`PRDs/`):

| File | Owns | Main sources |
| --- | --- | --- |
| `README.md` | Index, reading order, one-page answer, decision summary (one line per D), milestone table, owner decisions, how to read evidence | this spine |
| `00-overview.md` | The two halves today with evidence; goals; non-goals; the shape (§2 picture); how the three features connect; honesty about what "realistic" means now | §1, §2, D18, D19 honesty; A1, B, C |
| `01-architecture.md` | Module DAG and layering rules; the two contracts; stated exceptions; the §3 recorded-text table written out in full; one step walked through with real numbers (quarter fold step 2) | §2, §3, D1, D13, D14 contract split |
| `02-language-semantics.md` | Semantics shared by both front ends: state and initialisation; references and resolution by slot; units; reader's side and presentation; moves; layers; stacking relations; macros; figures; repeat/checkpoint/not-modelled/expect-refused; assurance; written-frame rules; refusal catalogue | D2–D11, D21, D22, D4 |
| `03-prd-embedded-dsl.md` | Feature 1: builder, Refs, examples, printing, tests | D1, D12 round trip, §5, §7 EDSL |
| `04-prd-sequence-source-and-cli.md` | Feature 2: full EBNF, lexical rules, reserved words, error display, pretty printer, `run` verb, I/O, examples | D12, D13, D20, §6, §7 |
| `05-prd-library-additions.md` | Every fold-solver change the runner needs, each with signature, why, acceptance, "goldens unchanged" proof: `creaseAllAlongWith`, `creaseLayersThrough`, shared start check, ordered cover, `carryOrders`, `stackingWhere`, `fitRigid` + Step classification, `motionsAcross`/`creasesToCome`, `flapPoseAt`, `macroPoseAt`, `atRest`, `ThroughError` point, `Flap` stationary face export | D5, D6, D8, D10, D11, D4, D20 |
| `06-prd-step-diagrams.md` | `StepNote`, arrows, `Symbol`, captions, turn-over loop, figures with several moves, growing graphs on the page, arrow kind under views, goldens plan | D7, D5 page rules, D6, D22 |
| `07-prd-material-consumption.md` | Feature 3a: records → settle; hold/grip vocabulary; rest angles; settle blocks; material block and units; illustrations and failure scope; certificate registry; graduation stages and gates; external solvers and licences | D14, D15, D17, D10 registry |
| `08-prd-realistic-rendering.md` | Feature 3b: axes; M7a mode; glTF lines spike; A2b; W1 algorithm; wireframe question; G1 animation; metadata; #104 | D19 |
| `09-testing-and-acceptance.md` | Acceptance per milestone; quarter-fold tests; E1–E10; goldens unchanged; counted budgets; CI placement; angle equality; migration table | D16, gap-sequence-cost, gap-study-consumption (d) |
| `10-roadmap-risks-questions.md` | Milestones and order; issue mapping; risks; owner decisions; corrections (§10) | §8, §9, §10 |
| `glossary-additions.md` | The one copy of every new term, in glossary table format, one or two plain sentences each, with defining module or note | review-L4 §L4-18 list; D terms |

**Writing rules** (AGENTS.md "Audience and tone" and "Writing an explanation" apply in full):

- Reader: knows intermediate Haskell, has never folded paper. Define no term locally beyond one
  clause plus a link to `glossary-additions.md` (or `../docs/glossary.md`). Concrete before
  abstract: real coordinates from a command actually run. Name the line that looks like a typo.
  If an example can be misread, fix the example.
- Every code claim cites `path:line` actually read. Every measurement says how it was obtained
  (command, run count, machine) or cites the research note and its evidence tag. Never invent
  numbers. Every example sequence is checked against its fixture with jq/python3 and the command
  cited, or marked **UNVERIFIED** with what would verify it. No placeholders.
- Research cited by file name and section heading, not bare keys.
- PRD template (feature PRDs 03–08): Summary · Problem and evidence · Goals · Non-goals · Users
  and scenarios · Requirements (numbered `R-<file#>-<n>`, each testable) · Design (with rejected
  alternatives) · Acceptance criteria (each with the change that turns it red) · Dependencies
  (issues, milestones) · Risks · Open questions for the owner (from §9) · Research links.
  `00`–`02`, `09`, `10` use sensible structures of their own.
- Succinct: say it once, link for depth; tables for enumerations; sketches marked **SKETCH**.
- Nothing under `PRDs/` edits other repo files; follow-ups point at §3 or §10 items, reproduced
  in `01` and `10`.
- Links relative (`research/…`, `../docs/…`, `../src/Senbazuru/…`); issues as
  `[#60](https://github.com/avalonalex/senbazuru/issues/60)`.
- End with a reread as a Haskell programmer who has never folded.
