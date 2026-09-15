# Review L4 — repository conventions, recorded owner decisions, internal consistency

> **Historical record.** Part of the design review of the PRD series, kept so its citations resolve. Line numbers cite the draft named in the file; the current decisions are [../../decisions.md](../../decisions.md).

Spine reviewed: [`decisions-draft-v1.md`](decisions-draft-v1.md) (905 lines, draft of 2026-09-14,
against `568dcb6`). Nothing built or run. Evidence is `file:line` read, `jq` or
`python3` on fixture JSON, `grep` over imports, and `gh issue view N --json
body,comments` for #36, #58, #60, #73, #94, #95, #97, #110, #111.

Severity key: **critical** = a PRD written from the decision is wrong or
unbuildable; **major** = materially wrong or missing something the PRDs need;
**minor** = wording, naming, small gaps.

Import graph used throughout (library modules, `Senbazuru.*` imports only,
from `grep -E '^import( qualified)? +Senbazuru\.'` over `src/`):

- `Explain`, `Fold.Types`, `Geometry.VectorSpace` import nothing in the project;
  `Geometry` imports only `Geometry.VectorSpace`.
- `Diagram.Style` imports `Diagram`, **`Fold.Types`**, `Geometry`.
- `Origami.Surface` imports `Origami.Folding`; `Origami.Contact` imports
  `Surface`; `Origami.HingeSweep` imports `Contact`, `Surface`.
- No `Origami.*` module imports `Diagram.*` or `Render.*`.
- `Render.Steps` imports `Diagram.*`, `Origami.Stacking`, `Origami.Step`,
  `Render.Camera`, `Render.CreasePattern`.
- `Render.Gltf` imports `Diagram`, `Diagram.Style`, `Origami.Stacking`,
  `Origami.Surface`, `Render.PaperMesh`.
- Study: `SparseSolve` and `DirectionalDistance` import only `Geometry.V3` and
  `Geometry.VectorSpace`.

---

## L4-1 (critical) — D5: the presentation axis needs the page camera, but the runner may not import one

**Claim.** D5 puts the presentation `Rigid` in `FoldState`, owned by
`Sequence.Run`, and writes **presented** frames. It also fixes the turn axis
"through the centre of the model's projected extent **in page axes**, with the
camera basis chosen from the unturned frames". Its residue reads "as seen" as
"from the side the page's camera looks at". Those rules make the runner's output
depend on the render camera. There are two ways out, and both break a rule the
spine sets for itself:

- The runner imports `Render.Camera`/`Render.CreasePattern.basisFor`. That
  breaks §1 ("`Sequence.Run` — over `Fold.*` and `Origami.*` only") and the
  layer order (`Sequence` before `Render`).
- Or the runner gets a `View`. Then `run x.fseq -o x.fold` writes different
  coordinates, and possibly different mountain/valley signs, depending on a
  `--view` flag. D14 says the camera is "a render option, never sequence data",
  and D13 gives `-o .fold` no `--view` at all.

**Evidence.**
- spine §1 line 62, layer order line 80, D5 lines 252-256 and residue 274-276,
  D13 lines 451-455, D14 lines 496-498, §4 `runSequence :: RunSettings -> Frame
  -> Checked -> …` line 689 (no `View`).
- `basisFor :: View -> [V3] -> Basis` lives in `Render/CreasePattern.hs:509-510`;
  `View` in `Render/Camera.hs:188`.
- gap-step-annotation-channel, table at line 327: "Sequence gives the axis; the
  page gives where it passes". F15 (lines 236-243): "the basis depends on the
  vertices … pick the basis from the unturned frames (or the named view), then
  turn". The research put the axis's position on the page; D5 moved the `Rigid`
  into the runner without moving that dependency.

**Proposal.** Replace D5's second bullet and its residue with:

> The presentation is defined in **model axes**, never page axes.
> `turn over left-right` is a half turn about the model's y axis;
> `turn over top-bottom` is a half turn about its x axis. Both pass through the
> centre of the model's bounding box (x, y and z) at that step. `rotate` turns
> about z through the same centre. The runner computes this from vertex
> positions alone, so `run -o .fold` output is independent of any view.
>
> "As seen" means from +z of the presented model, which is exactly what
> `topDown` shows (`Render/Camera.hs:106-107`). `Render.Steps` keeps its single
> basis chosen from all frames (`Steps.hs:107`). Under `topDown`, a turn about
> the box centre leaves the extent unchanged (gap-step-annotation F13). Under
> isometric or a named view, the PRD measures on `bird-base-sequence.fold`
> whether the extent changes, and says so on the page if it does.

---

## L4-2 (major) — Layer order: `Diagram` is missing, `Numeric` is misplaced, and graduated `settleStep` would create a cycle

**Claim.** `Geometry → Explain → Fold/Import → Origami → Numeric → Material →
Sequence → Render → app` has four problems:

1. **It omits `Diagram`.** `Diagram.Style` imports `Fold.Types`, and
   `Render.Gltf` and `Render.Steps` import `Diagram.*`. The architecture rule
   "Origami must not mention a diagram" (`architecture.md:150-153`) is a
   sibling constraint, and a chain cannot express it.
2. **It places `Numeric` after `Origami`,** which licenses `Numeric.Sparse` to
   import paper. D15 describes that module as "knows no paper". The study
   sources it graduates from import only `Geometry.V3`/`VectorSpace`.
3. **It reads as `Explain` may import `Geometry`.** `architecture.md:143-148`
   says `Explain` "depends on nothing in the project either".
4. **It invites a cycle at graduation.** §4 line 721 labels
   `settleStep :: SettleSpec -> StepRecord -> …` "study first,
   Senbazuru.Material.* after graduation", and D15 stage 7 lists
   `Material.Settle`. A `Material.Settle` exporting `settleStep` imports
   `Sequence.Record`, which the order places to its right.

**Evidence.** The import graph above; spine line 80, D15 lines 545-554, §4
lines 721-726; `architecture.md:142-153`; gap-study-consumption-contract line
435 puts `settleStep` "study-side". `SparseSolve <- Geometry.V3
Geometry.VectorSpace`; `DirectionalDistance <- Geometry.V3
Geometry.VectorSpace`.

**Proposal.** State the order as a DAG, not a chain:

> Bottom, importing nothing in the project but each other: `Geometry.*`,
> `Explain`, `Numeric.*`.
> Then `Fold.Types` → `Import.*` → `Fold.Query`/`Faces`/`Crossings`/`Creasing`
> → `Fold.Load`.
> Then `Diagram.*` (after `Fold.Types`) and `Origami.*` (after `Fold.*`); these
> two never import each other.
> Then `Material.*`, after `Origami`. It takes `Surface V2` and never a
> `StepRecord`.
> Then `Sequence.*`. `Sequence.Material.settleStep` resolves holds against a
> record and calls `Material.Settle.settle`.
> Then `Render.*`, then `app`.

---

## L4-3 (major) — The stated exception and the supersessions miss the recorded text they overturn, and say three different things about where they land

**Claim.** The spine frames D13 as an exception only to "a new input format
becomes a `Frame`". The recorded text it most directly contradicts is
`architecture.md:81-86`:

> Everything an authoring vocabulary (#60) adds will have that shape, and will
> reach the rest of the pipeline the way a file does — by being a `Frame` that
> `Fold.Query` cannot tell from one somebody wrote by hand.

`Render.Sequence` and the material consumer both take `StepRecord`s, "not
files" (§0 contract 3, D14). That is exactly what this paragraph rules out.

D1 supersedes only #60's *reason* ("one interpreter"). It also silently drops
two more #60 decisions: `apply :: Move -> Frame -> Either MoveError Frame`, and
`scanl` giving `[Frame]`. #95's `apply TurnOver` goes the same way. The runner
threads `FoldState`, not `Frame`. The study's recorded "not an instruction
language" (`architecture.md:206-207`; D research A19) is also overturned
without a note.

Where these land is inconsistent:

- D13: added to AGENTS.md/architecture.md "when implemented";
- M0: "drafted";
- D17: "proposed wording for AGENTS.md", but none is given;
- §7: "no file under PRDs/ … proposes edits except as listed follow-ups", and
  there is no list.

**Evidence.** `architecture.md:81-86`, `:170-175`, `:206-207`;
`AGENTS.md:193-197`, `:376` ("Record lasting decisions in the repository");
#60 body, Approach and first code block; #95 Approach ("`apply :: Move -> Frame
-> Either MoveError Frame`"); spine D1 lines 108-109, D13 lines 465-469, D17
lines 587-589, M0 line 615, §7 lines 901-902.

**Proposal.** Add §2.0 "Recorded rules this design changes": one table, one row
per rule. Each row has the quoted current text, the replacement text, the file
or issue it lands in, and the milestone.

1. `architecture.md:81-86` → "A sequence is run, not read. `Sequence.Run`
   threads a `FoldState` and returns a `FoldFile` and `[StepRecord]`. The file
   reaches the pipeline as any `.fold` does. What needs the moves themselves
   (`Render.Sequence`, the material consumer) takes the records."
2. `AGENTS.md:193-197` → append "A sequence file is not an input format. It is
   a program: it becomes a `Sequence` at the boundary and a `FoldFile` plus
   `[StepRecord]` when run. Nothing that reads the written file may know it came
   from a sequence."
3. #60 Approach (`apply`, `scanl`, "one interpreter") → superseded by D1/D3,
   with the reason.
4. #95 Approach → superseded by D5.
5. `architecture.md:206-207` and the `BlintzSequence.hs:4` header → superseded
   once blintz migrates (D16).
6. `docs/notes/no-sequence-solver.md`, first reason → D18.

All six land in M0, **before** the first `Sequence.*` module merges, because
architecture.md says to read it before adding a module. Drop "when
implemented". D17's AGENTS wording goes in the same table.

---

## L4-4 (major) — `--layer-budget` does not reach the runner or `run -o .glb`, and stacking policy moves out of `Origami.Stacking`

**Claim.** The runner solves stackings: D3 invariant 7 uses `layerOrderFor`,
and D11 says "the runner solves, filters valid stackings by the relations".
`layerOrderFor` takes a `Budget`, yet `runSequence` takes an undefined
`RunSettings`. D13 grants `--layer-budget` only to `-o OUT.svg`, not to `.fold`
or `.glb`. AGENTS lists `--layer-budget` as a parameter of every entry point.

Filtering stackings by relation inside `Sequence.Run` also contradicts the
owner's recorded plan (#110) to keep "which order" policy beside
`layerOrderFor`, because "a policy spelled out per caller is a policy the next
caller forgets".

**Evidence.** `AGENTS.md:217-222`; `Origami/Stacking.hs:165` (`newtype
Budget`), `:386` (`layerOrderFor :: Budget -> Frame -> Either FoldError (Maybe
[FaceOrder])`); #110 body (`withLayerOrder :: Budget -> Frame -> Either
FoldError Frame`, and "`--stacking` asks for a particular order by index, which
is a different question"); spine D3 lines 200-202, D11 lines 414-418, D13 lines
451-456, §4 line 689.

**Proposal.**
- `runSequence :: Budget -> RunSettings -> Frame -> Checked -> Either
  SequenceError Run`, with `Budget` explicit and first, as in `stepPage`.
- `run` accepts `--layer-budget` for every `-o` extension.
- The relation filter is a third question beside the two #110 names:
  `Origami.Stacking.stackingWhere :: Budget -> [(FaceId, FaceId)] -> Frame ->
  Either StackingChoiceError ([FaceOrder], StackingChoice)`, reusing #110's
  `withLayerOrder` for the solve-one case.
- AGENTS' entry-point list gains `runSequence`, `stepPageWith` and the realistic
  glTF entry point, in the M0 table (L4-3).

---

## L4-5 (major) — Error types without `Explain`, and `SequenceError`'s wording breaks the `Explain` conventions

**Claim.** §4 declares one instance, `instance Explain SequenceError`. The
spine introduces at least these error or refusal types, each of which "is one
`Left` away from being printed":

- nested in `SequenceError`: `ParseProblem`, `StaticProblem`, `ResolveProblem`,
  `MoveFailure`, `SelectionError`, `MacroBindError`, `StackingChoiceError`;
- material side: `SettleError` (D14), `Reason` (the CLI "names reasons" on
  `Diagnostic`, D14), and the certificate registry's `Refused` (D10);
- D15's replacements for `newtype … Text`.

Two wording rules in D12 also contradict the recorded conventions:

- The `Explain` fragment is to contain `file:line:col`. But a message is a
  fragment the *caller* puts after its own `path:` prefix, and `StepError`
  records that the CLI supplies the file name.
- "Library errors that name CLI flags are translated to the sequence's own
  spelling." Wrapping types must just call `explain` on the nested error; a
  re-worded copy is a second spelling of one message, which `Steps.hs` calls "a
  real cost".

**Evidence.** `AGENTS.md:165-172`; `Explain.hs:40-43` ("types that wrap
another error just call 'explain' on it"), `:63-67`; `Render/Steps.hs:64-78`;
`Fold/Query.hs:67-70` (`creaseEndFlag` returns `"--from"`/`"--to"`); spine D12
lines 432-437, §4 lines 713-723, D14 line 500, D10 line 402.

**Proposal.**
- Every type in the lists above gets an `Explain` instance in the module that
  defines it. The PRD lists them in a table with an example message for each.
- `SequenceError`'s message leads with `step N (name)` and the author's
  reference text, and never contains the file path. The CLI prefixes
  `path:line:col`, as it does for `StepError`.
- Nested errors are quoted with `explain`, never re-worded.
- Fix the flag leak at its source: `FoldError`/`ThroughError` name "the start"
  and "the end" of the line, and `app/` maps an end to `--from`/`--to`. The CLI
  keeps its current words. This is filed as an M0 follow-up issue.

---

## L4-6 (major) — D4's angle-to-assignment rule is a fifth answer to #111's question, and it disagrees with `creaseDirections`

**Claim.** #111 records four places that decide what a file's angles mean, and
the owner wants them answered "in one place" in `Fold.Query`. D4 adds a writer
rule: `M` if the angle is below −threshold, `V` if above, `F` otherwise, "with
one named threshold constant".

`Stacking.creaseDirections` uses exact `d > 0`/`d < 0` and falls back to the
assignment only at exactly 0. With any threshold τ > 0, the writer writes an
angle in (0, τ) as `F`, while `creaseDirections` reads the same angle from the
written file as a valley. senbazuru then disagrees with its own output, which
is #111's stated risk ("senbazuru writes a file that senbazuru reads back").
The spine never mentions #111.

**Evidence.** #111 body (table of four; "Nothing holds them together, and the
agreement is now load-bearing"); `Origami/Stacking.hs:719-726`; spine D4 lines
213-217; `grep -n '#111' spine.md` returns nothing.

**Proposal.** Add to D4:

> The at-rest rule lives in `Fold.Query` beside `resolveAssignments`, as
> `assignmentAtRest :: Double -> Assignment`. `creaseDirections` and the writer
> share its threshold: either both use exact zero, or both use the one named
> constant. M2's writer depends on #111.

Add #111 to M0's amend list.

---

## L4-7 (major) — Vendor keys: D7 rejects them for a reason D4 and D10 ignore; the key frame and the sheet's file metadata are undecided

**Claim.**
- **The same reason cuts both ways.** D7 rejects vendor keys as the notes
  channel because "transforms drop extras; #73's file/frame key split comes
  first", and D18 makes persisting notes before #73 a non-goal. Yet D4 writes
  `senbazuru:material_coords` on every frame, and D10 writes
  `senbazuru:assurance` "on each frame after the last transform". If writing
  after the last transform makes D10 safe, it makes captions and arrow kinds
  safe too. If it does not, D4 and D10 are blocked on #73 as well.
- **The key frame.** For the key frame, `frameExtras` *is* the top-level
  object's bag (#73). Writing per-frame keys there is the file/frame confusion
  #73 describes.
- **The sheet's file metadata.** `runSequence` takes a `Frame` and
  `writeSequence :: Run -> FoldFile` has no file input. So the sheet file's
  `file_*` keys and file-level extras (#73's `cpedit:page`) cannot survive, in
  the first verb whose whole purpose is writing files. That contradicts
  "preserve at the boundary".
- **Which frame the assurance describes.** D7 says a figure's caption describes
  the move *leaving* it. D10 does not say whether frame i's assurance describes
  the step into i or out of it.

**Evidence.** #73 body ("For the key frame, `frameExtras` holds the unknown
keys of the top-level object"); `AGENTS.md:184-192`;
`Origami/Surface.hs:248-252` (`materialFrame` inserts into `frameExtras`);
spine D4 lines 217-219, D7 lines 320-327, D10 lines 403-406, D18 line 606, §4
lines 689 and 707.

**Proposal.**
- Replace D7's reason with: "Notes are not persisted in v1 because nothing
  reads them, and `render --steps` must not depend on them (D13)."
- Add to D4/D10: "The writer adds `senbazuru:*` keys after the last transform,
  and only to `file_frames` entries. The key frame carries file metadata and no
  step (`Steps.hs:81-89` already skips a metadata-only key frame) until #73
  splits the bag."
- `runSequence` takes the sheet's `FoldFile` and the frame index.
  `writeSequence` copies the sheet's `file_*` keys and file-level extras, and
  drops frame extras.
- "`senbazuru:assurance` on a frame records the evidence of the step that
  produced it. The first state has none and the key is absent, not empty."

---

## L4-8 (major) — Sequence numbers have no unit: `(u, v)` means different paper on a `.cp` sheet and a `.fold` sheet

**Claim.** D2 takes `(u, v)` as exact `Rational` material coordinates. The
glossary defines material coordinates as positions on the original sheet, in
its model units. `examples/bird-base.cp` spans ±200 in both axes, while the unit
fixtures span [0, 1].

So `anchor (0.58, 0.4)` names the intended flap on `bird-base.fold` but a
point near the centre of `bird-base.cp`, with no refusal. D14 adds "sheet
units", which is never defined, and physical "sheet size, thickness" in the
`material` block. That is a third unit system beside AGENTS' model and page
units, left unstated. The D research raised this exact question (A11); the
spine does not answer it.

**Evidence.** `python3` over `examples/bird-base.cp`: x ∈ [−200, 200],
y ∈ [−200, 200]. `jq` over `crane.fold`, `bird-base.fold`, `blintz-base.fold`:
[0, 1]. `docs/glossary.md:46` (hair: a `.cp` 400-unit square and a unit square
do not share numbers) and `:81`; `AGENTS.md:173-178`; spine D2 lines 123-126,
D14 lines 489 and 494-495; D research A11.

**Proposal.** Add to D2:

> Every point or length written in a sequence is a **fraction of the sheet**.
> `(u, v)` ∈ [0,1]² maps affinely onto the sheet's material bounding box, with
> `(0, 0)` at bottom-left. One file therefore names the same paper on `.cp`,
> `.opx` and `.fold` sheets.
>
> - `model (x, y)` is the one exception, and is in model units.
> - Angles are in degrees.
> - Physical lengths appear only in the `material` block, each with an explicit
>   unit suffix (`0.1mm`), and are converted to model units once, in the
>   material consumer.

In D14, replace "sheet units" with "fractions of the sheet side".

---

## L4-9 (major) — §5 quarter fold contradicts D3 and its own known facts: the anchor moves, and step 2 is a valley

**Claim.** `anchor (1/4, 1/4)` lies in face 3 (the bottom-left quarter), and
face 3's vertices are the first to move. D3 invariant 5 refuses a move whose
moving set contains the anchor face, so the spine's first example is refused
by the spine. The stationary quarter in both folds is face 0, at (3/4, 1/4).

Step 2 is written `fold mountain edge top to edge bottom`, "Fold the top half
behind". But the known facts give edge 9 +180 in the last frame. Edge 9 is the
hinge between face 0 (stationary, anticlockwise, normal +z) and face 1. A
positive angle lifts the child towards the viewer, so by D5's "as seen from +z"
rule this is a **valley** that brings the top half down **in front**. The back
layer's −180 on edge 11 is the M/V alternation through layers.

**Evidence.** `python3` over `examples/quarter-fold-steps.fold`:

- face 3 `[8,7,0,4]` has centroid (0.25, 0.25); face 0 `[8,4,1,5]` has centroid
  (0.75, 0.25); all four faces have signed area +0.25;
- vertices moved from flat: `[0, 3, 7]` in frame 1, `[0, 2, 3, 6, 7]` in
  frame 2, so vertices 1, 4, 5, 8 never move;
- edge 9 runs (0.5, 0.5)→(1, 0.5); angles in the last frame are
  `[-180, 180, -180, -180]`.

`Origami/Folding.hs:46-47` ("a valley — positive, in FOLD — lifts the child
towards the viewer"), `:643`; `Render/Camera.hs:107` (`topDown` looks along
−z); spine D3 lines 194-197, §5 lines 735-737 and 752-759.

**Proposal.** Replace the example with:

```text
anchor (3/4, 1/4)
step half "Fold the left half behind, onto the right."
  fold mountain edge left to edge right
step quarter "Fold the top half down in front, onto the bottom."
  fold valley edge top to edge bottom
```

Add one sentence naming what looks like a typo: the last frame has `-180` on
edge 11 even though the step says valley, because that layer lies upside down
(AGENTS, creasing through layers).

---

## L4-10 (major) — D2 classifies `centre` as a vertex, but blintz-base has no vertex there, so §5's blintz is refused

**Claim.** D2 lists `centre` with `corner` as a **vertex** reference: within
tolerance of exactly one vertex, otherwise refused, naming the nearest vertex.
`examples/blintz-base.fold` has 8 vertices, none at (0.5, 0.5), and no
`faces_vertices`. `anchor centre`, `fold … to centre` and the EDSL's
`header … centre` are therefore all refused under D2 as written. The
underlying gap is that D2 decides kind by spelling. An anchor needs a region, a
construction needs a position, and only a few moves (`collapse at P`) need a
vertex.

The captions are also misleadable. The fixture folds the corners −180
(mountain) with the central face stationary, so the corners go behind, but the
caption says only "Fold the first corner to the centre". A book reader will
make a valley fold.

**Evidence.** `python3` over `examples/blintz-base.fold`: "vertices 8 edges 12
faces 0; centre is a vertex: []", edges 8-11 `M -180`; spine D2 lines 136-143,
§5 lines 739-740 and 766-777, EDSL lines 823-826; `Folding.hs:46-47`;
`AGENTS.md:59-60` ("If an example can be misread, fix the example").

**Proposal.** Replace D2's two resolution bullets with:

> A named point's kind is decided by its **use**, not its spelling.
>
> - As an `anchor`, a `flap containing` seed or a `layers … above` term, it is
>   a **region**: strictly inside exactly one face.
> - As an argument of a construction or an end of `crease P-Q`, it is a
>   **position**. It is found through any face whose closure contains it, or
>   through a vertex within `Fold.Faces.tolerance`.
> - It must be a **vertex** only where the move says so: `collapse at P`, and a
>   macro's centre.

Change the blintz captions to "Fold the first corner behind, to the centre."

---

## L4-11 (major) — D5 requires exact ±1 matrices, but `Rotate Rational` allows any fraction

**Claim.** D5 builds the presentation "from exact ±1 matrices (never
`rotationAbout … pi`; `sin π ≠ 0`)" and allows only proper rotations. §4 has
`Rotate Rational`, and D12 lists `rotate` among the keywords with no
restriction. `rotate 1/8`, the square-to-diamond turn books use constantly,
has entries of √2/2. It cannot be built from ±1 matrices, so a PRD writer must
either break D5 or refuse a common book step without a recorded decision.

**Evidence.** spine D5 lines 247-250; §4 line 663 (`TurnOver PageAxis |
Rotate Rational`); D12 line 429; gap-step-annotation F16 (`sin π` in doubles is
`1.2246467991473532e-16`).

**Proposal.** In §4 and D5:

> `data QuarterTurn = Quarter | Half | ThreeQuarter`, and `Rotate QuarterTurn`.
> `checkSequence` refuses any other fraction, naming it.
>
> Eighth turns are an open question for the owner, with a concrete fork: exact
> matrices for 1/8 only, or a named tolerance on the presentation. The join
> check must then compare presented positions at that tolerance.

---

## L4-12 (major) — Three frames of reference for the directions an author writes

**Claim.** An author writes a direction in three places, and the spine reads
each from a different side:

- `valley`/`mountain` are "as seen by the reader at that step", after
  presentation (D5);
- `top N layers` counts "from the viewer's current side" (D2);
- `layers A above B` is "along the anchor's +z" (D11 and §4 `Relation`), which
  does **not** follow a `turn over`.

After `turn over`, "top 1 layers" and "A above B" therefore describe one stack
from opposite sides. D5 states the book principle ("senses are read as the
reader sees them"), and D11 breaks it without saying so.

**Evidence.** spine D2 lines 134-135 and 158-160, D5 lines 257-261, D11 lines
414-418, §4 line 657.

**Proposal.** One rule, stated in D2:

> Every direction an author writes — valley/mountain, top N, above/below — is
> read from +z of the presented model. The runner converts all three to the
> anchor's frame once, and the record stores that form. `start folded`
> relations come before any presentation step, so they read from +z as well.

---

## L4-13 (major) — D12's grammar cannot parse §5, and D9 uses a different block syntax

**Claim.** D12 makes a step run "to the next `step`", with "indentation is
conventional, not significant". It lists header lines `fseq 1`, `title`,
`sheet` and `material`. Against that:

- **Blocks.** D9 writes `together { … }` and `pose { crease P-Q to A; … }` with
  braces and semicolons. §5 writes `together`, `settle` and `start folded`
  blocks with **no** braces, so they are delimited only by indentation, which
  D12 rejects. With neither braces nor significant indentation, the end of a
  `together` block inside a step is ambiguous.
- **Header lines.** §5 uses an `anchor` header line that D12 does not list.
- **`start folded`.** §5 places it before any `step`, while §4 makes it a
  `Step` constructor.
- **Closing caption.** D7 promises "the sequence's closing caption" as the last
  frame's title, but no syntax carries one.
- **`hold`.** It means re-anchor at step level (§4 `Hold`, D3 invariant 5) and
  a material hold inside `settle` (D14, §5).
- **Settle-only steps.** §5's "Spread the wing" step has a `settle` block and no
  move, but §4's `Located (StepHeader, Step)` requires a `Step`.

**Evidence.** spine D12 lines 424-430 and 440-441, D9 lines 378-381, §5 lines
750-753, 786-796 and 799-817, §4 lines 664-674, D7 lines 318-319, D14 lines
487-495.

**Proposal.** In D12:

> - **Blocks.** Braces everywhere: `together { … }`, `pose { … }`,
>   `settle { … }`, `start folded { … }`. A newline or `;` separates
>   statements; indentation stays conventional.
> - **Header.** `fseq 1`, `title "…"`, `sheet …`, `anchor P`, optional
>   `material { … }`, optional `start folded { layers … }`, optional
>   `closing "…"`. `start folded` becomes a header field, not a `Step`.
> - **Re-anchor.** The re-anchor step is `anchor P`, the header's word, which
>   frees `hold` for settle blocks.
> - **Settle.** A `settle { … }` block belongs to the step it appears in. §5's
>   crane settle moves into the fold step, or §4 gains an explicit `Rest` step
>   (no move, `NoMotion`). Pick one.

Rewrite all four §5 texts in that grammar.

---

## L4-14 (major) — `Repeat` and `ExpectRefused` are in the AST with no decision behind them

**Claim.** §4's `Step` includes `Repeat Symmetry [Name]` and
`ExpectRefused RefusalKind Step`. No decision defines:

- what a `Symmetry` is, or how material references, senses and seeds map
  through it;
- what `ExpectRefused` means for the runner, the writer (which frame is
  written?), the record and the CLI.

D1 mentions "repeat … sugar" and D7 a "repeat range"; nothing mentions
`ExpectRefused`. A parser PRD must round-trip every constructor (D12), so these
cannot be left for the PRD writer to invent.

**Evidence.** `grep -n "ExpectRefused\|Repeat\|repeat\|Symmetry" spine.md`
matches only lines 59, 306, 311, 325 (prose) and 670-671 (§4).

**Proposal.** Either remove both from the v1 AST and list them under D18, or add
a D19:

> **Repeat.** `repeat mirror left-right { s1 s2 }` elaborates by reflecting
> every material point of the named steps across the sheet's axis. Senses stay
> unchanged, because both sides are read from one viewer (L4-12). Provenance is
> kept for the repeat arrow.
>
> **ExpectRefused.** Test-only. `run` refuses a file containing it except under
> `--check` and in the test suite. It writes no frame and produces a record
> whose evidence is the refusal.

---

## L4-15 (major) — Milestone dependencies and issue closures do not match the decisions

**Claim.**
- **M6 needs M4.** "Crane spreading re-expressed" requires the crane-wing fold
  with `flap containing` (D8/M4). D16 says the crane wing waits for D8, and the
  §5 crane settle follows that fold. The order constraints list only M2 → M6.
- **M7 needs M5 for part of its scope.** "glTF animation of checked routes (G1)"
  covers `Sampled` coupled routes, which exist only after M5.
- **M0 cannot close #97.** #97's done-when 2 ("the quarter-fold sequence
  written in the chosen syntax, reproducing `examples/quarter-fold-steps.fold`")
  needs a runner (M2). Under D4 it cannot be met as written anyway: the fixture
  writes M/V at angle 0.
- **M0's amend list is incomplete.** It omits #97, and #73 and #111, which D4,
  D7 and D10 depend on (L4-6, L4-7).
- **`--rigid-fallback`** (D14) belongs to no milestone.

**Evidence.** #97 body, Done when; spine §3 lines 615-627, D8 lines 350-352,
D14 lines 499-503, D16 line 581, §5 lines 799-817.

**Proposal.** Replace the order-constraints sentence with:

> M1 → M2 → {M3, M4} → M5; M4 → M6; M2 → M6 → M8; M3 → M7 (G1 animates only
> `SweptHinge` routes until M5); #73's and #111's decisions before M2's writer;
> #208 before M8.

- M0 amends #97's done-when 2 to "parses and pretty-prints at M1; at M2, runs
  to frames matching the fixture's coordinates and angles within a tolerance,
  with assignments by the state rule". #97 closes at M2.
- Add #73, #111 and #110 to M0's amend and dependency list.
- `--rigid-fallback` lands in M8.

---

## L4-16 (major) — D8's new through-layers function creases one line at a time, against the batch rule

**Claim.** AGENTS requires creases to be drawn "in **batches**
(`creaseAllAlong`), because the handing back is the cost and doing it per
crease is cubic". D8's `creaseLayersThrough :: Set FaceId -> V2 -> V2 ->
Assignment -> Folded -> …` takes one line. Several steps need several lines at
once:

- a macro that adds creases (D9);
- `pose`;
- elaborated `repeat`;
- a precrease of both diagonals.

A runner built on D8's signature re-cuts and re-traces once per line.

D8 also says the existing `creaseThroughLayers` "becomes its all-faces case".
But the existing function takes a `Frame`, not a `Folded`, so the wrapper must
fold first, and the PRD should say so. §6 item 21 (`creaseAllAlong` returns no
new edge ids) is the same gap at the flat level.

**Evidence.** `AGENTS.md:206-213`; `Fold/Creasing.hs:138` (`creaseAllAlong ::
[(V2, V2, Assignment)] -> Frame -> Either FoldError Frame`);
`Origami/ThroughLayers.hs:227` (`creaseThroughLayers :: V2 -> V2 -> Assignment
-> Frame -> Either ThroughError Frame`); spine D8 lines 335-339, §6 item 21.

**Proposal.** In D8:

> `creaseLayersThrough :: [(Set FaceId, V2, V2, Assignment)] -> Folded ->
> Either ThroughError Creased`, where `Creased { creasedPattern :: Frame,
> creasedEdges :: [[EdgeId]] }` has one list per requested line.
>
> - Exactly one `creaseAllAlong` call per step: one step is one batch.
> - `creaseThroughLayers from to a fr` becomes `foldFrameWith fr` followed by
>   the all-faces single-element case, with goldens unchanged.
> - The flat `creaseAllAlong` gains the same new-ids result.

---

## L4-17 (major) — §7 puts new vocabulary in `PRDs/00-overview.md`, a second place for definitions

**Claim.** AGENTS says to prefer the glossary because "a word defined in four
notes will be defined four different ways within a year", and calls
`docs/glossary.md` "the one place a definition lives". §7 creates a second
place (`PRDs/00-overview.md §Vocabulary`) and forbids PRDs from proposing
glossary edits. M0 later adds "glossary entries". Between those two points
there are two copies, and they will drift.

The glossary already shows this failure: §6 item 11 records rest angle defined
twice, differently.

**Evidence.** `AGENTS.md:47-49`, `:109`; `docs/glossary.md:19` and `:83`;
spine §7 lines 887-889 and 901-902, M0 line 615.

**Proposal.** Replace §7's vocabulary bullet with:

> New terms are drafted **once**, as rows in `docs/glossary.md`'s own table
> format, in `PRDs/glossary-additions.md`, and PRDs link to those rows. M0's
> first PR moves the rows verbatim into `docs/glossary.md`, replaces the file
> with a pointer, and fixes the rest-angle duplicate. No PRD defines a term
> beyond one clause and a link. A new row must not reuse `sequence`, `step`,
> `frame`, `hold` or `rest angle` with a new meaning.

---

## L4-18 (major) — Terms the spine uses that are defined neither in the spine nor in `docs/glossary.md`

**Claim.** The terms below are used in D1-D18, §4 or §5. Each is neither in the
glossary's term list nor defined where the spine uses it. Terms the spine does
define inline are excluded: working pattern, intent assignment, state rule,
presentation, Lucero's eighth operation, backfill, `flap containing`,
`top N layers`, the G0-G4/A0-A3/W0-W2 rungs, near miss. A reader "who has never
folded anything" (AGENTS) cannot follow the PRDs without these.

- **Program:** sequence (as a program; collides with glossary *Step*/*Frame*
  "diagram sequence", see L4-19), EDSL, deep/shallow embedding, first-order AST,
  interpreter, elaboration, span, reference, landmark, construction (the
  glossary's Huzita-Hatori row does not number O1-O7), disambiguator,
  off-paper solution, provenance (used for both crease provenance and
  "provenance lines").
- **Moves and state:** anchor, turn over, rotate (as a step), precrease,
  unfold (reverse a named step), hinge, seed, moving side, stationary side,
  handoff, join check, stacking, stacking choice, accepted orders, directional
  layer requirements, ordered cover, coupled move, macro, signature, moving
  star, role, driving parameter, press, pose/pose table, checkpoint, instant
  flat fold, re-anchor.
- **Evidence:** route, route evidence, assurance, sampled route, swept hinge,
  certificate, certificate registry, fixture fingerprint, reachability.
- **Page:** caption, symbol (the new `Shape`), gutter, fold-here line, creases
  to come, repeat/repeat range, push, sink, fold-and-unfold, x-ray line,
  cut-away, silhouette, quantitative invisibility, feature edge, presentation
  change.
- **Material:** settle/settled/settle request, hold, grip, grip target, band,
  material-band, closed region, across-hinge, rigid-pose, arc-grip,
  springback, penalty contact, barrier contact, Gauss-Newton, sparse factor,
  held boundary, line search, refinement, triangle budget, verdict
  (accepted/diagnostic), rigid fallback, graduation, schematic (labelled),
  complete scene.
- **glTF:** split normals, `TEXCOORD_0`, `LINES` primitive, morph target,
  skinning, fillet, sheen, diffuse translucency, `extensionsRequired`.
- **Numbers and budgets:** layer budget (`Budget`, used in AGENTS but absent
  from the glossary), ulp (§6 item 16), sweep interval.

**Evidence.** `grep -o '^| \*\*[^*]*\*\*' docs/glossary.md` (full term list:
Crease pattern … Ear clipping; none of the above appear);
`docs/glossary.md:48`, `:58`; `AGENTS.md:62-65`.

**Proposal.** Put exactly this list into `PRDs/glossary-additions.md` (L4-17).
Each row gets one or two plain-word sentences and, where it has one, the
module or research note that defines the term. §7 should require that a PRD
using a term not on the list adds it there first.

---

## L4-19 (minor) — Names and signatures disagree between sections

**Claim.**
- **`sequenceOf`.** D1 gives `sequenceOf :: Build () -> Sequence`; §4 gives
  `sequenceOf :: SequenceHeader -> Build () -> Sequence`, and `SequenceHeader`
  is never defined (only `StepHeader`).
- **`Build`.** D1 has `type`-like `Build a = State BuildState a`; §4 has a
  `newtype`.
- **The moving seed is stored twice.** §4 has it in `Layers`
  (`FlapContaining Point`) and again as `Fold`'s trailing `(Maybe Point)`.
  D2 says `P-Q` "must name a `flap containing` seed", so which field carries it
  is ambiguous.
- **"Sequence" already means something.** The glossary and the repo use it for
  a multi-frame FOLD file: *Step* and *Frame* rows, `Render.Steps` ("a whole
  folding sequence"), `examples/bird-base-sequence.fold`. #60 and #97 call the
  program a "scheme". The spine renames without saying so, and names the M0
  note `docs/notes/sequences.md` where #97 asks for `docs/notes/schemes.md`.
- **The EDSL blintz is not the text blintz.** Its captions differ ("next
  corner" against "second/third/last"), yet §5 says both are "written for the
  same models" and calls it "same blintz".

**Evidence.** spine D1 lines 94-95, §4 lines 655-680, D2 lines 151-153, §5
lines 768-777 and 819-830, M0 line 615; `docs/glossary.md:48`, `:58`;
`architecture.md:108`; #97 body ("Record the decision … in
`docs/notes/schemes.md`").

**Proposal.**
- Use one signature: `sequenceOf :: SequenceHeader -> Build () -> Sequence`,
  with `SequenceHeader` defined in §4.
- Use `newtype Build a`.
- Keep the seed in one place: `Layers = AllLayers | TopLayers Int` plus a
  separate `seed :: Maybe Point` on `Fold`.
- Name the program a **sequence source** (`.fseq`) and the written result a
  **sequence file** (FOLD). Say in M0 that this replaces #97's "scheme", and
  either keep #97's note name or amend #97.
- Make the EDSL example produce the text example's `Sequence` exactly
  (`zipWithM_` over the three captions), so "same" is true.

---

## L4-20 (minor) — Library stanza and I/O boundary: missing dependencies, and a sequence file read outside `Fold.Load`

**Claim.**
- **Dependencies.** The library's `build-depends` has no `mtl` or
  `transformers`, which D1's `State` needs. D12 names only megaparsec and
  parser-combinators. M2 claims #58 items 3-4, but item 4 (atomic write) costs
  `directory` as a **library** dependency, which #58 calls "the real decision
  … for all three backends or none". The spine does not decide it.
- **I/O.** Every CLI input goes through `withFoldFile`/`Fold.Load` today. D13
  says `run` never uses `withFoldFile`, but does not say who reads the `.fseq`
  bytes, or whether a relative `sheet "path"` resolves against the `.fseq`'s
  directory or the working directory.
- **Wrong verb.** `Fold.Load.decodeFile` decodes any unknown extension as FOLD,
  so `render x.fseq` fails with a JSON error, not "use `run`".

**Evidence.** `senbazuru.cabal` library `build-depends`: aeson, base,
bytestring, containers, filepath, tagsoup, text. #58 item 4. `grep -n
"readFile\|withFoldFile ::" app/Senbazuru/Cli.hs` shows input only via
`withFoldFile` (`:800`). `Fold/Load.hs:103-106` (`_ -> decodedAsFold`). spine
D12 lines 431-433, D13 lines 459-461, M2 line 617.

**Proposal.**
- D12 lists `mtl` (or `transformers`) with megaparsec and parser-combinators.
- M2 either takes the `directory` decision explicitly or drops #58 item 4.
- D13 adds:
  - `Fold.Load.readSequenceText :: FilePath -> IO (Either LoadError Text)` is
    the only reader of `.fseq` bytes. It returns `Text`, never a `Sequence`,
    so `Fold` does not import `Sequence`.
  - `sheet` paths resolve relative to the `.fseq` file's directory.
  - `decodeFile` refuses `.fseq` with a message naming `run`.

---

## L4-21 (minor) — More "hair" tolerances, while D2 calls unifying them a prerequisite

**Claim.** §6 item 17 counts at least nine hair formulas, and D2's residue makes
unifying them a prerequisite issue. The spine still adds three more numeric
rules without citing a shared source:

- D3's join check "within `1e-12 × span`";
- D9's sector comparison using `FlatFold`'s tolerance;
- D16's "one named tolerance" for formula-derived angles.

These sit beside D2's `Fold.Faces.tolerance` (`1e-9 ×` sheet diagonal) and the
glossary's hair (`Origami.Flat.sheetHair`).

**Evidence.** `Fold/Faces.hs:248-251`; `docs/glossary.md:46`; spine D2 lines
139-141 and 170-171, D3 lines 198-199, D9 line 376, D16 lines 577-578, §6 item
17.

**Proposal.** Add to D3:

> The runner defines no tolerance of its own. Every requirement that compares
> numbers names which existing tolerance it uses, cited by `path:line`: faces
> (`Fold.Faces.tolerance`), sectors (`FlatFold`), joins (the one `CheckedBird`
> uses). The angle tolerance of D16 waits for the unification issue.

---

## L4-22 (minor) — §7 does not carry AGENTS' rules for examples and the newcomer reread

**Claim.** §7 cites "Writing an explanation" but leaves out its two sharpest
rules:

- "the numbers … come from a command that was actually run";
- "If an example can be misread, fix the example".

§5's examples already fail both. L4-9 and L4-10 show two refused or wrong
examples. The crane example has placeholders (`(tail point)`, `# writer: pick
a point`). `model (0, 1/4)-(2, 1/4)` parses under D2 as a model point joined to
the *material* point (2, 1/4), which is off the sheet.

§7 also omits AGENTS' closing reread ("as someone who knows Haskell and has
never folded anything"). And it lets PRDs cite research by shorthand keys
("F finding 14", "critic spot check 21"), which a newcomer cannot follow
without opening the notes.

**Evidence.** `AGENTS.md:52-54`, `:59-60`, `:62-65`; spine §5 lines 729-732,
799-808; §7 lines 884-905.

**Proposal.** Add to §7:

> - Every example sequence in a PRD has been run against its fixture with
>   `jq`/`python3`. The command and its output are cited, and no placeholder
>   survives.
> - Research is cited by file and section heading (`research/C-…md §Findings
>   27`), not by bare key.
> - Before a PRD is final, it is reread as someone who knows Haskell and has
>   never folded anything. Every term is in `PRDs/glossary-additions.md` or
>   the glossary.

Rewrite the crane step as
`fold valley 90 model (0, 1/4)-model (2, 1/4) flap containing (…)`, and state
the grammar rule that `model` binds one point.

---

## L4-23 (minor, not checked) — D5 changes what `render --steps` draws for user files

**Claim.** D5 makes `Origami.Step` classify any frame pair related by one
whole-model rigid motion as a presentation change, and infer no arrow for it.
Its only acceptance test is "no existing arrow-bearing golden has such a
pair". D13 promises "Existing verbs and their outputs are untouched", and the
owner's rule is to keep the default output unchanged, not just the goldens.

I did not check whether any multi-frame file in `examples/` (for instance
`bird-base-sequence.fold`, 16 frames) contains such a pair.

**Evidence.** spine D5 lines 262-265, D13 line 462; memory note
`keep-the-default-output-unchanged.md` (as quoted in D research A8).

**Proposal.** Either:

- apply the classification only in `stepPageWith` when a `StepNote` says the
  step is a presentation, leaving `motionsBetween` inference for
  `render --steps` unchanged; or
- extend the acceptance test to "`render --steps --arrows` output is
  byte-identical for every multi-frame file under `examples/`".

---

## Confirmations (checked and found correct)

- **`stepPageWith` is purely additive to today's `stepPage`.** `stepPage ::
  Theme -> Budget -> Grid -> View -> Bool -> [Frame] -> Either StepError (Maybe
  Diagram)` (`Render/Steps.hs:90-100`), so D7's `stepPageWith` differs only in
  its list element type. `stepPage` is referenced in 15 files outside
  `Steps.hs`, 38 lines in all (grep), consistent with "about fifteen call
  sites".
- **GLB extras keep exactly three `senbazuru:` keys.** They are
  `material_coords`, `source_panels` and `source_edges`
  (`Render/Gltf.hs:241-242`), so D10's "gains that key only when present" is a
  real whitelist change.
- **33 goldens.** `git ls-files test/golden | wc -l` = 33, with no `.actual`
  files tracked (D16).
- **`Fold.Faces.tolerance` is `1e-9 × diagonal`** (`Fold/Faces.hs:248-251`,
  D2).
- **`creaseThroughLayers :: V2 -> V2 -> Assignment -> Frame -> Either
  ThroughError Frame`** (`ThroughLayers.hs:227`), and **`creaseAllAlong ::
  [(V2, V2, Assignment)] -> Frame -> …`** (`Creasing.hs:138`).
- **`motionsBetween :: Frame -> Frame -> Either FoldError [Motion]`**
  (`Step.hs:88`), refusing differing graphs with `FramesDiffer`/`FramesDisagree`
  (D6's premise).
- **Quarter-fold known facts.** 9 vertices, 12 edges, 4 faces; edges 8-11 go
  `0` → `[-180,0,-180,0]` → `[-180,180,-180,-180]`; frame titles are states
  (`jq`/`python3`).
- **Blintz known facts.** Edges 8-11 are the four corner creases, all `M`,
  angle −180 (`python3`).
- **The issue bodies say what the spine says they say.**
  - #60 Approach: "Not a free monad: there is one interpreter".
  - #95: the axis is `(x, y, z) ↦ (−x, y, −z)`.
  - #94: "nothing reads them", which is stale.
  - #36 done-when 1 uses a reflection through the sheet's plane.
  - #73: the key frame's extras are the file's keys.
  - #110: `withLayerOrder`.
  - #58 item 4 costs `directory`.
- **Nothing existing sits in the wrong layer.** `Explain` imports nothing in the
  project. No `Origami.*` module imports `Diagram.*` or `Render.*`. No existing
  `Render.*` module imports anything a `Sequence.*` layer would sit above, so
  `Render.Sequence → Sequence.Record → Origami.*` adds no cycle (import grep).
- **`materialFrame` writes `senbazuru:material_coords` into `frameExtras`**
  (`Origami/Surface.hs:248-252`, D4).
- **The megaparsec version is already vendored.** The spine's claim rests on
  the vendored cabal.config (critic contradiction 9), not on a package page.
