# Design spine — connecting the fold solver and the material study

> **Historical record.** Part of the design review of the PRD series, kept so its citations resolve. Line numbers cite the draft named in the file; the current decisions are [../../decisions.md](../../decisions.md).

Status: **draft for review**, 2026-09-14, against `568dcb6`. This is the
decision record every PRD file under `PRDs/` is written from. Research notes
live in `PRDs/research/`, keeping
their file names (A1, A2, B, C, D, E1, E2, F, G, Z-critic, gap-*), because they
cite each other by those keys.

The user's request, restated:

1. **Library:** an embedded Haskell DSL to define fold sequences and steps.
2. **CLI:** parse a similarly specified folding-sequence language from a file.
3. **Material:** the material study, when mature, takes what (1) and (2) define
   and produces realistic renderings, as 3D (glTF) and as an SVG wireframe.

Deliverable: research plus PRDs, no implementation.

---

## 0. What "the two halves" are, and what connecting them means

- **The fold solver** is the library's rigid pipeline: `Fold.Creasing`,
  `Fold.Crossings`, `Origami.Folding` (angles on a cut pattern → `Folded`),
  `Origami.Flap` + `Origami.HingeSweep` (one checked hinge turn),
  `Origami.ThroughLayers`, `Origami.Stacking`, `Origami.Surface`, and the
  renderers (`Render.Steps`, `Render.CreasePattern`, `Render.Gltf`). It can
  fold, check and draw a state, and check one hinge turn. It cannot be told a
  sequence: every sequence in the repo is a hand-written study recipe naming
  raw `EdgeId`/`FaceId`s (A2 F2–F5).
- **The material study** is `study/fold-material/`: a static, zero-thickness,
  held-boundary solver (Gauss–Newton on lengths, crease/panel angular springs,
  penalty and barrier contact, sparse factor), fixture recipes (crane wing
  spreading, closed-crease controls) and certified coupled routes
  (`CheckedBird`). Its only rigid→material path, `CraneSpread`, consumes one
  hand-built move (gap-study-consumption-contract F1).
- **They already share** `Origami.Surface` (material identity, positions,
  crease topology, optional thickness) and `Origami.Contact`/`HingeSweep`.
- **Connecting them** means three contracts that do not exist today:
  1. a *sequence* value both front ends produce (the DSL and the file);
  2. a *run* of that sequence by the library, producing per-step records with
     their evidence (what was checked);
  3. a *material consumer* that takes those records, not files, and produces
     settled surfaces and realistic renders — first in the study, later
     graduated into the library.

## 1. The shape, in one picture

```
 Haskell author                 text author (.fseq file)
      |                                |
 Sequence.Build (State builder)   Sequence.Parse (megaparsec, pure Text -> ...)
      \                                /
       v                              v
            Sequence.Syntax : Sequence  (first-order AST, spans, captions)
                 |        ^
                 |        | Sequence.Pretty (round trip)
                 v
            Sequence.Check (static: names, kinds, arity, finiteness)
            Sequence.Elaborate (repeat / precrease sugar -> core; keeps provenance)
                 |
                 v
            Sequence.Run   -- over Fold.* and Origami.* only
              threads FoldState, resolves references per step,
              enforces the handoff invariants, returns
                 |
                 v
            [StepRecord]  (Sequence.Record)   <-- contract #1, library, knows paper not drawing
             |          |             |                     |
             v          v             v                     v
   Sequence.Write   Render.Sequence   Render.Gltf       material consumer
   (state rule ->   ([(Frame,StepNote)] (per-state      study: settleStep :: SettleSpec -> StepRecord
    FoldFile)        -> stepPageWith)   Surface; later    -> Either SettleError Settled
                                        animation)       later: Senbazuru.Material.* + Sequence.Material
                                                                  |
                                                                  v
                                                    realistic glTF mode, SVG wireframe
```

Layer order after this work (each may import only leftwards):
`Geometry → Explain → Fold/Import → Origami → Numeric → Material → Sequence → Render → app`.
`Numeric` and `Material` are new and are introduced only at graduation (M8);
until then the material consumer lives in `study/`.

---

## 2. Decisions

Each decision: **what**, **why** (with research keys), **rejected**, **residue**.

### D1. One first-order AST, a deep embedding; the builder hands out names only

- **What.** `Sequence.Syntax` defines a first-order AST: no functions inside,
  `Eq`/`Show`, every step `Located` with a source span (`NoSpan` from Haskell).
  The EDSL is a `Build a = State BuildState a` whose binds return **names**
  (`Ref`), never geometry; `sequenceOf :: Build () -> Sequence`. The parser
  produces the same `Sequence`. Interpreters (check, elaborate, run, pretty,
  page projection, material consumption) are ordinary functions.
- **Why.** The request names at least four consumers of one sequence; a deep
  ADT gains interpreters by writing functions (Gibbons & Wu, F §B). A file can
  hold only first-order data, so anything carrying Haskell functions cannot
  round-trip (F finding 14, D A2). The builder's monad is harmless because
  only names flow through binds (F finding 17). Haskell loops unroll at build
  time: printing a built sequence shows the unrolled steps, which is correct.
- **Rejected.** Free/operational monads (continuations are functions; later
  steps could depend on results, which a file cannot express); tagless final
  (reading a file needs a typechecker into an existential); GADT-indexed AST
  (parser would have to typecheck); shallow embedding (cannot print or check).
- **Supersedes** #60's reason ("one interpreter, so no free monad") while
  keeping its conclusion (a plain ADT). Say so explicitly.
- **Residue.** Kind-indexed `Ref` for builder users is optional sugar and needs
  `DataKinds` (not in GHC2021) or empty phantom types; the untyped static pass
  is the source of truth either way. Recommend empty phantom types, no new
  extension.

### D2. References: names are material, constructions are evaluated where the paper is now

- **What.** Every reference a step makes to paper or geometry is **named on the
  unfolded sheet** (material coordinates, glossary) and **evaluated at the
  current state**. Ids (`EdgeId`, `FaceId`, mesh vertex ids) never appear in the
  language; they are step-local resolution outputs recorded in `StepRecord`.
- **Vocabulary** (text spelling in §5; AST in §4):
  - *Points:* `corner bottom-left|bottom-right|top-right|top-left`, `centre`,
    `(u, v)` with exact `Rational` numerals (`1/3`, `0.25`), `midpoint of L`,
    `fraction r along P-Q`, `meet L1 L2`, a `let`-bound name, and the escape
    `model (x, y)` (a point in the current model's coordinates **as seen**, flat
    states only, flagged "not a landmark" in the record).
  - *Lines:* sheet edges `edge bottom|right|top|left`; `P-Q` (the line through
    two points, Huzita–Hatori O1); `P to Q` (fold P onto Q, O2); `L1 to L2`
    (O3); `perpendicular to L through P` (O4); `P to L through Q` (O5);
    `P to L1 and Q to L2` (O6); `P to L1 perpendicular to L2` (O7); `crease P-Q`
    (fold along an existing crease, Lucero's eighth operation).
  - *Paper selectors:* `flap containing P` (a seed: the connected paper on the
    moving side once the hinge is cut, as `Flap` grows it), `top N layers`
    (counted along the line at each point, from the viewer's current side),
    `all layers` (default).
- **Resolution rules.**
  - Material point as a **region**: strictly inside exactly one face of the
    working pattern, else refuse naming the faces found (StudyCase precedent).
  - Material point as a **vertex** (`corner`, `centre`, landmark): within
    creasing's tolerance (`Fold.Faces.tolerance`, 1e-9 × sheet diagonal) of
    exactly one vertex; a near miss is refused naming the nearest vertex and its
    distance (gap-exact-landmarks F2–F3, E2 rule 1). Decimals are never promoted
    to constructions: `0.2071` stays a rational and misses.
  - Material segment (`crease P-Q`): every current edge lying on that line and
    overlapping it; refuse gaps when a hinge is required (E2 rule 2).
  - Constructions O1–O7: compute every real solution from current positions of
    the named points and lines; report off-paper solutions rather than drop
    them silently; for O3 (crossing), O5, O6, O7 require a disambiguator
    `nearest P` whenever more than one remains; accept exactly one (E2 rule 4).
  - Moving side for `P to Q` and `L1 to L2`: the side containing the first
    argument (books: "fold corner A to C" moves A). For `P-Q` and `crease P-Q`
    the step must name a `flap containing` seed. Reversing a line's endpoints
    never reverses a fold.
  - Constructions are evaluated only on **flat** states (flat sheet or
    flat-folded model, one plane). On states with paper in the air, only
    `crease P-Q` hinges and material seeds are allowed; constructions are
    refused by name.
  - Viewer-relative selectors (`top N layers`) resolve **once**, against the
    state's **accepted** layer order and the viewer's side, and the resolved
    material result is pinned in the record (E2 "resolve once and pin").
- **Why.** Rigid folding never adds or removes paper, so material coordinates
  are the fixed parameter domain CAD lacks for its topological naming problem
  (E2 §D). Every pattern-changing move renumbers edges and faces (A1 (c)).
  Books name references by alignment, which Huzita–Hatori formalises (E1, E2).
- **Rejected.** Raw ids (renumbered by cutting, A14); typed decimals as the
  primary form ("coordinates with extra steps", #97); exact algebraic landmark
  types in the library (Q(√2) is not closed under constructions and cannot hold
  the rabbit ear's constant; `cyclotomic` is GPL-3.0-only and unordered —
  gap-exact-landmarks F5–F6).
- **Residue.** Unifying the several "hair" tolerances (gap-exact-landmarks F2)
  is a prerequisite issue, not part of the language. `existingAt` returning the
  first rather than nearest vertex within tolerance (Creasing.hs:323-327) must
  be decided before a resolver relies on it; recommend refusing when two
  distinct vertices are within tolerance.

### D3. The runner owns the state and the handoff invariants

- **What.** `FoldState` (sketch §4):
  - the **working pattern**: the cut crease pattern with material coordinates,
    rings normalised counter-clockwise once at initialisation, the anchor's face
    first, **intent assignments** (M/V for every crease ever made, including
    precreased-and-flat ones), explicit `edges_foldAngle`;
  - accepted coplanar `faceOrders`, and directional layer requirements where a
    move supplied them;
  - the **anchor** as a material point; the **presentation** `Rigid`;
  - the **landmark table** (name → material point / segment / step);
  - crease provenance (which step created each material segment).
- **Invariants enforced by `Sequence.Run`, never by authors** (A2 F11–F19):
  1. carry accepted angles and orders onto the working pattern; never feed
     folded coordinates back as material;
  2. drop `frameExtras` and stale faces on every transform;
  3. re-fold after every handoff; never patch a `Folded` (`FlapStartMismatch`);
  4. re-resolve every id after a topology change;
  5. anchor by material point; after any re-trace, put the anchor's face first
     before any orders exist, or re-map orders; refuse a move whose moving set
     contains the anchor face, with a hint to re-anchor (`hold P` step,
     jump-free because the new root is aligned to its current placement);
  6. join check at every step, CheckedBird strength: positions within
     `1e-12 × span`, exact angles, topology, orders and material map;
  7. never re-solve a stacking silently: `layerOrderFor` only for a flat state
     with no accepted orders, and the choice is recorded (index plus the
     predicate that selected it, D11).
- **Why.** Every recipe repeats this policy by hand and they are not consistent
  about which frame receives the handoff (A2 F6); a latent winding hazard exists
  (A1 finding 6); anchoring by face order makes two individually correct states
  differ by a whole-model motion (chaining-checked-folds note).
- **Residue.** Caching one `Folded` per state conflicts with `Flap`'s deliberate
  rebuild; measure before optimising (gap-sequence-cost F6: ~7 folds per checked
  step, read from code).

### D4. Written frames follow the state rule; intent stays in the source

- **What.** Every frame `Sequence.Write` emits:
  - has `edges_foldAngle`, one entry per edge (refuse to write without it);
  - writes each non-B/C/J edge as `M` if its angle < 0, `V` if > 0, `F` if 0,
    with one named threshold constant;
  - never writes `U`, never writes M/V at 0;
  - carries `senbazuru:material_coords` (via `materialFrame`) so frames can be
    matched across growing crease graphs (D6).
  The working pattern (D3) keeps intent. Resuming a sequence requires its
  source, not its output. Types separate `WorkingPattern` from written `Frame`.
- **Why.** Only convention consistent with the FOLD spec's sign rule, the
  `Assignment` haddock and #72's `flatAngleFor`; gives `check` correct answers
  on precreases that end flat (writing them M at 0 produced a false Maekawa
  violation on the square base); needs no look-ahead, so a failing step can be
  reported before later steps run (gap-assignment-at-rest F1–F3, F19).
- **Rejected.** M/V at 0 (departs sign rule; false Maekawa; the fixture's
  convention); U at 0 (claims ignorance; silently skips Maekawa); target-state
  direction (needs the whole sequence evaluated before frame 1); J for
  not-yet-made creases (spec says treat J's faces as one; our code does not).
- **Consequences, stated plainly.**
  - `examples/quarter-fold-steps.fold` stays as it is (a folding regression);
    #60's done-when is amended to tolerance on coordinates and angles, with
    assignments by the state rule. Migrating the fixture is a separate, reviewed
    change that moves `quarter-fold-step-1.svg` and `quarter-fold-steps.svg`
    (measured in gap-assignment-at-rest F18).
  - Fold-here dashes on step pages come from `StepNote` (D7), not assignments.
  - The material consumer takes crease identity and rest-angle intent from the
    `StepRecord`, never from F/M/V in a written frame (`FoldBending` refuses a
    control on an F edge).
  - Macro binding (D9) reads target signs from the working pattern, not from
    written frames.

### D5. Turn-over and rotation are presentation; senses are read as the reader sees them

- **What.**
  - `turn over [left-right|top-bottom]` and `rotate N/D` are **presentation**
    steps: they update `FoldState.presentation`, a `Rigid` built from exact ±1
    matrices (never `rotationAbout … pi`; `sin π ≠ 0`), and move no paper. A
    presentation `Rigid` is always a proper rotation; reflections are refused
    (Rigid(..) is exported and unchecked today, A1).
  - The axis passes through the centre of the model's projected extent **in page
    axes**, with the camera basis chosen from the unturned frames, so the
    extent and page scale do not change (gap-step-annotation F12–F15). This
    corrects #95's axis at x = 0, which moves the quarter fold across the page
    and halves every figure's scale.
  - `valley`/`mountain` in a step are **as seen by the reader at that step**
    (book convention). The runner maps a sense through the presentation and each
    layer's way up to FOLD signs; `Flap` already derives per-segment signs from
    the stationary face (Flap.hs:208-216). `top N layers` counts from the
    viewer's current side.
  - Written frames are **presented** (a file re-rendered without notes shows the
    turned model). `Origami.Step` classifies a frame pair related by one
    whole-model rigid motion as a presentation change and infers no arrow;
    acceptance must show no existing arrow-bearing golden has such a pair.
- **Why.** A turn written into coordinates is lost or refused by the next
  `foldFrameWith` (`AlreadyFolded`; first-face re-anchoring) (A1, critic
  contradiction 2). An inferred arrow on a turn-over is wrong by construction:
  corner centroid ≠ extent centre, up to 0.0975 model units on the bird
  sequence (gap-step-annotation F13).
- **Rejected.** Turn-over as a frame move (#95, D, F sketch); reflection
  (FoldingAgent `flip`, Doodle — the mirror model); unpresented written frames
  (a re-rendered file would contradict its own captions).
- **Residue.** Whether "as seen" means through the page basis or from +z after
  presentation differs for bottom and isometric views; the PRD fixes it as
  "from the side the page's camera looks at, after presentation".

### D6. Crease graphs grow between frames; frames are matched by material identity (no backfill)

- **What.** Each written frame carries only the creases that exist at that
  state. `Origami.Step` gains `motionsAcross :: Frame -> Frame -> Either FoldError
  [Motion]`: `before`'s vertex ids must be a prefix of `after`'s with equal
  material coordinates; added vertices are placed on `before` by material
  interpolation on an edge or by the face's material→position affine map;
  groups are formed over `after`'s faces. `motionsBetween` is unchanged and is
  used when graphs are equal. `creasesToCome` gives a step's new creases at
  `before` positions for the page's fold-here line.
- **Why.** Backfill draws every future crease at step 1 and draws unfolded
  creases on folded figures as finished edges; the existing golden already
  shows it (gap-step-annotation F9). Vertex ids survive creasing and cutting;
  material coordinates name the same paper in every state.
- **Rejected.** Backfill (A); "A + birth" (still one graph for the whole
  sequence, a two-pass runner, unborn-edge visibility unverified).
- **Residue.** On bent panels the affine placement is approximate — acceptable
  for arrow ends only. `render --steps` on files without material coordinates
  and with differing graphs is refused, as today.

### D7. A typed step-annotation channel reaches the page; defaults stay byte-identical

- **What.**
  - `Render.Steps.stepPageWith :: Theme -> Budget -> Grid -> View -> Bool ->
    [(Frame, StepNote)] -> Either StepError (Maybe Diagram)`; `stepPage` becomes
    `stepPageWith … . map (\f -> (f, noNote))` — one implementation, identical
    bytes for every existing caller (about fifteen call sites).
  - `StepNote`: caption; arrows (`InferArrows | InferArrowsAs kind | GivenArrows
    | NoArrows`); presentation change applied to later figures; repeat range;
    layer selection; creases to come.
  - `Diagram` stays FOLD-ignorant: `ArrowPath` gains a head shape (solid =
    today, hollow half = mountain, hollow double = unfold) and body (plain =
    today, cleft tail = push) whose defaults emit today's bytes; one new
    `Shape`, `Symbol` — page-unit glyph (turn-over loop, rotate, repeat) at a
    model-unit anchor, contributing only its anchor to extents.
  - Captions are `Label`s placed by `Layout` at the model-space bottom of each
    cell (no page-unit bands — the recorded units bug); a trailing gutter only
    when some figure has a caption.
  - A step's caption is the instruction for the move **leaving** that figure
    (the arrow is drawn on the figure before the fold). `Sequence.Write` writes
    that caption as `frame_title` of the figure's frame; the last frame's title
    is the sequence's closing caption.
  - Notes are **not** persisted in FOLD in v1 (transforms drop extras; #73's
    file/frame key split comes first). `run -o steps.svg` renders with notes;
    re-rendering a written FOLD gets inferred arrows and titles only.
- **Why.** `Step` cannot infer caption, arrow kind (one quarter-fold motion
  changes a valley and a mountain together), precrease, push, turn-over,
  repeat or layer selection (C finding 27, gap-step-annotation table).
- **Rejected.** Vendor keys as the channel (dropped by transforms, GLB keeps
  three keys); #36's "kind from the changed assignment"; #94's page-unit band.
- **Residue.** Caption overflow (no font metrics) — PRD picks estimated-width
  truncation with a warning, open for the owner. Whether a stated arrow kind is
  cross-checked against inference.

### D8. Folding some layers of folded paper is a first-class move, with one small library addition

- **What.**
  - Library: `Origami.ThroughLayers.creaseLayersThrough :: Set FaceId -> V2 ->
    V2 -> Assignment -> Folded -> Either ThroughError Creased`, where `Creased`
    returns the pattern **and the new edge ids** (the suffix after cutting). The
    existing `creaseThroughLayers` becomes its all-faces case (goldens
    unchanged). Export an ordered-cover query built on `Visible.nearness` that
    refuses unordered overlaps. Add `carryOrders` mapping accepted orders from
    parent faces to child faces across a crease (exact, since a crease at angle 0
    moves no paper).
  - Selection rule (in the library, used by the runner): cut every crossed face
    along the line; `flap containing P` selects the seed's component; `top N
    layers` counts depth at each point along the line; then cut only the
    selected faces and walk from the moving side — refuse as coupled, naming the
    joining face, if the walk reaches the other side; refuse if a stationary
    face is nearer on the turning side (full refusal table in
    gap-layer-selective-folds).
  - If the constructed line lies along existing creases covering the selected
    faces, hinge on them without creasing (crane steps 15–23 fold along
    existing creases; ThroughLayers refuses that case today).
  - Unselected layers get **no** crease.
- **Why.** Of 28 steps in a traditional crane diagram, 12 fold some layers and
  7 of those along existing creases (gap-layer-selective-folds (e), reasoning
  plus a Python re-implementation). The rule reproduces CraneWing's hand-picked
  faces `[2,3,6,7]` on `crane.fold` (script evidence, to be confirmed in Haskell).
- **Residue.** The Python evidence must be reproduced with the library before
  a PRD relies on it; mark it so.

### D9. Coupled macro-moves are named angle relations with signatures, not compositions

- **What.**
  - v1 macros: `collapse at P`, `rabbit-ear at P`, `petal tip P`; later:
    squash, inside/outside reverse, sink, swivel, crimp — each only when its
    relation and signature are derived and tested.
  - Each macro = driving parameter (a `Rational` degree range), closed-form
    role formulas (one Haskell function each, shared by runner and tests),
    a **signature** matched on a *moving star* (current angles plus intent
    signs from the working pattern: six moving rays with sectors
    45,45,90,45,45,90 for a collapse; four rays, one lone assignment, for a
    rabbit ear; hinge + opening line + side creases with 22.5° geometry for a
    petal), role extraction, branch/sign choice.
  - Roles are unique within a match; matches are not (two fish ears, two bird
    petals), so a material-point disambiguator is required whenever more than
    one matches; refuse 0 or ≥2 listing candidates. Sector comparison uses
    `FlatFold`'s tolerance so `check` and the macro agree.
  - `together { … }` runs several macros' parameters in lockstep (the press).
  - `sample 30 60 90 …` chooses illustration poses in the macro's own parameter.
  - Escape hatch: `pose { crease P-Q to A; … }` sets angles on creases named by
    material segment. It is serialisable (the EDSL can generate it with Haskell
    functions at build time) and gets `StateOnly` assurance.
- **Why.** A petal's seven creases turn at three rates; flap turns cannot
  compose it (#60's premise is false, gap-exact-landmarks F15). Signatures were
  checked by hand against square, waterbomb, fish and bird fixtures (F9–F13).
- **Rejected.** Macros as compositions of flap turns (Foldinator); library
  exact certificates; a general coupled-angle solver as a prerequisite (#55
  stays independent).
- **Residue.** Petal geometry other than 22.5° is refused until derived;
  rabbit-ear "rays reach the edge or pass through still vertices" may be too
  strict on multi-molecule patterns.

### D10. Assurance is recorded per step, as evidence values

- **What.** `RouteEvidence` in the library:
  `NoMotion` (a crease drawn, no paper moved) | `Presented` (turn-over, rotate) |
  `StateOnly` (pose tables, checkpoints, instant flat folds) |
  `Sampled SampleReport` (coupled macro checked at poses: shared vertices,
  achieved angles, static crossings, orders at flat endpoints, sample spacing) |
  `SweptHinge CheckedFlap` (whole interval checked by `HingeSweep`).
  Certificates attach **after** the run, in the study, through a registry keyed
  by macro name **and** fixture fingerprint (`Certified | NoCertificateFor |
  Refused`), never downgraded. The CLI prints assurance per step; the writer
  records it as `senbazuru:assurance` on each frame after the last transform;
  the GLB extras whitelist gains that key only when present (existing GLB goldens
  unchanged).
- **Why.** Four strengths of evidence already coexist (gap-study-consumption
  F6); a realistic render must not be mistaken for a validated motion (A1
  implication 3, E1 implication 11); state, route and reachability are three
  questions (endpoints-and-routes note).

### D11. Stacking choices are stated as relations, never indices

- **What.** `start folded` (angles from the sheet's assignments) or any step
  that needs a stacking takes `layers <material point> above <material point>`
  relations along the anchor's +z; the runner solves, filters valid stackings by
  the relations, and refuses 0 or ≥2 survivors, listing how many and which
  relations would split them. The resolved index is recorded, never authored.
- **Why.** CraneWing picks index `[2]` of five; its test checks the tail
  relation, not the index (A2 F19, several-stackings note).

### D12. The text syntax: line-oriented, book words, exact numbers

- **What.** File extension `.fseq` (placeholder, owner to confirm). Line-oriented;
  `#` comments; a header (`fseq 1`, `title`, `sheet`, optional `material`
  block), then steps. A step starts with `step [name] "caption"` and runs to the
  next `step`; indentation is conventional, not significant. Numbers are exact:
  integers, decimals and `n/d` parse to `Rational`. Keywords are book words
  (`valley`, `mountain`, `fold`, `unfold`, `precrease`, `turn over`, `rotate`).
  Canonical formatting is whatever `Sequence.Pretty` prints. Full examples in §5.
- **Parser.** megaparsec 9.5.0 + parser-combinators 1.3.0 (both in the pinned
  lts-22.44 snapshot, BSD licences — critic spot check 21) in the **library**
  stanza. Errors: one `SequenceError` type with an `Explain` instance giving a
  one-line fragment (file:line:col, step index and name, the author's reference
  text), plus a separate `excerpt` function the CLI uses for a caret display.
  Library errors that name CLI flags (`creaseEndFlag` → `--from`) are
  translated to the sequence's own spelling.
- **Rejected.** JSON/YAML as authoring syntax (aeson errors are JSON paths, not
  lines; per-edge arrays need a calculator — F finding 19); indentation-
  sensitive syntax (whitespace errors are hard to explain); s-expressions
  (unfamiliar to folders); hand-written reader (grammar is nested enough:
  constructions, blocks). A JSON *machine encoding* of the same AST may come
  later (LLM-emitted programs), not in v1.
- **Round trip.** QuickCheck `parse (pretty s) == Right s` on generated ASTs with
  spans stripped, covering every constructor including captions and macros,
  `Rational` numbers, no NaN; plus goldens of pretty output and of error text.

### D13. CLI: one new verb, output chosen by extension; the parser lives in the library

- **What.**
  - `senbazuru run FILE.fseq -o OUT.fold` — the written sequence (default when
    `-o` ends in `.fold`, or stdout).
  - `-o OUT.svg` — the step page rendered with notes (`--columns`, `--view`,
    `--width`, `--height`, `--layer-budget` as `render --steps`).
  - `-o OUT.glb` — the final state (`--frame N` for another); `--animate` after
    M7.
  - `--check` — static check only, no geometry; `--report` — per-step assurance,
    resolved references and work counts (sweep intervals, refolds, triangles).
  - The CLI resolves `sheet "path"` through `Fold.Load`; the parser and runner
    stay pure. `run` never goes through `withFoldFile` (which would decode the
    sequence as FOLD).
  - Existing verbs and their outputs are untouched.
- **Why.** C findings 14–21; the CLI is untested by design, so all logic lives
  in the library.
- **Stated exception to "a new input format becomes a Frame and stops there":**
  a sequence is a program; it becomes a `Sequence` at the boundary and a
  `FoldFile` plus `[StepRecord]` when run. Nothing downstream of a written FOLD
  file may know it came from a sequence; `Render.Sequence` consumes records by
  design. To be added to AGENTS.md and architecture.md when implemented.

### D14. The material consumer takes StepRecords, and realism is a ladder, not a promise

- **What.**
  - `StepRecord` (library, `Sequence.Record`): label, macro path, move kind,
    `before`/`after :: Surface V2`, `RouteEvidence`, hinge seeds with resolved
    ids, moving seeds with resolved faces, stationary seed, new creases (as
    material segments), angles before/after, accepted orders, directional
    requirements (kept separate from orders), stacking choice, anchor,
    presentation. Full sketch §4.
  - Study first: `settleStep :: SettleSpec -> StepRecord -> Either SettleError
    Settled`, over B's kernel `settle :: SettleSpec -> Surface V2 -> …`, with
    `Settled { surface, report, verdict :: Accepted | Diagnostic [Reason] }`.
  - **Settle is not a function of the rigid state.** A checked rigid state is
    already an equilibrium when rest angles equal achieved angles (B finding 6).
    A settle request must state what differs: released holds, a moved grip, or
    rest angles different from the achieved ones.
  - Holds and grips are named against a record, never by id: `side stationary`,
    `side moving`, `across-hinge S`, `closed R`, `band S d0..d1` (distance from
    the hinge in the start pose, sheet units), `material-band u0..u1`,
    `crease-line P-Q`, `layer upper|lower of R`, set union/minus. Grip targets:
    `rigid-pose p` or a registered generator (`arc-grip root extra`). The table
    mapping every existing CraneSpread/CraneRoot/CraneBody/CraneInternal hold to
    this vocabulary is in gap-study-consumption-contract (b).
  - Physical parameters (sheet size, thickness, stiffness preset, rest-angle
    policy) live in the sequence's optional `material` block; per-step `settle`
    blocks attach requests to steps. **Display** parameters (fidelity level,
    display exaggeration, colours, camera, textures) are render options, never
    sequence data.
  - Failure policy: the library returns the verdict and never substitutes rigid
    geometry; the CLI refuses on `Diagnostic` and names reasons; an explicit
    `--rigid-fallback` renders the checked rigid state and records the fallback
    in glTF extras and SVG metadata; diagnostic meshes go to FOLD/complete-scene
    GLB only, never through the SVG painter.
  - Settles are independent per step from that step's rigid state; nothing
    settled is carried into the next step (only the study supports this today).
- **Fidelity ladder** (G finding 23, each output records its level):
  - **G0** rigid, faceted, zero thickness, static states — production today.
  - **G1** G0 animated along checked routes — nested glTF nodes along the
    folding spanning tree, hinge-located origins, keys turning each crease
    < 180°, loop-closing creases checked at sampled midpoints.
  - **G2** rounded creases and thickness offsets — **labelled schematic**; the
    study showed a stacked second bend stretches 200% (two-bends note).
  - **G3** bent panels with contact, static endpoints — study, fixture-driven,
    opt-in per step via `settle`.
  - **G4** animated flexible routes — none; research.
  - Appearance axis A0 (two flat colours, today) → A1 normals split at feature
    edges, averaged within panels → A2 `TEXCOORD_0` = material coordinates, fibre
    and crease-memory textures → A3 diffuse translucency once loaders support it
    (release-candidate extension; core fallback, never `extensionsRequired`).
  - Line-drawing axis W0 book notation on planar panels (today) → W1 provenance
    lines (source creases and boundaries, never dihedral thresholds) plus
    per-view silhouettes (#104) with hidden-line removal → W2 x-ray lines by
    quantitative invisibility (#48) and cut-aways (#49).
- **"Realistic" for an arbitrary sequence** therefore means, in order of
  availability: G0/G1 + A1/A2 + W1 (production-feasible, no new physics);
  opt-in G3 on steps the author marks; G2 only as a labelled schematic;
  default springback rest angles are research (the crane solve fails there).
- **SVG wireframe** consumes `Diagram` (architecture rule): feature edges by
  provenance, silhouettes per view, hidden lines removed via `Render.Projected`
  on refined convex triangles; where `Projected` declines (intersecting within
  tolerance, depth ties), refuse by name and point to the complete-scene GLB.
  Measure `Projected`'s pairwise cost on refined meshes before promising sizes.
- **Realistic glTF** is a new export mode, never a change to the default bytes:
  `NORMAL` split at `surfaceFeatures` edges; optional `LINES` primitives from
  feature edges; `TEXCOORD_0` from material coordinates; colours from
  `Diagram.Style` so viewers agree; `KHR_materials_sheen` optional; never
  `KHR_materials_volume` on a sheet; animation per G1; morph targets only as a
  crossfade between densely sampled checked states; no skinning across fillets.

### D15. Graduation from study to library is staged and gated

- **Order** (B graduation, each a self-contained PR):
  1. split generic pieces out of fixtures (`ContactRow`, generic measures out of
     `FoldContact`/`FoldMaterial`; delete `PacketContact` from `ContactMode`);
  2. `Senbazuru.Numeric.Sparse` (from `SparseSolve`, knows no paper) and
     `DirectionalDistance`;
  3. surface-based `FoldBending` → `Material.Bending`;
  4. `SurfaceContact` penalty + barrier rows → `Material.Contact`;
  5. `relaxPinnedHinges`/`relaxPinnedContact` + bounded diagnostics, structured
     errors (no `newtype … Text`) → `Material.Relax`;
  6. one export adapter (from `spreadSurface`) and one acceptance report (from
     `spreadAccepted`) → `Material.Export`, `Material.Verdict`;
  7. `Material.Settle` and `Sequence.Material` (hold resolution against
     records).
- **Gates.** #208's value-only line-search evaluation lands first with equal
  energies and unchanged accepted/rejected controls; a stated triangle budget
  per settle; long solves never in default CI (slow job, fixtures in
  `beforeAll`).
- **Stays in study:** `ContactQuadratic`, `CreasePairContact`, `CoupledCrease`,
  `UnequalCrease`, `CreaseInequality`, discovery/history/correction-sweep modes,
  `ClosedCrease`, `FoldMaterial` rounded bends, all `Crane*`/`Wing*` recipes and
  galleries, `PetalCertificate` and the certificate registry.

### D16. Testing: counted budgets, goldens unchanged, one end-to-end fixture in default CI

- Existing 33 tracked goldens stay byte-identical (check: `git diff --name-only
  origin/main -- test/golden/` lists only goldens a feature adds).
- End-to-end acceptance table E1–E10 (gap-sequence-cost-and-test-budget) on a
  small default-CI sequence (blintz-sized, no creasing through layers so no
  trig-derived GLB JSON numbers); crane-sized sequences behind a slow job.
- Every assertion names the change that would turn it red.
- Budgets are counted work per step (`sweepIntervals` against 4096, refolds,
  triangles, pair counts), not seconds; wall-clock guards only after
  measurement. Measured so far: any filtered `stack test` run pays ~15–20 s of
  `runIO` fixture setup (3 runs, loaded machine) — expensive fixtures must move
  to `beforeAll`.
- Angle equality policy: exact only for driving parameters, copied literals,
  guarded endpoints; everything formula-derived uses one named tolerance.
- Migration: blintz then helmet become sequences first (equivalence PR, then
  deletion PR); crane wing waits for D8; the bird waits for D9 and the
  certificate registry; frog, six bases and most of `cases.json` stay fixtures
  (migration table in gap-study-consumption-contract (d)).

### D17. Third-party and external tools

- Running an external program and reading its output is not vendoring; it needs
  a row in `docs/related-projects.md` with the licence **of the program as
  built**, provenance for kept outputs, and no CI dependency. Proposed wording for
  AGENTS.md; do not edit AGENTS.md in this deliverable.
- Origami Simulator (MIT) as an oracle via #53, manually or by browser
  automation — it has no headless mode per its README. ipc-toolkit (MIT) is a
  library, not a solver. Codim-IPC (Apache-2.0) default build links GPL CHOLMOD
  Supernodal; user-installed only, `WITH_GPL=OFF`/Eigen if ever used.
- GPL sources (Doodle GPLv2, Rabbit Ear GPL-3.0, ReferenceFinder GPL-2.0, Creasy
  GPL-3.0, ORIPA GPL-3.0) are ideas only. Example sequences fold traditional or
  generated models only.

### D18. Non-goals

- A sequence **solver** or search over the vocabulary (no-sequence-solver's
  first reason becomes a statement about the field, not about senbazuru; update
  the note with #96).
- A general coupled-angle solver (#55) as a prerequisite; sliding contact;
  automatic hold selection; calibrated paper; pressure/inflation (#106); wet
  folding.
- Persisting step notes in FOLD before #73; resolving `frame_inherit` (#102).
- Reading OrigamiBench/FoldingAgent/Learn2Fold id-based programs in v1.

---

## 3. Milestones (for the roadmap PRD)

| M | Name | Contents | Closes / advances |
| --- | --- | --- | --- |
| M0 | Decisions on record | `docs/notes/sequences.md` (the #97 decision), glossary entries, the state rule, stated exceptions drafted for AGENTS.md/architecture.md, stale-issue corrections | closes #97; amends #60, #95, #36, #94, #114, #56, #104 texts |
| M1 | Language without geometry | `Sequence.Syntax`, `Build`, `Parse`, `Pretty`, `Check`; `run --check`; round-trip property | #60 (part) |
| M2 | Rigid runner, flat-sheet vocabulary | references D2 on flat states; `fold`/`unfold`/`precrease` along constructions and existing creases through all layers; checked hinges; presentation; anchor; state-rule writer; `run -o .fold/.glb`; blintz and helmet equivalence | #60 (part), #95, #58 items 3–4, #109/#110 where touched |
| M3 | Step pages that read like a book | `StepNote`, `stepPageWith`, arrow heads, `Symbol`, captions, `motionsAcross`, `creasesToCome`; `run -o .svg` | #36, #94, #95 loop |
| M4 | Folding some layers | `creaseLayersThrough` + new ids, ordered-cover query, `carryOrders`, selectors, stacking relations; crane-wing prefix as a sequence | #70 revisited, #54 (part) |
| M5 | Coupled macros | collapse, rabbit ear, petal with signatures, `together`, `sample`, `pose`; `Sampled` evidence; study certificate registry; bird route as a sequence | #54, #61 (part); #55 unblocked, not required |
| M6 | Study consumes records | `StepRecord` finalised, `settleStep`, hold vocabulary, `material`/`settle` blocks parsed and passed through; crane spreading re-expressed; `senbazuru-material-study --sequence FILE DIR` | #195 follow-ups, #114 (rewritten) |
| M7 | Realistic output without new physics | realistic glTF mode (A1/A2, lines), SVG provenance wireframe + silhouettes (W1), glTF animation of checked routes (G1) | #56, #104, #48 (part) |
| M8 | Graduation | D15 stages 1–7, `run --settle` in the CLI | #208 gate; #106 later |
| R | Research track | G2 thickness/rounded creases at vertices, unheld equilibrium, calibration, exact contact at scale, springback rest angles, G4 | #114, #106, #64 |

Order constraints: M1 → M2 → {M3, M4} → M5; M2 → M6 → M8; M3 → M7 (wireframe
and animation reuse page and record plumbing); #208 gate before M8.

## 4. Type sketches (names every PRD uses; SKETCH, not implementation)

```haskell
-- Senbazuru.Sequence.Syntax
data Span = Span !FilePath !Int !Int !Int !Int | NoSpan
data Located a = Located { locSpan :: !Span, locValue :: !a }
newtype Name = Name Text

data Corner = BottomLeft | BottomRight | TopRight | TopLeft
data Side = BottomEdge | RightEdge | TopEdge | LeftEdge
data Sense = Valley | Mountain                         -- as seen by the reader (D5)

data Point
  = CornerOf Corner | Centre | AtMaterial Rational Rational
  | MidpointOf Line | FractionAlong Rational Point Point | Meet Line Line
  | PointNamed Name | InModel Rational Rational         -- escape hatch, flat states only
data Line
  = EdgeOf Side | Through Point Point                  -- O1
  | Onto Point Point                                   -- O2 (first argument moves)
  | LineOnto Line Line (Maybe Point)                   -- O3 (+ nearest disambiguator)
  | PerpendicularThrough Line Point                    -- O4
  | PointToLineThrough Point Line Point (Maybe Point)  -- O5
  | TwoPointsToTwoLines Point Line Point Line (Maybe Point) -- O6
  | PointToLinePerpendicular Point Line Line           -- O7
  | ExistingCrease Point Point                         -- Lucero's eighth
  | LineNamed Name
data Layers = AllLayers | TopLayers !Int | FlapContaining Point
data Amount = ToFlat | Degrees Rational
data Relation = Above Point Point                      -- along the anchor's +z

data Step
  = Fold Sense Line Layers Amount (Maybe Point)        -- optional explicit moving seed
  | Unfold Name                                        -- reverse a named earlier step
  | Precrease Sense Line Layers                        -- elaborates to Fold + Unfold
  | TurnOver PageAxis | Rotate Rational
  | Hold Point                                         -- re-anchor, jump-free
  | Let Name Binding
  | StartFolded [Relation]
  | Macro MacroName [MacroArg] ParamRange              -- collapse / rabbit-ear / petal
  | Together [Step]
  | Pose [(Point, Point, Rational)]                    -- crease P-Q to angle; StateOnly
  | Repeat Symmetry [Name]
  | ExpectRefused RefusalKind Step
data Binding = BindPoint Point | BindLine Line
data StepHeader = StepHeader { stepName :: Maybe Name, stepCaption :: Maybe Text, stepSamples :: [Rational], stepSettle :: Maybe SettleRequest }
data Sequence = Sequence { seqTitle :: Maybe Text, seqSheet :: SheetSource, seqAnchor :: Point, seqMaterial :: Maybe MaterialSpec, seqSteps :: [Located (StepHeader, Step)] }
data SheetSource = UnitSquare | SheetFile FilePath

-- Senbazuru.Sequence.Build
newtype Build a = Build (State BuildState a)
newtype Ref k = Ref Name                               -- k: empty phantom types PointK | LineK | StepK
sequenceOf :: SequenceHeader -> Build () -> Sequence

-- Senbazuru.Sequence.Parse / Pretty / Check
parseSequence :: FilePath -> Text -> Either SequenceError Sequence
prettySequence :: Sequence -> Text
checkSequence :: Sequence -> Either SequenceError Checked

-- Senbazuru.Sequence.Run
data FoldState   -- abstract: WorkingPattern, orders, requirements, anchor, presentation, landmarks, provenance
runSequence :: RunSettings -> Frame -> Checked -> Either SequenceError Run
data Run = Run { runRecords :: [StepRecord], runFinal :: FoldState }

-- Senbazuru.Sequence.Record
data RouteEvidence = NoMotion | Presented | StateOnly | Sampled SampleReport | SweptHinge CheckedFlap
data StepRecord = StepRecord
  { recordIndex :: !Int, recordSpan :: !Span, recordLabel :: !(Maybe Text), recordPath :: ![Name]
  , recordMove :: !MoveKind, recordBefore :: !(Surface V2), recordAfter :: !(Surface V2)
  , recordEvidence :: !RouteEvidence
  , recordHinge :: ![(MaterialSegment, [EdgeId])], recordMoving :: ![(MaterialPoint, [FaceId])]
  , recordStationary :: !(Maybe (MaterialPoint, FaceId))
  , recordNewCreases :: ![(MaterialSegment, Assignment)]
  , recordAngles :: !([Double], [Double]), recordOrders :: ![FaceOrder]
  , recordRequirements :: !(Maybe (V3, [(FaceId, FaceId)]))
  , recordStacking :: !(Maybe StackingChoice), recordAnchor :: !MaterialPoint
  , recordPresentation :: !Rigid, recordResolved :: ![ResolvedReference], recordCost :: !StepCost }

-- Senbazuru.Sequence.Write
writeSequence :: Run -> Either SequenceError FoldFile  -- state rule, material coords, titles, assurance

-- Senbazuru.Render.Sequence
stepNotes :: Run -> [(Frame, StepNote)]

-- Errors
data SequenceError
  = ParseFailed ParseProblem
  | StaticRefused Span StaticProblem          -- Unbound, Redefined, WrongKind, Arity, NonFinite
  | ResolveRefused Int Span Text ResolveProblem  -- NoSolution, Ambiguous [candidate], OffPaper, NearMiss nearest distance, SeedNotInOneFace [FaceId], ...
  | StepRefused Int Span (Maybe Text) MoveFailure -- wraps FoldError, FlapError, ThroughError, SelectionError, MacroBindError, JoinMoved, AnchorMoves, StackingChoiceError
instance Explain SequenceError
excerpt :: Text -> SequenceError -> Maybe Text   -- caret display for the CLI

-- study first, Senbazuru.Material.* after graduation
data SettleSpec = SettleSpec { settleRefinement :: Refinement, settleStiffness :: Bending, settleRest :: RestAngles
                             , settleHolds :: [Region], settleGrips :: [(Region, GripTarget)], settleContact :: ContactSpec, settleBudget :: Settings }
settleStep :: SettleSpec -> StepRecord -> Either SettleError Settled
data Settled = Settled { settledSurface :: Surface V2, settledReport :: SettleReport, settledVerdict :: Verdict }
data Verdict = Accepted | Diagnostic [Reason]
```

## 5. Example sequences (text and EDSL must be written for the same models)

These are **sketches**; every writer must re-derive details (which half moves,
which sense, which edges) from the fixtures with `jq` and cite what they ran.
Known facts to respect:

- `examples/quarter-fold-steps.fold`: 9 vertices, 12 edges, 4 faces; edges 8–11
  go `0` → `[-180, 0, -180, 0]` → `[-180, 180, -180, -180]`; frame 1 extent
  x∈[0.5,1], y∈[0,1]; frame 2 x∈[0.5,1], y∈[0,0.5]; frame titles are states.
- `examples/blintz-base.fold`: edges 8–11 are the corner creases (0.5,0)–(1,0.5),
  (1,0.5)–(0.5,1), (0.5,1)–(0,0.5), (0,0.5)–(0.5,0), all `M`, recipe travel −180,
  then reopen edge 8 with +180.
- `examples/crane.fold` wing line is folded y = 1/4, faces `[2,3,6,7]`, travel +90
  accepted, −90 refused; stacking index 2 (tail tucked).
- `examples/bird-base.fold` route: collapse, front petal 0–175, back petal 0–175
  with front held, press both 175–180; anchor `(0.58, 0.4)`; petal hinge 26 and
  27; tips at material corners.

Text (sketch):

```text
fseq 1
title "A square folded into quarters"
sheet square
anchor (1/4, 1/4)

step half "Fold the left half behind, onto the right."
  fold mountain edge left to edge right

step quarter "Fold the top half behind, onto the bottom."
  fold mountain edge top to edge bottom
```

```text
fseq 1
title "Blintz base, then reopen one corner"
sheet "examples/blintz-base.fold"
anchor centre

step c1 "Fold the first corner to the centre."
  fold mountain corner bottom-right to centre     # lies on an existing crease: no new crease
step "Fold the second corner to the centre."
  fold mountain corner top-right to centre
step "Fold the third corner to the centre."
  fold mountain corner top-left to centre
step "Fold the last corner to the centre."
  fold mountain corner bottom-left to centre
step "Reopen the first corner."
  unfold c1
```

```text
fseq 1
title "Bird base from a square base"
sheet "examples/bird-base.fold"
anchor (0.58, 0.4)

step "Collapse into a square base."
  collapse at centre
  sample 30 60 90 120 150 175
step front "Petal fold the front flap up."
  petal tip corner bottom-right to 175
step "Petal fold the back flap behind."
  petal tip corner top-left to 175
step "Press both petals flat."
  together
    petal tip corner bottom-right to 180
    petal tip corner top-left to 180
```

```text
fseq 1
title "Lower one crane wing"
sheet "examples/crane.fold"
anchor (0.5, 0.5)                    # writer: pick a point in face 0 and verify
start folded
  layers (tail point) above (body point)   # writer: express the tail-tucked relation by material points

step "Fold one wing down along the line."
  fold valley 90 model (0, 1/4)-(2, 1/4) flap containing (0.02, 0.97)
  # sense as seen from +z: writer to verify against CraneWing +90 accepted / -90 refused

step "Spread the wing."            # M6: request only; rigid state unchanged
  settle
    refine moving 3
    hold closed side stationary
    hold band moving 0..1/32 at rigid-pose 1/3
    grip band moving 7/32.. arc-grip 30 50
```

EDSL (sketch, same blintz):

```haskell
blintz :: Sequence
blintz = sequenceOf (header "Blintz base, then reopen one corner" (sheetFile "examples/blintz-base.fold") centre) $ do
  c1 <- step "Fold the first corner to the centre." $ fold Mountain (cornerOf BottomRight `onto` centre)
  forM_ [TopRight, TopLeft, BottomLeft] $ \c ->
    step_ "Fold the next corner to the centre." $ fold Mountain (cornerOf c `onto` centre)
  step_ "Reopen the first corner." $ unfold c1
```

(Printing `blintz` yields four explicit fold steps; the `forM_` is gone — D1.)

## 6. Corrections found by the research (to list in the roadmap PRD, not to file)

Evidence strength in brackets: [code] read at cited lines, [jq] measured on
fixture, [py] Python re-implementation, [bin] prebuilt binary from 2026-09-07,
[web] fetched source.

1. #95's half turn about x = 0 moves the model across the page and rescales it
   [jq, py].
2. #36 done-when 1 (reflection classified as turn-over) cannot be met; arrow
   kind from changed assignment is ambiguous per motion [code, jq].
3. #94's "nothing reads frame_title" is half stale (CLI reads it) and captions
   would move #60's golden [code].
4. #114's premises are stale (`--thickness` and face lifting removed; 3:1 radius
   stretches a stacked bend) [code, notes].
5. #56's "per-face transforms discarded" is stale (`foldedPlacements`) [code].
6. #104 cites `docs/notes/inflate-outside-draw-inside.md`, which does not exist
   [ls].
7. #60's done-when exercises folding, not authoring; coordinates need a
   tolerance; "macros are compositions" is false [jq, code].
8. #96 says three papers, lists four; COrigami builds no move vocabulary [web].
9. `docs/related-projects.md`: Doodle is GPLv2; ReferenceFinder GPL-2.0;
   origami-diagrams now at `amkraft/` with MIT only in package.json; Oriedita
   `LICENSE.md` is MIT [web].
10. `docs/notes/huzita-hatori.md` dates disagree with Alperin & Lang (Justin and
    Huzita 1989; Hatori 2001/2002) [web].
11. `docs/glossary.md` defines rest angle twice, differently [code].
12. `check` silently skips Maekawa at any vertex touching a `U` edge and its
    report does not say so [code, bin].
13. `Creasing.existingAt` returns the first vertex within tolerance, not the
    nearest [code].
14. `CraneWing`'s clip copies ThroughLayers' mapping without its length and
    midpoint guards; its hinge recovery by "every U edge" works only because
    crane.fold has no U edges [code, jq].
15. The blintz manifest case folds corners up (+90/+175) while the recipe folds
    them down (−180) [jq, code].
16. `cases.json` literals at rabbit-ear m = 30 and petal t = 175 are one ulp
    from the documented `atan2` formulas; a `tan` form reproduces them [py].
17. At least nine different tolerance formulas act as "a hair" [code].
18. `quarter-fold-steps.fold` writes M/V at angle 0, departing from the FOLD sign
    rule [jq, web spec].
19. `Rigid(..)` is exported and nothing checks a rotation; `transformSurface`
    would accept a mirror [code].
20. Any filtered `stack test` run pays ~15–20 s of `runIO` fixture setup
    [measured, 3 runs, loaded machine].
21. `creaseAllAlong` does not return new edge ids, which is why recipes mark new
    creases `U` to find them [code].
22. GLB `extras.senbazuru.frame` writes raw doubles (angles, material
    coordinates, layer direction) that can carry platform-dependent trig bits
    [code].
23. #64's framing ("inflating a body is outside the model") is overtaken by
    #106 and the README [code, docs].

## 7. Writing rules for every PRD file

- Audience: AGENTS.md "Audience and tone" and "Writing an explanation". Define
  or glossary-link every term; concrete before abstract; name the line that
  looks like a typo. Terms new to the repo are defined once in
  `PRDs/00-overview.md` §Vocabulary and linked from other files.
- Every claim about the code cites `path:line` actually read; every measurement
  says how it was obtained (command, run count) or cites the research note that
  measured it with its evidence tag; never invent numbers; mark sketches
  `SKETCH`.
- PRD template: Summary · Problem and evidence · Goals · Non-goals · Users and
  scenarios · Requirements (numbered `R-<file>-<n>`, each testable) · Design
  (with rejected alternatives) · Acceptance criteria (each with "the change that
  turns it red") · Dependencies (issues) · Risks · Open questions for the owner ·
  Research links.
- Succinct: say it once; link the research note for depth; tables for
  enumerations.
- No file under `PRDs/` edits or proposes edits to other repo files except as
  listed follow-ups.
- Links: relative (`research/A1-library-fold-solver.md`, `../docs/glossary.md`,
  `../src/Senbazuru/Origami/Flap.hs`); issues as
  `[#60](https://github.com/avalonalex/senbazuru/issues/60)`.
