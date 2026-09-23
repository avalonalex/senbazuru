# 01 — Architecture: modules, contracts, and one move end to end

Written 2026-09-14 against `568dcb6`, and reconciled on 2026-09-15 with
[decisions.md](decisions.md), the decision record every PRD file follows; where
this file and that record disagree, the record wins. Nothing here is implemented,
and every planned module, type and signature is **SKETCH**.
[02](02-language-semantics.md) says what the language means. This file covers the
rest:

- where the code goes (§1);
- the shared `Sequence` value and the two contracts between the pieces (§2);
- the stated exceptions to recorded rules (§3);
- the replacement text for every recorded rule the design changes (§4);
- one move traced through the pipeline with real numbers (§5).

Each term gets one clause and a link to [glossary-additions.md](glossary-additions.md)
or [the glossary](../docs/glossary.md). *The study* is the
[material study](glossary-additions.md#code-and-tests): `study/fold-material/`, an
experimental executable compiled and tested with the project, which the library
never imports ([00](00-overview.md#the-material-study)). Two project words have
no row there yet:

- *the material consumer* is the code, in the study until M8, that takes move
  records and returns settled surfaces and realistic renders ([00](00-overview.md));
- a *verb* is a CLI subcommand: `render`, `info`, `check`, `export`, `crease` or
  `fold`.

A decision is cited by its number, D*n*, linked to its section of
[decisions.md](decisions.md), such as
[D23](decisions.md#d23-the-sequence-modules-and-where-run-lives); a change that
record made to its previous draft is cited as C*n*, linked to
[its changes table](decisions.md#changes-since-draft-v2).

M0–M8, with M7a and M7b, are the delivery stages in
[10's milestone table](10-roadmap-risks-questions.md#1-milestones) and
[decisions §8](decisions.md#8-milestones): M0 puts
decisions on record, M1 is the language without geometry, M2 the first runner, and
M8 moves the material solver into the library.

## 1. The module graph

### 1.1 Layers

A module imports its own family and what its row's *May import* column lists, and
nothing else: the column is exhaustive. Row 3 is narrower from outside than it
looks, because only `Fold.Load` imports `Import.*` and only `app/` imports
`Fold.Load`; so "row 3" in any other row means `Fold.{Query,Faces,Crossings,Creasing}`.
When a row names *siblings*, the siblings never import each other. Within one
family the only rule is no cycles: today `Origami.Flap` imports `Origami.Folding`,
`HingeSweep`, `Layers` and `Surface`.

| Row | Modules | May import | Checked today |
| --- | --- | --- | --- |
| 1 | `Geometry.*`, `Explain`, `Fold.Types` | nothing outside itself | `Explain` and `Fold.Types` import no project module; `Geometry.*` imports only `Geometry.*` |
| 2 | `Numeric.*` (M8) | `Geometry.*`, `Explain`; knows no paper | its sources, the study's `SparseSolve` and `DirectionalDistance`, import only `Geometry.V3` and `Geometry.VectorSpace` |
| 3 | siblings `Import.*` and `Fold.{Query,Faces,Crossings,Creasing}`; `Fold.Load` over `Import.*` | row 1; `Fold.Load` also imports `Import.*` | `Import.*` and `Fold.{Query,Faces,Crossings,Creasing}` import only row 1 and their own family; `Fold.Load` imports `Explain`, `Fold.Types` and `Import.*`; no library module imports `Fold.Load` |
| 4 | siblings `Diagram.*` and `Origami.*` | `Diagram.*`: rows 1–2, but from `Fold.Types` only `Assignment`, §3.3's exception. `Origami.*`: rows 1 and 3 | neither family imports the other; `Diagram.*` imports only `Geometry` and, in `Diagram.Style`, `Fold.Types`; `Origami.*` reaches row 3 only through `Fold.{Query,Crossings,Creasing}` |
| 5 | `Material.*` (M8) | rows 1–3, `Origami.*` | — |
| 6 | `Sequence.*` (M1–M6) | rows 1 and 3, `Origami.*`; `Material.*` only from `Sequence.Material`; inside the family, §1.3's levels | — |
| 7 | `Render.*` | rows 1–5, and from `Sequence.*` only `Sequence.Record` and `Sequence.Error` | `Render.*` imports only rows 1, 3 and 4 and its own family; `Render.Svg` imports only `Diagram`, `Geometry` and `Geometry.Polygon`; `Render.Gltf` does not import `Render.CreasePattern` |
| 8 | `app/` | the library | every verb reads its input through `withFoldFile` ([`Cli.hs:693-698`](../app/Senbazuru/Cli.hs#L693-L698)) |

Rows 1, 3, 4 and 7 of *Checked today* are the output of this loop, run at
`568dcb6`:

```bash
for f in $(find src -name '*.hs' | sort); do m=$(echo $f | sed 's#src/##; s#\.hs$##; s#/#.#g'); echo "$m <- $(grep -E '^import( +qualified)? +Senbazuru\.' $f | sed -E 's/^import( +qualified)? +//; s/ .*//' | sort -u | tr '\n' ' ')"; done
```

Row 2's cell is `grep '^import' study/fold-material/SparseSolve.hs
study/fold-material/DirectionalDistance.hs`, and row 8's is read from
[`Cli.hs:693-698`](../app/Senbazuru/Cli.hs#L693-L698). Every existing module fits
its row. The loop sees only `Senbazuru.*` imports, so the check that no `src/`
module imports a `study/` module is a `grep` of `src/` for each
`study/fold-material/*.hs` module name, which finds none.

### 1.2 Rules

1. **Paper and drawing meet only in `Render`.** `Diagram.*` does not know FOLD,
   except as §3.3 says. Of `Origami.*`: "Nothing in it may mention a diagram, a
   page or a colour" ([architecture.md:149-153](../docs/architecture.md)).
   `Geometry` and `Explain` import nothing
   ([architecture.md:142-148](../docs/architecture.md)).
2. **`Numeric.*` knows no paper; `Material.*` knows no move.** `Material.*` takes a
   resolved input and a `Surface V2` (a surface whose material coordinates are 2D
   points) and imports no `Sequence.*` module, which is why contract 2 is split
   (§2.3).
3. **Only `Sequence.Material` imports `Material.*`**, so a sequence that settles
   nothing needs no solver.
4. **Renderers see two `Sequence` modules, `Sequence.Record` and `Sequence.Error`**
   ([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)). A renderer
   drawing a run needs the run and the type of its refusals, and neither module
   imports a parser, a checker or the runner. So `Run` is defined in
   `Sequence.Record`: [06](06-prd-step-diagrams.md) R-06-20's
   `Render.Sequence.stepNotes :: Run -> Either WriteProblem [(Frame, StepNote)]`
   needs it, and `Sequence.Record` cannot import `Sequence.Run`, which imports
   `Sequence.Record`. `Run` holds what a reader of a run needs: the start state,
   every record, each step's outcome, the closing caption and the stop, if any. It
   does not hold the runner's abstract
   [`FoldState`](glossary-additions.md#running-a-sequence): nothing that reads a
   run needs the working pattern, and a renderer able to reach it could come to
   depend on it.
5. **I/O stays in `Fold.Load`** ([architecture.md:155-158](../docs/architecture.md)).
   `readSequenceText :: FilePath -> IO (Either LoadError Text)` imports no
   `Sequence` module. `app/` loads the source and every `sheet` and `checkpoint`
   file and hands the pure runner a `Map FilePath Frame`.
6. **The study stays outside.** Until M8 the material consumer is a
   `study/fold-material/` module importing `Senbazuru.Sequence.Record`, as the
   study imports `Origami.Flap` today.
7. **Unchanged:** `Render.Gltf` does not import `Render.CreasePattern`; they share
   `Origami.Stacking.layerOrderFor` ([architecture.md:176-182](../docs/architecture.md)).

### 1.3 Levels inside `Sequence.*`

Row 6's family is layered so that it has no cycles
([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)); no module
imports one on a higher level.

| Level | Modules | Holds |
| --- | --- | --- |
| 1 | `Sequence.Syntax` | the tree, spans, `canonical`, `stripSpans`, `sourceFiles` |
| 2 | `Sequence.Error` | `SequenceError` and every sequence-level problem type with its `Explain` instance; `RefusalKind`; `sourceLocation`, `excerpt` |
| 3 | `Sequence.Build`, `Sequence.Parse`, `Sequence.Pretty`, `Sequence.Check`, `Sequence.Elaborate` | the two front ends and the static passes |
| 4 | `Sequence.Record` | `RouteEvidence`, `MoveRecord`, `MacroBinding`, `recordPoseAt`, `Run`, `writtenStates`, `runRefusal`, `renderRunReport`; re-exports `RoutePose` |
| 5 | `Sequence.Run` | `FoldState`, `sheetState`, `RunSettings`, `runSequence` |
| 6 | `Sequence.Write`, `Sequence.RunPlan`, `Sequence.Material` | the file writer; the `run` verb's flag rules; the settle consumer, in the study until M8 |

`SequenceError` sits at level 2, below both front ends, because `parseSequence`,
`checkSequence` and `runSequence` all return it.
`writtenStates :: Run -> Either WriteProblem [WrittenState]` applies the
[state rule](glossary-additions.md#the-fold-format) and each state's display once.
`Sequence.Write` and `Render.Sequence.stepNotes` both call it, so the page draws
exactly the frames the file holds by construction, not because a test checks it.

## 2. What crosses the boundaries

### 2.1 The `Sequence` value

`Sequence` is the value both front ends, the Haskell builder and the text parser,
produce. It is a first-order data type
(`Eq`, `Show`, no functions inside):

- `Sequence.Build` or `Sequence.Parse` builds it, and `Sequence.Pretty` prints it.
- `Check`, `Elaborate` and `Run` read it, and nothing after the runner does.
- Parsing the printed text gives the same value back, with spans (source
  positions) stripped.

[03](03-prd-embedded-dsl.md) and [04](04-prd-sequence-source-and-cli.md) own its
two spellings. [F](research/F-haskell-edsl-techniques.md) "B. Embedding styles"
says why it is first-order. It is a value both front ends share, not a boundary
between separately owned pieces of code, so it is not numbered as a contract
([C1](decisions.md#changes-since-draft-v2)).

### 2.2 Contract 1: `MoveRecord`

`Sequence.Run` produces one `MoveRecord` per move
([move record](glossary-additions.md#running-a-sequence)), inside the `Run` of §1.2
rule 4, read by `Sequence.Write`, `Render.Sequence`, `Render.Gltf` (M7b) and the
material consumer. [D14](decisions.md#d14-material-consumption) decides the record;
§5.8 fills one in.

| Invariant | Why |
| --- | --- |
| **Unpresented.** `recordBefore` and `recordAfter` are raw `foldFrameWith` geometry of the [working pattern](glossary-additions.md#running-a-sequence), with the [anchor](glossary-additions.md#running-a-sequence)'s face unmoved. The record keeps [presentation](glossary-additions.md#running-a-sequence) and [anchor placement](glossary-additions.md#running-a-sequence) as separate (before, after) pairs, `recordPresentation` and `recordPlacement`. `displayBefore` and `displayAfter` compose them, placement first and then presentation, and only writers and renderers apply them. | The study reads each `faceOrders` entry, which of two overlapping faces lies above the other, by whether its reference face's normal points to +z ([`CraneSpread.hs:112`](../study/fold-material/CraneSpread.hs#L112)), and solves contact along +z ([`:138`](../study/fold-material/CraneSpread.hs#L138)). A record presented turned over would flip every normal's z, so every above-or-below would be read backwards. The display is kept as two pairs because a `turn over` changes presentation between its before and after, a re-anchoring fold changes placement, and animation needs the two as separate nodes; one display field could not say which display a turn-over's before-state had ([D14](decisions.md#d14-material-consumption), [C46](decisions.md#changes-since-draft-v2)). |
| **One numbering.** Every id is in `recordBefore`'s numbering, which `recordAfter` shares (faces compared as `map sort facesVertices`, [`Surface.hs:207`](../src/Senbazuru/Origami/Surface.hs#L207)). For a fold that creases, `recordBefore` is the cut, creased, unturned state. A flap turn never re-cuts; a move kind that re-cuts after moving must be split or record a mapping. | `CraneSpread` refines that state and looks hinge ids up in it ([gap-study-consumption-contract](research/gap-study-consumption-contract.md) "(a) What the study takes from a move today"). |
| **Nothing stored twice.** Orders and layer requirements are read from the surfaces. | `Surface` holds both ([`Surface.hs:115-123`](../src/Senbazuru/Origami/Surface.hs#L115-L123)). |
| **Evidence is a value:** one of the [route evidence](glossary-additions.md#assurance) constructors `NoMotion`, `Presented`, `StateOnly`, `Sampled CheckedMacro SampleReport` or `SweptHinge CheckedFlap`. `recordPoseAt :: MoveRecord -> PoseRef -> Either PoseError RoutePose` gives the model at a pose: `PoseRef` is `PoseBefore`, `PoseAfter` or `PoseOnRoute r`, a `Rational` fraction r of the way along the checked route ([02 §10](02-language-semantics.md#10-assurance)). `RoutePose` holds that pose's angles, surface and face placements; it lives in a new `Origami.Route`, which `Sequence.Record` re-exports, because `Origami.Flap` may not import `Sequence.*` ([05 L4](05-prd-library-additions.md#l4-flapstationaryface-flapposeat-and-routepose)). `PoseError` is `NoRoute`, or the `FlapError` or `MacroError` of rebuilding a pose; `recordPoseAt` refuses `PoseOnRoute` as `NoRoute` for the first three constructors, which have no checked route ([D10](decisions.md#d10-assurance-as-evidence-values)). | A Boolean gives no pose; `CheckedFlap` is opaque ([`Flap.hs:19-20`](../src/Senbazuru/Origami/Flap.hs#L19-L20)). |
| **Intent survives.** Surfaces handed to the solver keep [intent assignments](glossary-additions.md#the-fold-format); only `Sequence.Write` applies the [state rule](glossary-additions.md#the-fold-format). | A crease about to fold still lies at 0. Written `F`, it would drop out of `surfaceFeatures`, which keeps an `F` edge only at a nonzero angle ([`Surface.hs:278`](../src/Senbazuru/Origami/Surface.hs#L278)), and the bending solver would treat it as a bend inside a panel, not a crease ([`FoldBending.hs:160-171`](../study/fold-material/FoldBending.hs#L160-L171)). |

**Records derive `Eq`** ([D10](decisions.md#d10-assurance-as-evidence-values),
[C4](decisions.md#changes-since-draft-v2)). No record field holds a function, so
`MoveRecord` derives `Eq` and tests compare records with `==`. That takes one
library change, [05](05-prd-library-additions.md) L14 at M2. `FlapMotion` and
`CheckedFlap` derive only `Show`
([`Flap.hs:93`](../src/Senbazuru/Origami/Flap.hs#L93),
[`:96`](../src/Senbazuru/Origami/Flap.hs#L96)), although every field's type derives
`Eq`: `Folded` ([`Folding.hs:324`](../src/Senbazuru/Origami/Folding.hs#L324)),
`HingeSweep` and `SweepCheck` ([`HingeSweep.hs:89`](../src/Senbazuru/Origami/HingeSweep.hs#L89),
[`:101`](../src/Senbazuru/Origami/HingeSweep.hs#L101)), `FaceOrder`
([`Types.hs:357`](../src/Senbazuru/Fold/Types.hs#L357)), `EdgeId` and `FaceId`
([`:284`](../src/Senbazuru/Fold/Types.hs#L284), [`:289`](../src/Senbazuru/Fold/Types.hs#L289))
and `V3` ([`V3.hs:32`](../src/Senbazuru/Geometry/V3.hs#L32)). So both gain
`deriving stock (Eq)`. A record's surfaces already compare, since `Surface` derives
`Eq` ([`Surface.hs:123`](../src/Senbazuru/Origami/Surface.hs#L123)), and the new
`CheckedMacro` and `SampleReport` derive it from the start.

### 2.3 Contract 2: the settle input

A *settle* is a static material solve that bends one step's rigid result
([glossary-additions](glossary-additions.md#material)). An author names paper
against the record, but the solver needs ids on a refined mesh. The contract
splits between the two:

| | `Sequence.Material` (study until M8) | `Material.Settle` (library from M8) |
| --- | --- | --- |
| Entry point | `settleStep :: SettleSpec -> MoveRecord -> Either SettleStepError Settled` | `settle :: SettleInput -> Surface V2 -> Either SettleError Settled` |
| Paper | the record's `recordBefore`, which must be a [flat state](glossary-additions.md#words-the-prds-narrow) | a `Surface V2` |
| Holds, grips | [holds](glossary-additions.md#material) named against the record (`side stationary`, or a [band](glossary-additions.md#material) such as `band moving 0..1/32`) and [grip](glossary-additions.md#material) targets (`rigid-pose 1/3`) | resolved vertex sets and target positions |
| Rest angles | `RestAngles`, such as `RestAtPose PoseRef` | `rest :: Map EdgeId Double` |
| Errors | `SettleStepError`: every refusal that names a move or a pose (`SettleOnNoMove`, `SettleNoPose`, `SettleNoRest`, `NoDifference`, …), and the solver's own as `SettleFailed SettleError` | `SettleError`, knowing no move |

`settleStep` resolves every name, then calls `settle`.
[07](07-prd-material-consumption.md) owns both sides, and
[D14](decisions.md#d14-material-consumption) decides them. Rule 2 is why there are
two error types: `Material.*` cannot name a move, so every refusal that does
belongs to `SettleStepError`, which wraps `SettleError`
([C6](decisions.md#changes-since-draft-v2)).

## 3. Stated exceptions

### 3.1 A sequence source is a program, not an input format

The rule is "a new input format becomes a `Frame` and stops there"
([AGENTS.md:193-196](../AGENTS.md), [architecture.md:170-175](../docs/architecture.md)).
A *sequence source*, the text an author writes
([glossary-additions](glossary-additions.md#the-sequence-language)), cannot follow it:

- **It needs the folding stack.** Running it needs `Fold.Creasing`,
  `Origami.Folding` and `Origami.Flap`; reading it in `Fold.Load.decodeFile`
  ([`Load.hs:102-106`](../src/Senbazuru/Fold/Load.hs#L102-L106)) would drag that
  stack to the top of the pipeline.
- **It needs a second file**, its sheet, which
  `decodeFile :: FilePath -> ByteString -> …` cannot read
  ([C](research/C-renderers-cli-formats.md) section (d), "A new input format becomes
  a Frame and stops there", finding 21).

So a source becomes a `Sequence` at the boundary, and running it gives a `Run`
holding one `MoveRecord` per move, which `Sequence.Write` turns into a `FoldFile`.
`decodeFile` refuses a `.foldseq` path with a new `LoadError` whose message says the
file is a sequence source, not FOLD, and names no command; `app/`'s `withFoldFile`
adds the hint to use `senbazuru run`
([D13](decisions.md#d13-the-run-verb-and-io)).
The output still obeys the rule: the written *sequence file* is plain FOLD that
every existing verb reads unchanged. `Render.Sequence` and the material consumer
read the records instead, by design.

### 3.2 A move is not "a frame in, a frame out"

[architecture.md:81-86](../docs/architecture.md) expects every authoring move to
have `Fold.Creasing`'s shape. `Fold.Creasing` keeps that shape, but a move cannot.
The page needs a move's kind, direction and hinge, and the study needs its
evidence and resolved paper. A frame holds none of these: a fold followed by its
unfold leaves every vertex where it was, adding at most flat creases, so nothing in
the two frames says which way the paper went or about which line.

### 3.3 `Diagram.Style` imports `Fold.Types`

[`Style.hs:91`](../src/Senbazuru/Diagram/Style.hs#L91) imports `Assignment` to choose
line styles. That goes against "`Senbazuru.Diagram` must not know what FOLD is"
([architecture.md:149](../docs/architecture.md)), and it is the existing, named
exception. The new arrows do not widen it:

- `ArrowPath` gains head and body shapes that know no assignment.
- `Render.Sequence` gives each arrow its record's kind, such as the move's *sense*
  (valley or mountain, as the author wrote it), and only `Diagram.Style.arrowFor`
  ([`Style.hs:364-372`](../src/Senbazuru/Diagram/Style.hs#L364-L372)) turns a kind
  into a head and a body ([D7](decisions.md#d7-a-typed-step-note-reaches-the-page),
  [06](06-prd-step-diagrams.md)).

`Render.Gltf` still consumes `Origami.Surface`
([architecture.md:176-182](../docs/architecture.md)).

## 4. Recorded text this design changes

Nothing under `PRDs/` edits these files. The rows are
[decisions §3](decisions.md#3-recorded-text-this-design-changes)'s, under the same
numbers; this section writes each replacement out. The PR in the *Lands* column
makes the change, and
[10 §3](10-roadmap-risks-questions.md#3-recorded-text-changes-by-milestone)
schedules it.

| # | Where | Lands |
| --- | --- | --- |
| 1 | `docs/architecture.md:81-86` | M0 |
| 2 | `AGENTS.md:193-196`, `docs/architecture.md:170-175` | M0, no later than M1's `Sequence.Parse` PR |
| 3 | [#60](https://github.com/avalonalex/senbazuru/issues/60) | M0 |
| 4 | [#95](https://github.com/avalonalex/senbazuru/issues/95) | M0 |
| 5 | [#97](https://github.com/avalonalex/senbazuru/issues/97) | M0 |
| 6 | [#111](https://github.com/avalonalex/senbazuru/issues/111) | M0 |
| 7 | #36, #94, #104, #114, #56, #64 | M0 |
| 8 | `AGENTS.md` "Third-party material" | M0 |
| 9 | `docs/notes/no-sequence-solver.md` | M0, with [#96](https://github.com/avalonalex/senbazuru/issues/96) |
| 10 | `docs/glossary.md` | M0, first PR |
| 11 | `AGENTS.md:173-177` | with M2 |
| 12 | `AGENTS.md:217-221` | two PRs: `runSequence` at M2, `stepPageWith` at M3 |
| 13 | `src/Senbazuru/Origami/Step.hs:30-34` | the M2 PR classifying presentation changes |
| 14 | `docs/architecture.md:202-211`; `BlintzSequence.hs`, `HelmetSequence.hs` headers | the recipe deletion PRs (M2 or later) |
| 15 | `AGENTS.md:378-379`, "all three CI checks" | the M4 PR adding the slow job |
| 16 | `docs/roadmap.md:82-87`, `:368-373` | M0 |
| 17 | `test/Senbazuru/Origami/ThroughLayersSpec.hs:271-275`, `docs/usage.md:866-872` | the follow-up PR fixing `LineStopsOnTheModel`, before M4 |
| 18 | `README.md:213-219` roadmap item 2, `docs/roadmap.md` item 2 | the PR closing #60 (M4) |

### 4.1 `docs/architecture.md:81-86`

Current: "Everything an authoring vocabulary (#60) adds will have that shape, and
will reach the rest of the pipeline the way a file does — by being a `Frame` that
`Fold.Query` cannot tell from one somebody wrote by hand."

Replacement for the paragraph:

> `Senbazuru.Fold.Creasing` is the first such caller, and the first module that goes
> *in* at the top and comes *out* at the top: a frame in, a frame out, no picture
> anywhere. A sequence's moves are not like that. `Senbazuru.Sequence.Run` threads
> a `FoldState` and returns one `MoveRecord` per move, because a step page and the
> material study need what no frame holds: which paper moved, about which hinge,
> which way as the reader sees it, with what evidence. (A fold and its unfold leave
> every vertex where it was.) What reaches the pipeline as a file is the `FoldFile` that
> `Sequence.Write` makes from the records, and `Fold.Query` cannot tell it from one
> somebody wrote by hand. `Render.Sequence` and the material consumer read the
> records, by design.

### 4.2 `AGENTS.md:193-196` and `docs/architecture.md:170-175`

Current (AGENTS.md): "`Senbazuru.Import.*` hands back a frame that says only what
the file said; nothing downstream may know a frame came from anywhere but a
`.fold`."

Append to both:

> A sequence source (`.foldseq`) is the stated exception: a program, not an input
> format. Running it needs the folding stack and a second file, its sheet. So
> `Fold.Load.readSequenceText` reads only its text, `Sequence.Parse` makes a
> `Sequence`, `Sequence.Run` makes a run of one `MoveRecord` per move, and
> `Sequence.Write` makes the `FoldFile`.
> Nothing reading the written file may know it came from a sequence.
> `Render.Sequence` and the material consumer read the records instead.

### 4.3 #60

Current: `apply :: Move -> Frame -> Either MoveError Frame`, with "`scanl` over it
is `[Frame]`" ("What and why"); "Not a free monad: there is one interpreter", item 1
"No geometry beyond a reflection" and item 4 "each a composition of the above"
("Approach"); "creases and coordinates match `examples/quarter-fold-steps.fold`"
and "the golden does not move" ("Done when").

"What and why", from the code block to the end of its paragraph:

> A sequence is a first-order value, `Sequence`, built in Haskell or parsed from a
> sequence source. A step is one figure holding one or more moves; `Move` names one
> move. `runSequence :: Budget -> RunSettings -> Map FilePath Frame -> Elaborated ->
> Either SequenceError Run` threads a `FoldState` and returns one `MoveRecord` per
> move, and `Sequence.Write` turns the run into the multi-frame `FoldFile` the
> renderer already consumes. It is not `[Move] -> [Frame]`: presentation, the
> material references each move was resolved from, and each move's kind and
> evidence must reach the page and the material study, and none survives into a
> frame.

"Approach", first paragraph and items 1 and 4:

> A plain first-order ADT and ordinary functions over it; not a free monad or
> tagless final. "One interpreter" no longer holds (check, elaborate, run,
> pretty-print, page and material make six), but a first-order value is still what
> they share, because it can be compared, printed and saved
> (`docs/notes/sequences.md`).
>
> 1. **Turn the model over.** Presentation, not a frame move: a half turn about a
>    model-intrinsic axis through the bounding-box centre, never a reflection, which
>    gives the mirror model (#95).
> 4. **Macro-moves** (collapse, rabbit ear, petal): named angle relations with
>    signatures, not compositions of flap turns; a petal's seven creases turn at
>    three rates.

"Done when":

> - **Folding equivalence.** Run `sheet "examples/quarter-fold-steps.fold"`,
>   `anchor (3/4, 1/4)`, `fold behind edge west to edge east`, `fold in front edge
>   north to edge south`. The first fold turns about existing edges 8 and 10, the
>   second about 9 and 11, and no ids change. Written `file_frames` 0, 1 and 2 are
>   compared with the fixture's key frame, `file_frames[0]` and `file_frames[1]`:
>   positions (the fixture's, with z = 0) within 1e-12 × `modelSpan`; angles, edges
>   and face rings exactly; each assignment equal to the state rule applied to the
>   fixture's assignment and angle; `frame_classes` compared; `frame_title`,
>   `faceOrders` and `frame_attributes` not compared. `render --steps`
>   over these frames is a new reviewed golden; the existing golden stays as the
>   regression for the unchanged fixture.
> - **Authoring.** The same moves from `sheet square` write coarser crease graphs,
>   so frames are compared by material identity, which piece of paper each vertex
>   and edge is, by five rules per state. T1: each fixture edge lies inside exactly
>   one written edge with the same angle, or inside none at angle 0. T2: the
>   fixture edges inside a written edge cover it. T3: each written vertex sits at a
>   fixture vertex's material coordinates, positions within 1e-12 × `modelSpan`.
>   T4: every other fixture vertex is placed at its fixture position, within the
>   same tolerance, by the written face or edge containing it. T5: assignments
>   follow the state rule. Their page is a new reviewed golden. The test and its
>   page land at M4, and this issue closes with them.
> - A move that cannot be applied is refused naming the step, the author's
>   reference and the offending element, and is never applied halfway.

[09 §2.2](09-testing-and-acceptance.md#22-test-1-folding-equivalence-m2) and
[§2.3](09-testing-and-acceptance.md#23-test-2-authoring-from-sheet-square-m3-and-m4)
own the full comparison tables.

### 4.4 #95

Current: "Turning over is a **half turn about an axis in the page**, `(x, y, z) ↦
(-x, y, -z)`", applied as `apply TurnOver`. The done-when compares the result with
`render --view bottom`.

"Approach":

> `turn over left-right | top-bottom` is presentation: it changes `FoldState`'s
> presentation, never a crease. A half turn about the line x = 0 would carry the
> quarter fold from x ∈ [½, 1] to x ∈ [−1, −½], moving it across the page and
> doubling the page's width, so the turn is about the model's own centre.
> `left-right` maps (x, y, z) to (2cx − x, y, 2cz − z), and `top-bottom` to
> (x, 2cy − y, 2cz − z). Here (cx, cy) is the centre of the current displayed
> state's xy bounding box, and cz the middle of its z range. They are computed from
> `Geometry` alone, never from a camera. The turn is a proper rotation, so windings,
> angles, assignments and `faceOrders` stay as written. The reader's side flips
> with it.

"Done when":

> - `Origami.Step` classifies a frame pair as a presentation change, with no
>   inferred arrow, when some vertex moves and one whole-model proper rigid motion
>   (`Geometry.Rigid.fitRigid`) maps every vertex onto the second frame. An
>   identical pair still gives `[]`, since nothing moves.
> - `render --steps --arrows` is byte-identical for every tracked golden and every
>   multi-frame file under `examples/`.
> - A turn over keeps each figure's extent (the box it fills on the page), the page
>   union (the union of every figure's extent, which fixes the one scale) and the
>   scale, on top-down and bottom-up pages whose roll (the camera's turn about its
>   viewing direction) is a multiple of 90°.
> - Closes at M2.

### 4.5 #97

Current: "Record the decision and the two rejected shapes in
`docs/notes/schemes.md`". Done-when 2 asks the quarter fold to reproduce the
fixture, "which is #60's own acceptance test".

Replacement:

> Record the decision and the rejected shapes in `docs/notes/sequences.md`.
> "Scheme" is retired. An author writes a *sequence source*, which produces a
> *sequence file*. A figure is a *step*, and an instruction in it is a *move*.
>
> Done when:
>
> - The note records the decision, the alternatives and the reference vocabulary
>   (M0).
> - The quarter fold, written in the chosen syntax, passes #60's
>   folding-equivalence test (M2). #60 keeps the authoring test, which lands with
>   its page at M4.
> - #60's approach is updated to match (M0).
>
> This issue closes at M2, not M0.

### 4.6 #111

Current: a four-row table (`resolveAssignments`, `foldAnglesOf`,
`creaseDirections`, `flatAngleFor`). Add these rows and a sentence:

> | Where | What it decides |
> | --- | --- |
> | `Sequence.Write` (planned) | written frames: `B`, `C`, `J` kept; otherwise `M` below −τ, `V` above τ, and `F` written at exactly 0; τ is `Fold.Query.atRest` |
> | `Origami.Surface.surfaceFeatures` | `B`, `M`, `V`, `U` and `C` edges are always features; an `F` or `J` edge is one when its angle's magnitude exceeds `1e-10` (`Surface.hs:278`) |
> | study `StudyCase` (`StudyCase.hs:208`) | the reverse rule: an `F` edge whose angle's magnitude exceeds `1e-10` becomes `M` or `V` |
>
> The last two should read `Fold.Query.atRest`. `creaseDirections` keeps its exact
> test, and its header says why: "which way" may be answered more coarsely than
> "how far".

### 4.7 Corrections to six issues

| Issue | Current | Replacement |
| --- | --- | --- |
| [#36](https://github.com/avalonalex/senbazuru/issues/36) | Done-when 1: a pair "reflecting every vertex through the sheet's plane produces a turn-over arrow". Approach: arrow kind "from the assignment that changed". | "A pair related by one whole-model proper rigid motion is a presentation change: no inferred arrow, and a sequence's `turn over` places a `Symbol`. A reflection is the mirror model." Approach: "Arrow kind comes from the move record; one motion can change a `V` and an `M` crease together (quarter-fold step 2 sets edge 9 to +180 and edge 11 to −180)." |
| [#94](https://github.com/avalonalex/senbazuru/issues/94) | "`frame_title` and `frame_description` are decoded into `Frame` and nothing reads them"; done-when: the quarter fold "given titles, draws them under the figures", and the single-frame `render --arrows` page "draws the title too". | "The CLI reads `frame_title` for `info`, the page title and the glTF title (`Cli.hs:981`, `:879`, `:779`), but nothing draws it under a figure. A file cannot say whether its titles name states, as the fixture's "Step 2: folded in half" does, or give instructions, as a written sequence file's do: there a state's `frame_title` is the caption of the step leaving it. So `render --steps` never draws `frame_title`, and every page it draws stays byte-identical, `quarter-fold-steps.svg` included. Captions come from step notes." Done when: "`run -o x.svg` draws each step's caption under the figure of the state the step starts from, and the `closing` caption under the last figure, pinned by a new golden; every tracked golden stays byte-identical. Closes at M3." ([D7](decisions.md#d7-a-typed-step-note-reaches-the-page), [C35](decisions.md#changes-since-draft-v2)) |
| [#104](https://github.com/avalonalex/senbazuru/issues/104) | Cites `docs/notes/inflate-outside-draw-inside.md`; done-when 1 asks `render examples/puffed-square.fold --view iso --hide-flat` to draw "the dome's outline"; done-when 3 lets two examples change "except for any edge that is a silhouette". | "Default `render` output is byte-identical; `render examples/puffed-square.fold --view front --hide-flat --lines features` draws the visible boundary and silhouette, as a new golden." A *silhouette* is an edge between a face turned towards the reader and one turned away, of any assignment: the file's 320 edges are 40 `B` and 280 `F` (`jq`), so a rule limited to `J` edges finds none of its 27 candidates from the front. From `--view iso` no face of the file turns away, so done-when 1 cannot be met; from `--view front`, the view of done-when 2, 90 of 200 faces do ([08](08-prd-realistic-rendering.md#104-amended), [D19](decisions.md#d19-realistic-rendering)). The cited note does not exist (`ls`). M7b advances the issue without closing it. |
| [#114](https://github.com/avalonalex/senbazuru/issues/114) | "Both numbers already exist: `Origami.Layers.layerDepths` and `--thickness`"; the export "lifts each face by its layer number". | "`--thickness` and face lifting were removed (`docs/notes/paper-thickness.md:8`, `docs/architecture.md:126`), and a second bend rounded over a first stretches 200% (`docs/notes/two-bends-need-more-than-radii.md:55`): thickness as geometry is research." Full rewrite at M6. |
| [#56](https://github.com/avalonalex/senbazuru/issues/56) | Transforms are what `spanningWalk` "computes and currently discards"; step 1, "Expose the per-face `Rigid`s". | "`foldFrameWith` returns them as `foldedPlacements` (`Folding.hs:322`), used by `Flap` and `ThroughLayers`. Keys come from checked routes via `recordPoseAt`, over one node hierarchy per checkpoint interval, on that interval's final cut pattern, with each face's parent and crossing edge taken from `Origami.Folding`'s own walk. Closes at M7b." ([D19](decisions.md#d19-realistic-rendering)) |
| [#64](https://github.com/avalonalex/senbazuru/issues/64) | "**Inflate the body** is *outside the model*, not merely hard." | "Opening a body is a stated future goal (`README.md:158-164`, #106); what lies outside the rigid model is bending and pressure, not opening." |

### 4.8 `AGENTS.md` "Third-party material"

Append after "A repository licence is not a design licence":

> **Running an external program and reading its output is not vendoring.** It
> needs a row in `docs/related-projects.md` giving the licence of the program *as
> built*, since a permissive source can link GPL code by default. Any output kept
> needs provenance in `examples/README.md`. No CI job or test may depend on the
> program, the build, format and lint tools excepted. External solvers are
> comparison oracles, never ahead of the in-repo
> path, and the design-licence rule applies to any pattern fed to one.

### 4.9 `docs/notes/no-sequence-solver.md`

Current: "**A "step" is not a formal object.** … there is no agreed formalisation
of the vocabulary to emit", and later "The real barrier is the first reason: you
cannot search a move set nobody has defined".

The first reason becomes:

> **A "step" was not a formal object.** Diagrams are written in named macro-moves,
> each several creases formed together. Senbazuru's own vocabulary is now formal
> (`docs/notes/sequences.md`), but only for the moves it models; a coupled
> macro-move enters once its angle relation is derived. Searching over it stays a
> non-goal: many patterns are collapsed rather than folded in sequence, and a
> vocabulary covering some book moves cannot say which unmodelled move a sequence
> needs.

The "real barrier" sentence becomes: "For a general move set the real barrier is
still the first reason: senbazuru's own moves are not a vocabulary to search, and
substituting the nearest well-defined one returns sequences that fold through forty
layers at once."

### 4.10 `docs/glossary.md`

First fix the three rows below, by these line numbers, which moving rows in would
shift. Then move the rows of [glossary-additions.md](glossary-additions.md) in,
rewriting links for the new directory: `research/X` becomes `../PRDs/research/X`,
`0N-….md` becomes `../PRDs/0N-….md`, `../docs/notes/X` becomes `notes/X`, and
`../src/…` and `../study/…` are unchanged. Each row under "Words the PRDs narrow"
is merged into the glossary row of the same term. Glossary-additions' **Springback**
row is dropped, because the `:19` replacement supersedes it. Every other row goes
into its section.

| Line | Current | Replacement |
| --- | --- | --- |
| `:19` | **Rest angle**: "The angle a creased sheet's two panels settle at when nothing is loading them…" | **Springback**: "A pressed crease reopening partway when released, to an angle set by the material's yield stress, independent of thickness, and not zero. See notes/a-crease-is-a-hinge.md." |
| `:83` | **Rest angle**: "The angle a crease spring prefers…" | The only rest-angle row, adding: "In a settle it comes from a rest pose, never from an assignment." |
| `:21` | **Flat-folded**: "Every fold angle is exactly ±180°." | "Folded so every face lies in one plane, so every fold angle is 0 or ±180°. A crease made and unfolded stays at 0." |

### 4.11 `AGENTS.md:173-177`, "Two unit systems"

Append:

> Sequences add *sheet lengths* (the sheet box's larger side is 1) and *physical
> lengths* (the `material` block). Each becomes model units in exactly one place:
> sheet lengths when `Sequence.Run` resolves a reference, physical lengths when
> `Sequence.Material` resolves a settle.

### 4.12 `AGENTS.md:217-221`, the `--layer-budget` list

Add `runSequence` to "`creasePatternFrom`, `creasePatternAuto`, `surfaceDiagram`,
`stepPage`, `renderGlb` and `renderSurfaceGlb`". `stepPageWith` joins the list at
M3, since its signature also takes a `Budget`.

### 4.13 `src/Senbazuru/Origami/Step.hs:30-34`

Current: "a step may move paper without changing any angle, by turning the whole
model over. The coordinates are what the reader is looking at."

Replacement paragraph:

> Comparing positions rather than reading fold angles is deliberate, and it is the
> more robust of the two: a frame may record no angles, or angles that disagree with
> its coordinates. The coordinates are what the reader is looking at, with one
> exception. When some vertex moves and one proper rigid motion
> (`Geometry.Rigid.fitRigid`) maps every vertex onto the next frame, nothing was
> folded: the reader turned the model over or round. A turn over leaves the
> vertices on its axis where they were, so the test cannot ask that every vertex
> move. That pair is a presentation change, marked with a symbol and given no
> inferred arrow. An identical pair is not one.

**Some vertex, not every vertex**
([D5](decisions.md#d5-presentation-and-the-readers-side),
[C26](decisions.md#changes-since-draft-v2); the rule is
[05 L3](05-prd-library-additions.md#l3-fitrigid-proper-rotations-and-the-whole-model-classification)'s
R-05-12′). A turn-over leaves the vertices on its axis where they were, so a test
asking every vertex to move would give the runner's own turn-overs arrows. On the
key frames of `quarter-fold-steps.fold` and `quarter-fold.fold`, 3 of 9 vertices lie
on the `left-right` axis; on `bird-base.fold` 5 of 13, and on `blintz-base.fold` 2
of 8. That counts the vertices at the x-midpoint of each key frame's bounding box,
run at `568dcb6`:

```bash
python3 -c 'import json;[print(f,sum(v[0]==(min(u[0] for u in V)+max(u[0] for u in V))/2 for v in V),len(V)) for f in ["quarter-fold-steps","quarter-fold","bird-base","blintz-base"] for V in [json.load(open("examples/%s.fold"%f))["vertices_coords"]]]'
```

A flap turn still cannot qualify: its stationary face keeps three vertices that are
not on one line where they were, so the only rigid motion fitting every vertex is
the identity, which the moved vertices contradict.

### 4.14 `docs/architecture.md:202-211` and the recipe headers

Current: "`BlintzSequence` composes five accepted turns … neither module introduces
a second contact checker or a general instruction format. `HelmetSequence` chains
three turns … see [aligned hinges](../docs/notes/aligned-crease-hinges.md)." The header of
`BlintzSequence.hs:4` says "not an instruction language".

When the deletion PRs remove the recipes, those sentences (lines 202-211) become the
text below. The rest of the paragraph, lines 192-201 on `Flap` and 212-221 on
`HingeSweep`'s contacts, is unchanged:

> The blintz and helmet sequences replace the `BlintzSequence` and `HelmetSequence`
> recipes. `Sequence.Run` performs the same checked turns with the handoff those
> recipes established: angles and endpoint orders carried onto the material
> pattern, the stationary face first, every join checked. Their galleries draw the
> run's records through the ordinary renderers.

The headers go with their modules.

### 4.15 `AGENTS.md:378-379`, "all three CI checks"

Current: "`main` is protected. Changes reach it through pull requests, and all three
CI checks must be green before merge. Do not push to `main` directly."

The three are the jobs of `.github/workflows/ci.yml`: `test` ("build and test"),
`format` ("ormolu") and `lint` ("hlint"). M4 adds a fourth job for the crane-sized
specs under `describe "slow"`, which the default job skips
([D16](decisions.md#d16-testing-and-acceptance)). Replacement, under
[owner decision 12](decisions.md#9-owner-decisions)'s recommended default that the
slow job is a required check (the job's name is **SKETCH**, chosen in that PR):

> `main` is protected. Changes reach it through pull requests, and all four CI
> checks — build and test, ormolu, hlint, and the slow tests — must be green before
> merge. Do not push to `main` directly.

If the owner makes the slow job optional instead, the sentence keeps "three" and
adds: "The slow tests run as a fourth job, which is not required."

### 4.16 `docs/roadmap.md:82-87` and `:368-373`

Both passages record an order this design replaces: the vocabulary waits on #97,
and #97 waits on #93 and #96, before "only then" #95, #94 and #36. M0 decides #97
without #93, and the milestones schedule #95 at M2, #94 and #36 at M3, and #60's
close at M4 ([decisions §8](decisions.md#8-milestones)). The PR keeps the file's
full issue links; the text below writes them as numbers.

Current, roadmap item 2 (`:84-87`): "The done-when — reproduce
`examples/quarter-fold-steps.fold` from a written scheme — is not met. What stands
in the way is a decision, #97, on how a scheme is written down, before the second
move #95 and the flap rotation #54."

Replacement for those two sentences:

> The done-when — reproduce `examples/quarter-fold-steps.fold` from a written
> sequence — is not met. #97's decision is recorded in `docs/notes/sequences.md`,
> and the milestones in `PRDs/10-roadmap-risks-questions.md` order the rest:
> turning the model over (#95) at M2, arrows and captions (#36, #94) at M3, and
> folding some layers, which advances #54, at M4, where #60 closes.

Current, items 2 and 3 of the ordered list (`:368-373`): item 2 is #93, the sweep;
item 3 reads "#96 then #97: read what the 2026 papers use as their vocabulary, then
decide the scheme format. Only then #95, #94 and #36, which give a written scheme
its arrows and captions."

Item 2 is unchanged except for an appended sentence, "The sequence language in item
3 does not wait for it." Item 3 becomes:

> 3. The sequence language, in the order of the milestones in
>    `PRDs/10-roadmap-risks-questions.md`: #96 amended and #97 decided at M0 (#97
>    closes at M2), #95 at M2, #94 and #36 at M3, and #60 at M4.

### 4.17 `ThroughLayersSpec.hs:271-275` and `docs/usage.md:866-872`

Current, the sentence the spec pins for the end (0.2, 0.2) on `diagonal-cp.fold`:
"--from is inside face 0 of the folded model rather than on that face's edge, so
that layer would be creased only part of the way across. Each layer the line
reaches has to be creased right across, so move this end onto an edge or clear of
the paper". `docs/usage.md:868-871` quotes the same sentence from a run on
`examples/bird-base.cp`, starting "--from is inside face 12".

The sentence starts with `creaseEndFlag end`
([`ThroughLayers.hs:194-195`](../src/Senbazuru/Origami/ThroughLayers.hs#L194-L195),
[`Query.hs:68-71`](../src/Senbazuru/Fold/Query.hs#L68-L71)): a command-line word in
a library message, which a sequence run has no flag to match
([D20](decisions.md#d20-errors)).
[05 L6](05-prd-library-additions.md#l6-linestopsonthemodel-carries-its-point)
carries the given point in `LineStopsOnTheModel` and names the end by it, as
`CreaseEndMeetsNothing` already does
([`Query.hs:312-318`](../src/Senbazuru/Fold/Query.hs#L312-L318)).

Replacement: in the spec, the first words "--from is inside face 0" become "the end
at (0.2, 0.2) is inside face 0", and the rest of the sentence is unchanged. In
`docs/usage.md`, the output's "--from is inside face 12" becomes "the end at
(-200.0, 150.0) is inside face 12". The digits are `coord`'s, which prints a
`Double` in fixed point, so -200 prints as `-200.0`
([`Query.hs:423-430`](../src/Senbazuru/Fold/Query.hs#L423-L430)). **UNVERIFIED**:
the `usage.md` output, which no test pins; the PR reruns the command and pastes what
it prints.

### 4.18 `README.md:213-219` and `docs/roadmap.md` item 2

This lands in the PR closing #60 (M4), after §4.16 has rewritten roadmap item 2.

Current (`README.md:213-219`): "**A vocabulary of folds, so a sequence can be
authored.** … What is missing is the rest of the vocabulary — turning the model
over, rotating a flap, and the named moves a book uses — and a way to write a whole
sequence down. Not a sequence *solver*; see above."

Replacement: the item's title gains the "Complete:" prefix item 1 already uses
(`README.md:205`, `docs/roadmap.md:68`), and the "What is missing" sentence becomes:

> The vocabulary exists: a sequence is written in Haskell or as a `.foldseq`
> source, and `senbazuru run` folds it move by move, checks each move, and writes a
> sequence file, a step page or a GLB. What remains are the coupled moves
> (collapse, rabbit ear, petal) and the book moves not modelled yet — squash, the
> reverse folds, sink, swivel, crimp — each waiting for a derived and tested angle
> relation.

In `docs/roadmap.md`, item 2 becomes "**Complete: a vocabulary of folds** (#60)",
and the same two sentences replace §4.16's.

## 5. One move, end to end: quarter fold, step 2

This is the second move of #60's folding-equivalence test (§4.3). Each number
carries a tag:

- **[jq]**: a measurement of the fixture;
- **[py]**: a Python re-implementation of `Origami.Folding`'s walk and `Flap`'s
  sign rule, not senbazuru;
- **[reasoned]**: worked out from the cited code.

**UNVERIFIED** marks what needs Haskell. §5.10 has the commands.

### 5.0 The fixture and the source

`examples/quarter-fold-steps.fold` is a unit square with four creases meeting at its
centre, and two folded states in `file_frames` [jq]. A *face* is a flat region
between creases. A *fold angle* is 0 when flat, +180 for a *valley* folded flat
and −180 for a *mountain* folded flat. In a valley the paper either side of the crease swings up
towards the viewer while the crease line itself stays down, away from the viewer,
which is the part the [glossary](../docs/glossary.md#origami) describes; a mountain
is the reverse. A *state* is one `file_frames` entry of the written sequence file,
numbered from 0 by its index
([D24](decisions.md#d24-states-figures-and-their-numbers)): state 0 is the flat
sheet, state 1 is after `half`, and state 2 is after `quarter`.

```text
                 edge north = edges 4, 5
 v3 (0,1) ------- v6 (1/2,1) ------- v2 (1,1)
    |       F2         | 10      F1       |
 v7 (0,1/2) --11-- v8 (1/2,1/2) --9-- v5 (1,1/2)
    |       F3         | 8       F0       |
 v0 (0,0) ------- v4 (1/2,0) ------- v1 (1,0)
                 edge south = edges 0, 1
```

The faces are F0 `[8,4,1,5]`, F1 `[8,5,2,6]`, F2 `[8,6,3,7]` and F3 `[8,7,0,4]`.
Edges 0–7 are boundary (`B`); creases 8–11 are `M V M M`, all at angle 0 in the
key frame [jq]. Edge 11 is `M` though step 2 is a valley; §5.6 says why. The
source is [decisions §7](decisions.md#7-examples)'s quarter fold, and the move
walked here is on line 10:

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

### 5.1 Parse, check, elaborate

**Parse.** `Sequence.Parse` reads `fold in front edge north to edge south` at
line 10, columns 3–40 [py].

- `in front` is the alias of `valley`.
- Both operands start with the keyword `edge`, so `to` joins two lines. That is
  Huzita–Hatori O3, the fold laying one line onto another
  ([glossary-additions](glossary-additions.md#references)).
- There is no angle, so the fold goes flat. There are no layer words, so it moves
  the [flap](glossary-additions.md#words-the-prds-narrow) containing its first
  argument.

The parsed move (**SKETCH**):

```haskell
Located span (Fold ValleyFold ToFlat (LineOnto (EdgeOf North) (EdgeOf South) Nothing) FlapOfFirstArgument Nothing)
```

The constructor is `ValleyFold`, not `Valley`, because `Fold.Types` already has an
assignment constructor `Valley` and `Sequence.Run` imports both modules
([D1](decisions.md#d1-one-first-order-syntax-tree-built-by-name-only-builders)).
`prettySequence` prints the move as `fold valley edge north to edge south`.

**Check.** `Sequence.Check` confirms that `half` and `quarter` are unique names and
that both operands of `to` are lines. It uses no geometry, so `run --check` stops
here.

**Elaborate.** `Sequence.Elaborate` has nothing to expand.

### 5.2 The state before the move

`sheetState` takes the **key frame**, never one of the 2 `file_frames` [jq]:

- **Accepted.** It is `creasePattern` and 2D, so `Query.frameKind` says
  `CreasePattern` ([`Query.hs:459-463`](../src/Senbazuru/Fold/Query.hs#L459-L463)).
- **Face ids are the file's.** `withPlanarFaces` leaves a frame that already records
  faces unchanged: `splitCrossings` returns it as it is
  ([`Crossings.hs:128`](../src/Senbazuru/Fold/Crossings.hs#L128)), and so does
  `withTracedFaces` ([`Faces.hs:136-138`](../src/Senbazuru/Fold/Faces.hs#L136-L138)).
- **Nothing re-wound.** A face's *ring* is its corners in order, and a positive
  signed area means it runs counter-clockwise. In *material coordinates*, where each
  point was on the unfolded sheet, every ring's area is +0.25 [py].
- **Anchor**, the material point whose face stays still. The sheet box is [0,1]²,
  so [sheet lengths](glossary-additions.md#references) equal model units. (3/4, 1/4) is strictly
  inside F0 alone, 0.25 from its boundary and 0.354 from the nearest vertex [py].
  `Origami.Folding` holds its first face still and places everything else relative
  to it ([`Folding.hs:578-585`](../src/Senbazuru/Origami/Folding.hs#L578-L585)), so
  the runner puts the anchor's face first. F0 already is first, so nothing is
  reordered, and anchor placement and presentation are the identity: coloured side
  up, no whole-model turn yet.
- **Angles.** Intent `M V M M` on 8–11 is kept, and `sheet` sets every angle to 0.

**Step 1** turns about edges 8 and 10 with *travel* −180, by §5.6's rule; travel is
the signed change in the first hinge crease's fold angle
([glossary-additions](glossary-additions.md#running-a-sequence)). At −179° the
F2 and F3 centroids are at z = −0.0044, behind the sheet; at −180 the refold matches
the fixture's first folded state within 6.1e-17 [py], moving vertices 0, 3 and 7
[jq]. The expected carried orders are `FaceOrder 3 0 Below` (F3 below F0, against
F0's normal) and `FaceOrder 2 1 Below`, built from the contacts at the end of the
turn ([`Flap.hs:301`](../src/Senbazuru/Origami/Flap.hs#L301)). **UNVERIFIED**: the
contacts `HingeSweep` reports.

Step 1 laid the west half exactly on the east half, so v0 now sits on v1, v3 on v2
and v7 on v5. The repeated coordinates below, and the edges in §5.3 that run over
the same stretch in opposite directions, are not typos.

State 1, where this move starts [jq]:

| Vertex | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| x, y | 1, 0 | 1, 0 | 1, 1 | 1, 1 | ½, 0 | 1, ½ | ½, 1 | 1, ½ | ½, ½ |

### 5.3 References, fold line and moving side

State 1 is a [flat state](glossary-additions.md#words-the-prds-narrow): every face
lies in z = 0. So [constructions](glossary-additions.md#references) are allowed.

- **`edge north`.** Its material edges are 4 (v2–v6) and 5 (v6–v3), now at
  (1,1)–(½,1) and (½,1)–(1,1) [py]. Their y values spread by 0, within
  `Fold.Faces.tolerance` = 1e-9 × the sheet diagonal = 1.41e-9
  ([`Faces.hs:248-249`](../src/Senbazuru/Fold/Faces.hs#L248-L249)). They are
  collinear, on y = 1.
- **`edge south`.** Edges 0 and 1, now at (1,0)–(½,0) and (½,0)–(1,0), lie on
  y = 0.
- **The fold line.** O3 on two parallel lines has one solution, the midline
  **y = ½**. Crossing lines give two bisectors; the one mapping segment onto
  segment is preferred, and `nearest` is needed only if both remain.
- **The [moving side](glossary-additions.md#references).** For `L1 to L2` it is
  the side holding the interior of the first segment. Edge 4 lies at y = 1 and
  does not straddle the line, so the y > ½ side moves.

### 5.4 Which layers, and the hinge

- **Existing creases.** In state 1 exactly edges 9 and 11 have both ends on y = ½
  [py]; edge 11, material (½,½)–(0,½), is there only because step 1 swung it over.
  So the move uses them as its [hinge](glossary-additions.md#origami) without creasing
  ([02](02-language-semantics.md)): no new id, and `recordBefore` is state 1.
- **The flap.** A [flap](glossary-additions.md#words-the-prds-narrow) is every face still joined to a
  [seed](glossary-additions.md#references) once the paper is cut along the line. Cutting at 9 and 11
  leaves edges 8 (F3–F0) and 10 (F1–F2) as links, so the components are {F1, F2}
  and {F0, F3} [py]. `edge north` lies in F1 and F2, so they move: two layers, F1
  face up and F2 face down (normals +z for F0 and F1, −z for F2 and F3 [py]). F0
  holds the anchor, so nothing re-anchors.
- **Nothing refused.** A selection is refused when stationary paper covers the
  moving layers on the side they turn towards, or when the moving layers stay joined
  to paper that does not move
  ([05 L11](05-prd-library-additions.md#l11-the-selection-rule-lives-in-the-library)).
  Here F1 is the top layer over y > ½ and the flap turns towards +z, so nothing
  covers it, and cutting at 9 and 11 separates the flap cleanly [reasoned].
  **UNVERIFIED**: that rule has only a Python reproduction
  ([gap-layer-selective-folds](research/gap-layer-selective-folds.md) "Re-deriving
  CraneWing by rule (script)").
- **The call** (**SKETCH**): `prepareFlapToward [EdgeId 9, EdgeId 11] (FaceId 1)
  180 TowardRawPlusZ folded`, where `folded` is `foldFrameWith` of the working
  pattern with step 1's orders on it, `FaceId 1` is the moving face on the first
  crease, 180 is the size of the turn, and `TowardRawPlusZ` is the raw valley's
  side, from which `Flap` works out the signed travel as §5.5 shows. #344 named
  it `TowardPlusZ`; §5.5 says what owner decision 13 changes.
  `prepareFlapToward` is new
  ([05](05-prd-library-additions.md) L14); it signs the travel and then does what
  `prepareFlapAlong` does today
  ([`Flap.hs:157-164`](../src/Senbazuru/Origami/Flap.hs#L157-L164),
  [`:195`](../src/Senbazuru/Origami/Flap.hs#L195)).

### 5.5 Raw sense and travel

Directions are read from the [reader's side](glossary-additions.md#running-a-sequence). The
*raw sense* is the author's sense restated for unpresented coordinates: negated when
presentation after anchor placement turns +z to −z
([02 §5.3](02-language-semantics.md#53-one-conversion-for-the-whole-model)). Here that
composition is the identity, so the raw sense is valley: the moving paper lifts
towards raw +z.

*Travel* is the signed change in the first crease's fold angle
([glossary-additions](glossary-additions.md#running-a-sequence)). `Flap` turns the paper by
−travel, right-handed, about an axis along that crease, pointing the way the
stationary face's counter-clockwise ring runs, in folded coordinates
([`Flap.hs:10-13`](../src/Senbazuru/Origami/Flap.hs#L10-L13),
[`:201-206`](../src/Senbazuru/Origami/Flap.hs#L201-L206),
[`:222`](../src/Senbazuru/Origami/Flap.hs#L222)). For edge 9 the stationary face is
F0, so the axis is v5 → v8 = (−1, 0, 0), from v5 = (1, ½, 0). A small right-handed
turn by θ moves a point at offset r by about θ (axis × r); for v2, r = (0, ½, 0) and
axis × r = (0, 0, −½). For a small fraction δ of the turn θ = −travel·δ, so v2 rises exactly when
travel > 0. So **travel = +180**.

At progress ½ (edge 9 at +90, edge 11 at −90), F1 and F2 have centroid z = +0.25
while F0 and F3 stay at 0, placements agree within 6.1e-17, and rotating the moving
vertices −90° about the axis lands exactly on the refold, v2 at (1, ½, ½) [py]. That
agreement is what `Flap`'s `comparePoint` requires of `HingeSweep`'s path
([`Flap.hs:349-360`](../src/Senbazuru/Origami/Flap.hs#L349-L360)).

**Why the runner passes a side, not +180**
([D5](decisions.md#d5-presentation-and-the-readers-side),
[C5](decisions.md#changes-since-draft-v2)). The sign just worked out depends on the
direction of `Flap`'s axis, which `Flap` derives from the first segment's
stationary face's ring and does not export
([`Flap.hs:195-206`](../src/Senbazuru/Origami/Flap.hs#L195-L206)). With edge 11
listed first, the same valley would be travel −180, because its stationary face F3
lies face down. So the raw sense alone cannot sign the travel, and the library,
which holds the ring, signs it. `Origami.Flap` gains (**SKETCH**,
[05](05-prd-library-additions.md) L14):

```haskell
data Toward = TowardRawPlusZ | TowardRawMinusZ
prepareFlapToward :: [EdgeId] -> FaceId -> Double -> Toward -> Folded -> Either FlapError FlapMotion
```

It takes the size of the turn, A (180 here), and a raw side. It reads the first
segment's stationary face normal from that face's placement and sets travel to +A
when the side agrees with the normal's z sign, −A otherwise; a
normal that is not ±ẑ within 1e-12 is refused as `FlapStationaryNotFlat`. The
runner passes `TowardRawPlusZ` for a raw valley. Here the first stationary face is
F0, normal +z, so travel is +180; listing edge 11 first would make it F3, normal
−z, and travel −180, the same physical turn.

*Superseded in part* by [D5](decisions.md#d5-presentation-and-the-readers-side)'s
amendment (owner decision 13): the sign is read from the *moving* face beside the
first crease, F1 here, which lies top up and gives the same +180; with edge 11
first it is F2, face down, and −180 as before. This section is rewritten with that
change to `prepareFlapToward`.

### 5.6 Travel per segment

**In the table, edge 11 ends at −180 under a valley fold. That is not a typo.** Why
one valley writes opposite signs on edges 9 and 11 is
[02 §5.3](02-language-semantics.md#53-one-conversion-for-the-whole-model); this
section shows where the code makes the sign.

[`Flap.hs:208-216`](../src/Senbazuru/Origami/Flap.hs#L208-L216) handles each
segment in turn. It finds the segment's stationary face, and that face's ring edge
u → v along the crease. The segment gets `travel` when (v − u)·axis > 0, and
`−travel` otherwise:

| Segment | Stationary face | Ring edge | (v − u)·axis | Angle after |
| --- | --- | --- | --- | --- |
| 9 | F0, face up | v5 → v8 | +0.5 | +180 |
| 11 | F3, face down | v8 → v7 | −0.5 | −180 |

F3 lies upside down after step 1, so its ring runs the other way along the shared
line, and edge 11 takes −travel. The fixture's last state agrees [jq].

Both segments' ends lie within 6.1e-17 of the hinge line, below `Flap`'s 1e-12
([`Flap.hs:207`](../src/Senbazuru/Origami/Flap.hs#L207)) [py]. Step 1 works the
same way: edges 8 (F0, v8 → v4) and 10 (F1, v6 → v8) both give +0.5, so both
take −180 [py].

### 5.7 The checked turn and the join check

- **Sweep.** `checkFlap defaultSweepSettings` checks the half turn for paper passing
  through paper, to depth 20 within 4096 [sweep intervals](glossary-additions.md#geometry)
  ([`HingeSweep.hs:95`](../src/Senbazuru/Origami/HingeSweep.hs#L95)). `FaceOrder 2 1`
  (both moving) and `FaceOrder 3 0` (both stationary) move rigidly
  ([`Flap.hs:223-233`](../src/Senbazuru/Origami/Flap.hs#L223-L233)), and the end
  contacts add new orders. From the reader the stacking should end F2, F1, F0, F3
  [reasoned]: F2 lay on F1's back, and F1 lands face down on F0. **UNVERIFIED**: the
  reported orders and the interval count.
- **Handoff.** The runner takes `flapAt checked 1`, carries its angles (−180, 180,
  −180, −180 on 8–11) and orders onto the working pattern and refolds, as
  [`BlintzSequence.hs:63-64`](../study/fold-material/BlintzSequence.hs#L63-L64)
  does.
- **[Join check](glossary-additions.md#running-a-sequence).** Positions agree within 1e-12 ×
  `modelSpan`, the largest extent along any axis, which is 1 here
  ([`V3.hs:72-73`](../src/Senbazuru/Geometry/V3.hs#L72-L73)); angles, edges, rings as
  vertex sets, orders and material coordinates agree exactly. F0 never moves, so `Flap`'s stationary correction is the identity
  ([`Flap.hs:346-348`](../src/Senbazuru/Origami/Flap.hs#L346-L348)) and the two folds
  should agree exactly [reasoned]. The Python refold is within 1.2e-16 of the
  fixture's last state [py].
- **Cost.** About 7 folds per checked step, counted in the code, not timed
  ([gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md)
  "From reading the code (counts, not timings)", finding 6).

### 5.8 The move record

The record this move produces (**SKETCH** values):

| Field | Value |
| --- | --- |
| `recordStep`, `recordMoveIndex`, `recordSpan` | step 2, `quarter` (steps count from 1 in source order); its only move; line 10, columns 3–40 |
| `recordLabel`, `recordPath` | "Fold the top half down in front, onto the bottom."; `[quarter]` |
| `recordKind`, `recordEvidence` | fold on existing creases; `SweptHinge` with its `CheckedFlap`, meaning the whole turn was checked ([route evidence](glossary-additions.md#assurance)) |
| `recordBefore`, `recordAfter` | states 1 and 2, unpresented, both with the fixture's ids |
| `recordPresentation`, `recordPlacement` | (identity, identity) each: no turn-over, no re-anchor |
| `recordHinge` | material (½,½)–(1,½) with `[9]`; (½,½)–(0,½) with `[11]` |
| `recordMoving` | the seed (1/4, 3/4), with `[F1, F2]` |
| `recordStationary` | F0, from `flapStationaryFace` ([05](05-prd-library-additions.md#l4-flapstationaryface-flapposeat-and-routepose), R-05-14), with a material point in it |
| `recordNewCreases`, `recordMacros` | `[]`; `[]` |
| `recordAngles` | edges 8–11 go from −180, 0, −180, 0 to −180, 180, −180, −180 |
| `recordStacking` | `Nothing`: the orders came from the checked endpoint, not from a stacking choice |
| `recordAnchor` | (3/4, 1/4) before and after |
| `recordResolved` | edge north: edges 4, 5 at y = 1. Edge south: edges 0, 1 at y = 0. Line y = ½. Valley stays valley. Flap F1, F2 |
| `recordCost` | fold count and sweep intervals (**UNVERIFIED**) |

**The seed.** For `L1 to L2` a record keeps the vertex mean (the average of the
corner coordinates) of the face beside L1's longest current material segment, ties
to the lowest, then the leftmost
([D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot),
[C68](decisions.md#changes-since-draft-v2)). Edge north's segments, edges 4 and 5,
are both ½ long; edge 5, from (½, 1) to (0, 1), is the leftmost, and its face is F2
`[8,6,3,7]`, whose vertex mean is (1/4, 3/4) [py]. A seed must fill a region slot,
strictly inside one face, because `unfold` resolves it again later. A point on edge
north itself, such as (3/4, 1) on edge 4, lies on a face's boundary and could not.

### 5.9 The written frame and the page note

`writeSequence` writes a metadata-only key frame and three `file_frames`, states 0,
1 and 2: the sheet, after `half`, after `quarter`. This move's end state is state 2,
`file_frames[2]`. `--frame 3` selects it, because every verb counts the key frame
as frame 0 ([`Types.hs:209-210`](../src/Senbazuru/Fold/Types.hs#L209-L210),
[D24](decisions.md#d24-states-figures-and-their-numbers)):

| Key | Value | Rule |
| --- | --- | --- |
| `vertices_coords` | (1,0) ×4, (½,0), (1,½), (½,0), (1,½), (½,½); z = 0 | raw positions under `displayAfter` (the identity), written as computed: up to 1.2e-16 off, because sin π is 1.2e-16 in floating point [py] |
| `edges_foldAngle` | 0 ×8, −180, 180, −180, −180 | always explicit |
| `edges_assignment` | `B` ×8, `M V M M` | [state rule](glossary-additions.md#the-fold-format); same as the fixture |
| `faces_vertices` | `[8,4,1,5] [8,5,2,6] [8,6,3,7] [8,7,0,4]` | material winding; signed areas in written x, y are +0.25, −0.25, +0.25, −0.25 [py], so F1 and F3 show their backs and F2, on top, its front |
| `frame_classes` | `["foldedForm"]` | nonzero angles |
| `frame_title` | "Folded into quarters." | the `closing` caption |
| `senbazuru:material_coords` | `[[0,0],[1,0],[1,1],[0,1],[0.5,0],[1,0.5],[0.5,1],[0,0.5],[0.5,0.5]]` | after the last transform, shaped as at [`Surface.hs:252`](../src/Senbazuru/Origami/Surface.hs#L252) |
| `senbazuru:assurance` | `quarter`'s `SweptHinge` evidence | the step that produced this state |

The earlier frames' written assignments and titles are
[02 §11](02-language-semantics.md#11-written-frames)'s table. They differ from the
fixture, which writes `M V M M` in every frame, including on creases still at angle
0 [jq]; hence #60's comparison by the state rule and its new golden.

**The page note** sits on the second figure, which draws state 1: this move's
caption, which is state 1's `frame_title`, and one valley arrow from this record. It
reads as a valley because flat frames default to a top-down view from the reader's
side ([`CreasePattern.hs:521-524`](../src/Senbazuru/Render/CreasePattern.hs#L521-L524)).
`Render.Sequence.stepNotes` reads the same three frames from `writtenStates`
(§1.3), and [06](06-prd-step-diagrams.md#2-from-a-run-to-notes) draws this note's
arrow as `GivenArrows` (R-06-16): one arrow per connected moving group, from
`motionsBetween` over the record's before surface under `displayBefore` and its
after surface under `displayAfter`, with the record's kind
([D7](decisions.md#d7-a-typed-step-note-reaches-the-page)). There is no
presentation mark and no crease to come. Both frames share vertex ids and edges, so
`motionsBetween` applies: vertices 2, 3 and 6 move [jq], in the connected faces F1
and F2, making one motion and one arrow. The third figure carries the closing
caption and no arrow.

### 5.10 Commands behind the numbers

Run from the repository root at `568dcb6`.

**[jq]** fixture summary:

```bash
jq -c '{faces: .faces_vertices, edges: .edges_vertices, assignments: [.edges_assignment, .file_frames[].edges_assignment], angles_8_11: [.edges_foldAngle, .file_frames[].edges_foldAngle | .[8:12]], classes: [.frame_classes, .file_frames[].frame_classes], titles: [.frame_title, .file_frames[].frame_title], file_frames: (.file_frames | length), coords: [.vertices_coords, .file_frames[].vertices_coords], moved: ([.vertices_coords, .file_frames[].vertices_coords] as [$a, $b, $c] | [[range(0; 9) | select($a[.] != $b[.])], [range(0; 9) | select($b[.] != $c[.])]])}' examples/quarter-fold-steps.fold
```

It prints, among the rest, `"angles_8_11":[[0,0,0,0],[-180,0,-180,0],[-180,180,-180,-180]]`,
`"file_frames":2` and `"moved":[[0,3,7],[2,3,6]]`.

**[py]** span of the move:

```bash
python3 -c 'l="  fold in front edge north to edge south"; s=len(l)-len(l.lstrip())+1; print(s, s+len(l.strip())-1)'
```

It prints `3 40`.

**[py]** the recorded seed (§5.8), in exact fractions:

```bash
python3 - <<'EOF'
import json
from fractions import Fraction as F
d = json.load(open("examples/quarter-fold-steps.fold"))
V = [(F(x).limit_denominator(), F(y).limit_denominator()) for x, y in d["vertices_coords"]]
E = d["edges_vertices"]; FACES = d["faces_vertices"]
north = [i for i, (a, b) in enumerate(E) if V[a][1] == 1 and V[b][1] == 1]
L = lambda i: abs(V[E[i][0]][0] - V[E[i][1]][0])
print("edges with material y = 1", north, "lengths", [str(L(i)) for i in north])
left = min(north, key=lambda i: (-L(i), min(V[E[i][0]][1], V[E[i][1]][1]), min(V[E[i][0]][0], V[E[i][1]][0])))
f = [f for f, r in enumerate(FACES) if E[left][0] in r and E[left][1] in r][0]
print("leftmost", left, "face", f, FACES[f], "vertex mean", tuple(str(sum(V[v][k] for v in FACES[f]) / 4) for k in (0, 1)))
EOF
```

It prints `edges with material y = 1 [4, 5] lengths ['1/2', '1/2']` and
`leftmost 5 face 2 [8, 6, 3, 7] vertex mean ('1/4', '3/4')`.

**[py]** the refold. This re-implements `Folding`'s spanning walk
([`Folding.hs:577-653`](../src/Senbazuru/Origami/Folding.hs#L577-L653)), with
rotations as in [`Rigid.hs:95-129`](../src/Senbazuru/Geometry/Rigid.hs#L95-L129),
and `Flap`'s sign rule. Run it as `python3 - <<'EOF' … EOF`:

<details>
<summary>Script</summary>

```python
# Re-implementation of Origami.Folding's walk (Folding.hs:577-653) and
# Flap's per-segment sign (Flap.hs:193-216) on examples/quarter-fold-steps.fold.
import json, math
d = json.load(open("examples/quarter-fold-steps.fold"))
MAT = [(float(x), float(y), 0.0) for x, y in d["vertices_coords"]]
E = [tuple(e) for e in d["edges_vertices"]]
FACES = d["faces_vertices"]
key = lambda a, b: (min(a, b), max(a, b))
EID = {key(*e): i for i, e in enumerate(E)}
sub = lambda p, q: tuple(a - b for a, b in zip(p, q))
dot = lambda p, q: sum(a * b for a, b in zip(p, q))
cross = lambda p, q: (p[1]*q[2]-p[2]*q[1], p[2]*q[0]-p[0]*q[2], p[0]*q[1]-p[1]*q[0])
norm = lambda p: math.sqrt(dot(p, p))
ring = lambda f: list(zip(FACES[f], FACES[f][1:] + FACES[f][:1]))
NB = {}
for f in range(len(FACES)):
    for a, b in ring(f): NB.setdefault(key(a, b), []).append(f)
def rotation(p, axis, th):                      # Rigid.hs:114-129
    x, y, z = (a / norm(axis) for a in axis); c, s = math.cos(th), math.sin(th); t = 1 - c
    R = [(t*x*x+c, t*x*y-s*z, t*x*z+s*y), (t*x*y+s*z, t*y*y+c, t*y*z-s*x), (t*x*z-s*y, t*y*z+s*x, t*z*z+c)]
    return (R, sub(p, tuple(dot(r, p) for r in R)))
def after(a, b):                                # a `after` b: apply b first
    (Ra, ta), (Rb, tb) = a, b
    cols = [tuple(Rb[k][j] for k in range(3)) for j in range(3)]
    return ([tuple(dot(Ra[i], cols[j]) for j in range(3)) for i in range(3)], tuple(dot(Ra[i], tb) + ta[i] for i in range(3)))
apply = lambda m, p: tuple(dot(m[0][i], p) + m[1][i] for i in range(3))
I = ([(1, 0, 0), (0, 1, 0), (0, 0, 1)], (0, 0, 0))
def fold(deg):                                  # deg: {edge id: FOLD angle}; faces[0] is the root
    placed, frontier = {0: I}, [0]
    while frontier:
        reached = []
        for f in frontier:
            for a, b in ring(f):
                for g in NB[key(a, b)]:
                    if g != f and g not in placed:
                        th = -deg.get(EID[key(a, b)], 0.0) * math.pi / 180
                        reached.append((g, after(placed[f], rotation(MAT[a], sub(MAT[b], MAT[a]), th))))
        new = {}
        for g, m in reached: new.setdefault(g, m)
        placed.update(new); frontier = sorted(new)
    pos, spread = [], 0.0
    for v in range(len(MAT)):
        ps = [apply(placed[f], MAT[v]) for f in range(len(FACES)) if v in FACES[f]]
        spread = max([spread] + [norm(sub(p, ps[0])) for p in ps]); pos.append(ps[0])
    return pos, placed, spread
area2 = lambda f, P: sum(P[a][0]*P[b][1] - P[b][0]*P[a][1] for a, b in ring(f)) / 2
cz = lambda f, P: sum(P[v][2] for v in FACES[f]) / len(FACES[f])
fx = lambda i: [(x, y, 0.0) for x, y in d["file_frames"][i]["vertices_coords"]]
maxdiff = lambda P, Q: max(norm(sub(p, q)) for p, q in zip(P, Q))
tol = 1e-9 * math.hypot(1, 1)                   # Faces.hs:248-249, diagonal of the sheet box
print("material ring areas", [area2(f, MAT) for f in range(4)])
A = (0.75, 0.25)
print("anchor in faces", [f for f in range(4) if min(MAT[v][0] for v in FACES[f]) < A[0] < max(MAT[v][0] for v in FACES[f]) and min(MAT[v][1] for v in FACES[f]) < A[1] < max(MAT[v][1] for v in FACES[f])],
      "distance to F0 boundary", min(A[0]-0.5, 1-A[0], A[1], 0.5-A[1]), "nearest vertex", min(math.hypot(A[0]-x, A[1]-y) for x, y, _ in MAT))
S1 = {8: -180, 10: -180}; S2 = {8: -180, 9: 180, 10: -180, 11: -180}
P1, pl1, t1 = fold(S1); P2, pl2, t2 = fold(S2)
print("state1 vs file frame 1", maxdiff(P1, fx(0)), "tear", t1, "max|z|", max(abs(p[2]) for p in P1))
print("state2 vs file frame 2", maxdiff(P2, fx(1)), "tear", t2, "max|z|", max(abs(p[2]) for p in P2))
print("state2 positions", [tuple(round(c, 12) + 0.0 for c in p) for p in P2])
Pm, _, tm = fold({8: -179, 10: -179}); print("step1 at -179: face centroid z", [round(cz(f, Pm), 4) for f in range(4)])
Ph, _, th = fold({8: -180, 9: 90, 10: -180, 11: -90}); print("step2 at progress 1/2: face centroid z", [round(cz(f, Ph), 4) for f in range(4)], "tear", th)
north = [i for i, (a, b) in enumerate(E) if MAT[a][1] == 1 and MAT[b][1] == 1]
south = [i for i, (a, b) in enumerate(E) if MAT[a][1] == 0 and MAT[b][1] == 0]
for name, es in (("edge north", north), ("edge south", south)):
    segs = [(P1[E[i][0]], P1[E[i][1]]) for i in es]
    print(name, "edges", es, "material", [(MAT[E[i][0]][:2], MAT[E[i][1]][:2]) for i in es], "now", [(p[:2], q[:2]) for p, q in segs],
          "y spread", max(abs(p[1] - segs[0][0][1]) for s in segs for p in s))
on = [i for i, (a, b) in enumerate(E) if all(abs(P1[v][1] - 0.5) <= tol and abs(P1[v][2]) <= tol for v in (a, b))]
print("tol", tol, "edges lying on y = 1/2 in state 1", on, [(MAT[E[i][0]][:2], MAT[E[i][1]][:2]) for i in on])
def component(seed, removed):
    links = [(fs[0], fs[1]) for k, fs in NB.items() if len(fs) == 2 and EID[k] not in removed]
    seen, todo = set(), [seed]
    while todo:
        f = todo.pop()
        if f not in seen: seen.add(f); todo += [b for a, b in links if a == f] + [a for a, b in links if b == f]
    return sorted(seen)
normal = lambda f, P: tuple(sum(c) for c in zip(*[cross(P[a], P[b]) for a, b in ring(f)]))
print("state1 face normals", [normal(f, P1) for f in range(4)])
def segment_signs(eids, side, P):              # Flap.hs:193-216 with expected = P
    moving = component(side, eids); first = eids[0]
    fixed = [g for g in NB[key(*E[first])] if g != side][0]
    frm, to = [(a, b) for a, b in ring(fixed) if key(a, b) == key(*E[first])][0]
    axis = tuple(c / norm(sub(P[to], P[frm])) for c in sub(P[to], P[frm]))
    out = []
    for e in eids:
        l, r = NB[key(*E[e])]; st = r if l in moving else l
        u, v = [(a, b) for a, b in ring(st) if key(a, b) == key(*E[e])][0]
        res = max(norm(cross(axis, sub(P[w], P[frm]))) for w in (u, v))
        out.append((e, "stationary F%d" % st, "ring %d->%d" % (u, v), "dot %+.3f" % dot(axis, sub(P[v], P[u])), "onLine residual %.1e" % res))
    return moving, fixed, (frm, to), axis, out
print("step 1 [8,10] side F3:", segment_signs([8, 10], 3, MAT))
print("step 2 [9,11] side F1:", segment_signs([9, 11], 1, P1))
moving, fixed, (frm, _), axis, _ = segment_signs([9, 11], 1, P1)
sweep = rotation(P1[frm], axis, -180 * 0.5 * math.pi / 180)      # Flap.hs:222, progress 1/2
mv = sorted({v for f in moving for v in FACES[f]})
print("sweep vs refold at 1/2, max distance over moving vertices", max(norm(sub(apply(sweep, P1[v]), Ph[v])) for v in mv), "v2 at", tuple(round(c, 12) + 0.0 for c in Ph[2]))
rule = lambda a, x, t=1e-10: a if a in "BCJ" else ("M" if x < -t else "V" if x > t else "F")
asg = d["edges_assignment"]
for name, S, P in (("state0", {}, MAT), ("state1", S1, P1), ("state2", S2, P2)):
    print(name, "state rule", "".join(rule(asg[i], S.get(i, 0)) for i in range(12)), "written ring areas", [round(area2(f, P), 3) + 0.0 for f in range(4)])
print("modelSpan(material)", max(max(p[i] for p in MAT) - min(p[i] for p in MAT) for i in range(3)))
```

</details>

Output, abridged:

```text
material ring areas [0.25, 0.25, 0.25, 0.25]
anchor in faces [0] distance to F0 boundary 0.25 nearest vertex 0.3535533905932738
state1 vs file frame 1 6.123233995736766e-17 tear 0.0 max|z| 6.123233995736766e-17
state2 vs file frame 2 1.2246467991473532e-16 tear 1.2246467991473532e-16 max|z| 1.2246467991473532e-16
step1 at -179: face centroid z [0.0, 0.0, -0.0044, -0.0044]
step2 at progress 1/2: face centroid z [0.0, 0.25, 0.25, -0.0] tear 6.123233995736766e-17
tol 1.4142135623730953e-09 edges lying on y = 1/2 in state 1 [9, 11] ...
step 2 [9,11] side F1: ([1, 2], 0, (5, 8), (-1.0, 0.0, 0.0), [(9, 'stationary F0', 'ring 5->8', 'dot +0.500', ...), (11, 'stationary F3', 'ring 8->7', 'dot -0.500', 'onLine residual 6.1e-17')])
sweep vs refold at 1/2, max distance over moving vertices 0.0 v2 at (1.0, 0.5, 0.5)
state2 state rule BBBBBBBBMVMM written ring areas [0.25, -0.25, 0.25, -0.25]
```

## Research links

- [A1](research/A1-library-fold-solver.md) "(c) Identifiers that do not survive, and the ones that do"
- [A2](research/A2-study-recipes-as-proto-dsl.md) "(b) The shared handoff policy: invariants an interpreter must enforce"
- [C](research/C-renderers-cli-formats.md) section (d), "A new input format becomes a Frame and stops there"
- [F](research/F-haskell-edsl-techniques.md) "B. Embedding styles"
- [gap-study-consumption-contract](research/gap-study-consumption-contract.md) "(a) The per-step record, and who imports what"
- [gap-layer-selective-folds](research/gap-layer-selective-folds.md) "(c) Smallest library addition, and what the interpreter does itself"
- [gap-assignment-at-rest-convention](research/gap-assignment-at-rest-convention.md) "Recommendation"
- [gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md) "From reading the code (counts, not timings)"
