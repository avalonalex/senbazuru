# Decisions: connecting the fold solver and the material study

**Status.** The current decision record, version 3. Dated 2026-09-15, against
commit `568dcb6`, before anything was built; M1 and M2 have been built since, and the
changes table (C75 onward) and §5's notes say where they were built otherwise. Every PRD file in this directory is
written against this record, and where a file and this record disagree, this
record wins and the file is to be corrected.

**Amended** 2026-09-23, after M1 and #344 were implemented: the sense of a
hinge turn is where the moving paper goes ([D5](#d5-presentation-and-the-readers-side),
owner decision 13), from [E3](research/E3-formal-fold-semantics.md), which
also adds [§10](#10-corrections) rows 33–38. Also that day: a pre-crease is one
move, with one record ([D12](#d12-the-text-syntax), owner decision 14). Refined
2026-09-24: a pre-crease marks the paper, and its crease has no direction until
a later move folds it.

**How it relates to the drafts.**

- [decisions-draft-v1.md](research/spine-reviews/decisions-draft-v1.md) was the
  first design record.
- Five reviews checked it: code feasibility
  ([L1](research/spine-reviews/review-L1-code-feasibility.md)), fixture truth
  ([L2](research/spine-reviews/review-L2-fixture-truth.md)), author ergonomics
  ([L3](research/spine-reviews/review-L3-author-ergonomics.md)), conventions
  ([L4](research/spine-reviews/review-L4-conventions-consistency.md)), and
  material and rendering honesty
  ([L5](research/spine-reviews/review-L5-material-rendering-honesty.md)).
- [decisions-draft-v2.md](research/spine-reviews/decisions-draft-v2.md) adopted
  their verified objections. The PRD files call v2 "the spine" and cite it as
  "Dn" and "spine §n".
- While writing and re-checking the PRDs, their authors found errors and gaps in
  v2 and marked them as notes. This version decides every one of them.
  [Changes since draft v2](#changes-since-draft-v2) lists each change with the
  evidence checked, and [Proposals not adopted](#proposals-not-adopted) lists what
  was turned down.

**How to cite.** PRD files cite a decision as `[D5](decisions.md#d5-presentation-and-the-readers-side)`,
a section as `[§8](decisions.md#8-milestones)`, and a change as `[C12](decisions.md#changes-since-draft-v2)`.
"Spine", "spine Dn" and "spine §n" in the PRD files are to be replaced by these
links; the numbering D1–D22 is unchanged, and D23 and D24 are new.

| D | Anchor |
| --- | --- |
| D1–D6 | [D1](#d1-one-first-order-syntax-tree-built-by-name-only-builders) · [D2](#d2-references-named-on-the-sheet-and-resolved-by-slot) · [D3](#d3-the-runner-owns-the-state-its-start-and-the-handoffs) · [D4](#d4-written-frames-follow-the-state-rule) · [D5](#d5-presentation-and-the-readers-side) · [D6](#d6-crease-graphs-grow-between-frames) |
| D7–D12 | [D7](#d7-a-typed-step-note-reaches-the-page) · [D8](#d8-folding-some-layers) · [D9](#d9-macro-moves-as-named-angle-relations) · [D10](#d10-assurance-as-evidence-values) · [D11](#d11-stacking-choices-are-relations) · [D12](#d12-the-text-syntax) |
| D13–D18 | [D13](#d13-the-run-verb-and-io) · [D14](#d14-material-consumption) · [D15](#d15-graduation-from-study-to-library) · [D16](#d16-testing-and-acceptance) · [D17](#d17-third-party-and-external-tools) · [D18](#d18-non-goals) |
| D19–D24 | [D19](#d19-realistic-rendering) · [D20](#d20-errors) · [D21](#d21-repeat-checkpoint-not-modelled-expect-refused) · [D22](#d22-figures-holding-several-moves) · [D23](#d23-the-sequence-modules-and-where-run-lives) · [D24](#d24-states-figures-and-their-numbers) |

**Reading it.** The reader knows intermediate Haskell and has never folded paper.
Each term gets one clause here and a link to
[glossary-additions.md](glossary-additions.md) or
[the glossary](../docs/glossary.md). A tag gives the evidence as of the text it
supports: `568dcb6` for the record as written on 2026-09-15, and the PR or issue it
names for text added since, such as the changes rows from C75 on, which cite code
by module or function. §10 also uses
[10 §7](10-roadmap-risks-questions.md#7-corrections-as-proposed-follow-up-issues)'s
tags [web], [bin], [ls] and [docs]. Evidence tags:

| Tag | Meaning |
| --- | --- |
| [code] | code read, cited as `path:line` or by module or function |
| [jq], [py] | a fixture measurement by a command run for this record; the commands are in [the appendix](#appendix-commands-behind-the-numbers) |
| [ran] | a command run for this record, named or described in its row or in the appendix |
| [measured] | timed runs of a compiled build, with the run count; the commands are in the appendix |
| [prd] | a measurement made by a PRD file, whose section holds the command |
| [research] | a research note, by file and heading |
| [reasoned] | worked out from cited code, not run |

**SKETCH** marks a planned name, type or message. **UNVERIFIED** marks a claim no
command has checked, with what would check it.

The request this record answers:

1. **Library:** an embedded Haskell language to define fold sequences and steps.
2. **CLI:** parse the same language from a file.
3. **Material:** the material study, when mature, takes what (1) and (2) define
   and produces realistic renderings, as glTF and as an SVG line drawing.

---

## 1. The two halves today, and what connecting them means

**Concrete first.** The only code in the repository that performs folds one after
another is the study's hand-written *recipes*. The blintz recipe (a blintz folds
a square's four corners to its centre) is five tuples of a caption, an edge id, a
face id and an angle change
([`BlintzSequence.hs:50-56`](../study/fold-material/BlintzSequence.hs#L50-L56))
[code]. Its ids belong to one cut and traced pattern, and adding any crease
renumbers them ([A1](research/A1-library-fold-solver.md) "(c) Identifiers that do
not survive, and the ones that do").

- **The fold solver, in the library.** `Fold.Creasing`, `Fold.Crossings`,
  `Origami.Folding` (fold angles on a cut pattern become a `Folded`),
  `Origami.Flap` with `Origami.HingeSweep` (one checked turn about a hinge),
  `Origami.ThroughLayers`, `Origami.Stacking`, `Origami.Surface` and the
  renderers. It folds, checks and draws states, and checks one hinge turn. It
  cannot be told a sequence.
- **Sequences in the repository today.** The study writes them in four forms
  ([A2](research/A2-study-recipes-as-proto-dsl.md) "Summary"): angle tables with
  one angle per edge *by position* (`cases.json`, read by `StudyCase`); flap
  recipes naming ids of a cut pattern (`BlintzSequence`, `HelmetSequence`,
  `CraneWing`); certified coupled recipes, where a stage and a progress fraction
  go through a formula to every angle (`CheckedPetal`, `CheckedBird`); and flat
  checkpoints giving material crease segments per milestone (the frog guide in
  `BasicBases`). Two multi-frame FOLD files exist:
  `examples/bird-base-sequence.fold`, generated from the manifest, and
  `examples/quarter-fold-steps.fold`, written by hand [jq]. v2 said every
  sequence is a recipe naming raw ids; that was true of one form in four
  ([C2](#changes-since-draft-v2)).
- **The material study.** `study/fold-material/` builds an executable that bends
  folded paper as a thin elastic sheet: a static, zero-thickness, held-boundary
  solver (Gauss–Newton on edge lengths, crease and panel angular springs, penalty
  contact, a sparse factorisation), fixture experiments (a crane wing bending,
  closed-crease controls) and exact certificates for coupled routes. Its only path
  from a rigid fold to bent paper, `CraneSpread`, consumes one hand-built move
  ([gap-study-consumption-contract](research/gap-study-consumption-contract.md)
  "(a) What the study takes from a move today").
- **Shared today:** `Origami.Surface`, `Origami.Contact`, `Origami.HingeSweep`.

**Connecting them takes three new pieces, of which two are contracts**
([C1](#changes-since-draft-v2)):

1. **The `Sequence` value**, first-order data that both front ends produce. It is
   a shared value, not a boundary between separately owned code, so it is not
   numbered as a contract.
2. **Contract 1, the move record.** The library's run returns one `MoveRecord` per
   move, with its evidence ([D14](#d14-material-consumption), [D23](#d23-the-sequence-modules-and-where-run-lives)).
3. **Contract 2, the settle input.** The material consumer takes records, never
   files, resolves an author's holds and grips against one record, and hands the
   solver a resolved `SettleInput` and a `Surface V2`. It lives in the study until
   graduation.

v2 said "three contracts" in its §1 and labelled two in its picture; the picture
was right.

## 2. Shape

```
 Haskell author                          text author (.foldseq source)
  Sequence.Build (State, names only)     Fold.Load.readSequenceText -> Text
          \                               Sequence.Parse (megaparsec, pure)
           v                                   v
          Sequence.Syntax : Sequence  (first-order, spans)   <-> Sequence.Pretty
                         |
          Sequence.Check (names, kinds, arity, units; no geometry)
          Sequence.Elaborate (let; keeps provenance)
                         |
          Sequence.Run  (RunSettings, sheets) over Fold.* / Origami.*
                         |
          Run = records + states   (Sequence.Record)          <- contract 1
             |              |               |                     |
   Sequence.Write     Render.Sequence   Render.Gltf        Sequence.Material (study until M8)
   (FoldFile around   (StepNote per     (surfaces;           settleStep :: SettleSpec -> MoveRecord
    writtenStates)     state, then       new modes, M7)          -> Either SettleStepError Settled
                       stepPageWith)                                 |  SettleInput      <- contract 2
                                                                     v
                                                              Material.Settle.settle (library from M8)
```

**SKETCH.** Arrows are data flow.

**Module layers.** A module imports its own family and what its row lists, and
nothing else; siblings in a row never import each other; within a family the
only rule is no cycles ([review L4](research/spine-reviews/review-L4-conventions-consistency.md) L4-2).

| Row | Modules | May import |
| --- | --- | --- |
| 1 | `Geometry.*`, `Explain`, `Fold.Types` | nothing outside itself; `Geometry` does not import `Explain` |
| 2 | `Numeric.*` (M8) | `Geometry.*`, `Explain`; knows no paper |
| 3 | siblings `Import.*` and `Fold.{Query,Faces,Crossings,Creasing}`; `Fold.Load` over `Import.*`, the only I/O | row 1 |
| 4 | siblings `Diagram.*` and `Origami.*` | `Diagram.*`: rows 1–2 and `Fold.Types` for `Assignment`, the existing named exception ([`Style.hs:91`](../src/Senbazuru/Diagram/Style.hs#L91)); `Origami.*`: rows 1 and 3 |
| 5 | `Material.*` (M8) | rows 1–3, `Origami.*`; takes a resolved input and a `Surface V2`, never a move |
| 6 | `Sequence.*` | rows 1 and 3, `Origami.*`; only `Sequence.Material` imports `Material.*` |
| 7 | `Render.*` | rows 1–5, and from `Sequence.*` only `Sequence.Record` and `Sequence.Error` |
| 8 | `app/` | the library |

Row 7 is the one change from v2: a renderer that draws a run needs the run's
states and their refusal type, and both now live in modules that import no
parser, checker or runner ([D23](#d23-the-sequence-modules-and-where-run-lives)).
`Numeric` and `Material` appear only at graduation (M8).

## 3. Recorded text this design changes

Nothing under `PRDs/` edits these files. [01 §4](01-architecture.md#4-recorded-text-this-design-changes)
writes out every replacement; [10 §3](10-roadmap-risks-questions.md#3-recorded-text-changes-by-milestone)
schedules them. Rows 15–18 are new ([C51](#changes-since-draft-v2), [C56](#changes-since-draft-v2), [C66](#changes-since-draft-v2), [C74](#changes-since-draft-v2)).
A row is marked once any of its text lands: on `main`, or on the issue it
changes. Its Lands cell then says what landed, with which issue, and the Pacific
day the PR merged or the comment was posted; a row that landed in part also says
what has not. A PR that marks its own row writes that day before it merges, so
the date is checked after the merge: #531 marked row 11 one evening and merged
the next morning. A row with no mark has not landed, and may say what stands in
its way.

| # | Where | Change (summary) | Lands |
| --- | --- | --- | --- |
| 1 | `docs/architecture.md:81-103` | `Fold.Creasing` is frame in, frame out; a sequence's moves are not: `Sequence.Run` returns records, and what reaches the pipeline as a file is the written `FoldFile` | M0: landed with #278, 2026-09-19, without naming the modules not yet built |
| 2 | `AGENTS.md:193-196`, `docs/architecture.md:197-202` | stated exception: a sequence source is a program, not an input format | M0, no later than M1's `Sequence.Parse` PR: landed with #278, 2026-09-19, before the parser's PR merged that evening; `AGENTS.md` holds a short form that points at `docs/architecture.md`'s "Layering rules" |
| 3 | [#60](https://github.com/avalonalex/senbazuru/issues/60) | `runSequence` returning a run of records; "one interpreter" superseded; done-when split into folding equivalence and authoring ([D16](#d16-testing-and-acceptance)) | M0; not landed, and 01 §4.3's text is stale: it gives the planned `runSequence` (C96) and cites `docs/notes/sequences.md`, which was never written |
| 4 | [#95](https://github.com/avalonalex/senbazuru/issues/95) | turn over is presentation about a model-intrinsic axis ([D5](#d5-presentation-and-the-readers-side)) | M0: landed in part, as a comment on #95, 2026-10-06, the body left as it was; 01 §4.4's top-bottom map and some of its done-when have not landed, and #95 closed with #533 on 2026-10-11, so they cannot land there |
| 5 | [#97](https://github.com/avalonalex/senbazuru/issues/97) | note named `docs/notes/sequences.md`; "scheme" retired; closes at M2 | M0: landed in part, as a comment on #97, 2026-10-06: the decision, and that #97 closes at M2, which it did with #501, 2026-10-07. `docs/notes/sequences.md`, which rows 3, 9 and 16 cite, was never written, so "scheme" is not retired, and with #97 closed the note has no issue |
| 6 | [#111](https://github.com/avalonalex/senbazuru/issues/111) | add the writer's at-rest rule and the two `1e-10` thresholds ([`Surface.hs:278`](../src/Senbazuru/Origami/Surface.hs#L278), [`StudyCase.hs:208`](../study/fold-material/StudyCase.hs#L208)) that should read `Fold.Query.atRest` | M0: landed as a comment on #111, 2026-10-07, the body's table left as it was |
| 7 | #36, #94, #104, #114, #56, #64 | premise and done-when corrections ([§10](#10-corrections)); #104's done-when names `--view front` ([D19](#d19-realistic-rendering)) | M0 |
| 8 | `AGENTS.md` "Third-party material" | running an external program is not vendoring ([D17](#d17-third-party-and-external-tools)) | M0: landed with #550, 2026-10-12, in 01 §4.8's words, and scoped with #552, 2026-10-12 ([C100](#changes-since-draft-v2)) |
| 9 | `docs/notes/no-sequence-solver.md` | the vocabulary is formal now; searching it stays a non-goal | M0, with [#96](https://github.com/avalonalex/senbazuru/issues/96); not landed, and 01 §4.9's text cites `docs/notes/sequences.md`, which was never written |
| 10 | `docs/glossary.md` | move glossary-additions rows in; fix rest angle (`:19`, `:86`) and flat-folded (`:21`) | M0, first PR: landed in part. Since #278, 2026-09-19, rows move in one term at a time with the code that uses it (C97), and many built terms have not moved, among them route evidence, seed and join check; the fixes to rest angle and flat-folded have not landed |
| 11 | `AGENTS.md:173-177` "Two unit systems" | sheet lengths and physical lengths, each converted in one named place | with M2: landed with #505, 2026-10-11, the one place for sheet lengths being `Sequence.SheetLengths` (C88); the place for physical lengths is named when the `material` block brings it, at M6 |
| 12 | `AGENTS.md:229-233`, the `--layer-budget` list | add `runSequence` at M2 and `stepPageWith` at M3 | M2, M3: the M2 half landed with #501, 2026-10-07; `stepPageWith` joins the list at M3 |
| 13 | `src/Senbazuru/Origami/Step.hs:30-34` | a whole-model rigid motion is a presentation change, tested as "some vertex moves" ([D5](#d5-presentation-and-the-readers-side)) | the M2 PR classifying presentation: landed with 05 L3 (#95), 2026-10-09 |
| 14 | `docs/architecture.md:288-297`; `BlintzSequence`, `HelmetSequence` headers | recipes replaced by sequences | the recipe deletion PRs: the blintz's landed with #503, 2026-10-10 (the architecture paragraph rewritten, the recipe and its header gone; C87); the helmet's with #534, 2026-10-11, the same way (C92) |
| 15 | `AGENTS.md:390-391` "all three CI checks" | name the slow job as a required check (owner decision 12, decided 2026-10-12) | the M4 PR adding the slow job, then the owner listing that job in `main`'s branch protection, which no pull request can change |
| 16 | `docs/roadmap.md:271-276`, `:1004-1009` | the recorded order (#93, #96, #97, "only then" #95, #94, #36) replaced by the milestones | M0; not landed, and 01 §4.16's text is stale: it cites `docs/notes/sequences.md`, which was never written, and was written before M2 closed #95 and #97 |
| 17 | `test/Senbazuru/Origami/ThroughLayersSpec.hs:271-275`, `docs/usage.md:1652-1658` | the `LineStopsOnTheModel` sentence names the end by its point ([D20](#d20-errors)) | the follow-up PR, before M4; not landed, and its issue (10 §7.2 item 31) was never filed |
| 18 | `README.md:213` roadmap item 2, `docs/roadmap.md` item 2 | the vocabulary exists | the PR closing #60 (M4) |

Row 14's range was `288-299` in v2. `grep -n` puts the blintz sentence at
`docs/architecture.md:288` and the end of the helmet sentence at `:297`, with
`HingeSweep`'s paragraph starting at `:298` [code], so `288-297` is right.

---

## 4. Decisions

Each decision gives **what**, **why**, **rejected** and **residue**. A PRD file
that departs from one must say so in a marked note and add a row to the changes
table in the next version of this record.

### D1. One first-order syntax tree built by name-only builders

- **What.** `Sequence.Syntax` is first-order: `Eq`, `Show`, no functions inside.
  A `Sequence` is a header and a list of located steps. A **step** is the
  instruction for one picture in a book, and holds one or more **moves**: "fold and
  unfold both diagonals" is one step of two moves. Its caption and arrows are drawn
  on the *figure* of the state it starts from, so a step is not a figure and the two
  are numbered differently ([D24](#d24-states-figures-and-their-numbers)). The Haskell builder is
  `newtype Build a = Build (State BuildState a)` over
  `Control.Monad.Trans.State.Strict` (the `transformers` package, no `mtl`), and a
  step's body has its **own** type, `newtype Moves a = Moves (State MoveState a)`
  ([C22](#changes-since-draft-v2)). Binds hand out `Ref`s holding **names**, never
  geometry. `sequenceOf :: Header -> Build () -> Sequence`. Checking,
  elaboration, running, printing, page projection and material consumption are
  ordinary functions over the value.
- **Why a separate body type.** With one builder type, `fold` typechecks outside
  any step and `step` typechecks inside another; neither fits a `Sequence`, whose
  steps hold located moves, so the builder would have to drop or reorder something
  silently ([03](03-prd-embedded-dsl.md#what-a-bind-returns-names-never-geometry)).
  Two types make both mistakes compile errors, and every example reads the same.
- **Why names.** Several consumers read one value
  ([F](research/F-haskell-edsl-techniques.md) "B. Embedding styles"); a file holds
  only first-order data (same note, finding 14); and a bind that returned a hinge
  length would make building need the sheet, fail for geometric reasons, and print
  only the branch taken ([03](03-prd-embedded-dsl.md#what-a-bind-returns-names-never-geometry)
  works this through: 0.7071 sheet lengths on a square, 0.5590 on a 1 × 1/2 sheet).
- **Name clashes are removed at the constructor, not at the import**
  ([C23](#changes-since-draft-v2)). `Fold.Types` already has constructors
  `Mountain`, `Valley` ([`Types.hs:302-305`](../src/Senbazuru/Fold/Types.hs#L302-L305))
  and `Above`, `Below` ([`:334-336`](../src/Senbazuru/Fold/Types.hs#L334-L336))
  [code]. `Sequence.Run` must import both `Fold.Types` and `Sequence.Syntax`, and
  GHC 9.6 does not pick a constructor by its type, so `Sense = Valley | Mountain`
  would force qualified names inside the library itself. So the syntax
  constructors are `Sense = ValleyFold | MountainFold` and
  `Relation = LayerAbove Point Point`, and `Sequence.Build` exports the lowercase
  builders `valley`, `mountain`, `inFront`, `behind` and `above`. Likewise
  `Origami.Visible` exports a type `Region`
  ([`Visible.hs:103`](../src/Senbazuru/Origami/Visible.hs#L103)) [code], so the
  settle vocabulary's type is `SettleRegion` ([D14](#d14-material-consumption)).
- **Rejected.** Free or operational monads; tagless final; a GADT-indexed tree; a
  shallow embedding ([F](research/F-haskell-edsl-techniques.md) "Rejected
  alternatives"); `Ref` indexed with `DataKinds`, which GHC2021 lacks; keeping the
  clashing constructor names and asking every importer to qualify
  ([03](03-prd-embedded-dsl.md#the-builder-vocabulary)'s note).
- **Supersedes** #60's `apply :: Move -> Frame` and its "one interpreter" reason,
  keeping its plain data type ([§3](#3-recorded-text-this-design-changes) row 3).
- **Residue.** `Ref :: Type -> Type` with empty index types `PointK`, `LineK`,
  `StepK`; the kind signature is not redundant, because GHC2021's `PolyKinds`
  would let a bare `Ref` accept `Ref Maybe`. No builder shares a Prelude name
  (`sequenceOf`, `repeatSteps`, `letLine`, `allLayers`) or is called `pattern`,
  which hlint reads as a keyword. Builders emit canonical values
  ([D12](#d12-the-text-syntax)); a value built with `move` and constructors may
  not be canonical and is compared through `canonical`.

### D2. References named on the sheet and resolved by slot

- **Material names use a sheet compass.** `corner south-west | south-east |
  north-east | north-west`, `edge south | east | north | west`, `centre`. North
  is +v on the unfolded sheet as the file draws it. These names never change as
  paper moves. `left`, `right`, `top`, `bottom`, `front` and `behind` are
  reserved for the view and refused where a material feature is expected, with
  the compass spelling in the message. Messages also say where a feature now
  appears as seen ("corner north-west, now at the reader's top-right").
- **Compass names need a square outline** (G11, [C21](#changes-since-draft-v2)).
  `corner X` is refused unless a boundary vertex lies at that corner of the
  sheet's bounding box within `Fold.Faces.tolerance`, and `edge S` unless boundary
  edges cover that side; `centre` and `(u, v)` are always defined. On
  `crane.fold` the corners are 5.8e-15 off, inside the 1.41e-9 tolerance
  ([07](07-prd-material-consumption.md#one-move-fed-by-hand)'s box check) [prd].
- **Numbers have four kinds.** *Sheet lengths*: with s the larger side of the
  unfolded sheet's bounding box and (xmin, ymin) its south-west corner,
  (u, v) = ((x − xmin)/s, (y − ymin)/s), one scale on both axes; on
  `bird-base.cp`, whose 26 segments span [−200, 200], s = 400 and `(29/50, 2/5)`
  is model (32, −40) ([02 §3](02-language-semantics.md#3-numbers)) [prd].
  *Model units* only inside `model [...]`. *Degrees*, always written with `°` or
  `deg`. *Pure ratios* in [0, 1]. Physical lengths only in `material { … }`, with
  unit suffixes.
- **Points** are `corner …`, `centre`, `(u, v)` (exact `Rational`),
  `midpoint of [P, Q]`, `midpoint of edge S` (new, [C13](#changes-since-draft-v2)),
  `fraction r along [P, Q]` (computed in material coordinates), `meet L1 L2`
  (current positions), `end of crease of NAME nearest P`, mark names and `let`
  names. `fraction r along edge S` is refused, because nothing says which end r
  counts from.
- **Lines** are O1 `[P, Q]`, O2 `P to Q`, O3 `L1 to L2`, O4
  `perpendicular to L through P`, O5 `P to L through Q`, O6
  `P to L1 and Q to L2`, O7 `P to L1 perpendicular to L2`, and `P to L` (the fold
  putting P on L with the fold line parallel to L); `edge S` when its current
  segments are collinear within `Fold.Faces.tolerance`; `crease [P, Q]` (the
  operation Lucero adds to the seven, his O3: along existing creases);
  `hinge of NAME` and `crease of NAME`, each while its segments are collinear
  (`HingeNotStraight`, owner decision 52); and the
  escape `model [(x1, y1), (x2, y2)]`, flat states only, recorded "not a
  landmark".
- **Resolution is decided by the slot a point fills, never by its spelling.**

  | Slot | Filled by | Accepted when |
  | --- | --- | --- |
  | Position | inputs of O1–O7 and `P to L`; both arguments of `P to Q`; `meet`; `model` | on paper, and every face whose closed polygon contains it places it at one point. Typed literals only (`(u, v)`, `model`) are refused as `NearMiss` when not within tolerance of a vertex but within `RunSettings.nearMissBand` of one (owner decision 2) |
  | Region with a hinge | a move's seed | strictly inside exactly one face, or a vertex whose pieces after cutting lie in one component |
  | Region without a hinge | `anchor`, `layers A above B`, `mark … in face containing S` | strictly inside exactly one face |
  | Vertex | `collapse at`, `rabbit-ear at`, `petal tip`, ends of `crease [P, Q]` and pose creases, `end of crease of` | within tolerance of exactly one vertex; never `Creasing.existingAt`'s first match ([`Creasing.hs:323-327`](../src/Senbazuru/Fold/Creasing.hs#L323-L327)) [code] |

  **The example that looks wrong.** `anchor centre` is accepted on
  `blintz-base.fold` although the fixture has no vertex at (1/2, 1/2): an anchor
  fills a region slot, and the centre lies strictly inside the traced central
  square [py]. `collapse at centre` on the same file is refused as `VertexMiss`,
  because a vertex slot needs a vertex and the nearest are 1/2 away
  ([02 §4.4](02-language-semantics.md#44-resolution-by-slot)).
- **A slot needing a material point, filled by a folded position** (G8), such as
  `anchor meet L1 L2`, resolves as `mark` does: the distinct material points there,
  refused when more than one.
- **Moving side** (decided by the move's text, never by the anchor). `P to Q`, O5,
  O6 and O7: the side containing P; O6 is refused if Q lies on the other side
  (G2). `L1 to L2`: the side containing L1's interior, refused if L1 straddles the
  line; for crossing lines the solution mapping segment onto segment is preferred,
  and `nearest` is needed only if two remain. `[P, Q]`, `crease [P, Q]`, O4,
  `edge S`, `hinge of`, `crease of` and `model`: the move names a seed with
  `moving P` (alias `flap containing P`), and a seedless one is refused listing
  a seed for each flap the fold can move, each one the fold runs from as printed
  ([C112](#changes-since-draft-v2); on paper of one layer that is both sides), named
  as an author would write it where it can be (owner decision 53).
- **The seed a record keeps** for `L1 to L2` is the vertex mean of the face beside
  L1's longest current material segment (ties lowest, then leftmost), a point
  that fills a region slot. For quarter-fold step 2, edge north's segments, edges
  4 and 5, are equally long; the leftmost is edge 5, beside face `[8,6,3,7]`, so
  the seed is (1/4, 3/4) [py]. [01 §5.8](01-architecture.md#58-the-move-record)'s
  "(3/4, 1)" lies on an edge and could not be re-resolved by `unfold`.
- **Which layers.** An alignment fold moves the flap containing its first
  argument; `moving P` names another seed; `all layers`; `top layer`;
  `top N layers` counted at each point along the line from the reader's side;
  `top flap`, the smallest N whose selection is not coupled. Viewer-relative
  selections resolve once against the accepted layer order and are pinned in the
  record as material seeds.
- **Constructions need a flat state** (every face in one plane). With paper in the
  air, only `crease [P, Q]`, `hinge of`, material seeds and macros are allowed.
  Constructions are computed on raw positions, since they commute with rigid
  motions; only `model [...]` is mapped through the inverse display.
- **Axioms return lists**: every real solution; off-paper ones reported, never
  chosen; `nearest P` when more than one remains; exactly one accepted.
- **Landmarks.** `mark A = POINT [in face containing S]` pins one material point
  and labels it while visible. `let NAME = POINT | LINE` is expanded by
  `Sequence.Elaborate` and re-evaluated at each use. Only marks and step names
  enter the landmark table; names are unique; a reference a later step made
  ambiguous is refused.
- **Why.** The sheet never gains or loses paper, so material coordinates are the
  fixed parameter domain CAD lacks
  ([E2](research/E2-references-and-persistent-naming.md) "D. The topological naming
  problem in CAD"); edge and face ids do not survive creasing; books name
  alignments ([E1](research/E1-prior-art-sequence-languages.md)).
- **Rejected.** Raw ids; typed decimals as the primary form; exact algebraic
  landmark types; `cyclotomic` (GPL-3.0-only); view words for material features.
- **Residue.** Unifying the nine "hair" tolerances is a prerequisite issue
  ([gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md)
  "A. How exact a landmark is today", finding 2); until then every requirement
  names the existing tolerance it reuses, and the runner defines none of its own
  beyond `nearMissBand`. The issue was filed only after M2, as #546 on
  2026-10-12, and M2 has four of its own. When the runner re-anchors, it counts
  faces within a relative 1e-9 of the largest area as tied, and takes only a face
  turned to the reader, or away, to within 4.5e-5 radians: its normal's cosine
  within 1e-9 of 1. The resolver calls a line north-south when its east-west part
  is within 1e-12 ([C96](#changes-since-draft-v2)), and the run report says an
  anchor moved off the new crease within 1e-9 sheet lengths.

### D3. The runner owns the state, its start and the handoffs

- **`FoldState`** is abstract and lives in `Sequence.Run` ([D23](#d23-the-sequence-modules-and-where-run-lives)).
  It holds the *working pattern* (the crease pattern cut at crossings, in material
  coordinates, rings counter-clockwise, the anchor's face first, *intent
  assignments*, explicit `edges_foldAngle`, accepted `faceOrders`); directional
  layer requirements where a move supplied them; the *anchor*, a material point;
  *anchor placement*, a proper rotation, identity at start, keeping the picture
  still across a re-anchor; *presentation* ([D5](#d5-presentation-and-the-readers-side));
  the landmark table; crease provenance; macro bindings. Displayed positions are
  presentation ``after`` anchor placement ``after`` raw `foldFrameWith` positions,
  where ``a `after` b`` does b first.
- **Intent at angle 0 is kept on purpose.** A crease lying flat keeps on the
  working pattern the M or V it was made as: a sheet file's crease, which plain
  `sheet` lays at 0, or a fold's new crease, at 0 before the paper turns and again
  after an `unfold`. That departs from `Fold.Creasing`'s "a valley with an angle of
  nought is not a valley" ([`Creasing.hs:281-286`](../src/Senbazuru/Fold/Creasing.hs#L281-L286)).
  It is needed because `Flap` turns only M, V or U
  ([`Flap.hs:262`](../src/Senbazuru/Origami/Flap.hs#L262)) [code] and a collapse
  binds on direction; it is safe because folding reads explicit angles first and
  stacking reads an assignment only at angle 0, where a crease orders nothing.
  Written frames restore the FOLD rule ([D4](#d4-written-frames-follow-the-state-rule)).
- **A pre-crease's crease is U** (owner decision 14, refined 2026-09-24,
  [D12](#d12-the-text-syntax)). A pre-crease marks the paper: a later move may fold
  its crease either way, and may fold one stretch mountain and another valley, so
  it has no direction to keep. U is FOLD's letter for a crease whose direction is
  undecided. `Flap` turns it, `surfaceFeatures` keeps it as a crease
  ([`Surface.hs:278`](../src/Senbazuru/Origami/Surface.hs#L278)) [code], and
  written frames show it as F at 0.
- **Starting.** `Sequence.Run.sheetState :: SheetStart -> Frame -> Either SheetProblem FoldState`
  is pure; the CLI only loads bytes. (Built as `FoldFile -> Either SheetProblem FoldState`,
  [C96](#changes-since-draft-v2).)
  1. The sheet is the file's *key frame*, never a `file_frames` entry. A key frame
     with no vertices is refused as `SheetHasNoVertices`, naming the
     `file_frames` count; one whose `Query.frameKind` is `FoldedForm`
     ([`Query.hs:459-463`](../src/Senbazuru/Fold/Query.hs#L459-L463)) as
     `SheetAlreadyFolded`.
  2. Drop `faceOrders` and `frameExtras`, apply `withPlanarFaces`, normalise rings.
  3. **Intent** ([C17](#changes-since-draft-v2)): M and V kept; an F crease whose
     file angle is beyond ±τ becomes M below −τ and V above τ, as `StudyCase`
     rewrites F ([`StudyCase.hs:208`](../study/fold-material/StudyCase.hs#L208))
     [code]; B, C, J and U kept as written, so **U stays U whatever its angle**.
     v2 said both "U stays U" and "an edge with a nonzero angle and no M/V takes M
     or V", which contradict for U. F at a nonzero angle contradicts itself (F
     means unfolded), so the angle is trusted over the letter; U at a nonzero
     angle is consistent (the direction is undecided), and intent is a claim about
     how a crease was made that the runner must not invent.
  4. **Angles.** Plain `sheet` sets every angle to 0, as the recipes do
     ([`BlintzSequence.hs:42`](../study/fold-material/BlintzSequence.hs#L42)) [code].
     `start folded { … }` keeps angles as `Folding.foldAnglesOf` reads them:
     explicit angles first, otherwise M −180, V +180, else 0
     ([`Folding.hs:521-547`](../src/Senbazuru/Origami/Folding.hs#L521-L547)) [code],
     then chooses a stacking by [D11](#d11-stacking-choices-are-relations). M2
     refuses it before `sheetState`, as `StartFoldedNotRunYet`
     ([C96](#changes-since-draft-v2)). `sheet square` is the unit square.
- **Default anchor** ([C20](#changes-since-draft-v2)): the *vertex mean* (the
  average of the corner coordinates) of the initial pattern's largest face, ties
  to the lowest then leftmost vertex mean. That is `StudyCase`'s rule, which ranks
  by area, then negated mean y, then negated mean x
  ([`StudyCase.hs:242-248`](../study/fold-material/StudyCase.hs#L242-L248)) [code];
  v2 and the glossary said "centroid", which differs on a general quadrilateral.
  The header's `anchor P` overrides. A face that is not convex can have its vertex
  mean outside it or on its outline; then the point is the vertex mean of the face's
  largest *ear*, by the same ties, and a face with neither clear of its outline is
  passed over (owner decision 51, [C110](#changes-since-draft-v2)). G13's refusal of
  such a default is withdrawn.
- **Re-anchoring** (owner decision 3, decided 2026-10-06: re-anchor). When a move's moving
  side contains the anchor's face, the new anchor face is the stationary face
  beside the hinge with the largest material area, ties by lowest then leftmost
  material vertex mean, never by face id; its vertex mean becomes the anchor, or
  its largest ear's, as for the default.
  Mechanism: read h, that face's placement in the current raw fold, before
  reordering; anchor placement := anchor placement ``after`` h; put that face
  first; re-map orders and requirement pairs; refold; join-check displayed
  positions. Refused as `ReanchorNotFlat` if the new face's displayed normal is
  not ±ẑ. The move `anchor P` does the same on demand.
- **An anchor that a new crease passes through** (G1, [C19](#changes-since-draft-v2)).
  After creasing, if the anchor point is no longer strictly inside one face, the
  anchor moves to the vertex mean of the largest face whose closed polygon contains
  the old point and which this move does not turn, ties lowest then leftmost, or
  to its largest ear's, as for the default.
  Creasing moves no paper, so anchor placement is unchanged; the record notes the
  move. Example: `sheet square` with no `anchor` line has its default anchor at
  (1/2, 1/2), which the crane opening's first diagonal passes through. 02's G1
  said [D16](#d16-testing-and-acceptance)'s authoring test hits this; it does
  not, because that test writes `anchor (3/4, 1/4)`
  ([09 §2.3](09-testing-and-acceptance.md#23-test-2-authoring-from-sheet-square-m3-and-m4)).
- **Invariants** ([A2](research/A2-study-recipes-as-proto-dsl.md) "(b) The shared
  handoff policy: invariants an interpreter must enforce"):
  1. carry accepted angles and orders onto the working pattern; never feed folded
     coordinates back as material;
  2. drop `frameExtras` and stale faces on every transform;
  3. refold after every handoff and never patch a `Folded`. Orders reach `Flap` by
     sitting on the working pattern before the fold: `foldFrameWith` copies them
     and re-signs any whose second face it re-wound (#78). A state's first
     stacking: fold, solve on `foldedFrame`, record the orders on the working
     pattern, refold. Never attach orders to a `Folded` as `CraneWing.hs:139` does;
  4. re-resolve every id after a topology change;
  5. anchor by material point, and re-anchor as above;
  6. join-check every step: positions within 1e-12 × `modelSpan`
     ([`BlintzSequence.hs:69`](../study/fold-material/BlintzSequence.hs#L69)
     [code]); angles, edge lists, face rings compared as `map sort facesVertices`,
     orders and material coordinates exactly;
  7. never re-solve a stacking silently ([D11](#d11-stacking-choices-are-relations)).
- **Rejected.** Refusing whenever a move carries the anchor (kept as owner
  decision 3's alternative); a default anchor by face id; inventing intent for U.
- **Residue.** About seven `foldFrameWith` calls per checked step, counted from
  code, not timed
  ([gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md)
  "From reading the code (counts, not timings)"); measure before caching. As built,
  [C89](#changes-since-draft-v2) counted 8 per blintz move.

### D4. Written frames follow the state rule

- **The at-rest rule, defined once.** `Fold.Query.atRest :: Double` is τ, **1e-10
  degrees** ([C29](#changes-since-draft-v2)), equal to both existing literals
  ([`Surface.hs:278`](../src/Senbazuru/Origami/Surface.hs#L278),
  [`StudyCase.hs:208`](../study/fold-material/StudyCase.hs#L208)) [code], so
  migrating either later is a rename. `assignmentAtRest :: Assignment -> Double -> Assignment`:
  B, C, J pass through; otherwise M below −τ, V above τ, F between. When the
  writer writes F it writes the angle as exactly 0, so no written frame has F at a
  nonzero angle and `Stacking.creaseDirections`'s exact test agrees with the rule.
- **Every emitted frame** has explicit `edges_foldAngle` (else `WriteMissingAngles`),
  no non-finite number (else `WriteNonFiniteAngle`, #58 item 3), never U, never M
  or V at 0. (Built otherwise: `encodeFoldFile` refuses any non-finite number as
  `NotFinite`, #510, and the writer a non-finite material coordinate as
  `WriteNonFinite`, [C96](#changes-since-draft-v2).)
- **Layout.** A metadata-only key frame; then `file_frames` holding the states of
  [D24](#d24-states-figures-and-their-numbers): the starting state, then for each
  step that writes one its authored `sample` poses in parameter order and its end
  state. `senbazuru:material_coords` and `senbazuru:assurance` go only on
  `file_frames` entries, written after the last transform. The key frame carries no
  vertex-indexed data until #73 splits file and frame keys; a record that is not
  vertex-indexed, such as [D14](#d14-material-consumption)'s `senbazuru:unsettled`,
  may sit there.
- **`frame_classes`.** `creasePattern` only when every angle is 0 **and** every
  face shows its top towards +z in written coordinates (its material-winding ring
  has positive signed area in written x, y); otherwise `foldedForm`.
  `faces_vertices` keep the material winding, so a turned face draws its back and
  a `white side up` sheet's first state is `foldedForm` although flat.
- **File header.** `writeSequence :: FileHeader -> Run -> Either SequenceError FoldFile`
  writes `file_spec` 1.2, a `file_creator` naming senbazuru, `file_title` from the
  sequence title, `file_classes ["diagrams"]`, and optional `file_author` and
  `file_description`. The sheet's `file_classes` and top-level unknown keys are not
  copied, a stated omission until #73.
- **Captions and assurance point in opposite directions, on purpose.** A state's
  `frame_title` is the caption of the step *leaving* it (the `closing` caption on
  the last state); its `senbazuru:assurance` is the evidence of the step that
  *produced* it, absent on the first state.
- **Worked example** ([02 §11](02-language-semantics.md#11-written-frames)) [prd]:
  on the quarter fold, edges 8–11 are `M V M M` in every fixture frame, but the
  written assignments are `F F F F`, `M F M F`, `M V M M`, because edges 9 and 11
  stay at 0 until step 2.
- **Why the state rule.** It alone agrees with FOLD's sign rule, the `Assignment`
  haddock and `flatAngleFor`; writing square-base's flat guides as M made `check`
  report a false Maekawa violation; it needs no look-ahead
  ([gap-assignment-at-rest-convention](research/gap-assignment-at-rest-convention.md)
  "Recommendation").
- **Rejected.** M or V at 0; U at 0; the target-state direction; J for creases not
  yet made.
- **Consequences.** `examples/quarter-fold-steps.fold` stays as it is (owner
  decision 9). Fold-here dashes come from step notes. The material consumer reads
  intent from records, never from written F, M or V.

### D5. Presentation and the reader's side

- **Presentation moves no paper.** `turn over left-right | top-bottom` and
  `rotate k/8 turn clockwise | anticlockwise` change `FoldState`'s presentation.
  The axis is model-intrinsic, computed in `Sequence.Run` from `Geometry` alone:
  `left-right` maps (x, y, z) to (2cx − x, y, 2cz − z), `top-bottom` to
  (x, 2cy − y, 2cz − z), and `rotate` turns about the line parallel to +z through
  (cx, cy), where (cx, cy) is the centre of the current displayed state's xy
  bounding box and cz the middle of its z range. On quarter-fold state 2
  (x ∈ [1/2, 1]) cx = 3/4, so `left-right` maps x to 3/2 − x and keeps the model
  in place, where #95's half turn about x = 0 would carry it to [−1, −1/2]
  ([02 §5.2](02-language-semantics.md#52-presentation-moves-no-paper)) [prd].
- **Exactness.** Turn-overs, half turns and quarter turns use exact 0/±1 entries,
  and eighth turns ±`sqrt 0.5`, so a presentation adds no platform trigonometry
  bits of its own (owner decision 10, C91); joins compare unpresented positions,
  so exactness is not needed. No presentation is checked as the run goes: a
  `Rigid` cannot mirror or stretch, and the runner's turns composed in any
  order make only 32 matrices, each within 4.4e-16 of a proper rotation (C95).
- **The reader's side is a property of the fold state, never of a render.** It is
  model +z of the displayed model: coloured side up by default, or
  `white side up`, which starts with a `left-right` turn-over (G3); flipped by each
  turn-over; unchanged by `rotate` and by re-anchoring. `valley`/`mountain`
  (aliases `in front`/`behind`), `top N layers`, `top flap`,
  `layers A above B`, `model [...]` and pose angles are read from it.
- **The raw sense** is the author's sense, negated exactly when presentation
  ``after`` anchor placement sends ẑ to −ẑ. It names the assignment of new creases
  on a flat sheet, and it is the assignment handed to creasing through layers,
  which flips it per layer itself.
- **The hinge turn takes a side, not a signed travel** ([C5](#changes-since-draft-v2)).
  **The line that looks like a typo:** on quarter-fold step 2, one valley fold
  writes edge 9 at +180 and edge 11 at −180. `Flap`'s *travel* is the change in the
  *first* listed segment's angle, and every other segment's sign follows from
  its own stationary face's ring direction
  ([`Flap.hs:10-16`](../src/Senbazuru/Origami/Flap.hs#L10-L16),
  [`:284-301`](../src/Senbazuru/Origami/Flap.hs#L284-L301)) [code]. Both faces beside edge 11 were turned
  over by step 1, so the same physical turn is −180 there; with edge 11 listed
  first the valley would need travel −180
  ([01 §5.6](01-architecture.md#56-travel-per-segment)) [py]. So the sign of
  travel depends on the raw sense **and** on which way up the paper beside the
  first segment lies, and v2's "one raw sense sets the sign of Flap's travel" was
  wrong. The fix stays in the library, where v2 wanted every way-up decision:
  `Origami.Flap` has an entry taking a magnitude and a raw side (05 L14; #344,
  #368),
  `prepareFlapToward :: [EdgeId] -> FaceId -> Double -> Toward -> Folded -> Either FlapError FlapMotion`
  with `data Toward = TowardPlusZ | TowardMinusZ`. As the amendment below
  decides, it reads the moving face beside each segment: travel is +A when
  "towards +z" agrees with that face's way up and −A otherwise, and every
  segment's reading must agree ([`Flap.hs:332-364`](../src/Senbazuru/Origami/Flap.hs#L332-L364)) [code].
  The runner passes `TowardPlusZ` for a raw valley.

  | Raw sense | Moving face shows its top | shows its back |
  | --- | --- | --- |
  | valley | +A (edge 9 in step 2) | −A (edge 11 in step 2) |
  | mountain | −A (edges 8, 10 in step 1) | +A (the crane wing's accepted `behind`, appendix command 16 [ran]; the blintz's folded-under corner, reopened, in `BlintzSequenceSpec`) |
- **Amended 2026-09-23 (owner decision 13): the sense is where the moving
  paper goes.** `valley`/`in front` means the paper that moves sets off
  towards the reader's side, and `mountain`/`behind` away from it, as
  [02 §5.3](02-language-semantics.md#53-one-conversion-for-the-whole-model)'s
  own sentence says. This replaced the reading #344 shipped, of the sign
  from the first segment's *stationary* face. That reading agreed on every
  open hinge, which is every example above, but on a flap lying folded over
  its held face it called lifting the flap towards the reader `behind`, and on
  a page turn, whose held faces lie on both sides of the line, its answer
  depended on which crease was listed first
  ([E3](research/E3-formal-fold-semantics.md) G, whose run is the script
  [`E3-square-base-listing.ghci`](research/scripts/E3-square-base-listing.ghci)).
  Under the new reading a `fold` turns a flap back off the face it lies on
  with the sense of where the flap goes: lifting a top flap towards the
  reader is `in front`.
  - *Evidence.* No source E3 read attaches a sense read from the viewer to
    reopening a folded hinge, and where a source does attach a viewer's sense
    word to a fold, the word names where the moving paper goes. Rigid-origami
    definitions do sign a closed hinge, but relative to the paper, which is
    the reading this replaces (E3 finding 5).
  - *The rule*, proposed here and adopted by #368
    ([`Flap.hs:332-364`](../src/Senbazuru/Origami/Flap.hs#L332-L364)). A positive change in a crease's
    angle moves the face beside it towards that face's own top, so the sign
    follows from the moving face's way up, and `TowardPlusZ` means the turn
    that sets the moving paper beside the hinge off towards +z. The moving face
    beside *every* hinge segment is read. If those faces lie on both sides of
    the line, part of the paper would rise and part fall, and the turn is
    refused as `FlapMovesBothWays`, whatever its size, 0 included. Each must
    lie flat, judged by `hasRelief` as the held face was, or the turn is
    refused as `FlapMovingNotFlat`, which replaced `FlapStationaryNotFlat`; so
    a turn begun past vertical is refused rather than read as `behind` (E3
    open question 5). #368 replaced the name in `refusalKinds` too, and no
    source had named it.
  - *Reopening without a sense.* A move that only opens a folded hinge, drawn
    in books with an unfold arrow, is proposed beside `fold` (E3 G) and not
    decided. `unfold NAME` already reverses a named step exactly.
  - *#282's negative control, E10,* becomes `fold in front 180° hinge of c1
    moving corner south-east`: after c1 the corner lies under the square, so
    carrying it on through the centre sets it off towards the reader. `Flap`
    refuses it as `FlapEndpointOrder`, which 09's E10, its `expect refused`
    form and 04's A19 golden expect. Once 05 L11's covering check (02 §6.3
    step 4, M4) exists, the square is found nearer on the side the corner
    turns towards and the move is refused before `Flap` runs, as
    `FlapCovered`, whichever sense word it is written with; those three change
    with it, as the crane example did ([C9](#changes-since-draft-v2)).
  - *Where the replaced rule was written.* The bullet above; §5's sketch of
    `Toward`; §7's crane note; D20's refusal list; 01 §5.4's call and §5.5;
    02 §1's step `half`, §5.3's table and its paragraph on handing `Flap` a
    side, §9's crane note and §12's `FlapStationaryNotFlat` row; 05 L14 (its
    sketch, R-05-45 to R-05-47 and its acceptance rows) and its errors table;
    and the glossary additions' *Travel*. Each was rewritten once #368 shipped
    the rule (#370). C5 and its row in
    [Proposals not adopted](#proposals-not-adopted) keep their history. #368
    also corrected the shipped docs, `docs/usage.md` and `docs/tour.md`, and
    moved the argument into its own note,
    `docs/notes/turning-towards-a-side.md`. 09's E10 already read as above.
- **Render options never change a step's meaning.** For every view V,
  `run -o x.svg --view V` draws the states `run -o x.fold` writes. On a page, a
  stated kind is inverted when the camera looks from the opposite side; edge-on
  views draw the stated kind and mark the figure; captions are not rewritten; `run`
  warns once when a page is drawn from the opposite side.
- **Page extent.** A turn-over or half turn keeps each figure's extent, the page
  union and the scale only on `top` and `bottom` pages whose roll is a multiple of
  90°. On `bird-base-sequence.fold` `file_frames[13]` the `iso` extent changes from
  0.4142 × 0.6118 to 0.9981 × 0.3335, and at a 45° roll the width and height swap
  ([06 §5](06-prd-step-diagrams.md#5-turn-over-and-rotate-marks-and-the-page-extent))
  [prd].
- **Written frames are presented, and `Origami.Step` recognises a presentation
  change.** New `Geometry.Rigid.fitRigid :: [(V3, V3)] -> Maybe Rigid` (three
  non-collinear pairs, every pair within `1e-9 × max 1 modelSpan`, the tolerance
  at [`Step.hs:141`](../src/Senbazuru/Origami/Step.hs#L141), det +1). A frame pair
  is a presentation change, with no inferred arrow, when **some** vertex moves by
  more than that tolerance and one proper rigid motion maps every vertex within it
  ([C26](#changes-since-draft-v2)). v2 said "every vertex moves", but its own
  turn-over leaves the vertices on the axis still: 3 of 9 on
  `quarter-fold-steps.fold` and `quarter-fold.fold`, 5 of 13 on `bird-base.fold`,
  2 of 8 on `blintz-base.fold` [py]. An identical pair still gives `[]`, since
  nothing moves. A flap turn cannot qualify: its stationary face keeps three
  non-collinear vertices still, so the only fit is the identity, which the moved
  vertices contradict. No consecutive pair in either multi-frame example keeps
  every distance while something moves (0 of 15 on the bird sequence, 0 of 2 on
  the quarter fold) [py], so no existing page can change.
- **Rejected.** Turn-over as a frame move (#95); page-axis turns (the runner would
  need a camera, and written files would depend on `--view`); reflection, which is
  the mirror model; "every vertex moves".
- **Residue.** None left. `Rigid(..)` was exported unchecked until M2, when the
  constructor was hidden and a checked `rigidFrom` added
  ([§10](#10-corrections) item 19, C95).

### D6. Crease graphs grow between frames

- **What.** A crease first appears in the state after the move that makes it, so
  consecutive states can have different edge lists.
  `Origami.Step.motionsAcross :: Frame -> Frame -> Either FoldError [Motion]`
  matches them by *material identity*, which piece of paper each vertex and edge
  is. It relies on the **prefix rule**: `before`'s vertex ids are a prefix of
  `after`'s, with equal material coordinates, because cutting and creasing never
  renumber a vertex ([05 L5](05-prd-library-additions.md#l5-motionsacross-creasestocome-and-a-non-convex-point-test)).
  An added vertex is placed on `before` by interpolation along an edge's material
  segment, or by the containing face's material-to-position affine map, found with
  a new non-convex `Geometry.Polygon.insideRing`. `motionCreases` reports `after`
  edges; an unmatched edge is new, never "changed".
- `creasesToCome :: Frame -> Frame -> Either FoldError [(EdgeId, V3, V3)]` gives
  the new creases at `before` positions, for fold-here lines.
- `motionsBetween` is unchanged and still used whenever the two graphs are equal,
  so no existing page takes the new path.
- A `checkpoint` may remove creases, so it breaks the prefix rule and starts a new
  figure with no inferred motion ([D21](#d21-repeat-checkpoint-not-modelled-expect-refused)).
- New `FoldError` constructors: `MaterialCoordinatesMissing`,
  `VerticesNotAPrefix`, `AddedVertexOffPaper`.
- **Why.** `motionsBetween` refuses unequal graphs and compares angles by edge
  index ([`Step.hs:94-96`](../src/Senbazuru/Origami/Step.hs#L94-L96)) [code], and
  cutting shifts every later edge id
  ([05 L2](05-prd-library-additions.md#l2-creaseallalongwith-and-newcreaseangle)'s
  `diagonal-cp.fold` table).
- **Rejected.** Backfill, writing the final crease graph into every frame: the
  existing quarter-fold golden already shows its cost, drawing the second fold's
  line on the first figure
  ([gap-step-annotation-channel](research/gap-step-annotation-channel.md) "B. What
  the fixture and goldens show").
- **Residue.** Byte identity of `motionsAcross` on equal graphs is argued, not
  run; the equal-graph branch avoids depending on it.

### D7. A typed step note reaches the page

- **What.** `Render.Steps.stepPageWith :: Theme -> Budget -> Grid -> View -> [(Frame, StepNote)] -> Either StepError (Maybe Diagram)`,
  with no `Bool` beside the notes. `stepPage` keeps its signature and becomes
  `stepPageWith` over `noteFor arrows` (`inferNote` or `silentNote`), so its
  call lines are untouched
  ([06](06-prd-step-diagrams.md#what-changing-the-api-would-cost)) [prd].
- **`StepError` is unchanged** ([C37](#changes-since-draft-v2)). It is a record of
  a frame index and a `FoldError`
  ([`Steps.hs:58-62`](../src/Senbazuru/Render/Steps.hs#L58-L62)) and the CLI takes
  it apart by pattern ([`Cli.hs:969-977`](../app/Senbazuru/Cli.hs#L969-L977))
  [code]. Every note is drawable; the only new failures are `motionsAcross`'s and
  `creasesToCome`'s `FoldError`s, which fit.
- **`StepNote`** (**SKETCH**): caption; arrows (`InferArrows`,
  `InferArrowsAs kind`, `GivenArrows [..]`, `NoArrows`); a presentation mark
  (`TurnedOver` axis point and direction, or `Rotated` signed eighths), which
  places a `Symbol` and suppresses inference on that pair only; a repeat range;
  selected layers (for #48); fold-here lines; and marks, `noteMarks :: [(Text, V3)]`,
  added because M3 includes marks and D2 labels a visible mark
  ([C33](#changes-since-draft-v2)). Frames arrive presented, and `stepPageWith`
  never transforms a coordinate.
- **Arrows come from records.** For each moving record of a step, in order,
  `Render.Sequence` gives that record's arrows with the record's kind, from
  `motionsBetween` over its before surface under its before display and its after
  surface under its after display ([D14](#d14-material-consumption)). A move whose
  moving paper is two groups joined only through still paper gets one arrow per
  group, as `motionsBetween` already splits them
  ([`Step.hs:175-192`](../src/Senbazuru/Origami/Step.hs#L175-L192))
  ([C36](#changes-since-draft-v2)). A pre-crease's before and after surfaces are
  one flat state, so its arrows come from its route: the fold arrow from its
  before surface to `recordPoseAt r (PoseOnRoute 1)`, the folded pose at the
  route's end, both under its before display, and the unfold arrow the same pair
  reversed. The fold arrow takes the sense the author wrote, as every fold arrow
  does ([01 §3.3](01-architecture.md#33-diagramstyle-imports-foldtypes)); the
  crease has none to give ([D12](#d12-the-text-syntax)). With one fold-here line,
  that is what the figure draws, although its frames are identical.
- **Kinds on the page.** `seenFrom :: Basis -> SeenFrom` is `FromReadersSide`,
  `FromOppositeSide` or `EdgeOn` as `basisForward`'s z is negative, positive or
  zero. From the opposite side, valley and mountain swap in heads and dashes alike;
  unfold and push do not; edge-on draws the stated kind with an `EdgeOnMark`.
- **`Diagram` stays FOLD-ignorant.** `ArrowPath` gains a head (`SolidHead`, today;
  `HollowHalfHead`, mountain; `HollowDoubleHead`, unfold) and a body (`PlainBody`,
  today; `CleftTail`, push), set only by `arrowFor`
  ([`Style.hs:364-372`](../src/Senbazuru/Diagram/Style.hs#L364-L372)). One new
  `Shape`, `Symbol`: a page-unit glyph at one model anchor, contributing only its
  anchor to extents. The wildcard matchers at `LayoutSpec.hs:32-35`, `:42-44` and
  `CreasePatternSpec.hs:394` are updated by hand, since the compiler cannot flag
  them.
- **The turn-over loop** lies across the turn's axis projected through the page
  basis, at the lower (or right) end of the figure's extent. When the projected
  axis is shorter than 1e-6 × max(1, the figure's larger side), the cut-off
  `withArrows` already uses, the loop is drawn as if the axis were page-vertical
  ([06 §5](06-prd-step-diagrams.md#5-turn-over-and-rotate-marks-and-the-page-extent))
  ([C34](#changes-since-draft-v2)).
- **Captions** are `Label`s placed by `Layout` one gutter below each cell's shared
  box, raised by a page-unit `Offset`; a trailing gutter joins the page box only
  when some figure has a caption, so uncaptioned pages keep their bytes.
- **Which states get which notes** is [D24](#d24-states-figures-and-their-numbers):
  a step's caption and arrows go on the state it leaves from; an authored `sample`
  pose is its own figure with no caption and no arrows; `expect refused` adds
  nothing. `stepNotes :: Run -> [(Frame, StepNote)]` returns exactly the frames
  `Sequence.Write` writes, because both read `Sequence.Record.writtenStates`
  ([D23](#d23-the-sequence-modules-and-where-run-lives)).
- **`render --steps` never draws `frame_title`.** A file cannot say whether its
  titles name states (the fixture's "Step 2: folded in half") or instructions (a
  written sequence file), and drawing either moves `quarter-fold-steps.svg`. #94
  closes at M3 through `run -o x.svg`, with its done-when amended at M0
  ([C35](#changes-since-draft-v2)).
- **Rejected.** A `Bool` beside the notes; changing `stepPage`'s arity; a sum-type
  `StepError`; presentation applied inside the page; kind from the changed
  assignment (one quarter-fold motion changes edge 9 to +180 and edge 11 to −180);
  checking a stated kind against an inferred one; a page-unit caption band.
- **Residue.** Captions overlap their own figure on both default pages: the
  three-column CLI page's gutter is 11.5 page units against 14-unit type, and a
  gutter clears the type only when g ≥ 42/340 ≈ 0.124 of a figure
  ([06 §8](06-prd-step-diagrams.md#8-captions-and-the-gutter)) [prd]. Long
  captions overflow across cells, and the backend has no font metrics. Owner
  decision 7.

### D8. Folding some layers

- **Library additions** ([05](05-prd-library-additions.md) L2, L7–L11):
  `data NewCreaseAngle = AtRest | FlatForAssignment`;
  `Fold.Creasing.creaseAllAlongWith :: NewCreaseAngle -> [(V2, V2, Assignment)] -> Frame -> Either FoldError (Frame, [[EdgeId]])`,
  with ids from the cutting's own chains; `Origami.Folding.untouchedFold`, `Flap`'s
  start check extracted once; `Origami.ThroughLayers.creaseLayersThrough :: NewCreaseAngle -> [(Set FaceId, V2, V2, Assignment)] -> Folded -> Either ThroughError Creased`,
  one batch, one `creaseAllAlongWith` call; `Origami.Visible.orderedCover`;
  `ThroughLayers.carryOrders`; and `ThroughLayers.selectLayers`, the selection rule.
- **`creaseAllAlongWith` lands at M2, not M4** ([C27](#changes-since-draft-v2)).
  M2 folds along new constructions on the flat sheet. Today a new mountain or
  valley is written at ±180 whenever the angle array exists
  ([`Creasing.hs:290-292`](../src/Senbazuru/Fold/Creasing.hs#L290-L292),
  [`:316-320`](../src/Senbazuru/Fold/Creasing.hs#L316-L320)) [code], already
  folded, so nothing is left for `Flap` to check; and `creaseAllAlong` returns no
  new ids ([`:138`](../src/Senbazuru/Fold/Creasing.hs#L138)), which is why
  `CraneWing` marks its new hinge `U` and finds it as "every `Unassigned` edge"
  ([`CraneWing.hs:114`](../study/fold-material/CraneWing.hs#L114)) [code].
- **`AtRest`** writes every new piece at 0 with its requested assignment; cut
  pieces of old edges keep their parent's angle. On a frame with no
  `edges_foldAngle`, it writes the whole array, existing edges as `foldAnglesOf`
  reads them, new pieces 0 ([C30](#changes-since-draft-v2)); leaving it absent
  would fold the new valley to 180. `FlatForAssignment` is today's code path, so
  `creaseAllAlong = fmap fst . creaseAllAlongWith FlatForAssignment`.
- **Per-layer intent.** `creaseLayersThrough AtRest` still flips a requested
  valley to M on face-down layers
  ([`ThroughLayers.hs:330-331`](../src/Senbazuru/Origami/ThroughLayers.hs#L330-L331))
  [code]. `U` cannot encode "at rest", because flipping leaves `U` as `U`. In a
  batch of two or more requests, a refusal is `RequestRefused i err`; a single
  request's refusal stays bare, so `ThroughLayersSpec`'s cases hold
  ([C31](#changes-since-draft-v2)).
- **Selection rule** (semantics in [02 §6.3](02-language-semantics.md#63-which-layers)):
  cut every crossed face along the line; `flap containing` takes the seed's
  component; `top N` counts depth at each point along the line from the reader's
  side; cut only the selected faces and walk from the moving side, refusing a
  coupled selection naming the joining face; refuse `FlapCovered` when a
  stationary face is nearer than a selected face on the turning side. That last
  check runs before `Flap`'s sweep.
- **Existing creases.** Where the line lies along existing creases covering the
  selected faces, the fold hinges on them without creasing. In the traditional
  crane that is 6 of the 12 some-layer steps: 15, 17, 18, 20, 21 and 23
  ([gap-layer-selective-folds](research/gap-layer-selective-folds.md) "(e) The
  traditional crane, step by step", classified by reading a book) [research]. The
  note's own count line says 7; its table rows marked "existing" are six
  ([review L3](research/spine-reviews/review-L3-author-ergonomics.md) L3-16).
- **An existing `F` crease cannot be a hinge.** `Flap` turns only M, V or U
  ([`Flap.hs:262`](../src/Senbazuru/Origami/Flap.hs#L262)) [code], so such a fold
  is refused as `ExistingHingeFlat`.
- **Unselected layers get no crease.**
- **Evidence status.** The rule reproduces `CraneWing`'s faces on `crane.fold`
  only in a Python re-implementation
  ([`research/scripts/layer-selection-analyse.py`](research/scripts/layer-selection-analyse.py)):
  `[2,3,6,7]` at folded y = 1/4, and `[2,3,6,7,32,34,35,38]` at the wing's root, where
  the crane-wing sequence folds (owner decision 42). The first M4 PR must reproduce the
  root's in Haskell before anything relies on it ([05](05-prd-library-additions.md)
  L11).
- **Rejected.** Ids inferred from counts; the U-edge marker; one line per call,
  against the batch rule; refusing a selected face the line misses.
- **Residue.** Giving an `F` hinge an intent from the fold's sense, by the same
  per-layer rule creasing uses, is a later library function, not v1.

### D9. Macro-moves as named angle relations

- **What.** A *macro-move* turns several creases at rates the geometry fixes. v1
  has `collapse at P [keeping [Q1, Q2] flat] until A°`, `rabbit-ear at P until A°`,
  and `petal tip P until A°` / `petal top flap until A°`. Squash, the reverse
  folds, sink, swivel and crimp stay `not modelled "…"` until each has a derived
  and tested relation.
- **Parts.** A driving parameter, `until 175°`, an unsigned exact `Rational` in
  degrees; one closed-form Haskell function per role, shared by runner and tests;
  a *signature* matched on a moving star (the creases the macro would turn at a
  vertex, with current angles and intent signs); roles, branch and sign.
- **Collapse.** Candidates are rays at P whose first segment is at 0 with intent M
  or V, continued straight through collinear segments. `keeping [Q1, Q2] flat`
  removes the opposite collinear pair towards Q1 and Q2. The six-ray signature
  (sectors 45°, 45°, 90°, 45°, 45°, 90°) must then match exactly once; otherwise
  every candidate is listed as the `keeping` clause that would pick it. Sectors
  are compared with `FlatFold`'s 1e-5 rad so `check` and the macro agree. On
  `square-base.fold` and `bird-base.fold` exactly one match needs no `keeping`
  ([02 §8.2](02-language-semantics.md#82-collapse)) [prd]. On a square creased
  only by pre-creases there are none, since a pre-crease's crease is U
  ([D3](#d3-the-runner-owns-the-state-its-start-and-the-handoffs)); see Residue.
- **`continue NAME until A`** takes the latest macro binding in NAME's line of
  continuations, maps each role's material segment onto the current pattern
  (refused if split or missing), checks each role crease is at its formula's angle
  at `reached` and no rigid sector is folded, requires reached < A ≤ max, and runs
  from `reached` to A. Signatures are not loosened, because recovering the
  parameter from `Double` angles loses its exact value.
- **`together { … }` is one move, one record, several bindings**
  ([C12](#changes-since-draft-v2)). Members advance by the same fraction of each
  member's own range, and members sharing a crease are refused (G6). The record
  carries `recordMacros :: [MacroBinding]`, each binding naming the line it
  continues (`bindLine`, the step that started it), so a later
  `continue first-petal` finds its binding inside a `together` record.
- **`sample 30° 60° …`** chooses illustration poses in the macro's own parameter;
  each is checked and written as its own state ([D24](#d24-states-figures-and-their-numbers)).
  Every sample must lie strictly between `reached` and A (G10). **Checking does not
  depend on illustration** ([C38](#changes-since-draft-v2)): the runner checks the
  authored samples plus `RunSettings.macroChecks` evenly spaced interior
  parameters, a count fixed with evidence in M5's PR, so a macro written with no
  `sample` still earns `Sampled` evidence and writes no extra states.
- **A macro landing flat with several stackings** is refused, listing the open
  pairs (G9); v1 has no syntax giving a macro relations.
- **`pose { crease [P, Q] at A°; … }`** sets named creases' angles, claims no route
  (`StateOnly`), and is allowed with paper in the air. **The sign looks like a
  typo** ([C61](#changes-since-draft-v2)): a pose angle is a FOLD angle converted
  once for the whole model, negated exactly when the display sends ẑ to −ẑ, with
  no per-layer flip. So +90° is a valley as seen from the reader's side only on
  paper lying the same way up as the anchor's face. Halfway through quarter-fold
  step 2, a single valley as seen, is
  `pose { crease [centre, (1, 1/2)] at 90°; crease [centre, (0, 1/2)] at -90° }`,
  the angles [01 §5.5](01-architecture.md#55-raw-sense-and-travel) folds [prd]. v2
  said "positive = valley as seen", which a per-layer rule would need, and a layer
  in the air has no way up to flip by.
- **Why.** A petal's seven creases turn at three rates, and `Flap` "does not
  discover coupled motions" ([`Flap.hs:1-6`](../src/Senbazuru/Origami/Flap.hs#L1-L6))
  [code]; #60's "compositions of the above" is false.
- **Rejected.** Macros as compositions of flap turns; loosened signatures;
  `sample` as the only checked poses.
- **Residue.** Petal geometry other than 22.5° is refused until derived; the
  rabbit-ear rule may be too strict; manifest angle literals sit one or three ulps
  from their documented formulas ([§10](#10-corrections) item 16). **Open before
  M5:** each macro matches on intent M or V, and a pre-crease's crease is U, so on
  pre-creased paper there is nothing to match. The crane meets this twice: its
  step 4 collapses creases that only pre-creases made, and its step 11 repeats a
  petal onto sides that step 10 pre-creases. The directions have to come from
  somewhere else, from the author or from the match
  ([02 §8.2](02-language-semantics.md#82-collapse)).

### D10. Assurance as evidence values

- **`RouteEvidence`** (library, `Sequence.Record`): `NoMotion` | `Presented` |
  `StateOnly` | `Sampled CheckedMacro SampleReport` | `SweptHinge CheckedFlap`.
  `NoMotion` means no paper moved: a move that creases without turning, `anchor P`
  and `mark` (G7, [C21](#changes-since-draft-v2)). `CheckedMacro` is opaque, as
  `CheckedFlap` is.
- **Weakest** (G7): a step's state carries the weakest evidence of its moves, in
  the order `StateOnly` < `Sampled` < `SweptHinge` < `Presented` < `NoMotion`,
  ordered by how much of the route a reader takes on trust; the records keep each
  move's own.
- **`expect refused` produces no record** ([C8](#changes-since-draft-v2),
  [D21](#d21-repeat-checkpoint-not-modelled-expect-refused)). A refusal claims
  nothing about a route taken, and every record consumer (page, animation, settle)
  would otherwise have to skip it.
- **Pose primitives.** `Origami.Flap.flapPoseAt :: CheckedFlap -> Double -> Either FlapError RoutePose`
  reuses `surfaceAt`'s one fold and returns placements already composed with the
  stationary correction; `Origami.Macro.macroPoseAt :: CheckedMacro -> Rational -> Either MacroError RoutePose`;
  `data RoutePose = RoutePose { routeAngles :: [Double], routeSurface :: Surface V2, routePlacements :: IntMap Rigid }`
  lives in a new `Origami.Route`, because `Origami.Flap` may not import `Sequence.*`,
  and `Sequence.Record` re-exports it ([C28](#changes-since-draft-v2)).
  `data PoseRef = PoseBefore | PoseAfter | PoseOnRoute Rational`;
  `recordPoseAt :: MoveRecord -> PoseRef -> Either PoseError RoutePose`, refusing
  `PoseOnRoute` as `NoRoute` for `StateOnly`, `NoMotion` and `Presented`. A route
  ends at its record's after state, except a pre-crease's: its `PoseOnRoute 1` is
  the folded pose and its `PoseAfter` is flat, because the run never performs the
  unfold that retraces the route ([D12](#d12-the-text-syntax)).
- **Records derive `Eq`, which needs a library change** ([C4](#changes-since-draft-v2)).
  `FlapMotion` and `CheckedFlap` derive only `Show`
  ([`Flap.hs:123`](../src/Senbazuru/Origami/Flap.hs#L123),
  [`:126`](../src/Senbazuru/Origami/Flap.hs#L126)), although every field type derives
  `Eq`: `Folded` ([`Folding.hs:325`](../src/Senbazuru/Origami/Folding.hs#L325)),
  `HingeSweep` and `SweepCheck`
  ([`HingeSweep.hs:89`](../src/Senbazuru/Origami/HingeSweep.hs#L89),
  [`:101`](../src/Senbazuru/Origami/HingeSweep.hs#L101)), `Surface`
  ([`Surface.hs:123`](../src/Senbazuru/Origami/Surface.hs#L123)) and `Rigid`
  ([`Rigid.hs:80`](../src/Senbazuru/Geometry/Rigid.hs#L80)) [code]. Both gain
  `deriving stock (Eq)` in 05 L14 at M2, and `CheckedMacro` and `SampleReport`
  derive `Eq` from the start. No record field holds a function.
- **Certificates attach after the run, in the study.** A registry keyed by macro
  name and fixture fingerprint gives `Certified | NoCertificateFor | Refused`,
  never downgraded, and never shown as `Sampled`.
- **Where it appears.** `run --report` prints each move's evidence; the writer puts
  a state's evidence in `senbazuru:assurance`; GLB extras keep it only when
  present, so existing GLB goldens are unchanged.

### D11. Stacking choices are relations

- **What.** `Origami.Stacking.stackingWhere :: Budget -> [(FaceId, FaceId)] -> Frame -> Either StackingError Stackings`,
  beside `layerOrderFor`. A pair means "first face on the +z side of the second"
  in the solver's sense, not FOLD's `faceOrders` sign; the runner maps "A above B
  as seen from the reader's side" into it. The pairs enter the search as decided
  pairs, per component, at the cost of one solve. `stackingWhere b []` equals
  `stackingSpace b`.
- **Errors split by who can detect them** ([C32](#changes-since-draft-v2)). The
  library's `StackingError` gains what face ids alone show: `RelationOnOneFace`,
  `RelationNotOverlapping`, `RelationsContradict`. An exhausted budget stays
  `GaveUpStacking`, never "ambiguous". `Sequence.Error`'s `StackingChoiceError`
  holds the runner's counting policy, `StillAmbiguous` (relations leave two or more,
  with the open pairs) and `SeveralStackings` (no relations and more than one), and
  wraps `StackingError`.
- **The runner decides.** Exactly one stacking: its orders go on the working
  pattern and `StackingChoice` records orders and relations. No relations and
  several: refused unless the author writes `stacking first`, which records index
  0 as a stated default. `layerOrderFor`'s silent first choice
  ([`Stacking.hs:386-400`](../src/Senbazuru/Origami/Stacking.hs#L386-L400)) [code]
  is never used by the runner.
- **Where relations are written:** `start folded { … }` and `checkpoint "path" { … }`,
  as one `StackingSpec = Relations [Relation] | StackingFirst`.
- **Crane example**, **UNVERIFIED**: `layers (1/4, 1/5) above (3/8, 5/9)` and
  `layers (4/9, 3/8) above (1/4, 1/5)`, points strictly inside tail face 10 and body
  faces 27 and 29 ([02 §7](02-language-semantics.md#7-stacking-relations)) [prd].
  An M4 test must show they leave exactly today's index 2 of 5 and that dropping
  either leaves two or more.
- **Budget.** `runSequence` takes a `Budget`; `run` passes `--layer-budget` for
  every geometric output. (Built: in its `RunSettings`, [C96](#changes-since-draft-v2).)
- **Rejected.** Filtering an enumerated list, which meets the per-component cap;
  reporting an exhausted budget as ambiguity.

### D12. The text syntax

The full EBNF, lexical table, reserved words and printer rules are owned by
[04](04-prd-sequence-source-and-cli.md#grammar); [§6](#6-grammar) points there.
The decisions:

- **Extension** `.foldseq` (`.fseq` is the xLights and Falcon Player format); first
  line `foldseq 1`, nothing before it (owner decision 1, decided 2026-10-12).
- **Words.** *Sequence source* (the text), *sequence file* (the written FOLD),
  *step* (the instruction for one picture), *move* (an instruction in a step),
  *figure* (one drawn state, [D24](#d24-states-figures-and-their-numbers)), *move record*. "Scheme" is
  retired, and so is "step record" ([C60](#changes-since-draft-v2)).
- **Lexical.** `#` comments; newline or `;` separates statements; braces delimit
  every block; indentation means nothing; newlines inside `( )` and `[ ]` are
  whitespace. Numbers are exact: `175`, `0.58` (= `29/50`), `29/50`. `n/0` is a
  **parse** error with the hint `ZeroDenominator`, because no `Rational` can hold
  it, so no tree reaches `Sequence.Check` with one ([C15](#changes-since-draft-v2)).
  Angles carry `°` or `deg`; `º` (U+00BA) and `˚` (U+02DA) are refused naming both.
  A `-` sign only in `(u, v)`, `model` pairs, pose angles and settle `except`
  angles. `0..1/32` lexes as a range, not a malformed decimal. `rotate k/8` and
  `turned k/4` read the denominator as typed. Strings are one line, with escapes
  `\"`, `\\`, `\n`, `\t` and `\u{…}`, so the printer can write any caption.
- **Structure.** Header lines (`title`, `sheet` (required), `anchor`,
  `coloured side up | white side up`, `start folded { … }`, `material { … }`) come
  after `foldseq 1` and before the first step, in any order, at most once. Steps are
  `step NAME? STRING? { moves [settle] }`; the caption is optional
  (`stepCaption :: Maybe Text`). `closing "…"` comes **after the last step**, the
  order the page draws it, and is stored as `hClosing` ([C7](#changes-since-draft-v2)).
  No move appears outside a step: `rotate` and `expect refused` at top level, as
  v2's examples wrote them, are not grammar ([C14](#changes-since-draft-v2)). A
  step whose only moves are `let` (or none) is refused statically as `EmptyStep`.
- **Moves** (canonical spelling first): `fold SENSE [A°] LINE [LAYERS] [moving P]`;
  `unfold NAME…`; `pre-crease SENSE LINE [LAYERS] [moving P]` (also `precrease`
  and `fold and unfold`), which takes **no angle** because `FoldAndUnfold` has no
  field for one; `turn over`; `rotate`; `anchor P`; `mark`; `let`; the macros;
  `continue`; `together { … }`; `pose { … }`; `repeat NAME[..NAME] [mirrored across [P, Q] | turned k/4 about P]`;
  `checkpoint "path" { … }`; `not modelled "…"`; `expect refused KIND { move }`;
  and `settle { … }` last in a step.
- **Amended 2026-09-23 (owner decision 14): a pre-crease is one move.** A
  `fold and unfold` leaves the paper where it began, and what it leaves behind is
  a crease, as in a real sheet. Instruction books call that fold a pre-crease, so
  the move is one move with that name.
  - *Spelling.* `pre-crease` is printed; `precrease` and `fold and unfold` read
    the same. `-` is a word character, as in `rabbit-ear`, so `pre-crease` is one
    reserved word. Shipped in #374.
  - *One core move.* It elaborates to `CorePrecrease` (shipped in #374), in
    place of a fold and `CoreUnfoldPrevious` (#335). The fold is checked like any
    hinge turn, and the run performs no unfold: the state after is the state
    before with the new crease, U at 0 ([D3](#d3-the-runner-owns-the-state-its-start-and-the-handoffs)).
  - *One record,* of kind `Precrease`, the first constructor
    [§5](#5-type-sketch) gives `MoveKind`. Its before and after are both flat, in
    one numbering; `recordNewCreases` holds the crease, with assignment U; its
    evidence is the fold's `SweptHinge`. So a pre-crease through layers is still
    checked, the page draws the fold arrow and the unfold arrow from the one
    record's route ([D7](#d7-a-typed-step-note-reaches-the-page)), and an
    animation plays the route out and back ([D19](#d19-realistic-rendering)).
  - *Refined 2026-09-24 (owner): the crease has no direction.* A pre-crease marks
    the paper. A later move may fold its crease mountain or valley, and may fold
    one stretch of it one way and another stretch the other, so the crease keeps
    no direction: it is U on the working pattern, and `Precrease` carries no
    sense. The sense the author writes says only which way the paper goes while
    the crease is made, which the fold arrow shows. The project's note on
    pre-creases makes the same point: the square and waterbomb bases start from
    the same eight pre-creased segments and each folds a different six
    ([precreases-and-target-states](../docs/notes/precreases-and-target-states.md)).
    Until then this amendment said the crease kept its direction and its intent.
    The cost falls at M5, where the macros match on intent
    ([D9](#d9-macro-moves-as-named-angle-relations)).
  - *Rejected:* two records, the fold and its unfold, as the glossary additions,
    02 §6 and 06 §2 said before. The folded state between them is never drawn,
    settled or named, and [D14](#d14-material-consumption) already rejected two
    records for a move that creases and then turns.
- **Reserved words are never names**, compared ignoring case, even where only a name
  could appear; so the bird example's steps are `square-base`, `first-petal`,
  `second-petal`. View words and future move words (`squash`, `sink`, `swivel`,
  `crimp`, `pleat`, `reverse`, …) are reserved now so later macros cannot break a
  source.
- **Tree refinements** ([C13](#changes-since-draft-v2)): `MidpointOfEdge Compass`;
  `StackingSpec` for both `StartFolded` and `Checkpoint FilePath StackingSpec`;
  `Located` on the refusable header fields (`sheet`, `anchor`, `start`,
  `material`) and on `together` members, so a caret points at their own line.
- **Canonical form** ([C24](#changes-since-draft-v2)). A bare name beside `to` or
  on the right of `let` parses as a point, and `Sequence.Check` assigns its kind.
  `canonical :: Sequence -> Sequence` rewrites the four non-canonical shapes a
  constructor-built value can have (`PointToLine p (LineNamed b)`,
  `LineOnto (LineNamed a) (LineNamed b) Nothing`, `LineOnto (LineNamed a) l Nothing`
  with `l` not a bare name, `Let n (BindLine (LineNamed b))`) to the parser's.
  Parser output and builder output are canonical, and `canonical` is idempotent.
- **Printer.** Canonical words (`valley`, `mountain`, `pre-crease`, `°`,
  `moving P`, `top layer`); numbers as integers or `n/d` in lowest terms, except
  `rotate` and `turned` denominators, printed as stored; defaults left out.
- **Round trip.** QuickCheck:
  `isRight (checkSequence s) ==> fmap stripSpans (parseSequence "gen" (prettySequence s)) == Right (canonical s)`,
  covering every constructor with `checkCoverage`; goldens of printed sources and
  of error text; the Haskell blintz equals the parsed blintz with spans stripped.
- **Parser.** megaparsec 9.5.0 and parser-combinators 1.3.0, both in the pinned
  lts-22.44 snapshot, plus `transformers`, all in the library stanza. The versions
  were read from the snapshot file in Stack's pantry cache (appendix command 6)
  [ran]; a stackage.org package page served LTS 24.59 and is not evidence.
- **Rejected.** JSON or YAML authoring (errors are JSON paths); significant
  indentation; s-expressions; a hand-written reader; context-dependent keywords; a
  parser that tracks each name's kind. A JSON machine encoding of the tree may come
  later.

### D13. The run verb and I/O

- **What.** `senbazuru run SOURCE`, with output chosen by the lowercased `-o`
  extension: `.fold` (the sequence file; stdout when there is no `-o`), `.svg` (the
  step page; `--columns`, `--view`, `--width`, `--height`, with `render`'s
  defaults), `.glb` (one state; `--frame`, `--all-layers`). `--check` parses and
  checks only, opens no sheet and refuses every geometric flag. `--report` writes
  each move's evidence, resolved references, new creases, re-anchors, stacking
  choice and work counts to stderr. `--layer-budget` reaches `runSequence` and the
  renderer for every geometric output. `--author` and `--description` go only with
  `.fold`. Any other extension is refused before any file is read.
- **`--frame N` counts as every verb already does** ([C59](#changes-since-draft-v2)).
  `allFrames f = keyFrame f : otherFrames f`
  ([`Types.hs:209-210`](../src/Senbazuru/Fold/Types.hs#L209-L210)) and `--frame`'s
  help says "default: 0, the key frame"
  ([`Cli.hs:515-524`](../app/Senbazuru/Cli.hs#L515-L524)) [code]. A written
  sequence file's key frame has no vertices, so state k is `--frame k+1`, as
  `bird-base-sequence.fold`'s "frames 1–16 are the folding states"
  ([`usage.md:1841-1842`](../docs/usage.md)) [code]. `run -o x.glb --frame N`
  therefore writes the same bytes as `export` of `run`'s `.fold` at `--frame N`.
  `--frame 0` and out-of-range values are refused, naming the state count.
- **I/O.** `Fold.Load.readSequenceText :: FilePath -> IO (Either LoadError Text)`
  is the only reader of source bytes: strict UTF-8, a byte-order mark stripped,
  no `Sequence` import. `sheet` and `checkpoint` paths are relative to the source's
  directory (`Sequence.Syntax.sourceFiles`); the CLI loads each distinct path with
  `loadFile`, so `.cp` and `.opx` sheets work, and passes the pure runner a
  `Map FilePath Frame` keyed by the path as written. (Built: `FoldFile`s,
  [C96](#changes-since-draft-v2).)
- **`decodeFile` refuses a `.foldseq` path, and the library's words name no command**
  ([C25](#changes-since-draft-v2)). Today every unrecognised extension decodes as
  FOLD ([`Load.hs:131-136`](../src/Senbazuru/Fold/Load.hs#L131-L136)) [code], so a
  source handed to `render` fails as bad JSON. A new `LoadError` constructor carries
  the path, and its `explain` says the file is a sequence source, not FOLD.
  `app/`'s `withFoldFile` appends "use `senbazuru run PATH`" when it sees that
  constructor. v2 put the verb in the library message (D13) and also called a
  library message naming command-line words a leak (D20), as
  `Query.creaseEndFlag` is ([`Query.hs:68-71`](../src/Senbazuru/Fold/Query.hs#L68-L71))
  [code]; the two rules contradicted each other, and D20's is the one that keeps
  library callers such as GHCi and the study from reading CLI advice.
- **Flag rules are library functions with their own types** ([C62](#changes-since-draft-v2)).
  The CLI is untested by design
  ([`Cli.hs:5-8`](../app/Senbazuru/Cli.hs#L5-L8)), so `Sequence.RunPlan` holds
  `planRun :: RunOptions -> Either RunOptionError Plan`, `chooseState` and
  `refusalLines :: Text -> SequenceError -> [Text]`. Its plan holds a view *name*,
  a column count and a `GlbScenes` enumeration, not `Render.Camera.View`
  ([`Camera.hs:188`](../src/Senbazuru/Render/Camera.hs#L188)) or
  `Render.Gltf.ExportMode` ([`Gltf.hs:160`](../src/Senbazuru/Render/Gltf.hs#L160))
  [code], which live in row 7 where a row-6 module cannot reach; `app/` maps them.
  The `Command` constructor is `RunSource`, since `Run` names the runner's result.
- **A `not modelled` move ends the run successfully**, with the states before it,
  and `run` writes those and exits nonzero naming the step
  ([D21](#d21-repeat-checkpoint-not-modelled-expect-refused)).
- `run` never goes through `withFoldFile`; every other verb's output and `--help`
  text stay byte-identical. #58 item 3 (refuse non-finite numbers on write) lands
  with M2; item 4 (atomic write, which needs `directory` in the library) is not
  claimed.
- **Rejected.** `--check` opening sheets; reading `.foldseq` through `loadFile`,
  which would make `Fold.Load` depend on `Origami.*`; a location inside `explain`;
  lenient UTF-8, which would turn a Latin-1 `°` into an invisible replacement
  character; `--format`; flag rules in `Cli.hs`; `--rotate` (a turn the reader
  should see is written in the source).

### D14. Material consumption

**Records in, illustrations out.**

- **Records are unpresented.** `recordBefore` and `recordAfter` are raw
  `foldFrameWith` geometry of the working pattern, with the anchor's face at
  identity. `CraneSpread` turns face orders into lower/upper pairs by each face
  normal's z sign and solves contact along +z
  ([07](07-prd-material-consumption.md#the-record-as-the-consumer-reads-it)), so a
  record presented turned over would read every pair backwards.
- **A record keeps presentation and anchor placement, before and after, as
  separate fields** ([C46](#changes-since-draft-v2)): `recordPresentation :: (Rigid, Rigid)`
  and `recordPlacement :: (Rigid, Rigid)`, with `displayBefore` and `displayAfter`
  computed from them. A `turn over` record changes presentation between its before
  and after; a re-anchoring move changes placement while positions stay put,
  between the record before it and its own, since it re-anchors before it turns
  and both its surfaces are held from the new face ([C83](#changes-since-draft-v2)). v2's
  single `recordDisplay` could not say which display a `Presented` record's
  before-state had ([06](06-prd-step-diagrams.md#dependencies)), and animation needs
  presentation and placement as separate nodes ([D19](#d19-realistic-rendering)).
- **One record per move, one numbering.** For a fold that creases, `recordBefore` is
  the cut, creased, unturned state; the uncreased state is the previous record's
  `recordAfter`, or the run's start state. Every id in a record (hinge, moving,
  stationary, new creases, both angle lists, stacking) is in `recordBefore`'s
  numbering, which `recordAfter` shares: a flap turn never re-cuts. A move kind that
  re-cuts after moving must be split or record a mapping.
- **Orders and requirements are read from the surfaces**, never stored twice.
- **Solver surfaces keep intent assignments.** A crease about to fold is at 0 in its
  before state; written `F`, it would drop out of `surfaceFeatures`, which keeps an
  `F` edge only beyond `1e-10`
  ([`Surface.hs:278`](../src/Senbazuru/Origami/Surface.hs#L278)) [code], and the
  bending solver would treat it as a bend inside a panel. The state rule stays a
  writing concern.
- **Fields** are in [§5](#5-type-sketch). `recordStationary` comes from
  `Flap.flapStationaryFace` (05 L4); `recordMoving` keeps seeds by
  [D2](#d2-references-named-on-the-sheet-and-resolved-by-slot)'s rule;
  `recordMacros` is a list ([D9](#d9-macro-moves-as-named-angle-relations)).
- **A `settle { … }` block binds to its step's last moving record**
  (`SettleOnNoMove` when there is none). It is a static solve starting from
  `recordBefore`, which must be flat: every vertex within `Fold.Faces.tolerance` of
  the root face's plane, else `SettleStartNotFlat`. Contact pairs are that state's
  coplanar `faceOrders`, every consequence added first (A below B and B below C
  gives A below C) and only then pairs with no free vertex dropped; dropping first
  loses A below C whenever B and C are held. Contact discovered from a separated
  reference is a later registered option, never a fallback.
- **Holds and grips are named against the record**, never by id, with the type
  `SettleRegion` ([D1](#d1-one-first-order-syntax-tree-built-by-name-only-builders)):
  `side stationary | moving`, `across-hinge S`, `closed R`, `band S d0..d1`
  (distance from the hinge line in `recordBefore`, in sheet lengths, slack
  `Fold.Faces.tolerance`), `material-band u0..u1`, `crease-line [P, Q]`,
  `hinge of NAME`, `layer upper | lower of R`, `union`, `minus`. A region resolves
  first against the record (source panels plus a test on each sample, stored as
  data) and then against the refinement, the only place mesh ids exist.
- **Refinement names a region** ([C41](#changes-since-draft-v2)):
  `refine REGION INTEGER`, such as `refine side moving 3`. 04's grammar had
  `refine sideword INTEGER`, which cannot say `CraneSpread`'s second refinement,
  `side moving union across-hinge stationary`.
- **Targets.** `hold R` keeps R where `recordBefore` has it. `hold R at rigid-pose p`
  and `grip R TARGET` fix vertices at `rigid-pose p` (the rigid state a fraction p
  through the move, through `recordPoseAt`; `SettleNoPose` for a record with no
  route) or at a registered generator. v1 registers `arc-grip ROOT° EXTRA°`,
  accepting a 30° root and 0–20° extra, as `craneSpreadWith` does: the root is
  fixed in `bentPoint` ([`CraneSpread.hs:177`](../study/fold-material/CraneSpread.hs#L177)),
  and the extra angle is checked with the refinement level
  ([`:105-106`](../study/fold-material/CraneSpread.hs#L105-L106)) [code];
  else `GripOutOfRange`. A generator also sets the start positions of free vertices
  on its side; other free vertices start at their side's `rigid-pose` target if
  one exists, else at `recordBefore` (R-07-16). A vertex whose targets differ by
  more than 1e-12 × `modelSpan` is `ConflictingTargets` (R-07-17).
- **Rest angles.** `RestAngles = RestAtPose PoseRef | RestAtPoseExcept PoseRef [(CreaseLine, Rational)]`, where a `CreaseLine` is written `crease [P, Q]`, `hinge of NAME` or `crease of NAME` inside `except { … }` ([04 grammar](04-prd-sequence-source-and-cli.md#grammar));
  every active crease rests at its angle in that pose; never derived from an
  assignment, so `CraneSpread`'s rule, −π for a mountain and +π otherwise
  ([`CraneSpread.hs:112-116`](../study/fold-material/CraneSpread.hs#L112-L116)) [code],
  is deleted when the crane is re-expressed. Rest comes from the settle, else the
  material block; neither is `SettleNoRest` (R-07-19).
- **`NoDifference` is computable** ([C39](#changes-since-draft-v2)): refused when the
  rest is `RestAtPose PoseBefore` with no exceptions and every target lies within
  1e-12 × `modelSpan` of `recordBefore`. A checked rigid state is already an
  equilibrium: the rigid 30° control ends with edge error 1.39e-11 and panel energy
  1.44e-27 ([07](07-prd-material-consumption.md#a-rigid-state-is-already-settled),
  from `docs/notes/spreading-connected-wing.md:63-67`) [research]. v2 also required
  "no released hold"; releasing a hold cannot move anything from an equilibrium
  start, so that clause tests nothing.
- **Stiffness.** A named preset; v1's `illustrative` is `Bending 1 0.2`, as
  `CraneSpread` builds its hinges ([`CraneSpread.hs:121`](../study/fold-material/CraneSpread.hs#L121))
  [code], and outputs say so. Precrease stiffness is owner decision 4.
- **Two contracts, two error types** ([C6](#changes-since-draft-v2)).
  `Sequence.Material` holds `SettleSpec` and
  `settleStep :: SettleSpec -> MoveRecord -> Either SettleStepError Settled`. After
  graduation `Material.Settle.settle :: SettleInput -> Surface V2 -> Either SettleError Settled`
  takes a resolved input: refinement, stiffness, `rest :: Map EdgeId Double`,
  resolved holds and grips, contact pairs. `Material.*` knows no moves, so the
  constructors that name one (`SettleOnNoMove`, `SettleNoPose`, `SettleNoRest`,
  `NoDifference`, …) belong to `SettleStepError`, which wraps `SettleError` as
  `SettleFailed`. **`SettleInput`'s ids look like the ids a source may not contain,
  and are not:** they are one surface's for one call and never outlive it.
- **Physical parameters** live in `material { size 15cm; thickness 0.1mm; stiffness illustrative }`,
  each length with a unit suffix; model value = physical ÷ size × s. On
  `crane.fold`, s is exactly 1 in `Double`, so 0.1 mm on a 15 cm sheet is 1/1500
  model units ([07](07-prd-material-consumption.md#the-material-block-and-physical-units))
  [prd]. A physical `frame_unit` that disagrees is `UnitMismatch`. Thickness is
  stored, not interpreted, and `--report` says so. Display parameters are render
  options, never sequence data.
- **Settled geometry is an illustration, never state.** It never replaces a rigid
  figure, GLB scene or animation key, and never enters `motionsBetween`,
  `motionsAcross`, a page basis or extent, or a later step. Only steps with a
  `settle` block are settled. Each accepted settle writes `STEM.settled-NAME.glb`
  and `.svg`; the GLB puts the complete sheet first and adds the visible scene only
  if it exports (#206); the SVG uses the rigid page's camera with its own extent.
  A failed settle refuses only its own files; other settles run; rigid outputs are
  written; the exit is nonzero, naming every refused step. A failed rigid run
  refuses everything.
- **`--allow-unsettled`** exits 0, substitutes nothing, and records the unsettled
  steps and reasons in `senbazuru:unsettled` on the key frame (not vertex-indexed,
  so [D4](#d4-written-frames-follow-the-state-rule) allows it), GLB extras and SVG
  `<desc>`. **Byte identity is scoped** ([C42](#changes-since-draft-v2)): rigid
  outputs are byte-identical with and without settle blocks when every settle is
  accepted or `--allow-unsettled` is absent; with the flag and a failure, the record
  of the failure is new bytes by design. Unaccepted meshes appear only under their
  own labelled flag, as FOLD or complete-scene GLB, never SVG.
- **Before M8** (R-07-10, R-07-22): the parser refuses `settle` and `material`
  blocks as not yet supported until M6; from M6 `run --check` checks them, `run`
  skips them and `--report` counts them, and `senbazuru-material-study --sequence SOURCE DIR`
  settles them. The solver's iteration budget comes from the consumer's settings,
  never from the source.
- **What cannot be named stays a fixture** ([C40](#changes-since-draft-v2)). Of
  the 21 existing crane controls, the region, rest and target vocabulary above
  names 16, four of them (rows 5, 6, 16 and 18) **UNVERIFIED** until their pins or
  crease segments are compared
  ([07](07-prd-material-consumption.md#every-existing-crane-control-re-expressed))
  [prd]. `WeakerRoot` and `WeakerBody` scale some springs' stiffness by 0.1
  ([`CraneRoot.hs:88`](../study/fold-material/CraneRoot.hs#L88),
  [`CraneBody.hs:80`](../study/fold-material/CraneBody.hs#L80)) [code], which one
  global preset cannot say; `CraneInternal`'s force restriction and borrowed orders,
  `crossedGrip`'s offset and `WingBending`'s own mesh are also fixtures.
- **First M6 test.** The wing record's resolved pins equal `spreadPins` of
  `craneSpread source 3 20` (same ids, positions within 1e-12), without solving.
  **UNVERIFIED**: `hold band moving 0..1/32 at rigid-pose 1/3` giving the root-strip
  pins, and `arc-grip` giving the grip pins. **The slacks differ:** `CraneSpread`
  adds `1e-8` in its fraction units, 2.5e-9 sheet lengths on a 1/4-long wing, and
  the band adds 1.41e-9, so the test fails if a refined vertex lies between them.
  Owner decision 42 (decided 2026-10-13) moves the crane-wing sequence of
  [§7](#7-examples) to the wing's [root](../docs/glossary.md#origami), owner decision
  34's hinge at folded y = 0.37585 (decided 2026-10-02), and #560 re-derives this
  test there ([§10](#10-corrections) item 43). The root's twin of
  `craneSpread source 3 20` is `craneSpreadWithAt r WingOnly source 3 20` with `r`
  from `wingRoot source`, the crane-spreading gallery's `curved` control, but it is
  not the target as built: its wing has a join along the widest point that no move
  writes. `wingRoot` lay 1.2e-9 below the root's exact height
  ([C102](#changes-since-draft-v2)) until the study's root finder was made exact,
  within 5e-14 of it ([C106](#changes-since-draft-v2)).
- **Rejected.** A surface as the whole interface; two records per crease-and-turn
  move; state-rule surfaces with a separate intent field; settling from
  `recordAfter`; a default settle; rest from assignments or by `EdgeId`; holds by
  id; substituting rigid meshes or an external solver on failure.
- **Residue.** Few settles start flat (the wing's next move starts at 90°);
  per-spring controls stay fixtures; results move 3.95% between the two accepted
  crane meshes ([B](research/B-material-study-mechanics.md) "Capability table
  (question a)").

### D15. Graduation from study to library

**Staged and gated.** One PR per stage, in order; the tracked goldens and the study's
accepted and rejected controls stay unchanged at each
([07](07-prd-material-consumption.md#graduation-staged-and-gated)):

1. split generic pieces out of fixtures (`ContactRow`, generic measures); delete
   `PacketContact`;
2. `SparseSolve` and `DirectionalDistance` become `Numeric.*`;
3. surface-based bending becomes `Material.Bending`;
4. penalty contact rows only become `Material.Contact`; barrier rows are used only
   by the local-history mode and stay in the study;
5. `relaxPinnedHinges`, `relaxPinnedContact` and bounded diagnostics, with
   structured errors, become `Material.Relax`;
6. one export adapter and one acceptance report become `Material.Export` and
   `Material.Verdict`;
7. `Material.Settle` and the library `Sequence.Material`.

- **Gates.** M6's crane equivalence PR compares resolved pin sets without solving
  and solves once in the slow job, so it does not double the costliest test groups.
  `run --settle` counts a mesh's refined triangles before solving and refuses it
  above its budget. The PR that builds `run --settle` sets that budget from 3–5
  compiled runs on the crane fixtures it must settle, and any later change is made
  the same way. Default CI settles at most 392 triangles, and never a crane
  fixture, which runs in the slow job whatever its size (owner decision 12,
  decided 2026-10-12, [C101](#changes-since-draft-v2)). Both numbers were first
  timed once each, with the wing hinged at y = 1/4: 5.76 CPU s at 392 triangles
  and 64.30 CPU s at 1,192, the cap this bullet first proposed
  ([07](07-prd-material-consumption.md#one-move-fed-by-hand)) [research]. Until
  2026-09-29 this bullet also gated M6 and M8 on #208's value-only line search,
  which never landed; the owner withdrew that gate ([§10](#10-corrections) row
  39), and #441 carries the optimisation.
- **Stays in the study:** `ContactQuadratic`, `CreasePairContact`, `CoupledCrease`,
  `UnequalCrease`, `CreaseInequality`; discovery, history and correction-sweep
  modes; barrier rows; `ClosedCrease`; `FoldMaterial`'s rounded bends; the `Crane*`
  and `Wing*` recipes and galleries; `PetalCertificate` and the certificate
  registry.
- **Rejected.** Graduating barrier rows no graduated solve uses; wall-clock settle
  limits.

### D16. Testing and acceptance

- **Every assertion names the change that turns it red.**
- **Tracked goldens stay byte-identical.** There were 33 on 2026-09-15 at `568dcb6`
  (`git ls-files test/golden | wc -l`) [ran]. The check is two commands on the committed branch
  ([C53](#changes-since-draft-v2)):
  `git diff --name-only --diff-filter=MD origin/main...HEAD -- test/golden/` must
  print nothing, and `--diff-filter=A` lists the goldens a PR adds. Both printed
  nothing then [ran]. v2's `git diff --name-only origin/main -- test/golden/`
  mixes added with changed files, compares against the working tree (so a new golden
  not yet added is invisible), and shows commits `main` gained since the branch.
- **Multi-frame examples draw the same step pages** (D5's acceptance). A PR before
  05 L3 pins `bird-base-sequence-arrows.svg`, the bird sequence drawn with arrows by
  today's code, because no existing golden draws that file with arrows
  ([C70](#changes-since-draft-v2)); 05 L3's PR keeps it and `quarter-fold-steps.svg`
  byte-identical, and compares `render --steps --arrows` on both multi-frame
  examples by hand with `cmp`.
- **Quarter fold, test 1: folding equivalence (M2).** The source of
  [§7](#7-examples), from `sheet "examples/quarter-fold-steps.fold"` with
  `anchor (3/4, 1/4)`. Written `file_frames[k]` is fixture state k (the fixture's
  key frame is its state 0). Compared: edges and face rings exactly; positions (the
  fixture's 2D coordinates padded with z = 0) within 1e-12 × `modelSpan`; **angles
  exactly** ([C52](#changes-since-draft-v2)), because a flap endpoint is
  `angle + progress * travel` ([`Flap.hs:469`](../src/Senbazuru/Origami/Flap.hs#L469))
  [code] with progress 1 and whole-number doubles, which IEEE arithmetic gives
  exactly; assignments by `assignmentAtRest`; `frame_classes`. Not compared:
  `frame_title`, `faceOrders`, `frame_attributes`. **The line that looks like a
  typo:** edge 11 ends at −180 under a valley step, because its stationary face lies
  upside down ([D5](#d5-presentation-and-the-readers-side)). The written frames'
  page is a new reviewed golden; the existing golden stays as the regression.
- **Quarter fold, test 2: authoring from `sheet square`.** Same anchor and steps.
  The run writes coarser crease graphs (4, 6 and 9 vertices; 4, 7 and 12 edges on
  hand-built frames, **UNVERIFIED** as runner output), so frames are compared by
  material identity, per state ([C48](#changes-since-draft-v2)):

  | Rule | Holds when |
  | --- | --- |
  | T1 | each fixture edge's material segment lies inside exactly one written edge with the same angle, or inside none and has angle 0 |
  | T2 | the fixture edges inside each written edge cover it |
  | T3 | each written vertex sits at a fixture vertex's material coordinate, positions within 1e-12 × `modelSpan` |
  | T4 | each other fixture vertex is placed at its fixture position by the written face or edge containing it |
  | T5 | assignments by the state rule |

  v2's clauses ("every written edge inside exactly one fixture edge", "every
  unmatched fixture vertex lies on a written edge") are false on correct frames:
  on hand-built frames of the three states, its edge clause fails on states 0 and
  1, its vertex clause on state 0, and T1 and T2 hold on all three [py]. The test
  **lands with the later of M3 and M4** ([C49](#changes-since-draft-v2)): step 2
  creases both layers of a flat-folded state, which needs `creaseLayersThrough`
  (M4), and the page needs `motionsAcross` (M3).
- **End to end, E1–E10, on the blintz** in default CI
  ([09 §3](09-testing-and-acceptance.md#3-end-to-end-e1e10-on-the-blintz)). Every
  move turns about existing creases, so no trigonometry reaches GLB JSON. E10
  replaces the reopening with a turn carrying the corner on through the centre and
  expects `FlapEndpointOrder`, the refusal the recipe's equivalent already gets
  ([`BlintzSequenceSpec.hs:111-116`](../test/BlintzSequenceSpec.hs#L111-L116)) [code].
- **Budgets are counted work**: sweep intervals (4096 cap), refolds, triangles,
  pairs, stacking guesses, settle triangles. Measured: a `stack test` run matching
  nothing took 19.03, 19.59 and 20.95 s of wall time building fixtures in `runIO`
  (3 runs, loaded M1 Max); `CraneWingSpec` took 1.21–1.25 s and `CheckedBirdSpec`
  12.50–12.52 s by hspec's own timer, which leaves out the `runIO` setup that
  [C99](#changes-since-draft-v2) times
  ([gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md)
  "Measured", "Addendum") [research]. No wall-clock guard is adopted. Owner
  decisions 61 and 64 add one acceptance target timed by hand, not a guard: a
  model's whole run within 10 minutes of wall clock
  ([09 §6.4](09-testing-and-acceptance.md#64-one-models-whole-run-timed)).
- **Where tests run.** New sequence specs build fixtures in `beforeAll` (M2's use
  `runIO`: [C98](#changes-since-draft-v2)); crane-sized fixtures sit under
  `describe "slow"`; the default job runs `--skip /slow/` and a new slow job
  `--match /slow/` (hspec 2.11.12 in the snapshot, appendix command 6 [ran]).
  Existing `runIO` specs stay as they are until their recipe's deletion PR
  ([C71](#changes-since-draft-v2)), except that the slow study spec files move
  into the slow job (below). Three of the `runIO` specs, `CheckedBirdSpec`,
  `CraneWingSpec` and `CheckedPetalSpec`, build nearly all of the fixtures a
  filtered run pays for; whether they may move to `beforeAll` sooner, as an
  exception to C71, is the owner's question on #547 ([C99](#changes-since-draft-v2)).
  A slow job is a fourth check beside today's `test`, `format` and `lint`
  ([`ci.yml`](../.github/workflows/ci.yml), whose `changes` job only decides
  whether they run) [code], and `AGENTS.md:390` requires "all three CI checks".
  Owner decision 12 (decided 2026-10-12) makes the slow job a required check, so
  [§3](#3-recorded-text-this-design-changes) row 15 counts four; the owner lists the
  job in `main`'s branch protection once the PR adding it has merged, since no
  pull request can. That PR also moves into the job, whole, the study spec files
  that hold a test of 10 s or more, an exception to C71
  ([09 §6.3](09-testing-and-acceptance.md#63-beforeall-not-runio-and-a-slow-job)
  items 3 and 5; [C51](#changes-since-draft-v2), [C101](#changes-since-draft-v2)).
- **Angle equality.** Exact for driving parameters, copied literals, endpoints
  pinned by a guard, flap endpoints on whole-number angles, and two outputs of one
  binary; formula-derived angles within 1e-12°, as `RabbitEarSpec.hs:49` and
  `CheckedPetalSpec.hs:146` compare, until the tolerance issue, #546, names one. A
  sample is written as a driving-parameter value, never as a fraction, because
  `175 * (90/175)` is `89.99999999999999`.
- **Migration.** `BlintzSequence` then `HelmetSequence` become sequences, each as an
  equivalence PR then a deletion PR. Their pages are not step pages:
  `checked-blintz.svg` has eleven figures, the open square then each move's halfway
  pose and end ([`BlintzSequence.hs:75-87`](../study/fold-material/BlintzSequence.hs#L75-L87)),
  and `checked-helmet.svg` seven, its first intermediate at 120°
  ([`HelmetSequence.hs:70-86`](../study/fold-material/HelmetSequence.hs#L70-L86))
  [code]. So the equivalence PR rebuilds each page through the recipe's own page
  function from each record's `SweptHinge c`: `flapAt c 0`, `flapAt c 0.5` (or
  `120/180`) and `recordAfter` ([C50](#changes-since-draft-v2)). v2's "the
  figure-per-corner layout reuses `checked-blintz.svg`" could not give eleven
  figures. `CraneWing` waits for M4 (slow job), the bird for M5 and the registry;
  the frog guide, the basic bases and most of `cases.json` stay fixtures.
- **Whole-crane parse and check (M1).** `examples/traditional-crane.foldseq`, 28
  steps from `sheet square` using `repeat`, five `not modelled` moves and one
  `checkpoint`, parses and checks without loading any file; red if either
  constructor is removed. Its senses, seeds and `keeping` pairs are **UNVERIFIED**.

### D17. Third-party and external tools

- **Running an external program and reading its output is not vendoring.** An
  external program here is someone else's code whose answer we rely on: a solver,
  simulator, renderer or validator, or a library that computes what we cite as
  evidence or keep. The tools that build, run, format, lint or manage our own code
  are not, node and python running our own scripts among them, and neither are the
  packages `senbazuru.cabal` lists. Such a program needs a row in
  `docs/related-projects.md` giving its licence *as built*: the terms of the build
  that ran, with everything it links or bundles, since a permissive source can
  link GPL code by default. External solvers are [comparison
  oracles](../docs/glossary.md#this-project), never used in place of our own code,
  and the design-licence rule applies to any pattern fed to one. A user-installed
  GPL or GPL-linked build may be run as an oracle, but nothing GPL enters the tree
  or the library: no vendored GPL code, no GPL code linked into the library, and
  no script here that uses a GPL program's own API, such as Blender's Python API.
  Any output kept as a fixture needs provenance in `examples/README.md`. No CI job
  or test may depend on such a program.
  [H7](research/H7-tooling.md) finding 17 is why a user-installed build linking
  GPL code may run as an oracle. The wording goes to `AGENTS.md` (owner decision
  11, decided 2026-10-12;
  [01 §4.8](01-architecture.md#48-agentsmd-third-party-material) holds it):
  planned for M0, it landed with #550, and the owner scoped it the same day
  (#552, [C100](#changes-since-draft-v2)).
- Origami Simulator (MIT): an oracle through #53, manual or browser-automated.
  ipc-toolkit (MIT source; its PyPI wheel statically links filib, LGPL-2.1): a
  library, not a simulator; a driver is a toolchain decision.
  Codim-IPC: Apache-2.0 source whose default build links GPL CHOLMOD; user-installed
  only. IPC-family tools cannot start from a
  zero-thickness flat stack without a thickness offset
  ([G](research/G-realistic-rendering-and-simulation.md) "B. Geometry models, and
  whether a sequence could feed them", finding 13), so they apply to open states
  only ([gap-study-consumption-contract](research/gap-study-consumption-contract.md)
  "(e) Licences for driving external solvers") [research].
- GPL sources (Doodle GPLv2, Rabbit Ear GPL-3.0, ReferenceFinder GPL-2.0, Creasy
  GPL-3.0, ORIPA GPL-3.0) are ideas only: their code and fixtures are read, never
  copied. Running a user-installed build of one is the first bullet's case.
  Example sequences fold traditional or generated models only.

### D18. Non-goals

- A sequence solver or search over the vocabulary; a general coupled-angle solver
  (#55) as a prerequisite; sliding contact; automatic hold selection; calibrated
  paper; pressure or inflation (#106); wet folding; thickness as geometry.
- Persisting step notes in FOLD, and carrying the sheet's vendor keys through a
  run, both until #73; resolving `frame_inherit` (#102).
- Reading OrigamiBench, FoldingAgent or Learn2Fold id-based programs in v1.
- Recording an `expect refused` outcome in the written sequence file; `--report`
  prints it ([D21](#d21-repeat-checkpoint-not-modelled-expect-refused)).

### D19. Realistic rendering

**Independent axes, honest milestones.**

- **Four fidelity axes**, each output of a new mode recording its position on
  every one, in glTF `extras.senbazuru.fidelity` and in an SVG `<desc>` through a
  new optional `Page.pageDescription`; default outputs and the tracked goldens carry
  none.
  - *Geometry:* rigid panels · bent zero-thickness (settled, [D14](#d14-material-consumption); it names what its solve held that the model leaves free, owner decision 39)
    · thickness offsets (research) · **as read**, for a file senbazuru did not
    produce ([C47](#changes-since-draft-v2)). `export --smooth` of an arbitrary file
    cannot know whether its panels are rigid (`puffed-square.fold` is a hand-made
    dome), so it must not claim either.
    **As prescribed** (owner decision 17, 2026-09-29): a pose built by placing
    vertices rather than by folding or settling paper, a *shape sketch*
    ([11](11-prd-refined-final-forms.md#1-the-paper-screen), R-11-2).
  - *Motion:* static · animated rigid (checked routes) · animated flexible
    (research).
  - *Appearance:* A0 two flat colours (today) · A1 normals split at feature edges ·
    A2a `TEXCOORD_0` from material coordinates · A2b textures (owner decision 6) ·
    A3 diffuse translucency, behind a flag, never in `extensionsRequired`.
  - *Lines:* W0 book notation (today) · W1 exact line drawing of any surface · W2
    x-ray lines and cut-aways (#48, #49).
- **Honesty about rigid sequences.** On planar panels A1's normals equal the flat
  normals viewers already compute; W1's lines are the creases and boundaries today's
  drawing shows. On quarter-fold state 2 the two faces beside edge 9 have normals
  (0, 0, 0.5) and (0, 0, −0.5), Newell's formula at area 1/4
  ([08](08-prd-realistic-rendering.md#what-this-makes-realistic-and-what-it-does-not))
  [prd]; their average is zero, which is why normals and line offsets split at every
  feature edge. For a rigid sequence M7 adds animation, optional texture coordinates
  and optional glTF crease lines, not realistic paper. **No bent paper is reachable
  from the `senbazuru` CLI before M8.**
- **Feature edges** are every edge of the written state whose assignment is not `J`,
  at any angle, boundaries included; not `surfaceFeatures`, which drops `F` at 0.
- **M7a**, the smallest visible deliverable: a GLB mode writing `NORMAL` (per
  smoothing region, connected across `J` edges only, from packed positions) and, for
  `Surface V2` only, `TEXCOORD_0` with `t = 1 − (v − v₀)/S`. **The `1 −` looks like
  a typo:** glTF puts texture coordinate (0, 0) at the image's upper-left corner,
  and the sheet compass puts north at +v. The underside primitive's `NORMAL` is the
  negation of the top's, because both share one `POSITION` accessor and lighting
  reads `NORMAL` as written. Shown on the study's accepted crane-spread and
  wing-bending meshes; free-standing.
- **glTF crease lines are a measured spike before a requirement**: one copy per side,
  offset along that side's own panel normal by a display offset recorded beside
  `frame`, visible-scene exports only; accepted by validator counts, three.js
  screenshots from both sides and a headless Blender import. Fallback: lines as
  data in extras, drawn by the study viewer.
- **W1, an exact line drawing.** Candidates are feature edges, silhouettes and free
  boundaries. A **silhouette** is an edge shared by a face turned away from the reader
  and one that is not, **of any assignment** ([C43](#changes-since-draft-v2)): on
  `puffed-square.fold`, whose 320 edges are 40 `B` and 280 `F` [jq], all 27
  silhouette candidates from `--view front` are shared edges, so `F`, and a rule
  limited to `J` finds none [py]. A face is away when n̂ · forward > 1e-9, edge-on within ±1e-9, the threshold
  `Render.Projected` already uses
  ([`Shadows.hs:92`](../src/Senbazuru/Render/Shadows.hs#L92)) [code]; a band
  of edge-on faces gives one outline, not two (46 edges separate differing classes
  from the front, 27 separate away from not-away [py]). Visibility is exact per
  segment interval: project, clip against each face's projected outline, compare the
  linear depth gap with band τ = `Origami.Contact.panelTolerance` × S; inside the
  band, triangle-level `faceOrders`, closed transitively, decide; unordered ties are
  drawn and their length reported. **The rule that looks like a typo:** faces
  containing a segment's edge never occlude it, because a crease always lies within
  the band of its own faces and would otherwise hide itself. τ is contact's
  tolerance, so a mesh contact accepted draws under the tolerance that accepted it.
- **"Wireframe"** is owner decision 5: `--lines features | mesh`, default `features`;
  `mesh` adds visible `J` edges at the buried-sheet weight.
- **G1, animating checked rigid routes (M7b).**
  - **One node hierarchy per checkpoint interval** ([C44](#changes-since-draft-v2)),
    over that interval's final cut pattern, because a `checkpoint` may remove creases
    and break the prefix rule ([D6](#d6-crease-graphs-grow-between-frames)). Each
    face gets a hinge node (translation a, keyed rotation about b − a by the negated
    fold angle) and a mesh node (translation **−a**, which looks like a typo:
    together they are `rotationAbout a (b − a) (−θ)`, so every translation is
    constant and a crease stays closed between keys). Earlier states key a tree
    crease at the angle of their crease containing it, or 0 before it exists.
  - **The tree comes from the library's own walk** ([C45](#changes-since-draft-v2)).
    `spanningWalk` returns placements, not its tree
    ([`Folding.hs:586-591`](../src/Senbazuru/Origami/Folding.hs#L586-L591)), and
    `Folding` insists on "one spanning walk and not two implementations of it that
    can drift" ([`:342-344`](../src/Senbazuru/Origami/Folding.hs#L342-L344)) [code].
    So `Origami.Folding` exports each face's parent and crossing edge from that walk
    (05 L15, M7b).
  - **Presentation** is a pivot node per presentation move at the D5 axis point,
    keys at most 90° apart. **Re-anchors and `StateOnly` transitions** each start a
    new sub-hierarchy, switched by scale 0/1 under `STEP` interpolation at one key
    time; a rotation channel cannot jump, because sampler times must strictly
    increase.
  - **Keys** come from `recordPoseAt … (PoseOnRoute p)` at `RunSettings.keyDensity`
    n, p = 0, 1/n, …, 1, independent of `sample`. An interval turning any tree
    crease by 180° or more gets its middle p, repeatedly, since slerp between
    opposite quaternions has no defined direction. A pre-crease's route runs out
    and back: its keys go p = 0, 1/n, …, 1 and back to 0, 2n + 1 of them, since
    its `PoseOnRoute 1` is the folded pose and its `PoseAfter`, where the next
    record's keys start, is flat ([D12](#d12-the-text-syntax)).
  - **Midpoint refolds** fold at the per-crease mean of two keys' angles, the pose
    the viewer shows halfway; a failure subdivides, and after
    `RunSettings.keySubdivisionBudget` subdivisions the run refuses. For `SweptHinge`
    routes the mean and the route's midpoint coincide.
  - **The animated scene is complete paper**; no morph targets, skins,
    `KHR_animation_pointer` or `KHR_node_visibility`. #56 closes at M7b.
- **#104** ([C43](#changes-since-draft-v2)). Its first done-when bullet asks that
  `render examples/puffed-square.fold --view iso --hide-flat` draw the dome's
  outline; from `iso` no face of that file turns away, so there is no silhouette to
  draw [py]. Its second bullet already uses `--view front`, where 90 of 200 faces
  turn away [py]. Amended done-when: default render output byte-identical;
  `render examples/puffed-square.fold --view front --hide-flat --lines features`
  draws the visible boundary and silhouette, as a new golden. M7b advances #104
  without closing it.
- **Rejected.** A "rounded crease" availability claim (a second rounded bend over a
  first stretches 200%, `docs/notes/two-bends-need-more-than-radii.md`); fidelity
  inside `frame`; a sidecar metadata file; one flat node per face (#56's approach,
  which opens hinges between keys); skinning; morph targets; silhouettes from `J`
  edges only; point-sampled or raster visibility.
- **Residue.** W1's cost at 4,312 triangles is unmeasured (3–5 compiled runs at 392,
  1,192 and 4,312 triangles before any promise); whether `projectedForm` declines on
  the crane-spread meshes is recorded first, and if not, #206's crane-root mesh is
  the failing case, in the slow job.

### D20. Errors

- **Every new error type has an `Explain` instance in its defining module.** The
  sequence-level problem types all live in `Sequence.Error`
  ([D23](#d23-the-sequence-modules-and-where-run-lives)), which is also where
  `expect refused` finds its kind names. `SettleStepError`, `SettleError`, the
  verdict's `Reason` and the registry's `Refused` get instances too, so `explain`
  stays the one answer to how a refusal is printed.
- **`SequenceError`** (**SKETCH**, [C11](#changes-since-draft-v2)):
  `ParseFailed ParseProblem` · `StaticRefused Place Span StaticProblem`, where
  `data Place = InHeader | InStep Int (Maybe Name)`, because a Haskell-built sequence
  has no location and the step is the only place its author can look ·
  `SheetRefused Span Text SheetProblem` (`SheetHasNoVertices`,
  `SheetAlreadyFolded`) · `ResolveRefused Int (Maybe Name) Span Text ResolveProblem`
  · `StepRefused Int (Maybe Name) Span MoveFailure` · `WriteRefused Int WriteProblem`
  (`WriteMissingAngles`, `WriteNonFiniteAngle`). v2's sketch had no constructor for
  `sheetState`'s or the writer's refusals, and no step on `StaticRefused`. As built
  ([C96](#changes-since-draft-v2)): `SheetRefused` holds a `FilePath`, `ResolveRefused`
  a `Place`, and the writer's non-finite refusal is `WriteNonFinite`, for a material
  coordinate.
- **Message shape.** A `SequenceError` message is "step N (name)", then the author's
  reference as the printer spells it, then the nested `explain` unchanged. It carries
  no location; `sourceLocation :: SequenceError -> Maybe Text` gives `path:line:col`
  (1-based, columns in code points) and `excerpt :: Text -> SequenceError -> Maybe Text`
  gives the caret display, the only multi-line text. The CLI prints
  `senbazuru: PATH:LINE:COL: MESSAGE` then the excerpt, or the message alone, never
  the path twice. `ParseProblem` stores a span, what was found, the expected labels
  and an optional `Hint` as data.
- **Ids in new messages** are written "(internal edge 37)", so an author knows they
  did not write them. **Existing library messages keep their words in v1**, so
  `FlapError` ids reach authors bare; changing them would move pinned test sentences
  and quoted docs, and is a follow-up issue, not part of this design.
- **No command-line word in a library message** ([C25](#changes-since-draft-v2)):
  the flag leak is fixed at the source (05 L6): `ThroughError.LineStopsOnTheModel`
  carries the point given and names the end by it, as
  `FoldError.CreaseEndMeetsNothing` does; `creaseEndFlag` is deleted, its only uses
  being `Query` and `ThroughLayers`
  ([`ThroughLayers.hs:96`](../src/Senbazuru/Origami/ThroughLayers.hs#L96),
  [`:196`](../src/Senbazuru/Origami/ThroughLayers.hs#L196)) [code]. That PR changes
  the sentence at `ThroughLayersSpec.hs:271-275` and the example at
  `docs/usage.md:1652-1658` ([§3](#3-recorded-text-this-design-changes) row 17), and
  lands before M4. `decodeFile`'s `.foldseq` refusal follows the same rule
  ([D13](#d13-the-run-verb-and-io)).
- **Stacking errors split by who can detect them** ([D11](#d11-stacking-choices-are-relations)).
- **The refusal catalogue** is [02 §12](02-language-semantics.md#12-refusal-catalogue),
  corrected by this record: `ZeroDenominator` is a parse `Hint`, not a
  `StaticProblem` ([D12](#d12-the-text-syntax)); `SheetHasNoVertices` and
  `SheetAlreadyFolded` are `SheetProblem`; `RefusalNotRaised` and
  `RefusedDifferently` are `MoveFailure`; `NoRoute` is `PoseError`; the Haskell-only
  `StaticProblem`s of [03](03-prd-embedded-dsl.md#refusals-from-a-built-sequence)
  (`NotANameToken`, `ReservedWordAsName`, `LayerCountNotPositive`,
  `SignNotAllowed`) and `EmptyStep`, `UnfoldChangedSince`, `FlapMovingNotFlat`
  and `FlapMovesBothWays` are added; the last two replaced #344's
  `FlapStationaryNotFlat` in #368 (D5's amendment).
- **Rejected.** Locations inside `explain`; megaparsec's multi-line bundle as the
  message; wrappers rewording nested errors.

### D21. Repeat, checkpoint, not modelled, expect refused

- **`repeat NAME[..NAME] [mirrored across [P, Q] | turned k/4 about P]`.** P and Q
  are exact material points (corners, `centre`, `(u, v)`, `midpoint of` an edge;
  constructions refused); quarter turns only, so mapped points stay `Rational`;
  `turned k/4` is anticlockwise on the sheet as the file draws it (G3); the isometry
  must map the sheet to itself; the bare form is the identity. It maps only material
  references; presentation moves are kept as written; a step containing `model` or
  `top N` is refused. **The check is in material terms:** after the move, its new
  creases must equal the isometry's image of the original's with the same
  assignments, **and** each hinge segment's material image must turn by the same net
  angle change (G4, [C21](#changes-since-draft-v2)); otherwise `RepeatNotSymmetric`.
  G4 closes a hole: on the blintz, `repeat c1 turned 1/4 about centre` adds no crease,
  so creases alone compare nothing; the hinge check maps edge 8's segment
  (1/2, 0)–(1, 1/2) under (x, y) ↦ (1 − y, x) onto edge 9's (1, 1/2)–(1/2, 1) [py],
  and the recipe turns both by −180
  ([`BlintzSequence.hs:51-52`](../study/fold-material/BlintzSequence.hs#L51-L52)) [code]. One figure carries a repeat range; expanded moves get derived names and
  are each checked. There is no `behind` form, since turning and mirroring together
  flip every layer twice.
- **`checkpoint "path" { … }`** replaces the working pattern with a loaded key frame.
  Its angles are read **as `start folded` reads them**, by `foldAnglesOf`: explicit
  angles first, otherwise from assignments ([C18](#changes-since-draft-v2)). v2 said
  "folded from its assignments", which would ignore a checkpoint file's recorded
  angles while `start folded` kept a sheet's; one rule serves both. Intent follows
  [D3](#d3-the-runner-owns-the-state-its-start-and-the-handoffs)'s starting rule;
  the stacking is chosen by a `StackingSpec`; the outline must match the sheet's in
  material coordinates within `Fold.Faces.tolerance`; creases may be added or removed.
  Evidence `StateOnly`; it starts a figure with no inferred motion; its record
  carries the added and removed creases.
- **`not modelled "…"`.** `run --check` accepts it. `runSequence` stops there and
  returns `Right` a `Run` whose `runStop` names the step and the text, with every
  record and state before it ([C10](#changes-since-draft-v2)); `runRefusal :: Run -> Maybe SequenceError`
  gives `StepRefused … NotModelled` for the CLI's message and exit code. v2 said the
  run "still returns and writes the records before it" while typing `runSequence` as
  `Either SequenceError Run`, which returns nothing on `Left`. Other refusals return
  no partial run in v1. The page draws the step's caption on its start state with no
  arrows.
- **`expect refused KIND { move }` is a move inside a step** ([C8](#changes-since-draft-v2)),
  written before the move it contrasts with, so both run against one state. It runs
  the inner move, requires a refusal whose kind is KIND at any nesting depth
  (`RefusalNotRaised` if accepted, `RefusedDifferently` if refused otherwise; a
  refusal with no kind is passed on as itself, and the nesting is of an error in
  another, never of one `expect refused` in another, [owner decisions 49 and
  50](#9-owner-decisions)), leaves
  the state unchanged, and produces **no move record and no state**. Its outcome is
  kept in the `Run`, on its step, and printed by `--report`. A step whose moves are
  all `expect refused` writes no state and is not a figure (G12,
  [D24](#d24-states-figures-and-their-numbers)). v2's crane example put
  `expect refused` at top level after a step, which has no defined state.
- **The crane's expected kind is `FlapCovered`**, **UNVERIFIED**
  ([C9](#changes-since-draft-v2)). The selection rule refuses a stationary face nearer
  on the turning side before `Flap`'s sweep runs
  ([D8](#d8-folding-some-layers)), and the physical reason the crane wing cannot turn
  towards the reader is that wing B lies on its reader side
  ([02 §9](02-language-semantics.md#9-repeat-checkpoint-not-modelled-expect-refused)).
  That wing B lies there is inferred from test assertions
  ([gap-layer-selective-folds](research/gap-layer-selective-folds.md) finding 14).
  `CraneWing` itself gets `FlapEndpointOrder` because it calls `Flap` with no
  selection step.
- **Rejected.** A `RouteEvidence` value for a refusal; `expect refused` at top level;
  a checkpoint rule different from `start folded`'s.

### D22. Figures holding several moves

"Figure" in this decision has [D24](#d24-states-figures-and-their-numbers)'s sense,
one drawn state. A step's moves are all drawn on one figure, the state the step
starts from; that is the figure the heading means.

- **Honesty.** A step's moves run in order, each checked. Their figure draws the
  state before the step's first move, so move k is accepted only if every material
  point of its moving paper is where that drawing shows it, compared by material
  identity; in practice no earlier move of the step left that paper somewhere
  else. Otherwise `MoveLeavesFigure`, with a hint to start a new `step`. A
  pre-crease is one move here, like any other ([D12](#d12-the-text-syntax)), and
  it puts its paper back, so the crane's two diagonal pre-creases share a figure
  although their moving triangles overlap. All four blintz corners in one step
  pass; "fold the corner to the centre, then fold that flap in half" fails.
- **Batching stays inside one step** ([C16](#changes-since-draft-v2)). Consecutive
  moves of one step whose lines resolve on the step's start state share one
  `creaseAllAlongWith` call, because re-cutting is the cost (AGENTS.md "A move that
  changes a pattern"). In the crane opening of [§7](#7-examples), step `diagonals`'
  two diagonals share a batch and step `midlines`' two midlines are another, because
  the step "Turn over." lies between them. A batch across steps would show a later
  step's creases on an earlier figure, the backfill
  [D6](#d6-crease-graphs-grow-between-frames) rejects: counting by D24's rule
  [reasoned; the example is **UNVERIFIED**], `diagonals` is drawn on figure 2, the
  state the diamond step wrote, and one batch with `midlines` would already put the
  midlines on figure 3, the turn-over's figure, before the step that creases them.
  v2's example batched these same two steps across the turn-over, contradicting its
  own "a move after a turn starts a new one". v2 called them steps 1 and 3 because
  it wrote `rotate` at top level ([D12](#d12-the-text-syntax),
  [C14](#changes-since-draft-v2)); [D24](#d24-states-figures-and-their-numbers)
  counts the diamond step, so here they are steps 2 and 4. Batched results equal
  creasing move by move by material identity (edge ids may differ); a batched move's
  `recordBefore` may already show a later move's creases of the same step at 0, and
  each record's `recordNewCreases` still lists only its own.
- **`unfold NAME…`** reverses the named steps' net angle changes, last move first,
  reusing each move's recorded material hinge and seed; a move whose hinge creases
  are all at 0 now is skipped, which covers every pre-crease. If a later move
  changed one of those creases, the unfold is refused as `UnfoldChangedSince`, naming
  the crease (G5). `unfold c1` on the blintz takes edge 8 from −180 to 0.
- **Names and evidence.** `unfold` and `repeat` name steps (`unfold c1`, §7's
  blintz); `sample` belongs to a macro move; `settle` to the step's last moving
  record; a step's state carries the weakest evidence of its moves
  ([D10](#d10-assurance-as-evidence-values)).

### D23. The Sequence modules and where Run lives

- **What.** `Sequence.*` is layered inside its family, with no cycles
  ([C3](#changes-since-draft-v2)):

  | Level | Modules | Holds |
  | --- | --- | --- |
  | 1 | `Sequence.Syntax` | the tree (including `RefusalKind`, which `ExpectRefused` holds), spans, `canonical`, `stripSpans`, `sourceFiles` |
  | 2 | `Sequence.Error` | `SequenceError` and every sequence-level problem type with its `Explain` instance; the catalogue of kinds a `RefusalKind` may name; `sourceLocation`, `excerpt` |
  | 3 | `Sequence.Build`, `Sequence.Parse`, `Sequence.Pretty`, `Sequence.Check`, `Sequence.Elaborate` | the front ends and the static passes |
  | 4 | `Sequence.Record` | `RouteEvidence`, `MoveRecord` with `hingeTurn` and `recordAngles`, `MaterialPoint` and `MaterialSegment` (until an error at level 2 needs them, [C75](#changes-since-draft-v2)), `MacroBinding`, `recordPoseAt`, `Run`, `writtenStates`, `runRefusal`, `renderRunReport`; re-exports `RoutePose` |
  | 5 | `Sequence.Run` | `FoldState`, `sheetState`, `RunSettings`, `runSequence` |
  | 6 | `Sequence.Write`, `Sequence.RunPlan`, `Sequence.Material` | the file writer, the flag rules, the settle consumer |

  Built besides at M2 ([C96](#changes-since-draft-v2)): `Sequence.Resolve` at level 5
  beside `Sequence.Run`, and `Sequence.SheetLengths` below `Sequence.Record`;
  `docs/architecture.md` keeps the module map.

- **`Run` is defined in `Sequence.Record`**, and it holds what a reader of a run
  needs: the start state (surface and display), every record, each step's outcome
  (name, caption, which records, authored samples, expected refusals), the closing
  caption and the stop, if any. **It does not hold `FoldState`.** (Built: expected
  refusals are the run's, each with its step, [C96](#changes-since-draft-v2).)
- **`writtenStates :: Run -> Either WriteProblem [WrittenState]`** (built: `Either SequenceError`,
  [C77](#changes-since-draft-v2)) applies the state
  rule and the displays once, and both `Sequence.Write` and
  `Render.Sequence.stepNotes` call it, so "the page draws exactly the frames the file
  holds" (R-06-20) holds by construction rather than by a test.
- **Why.** Renderers may import one sequence module
  ([01 §1.2](01-architecture.md#12-rules) rule 4), and `stepNotes :: Run -> …`
  needs `Run` (R-06-20); `Sequence.Record` cannot import `Sequence.Run`, which
  imports it. v2's sketch defined `Run` in `Sequence.Run`. 01's note proposed moving
  `Run` with the abstract final `FoldState` into `Sequence.Record`; nothing that
  reads a run needs the working pattern, and a renderer able to reach it is a
  renderer able to depend on it. `SequenceError` sits at level 2 because
  `parseSequence`, `checkSequence` and `runSequence` all return it, and `MoveFailure`
  wraps only library errors and level-2 types.
- **Rejected.** `Run` in `Sequence.Run`; `FoldState` in `Sequence.Record`; an
  `.Internal` module exporting constructors, which the repository has no precedent
  for (`find src -path '*Internal*'` finds nothing [ran]); `Render.*` importing
  `Sequence.Write`.
- **Residue.** `stepNotes` returns `Either WriteProblem [(Frame, StepNote)]`, where
  v2 and 06 had it total, because it shares `writtenStates`' refusals.

### D24. States, figures and their numbers

**Concrete first.** The quarter-fold source has two steps. Its sequence file has a
metadata-only key frame and three states: `file_frames[0]` the flat sheet, `[1]`
after step `half`, `[2]` after step `quarter`. `run -o q.glb --frame 2` picks the
state after `half`. The page has three figures; figure 1 draws the sheet with step
`half`'s caption and mountain arrow, figure 2 the half-folded state with step
`quarter`'s caption and valley arrow, figure 3 the result with the `closing` caption.

- **A state** is one `file_frames` entry, numbered from 0 by its index. State 0 is
  the start. In prose "state k" always means `file_frames[k]` of the written file
  ([C59](#changes-since-draft-v2)); 02 numbered the same states from 1 and is to be
  corrected.
- **What a step writes.** In order, its authored `sample` poses (parameter order),
  then its end state. A step whose moves are all `expect refused` writes nothing
  (G12). A step with no move other than `let` is refused statically as `EmptyStep`.
- **Figures** are states: figure j draws state j − 1, numbered from 1 as `Layout`
  numbers figures.
- **Captions and arrows go on the state a step starts from.** So a state's
  `frame_title` is the caption of the next step that writes a state, and the last
  state's is `closing`. Sample states carry no caption and no arrows.
- **Step numbers** in messages, reports and `recordStep` count steps in source
  order from 1, including steps that write nothing. A figure number and a step
  number differ once any step writes samples or nothing, which is why messages say
  "step N (name)" and never "figure N".
- **`--frame N`** on any verb selects state N − 1, because frame 0 is the key frame
  ([D13](#d13-the-run-verb-and-io)).
- **Why.** 01, 06 and 09 counted states from 0, 02 from 1, and `--frame` from 1
  with the key frame at 0; v2 said only "`--frame N` counts states from 1". Samples
  written as states but left off the page would break the frames-equal-notes rule
  ([D23](#d23-the-sequence-modules-and-where-run-lives)). The glossary's *sequence
  file* row counted one entry per step and forgot state 0
  ([C63](#changes-since-draft-v2)); 03's A-6 (six states for the five-step blintz)
  was right.
- **Rejected.** States numbered from 1 in prose; samples in the file but not on the
  page; an empty figure for an `expect refused`-only step.

---

## 5. Type sketch

**SKETCH.** Names every PRD uses. Fields and constructors changed since v2 are
listed in [the changes table](#changes-since-draft-v2). A line built otherwise
carries a trailing `-- built:` note citing its changes row, and the PR that builds
it adds the note; a line with no note is as sketched, built or not.

```haskell
-- Senbazuru.Sequence.Syntax
data Span = Span !FilePath !Int !Int !Int !Int | NoSpan
data Located a = Located { locSpan :: !Span, locValue :: !a }
newtype Name = Name Text                                         -- IsString
newtype RefusalKind = RefusalKind Text

data Compass = North | East | South | West
data Corner = SouthWest | SouthEast | NorthEast | NorthWest
data Sense = ValleyFold | MountainFold                           -- as seen from the reader's side
data PageAxis = LeftRight | TopBottom
data Turning = Clockwise | Anticlockwise
data Side = ColouredUp | WhiteUp

data Point
  = CornerOf Corner | Centre | AtSheet Rational Rational
  | MidpointOf Point Point | MidpointOfEdge Compass | FractionAlong Rational Point Point
  | Meet Line Line | EndOfCreaseOf Name Point | PointNamed Name
data Line
  = EdgeOf Compass | Segment Point Point                         -- O1
  | Onto Point Point                                             -- O2
  | LineOnto Line Line (Maybe Point)                             -- O3 (+ nearest)
  | PerpendicularThrough Line Point                              -- O4
  | PointToLineThrough Point Line Point (Maybe Point)            -- O5
  | TwoToTwo Point Line Point Line (Maybe Point)                 -- O6
  | PointToLinePerpendicular Point Line Line                     -- O7
  | PointToLine Point Line                                       -- P to L
  | ExistingCrease Point Point | HingeOf Name | CreaseOf Name
  | ModelSegment (Rational, Rational) (Rational, Rational) | LineNamed Name
data Layers = FlapOfFirstArgument | AllLayers | TopLayers Int | TopFlap
data Amount = ToFlat | Degrees Rational
data Relation = LayerAbove Point Point                           -- as seen from the reader's side
data StackingSpec = Relations [Relation] | StackingFirst

data Move
  = Fold Sense Amount Line Layers (Maybe Point)                  -- optional `moving P`
  | FoldAndUnfold Sense Line Layers (Maybe Point)                -- no amount
  | Unfold [Name] | TurnOver PageAxis | Rotate Int Turning       -- k eighths
  | Anchor Point | Mark Name Point (Maybe Point) | Let Name Binding
  | Macro MacroCall [Rational] | Continue Name Rational | Together [Located Move]
  | Pose [(Point, Point, Rational)]
  | Repeat Name (Maybe Name) (Maybe Isometry)
  | Checkpoint FilePath StackingSpec
  | NotModelled Text | ExpectRefused RefusalKind Move
data MacroCall = Collapse Point (Maybe (Point, Point)) Rational | RabbitEar Point Rational | Petal PetalTip Rational
data PetalTip = TipAt Point | TopFlapTip
data Isometry = MirroredAcross Point Point | TurnedQuarters Int Point
data Binding = BindPoint Point | BindLine Line

data Step = Step { stepName :: Maybe Name, stepCaption :: Maybe Text
                 , stepMoves :: [Located Move], stepSettle :: Maybe SettleRequest }
data Start = StartFlat | StartFolded StackingSpec
data SheetSource = UnitSquare | SheetFile FilePath
data Header = Header { hTitle :: Maybe Text, hSheet :: Located SheetSource, hAnchor :: Maybe (Located Point)
                     , hSide :: Side, hStart :: Located Start, hMaterial :: Maybe (Located MaterialSpec)
                     , hClosing :: Maybe Text }                  -- written after the last step
data Sequence = Sequence { seqHeader :: Header, seqSteps :: [Located Step] }
canonical, stripSpans :: Sequence -> Sequence

-- Senbazuru.Sequence.Build
newtype Build a = Build (State BuildState a)                     -- Functor, Applicative, Monad only
newtype Moves a = Moves (State MoveState a)                      -- a step's body
type Ref :: Type -> Type
newtype Ref k = Ref Name                                         -- constructor hidden; k: PointK | LineK | StepK
sequenceOf :: Header -> Build () -> Sequence
step :: Name -> Text -> Moves () -> Build (Ref StepK)            -- and step_, stepUncaptioned, stepReturning
move :: Move -> Moves ()
valley, mountain, inFront, behind :: Sense
above :: Point -> Point -> Relation

-- Senbazuru.Sequence.Error
data SequenceError
  = ParseFailed ParseProblem
  | StaticRefused Place Span StaticProblem
  | SheetRefused Span Text SheetProblem                          -- the sheet path as written; built: FilePath for Text, "square" for `sheet square`, and the CLI gives an unreadable checkpoint's path the same way (C96)
  | ResolveRefused Int (Maybe Name) Span Text ResolveProblem    -- built: Place for Int (Maybe Name), as StaticRefused has, so a refused anchor in the header names the header (C96)
  | StepRefused Int (Maybe Name) Span MoveFailure
  | WriteRefused Int WriteProblem                                -- the state number
data Place = InHeader | InStep Int (Maybe Name)
data ParseProblem = ParseProblem { problemSpan :: Span, problemFound :: Found
                                 , problemExpected :: [Text], problemHint :: Maybe Hint }
data MoveFailure
  = Selecting SelectionError | Binding MacroBindError | ChoosingStacking StackingChoiceError
  | FlapRefused FlapError | ThroughRefused ThroughError | FoldingRefused FoldingError | MacroRefused MacroError
  | ReanchorNotFlat MaterialPoint | JoinBroken Text | MoveLeavesFigure MaterialPoint
  | RepeatNotSymmetric MaterialSegment | CheckpointOutlineDiffers MaterialPoint | UnfoldChangedSince MaterialSegment
  | NotModelled Text | RefusalNotRaised RefusalKind | RefusedDifferently RefusalKind RefusalKind
  | NotAProperRotation Double                                     -- built: NotModelled as NotModelledStop (C76); NotAProperRotation as PresentationImproper (C81), dropped (C95)
                                                                 -- built: ReanchorNotFlat V2 Double, the new anchor in sheet lengths and its face's tilt in degrees; UnfoldChangedSince
                                                                 -- EdgeId; added: CreasingRefused FoldError, MoveNotRunYet Text (C96). Not built yet: ThroughRefused, which will clash
                                                                 -- with Origami.ThroughLayers' constructor of that name, as NotModelled did (C76)
sourceLocation :: SequenceError -> Maybe Text
excerpt :: Text -> SequenceError -> Maybe Text

-- Senbazuru.Sequence.Parse / Pretty / Check / Elaborate
parseSequence :: FilePath -> Text -> Either SequenceError Sequence
prettySequence :: Sequence -> Text
checkSequence :: Sequence -> Either SequenceError Checked
elaborate :: Checked -> Elaborated

-- Senbazuru.Sequence.Record
data RouteEvidence = NoMotion | Presented | StateOnly | Sampled CheckedMacro SampleReport | SweptHinge CheckedFlap
                                                                 -- built: SweptHinge (#486), Presented (C81) and NoMotion (C84)
data PoseRef = PoseBefore | PoseAfter | PoseOnRoute Rational
data PoseError = NoRoute RouteEvidence | PoseFlap FlapError | PoseMacro MacroError
recordPoseAt :: MoveRecord -> PoseRef -> Either PoseError RoutePose   -- RoutePose from Origami.Route
newtype MaterialPoint = MaterialPoint V2                          -- built (#486); moves below Sequence.Error with the first
data MaterialSegment = MaterialSegment MaterialPoint MaterialPoint -- MoveFailure that names one, since level 2 cannot import level 4;
                                                                 -- no built MoveFailure holds one yet: ReanchorNotFlat holds a V2 (C96)
data MoveRecord = MoveRecord                                     -- opaque: constructor hidden, each field read through a function of its name (C75)
  -- built at M2 for a turn about a hinge (#486, #487):
  { recordStep :: Int, recordMoveIndex :: Int, recordStepName :: Maybe Name, recordCaption :: Maybe Text
  , recordOrigin :: Origin                                        -- the move as written, and its span
  , recordBefore, recordAfter :: Surface V2                      -- unpresented; one numbering
  , recordEvidence :: RouteEvidence
  , recordHinge :: [(MaterialSegment, [EdgeId])], recordMoving :: [(MaterialPoint, [FaceId])]
  , recordStationary :: FaceId                                    -- a Maybe once a move holds nothing still
  -- each with the first move that fills it:
  , recordKind :: MoveKind                                        -- built (C80)
  , recordPresentation, recordPlacement :: (Rigid, Rigid)        -- before, after; built (C81, C83). A record's two placements are equal:
                                                                 -- a move re-anchors before it turns, so a new placement shows only between records,
                                                                 -- though recordAnchor's pair does show the anchor moving
  , recordNewCreases :: [(MaterialSegment, [EdgeId], Assignment)] -- U for a pre-crease's; built (C79, C80)
  , recordStacking :: Maybe StackingChoice
  , recordAnchor :: (MaterialPoint, MaterialPoint)                -- before, after; built (C79, C83, C84)
  , recordResolved :: [ResolvedReference], recordMacros :: [MacroBinding], recordCost :: StepCost }
                                                                 -- built: recordResolved (C78), recordCost (C89)
  deriving stock (Eq, Show)
recordAngles :: MoveRecord -> ([Double], [Double])               -- read from the two surfaces, not stored
hingeTurn :: Int -> Int -> Maybe Name -> Maybe Text -> Origin
          -> [(MaterialSegment, [EdgeId])] -> MaterialPoint -> CheckedFlap -> Either FlapError MoveRecord
                                                                 -- built with more arguments: after the hinge, the new creases (C79), the anchor as one (before, after) pair,
                                                                 -- the presentation and the placement; after the seed, the resolved references (C96). Built also:
                                                                 -- asPrecrease (C80), presented (C81), anchoring (C84) and addRefolds (C89)
data MoveKind = Precrease | …                                     -- owner decision 14; no sense, since its crease has none; the rest with the MoveRecord agreement
                                                                 -- built: Turn | Precrease | Presentation Presenting | Anchoring (C80, C81, C82, C84)
displayBefore, displayAfter :: MoveRecord -> Rigid                -- presentation `after` placement
data MacroBinding = MacroBinding { bindLine :: Name, bindMacro :: MacroName, bindRoles :: [(Role, MaterialSegment)]
                                 , bindBranch :: Branch, bindDisambiguator :: Maybe ResolvedReference, bindReached :: Rational }
data Run = Run { runStart :: StateView, runSteps :: [StepOutcome], runRecords :: [MoveRecord]
               , runClosing :: Maybe Text, runStop :: Maybe (Int, Maybe Name, Text) }
                                                                 -- built: runTitle, runStart :: Surface V2, runStartPresentation (C81), runSteps :: [StepOutcome], runRecords,
                                                                 -- runExpected, the run's expected refusals, each with its step (D21, C96), runClosing, runStop :: Maybe RunStop
                                                                 -- (C76, C77); each StepOutcome also holds its presentation (C81) and its placement (C96)
writtenStates :: Run -> Either WriteProblem [WrittenState]       -- built: Either SequenceError, WriteRefused k (C77)
runRefusal :: Run -> Maybe SequenceError
renderRunReport :: Run -> [Text]

-- Senbazuru.Sequence.Run
data RunSettings = RunSettings { sweep :: SweepSettings, nearMissBand :: Rational, keyDensity :: Int
                               , keySubdivisionBudget :: Int, macroChecks :: Int }
                                                                 -- built: RunSettings { runSweep, runNearMissBand :: Double, runBudget :: Budget }; the key settings wait
                                                                 -- for M7b's animated export, and macroChecks for M5's macros (C96)
data FoldState                                                   -- abstract
sheetState :: SheetStart -> Frame -> Either SheetProblem FoldState
                                                                 -- built: FoldFile -> Either SheetProblem FoldState (C96)
runSequence :: Budget -> RunSettings -> Map FilePath Frame -> Elaborated -> Either SequenceError Run
                                                                 -- built: RunSettings -> Map FilePath FoldFile -> Elaborated -> Either SequenceError Run, the budget in
                                                                 -- RunSettings (C96)

-- Senbazuru.Sequence.Write, Render.Sequence
writeSequence :: FileHeader -> Run -> Either SequenceError FoldFile
stepNotes :: Run -> Either WriteProblem [(Frame, StepNote)]

-- Senbazuru.Sequence.Material (study until M8), Material.Settle (M8)
data SettleSpec = SettleSpec { refinement :: (SettleRegion, Int), stiffness :: Bending, rest :: RestAngles
                             , holds :: [SettleRegion], grips :: [(SettleRegion, GripTarget)], budget :: Settings }
data RestAngles = RestAtPose PoseRef | RestAtPoseExcept PoseRef [(CreaseLine, Rational)]
settleStep :: SettleSpec -> MoveRecord -> Either SettleStepError Settled
data SettleStepError = SettleOnNoMove | SettleStartNotFlat VertexId Double | SettleNoPose PoseRef | SettleNoRest
                     | NoDifference | EmptyRegion Text | AmbiguousLayer | ConflictingTargets | GripOutOfRange
                     | UnitMismatch | TriangleBudget Int | SettleFailed SettleError
data Settled = Settled { settledSurface :: Surface V2, settledReport :: SettleReport, settledVerdict :: Verdict }
data Verdict = Accepted | Diagnostic [Reason]
settle :: SettleInput -> Surface V2 -> Either SettleError Settled

-- Library additions (05; L14 and L15 are new)
atRest :: Double                                                 -- Fold.Query, 1e-10 degrees
assignmentAtRest :: Assignment -> Double -> Assignment
creaseAllAlongWith :: NewCreaseAngle -> [(V2, V2, Assignment)] -> Frame -> Either FoldError (Frame, [[EdgeId]])
isProperRotation :: Mat3 -> Bool; fitRigid :: [(V3, V3)] -> Maybe Rigid   -- built: also rigidFrom, translation; Rigid's constructor hidden (C95)
flapStationaryFace :: CheckedFlap -> FaceId
flapPoseAt :: CheckedFlap -> Double -> Either FlapError RoutePose
data Toward = TowardPlusZ | TowardMinusZ                         -- L14 (#344, #368), with Eq on FlapMotion and CheckedFlap; read from the moving faces
prepareFlapToward :: [EdgeId] -> FaceId -> Double -> Toward -> Folded -> Either FlapError FlapMotion
motionsAcross :: Frame -> Frame -> Either FoldError [Motion]
creasesToCome :: Frame -> Frame -> Either FoldError [(EdgeId, V3, V3)]
creaseLayersThrough :: NewCreaseAngle -> [(Set FaceId, V2, V2, Assignment)] -> Folded -> Either ThroughError Creased
stackingWhere :: Budget -> [(FaceId, FaceId)] -> Frame -> Either StackingError Stackings
macroPoseAt :: CheckedMacro -> Rational -> Either MacroError RoutePose
foldedWalk :: Folded -> IntMap (FaceId, EdgeId)                  -- L15: each face's parent and crossing edge
```

## 6. Grammar

[04](04-prd-sequence-source-and-cli.md#grammar) owns the EBNF, the lexical table,
the reserved words, the ambiguity table and the printer rules; nothing here repeats
them. That grammar already carries this record's syntax decisions
([D12](#d12-the-text-syntax)): `closing` after the last step, optional captions,
a pre-crease with no angle, `midpoint of edge S`, `stacking first` alone in its
block, `expect refused` as a move inside a step, string escapes, `n/0` as a parse
error, reserved words never names. Three corrections are 04's to make:

1. `settleitem`'s `"refine" sideword INTEGER` becomes `"refine" region INTEGER`
   ([D14](#d14-material-consumption)); a region never starts with an integer, so the
   count still ends it.
2. The static check `EmptyStep` for a step with no move other than `let`
   ([D24](#d24-states-figures-and-their-numbers)); the grammar itself still parses an
   empty block.
3. The mapping table's `Fold Valley …`, `Fold Mountain …` and `Above A B` become
   `ValleyFold`, `MountainFold` and `LayerAbove` ([D1](#d1-one-first-order-syntax-tree-built-by-name-only-builders)).

## 7. Examples

Every example is checked against its fixture by a cited command, or marked
**UNVERIFIED**. The files named own the full walk-throughs; the sources below are
the versions those files are to carry.

**Quarter fold** ([D16](#d16-testing-and-acceptance) test 1; walked through in
[01 §5](01-architecture.md#5-one-move-end-to-end-quarter-fold-step-2) and
[02 §1](02-language-semantics.md#1-one-run-walked-through)):

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

Facts ([01 §5.10](01-architecture.md#510-commands-behind-the-numbers)) [prd]: face
`[8,4,1,5]` never moves; step 1 moves vertices 0, 3 and 7, step 2 moves 2, 3 and 6;
edges 8–11 read 0, 0, 0, 0 in the key frame, −180, 0, −180, 0 after `half`, and
−180, 180, −180, −180 after `quarter`. **Edge 11 at −180 under a valley step is not
a typo** ([D5](#d5-presentation-and-the-readers-side)).

**Blintz** (M2 migration; [00](00-overview.md#the-problem-in-one-example),
[04](04-prd-sequence-source-and-cli.md#example-sources-checked-against-their-fixtures)):

```text
foldseq 1
title "Blintz base, then reopen one corner"
sheet "examples/blintz-base.fold"
anchor centre              # a region: strictly inside the traced central square

step c1 "Fold the south-east corner behind, to the centre." { fold behind corner south-east to centre }
step "Fold the north-east corner behind, to the centre." { fold behind corner north-east to centre }
step "Fold the north-west corner behind, to the centre." { fold behind corner north-west to centre }
step "Fold the south-west corner behind, to the centre." { fold behind corner south-west to centre }
step "Reopen the first corner." { unfold c1 }
```

Facts [py]: the lines taking the south-east, north-east, north-west and south-west
corners to the centre contain exactly edges 8, 9, 10 and 11, the recipe's order, so
no move creases; the centre is not a vertex. The file stores those edges at −180,
which plain `sheet` zeroes. The direction is owner decision 8. The same sequence in
Haskell (**SKETCH**, [03](03-prd-embedded-dsl.md#the-value-first-the-blintz)):

```haskell
blintz :: Sequence
blintz = sequenceOf (header "Blintz base, then reopen one corner" (sheetFile "examples/blintz-base.fold") (Just centre)) $ do
  c1 <- step "c1" "Fold the south-east corner behind, to the centre." $ fold mountain (cornerOf SouthEast `onto` centre)
  forM_ [(NorthEast, "north-east"), (NorthWest, "north-west"), (SouthWest, "south-west")] $ \(c, word) ->
    step_ ("Fold the " <> word <> " corner behind, to the centre.") $ fold mountain (cornerOf c `onto` centre)
  step_ "Reopen the first corner." $ unfold [c1]
```

**Bird base** (M5; [04](04-prd-sequence-source-and-cli.md#example-sources-checked-against-their-fixtures)).
Step names avoid reserved words:

```text
foldseq 1
title "Bird base"
sheet "examples/bird-base.fold"
anchor (29/50, 2/5)

step square-base "Collapse into a square base." {
  collapse at centre until 180° sample 30° 60° 90° 120° 150° 175°
}
step first-petal "Petal fold the front flap up." { petal tip corner south-east until 175° }
step second-petal "Petal fold the back flap behind." { petal tip corner north-west until 175° }
step "Press both petals flat." {
  together { continue first-petal until 180°; continue second-petal until 180° }
}
```

Facts ([04](04-prd-sequence-source-and-cli.md#example-sources-checked-against-their-fixtures),
[02 §8](02-language-semantics.md#8-macro-moves)) [prd]: `centre` is vertex 8; corner
south-east is joined to both ends of hinge 26 and corner north-west to both ends of
hinge 27; the anchor is 0.0798 from the nearest crease. **UNVERIFIED:** the
`continue` bindings and the sample poses. This is the certificate's route, not a
book's petal-turn-over-repeat route.

**Crane wing** (M4 and M6; replaces v2's and 04's versions, [C9](#changes-since-draft-v2),
[C41](#changes-since-draft-v2)). It folds the wing about its
[root](../docs/glossary.md#origami), where owner decision 42 (decided 2026-10-13) moves it,
naming the root by owner decision 43's construction. Its `material` line and `settle`
block were written for the fold at folded y = 1/4, where a band's ends, measured from
the hinge, select the study's pins; at the root they would not. So they are not here:
[07](07-prd-material-consumption.md#naming-holds-and-grips) keeps them with that
fold until #560 re-derives them at the root, before M6 ([§10](#10-corrections) item 43).

```text
foldseq 1
title "Lower one crane wing"
sheet "examples/crane.fold"
anchor (19/20, 1/3)        # strictly inside face 0
start folded {
  layers (1/4, 1/5) above (3/8, 5/9)     # UNVERIFIED: must leave exactly the tail-tucked stacking
  layers (4/9, 3/8) above (1/4, 1/5)
}

step wing "Fold the underneath wing away from you until it stands straight out." {
  let wing-root = perpendicular to [corner north-west, midpoint of edge north] through corner north-east
  expect refused FlapCovered { fold in front 90° wing-root moving corner north-west }   # UNVERIFIED kind
  fold behind 90° wing-root moving corner north-west
}
```

Facts ([02 §6.3](02-language-semantics.md#63-which-layers), check C and check P)
[prd]: the anchor and the three relation points each lie strictly inside one face
(0, 10, 27, 29). **On the flat sheet, the line at right angles to
[corner north-west, midpoint of edge north] through corner north-east would be the
sheet's east edge,** since all three lie on edge north. A construction is worked out
where the paper lies now ([02 §4.3](02-language-semantics.md#43-lines)), and on the
folded crane they lie elsewhere. Corner north-west is vertex 2 and the midpoint of edge
north vertex 28, which the Python re-implementation folds to (1, 4.6e-14) and (1, 0.5),
so the line through them is x = 1. Corner north-east, the tip of the crane's head, is
vertex 57, folded to (0.646447, 0.375849), and the line through it at right angles to
x = 1 is the wing's root, folded y = 1 − (√2/4)(1 + 2 sin 22.5°)
([C102](#changes-since-draft-v2), [C104](#changes-since-draft-v2)). It crosses 40 faces.
The flap containing corner north-west is faces 2, 3, 6, 7, 32, 34, 35 and 38: the wing's
four faces, and the four triangles folded inside it between its widest point and its
root, which cutting along the line leaves joined to them. That flap rests on Python, not
senbazuru. **The valley at 90° being refused while the mountain is accepted is not a
sign slip:** the moving face beside the first hinge segment shows its back, so the
accepted `behind` is +90 in FOLD terms ([D5](#d5-presentation-and-the-readers-side)). On
the study's wing built at its root without the join, that face, 44, and the face held
beside it are the halves of one face the crease cuts, and 44 lies face down; the build
accepts +90 and refuses −90, and +90 turns the wing's tip from z = 0 to z = −0.376,
away from the reader (appendix command 16) [ran].

**Crane opening from a square** (M5; **UNVERIFIED** throughout, [C14](#changes-since-draft-v2)):

```text
foldseq 1
title "Crane: square base"
sheet square

step "Start with the square as a diamond, coloured side up." { rotate 1/8 turn anticlockwise }
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

The diamond start is a step because no move may sit in the header; owner decision
10's alternative is `sheet square as diamond`. With no `anchor` line, the default
anchor (1/2, 1/2) lies on the first diagonal, so the runner moves it by
[D3](#d3-the-runner-owns-the-state-its-start-and-the-handoffs)'s rule for an anchor
a new crease passes through. The senses and which pair `keeping` must name are
derived at M5 with the runner; the four `keeping` candidates are the refusal test.

## 8. Milestones

| M | Name | Contents | Closes / advances |
| --- | --- | --- | --- |
| M0 | Decisions on record | [§3](#3-recorded-text-this-design-changes) rows 1–10 and 16; `docs/notes/sequences.md`; glossary rows moved in; the issues of [§10](#10-corrections) filed | amends #60, #95, #97, #111, #36, #94, #104, #114, #56, #64, #96 |
| M1 | Language without geometry | `Sequence.Syntax`, `Error`, `Build`, `Parse`, `Pretty`, `Check`, `Elaborate`; `Fold.Load.readSequenceText`; the `decodeFile` refusal; `Sequence.RunPlan` for `--check`; `run --check`; round-trip property; whole-crane parse-and-check test; row 2 | advances #60 |
| M2 | Rigid runner on flat states and existing creases | `sheetState`; references on flat states; `fold`, `unfold`, `pre-crease` along constructions on the flat sheet and along existing creases of flat-folded states; 05 L1 (`atRest`), L2 (`creaseAllAlongWith`), L3 (`fitRigid`, some-vertex classification), L4's `flapStationaryFace` (`Origami.Route` with its producer instead, C90), L14 (`prepareFlapToward`, `Eq`); presentation; anchors; `Sequence.Record` with `writtenStates`; the writer; `run -o .fold`, `.glb`; `--report`; `expect refused`; `not modelled`; the bird arrows golden pinned before L3; blintz and helmet equivalence; quarter-fold test 1; E1–E6, E8–E10; rows 11, 12 (`runSequence`), 13 | closes #95, #97; advances #60; #58 item 3 |
| M3 | Step pages that read like a book | `StepNote`, `stepPageWith`, arrow heads, `Symbol`, captions, 05 L5 (`motionsAcross`, `creasesToCome`), steps of several moves, marks, fanned layers (owner decisions 65 and 66); `run -o .svg`; E7; row 12 (`stepPageWith`) | closes #36, #94; advances #48 |
| M4 | Folding some layers | 05 L6 (before the runner wraps `ThroughError`), L7–L12; selectors; `stackingWhere`; `start folded`, `checkpoint`, `repeat`; the slow job, with the slow study spec files moved into it, and the crane-wing prefix in it, at the wing's root (owner decision 42, decided 2026-10-13; #560), compared as 09 §9's `CraneWing` row says (owner decisions 43, 44, 47 and 48; C104 to C107); quarter-fold test 2 and its page; rows 15, 17, 18 | closes #60; advances #54; revisits #70; related #110 |
| M5 | Coupled macros | collapse with `keeping`, rabbit ear, petal, `continue`, `together`, `sample`, `pose`; 05 L13 (`CheckedMacro`, `macroPoseAt`); the study's certificate registry; bird route; crane opening | advances #54, #61; #55 unblocked, not required |
| M6 | Study consumes records | `Sequence.Material` in the study; `settle` and `material` blocks; settled illustrations and failure scope; crane spreading re-expressed, pin-set equivalence first; `senbazuru-material-study --sequence SOURCE DIR`; 05 L4's `flapPoseAt` here or at M7b, with its first consumer | advances #195; #114 rewritten |
| M7a | Realistic GLB mode on existing meshes | A1 normals, A2a texture coordinates, fidelity metadata, `Page.pageDescription`; shown on the crane-spread and wing-bending study meshes | first visible realism |
| M7b | Motion and lines | G1 animation (`SweptHinge` routes, `Sampled` after M5); 05 L15 (`foldedWalk`); W1 line drawing; `--lines`; glTF crease-line spike | closes #56; advances #104, #48 |
| M8 | Graduation | [D15](#d15-graduation-from-study-to-library)'s seven stages; `run --settle`; `--allow-unsettled` | #106 later |
| R | Research | thickness offsets and crease radii at vertices; unheld equilibrium; calibration; exact contact at scale; springback rest angles; animated flexible routes | #114, #106, #64 |

**Order.**

- M1 → M2 → M3 and M2 → M4; M5 needs both M3 (macro figures get note rules) and M4
  (a macro landing flat needs stacking relations); M4 → M6 → M8; M2 → M7b; M7a has
  no edges.
- Row 2 merges no later than M1's `Sequence.Parse` PR.
- `Fold.Query.atRest` and #111's table amendment land before M2's writer.
- 05 L6 lands before M4's runner wraps `ThroughError`.
- Quarter-fold test 2 needs M3's `motionsAcross` and M4's `creaseLayersThrough`, so
  #60 closes in M4's last PR, after M3 has merged ([C54](#changes-since-draft-v2)).

## 9. Owner decisions

Numbered as every PRD's open questions cite them. Each has a recommended default,
and each has to be decided before the milestone named. This section and 10 §6 are
the record of which are decided: PRDs 00, 02, 03, 04, 06, 08 and 09 still give some
decided ones as open. Decisions 15–25 come from
[PRD 11](11-prd-refined-final-forms.md#open-questions-for-the-owner), whose milestones are F0–F7.
Decisions 26–28 were raised while scoping #410, PRD 11's paper screen, decision 29
by its wing galleries (#447), decisions 30 and 31 by #446 and #449, decisions
32, 33 and 38 by #453, decisions 34 to 37 by #455, decision 39 by #474,
decision 40 by the code review of #493, decision 41 by #507, decision 42 by the
code review of #557, decisions 43 to 48 by #560, decisions 49 and 50 by #580,
decision 51 by the code review of #588, decision 52 by #591, decision 53 by
#593, decisions 54 and 55 by #600, decisions 56 and 57 by #564, decisions 58 and
59 by #566, decision 60 by #605, decision 61 by the owner while #605's galleries
ran, decision 62 by #607, decision 63 by the code review of #614, decision 64
by the code review of #621, and decisions 65 to 67 by #623.

| # | Decision | Recommended default | If decided otherwise | Before |
| --- | --- | --- | --- | --- |
| 1 | File extension; the name "sequence source" | **decided 2026-10-12** as recommended, as M1's parser built it (#304): `.foldseq`, first line `foldseq 1` (`.fseq` is the xLights and Falcon Player format) | the extension, the first-line keyword, `decodeFile`'s refusal, error goldens and glossary rows change | M1's parser PR |
| 2 | `nearMissBand` | **decided 2026-10-06** as recommended: 1e-3 sheet lengths | smaller: a decimal near a vertex becomes a separate point and a crease sliver; larger: legitimate points refused. A `RunSettings` field, so no syntax change | M2 |
| 3 | A move carrying the anchor's face: re-anchor or refuse | **decided 2026-10-06** as recommended: re-anchor, printed by `--report` | refuse: authors write `anchor P` first, and animation needs no sub-hierarchy per re-anchor | M2 |
| 4 | A precrease's stiffness in a settle | its crease, U at 0 ([D12](#d12-the-text-syntax)), settles as a crease spring resting at 0, as an M or V crease at 0 does, weighted by length; a sheet file's `F` edges stay panel bends, weighted also by the two triangles' areas | as panel bends: turning concentrates differently, and M6's numbers change | M6 |
| 5 | SVG "wireframe": feature lines, or triangulation too | `--lines features` default; `--lines mesh` adds visible triangle edges | mesh default: every settled page draws its triangulation, and visibility runs on more segments | M7b |
| 6 | Textures (A2b): content and source | none; M7a ships normals and texture coordinates only | procedural: a PNG writer on `bytestring`, or `zlib`/`JuicyPixels` from lts-22.44; vendored: licence and provenance in `examples/README.md` | after M7a |
| 7 | Caption overlap and overflow | captioned pages get a gutter of at least 42/340 ≈ 0.124 of a figure, the bound at which 14-unit type clears on the default three-column page; uncaptioned pages unchanged; overflow across cells accepted and stated, since the backend has no font metrics | accept overlap: unreadable pages; squash or truncate: width estimates without metrics; refuse: some sequences cannot be drawn | M3 |
| 8 | Blintz direction: the recipe folds corners behind (−180), the study's manifest in front (+90 then +175) | **decided 2026-10-06** as recommended: the recipe's `fold behind`, so migration reuses `checked-blintz.svg` | both blintz sources switch to `fold in front` in one PR, and gallery output changes | M2's blintz PR |
| 9 | Whether `examples/quarter-fold-steps.fold` moves to the state rule | **decided 2026-10-06** as recommended: it stays as the regression; the state-rule page is a new golden | `quarter-fold-steps.svg` and `quarter-fold-step-1.svg` move in that PR, and their `test/fixtures` copy migrates too | M2 |
| 10 | Eighth turns by trigonometry, or a `sheet square as diamond` start | **decided 2026-10-11**: trigonometry, with cos 45° and sin 45° both `sqrt 0.5`, which IEEE 754 rounds correctly, so an eighth turn adds no platform bits of its own; folded positions keep folding's (09 §8) (C91) | `rotate` takes even k only, so frames stay exact; the crane-opening example's first step becomes a header option | M2 |
| 11 | The external-tools rule in `AGENTS.md` | **decided 2026-10-12** as recommended: yes, [§3](#3-recorded-text-this-design-changes) row 8, landed with #550; scoped by the owner the same day ([C100](#changes-since-draft-v2)) | only in `docs/related-projects.md`: agents reading `AGENTS.md` miss it | M0 |
| 12 | CI placement of crane-sized sequences; the slow job's status; triangle budgets | **decided 2026-10-12**: crane-sized sequences in a separate slow job that is a **required** check, so row 15 changes "all three CI checks" to four, and the PR adding it moves into it, whole, the study spec files that hold a test of 10 s or more; default CI settles ≤ 392 triangles, never a crane fixture; `run --settle`'s budget, in refined triangles counted before solving, is set from 3–5 compiled runs on the crane fixtures it must settle, by the PR that builds it and for any later change; the 1,192-triangle cap is withdrawn ([C101](#changes-since-draft-v2)) | an optional slow job lets slow regressions merge; crane tests in default CI pay [D16](#d16-testing-and-acceptance)'s costs on every PR; a higher cap admits unmeasured settles | M4 |
| 13 | The sense of a hinge turn on paper already folded: read from the held face, or from where the moving paper goes | **decided 2026-09-23**: where the moving paper goes ([D5](#d5-presentation-and-the-readers-side), [E3](research/E3-formal-fold-semantics.md) G) | reading the held face: lifting a flap off the face it lies on is `behind`, and a page turn depends on which crease is listed first | M2's runner |
| 14 | A `fold and unfold`: one record or two, and its name | **decided 2026-09-23**: one move, the *pre-crease*, printed `pre-crease`, whose one record of kind `Precrease` changes nothing but the new crease; **refined 2026-09-24**: that crease has no direction, U, since a later move may fold it either way, a stretch at a time ([D12](#d12-the-text-syntax)) | two records, the fold and its unfold: a folded state no figure draws, and a pair every consumer has to match up | M2's runner (`Sequence.Record`) |
| 15 | What "refined" requires, and the crane target ([11](11-prd-refined-final-forms.md#4-the-crane)) | **decided 2026-09-29**: both. More tucked stays in the gallery, labelled a schematic; the physical target is the pod; the pillow stays a target only if F2's core-lengthening test passes | picture only: F2–F5 are not needed, and the look track works on labelled sketches; paper only: More tucked leaves the gallery | F0 |
| 16 | The paper screen's strain threshold ([11](11-prd-refined-final-forms.md#what-refined-means)) | **decided 2026-09-29**: 1% principal strain outside declared tension-field regions, with 0.1% reported beside it. Crossings are reported, as a count and the deepest [reach-through](../docs/notes/crossing-counts-on-touching-paper.md), with no pass/fail depth until F2's contact states give separations to compare | 0.1%: few poses pass, and the tension-field regions carry the look | F0 |
| 17 | [D19](#d19-realistic-rendering)'s geometry axis gains `as prescribed` | **decided 2026-09-29**: yes; D19 amended | sketches stay unlabelled in their files | F0 |
| 18 | Reopen four [D18](#d18-non-goals) non-goals (pressure or inflation, thickness as geometry, sliding contact, calibrated paper) for illustrations only | yes | F2–F6 stay research notes | F2 |
| 19 | Sim-FAST is CC BY 4.0, not unlicensed | ideas only, as for GPL sources, to keep one rule | adapted code carries CC BY attribution, not MIT | F2 |
| 20 | Where offline stills live ([11](11-prd-refined-final-forms.md#22-3d-viewer-and-offline-stills)) | a Mitsuba script under MIT, with Blender kept to one-off renders outside the tree | a GPL directory with its own licence file and a line in the research README; amends [D17](#d17-third-party-and-external-tools) and the AGENTS.md external-tools rule, which since [C100](#changes-since-draft-v2) lets no script here use Blender's API | F1 |
| 21 | A Python prototype under `study/`, outside CI | yes | the prototype lives outside the repository; only its FOLD outputs arrive, as fixtures with provenance | F2 |
| 22 | May an external tool's shape be shown for review | yes, labelled a prototype, never a golden or the published illustration | review waits for F4 | F2 |
| 23 | An inflate or spread step's settled figure as a page cell with its own three-quarter camera | no: a separate figure after the page (R-11-32) | amends [D14](#d14-material-consumption) (R-07-32) and the AGENTS.md one-camera rule | F7 |
| 24 | The membrane for inflated paper: tension field with crimps drawn on top, or a plain shell whose folds depend on a seed | tension field | the look depends on a seed, stated with each pose; F2's benchmarks change | F2 |
| 25 | The finished 3D book figure the ink-volume target is measured against | the owner names one | the flat crane's 4.8, as a floor only | F1 |
| 26 | Which gallery poses show a paper screen ([11](11-prd-refined-final-forms.md#1-the-paper-screen), R-11-1) | **decided 2026-09-30**: every pose a gallery draws as paper that could be taken for it, solved or placed: 28 galleries besides whole-crane, listed on #410. Diagnostic, trace, archive-replay and rigid galleries show none, and #410 records why | every entry point, including solver traces and rigid poses whose strain is zero by construction | F0 |
| 27 | The false creases of a pose that can be made again one level finer only by solving it again (R-11-1) | **decided 2026-09-30**: reported on its own mesh, with the finer level not measured, which neither passes nor fails | solve it again one level finer; or judge it on its own mesh alone, the rule #438 removed | F0 |
| 28 | The no-stretch floor on a sheet that is not convex (R-11-3) | **decided 2026-09-30**: taken over the pairs whose chord stays on the flat sheet, for which the distance along the paper is the chord, so it is still a proof; on a convex sheet, the floor over every pair | refuse the sheet, as R-11-3 first said; or measure distances within the sheet, exact but a new routine | F0 |
| 29 | Whether a gallery's own solve one level finer counts as a solved pose made again (R-11-1; raised by #447) | **decided 2026-09-30**: it counts where (1) its mesh is checked to be the pose's mesh with every triangle split into four, (2) it solves the same control, and (3) the two solves agree at every vertex of the coarser mesh within the floor limit, 1 px at the screen's 600 px per sheet unit. Elsewhere the finer level stays not measured, as decision 27 says | never, as decision 27 alone says, so that no solved pose can pass; or wherever the gallery solved the same control on the finer mesh, with no check that the solve found the same shape | F0 |
| 30 | The scale at which the paper screen gives a pose's floors and reach-throughs in pixels, and judges the 1 px floor limit (R-11-3's "page scale"; raised by #446) | **decided 2026-09-30**: each page's own drawing scale, so a verdict follows the size the page draws a pose at. Decision 29's condition (3), judged at the screen's scale, follows it | 600 px per sheet unit on every page, the scale of #409's visible-change rule and of the whole crane's drawings, so that a verdict does not change with the size a pose is drawn at | F0 |
| 31 | Whether a finer solve its gallery does not accept, for example because it did not converge or failed its contact check, counts as a solved pose made again (decision 29; raised by #449) | **decided 2026-09-30**: it does not count: the pose's finer level stays not measured, and its report says the gallery does not accept that solve | count it differently, for example reporting its false creases beside the pose without letting them decide the verdict, which the owner named as the other way; or count it, as decision 29 alone allows | F0 |
| 32 | Which drawings set a page's scale (decision 30): only those the page shows, or also those its gallery writes beside it (raised by #453; #456) | **decided 2026-10-01**: also those beside it. A page's scale is the largest at which its gallery draws the paper, on the page or in the drawings it writes beside it, so that a pose that passes passes in every one of them. wing-layers stays at 669 px per sheet unit, the scale of its controls' own drawings in `wing-layers/` | only the drawings the page shows: wing-layers at 626, its lifted grip's figure, and a page that shows none, such as crane-body's, would need another rule (decision 33) | F0 |
| 33 | The scale of a page that shows no drawing, such as crane-body's, which shows tables and a 3D viewer (raised by #453; #456) | **decided 2026-10-01**: the scale of the drawings its gallery writes beside it, as decision 32 gives: crane-body's trials' own drawings, at 692 px per sheet unit. A page whose gallery draws no paper at all has no scale; its gallery writes the measurements without screens and publishes no page | the fixed 600 px per sheet unit of the whole crane's drawings, for any page that shows no drawing | F0 |
| 34 | Where the crane-with-a-wing studies hinge the wing (#455) | **decided 2026-10-02**: at its root, the line from the base of the neck to the base of the tail, where a crane's wing opens: folded y = 0.37585 on `examples/crane.fold`. Found by decision 35's rule, not typed in. The galleries move to it from y = 1/4 | y = 1/4, a quarter of the sheet from the wing's tip, where the studies have hinged it so far; or where the wing's paper leaves the body's, y ≈ 0.29–0.32 | the galleries' move (#455) |
| 35 | How a study makes a choice the model leaves open, such as where a flap hinges or the angle a rigid base settles at (#455) | **decided 2026-10-02**: by a stated rule the code applies, the same for every model, not by the owner model by model; the owner reviews the rules and where they fail. A flap's root joins the first corners on each side of its tip where its outline meets other paper, and is kept only if the flap then turns about it; a root hidden between layers, as the crane's neck and tail have, is refused, not guessed. A rigid base settles at the angle of least bending energy | the owner chooses each case, which does not scale to the many models the project should fold | the galleries' move (#455) |
| 36 | The angle at which a released control's rigid base is held, when its gallery also runs the flat-preference control, whose angle decision 35's search finds (#455). A *released* control leaves the paper at the wing's hinge free to bend instead of holding it; its *rigid base* is the wing between its widest point and the hinge, turned as one piece; the *flat-preference* control is the released one whose hinge spring prefers flat | **decided 2026-10-03**: the flat-preference control's angle, found by its own search in the same run, not typed in. For the other released controls this refines decision 35's last sentence. Each of them is also solved 1° either side, and is refused, naming the side, if either side ends with less bending energy. A side that does not converge is compared all the same and recorded as unconverged, as the search records its own solves. A control made to fail, such as an incompatible grip, and a continuation of another control's endpoint take the angle without the check; **refined 2026-10-03**: so does any control its gallery can never accept, such as crane-internal's two that leave out contact forces, since the check could not change its verdict. Measured on the body-free control at the root, one run: its own 16-solve search chose the same angle, 28.383°, in 24,412 CPU seconds, 23 times the 1,046 of one solve at that angle | a 16-solve search for every released control, which took 6.8 CPU hours on the one control measured; or the flat-preference angle with no check, one solve each | crane-body's and crane-internal's move (#455) |
| 37 | How crane-body and crane-internal, each built on the paper of the 1/4 hinge, move to the root (#455) | **decided 2026-10-03**: each finds by rule what it took from that paper. crane-internal's creases are every mountain crease with both panels in the released body patch, the body panels beside the hinge that the body-free controls leave free, each with the one contact order the body-free fixture keeps active between its two panels: 26 and 51 at 1/4, which the gallery names today, and 28, 30, 55 and 57 at the root. crane-body's opening creases already come from the crane pocket map (`CranePocket`), which sorts the crane's panels into its body and flaps. The map now checks the crane's structure instead of the 1/4 fixture's counts of panels, edges, vertices and authored root edges, the hinge's own crease segments: it finds 21 and 46 at 1/4, as today, and 22 and 49 at the root | both stay at 1/4 as the record of why releasing the body fails there, with a body-free control added to crane-root at the root; or that, with both retired | crane-body's and crane-internal's move (#455) |
| 38 | Whether a magnified plot of measurements sets its page's scale (decision 32): crane-root's side profile, a chart of the heights along the wing's middle, at 2,000 px per sheet unit (raised by #453; #456 question 2) | **decided 2026-10-03**: it does not. A plot of measurements is not a drawing of the paper, and no reader would take it for the pose, the test decision 26 applies to which poses show a screen; crane-root's page stays at 692 px per sheet unit, the scale of its crane drawings and of its sibling pages crane-spreading and crane-body | count it: crane-root's screen at 2,000 px per sheet unit, 2.89 times stricter than its sibling pages' for the same crane | F0 |
| 39 | What a quick tier may hold that the model leaves free, so that a settled shape comes in seconds rather than the hours a research gallery takes (#474) | **decided 2026-10-03**: the paper the moving flap does not need, such as the crane's body, held and said so. The output's fidelity record names what was held, so it is a true solve of held paper and claims no more; this adds to D19's settled geometry the paper it held, which neither D19 nor `Senbazuru.Render.Fidelity` can say yet. The galleries keep a periodic comparison of the held solve against the released one, which shows where the label stops being a technicality: at the crane wing's root the two differ by 0.0003 px at 600 px per sheet unit, and the held solve costs 7.5 CPU seconds, in three runs, against 1,046 in one. A model whose shape comes from moving that paper, such as an inflated water bomb, cannot be quickened this way; that is research, with #427 and #428 | release the held paper only where a held solve fails its own checks; or solve each model both ways once, and hold only where the two agree within 1 px | the quick tier (#474) |
| 40 | Whether `expect refused` may name a turn blocked part-way: `FlapCollision`, paper the sweep finds in the turn's path, and `FlapUnresolved`, a path the sweep cannot decide within its budget | **decided 2026-10-06**: yes, both. They are refusals of the paper, like the nine `FlapError` kinds [02 §12](02-language-semantics.md#12-refusal-catalogue) already listed, and without them a sequence could document only a turn refused before it starts or at one of its ends. Today only an unfold is blocked part-way, since a fold starts from paper lying flat: on the accordion, unfolding a strip into a flap leaning over it is refused as `FlapCollision`, with a witness a quarter of the way along, and as `FlapUnresolved` by a sweep of no depth (`RunSpec`, "a turn blocked part-way"). Expecting `FlapUnresolved` pins the sweep's budget as much as the paper: a deeper default can turn the same move into a collision or a clearance | leave them out: `expect refused` documents only a turn refused before it starts or at one of its ends, and a blocked unfold cannot be written down as the thing to avoid | M2's runner |
| 41 | What a `nearest P` does where the rules have already taken one answer, so that it was not needed: in `L1 to L2`, the only answer crossing the paper, or the only one laying L1's stretch onto L2's | **decided 2026-10-08**: it must agree with them. A P lying nearer another answer than the one taken is refused as `NearestDisagrees`, which names the answer taken and why, and the answer P lies nearer. Any answer counts, one crossing no paper included, since an author pointing at it expected it. A P nearer the answer taken is accepted, and so is one as near to both, such as the point where the answers cross, since it points at neither. Being read, P must name a place on the paper even where it is not needed: `nearest (2, 2)` is refused as off the paper. Raised in #507, which ignored such a P: on the blintz sheet, `[midpoint of edge west, centre] to [centre, midpoint of edge north] nearest corner south-west` resolved to x + y = 1, though the corner lies on y = x. O5 and O6 take `nearest` too, and the rule holds for them when they run | ignore it, as #507 did: `nearest` is only a tie-break, and an author's word can be overruled without a word. Or let it override the preference, never the paper, which makes the preference a default | M2's runner |
| 42 | Whether owner decision 34's hinge, the wing's root, reaches the crane-wing sequence. [§7](#7-examples) folds it at y = 1/4, and [D14](#d14-material-consumption)'s first M6 test and 07 AC-1 compare it with `craneSpread source 3 20`, the wing hinged at y = 1/4 (392 triangles), while the galleries hinge at the root, apart from crane-root, which keeps seven of its nine controls at y = 1/4 for comparison | **decided 2026-10-13**: Alternative 2, "Move the hinge to the wing root" (#559). The crane-wing sequence and every passage that plans it at y = 1/4 move to the wing's root: the fold and 09 §9's prefix before M4, when that prefix becomes a sequence, and the settle and its tests before M6 ([§10](#10-corrections) items 42 and 43, #560). How a sequence names the root, and what its settle is compared with, are owner decisions 43 to 46, from #560's research ([C102](#changes-since-draft-v2), [C103](#changes-since-draft-v2)) | y = 1/4 kept: the sequence and its tests stay on `craneSpread source 3 20` (392 triangles), and the illustration bends the wing where a real crane's does not open; or both, which the question recommended: y = 1/4 for the language's tests, and a second sequence at the root for the illustration once the language can name the root | M6 |
| 43 | How a sequence names the wing's [root](../docs/glossary.md#origami), where owner decision 42 moves [§7](#7-examples)'s fold (#560). No crease-pattern vertex folds to the root's ends, but the sheet's corner north-east, the tip of the crane's head, folds exactly onto its line ([C102](#changes-since-draft-v2), corrected in [C107](#changes-since-draft-v2)) | **decided 2026-10-13**: first the question's second option, a `root of P` reference applying owner decision 35's rule before M4: "I feel root of P may be a bit more intuitive for the author?" ([#560's answers](https://github.com/avalonalex/senbazuru/issues/560#issuecomment-6153343399)); **revised the same day**, after #565's review found costs the question had not given ([the corrections](https://github.com/avalonalex/senbazuru/issues/560#issuecomment-6154343649)): "O4 at M4, root of P after" ([#560](https://github.com/avalonalex/senbazuru/issues/560#issuecomment-6154363309)). The crane fold names its root by the O4 construction `perpendicular to [corner north-west, midpoint of edge north] through corner north-east`, on whose line the head's tip lies: about five lines in the resolver and no new language. `root of P` is designed and built after M4, once these are settled: decision 35's turn check, which alone refuses the crane tail's root and needs the run's layer orders; `FlapRoot`'s tolerances, against 05's R-05-3; its refusal of unassigned creases, though owner decision 14 makes every pre-crease `U`; and [D2](#d2-references-named-on-the-sheet-and-resolved-by-slot)'s vertex slot for P. Owner decision 47 makes the study's root finder exact, so that the comparison and the galleries share one root ([C103](#changes-since-draft-v2), [C106](#changes-since-draft-v2)) | `root of P` before M4, as first decided, with that work done first; or O4 only, with no root reference until a model needs one that no construction names | M4 |
| 44 | What M4's crane-wing prefix and M6's first test compare with, at the root, where `buildCraneWingAt` also writes a [join](../docs/glossary.md#the-fold-format) (`J`) straight across the wing where it is widest, folded y = 0.324 ([07](07-prd-material-consumption.md#one-move-fed-by-hand)), which no move writes, and without which crane-spreading's curved control starts with 452 layer orders reversed | **decided 2026-10-13** as recommended: the study keeps the join. At M4 the [move record](../docs/glossary.md#fold-sequences) is compared with a build without it, at the sequence's own line, which needs one parameter of the study's builder. At M6 the settle gains `split REGION along LINE`, which cuts the region's faces along the line for the mesh only, never the move record, so that the settle meshes as the study does and its hold can be `closed across-hinge moving`. That hold was measured only with the line in the record, and the joined control itself converges on `aed4755` only with twice the gallery's iterations ([#566](https://github.com/avalonalex/senbazuru/issues/566)). How region words and contact orders read the split's pieces, how its edges settle, and how it names its line, where no named landmark folds, #560 proposes and the owner sees before it is built ([C103](#changes-since-draft-v2)) | compare with builds without the join at M6 too, where the curved control does not converge with the gallery's iterations or twice them, so the illustration is refused; or drop the join from the study, after which that control fails the same way, owner decision 37's crease ids change, and the galleries re-run | M4, the build without the join; M6, the split |
| 45 | How M6 writes the settle's band ends and `arc-grip`'s lengths at the root, where the hold covers the wing's *rigid base* (owner decision 36), 0.0514252… from the hinge to where the wing is widest, and the grip starts 0.3288675… from the hinge, 7/8 of the *tip side*, the wing from the hinge to its tip ([07](07-prd-material-consumption.md#one-move-fed-by-hand)). Band ends are [sheet lengths](../docs/glossary.md#fold-sequences), and neither is a fraction a sequence can type | **decided 2026-10-13** as recommended: band ends are chosen only to select the right vertices, never typed as those lengths; the hold `band moving 0..13/250` and the grip `band moving 8/25..` select exactly the vertices the study pins ([C103](#changes-since-draft-v2)). `arc-grip` works out its lengths itself: its arc stops 7/8 of the tip side from the hinge, as `bentPoint` has it, and starts at the farthest vertex that a hold at a `rigid-pose` holds on its side. An `arc-grip` with no such hold, or more than one, is refused, so every released control's grip is refused, since none holds paper on the moving side (07's rows 12–14, 16 and 18). How "farthest" is measured, and a start past the stop, #560 proposes | a third argument, `arc-grip 30° 20° L`, whose L needs 11 decimal places for AC-1's 1e-12, against [04](04-prd-sequence-source-and-cli.md#goals)'s Goal 1, no decimals a book would not print; or the study's rule, the larger of an eighth of the tip side and the stretch to the widest point, which needs a widest point the language does not have | M6 |
| 46 | What M6 re-expresses of crane-root, which keeps seven of its nine controls at y = 1/4 for comparison, and of the released controls at the root, which hold their *rigid base*, the wing between the hinge and its widest point turned as one piece, at an angle a search finds (owner decisions 35 and 36) | **decided 2026-10-13** as recommended: crane-root's seven y = 1/4 controls stay study fixtures, since a record at the root cannot name them, as [C40](#changes-since-draft-v2) keeps what the vocabulary cannot name; so M6 checks neither `ReleasedRoot`, one of the seven, nor the ids crane-root's tests pin at y = 1/4. The released controls at the root stay fixtures too, until a settle can hold a region at a searched angle and owner decision 45's `arc-grip` can start from that hold: no settle word does, and a typed `rigid-pose` would need the angle to about 11 digits for AC-1's 1e-12 on a rigid base 0.0514 long, where the energy fixes it only to about a degree ([wing-hinged-at-the-neck.md](../docs/notes/wing-hinged-at-the-neck.md)). [D14](#d14-material-consumption)'s 16 controls named fall to about 11 at the root; #560 re-derives the count ([C103](#changes-since-draft-v2)) | keep a y = 1/4 test sequence, today's §7 example, so that M6 re-expresses the five of the seven that 07's table names (rows 15 and 20 are fixtures already), which reopens the half of Alternative 3 owner decision 42 declined and puts a second crane-wing source in the slow job at M4 and M6; or move them to the root, losing crane-root's comparisons with y = 1/4, its converged comparison of two meshes and the mesh 08 names as A-11's fallback, which §10 item 41 (#558) finds may no longer serve, and paying a base search of about 596 CPU s for each released control | M6 |
| 47 | Which hinge M4's comparison builds the study's wing at, without its join (owner decision 44). The sequence folds through corner north-east's folded height (O4, owner decision 43); the study's `wingRoot` found the root 1.24e-9 lower, so a build there missed the sequence's line by 1.76e-9, against 09 §9's 1e-12 ([C103](#changes-since-draft-v2); the question [as asked](https://github.com/avalonalex/senbazuru/issues/560#issuecomment-6159771153)) | **decided 2026-10-13** as recommended: "Exact root finder (Recommended)" ([#560's answers](https://github.com/avalonalex/senbazuru/issues/560#issuecomment-6157138819)). The study's `FlapRoot` finds the root's ends by crossing folded edges, so `wingRoot` lies 4.9e-14 above y\* = 1 − (√2/4)(1 + 2 sin 22.5°), and the galleries, the comparison and the sequence share one root. Built in #575 ([C106](#changes-since-draft-v2)) | build the comparison at corner north-east's folded height and leave `wingRoot` as it was, so that the study holds two roots 1.24e-9 apart and M6's AC-1 fixture is no longer the gallery's curved control, as the question gave it | M4 |
| 48 | Whether the plan adds a golden of the wing lowered at its root. 09 §9 asks each migration's goldens to stay byte-identical; the only crane-wing golden, `checked-crane.svg`, stays at y = 1/4 ([§10](#10-corrections) item 42), and nothing pins the root build's drawing (the question [as asked](https://github.com/avalonalex/senbazuru/issues/560#issuecomment-6159771153)) | **decided 2026-10-13** as recommended: "Add a root golden at M4 (Recommended)" ([#560's answers](https://github.com/avalonalex/senbazuru/issues/560#issuecomment-6157138819)). The M4 equivalence PR adds a page of the wing lowered at its root, rendered from the comparison build, and the sequence's page must match it byte for byte. How both pages are drawn, 09 §9's `CraneWing` row says ([C107](#changes-since-draft-v2)) | M4's equivalence at the root compares records only: angle lists, order and frame counts, 1e-12 placement and contact, with the root build's drawing unpinned | M4 |
| 49 | Which of the 25 kinds a run reports, through `refusalKindOf`, but `expect refused` cannot name ([#580](https://github.com/avalonalex/senbazuru/issues/580)) to give a name: 9 of the library's folding refusals, 14 of its flap refusals, and the two an expect refused not met raises (decision 50). Found on 3121083 by reading the code, with four cases re-run [reasoned] ([the questions as asked](https://github.com/avalonalex/senbazuru/issues/580#issuecomment-6278612261)): 19 are reached by no valid sequence, and the other six only through a checker gap (a 400° fold, `FlapInvalidTurn`; a 0° fold, `FlapSweep`), a fold line 5e-7 from a vertex (`DegenerateFace`), a face the mesh cannot triangulate (`FlapSurface`, #579), or a nested `expect refused` | **decided 2026-10-19**: as recommended, no kind for all 25. `refusalKindOf` gives them none, as it gives `CreasingRefused` and a move not run yet none, so a run passes such a refusal on as itself, and a test holds every kind it gives to `refusalKinds`. None is a refusal of the paper: each is unreachable, or reached only through a gap filed to be closed where it opens | list the four reachable ones, `DegenerateFace`, `FlapInvalidTurn`, `FlapSurface` and `FlapSweep`, as decision 40 listed two, which would pin today's gaps and the mesh's fan-triangulation limit as things a sequence may expect; or list all 25 | issue #580, built there ([C109](#changes-since-draft-v2)) |
| 50 | What an `expect refused` nested inside another does. The parser, checker and runner all accepted one, and it could never pass: whatever the inner one did, the outer saw no refusal it could name, since a met expectation is no refusal, one not met (`RefusalNotRaised`, `RefusedDifferently`) is in 02 §12's table but was not in `refusalKinds`, and any other refusal with no kind is passed on. The question as asked said it could raise only those two, which missed the last case. 02 §9's "at any nesting depth" read as allowing nesting | **decided 2026-10-19**: as recommended, "refuse nesting statically": refused before anything runs, as `NestedExpectRefused`, a static problem, directly or inside a `together`; the two refusals have no kind. 02 §9's nesting is an error wrapped in another: a turn refused because folding tore matches `TornAt` | allow nesting and list the two, so that `expect refused RefusalNotRaised { expect refused K { … } }` asserts the inner move succeeds; or leave nesting accepted with the two unnamed, so a nested one always stops the run | issue #580, built there ([C109](#changes-since-draft-v2)) |
| 51 | How a run picks a point inside a face. Four places did it, each its own way: the start's default anchor was refused when outside its face, asking for `anchor P` (G13); re-anchoring and the move off a new crease ([C19](#changes-since-draft-v2)) took an ear's mean (#588); and an `L1 to L2` fold's seed took the vertex mean of the face beside L1, and was refused when that lay on a crease. The code review of #588 also found that the start refused its default before reading a header `anchor P`, though [D3](#d3-the-runner-owns-the-state-its-start-and-the-handoffs) says the header overrides it. Where in its face the anchor sits changes no face held still, no placement and no picture ([the question as asked](https://github.com/avalonalex/senbazuru/issues/579#issuecomment-6295603098)) | **decided 2026-10-20**: as recommended, "one rule everywhere". One `Geometry.Polygon` function, `pointInside`, gives a point strictly inside a face: its vertex mean, or else the mean of its largest ear, chosen by the start's tie rule. It serves all four places, so G13's refusal goes, and with it the header-anchor bug. A face with no such point is passed over; a sheet with none is refused as `NoRoomForAnchor` | ears only where the run chooses: keep G13, fixed so that a header anchor gets past it, ears for re-anchoring and the crease move, and the `L1 to L2` seed filed as its own issue; or withdraw the ear change, fix only the header-anchor bug, and leave #579 to #586, since today the ears change only which refusal is printed: every turn refuses a face that is not convex | issue #579, built there ([C110](#changes-since-draft-v2)) |
| 52 | How `hinge of NAME` is refused where a later fold has bent the crease the named step turned about, so that its pieces lie on more than one line. On `sheet square`, pre-creased at x = 1/4 and y = 1/4, folded in half along y = 1/2 and unfolded, then with its north-east corner folded down along x + y = 5/4, the half crease's piece from (3/4, 1/2) to (1, 1/2) runs from (3/4, 1/2) to (3/4, 1/4). #589 refused such a hinge as not run yet, with no kind; its first commit had taken the first piece, so the fold depended on which way the crease was typed ([the question as asked](https://github.com/avalonalex/senbazuru/issues/591#issuecomment-6302364672)) | **decided 2026-10-20**: as recommended, a refusal of the paper with a kind, `HingeNotStraight`, naming each piece where it lies, as `EdgeNotStraight` does for `edge S` and the planned `CreaseNotStraight` for `crease of NAME`; "for now" | fold along the crease's longest straight run, which on the example is refused anyway as crossing folded paper where no crease runs (M4), ignores the carried piece and needs a tie rule; or keep it not run yet, with no kind | issue #591, built there ([C113](#changes-since-draft-v2)) |
| 53 | How a seedless fold's refusal writes the seed it offers for each flap. [C112](#changes-since-draft-v2) printed each to six places, though on five sheets tried every one could be named more simply, a corner, `centre` or an exact fraction written in its place giving a byte-identical FOLD file; and on striped paper a corner on a side the fold could move is refused on layer order, so a name has to be checked by running the fold ([the question as asked](https://github.com/avalonalex/senbazuru/issues/593#issuecomment-6304407386)) | **decided 2026-10-20**: as recommended, named point first, then an exact fraction, then a decimal. For each flap: a sheet corner or `centre`, lowest and then leftmost, that names that flap and from which the fold runs; else an exact fraction with a small denominator, within the sheet's tolerance; else the six-place decimal. It follows 02 §4.4's "vertex seeds are preferred to decimals" | exact fractions only, without names; or keep decimals | issue #593, built there ([C114](#changes-since-draft-v2)) |
| 54 | Which name a seedless fold's refusal offers when several would pick one flap. Decision 53's order, lowest and then leftmost, offered the blintz's body, with its four corners folded behind and then folded along `[midpoint of edge north, midpoint of edge east]`, as `corner south-west`, the tip of a flap folded in, which names the body only through the crease joining it; and on the flat blintz it gave `corner south-west or corner south-east` where decision 53's table showed `corner south-east or centre`. Run on 7c32c7e and two variants over 57 seedless folds, the code review of #598's 52 and five more on the plain square (53 distinct cases: four of #598's were written twice), every offered seed of every version, written in, folds the same file as 94cd756's six-place seed for that flap, and the versions differ in 9 cases ([the question as asked](https://github.com/avalonalex/senbazuru/issues/600#issuecomment-6306313536)) | **decided 2026-10-20**: as recommended, "largest face first": the names lying in the flap's largest face first, then the rest, each group lowest and then leftmost. Of the cases run, it changed only the three blintz cases, each to `centre`. **Replaced the same day by decision 55**, after #601's code review found that it missed a pre-creased blintz and changed flat paper | the centre first, which also swaps a corner for `centre` in six plain folds; or keep decision 53's order | issue #600, built there ([C115](#changes-since-draft-v2)) |
| 55 | Which rule replaces decision 54's. The code review of #601 found that decision 54, built as the flap's largest single face, misses its own case: a pre-crease cuts the blintz's diamond into faces the size of a corner triangle, the tie goes to the lowest, the folded-in south-west triangle, and the blintz with its midlines pre-creased and its corners folded behind is offered as `corner south-west` again. Face sizes also moved names on flat paper where nothing is folded in: the square pre-creased a quarter up and folded at y = 3/4 offered `centre`, the outcome decision 54 turned down, and the crane's crease pattern folded at y = 1/4 changed from `corner south-west or centre` to `corner south-east or corner north-west`. Run over 112 seedless folds (#600's 57 and the review's 55; 40 on folded paper) on 7c32c7e, on #601's 841ddd7 and on prototypes, every offered seed of every version, written in, folds the same file as 94cd756's six-place seed for that flap, 170 seeds a version; decision 54 as built changed 22 runs against 7c32c7e, 7 folded and 15 flat ([the question as asked](https://github.com/avalonalex/senbazuru/issues/600#issuecomment-6308075051)) | **decided 2026-10-20**: as recommended, "paper lying together": the names in the flap's largest piece of paper first, a piece being the faces folding placed together, then the rest, each group lowest and then leftmost. It changed 13 of the 112 runs, all on folded paper. Flat paper is one piece and keeps decision 53's names, so the flat blintz crease pattern keeps `corner south-west`, a real corner there, rather than decision 53's table row; where the centre lies on a crease the corner folded in is still offered | keep decision 54 as built; or the same as recommended, then the piece's own point before the other names, which offers a number where the centre lies on a crease, but in the letter fold, where two pieces tie, a point on the folded third instead of `centre`. A rule joining faces across pre-creases was dropped: it reads crease letters, and a crease keeps its pre-crease letter once folded | issue #600, built in #601 ([C115](#changes-since-draft-v2)) |
| 56 | What [07](07-prd-material-consumption.md)'s AC-15 checks of the crane-spreading gallery in each graduation PR. AC-15 quoted `[True, True, True, False]`, the list #470 replaced with `acceptedAs "rigid" && acceptedAs "curved" && not (acceptedAs "crossed-grip")` (`CraneSpreadGallery.hs:139`), which reports the finer mesh either way; on 7af4c92 the gallery gives `rigid` and `curved` accepted, `fine` unaccepted after 43 iterations without converging (#469), and `crossed-grip` rejected, in one run of 1011 s user CPU ([the question as asked](https://github.com/avalonalex/senbazuru/issues/564#issuecomment-6321260418)) | **decided 2026-10-21**: as recommended, "same as on the base": the four controls' `accepted` in `checks.json` equal what the gallery writes on `origin/main`, R-07-39's "unchanged" for the gallery's four controls. Fixing #469 changes `main`, not a graduation PR. A second gallery run is the cost. **Replaced the same day by decision 57**, after #602's code review found that #566's flags flip on changes of about 1e-13 and that the comparison named the tip of `origin/main`, not the merge base | pin today's `[True, True, False, False]`, which fixing #469 turns red; or quote the guard as it is, which leaves `fine` unchecked | issue #564, built there ([C116](#changes-since-draft-v2)) |
| 57 | What AC-15 compares instead of decision 56's flags. #602's code review found #566's evidence, which decision 56's question left out: the gallery's `accepted` flags flip on changes of about 1e-13. At aed4755 (#566) `curved` did not converge and `fine` did; at 7af4c92 the reverse. Their panel energies agree to the six digits #566 printed (`curved` 0.0131812 and 0.013181173, `fine` 0.0133058 and 0.013305843), while their edge errors move (`curved` 1.23e-7 and 1.81e-7). `rigid`'s energies are rounding noise (2.5e-25), and `crossed-grip`'s edge error is 0.096 against the 1e-5 it must stay under. The review also found decision 56's wording compared with the tip of `origin/main`, where the golden check in the same cell uses the merge base ([the question as asked](https://github.com/avalonalex/senbazuru/issues/564#issuecomment-6322181696)) | **decided 2026-10-21**: as recommended, "energies, plus the two fixed": at the PR's head and its merge base, `curved`'s and `fine`'s `panelEnergy` agree to six significant digits, `rigid` is accepted and `crossed-grip` rejected; convergence and edge error are reported, not compared | keep decision 56's flags, which a stage that only reorders arithmetic, as #539 did, can flip; or wait for #566 and treat a flipped flag as a question until then | issue #564, built in #602 ([C116](#changes-since-draft-v2)) |
| 58 | How far the fix for [#566](https://github.com/avalonalex/senbazuru/issues/566)'s contact derivative reaches. `SurfaceContact`'s clip snapped a distance within 1e-14 of a clip line to zero but kept its derivative. Where stacked layers' edges nearly coincide, a crossing on them differentiates as about 1 / (dp − dq), and a penetrating contact row with a large gradient made the stopping test's linear solve fail, so the crane-spreading `curved` control converged at 5 of 9 hinges within 1e-11 of `wingRoot`. Dropping the snapped distance's derivative made all 9 converge, and `fine` converge at its one hinge, with the quick tier's result unchanged. The question's figures for that fix, a largest gradient of 6.6 among them, were wrong; decision 59's question corrects them, and this answer does not depend on them ([the question as asked](https://github.com/avalonalex/senbazuru/issues/566#issuecomment-6326253994)) | **decided 2026-10-21**: as recommended, "every study, note the rest": the fix is in `SurfaceContact` for all; the crane-spreading gallery and the quick tier are run again; other studies' recorded results are noted as predating it and measured again when next used, in [#605](https://github.com/avalonalex/senbazuru/issues/605) | run every gallery that uses `SurfaceContact` again before merging; or give the fix to crane-spreading's solve alone | issues #566 and #469, built there ([C117](#changes-since-draft-v2)) |
| 59 | How wide the clip's snap is. #604's code review found decision 58's fix incomplete: a crossing on an edge lying almost along a clip line has a true derivative of about 1 / (dp − dq) whether or not a corner is snapped. With the band at 1e-14 every one of `curved`'s nine hinges ended with 1 to 16 rows at gradients of 4.9e9 to 3.3e11, none penetrating, and `fine` with 5 to 17 up to 3e10. Holding the crossing fixed while differentiating bounds every gradient, but stops crease correction's viable starts converging and blocks body-patch stages ([the question as asked](https://github.com/avalonalex/senbazuru/issues/566#issuecomment-6327968908)) | **decided 2026-10-21**: as recommended, "widen to 1e-12", in the clip's cross-product units: no row above 1e3 at the nine hinges (largest 6.6) or at `fine`'s two (6.2); the gallery's four controls as before; the quick tier the same base angle, its positions moving by at most 1.2e-11. **Revised 2026-10-22 by decision 62**, which makes the band a distance, after #607 found this band stalling crane-root's released strip | keep 1e-14 and record the latent rows; or divide by the edge length first, as `Origami.Contact.clipBy` does, which left 8 rows near 7e9 at 2 hinges | issue #566, built in #604 ([C117](#changes-since-draft-v2)) |
| 60 | How [#605](https://github.com/avalonalex/senbazuru/issues/605) treats the body chain below `--body-subdivision`. With #566's fix the chain regenerates only that far: the new continuation makes the same three crossings (triangles 14–55, 22–63 and 46–70) at correction 1, at step fraction 0.25, and takes correction 2 at step fraction 2.4e-7, where the old run made the crossings at correction 2 at 0.25. Every gallery that reads its archive checks for correction 2 at 0.25 and refuses the new one (`changed archive field: "scale"`). About 25 flags lie downstream. The question said each studies an event of the old run and that an old archive would fail exact gradient comparisons under the fixed clip; the first is false for `--body-larger-opening` and the two galleries after it, which use only the seed, and the second was reasoned, not measured ([the question as asked](https://github.com/avalonalex/senbazuru/issues/605#issuecomment-6329894474); [corrections](https://github.com/avalonalex/senbazuru/issues/605#issuecomment-6333637666)) | **decided 2026-10-21**: as recommended, "keep as a pre-fix record": re-run what still runs (body-patch, -checkpoints, -subdivision, -crease-seed, -angle-contact and whole-crane) and update its notes; mark the downstream notes as recording runs made before the fix; the subdivision note says where and why a fresh chain stops; the chain's readers are not changed, and [#612](https://github.com/avalonalex/senbazuru/issues/612) holds the re-pinning | re-pin each reader to the new run, regenerate the chain and rewrite about 25 notes; or retire the downstream galleries and keep their notes as history | issue #605, built in #611 ([C118](#changes-since-draft-v2)) |
| 61 | What a time limit on the main workflow covers. While [#605](https://github.com/avalonalex/senbazuru/issues/605)'s research galleries ran for hours, the owner asked that the main workflow, once the project is ready, take no more than 10 minutes; the research galleries may stay slow. The record limited a run's work and never its time: [07](07-prd-material-consumption.md#graduation-staged-and-gated) counts refined triangles "never seconds", [D15](#d15-graduation-from-study-to-library) rejects wall-clock settle limits and [D16](#d16-testing-and-acceptance) adopts no wall-clock guard. The question's reference points, from 2026-10-21: the crane quick tier's nine settles at refinement 3 took 87–92 CPU s for their solves, one run each; the crane-spreading gallery 345–356 CPU s over three runs, about half of it in its 4,324-triangle finer solve; the research galleries up to 10,494 CPU s, crane-body's ([the question as asked](https://github.com/avalonalex/senbazuru/issues/606#issuecomment-6332905612)). #621's code review found two of these loose: 87–92 is one run each of three builds, of which only 92.3 is the code that merged ([C117](#changes-since-draft-v2)), and 10,494 is the user time of a run made beside many others ([C118](#changes-since-draft-v2)) | **decided 2026-10-21**: as recommended, "one model's whole run": a model's whole run, from its sequence source's text to every frame, settle and drawing, finishes within 10 minutes of wall clock on the owner's Mac, an Apple M1 Max with 10 cores, with the crane as the test case and the research galleries exempt; a measured acceptance target, checked by a timed run at M6's acceptance and when a settle is added, with no wall-clock check in the code, so D15 and D16 stand. **Refined 2026-10-23 by decision 64**, which says what the crane's time covers | each settle step within 10 minutes, a model with several settles allowed longer; or `stack test`, the slow job's crane fixtures included, within 10 minutes in CI, which says nothing directly about an author's run | issue #606, recorded in #621 ([C120](#changes-since-draft-v2)) |
| 62 | What width the contact clip's snap band has, and in what units. [#607](https://github.com/avalonalex/senbazuru/issues/607) found crane-root's released strip, hinged at y = 1/4, converging at 14 of 19 hinge offsets with decision 59's band of 1e-12 of the cross product, against 19 of 19 before #604. The question gave the cause as the solver's active set: rows about 8e-10 clear are left out of the linear step until they penetrate, and the full step drives them to −1.7e-7. Decision 63 corrects that cause. With 1e-13 of the cross product, with 1e-12 times the clipping side's length, or with 1e-14, the released strip converges at 19 of 19 and `curved` at 19 of 19, `fine` at both hinges probed, and the body, crease and wing-layer solves come out as on main. A solver that adds the rows a step would carry into contact, tried at nine offsets, fixed the released strip but broke crease correction and the body patch ([the question as asked](https://github.com/avalonalex/senbazuru/issues/607#issuecomment-6345250619)) | **decided 2026-10-22**: as recommended, "1e-12 as a distance": the band is 1e-12 times the clipping side's length, the same distance at every refinement, the test `Senbazuru.Origami.Contact.clipBy` makes; this revises decision 59; [#613](https://github.com/avalonalex/senbazuru/issues/613) measures the galleries again. **Kept the same day by decision 63**, after #614's code review found the cause as asked wrong | 1e-13 of the cross product; keep decision 59's band and record the released strip's sensitivity; or replace the penalty's sign-based active set with a constrained step | issue #607, built in #614 ([C119](#changes-since-draft-v2)) |
| 63 | Whether decision 62 stands. #614's code review found its question's cause wrong. The rows 8e-10 clear, and others from overlaps not yet there, refuse only steps of 2⁻⁶ and longer. What refused every scale from 2⁻⁷ to 2⁻²⁴ was five contact rows at −1.09e-9 that appeared when two corners crossed into decision 59's band: a snapped corner counts as inside, so an overlap of no area appears, each copy of its corner a row at full depth. Leaving out the three triangle pairs involved, the step is kept at 2⁻⁷; under the distance band the same positions add no rows. The snap moves to the band's edge the jump [rejected-bending-trials](../docs/notes/rejected-bending-trials.md) describes at a line, and no width removes it ([the question as asked](https://github.com/avalonalex/senbazuru/issues/607#issuecomment-6351653106)) | **decided 2026-10-22**: as recommended, "keep it, correct the cause": the distance band stays, with the released strip converging at 19 of 19 hinge offsets and `curved` at 19 of 19; no band measured leaves fewer of `curved`'s 19 endings with rows above 1e3 without stalling the released strip (2, 9, 5 and 19 for decision 59's band, 1e-13 of the cross product, the distance and 1e-14); [#617](https://github.com/avalonalex/senbazuru/issues/617) tracks removing the jump | hold #614 and make the penalty grow from zero as an overlap appears, then measure every study again | #614's code review, recorded in #614 ([C119](#changes-since-draft-v2)) |
| 64 | What decision 61's crane check times. #621's code review found that no planned milestone runs the crane whole, while #621 timed only the crane-wing sequence of [§7](#7-examples), one step that lowers a wing of the finished crane, with the settle [§10](#10-corrections) item 43 re-derives. The crane from a square, `examples/traditional-crane.foldseq`, has 28 steps: it stops at step 4 until M5's macro moves, and at step 24, "Swivel the tail up", after them, since swivel and reverse folds stay `not modelled` with no milestone planning them ([02 §8](02-language-semantics.md#8-macro-moves)) ([the question as asked](https://github.com/avalonalex/senbazuru/issues/606#issuecomment-6370422511)) | **decided 2026-10-23**: as recommended, "both crane sources": the crane-wing sequence with its settle and the crane from a square as far as it runs, their times added; timed at M6, at M8, when a settle is added, and at each milestone that makes more of the crane run ([09 §6.4](09-testing-and-acceptance.md#64-one-models-whole-run-timed)) | the crane-wing sequence alone, as a stand-in for the crane; or no crane timing until one source runs it from a square through its settle, which no milestone plans | #621's code review, recorded in #621 ([C120](#changes-since-draft-v2)) |
| 65 | How a step figure shows the layers of a flat fold. The owner asked for the look of Szinger's Foldinator, whose figures draw aligned layers offset so that a reader can see the stack. Today's step pages draw every sheet where it lies, so a flat fold's layers make one outline. `render --offset` moves each layer whole by the layers under it: the top moves furthest, every fold splits into two lines, and arrows are refused beside it. The owner saw a scratch prototype first, the helmet steps, the square and bird bases and the crane, each corner moved toward the lower left by the sheets over it ([the question as asked](https://github.com/avalonalex/senbazuru/issues/623#issuecomment-6375940371)) | **decided 2026-10-23**: as recommended, "fan from the folds": the paper on top stays where it lies and each hidden corner moves by the number of sheets over it, so folds stay joined and raw edges peek out; arrows and fold lines stay on true positions ([06 §10](06-prd-step-diagrams.md#10-layers-fanned-from-their-folds)). The owner found it "a bit more realistic, although visually a bit busy", and left which figures fan for later, suggesting only the last *N* steps | explode layer by layer, as `render --offset` does; or keep figures flat and show layers only in a side or section view (#50) | M3; issue #623, recorded in #625 ([C121](#changes-since-draft-v2)) |
| 66 | Where the fanned layers are on by default. 06's Goal 3 keeps `render --steps`, every gallery and every tracked golden byte-identical. The question said about a dozen tracked SVG goldens draw folded paper; #623's record counts 26 of 32 drawing folded paper or a step page, up to 22 of which could fan once the three offset views and the bent strip are left out ([the question as asked](https://github.com/avalonalex/senbazuru/issues/623#issuecomment-6375940371)) | **decided 2026-10-23**: as recommended, "new step pages only": on by default for `run -o x.svg`, by a flag for `render --fold` and `render --steps`, so `render`'s output and every tracked golden stay byte-identical | on everywhere folds are drawn, those goldens changing; or opt-in everywhere, the new step page included | M3; issue #623, recorded in #625 ([C121](#changes-since-draft-v2)) |
| 67 | Whether the fan reaches the 3D export. A flat-folded GLB's complete scene keeps coincident layers, and [08](08-prd-realistic-rendering.md) owns the GLB ([the question as asked](https://github.com/avalonalex/senbazuru/issues/623#issuecomment-6375940371)) | **decided 2026-10-23**: as recommended, "later, as its own PRD 08 item": this change stays on the page, and the GLB's version, each corner lifted off the stack by the sheets under it, is a follow-up ([08](08-prd-realistic-rendering.md#layers-lifted-off-the-stack-later), [#624](https://github.com/avalonalex/senbazuru/issues/624)) | specify the page's fan and the GLB's lift together now; or no GLB version | issue #623, recorded in #625 ([C121](#changes-since-draft-v2)); #624 |

Questions the PRD files raised that this record decides rather than leaves open: a
step body's own builder type ([C22](#changes-since-draft-v2)); constructor names that
clash with `Fold.Types` ([C23](#changes-since-draft-v2)); τ's value
([C29](#changes-since-draft-v2)); some-vertex classification
([C26](#changes-since-draft-v2)); `creaseAllAlongWith` at M2
([C27](#changes-since-draft-v2)); `RoutePose`'s module ([C28](#changes-since-draft-v2));
whether existing library messages adopt "(internal …)" ids ([D20](#d20-errors));
07's proposed rules ([C42](#changes-since-draft-v2)); quarter-fold test 2's milestone
([C49](#changes-since-draft-v2)); existing `runIO` specs ([C71](#changes-since-draft-v2));
the bird arrows golden ([C70](#changes-since-draft-v2)); `decodeFile`'s words
([C25](#changes-since-draft-v2)).

## 10. Corrections

Findings about the repository's own text and code. Items 1–26 keep v2's numbers;
27–32 are new; 33–38 were added on 2026-09-23 from
[E3](research/E3-formal-fold-semantics.md) and its review; 39 was added on
2026-09-29 from #413, 40 and 41 on 2026-10-12 from #557's code review, 42 and 43
on 2026-10-13 from owner decision 42, and 44 and 45 the same day from owner
decisions 43 to 46. *Row* means a
[§3](#3-recorded-text-this-design-changes) row carries it; *issue* means M0 was to
file a new issue ([§8](#8-milestones)), which the cell names once it is filed, and a
milestone in the cell is when the fix lands, as in 10 §7.2's *Lands* column
([10 §7](10-roadmap-risks-questions.md#7-corrections-as-proposed-follow-up-issues)
writes each out); *fixed* names where the text was corrected; *recorded here*
means the text is a research note, a snapshot that is not edited.

| # | Finding | Evidence | Disposition |
| --- | --- | --- | --- |
| 1 | #95's half turn about x = 0 moves the model across the page and doubles the page width | [prd] [02 §5.2](02-language-semantics.md#52-presentation-moves-no-paper) | row 4 |
| 2 | #36's done-when 1 (a reflection is a turn-over) cannot be met, and one motion can change a V and an M crease together | [prd] quarter-fold step 2 | row 7 |
| 3 | #94's "nothing reads `frame_title`" is half stale (the CLI reads it for `info`, page and glTF titles); captions drawn by `render` would move goldens | [code] | row 7 |
| 4 | #114's premises are stale: `--thickness` and face lifting were removed, and a second rounded bend stretches 200% | [code] `docs/notes/paper-thickness.md`, `two-bends-need-more-than-radii.md:55` | row 7 |
| 5 | #56's "per-face transforms are discarded" is stale: `foldFrameWith` returns `foldedPlacements` | [code] [`Folding.hs:319-323`](../src/Senbazuru/Origami/Folding.hs#L319-L323) | row 7 |
| 6 | #104 cites `docs/notes/inflate-outside-draw-inside.md`, which does not exist, and its done-when lets two goldens change | [ls], issue text | row 7 |
| 7 | #60's done-when tests folding, not authoring; coordinates need a tolerance; "macro-moves are compositions" is false | [code] issue text read with `gh issue view 60` | row 3 |
| 8 | #96 says three papers and lists four | [web] [E1](research/E1-prior-art-sequence-languages.md) "D. The 2026 papers" | amend #96 with row 9 |
| 9 | `docs/related-projects.md`: Doodle is GPLv2, ReferenceFinder GPL-2.0, origami-diagrams moved to `amkraft/` and MIT only in `package.json` | [web] [E1](research/E1-prior-art-sequence-languages.md), [E2](research/E2-references-and-persistent-naming.md) | fixed in `docs/related-projects.md` by #361 |
| 10 | `docs/notes/huzita-hatori.md`'s dates disagree with Alperin and Lang | [web] [E2](research/E2-references-and-persistent-naming.md) finding 11 | issue |
| 11 | `docs/glossary.md` defines rest angle twice, differently (`:19`, `:86`) | [code] | row 10 |
| 12 | `check` silently skips Maekawa at a vertex touching a `U` edge | [code] `FlatFold.hs:503-506`; [bin] | issue |
| 13 | `Creasing.existingAt` takes the first vertex within tolerance, not the nearest | [code] [`Creasing.hs:323-327`](../src/Senbazuru/Fold/Creasing.hs#L323-L327) | issue, before M2's resolver: filed as #495, and fixed there on 2026-10-08, the nearest taken |
| 14 | `CraneWing` takes every `U` edge as its hinge, which works only because `crane.fold` has no `U` edge; its clip lacks `ThroughLayers`' guards | [code] [`CraneWing.hs:114`](../study/fold-material/CraneWing.hs#L114); [jq] 0 `U` edges | issue |
| 15 | The blintz manifest and recipe fold corners in opposite directions | [jq, code] | owner decision 8 |
| 16 | Manifest angle literals are not the documented formulas' `Double`s. Rabbit ear at m = 30: the stored `97.58514830800293` is one ulp from the `atan2` form. Petal at t = 175: the stored `-166.98236060695527` is **three** ulps from the code's own `atan2` expression ([`CheckedPetal.hs:107`](../study/fold-material/CheckedPetal.hs#L107)), which gives `…518`. v2 said one ulp for both ([C58](#changes-since-draft-v2)) | [py] appendix command 7 | issue, M5 |
| 17 | At least nine tolerance formulas act as "a hair" | [code] [gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md) finding 2 | issue, D2's prerequisite: filed as #546 on 2026-10-12, after M2 |
| 18 | `quarter-fold-steps.fold` writes M and V at angle 0 (4 creases on its key frame, 2 on its first state) | [jq] [10 §7.3](10-roadmap-risks-questions.md#73-settled-without-a-new-issue) | owner decision 9 |
| 19 | `Rigid(..)` and `Mat3(..)` are exported and nothing checks a proper rotation | [code] [`Rigid.hs:24-26`](../src/Senbazuru/Geometry/Rigid.hs#L24-L26) | issue, M2: filed as #542 and built there (C95) |
| 20 | Any filtered `stack test` run pays 19–21 s of `runIO` fixture setup | [research] 3 runs | issue, before M1's specs: filed as #547 on 2026-10-12, after M2; nearly all of the cost is in three study specs that C71 leaves in `runIO` ([C99](#changes-since-draft-v2)) |
| 21 | `creaseAllAlong` returns no new edge ids | [code] [`Creasing.hs:138`](../src/Senbazuru/Fold/Creasing.hs#L138) | 05 L2: `creaseAllAlongWith` hands them back, built 2026-10-08 (#495) |
| 22 | GLB `extras.senbazuru.frame` stores fold angles and material coordinates unrounded | [code] `Gltf.hs:274-275` | issue, M7a |
| 23 | #64's "inflating a body is outside the model" is overtaken by #106 and the README | [docs] | row 7 |
| 24 | `Origami.Step`'s header says a turn-over is a motion | [code] [`Step.hs:30-34`](../src/Senbazuru/Origami/Step.hs#L30-L34) | row 13 |
| 25 | The study viewer's paper colours disagree with `Diagram.Style`'s | [code] `viewer.html:168` | issue, M7a |
| 26 | `docs/notes/a-crease-is-a-hinge.md`'s "about 200 thicknesses" and 30–40° Mylar figures are not in the cited abstract | [web] [B](research/B-material-study-mechanics.md) "Unverified" | study-note issue, M0 |
| 27 | #104's first done-when bullet cannot be met: from `--view iso` no face of `puffed-square.fold` turns away | [py] appendix command 4; issue text | row 7 |
| 28 | `docs/roadmap.md` records the old order: #97 before #95 and #54, and #93, #96, #97 "only then" #95, #94, #36 | [code] `docs/roadmap.md:271-276`, `:1004-1009` | row 16 |
| 29 | `AGENTS.md:390` requires "all three CI checks"; a slow job makes that count wrong or leaves the job unrequired | [code]; `ci.yml`'s checks are `test`, `format`, `lint`, beside its `changes` job | row 15; owner decision 12, decided 2026-10-12, makes the slow job required, so the sentence counts four |
| 30 | `README.md:213` and `docs/roadmap.md` item 2 call the vocabulary missing | [ran] `grep -n` | row 18 |
| 31 | A library message names CLI flags: `LineStopsOnTheModel` starts with `creaseEndFlag`'s `--from`/`--to` | [code] [`ThroughLayers.hs:196`](../src/Senbazuru/Origami/ThroughLayers.hs#L196), [`Query.hs:68-71`](../src/Senbazuru/Fold/Query.hs#L68-L71) | issue, before M4; row 17 |
| 32 | The research note's count line says 7 of the crane's 12 some-layer steps hinge on existing creases; its own table marks 6 | [research] [gap-layer-selective-folds](research/gap-layer-selective-folds.md) "(e) The traditional crane, step by step" | recorded here; the note is a snapshot and is not edited |
| 33 | E1 says Eos only picks a half-plane, and that no prior art folds only the top flap or the near layers; Eos takes a face set (2007) and face lists with `InsertFace` (2021) | [web] [E3](research/E3-formal-fold-semantics.md) A | recorded here; the note is a snapshot and is not edited |
| 34 | E1's Unverified list names Eos's functions `BeginOrigami` and `ProveByGroebner`; they are `NewOrigami` and `Prove`, and Eos is closed source | [web] [E3](research/E3-formal-fold-semantics.md) A | recorded here; the note is a snapshot and is not edited |
| 35 | `docs/related-projects.md` said Eos never answers how to fold a crane and that its licence was not checked; Eos has folded a crane, and it is closed source | [web] [E3](research/E3-formal-fold-semantics.md) A | fixed in `docs/related-projects.md` by #353, except its "Two halves that never met" paragraph, fixed by #361 |
| 36 | 02 §4.3, D2 and the glossary additions called `crease [P, Q]` "Lucero's eighth"; Lucero numbers it O3, the operation he adds, and his O8 is Huzita–Hatori O7 | [web] [E3](research/E3-formal-fold-semantics.md) C | fixed in all three |
| 37 | E2's construction rule 4 calls `along <line>`, a fold along a line already on the paper, "Lucero's eighth"; Lucero numbers it O3, as row 36 says | [web] [E3](research/E3-formal-fold-semantics.md) C | recorded here; the note is a snapshot and is not edited |
| 38 | E2 writes `nearest @p` as "Beloch's `toward`"; Beloch's O3 reads `toward X` as a direction, and only its O5 and O6 pick the landing nearest X | [web] [E3](research/E3-formal-fold-semantics.md) finding 10 | recorded here; the note is a snapshot and is not edited |
| 39 | [D15](#d15-graduation-from-study-to-library) gated M6's crane equivalence PR and M8 on #208's value-only line search, which never landed: #208 closed on 2026-09-23 with #331's parallel test workers, which did not add it | [code] no value-only evaluation in `study/` or `src/`; #208 and #331 read with `gh` | withdrawn by the owner on 2026-09-29 (#413); fixed in D15, §8, decision 12, 07, 09, 10, 11 and the glossary additions; the optimisation is [#441](https://github.com/avalonalex/senbazuru/issues/441) |
| 40 | 08 (the problem statement, M7a's demonstration, A-10, A-11, A-13, A-15 and Dependencies), 10's R13a, D19's residue and 11 §4 give the crane-spread meshes as 392 and 1,192 triangles, the crane-spreading gallery's with the wing hinged at y = 1/4. Since #470 (2026-10-02) that gallery hinges at the wing's root, where its meshes have 1,188 and 4,324 triangles and whether the finer converged turned on rounding, so at some commits it got no GLB (#469), until #566's fix to the contact clip ([C117](#changes-since-draft-v2)); nothing builds the 1,192-triangle mesh now. `study/fold-material/README.md` and `CraneSpreadScreen`'s header still give 1,192 | [code] [`CraneSpreadGallery.hs:61`](../study/fold-material/CraneSpreadGallery.hs#L61), `:118-120`; `CraneSpreadSpec` builds refinement 3 only; [docs] `docs/usage.md:487-493`; #469 and #470 read with `gh` | issue #558, before M7a; #425 copies 11 §4's sentence |
| 41 | 08's A-11 makes #206's 4,312-triangle crane-root mesh A-13's failing case if the crane-spread meshes give none, since #206 recorded `ImpossibleStacking` on it. #459 fixed that refusal on 2026-10-01 and says the fallback "needs another mesh"; whether `projectedForm` declines on that mesh from A-13's two views is unrecorded. 07's capability table still says it "fails the visible glTF scene", and 08's risks and Dependencies rows (#557 dated one of them, for decision 12 alone), 10's R13b, 10 §7's #206 row and D19's residue keep the fallback | [docs] `docs/usage.md:537-539`; [research] [B](research/B-material-study-mechanics.md) finding 15; #206 and #459 read with `gh` | issue #558, before A-11 (M7b) |
| 42 | The crane-wing sequence's fold is planned at folded y = 1/4: [§7](#7-examples)'s example, its copies in 04 and 07, and 04's facts for it; D8's evidence status; 02's crane-wing facts (§6.3, §9, §13, check P); 09's M4 (a) and 09 §9's `CraneWing` prefix; and 10's R1. Owner decision 42 moves it to the wing's root, where the fold crosses 40 faces, not 16, and turns a flap of 8, not 4 ([C102](#changes-since-draft-v2)). Staying at y = 1/4: dated measurements; syntax examples that reuse `0..1/32` or `7/32..`; and the study's `studyHinge` builds with the tests on them, 07's "Problem and evidence", 05's L8, L10 and L11 tests and `checked-crane.svg`. Items 42 and 43 list every passage stating a y = 1/4 fact that the sequence, its settle or their tests rely on; the notes on §7's example, D14, AC-1, 07's budget paragraph, 09 §9 and the M4 rows point here | [ran] `git grep -n -F` in `PRDs/`, research excepted, for `y = 1/4`, `1/32`, `7/32`, `2, 3, 6`, `2,3,6,7`, `76 faces`, `902`, `four segments` and `craneSpread source 3 20`, each hit read; owner decision 42 (#559) | issue #560, before M4, under owner decisions 43 and 44: fixed on 2026-10-13 in 02, 04, 05, 07, 09 and 10, and in §7, D8 and §8 here, with 07 keeping the settle's plan at y = 1/4 for item 43 ([C107](#changes-since-draft-v2)) |
| 43 | The crane-wing sequence's settle is planned at folded y = 1/4: its bands (`0..1/32` and `7/32..`, eighths of a wing 1/4 long) in [§7](#7-examples)'s example and its copies; [D14](#d14-material-consumption)'s first M6 test, and its residue's 3.95% between two meshes; in 07, "On the crane wing" (76 faces, 902 orders, four segments), "Why intent", the notes after its copy, the re-expression table's rows 5, 6, 16, 18 and 20, the `SettleStartNotFlat` and `EmptyRegion` examples, the risk that results depend on the mesh, AC-1, AC-5 and AC-7; 10's R3; and the glossary additions' *Band*. Settle blocks parse only from M6 (D14). At the root the hold band is the whole base, from the hinge to the wing's widest point, whether the finer of the two meshes converged turned on rounding (#469) until #566's fix to the contact clip ([C117](#changes-since-draft-v2)), and the study's root fixture has a join along the widest point that no move writes ([C102](#changes-since-draft-v2)). Staying at y = 1/4: crane-root's seven controls there, which 07's table expresses against the wing record (row 9's ids and the 902 orders after the table are theirs); a record at the root cannot name them, and owner decision 46 keeps them study fixtures (item 45) | [ran] item 42's search; [code] `CraneRootGallery.hs:65-73`, `CraneRootSpec.hs:42`, `:48`; owner decision 42 (#559) | issue #560, before M6, under owner decisions 44 to 46 |
| 44 | Owner decisions 43 and 44 add work that no PRD schedules or specifies. Before M4: O4's resolver case, which [02 §4.3](02-language-semantics.md#43-lines) specifies but #494 left refused (`Resolve.hs:271`), for the crane fold; and the parameter that builds the study's wing without its widest-point join. The M4 rows, here and in 10 §1, schedule neither. After M4: the line form `root of P`, the root of the flap whose tip is P, missing from 02 §4.3's table and [§12](02-language-semantics.md#12-refusal-catalogue)'s refusals, D2's *Lines*, [§5](#5-type-sketch)'s `Line`, and 04's grammar, mapping table and reserved words (`root`); and a 05 entry moving `FlapRoot` into the library, exact, with typed errors and its tolerances, which 05's R-05-3 forbids as new ones | [ran] `git grep -n -F` in `PRDs/`, research excepted, for `root of`, `FlapRoot` and `split`: no hit but §9 rows 43–45, C102 and C103, and other senses of *split*; [code] [`FlapRoot.hs:65`](../study/fold-material/FlapRoot.hs#L65), `:209`; [`CraneWing.hs:166`](../study/fold-material/CraneWing.hs#L166); owner decisions 43 and 44 (#560) | issue #560: O4's case before M4, filed as #567 and built there ([C104](#changes-since-draft-v2)); the builder before M4, filed as #572 and built there ([C105](#changes-since-draft-v2)); both fixed on 2026-10-13 in the M4 rows here and in 10 §1 ([C107](#changes-since-draft-v2)); `root of P` after |
| 45 | Owner decisions 44 to 46 add settle work before M6 that no PRD specifies. `split REGION along LINE`, which cuts a region's faces for the mesh only, is missing from 04's `settleitem` and reserved words, [§6](#6-grammar)'s corrections to 04, [D14](#d14-material-consumption)'s regions and 07's `SettleRequest`, and how region words read its pieces and how it names its line are open (owner decision 44). `arc-grip` working out its lengths from the rigid-pose hold on its side, refused when there is none or several, is missing from R-07-15 and R-07-16, 07's note on the grip, which still calls the root strip's length open, D14's *Targets*, both `SettleStepError` sketches, 07's error table and the glossary additions' *Grip*; as written, 07's rows 12–14, 16 and 18 hold no strip on the moving side, so the new refusal reaches them. Owner decision 46 makes fixtures of 07's rows 12–14, which the table marks `yes` (rows 16 and 18 are in item 43); retires the paragraph after that table, which rewrites crane-root's and crane-internal's y = 1/4 id tests at M6; and needs an exception in 09's row re-expressing `CraneRoot`, `CraneBody` and `CraneInternal` by name. D14's count of 16 controls named falls | [ran] item 44's search; owner decisions 44 to 46 (#560) | issue #560, before M6 |

## 11. File plan and writing rules

**Files** (`PRDs/`). Each owns its topic in full; this record owns the decisions.

| File | Owns | Decisions |
| --- | --- | --- |
| `README.md` | index, reading order, the one-page answer, the decision list linking here, milestone table, owner decisions | all |
| `00-overview.md` | the two halves today with evidence; goals; non-goals; the shape; honesty about "realistic" | §1, §2, D18, D19 |
| `01-architecture.md` | module layers and rules; the two contracts; stated exceptions; the recorded-text rows written out; one move traced with real numbers | §2, §3, D1, D13, D14, D23 |
| `02-language-semantics.md` | the semantics both front ends share, down to the refusal catalogue | D2–D11, D20–D22, D24 |
| `03-prd-embedded-dsl.md` | feature 1: the builder, `Ref`s, examples, printing, tests | D1, D12 |
| `04-prd-sequence-source-and-cli.md` | feature 2: EBNF, lexical rules, reserved words, printer, error display, the `run` verb, checked examples | D12, D13, D20, §6 |
| `05-prd-library-additions.md` | every fold-solver addition, L1–L15, with signature, acceptance and proof that no output moves | D4–D6, D8, D10, D11, D19, D20 |
| `06-prd-step-diagrams.md` | step notes, arrows, `Symbol`, captions, turn-over marks, goldens | D5, D6, D7, D22, D24 |
| `07-prd-material-consumption.md` | feature 3a: settles, holds and grips, rest angles, material block, illustrations, certificates, graduation, external tools | D14, D15, D17 |
| `08-prd-realistic-rendering.md` | feature 3b: fidelity axes, M7a, lines spike, W1, G1 animation, #104 | D19 |
| `09-testing-and-acceptance.md` | acceptance per milestone, the quarter-fold tests, E1–E10, budgets, CI placement, migration | D16 |
| `10-roadmap-risks-questions.md` | milestones and order, issue mapping, risks, owner decisions, corrections as issues | §8, §9, §10 |
| `glossary-additions.md` | the one copy of every new term | all |

**What each file changes to match this record.** Every file replaces "the spine",
"spine Dn" and "spine §n" with links here, and drops notes this record has decided,
keeping their evidence where it explains a rule.

- `README.md`: the decision table links anchors here and adds D23, D24; the
  departures table and "where the spine is silent" become a pointer to
  [Changes since draft v2](#changes-since-draft-v2); owner decision 7 takes §9's
  default, and 12 its decided text ([C101](#changes-since-draft-v2)).
- `00`: M4 closes #60.
- `01`: §1.2 rule 4 and its note follow D23; §2.2's `Eq` note points at 05 L14 and
  `recordDisplay` becomes the before/after fields of D14; rows 15–18 join §4;
  §4.13 and its note say "some vertex"; §5.0 drops "02 numbers the same states
  1–3"; §5.5's note points at `prepareFlapToward`; §5.8's seed is (1/4, 3/4).
- `02`: states numbered from 0 (§1, §11); §2.2's intent note and §2.3's centroid
  note stated as decided; §5.3's note replaced by D5's side entry; §6.1 gives
  `anchor` and `mark` `NoMotion` and `expect refused` no record; §8.5 adds
  `macroChecks`; §8.6's note stated as decided; §9 places `expect refused` in a step
  and describes `runStop`; §12 follows D20; §14's G1–G14 become decided rules, with
  G1's claim about the authoring test removed; constructor names `ValleyFold`,
  `MountainFold`, `LayerAbove`.
- `03`: `Moves` and the lowercase builders are decided (owner questions 4 and 5
  removed); A-5 imports constructors that no longer clash; `Place` is adopted.
- `04`: the crane example as [§7](#7-examples); `refine region INTEGER`; the mapping
  table's constructor names; `decodeFile`'s message names no verb and the hint
  moves to `app/` (R-04-18, A7); `RunPlan` holds its own option types;
  `ParseProblem` lives in `Sequence.Error`; `EmptyStep`; the stale "series README
  not yet written" sentences go.
- `05`: L2's milestone note and L4's module note stated as decided; L3 states
  R-05-12′ as the rule; new L14 (`Eq` on `FlapMotion` and `CheckedFlap`;
  `prepareFlapToward`; `FlapStationaryNotFlat`) and L15 (`foldedWalk`); L12's errors
  split with `StackingChoiceError`.
- `06`: R-06-16 uses each record's before and after displays; `stepNotes` returns
  `Either`; the `sample` row of §2's table follows D24; the `Presented` dependency
  is resolved by D14.
- `07`: `Region` becomes `SettleRegion`; the layering note and the "points this file
  adds" are decided; 04's copy of the crane example is reconciled.
- `08`: 05 L15 replaces the "new to 05's list" dependency.
- `09`: the three "differs from spine" notes and owner questions 5–7 stated as
  decided; row 15 exists.
- `10`: §2's note resolved (M2 in the table); §3 gains rows 15–18; §4's #60 closes
  at M4; §6 takes §9's default for 7 and the decided text for 12
  ([C101](#changes-since-draft-v2)).
- `glossary-additions.md`: *Anchor* says vertex mean; *Sequence file* counts state
  0; every "step record" becomes "move record"; *Route evidence* says `NoMotion`
  means no paper moved; a *State* row (D24) is added.

**Writing rules** (AGENTS.md "Audience and tone" and "Writing an explanation" apply
in full):

- The reader knows intermediate Haskell and has never folded paper. A term gets one
  clause and a link to `glossary-additions.md` or `../docs/glossary.md`. Concrete
  before abstract, with coordinates from a command actually run. Name the line that
  looks like a typo. If an example can be misread, fix the example.
- Every code claim cites a `path:line` actually read. Every number says how it was
  obtained (command, run count, machine) or cites the note that measured it. Every
  example sequence is checked against its fixture with `jq` or `python3`, the command
  given, or marked **UNVERIFIED** with what would verify it. Sketches are marked
  **SKETCH**.
- A requirement or acceptance criterion names the set or the check, not its size
  or today's value; a count or a value read from the code or a run carries the
  commit or date it was read at. "The 33 goldens stay byte-identical" was right on
  its day and went false when ten more were tracked ([C116](#changes-since-draft-v2)).
- Decisions are cited as `[Dn](decisions.md#dn-…)`; research by file and heading;
  issues as full GitHub links; all links relative.
- Feature PRDs (03–08) follow: Summary · Problem and evidence · Goals · Non-goals ·
  Users and scenarios · Requirements (`R-<file>-<n>`, each testable) · Design (with
  rejected alternatives) · Acceptance criteria (each naming the change that turns it
  red) · Dependencies · Risks · Open questions for the owner · Research links.
- Say it once and link for depth; tables for enumerations. Nothing under `PRDs/`
  edits another file.
- A file that must depart from a decision says so in a marked note, and the next
  version of this record decides it.
- End with a reread as a Haskell programmer who has never folded.

---

## Changes since draft v2

Every change this record makes to [decisions-draft-v2.md](research/spine-reviews/decisions-draft-v2.md).
*Proposed where* names the PRD file and section whose note raised it, or "here" for
a gap found while deciding. *Evidence checked* is what was re-read or run for this
record. *Files affected* are the PRD files [§11](#11-file-plan-and-writing-rules)
lists edits for.

| # | Change | Proposed where | Evidence checked | Verdict | Files affected |
| --- | --- | --- | --- | --- | --- |
| C1 | Three new pieces, two of them contracts (the `Sequence` value is shared, not a contract) | 00 "What connecting them means"; 01 §2 | v2 §1 says three contracts, its picture labels two | adopted-modified | README, 00, 01 |
| C2 | Sequences today come in four recipe forms, not "every sequence is a recipe naming ids"; two multi-frame FOLD examples exist | 00 "The two halves today" | A2 "Summary" [research]; `file_frames` counts [jq] | adopted | 00 |
| C3 | `Run` defined in `Sequence.Record` without `FoldState`; `Sequence.*` levels; `writtenStates` shared by writer and page; row 7 may import `Sequence.Error` | 01 §1.2 rule 4 note; 06 R-06-20 | v2 DAG row 7 and §5 sketch; no `Internal` module in `src` [ran] | adopted-modified | 01, 02, 03, 04, 06 |
| C4 | `FlapMotion` and `CheckedFlap` derive `Eq` (05 L14) | 01 §2.2 note | `Flap.hs:123`, `:126`; field types' derivings at `Folding.hs:325`, `HingeSweep.hs:89`, `:101`, `Surface.hs:123`, `Rigid.hs:80` [code] | adopted | 01, 05 |
| C5 | The hinge turn takes a raw side; `Flap` sets the first segment's sign from its stationary face (`prepareFlapToward`, `FlapStationaryNotFlat`); superseded in part by [D5](#d5-presentation-and-the-readers-side)'s amendment, which reads the moving face | 02 §5.3 note; 01 §5.5 note | `Flap.hs:10-16`, `:276-301` [code]; edge 9 +180, edge 11 −180 [prd] | adopted-modified | 01, 02, 05 |
| C6 | Two settle error types: `SettleStepError` wraps `Material.Settle`'s `SettleError` | 07 "SettleSpec and SettleInput" note | layer rule: `Material.*` knows no moves (§2) | adopted | 01, 02, 07 |
| C7 | `closing` is written after the last step, stored as `hClosing` | 04 ambiguity table | 04 grammar `source` production | adopted | 02, 03, 04 |
| C8 | `expect refused` is a move inside a step, produces no record and no state, and is kept in the `Run` | 02 §6.1, §9; 04 ambiguity table; 06 §2; 09 E10; 02 G12 | v2 D10 has no refusal constructor; `BlintzSequenceSpec.hs:111-116` [code] | adopted-modified | 02, 04, 06, 09 |
| C9 | The crane example expects `FlapCovered`, **UNVERIFIED** | 02 §9 | selection rule order (D8); finding 14 is inferred [research] | adopted | 04, 07 |
| C10 | A `not modelled` stop returns `Right` a `Run` with `runStop`; `runRefusal` gives the CLI its error | 04 R-04-28, A18; 09 M2 (g) | v2 D21 text against its `Either SequenceError Run` type | adopted-modified | 02, 04, 09 |
| C11 | `SequenceError` gains `SheetRefused` and `WriteRefused`; `StaticRefused` carries a `Place` | 02 §14 G14; 03 "Refusals from a built sequence" | v2 §5 errors sketch | adopted | 02, 03, 04 |
| C12 | `together` is one record with `recordMacros :: [MacroBinding]`, each naming its line | here (02 §8.4, §8.5) | v2 `recordMacro :: Maybe MacroBinding`; bird press step | adopted-modified | 02, 05, 07 |
| C13 | Tree refinements: `MidpointOfEdge`, `StackingSpec`, `Located` header fields and `together` members | 04 ambiguity table | v2 grammar `midpoint of edge north` in its crane example | adopted | 02, 03, 04 |
| C14 | No move outside a step; the diamond start is a first step | here | v2 §7 crane opening and crane wing examples against v2 §6 grammar | adopted | 04, 09 |
| C15 | Optional captions; `fold and unfold` takes no angle; string escapes; `n/0` a parse error; reserved words never names | 04 lexical and ambiguity tables; 03 note | v2 grammar allowed a precrease angle | adopted | 02, 03, 04 |
| C16 | Batching stays inside one step; corrected example | here (02 §6.5) | v2 D22 lines 939-940 contradict themselves | adopted-modified | 02, 05 |
| C17 | Intent at start: F beyond τ becomes M or V; U stays U | 02 §2.2 note | `StudyCase.hs:208`, `Flap.hs:262` [code] | adopted | 02, glossary-additions |
| C18 | `checkpoint` reads angles by `foldAnglesOf`, as `start folded` does | here | `Folding.hs:521-547` [code]; v2 D21 | adopted-modified | 02 |
| C19 | An anchor a new crease passes through moves to the largest unturned piece; 02's claim that the authoring test hits it is removed | 02 §14 G1 | 09 §2.3 writes `anchor (3/4, 1/4)` [prd] | adopted-modified | 02, 09 |
| C20 | The default anchor is a vertex mean, not a centroid | 02 §2.3 note | `StudyCase.hs:242-248` [code] | adopted | 02, glossary-additions |
| C21 | G2–G13 decided: moving side of O5–O7 (G2); `turned` direction and `white side up` axis (G3); repeat compares hinge turns (G4); `UnfoldChangedSince` (G5); lockstep (G6); weakest order and `NoMotion` for `anchor`, `mark` (G7); folded positions in material slots (G8); macro landing with several stackings refused (G9); sample range (G10); compass names need a square outline (G11); `expect refused`-only steps (G12); default anchor outside its face (G13) | 02 §14 | blintz quarter-turn image [py]; `crane.fold` corners 5.8e-15 off [prd] | adopted (G4, G7, G11 modified) | 02 |
| C22 | A step's body has its own type, `Moves` | 03 note; owner question 4 | v2 `step :: … -> Build () -> …` | adopted | 03 |
| C23 | Syntax constructors renamed `ValleyFold`, `MountainFold`, `LayerAbove`; lowercase builders; `SettleRegion` | 03 note; owner question 5 | `Types.hs:302-305`, `:334-336`; `Visible.hs:103` [code] | adopted-modified | 02, 03, 04, 07 |
| C24 | `canonical` normaliser in the round-trip property | 04 "Canonical form" | 04's four-row table | adopted | 03, 04 |
| C25 | `decodeFile`'s message names no command; `app/` adds the `run` hint | 04 §"Reading a source" note | `Load.hs:131-136`, `Query.hs:68-71` [code] | adopted-modified | 04 |
| C26 | Presentation change: *some* vertex moves (R-05-12′) | 05 L3 note; 01 §4.13 note | 3 of 9, 3 of 9, 5 of 13, 2 of 8 axis vertices; 0 of 15 and 0 of 2 rigid pairs [py] | adopted | 01, 05 |
| C27 | `creaseAllAlongWith` at M2 | 05 L2; 10 §2 note | `Creasing.hs:138`, `:290-292`, `:316-320`; `CraneWing.hs:114` [code] | adopted | 05, 10 |
| C28 | `RoutePose` in `Origami.Route`, re-exported by `Sequence.Record` | 05 L4 note | layer rows 4 and 6 | adopted | 05 |
| C29 | τ = 1e-10 degrees | 05 L1 | `Surface.hs:278`, `StudyCase.hs:208` [code] | adopted | 05 |
| C30 | `AtRest` writes the whole angle array when a frame has none | 05 R-05-8 | `Folding.hs:521-547` [code] | adopted | 05 |
| C31 | `RequestRefused` wraps refusals only in batches of two or more | 05 R-05-30 | 05's `ThroughLayersSpec` cases [prd] | adopted | 05 |
| C32 | Library `StackingError` holds face-id relation errors; `StackingChoiceError` holds the counting policy | here (05 L12 against 02 §12) | `Stacking.hs:386-400` [code] | adopted-modified | 02, 05 |
| C33 | `StepNote` carries marks | 06 §1 | v2 D7 field list lacks marks while M3 includes them | adopted | 06 |
| C34 | A turn-over axis projecting to a point draws its loop as if page-vertical | 06 §5 | `withArrows`' 1e-6 cut-off [prd] | adopted | 06 |
| C35 | `render --steps` never draws `frame_title`; #94 closes at M3 through `run -o .svg` | 06 §9 | #94 done-when read with `gh issue view 94` [ran] | adopted | 01, 06, 10 |
| C36 | `GivenArrows` per connected moving group | 06 R-06-16 | `Step.hs:175-192` [code] | adopted | 06 |
| C37 | `StepError` unchanged | 06 R-06-3 | `Steps.hs:58-62`, `Cli.hs:969-977` [code] | adopted | 06 |
| C38 | Authored samples are states and figures without caption or arrows; checking adds `RunSettings.macroChecks` interior poses | 06 §2; 03 A-6 | v2 D9 ties evidence to illustration | adopted-modified | 02, 05, 06 |
| C39 | `NoDifference` without the "released hold" clause | 07 note | rigid control 1.39e-11 / 1.44e-27 [research] | adopted | 07 |
| C40 | Controls the vocabulary cannot name stay fixtures | 07 control table | `CraneRoot.hs:88`, `CraneBody.hs:80` [code] | adopted | 07 |
| C41 | `refine REGION INTEGER` and a `rest` line in the crane settle | 07 note under the crane block | control 2 needs a region; R-07-19 | adopted | 04, 07 |
| C42 | 07's proposed rules R-07-10, -13, -16, -17, -19, -22, -29 | 07 "Points this file adds" | each against v2 D14 | adopted | 07 |
| C43 | Silhouettes from edges of any assignment; #104's done-when names `--view front` | 08 R-08-17, "#104, amended" | 27 silhouettes front, 0 iso [py]; 40 `B`, 280 `F` [jq]; #104 text [ran] | adopted | 01, 08 |
| C44 | One animation hierarchy per checkpoint interval; `StateOnly` transitions switch sub-hierarchies; complete scene | 08 R-08-24, -27, -30 | `checkpoint` breaks the prefix rule (D6) | adopted | 08 |
| C45 | `Origami.Folding` exports its walk's tree (05 L15) | 08 Dependencies | `Folding.hs:586-591`, `:342-344` [code] | adopted | 05, 08 |
| C46 | Records keep presentation and anchor placement, before and after | 06 Dependencies | v2 single `recordDisplay` | adopted-modified | 01, 02, 06, 08 |
| C47 | Geometry level "as read"; W1's edge-on threshold 1e-9 | 08 Design | `Shadows.hs:92` [code] | adopted | 08 |
| C48 | Test 2 matching rules T1–T5 | 09 §2.3 note | hand-built frames: v2 clauses false, T1–T2 true [py] | adopted | 01, 09 |
| C49 | Test 2 lands with the later of M3 and M4 | 09 §2.3 note | step 2 creases two layers (L8, M4); page needs L5 (M3) | adopted | 09, 10 |
| C50 | Recipe goldens rebuilt from records through `flapAt` | 09 §9 note | `BlintzSequence.hs:75-87`, `HelmetSequence.hs:70-86` [code] | adopted | 09 |
| C51 | A slow job and "all three CI checks": row 15 and owner decision 12 | 09 §6.3 note | `AGENTS.md:390`; `ci.yml` jobs [code] | adopted-modified (owner decision 12, decided 2026-10-12, [C101](#changes-since-draft-v2)) | 09, 10 |
| C52 | Test 1 compares angles exactly | 09 §2.2 note | `Flap.hs:469` [code] | adopted | 09 |
| C53 | Golden check with `--diff-filter` and three dots | 09 §1.2 | both commands print nothing [ran] | adopted | 06, 08, 09 |
| C54 | #60 closes at M4 | here (10 §4 note said M3) | 09 §2.3's milestone | adopted-modified | 10 |
| C55 | #54 advanced, not closed; #96 amended at M0 | 10 §4 | issue checklists per 10 [prd] | adopted | 10 |
| C56 | `docs/roadmap.md` order passages as row 16 | 10 §3 | `docs/roadmap.md:271-276`, `:1004-1009` [code] | adopted | 01, 10 |
| C57 | Caption overlap: recommended gutter ≥ 42/340 on captioned pages | 06 open question 7; 10 §6 | 06 §8 arithmetic [prd] | adopted-modified (owner decision 7 with default) | 06, 10 |
| C58 | The petal literal is three ulps from the code's `atan2` form | 10 §7.2 item 16 | `CheckedPetal.hs:107` [code]; [py] | adopted | 10 |
| C59 | States numbered from 0 as `file_frames` index; `--frame k+1` | here (01/06/09 against 02) | `Types.hs:209-210`, `Cli.hs:515-524`, `usage.md:1841-1842` [code] | adopted-modified | 01, 02, 04, 06, 09 |
| C60 | "Anchor placement", "move record"; "step record" retired | glossary-additions; v2 D3 | `grep` of "step record" [ran] | adopted | glossary-additions |
| C61 | Pose angles converted once for the whole model | 02 §8.6 note | quarter-fold half-way pose [prd] | adopted | 02 |
| C62 | `Sequence.RunPlan` holds its own option types | here (04 `Plan`) | `Camera.hs:188`, `Gltf.hs:160` [code] | adopted-modified | 04 |
| C63 | Glossary *Sequence file* counts state 0 | 03 A-6 note | 02 §11 layout | adopted | glossary-additions |
| C64 | Row 14's range is `docs/architecture.md:288-297` | 01 §4.14 | `grep -n` [ran] | adopted | 10 |
| C65 | Row 12 lands in two PRs (`runSequence` at M2, `stepPageWith` at M3) | 01 §4.12; 10 §3 | `stepPageWith` takes a `Budget` | adopted | 01, 10 |
| C66 | The `LineStopsOnTheModel` sentence as row 17 | 10 §3 | `ThroughLayers.hs:196` [code] | adopted | 01, 10 |
| C67 | Existing library messages keep bare ids in v1 | 05 open question | pinned sentences in specs and docs [prd] | adopted-modified (decided, follow-up issue) | 05 |
| C68 | A record's seed for `L1 to L2` is the vertex mean of the face beside L1's longest segment | here (01 §5.8 left it to 02) | (1/4, 3/4) on quarter-fold step 2 [py] | adopted-modified | 01, 02 |
| C69 | An existing `F` hinge is refused as `ExistingHingeFlat`, with residue | 02 §6.2 | `Flap.hs:262` [code] | adopted | 02 |
| C70 | `bird-base-sequence-arrows.svg` pinned before 05 L3 | 09 §1.3; open question 7 | no golden draws that file with arrows (`BirdSequenceSpec.hs:79` passes `False`) [prd] | adopted | 09 |
| C71 | Existing `runIO` specs unchanged until their deletion PRs | 09 open question 6 | 14 spec files use `runIO` [prd] | adopted; excepted for the slow study spec files by [C101](#changes-since-draft-v2) | 09 |
| C72 | The crane's existing-crease count is 6 (the research note's count line says 7) | 02 §6.2 | the note's table [research] | adopted | 02 |
| C73 | A step with no move other than `let` is refused as `EmptyStep` | here | 04 grammar allows an empty block | adopted | 02, 04 |
| C74 | `README.md` and `docs/roadmap.md` roadmap item 2 as row 18 | 10 §4 note | `README.md:213` [ran] | adopted | 01, 10 |
| C75 | `MoveRecord` as built at M2 (#486, #487): opaque, made only by `hingeTurn` from a `CheckedFlap` and read through functions, so record update cannot pair one turn's paper with another's; `recordSpan` → `recordOrigin`, which keeps the move as written; `recordLabel`, the step's caption, → `recordCaption`; `recordPath` → `recordStepName`, one name while a step's is the only one a move sits under; `recordStationary` a bare `FaceId`; `recordAngles` read from the surfaces; every other field arrives with the first move that fills it. `MaterialPoint` and `MaterialSegment` were built in `Sequence.Record`, where the record first needed them; `MoveFailure`'s constructors that name them sit at level 2, so both move below `Sequence.Error` with the first such error | here; #282 | `Sequence.Record` [code] | adopted-modified | 01, 07 |
| C76 | The `not modelled` stop as built at M2 (#498): `MoveFailure`'s `NotModelled` is `NotModelledStop`, because `Sequence.Syntax.NotModelled` is the move and four modules import both whole (C23 renamed clashing constructors the same way); `runStop` is `Maybe RunStop`, the step, its name, the move's span and the text, since `runRefusal`'s `StepRefused` needs the span for `path:line:col`; the stop has no refusal kind, so `expect refused` around a `not modelled` passes it on and the run stops there | D21, C10 | `Sequence.Run.runStep`, `Sequence.Record.runRefusal` [code] | adopted-modified | 02, 04, 09 |
| C77 | The writer as built at M2 (#499): `writtenStates :: Run -> Either SequenceError [WrittenState]`, refusing as `WriteRefused` with the state's number, which a bare `WriteProblem` could not carry; `WrittenState` holds the step that produced it and its frame. `Run` gains `runTitle`, `runStart :: Surface V2` (the sketch's `StateView`), `runSteps :: [StepOutcome]` (step, name, caption, and the state it ends at, `Nothing` for a step of only `expect refused`) and `runClosing`; `RunStop` gains the stopped step's caption, which titles the last state written. `senbazuru:assurance`, whose shape no PRD gave, is a list of `{"move": i, "evidence": "SweptHinge"}`, one per record of the producing step, `[]` for a step that made none, absent on state 0. No display is applied until `turn over` lands. An anchor the header names now reorders the sheet's faces from the sheet's own order, not from the default anchor's, which had moved a second face: test 1's face ids match the fixture's only so | 02 §11, D24, 09 §2.2 | `Sequence.Record.writtenStates`, `Sequence.Write`, `Sequence.Run.startOf` [code] | adopted-modified | 01, 02, 09 |
| C78 | `recordResolved` and the report as built at M2 (#500): `ResolvedReference` is `ResolvedLine` (the fold line as written, where the paper lay: through its point nearest the middle of the paper, pointing east, or north for a line running north-south, as a refusal's candidate lines are shown), `ResolvedSeed` (the words naming the moving paper, and the point they named), in sheet lengths, and `ResolvedTurnedBack` (the step an `unfold` turns back); a fold resolves the first two, an `unfold` the last. The parts inside a line, such as edge north's edges 4 and 5 in 01 §5.8's example, are not yet kept. `renderRunReport` gives each move a heading, step and move with the move as the printer spells it, then one fact to a line (checked, line, named by, moving, hinge, held still), each expected refusal on its own heading, and the stop last; ids as `(internal edge 8)` (D20), numbers rounded to six places, which rounds away the last bits in which platforms differ | 04 R-04-24, A19; 01 §5.8 | `Sequence.Record.renderRunReport`, `Sequence.Run.foldMove` [code] | adopted-modified | 01, 04 |
| C79 | New creases as built at M2 (#495): only on the flat sheet, every crease at rest; on folded paper the line crosses layers and the move is refused as not run yet (M4). Each crossed face's stretch of the line is carried to the sheet by the fraction along the face's edges, since a rigid placement keeps fractions, and stretches meeting end to end are one crease. The crease is drawn by `creaseAllAlongWith AtRest`, lettered by the raw sense (D5), and the anchor's face is put first again. A crease through the anchor moves it as C19 says, to the vertex mean of the largest face around it that the move does not turn, chosen by `sheetState`'s default-anchor rule; which faces turn is chosen on the creased state as traced, which is safe because every face of the flat sheet lies where it lies whichever is held still, and then again with the anchor's face first. `recordAnchor` holds the anchor before and after, and the report says `anchor moved: (0.5, 0.5) to (0.333333, 0.666667), off the new crease`. `hingeTurn` takes the new creases after the hinge, and `recordNewCreases` holds them as `[(MaterialSegment, [EdgeId], Assignment)]`; the report gives each its own line in sheet lengths, as it gives the line and the seed, `new crease: (0, 0) to (1, 1), valley (internal edge 4)`. `unfold` and `hinge of` a move made before the paper was creased again find its creases again, since creasing renumbers edges and re-traces faces: an edge by its two vertices, which creasing never renumbers, its pieces as the edges between them, and the moving side by which way round the faces run along the crease; the unfold's record numbers them as they are now | 05 L2, D3, D5, D8 | `Sequence.Run.creaseAcross`, `Sequence.Resolve.chordsAcross` [code] | adopted-modified | 02, 04 |
| C80 | The pre-crease as built at M2 (#496): `MoveKind` is `Turn`, a fold or the unfold of one, and `Precrease`; `recordKind` reads it. A pre-crease runs as its fold does, resolved, creased, sweep-checked and refused by the same kinds, with its new creases drawn U; `asPrecrease` then makes the record of kind `Precrease` and its after the before, keeping the fold's evidence, and the working pattern takes nothing from the turn. A crease the paper already had keeps its letter: a pre-crease changes nothing but its new crease (02 §6.4), so one along an existing crease leaves the paper as it was. The report adds `laid flat again: the paper ends where it began` | owner decision 14, D3, D12, 02 §6.4 | `Sequence.Run.foldMove`, `Sequence.Record.asPrecrease` [code] | adopted-modified | 02, 04 |
| C81 | Presentation as built at M2 (#95): `FoldState` holds a presentation `Rigid` in place of a stored reader's side, which `frontOf` reads from it, the coloured side until the presentation sends ẑ to −ẑ. `turn over left-right \| top-bottom` composes D5's exact turn about the displayed state's middle onto the presentation, checked by `isProperRotation`, and refused as `PresentationImproper` if that ever fails; `white side up` starts with the left-right one (G3). Its record is made by `presented`: one surface before and after, evidence `Presented`, kind `Presentation`, no hinge or moving paper, the anchor's face held; `recordPresentation` holds (before, after) on every record, a turn's two equal. `recordPlacement` waits for re-anchoring (#497). Written frames are presented, each state's vertices moved by the presentation it ended with (`StepOutcome`'s `outcomePresentation`, `Run`'s `runStartPresentation`); the identity leaves coordinates as folded, so a run with no turn-over writes the bytes it wrote before. The report says `presented: the whole model shown from its other side; no paper moved` and lists no moving paper for it. `rotate` comes next, and its eighth turns wait on owner decision 10 | D5, D10, 02 §5.2, G3 | `Sequence.Run.turnOverAbout`, `Sequence.Record.presented`, `Sequence.Record.writtenFrame` [code] | adopted-modified | 02, 04 |
| C82 | `rotate` as built at M2 (#95), by whole quarter turns: `rotate k/8 turn` with k even composes D5's exact turn about the line parallel to +z through the displayed state's middle onto the presentation, so the reader's side stays and the turn is anticlockwise or clockwise as the reader sees the model, after a turn-over too. Its entries are 0 and ±1 (`quarterTurnsAbout`), built with the turn-over's by one function, `aboutMiddle`. An odd k is refused as not run yet until owner decision 10. `MoveKind`'s `Presentation` carries a `Presenting`, `TurnedOver PageAxis` or `Rotated Int Turning`, as written. That settles [06](06-prd-step-diagrams.md#dependencies)'s open question the first way it names: the record keeps a rotate's k and direction, because 14 written rotates make only 7 motions. The report says `presented: the whole model turned on the page, the same side up; no paper moved` | D5, owner decision 10, 02 §5.2, 06 "Dependencies" | `Sequence.Run.quarterTurnsAbout`, `Sequence.Record.Presenting` [code] | adopted-modified | 06 |
| C83 | Re-anchoring as built at M2 (#497): a fold or an unfold whose moving paper holds the anchor's face re-anchors before it turns. The new anchor is the vertex mean of the largest face beside the hinge that the move holds still, ties to the lowest, then leftmost, vertex mean; C19's move off a new crease is the same `reanchor` over the faces around the anchor. That face goes first and the layer orders are renumbered with it. `FoldState` gains `thePlacement`, which takes on h, that face's placement in the fold, so the model stands where it stood, checked refolded within 1e-12 of the model's size, and the fold line and its paper are then named afresh (the line carried instead since [C108](#changes-since-draft-v2)). The reader's side is read from the display, presentation `after` placement, so after re-anchoring onto paper lying face down a valley still goes towards the reader. Each half of `recordPlacement` is the placement its surface is shown with: a re-anchoring move re-roots before it turns, so both halves are the new placement and the change shows between records, with `recordAnchor`'s pair; `displayBefore` and `displayAfter` compose them, placement first. Written states are displayed, and a state with the same faces as the one before it numbers them as that one did (`numberedAsBefore`), because re-anchoring renumbers faces the paper did not change and the page pairs states by id. `ReanchorNotFlat` refuses a new face whose displayed normal is not ±ẑ: a fold never meets it, since paper is named only on flat states, and an unfold does once a later fold has stood up the paper beside its hinge. The report says `anchor moved: … off the paper the move turns`; its fold line stays in the record's frame, as a refusal's candidate line does (C78), so after re-anchoring onto moved paper it is where the line lies as folded from the new face | owner decision 3, D3, D14, 02 §2.3 | `Sequence.Run.reanchor`, `Sequence.Record.numberedAsBefore` [code] | adopted-modified | 01, 02 |
| C84 | `anchor P` as built at M2 (#497): P is named on the flat state as the header's anchor is, a region slot strictly inside one face (`NotInOneFace` otherwise, and `ConstructionInTheAir` on paper standing up, where no paper is named), and the run re-anchors onto that face with the anchor at P, through the same `reanchorAt` a re-anchoring fold uses, so its placement, layer-order renumbering, join check and `ReanchorNotFlat` are C83's. Its record is made by `anchoring`: one surface before and after, held from the new anchor's face as a re-anchoring move's are, so both halves of `recordPlacement` are the new placement; `recordAnchor` is (the anchor before, P); kind `Anchoring`; evidence `NoMotion`, the constructor D10 and G7 name for it, with no hinge and no moving paper. The written state after it is the state before it, faces numbered alike. The report says `nothing turned: no paper moved` and `anchor moved: … where the move names it` | D3, D10, G7, 02 §2.3 | `Sequence.Run.reanchorAt`, `Sequence.Record.anchoring` [code] | adopted-modified | — |
| C85 | `unfold` naming a step that turns no paper is refused statically as `TurnsNoPaper` (#527's review). 02 §6.4 defines an unfold as reversing the named steps' net angle changes, so a step of only `turn over`, `rotate`, `anchor`, `mark` or `checkpoint` has none, and its unfold ran as nothing, silently: the step wrote the state before it again and the report printed nothing for it. Whether a step turns paper needs no paper to see, so the checker refuses it, after `NotAFigure`, as `continue` and `hinge of` refuse the wrong kind of step. A pre-crease turns paper and is still accepted, its unfold skipped when run as §6.4 says; `repeat` of such a step is accepted, since a turn-over done again means something | 02 §6.4, §12 | `Sequence.Check.turnedNamed` [code] | adopted-modified | 02 |
| C86 | The helmet base runs as a sequence (#502), PRD 09 §9's second migration, as #493 did the blintz: three folds named by corners (the diagonal, then each corner of the doubled triangle laid on the tip), anchored at the south-east square face's middle, equal to `HelmetSequence`'s recipe in end angles exactly, layer orders by count and as sets, every point within 1e-12, and `checked-helmet.svg` byte for byte through the recipe's page function. Each corner fold resolves one line to two creases on different layers. That showed `hingeStretches` joining any two hinge edges that met on the sheet, so the record named one stretch along edge 10 carrying edge 12, which runs at right angles to it; stretches now join only along one line on the sheet. Edge ids, which `unfold` and `hinge of` read, were right throughout | 09 §9, D14 | `Test.SequenceExamples.helmet`, `Sequence.Resolve.hingeStretches` [code] | adopted | — |
| C87 | `BlintzSequence` deleted (#503), PRD 09 §9's second PR for the blintz. The study's gallery runs `blintz.foldseq` and draws `checked-blintz.svg` from the run: the open square, each turn halfway from its record's `SweptHinge` turn, and each record's end (`BlintzGallery.blintzStates`), byte for byte the recipe's page, which is now the guard the recipe comparison was, with `examples/blintz-sequence.fold` for every written state. Each assertion of the recipe's spec moved to `BlintzRunSpec` on the run's turns, each turn's start folded again from the working pattern with the angles and orders of the record's surface before; `RecordSpec` and `ResolveSpec` take their turns and their state after the first fold from a run. `HelmetSequence` stays, its deletion not yet filed | 09 §9 | `BlintzGallery`, `Senbazuru.Sequence.BlintzRunSpec` [code] | adopted | — |
| C88 | Sheet lengths converted in one module (#505), `Sequence.SheetLengths`: `sheetLengthOf`, `inSheetLengths` and `fromSheetLengths` for points and `lengthInSheetLengths` for distances, on the sheet's box. 01 §4.11 placed the conversion "when `Sequence.Run` resolves a reference", in the resolver; the run report (#500) had since kept its own copy, dividing where the resolver multiplied by a reciprocal, because it lives in `Sequence.Record`, which the resolver imports. The one place therefore sits below both, knowing no paper; the resolver, the runner's `ReanchorNotFlat` and the report call it, and AGENTS.md points at it. Physical lengths keep the plan: one place, with the `material` block at M6 | 01 §4.11, decisions §3 row 11 | `Sequence.SheetLengths` [code] | adopted-modified | 01 |
| C89 | Each record's cost as built at M2 (#504), E2's second half: `StepCost`, `costSweepIntervals` and `costRefolds`, read by `recordCost`. Counted where the work is done, never timed. A `CheckedFlap` counts its own refolds (`flapRefolds`): one for its start, and one for each pose preparation tries and each end whose order is checked, those two taken from the lists that drive the folds, so a pose added to a list counts itself; the start, and the record's two surfaces below, are single calls counted beside them. `hingeTurn` adds one for each of the record's two surfaces. The runner adds its own (`addRefolds`): `FoldState` keeps a running count, `foldNow` is the runner's one call of `foldFrameWith` and now keeps the fold it makes, and a move's refolds are the difference across it, the join check's included, which can only be counted once the record exists. A turn-over, a rotate and `anchor P` count no sweep. Set from a reviewed run: each blintz move is 1 sweep interval and 8 refolds, 3 preparing, 2 checking, 2 surfaces and 1 join check; 09 §6.1's "about 7 per checked step" was the recipe's, which built only its end surface. `--report` prints a move's counts as `work:` (04's "Work counts"). An `expect refused` move makes no record, so the work of its refused attempt is not counted: 09 §6.1 sums a run's cost over its records. Which count takes the time is not measured here; these are counts | 09 E2, §6.1; 01 §5.8; 04 report table | `run --report` on `blintz.foldseq` [ran] | adopted | 02, 09, 10, glossary-additions |
| C90 | `Origami.Route` waits for its producer (#504). 05 L4 puts it at M2 "for records", but it holds `RoutePose`, which only `flapPoseAt` makes, at M6 or M7b; a module holding a type nothing makes is a promise no test can check, as #486 found for the record's unfilled fields. It lands with `flapPoseAt`; C28's placement stands | 05 L4, C28 | no `RoutePose` producer in `src` [code] | adopted-modified | 05, 10 |
| C91 | Eighth turns as built at M2 (#95), owner decision 10: `rotate k/8 turn` with k odd turns by the matrix whose entries are ±`sqrt 0.5`, about the displayed state's middle as a quarter turn is, so `rotate` now takes 1 to 7 eighths. Not `rotationAbout`, which D5 named: it takes cos and sin from the platform's library, and they disagree at π/4, 0.7071067811865476 and 0.7071067811865475 with GHC 9.6.7 on macOS, so a turn built from them is not even symmetric. `sqrt` is one of the operations IEEE 754 requires to round correctly, so R9's platform bits do not arise and 09 §8's eighth-turn row does not apply; its first row, folded positions carrying folding's own cos and sin, still does. What remains is rounding: written coordinates after an odd eighth are not exact, and an eighth there and back lands within rounding of where it began. Quarter and half turns keep entries 0 and ±1 | owner decision 10; D5; 10 R9; 09 §8 | `sqrt 0.5` against `cos (pi / 4)` and `sin (pi / 4)` in GHC [ran] | adopted-modified | 02, 03, 04, 06, 08, 09, 10 |
| C92 | `HelmetSequence` deleted (#534), PRD 09 §9's second PR for the helmet. Its sequence was Haskell only, `Test.SequenceExamples.helmet`, which the study executable cannot import. Its text is now `helmet.foldseq` at the root, and both the study's gallery and `HelmetRunSpec` run that file, so they cannot run different sequences; the Haskell copy, which nothing else used, is gone. The gallery loads the sheet the source names (`sourceFiles`), as the run command does, and draws `checked-helmet.svg` from the run (`HelmetGallery.helmetStates`): the open square, the first turn at 120° and each corner at 90° along its record's `SweptHinge` turn, and each record's end. That is byte for byte the recipe's page, which is now the guard the recipe comparison was. Each assertion of the recipe's spec moved to `HelmetRunSpec` on the run's turns, each turn's start folded again with the faces, angles and orders of the record's surface before. The scale cases now run the whole sequence and compare it with the unscaled run. The backwards-winding cases became one check that the runner reads a backwards sheet as the same state as the forwards one; `FlapSpec` and `FoldingSpec` keep the library's own re-winding. The run's comparisons with the recipe became literals: each move's end angles and layer orders | 09 §9 | `helmet.foldseq`, `HelmetGallery`, `Senbazuru.Sequence.HelmetRunSpec` [code] | adopted | — |
| C93 | The blintz and helmet galleries share one pipeline (#537), `SequenceGallery`. It reads and checks a source, loads the sheet the source names from where the source says, keyed as the source writes it, as `run` does (`sourceFiles`), runs it, draws each turn part-way from its record's `SweptHinge` turn, and writes the page, its FOLD file, a GLB per figure, the checks, the viewer and the HTML page. `BlintzGallery` and `HelmetGallery` are one `Gallery` each, holding only what differs: the name, the source, the output directory, the title, the camera's view direction, the page size, one part-way pose per move, and the HTML template. A pose is a fraction of that record's own turn, with the words its figure's title takes, so the helmet's 120° is 120/180 of a half turn; a run of more or fewer moves than poses is refused. Two drifts between the copies are gone: the blintz loads its sheet as the helmet did, rather than naming `examples/blintz-base.fold` a second time, and takes its open square from the first record's surface before, as the helmet did, rather than its first turn at 0, the same paper. The closing message counts the figures it wrote | here; #535's review | `SequenceGallery` [code]; both galleries on main and here, every written file identical by `diff -r`, the figures' titles included, which the SVG goldens do not draw [ran] | adopted | — |
| C94 | Folding turns without `cos` and `sin` at multiples of 45° (#536), as owner decision 10 did for `rotate`. `Geometry.Rigid.rotationAboutDegrees` takes a crease's angle in degrees, as files and `Folding` hold it. At an exact multiple of 45° it uses 0, ±1 and ±`sqrt 0.5`, correctly rounded and so the same on every platform; the test compares the angle with 45 k as exact rationals, so no other angle is moved onto a multiple. There it also writes each diagonal entry as x² + (1 − x²) cos θ, since (1 − cos θ) x² + cos θ rounds at 135°, where 1 + `sqrt 0.5` is not a `Double`; the matrix of a turn about a coordinate axis then holds 0, 1, cos θ and ±sin θ and nothing else, though a position still rounds wherever √½ multiplies it. Any other angle turns as `rotationAbout` of `d * pi / 180`, bit for bit. `Sequence.Run.eighthTurnsAbout` is now `rotationAboutDegrees` about the vertical through the model's middle, the same matrix as its written-out table, bit for bit. `sin pi` is 1.2e-16, so a flat fold's paper lay about 1e-16 off its plane: the blintz's written sequence had 13 of 144 coordinates at z = −4.33e-17. Coordinates folded only by multiples of 45° now take no number from the platform's trigonometry, though the sweep that checks a turn and the tracing of faces still use `cos`, `sin` and `atan2`. So 09 §8's first row holds only for other angles, such as the bird's poses, and `examples/blintz-sequence.fold` is held exactly, E5's tolerance 0, as CI checks on Linux; `examples/bird-base-sequence.fold` is regenerated, within its 1e-12. Rows that compare placements with `rotationAbout` of `degrees × π / 180` exactly (05 L15's R-05-48, 08's statement of `Folding`'s rule) hold only off the multiples, and 01 §5.9's "up to 1.2e-16 off, because sin π" no longer holds, since a flat fold's sine is now 0. Measured beforehand with a throwaway version: no test or golden changed. `docs/notes/exact-turns.md` | #536; 09 §8 | suite unchanged; the blintz file's only change 13 z values from −4.33e-17 to 0 [ran] | adopted | 01, 05, 08, 09 |
| C95 | No `Rigid` can mirror or stretch (#542; §10 item 19, D5's residue), as the owner chose on 2026-10-11. `Geometry.Rigid` no longer exports the constructor, and `rigidLinear` and `rigidOffset` are plain functions, since an exported record field would let `r { rigidLinear = m }` past any check. `translation` makes the four pure translations that were built by hand, and `rigidFrom` admits a matrix made elsewhere only if `isProperRotation` does; `fitRigid` and the study's frame alignment call it, and it returns `Maybe`, as `fitRigid` does, since the geometry layer has no error type (`docs/architecture.md`). `Mat3 (..)`, the other half of item 19, stays exported: a `Mat3` is not a motion, and the only way from one to a `Rigid` is `rigidFrom`. The type does not promise a turn to the last bit: a long chain of general turns drifts, past 1e-12 after some 7,300, and an angle that is not finite or overflows in radians gives a matrix of NaN (the module header). The runner's turn-overs are `rotationAboutDegrees` half turns about the model's middle, the same bits as the matrices written out before. `PresentationImproper` (C81) is dropped. A presentation is a product of the runner's turns, by eighths about the vertical and halves about the horizontal, and those composed in any order make only 32 matrices, each within 4.4e-16 of a proper rotation, where the check allowed 1e-12; `RigidSpec` checks all 32 instead. D5's Exactness and Residue now say so. Superseded elsewhere: 02 §5.2's check, §2's 1e-12 among a run's tolerances and the `NotAProperRotation` row; 05 L3's "exported unchecked" and R-05-11; glossary-additions' "Proper rotation" row; and 10's item 19 | §10 item 19; D5; 10 §7.2 item 19 | turn-overs compared through `show` with the written-out matrices over five middles; the runner's turns composed in every order until no new matrix appears [ran] | adopted | 02, 05, 10, glossary-additions |
| C96 | M2's interfaces as built, where §5, D4, D11, D13, D20 and D23 planned them otherwise and no row said so (#544); each now carries a note. `runSequence` takes `RunSettings` and the sheets as `FoldFile`s, the layer budget being the field `runBudget`: #501 planned it so without giving a reason, where [review L4](research/spine-reviews/review-L4-conventions-consistency.md) L4-4 had proposed a separate `Budget` argument, and PRDs 00–04 pass one; §2's diagram now shows the budget inside `RunSettings`. `RunSettings` holds `runSweep`, `runNearMissBand :: Double` (owner decision 2's 1e-3) and `runBudget`; `keyDensity` and `keySubdivisionBudget` wait for M7b's animated export, and `macroChecks` for M5's macros. `sheetState` takes the `FoldFile` and reads its key frame, and `startOf` refuses `start folded` before calling it, as `StartFoldedNotRunYet`; D3 notes both. `hingeTurn` takes 13 arguments. `ResolveRefused` takes a `Place` instead of the step's number and name, as `StaticRefused` does, so a refused anchor in the header names the header. `ReanchorNotFlat` holds the new anchor as a `V2` in sheet lengths and its face's tilt in degrees, so no built `MoveFailure` names a `MaterialPoint`, and `MaterialPoint` stays in `Sequence.Record` (C75). `UnfoldChangedSince` names an `EdgeId`, and `SheetRefused` a `FilePath`, which the CLI also gives an unreadable checkpoint's path through; `CreasingRefused` and `MoveNotRunYet` were added. The writer's non-finite refusal is `WriteNonFinite`, for a material coordinate, where D4 planned `WriteNonFiniteAngle`; `encodeFoldFile` refuses any non-finite number as `NotFinite` (#510). Expected refusals are the run's own `runExpected`, each with its step, move and kind, not part of each step's outcome as D23 has it, and each `StepOutcome` holds its placement as well as its presentation. `Sequence.Resolve` sits at D23's level 5 beside `Sequence.Run`, and `Sequence.SheetLengths` below `Sequence.Record`. The runner and resolver have three tolerances of their own, and the run report one, which D2's residue now names; the issue they were to wait for (§10 item 17) was filed only after M2, as #546 on 2026-10-12 | §5; D2; D3; D4; D11; D13; D20; D23; 01 §4.3; 02; 03; 04; [review L4](research/spine-reviews/review-L4-conventions-consistency.md) L4-4 | `Sequence.Run`, `Sequence.Record`, `Sequence.Error`, `Sequence.Resolve`, `Fold.Load` [code]; #501's body, read with `gh issue view 501` [ran] | adopted-modified | 00, 01, 02, 03, 04, glossary-additions |
| C97 | Glossary rows move into `docs/glossary.md` one term at a time, with the code that uses each, not all in M0's first PR (§3 row 10): #278's PR, #299, left "the rest of the language's vocabulary" in glossary-additions "until the code that needs each word exists". So a term that has moved is defined in both files, and once it has, `docs/glossary.md` is its definition; the copies can disagree, as Refold's "about seven" here did with C89. Many built terms have not moved, among them route evidence, seed and join check | §3 row 10; 01 §4.10; §8's M0 row; README | `git show f3b1ea5` [ran] | adopted-modified | 01, 10, README, glossary-additions |
| C98 | M2's sequence specs build their fixtures with `runIO`, not the `beforeAll` D16 asks of new sequence specs: the blintz, helmet, record, report, resolve, run and write specs, while M1's `TraditionalCraneSpec` uses `beforeAll`. C71 kept `runIO` only for existing specs until their deletion PRs, so these depart from D16. A filtered run (`stack test --ta '--match …'`) builds their fixtures as well, each adding at most 0.01 s of user CPU; the setup R5 describes is spent in three older specs ([C99](#changes-since-draft-v2)). §10 item 20 was filed only after M2, as #547 on 2026-10-12. Moving M2's seven to `beforeAll` would save no measurable time, so #547 leaves them out, and it is not mechanical: `BlintzRunSpec` and `HelmetRunSpec` make one example per move of the run, so their trees need the run while they are built. Whether to move them for D16's sake is open, and no issue holds it | D16; C71; 09 §3, §6.3; 10 R5 | `grep -c runIO` and `beforeAll` over `test/Senbazuru/Sequence` [ran] | adopted-modified | 09, 10, glossary-additions |
| C99 | Nearly all of the fixture setup that §10 item 20 and [10's R5](10-roadmap-risks-questions.md#5-risks) describe is spent in three study specs, not in M2's specs (#547). On `a71ac04`, the compiled test binary, run directly rather than through `stack test`, with a `--match` that selects no example, takes 14.2–16.5 s of user CPU (14.7–18.1 s of wall time), and 0.02 s of user CPU (0.05–0.06 s of wall time) with every `runIO` spec stubbed out. With one `runIO` spec at a time left in, `CheckedBirdSpec` takes 7.0 s of user CPU, `CraneWingSpec` 6.1–6.2 s and `CheckedPetalSpec` 1.5 s; each of the other seventeen, M2's seven among them, takes 0.02–0.04 s. With only those three stubbed out, the run takes 0.07 s of user CPU (0.10–0.13 s of wall time). [gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md)'s "Unverified" 7, which 09 §6.3 cites, holds on hspec 2.11.12: `beforeAll` runs its action only when an example under it runs, and not when only an example elsewhere does, while `runIO` runs its action whatever `--match` selects. C71 leaves existing `runIO` specs unchanged until their recipes' deletion PRs. 09 §9 shrinks `CheckedBird` and `CheckedPetal` to certificate-registry entries at M5, and it and D15 keep `CraneWing`. So, under C71, item 20 cannot be met before M5, nor ever for `CraneWingSpec`. Whether these three may move to `beforeAll` sooner, as an exception to C71, is the owner's question, open on #547 | #547; 09 §6.2, §6.3, §9; 10 R5, §7.2 item 20; C71; C98 | direct runs of the compiled test binary with a `--match` that selects no example, three per configuration and five with only the three stubbed out [measured]; a probe of `beforeAll` with three selections [ran]; appendix command 13 | adopted | 09, 10 |
| C100 | The external-tools rule is scoped (#552), as the owner decided on 2026-10-12 after #551's review found it read wider than the project's practice. An external program is someone else's code whose answer we rely on: a solver, simulator, renderer or validator, or a library that computes what we cite as evidence or keep. The tools that build, run, format, lint or manage our own code are not, and #553's review added the packages `senbazuru.cabal` lists, which the definition otherwise caught, so that CI no longer contradicts the rule. A user-installed GPL or GPL-linked build may be run as an oracle, as [H7](research/H7-tooling.md) finding 17 concluded, but nothing GPL enters the tree or the library, so no script here may use Blender's Python API, and D17's Codim-IPC condition "with `WITH_GPL=OFF` or Eigen" is dropped. Only output kept as a fixture needs provenance in `examples/README.md`, the research's own wording ([gap-study-consumption-contract](research/gap-study-consumption-contract.md) "(e) Licence position for PRD 3"), so #551's entry for the research contact sheets is withdrawn: they are research images, not fixtures. "Never ahead of the in-repo path" becomes "never used in place of our own code", as [PRD 11](11-prd-refined-final-forms.md) reads it: a prototype never becomes the product. `docs/related-projects.md` gains rows, each with its licence as built, for thirteen programs and libraries the repository relies on: rsvg-convert, three.js, ImageMagick, Apple's ImageIO, SciPy, scikit-sparse, Eigen, `ad`, `hmatrix`, NumPy, Shapely, matplotlib and Pillow; Mitsuba 3 and CalculiX gain the builds that ran | #552; the code reviews of #551 and #553 | the reviews' findings; licences as built from `brew info` and `otool -L` on the installed Homebrew builds and on Blender's bundled NumPy, `otool -L` on the research's wheels still in pip's cache and the licence files inside them, PyPI metadata, `npm view`, Hackage and Stackage metadata with the installed Stack package database, conda-forge's package files and feedstock, and the scripts that built each wheel, at its release tag or, for NumPy 2.x and SciPy 1.18.1, in numpy-release and scipy-release, which have no tags, at the commits matching the release dates [ran]; scikit-sparse's version from the first release with the `cho_factor` the scripts call [reasoned]; the contact sheets' encoder from their JPEG segment order, which `sips` reproduces and ImageMagick does not [ran] | adopted (owner decisions) | 01, 07, 11 |
| C101 | Owner decision 12 is decided (2026-10-12, #556), with four answers the code review of #557 asked for the same day. Crane-sized sequence tests run in a separate slow job that is a required check, so [§3](#3-recorded-text-this-design-changes) row 15 counts four checks once the owner lists the job in `main`'s branch protection. The PR adding it also moves into it, whole, the study spec files that hold a test of 10 s or more in one full run at its base, never single tests, since tests share fixtures: an exception to [C71](#changes-since-draft-v2) like #547's. On `c17d317` those were 20 files, nine of them not crane fixtures, with 1,745 s of the run's 1,810 s of item time (each test's own time while four ran at once, summed; hspec timed the run at 417.3 s), leaving about 65 s in the default job. Default CI settles at most 392 triangles, and never a crane fixture, which runs in the slow job whatever its size: 392 is the owner's line between the two jobs, not a measured budget, since it was timed once at y = 1/4, as 1,192 was. `run --settle`'s budget of 1,192 triangles is withdrawn; the PR that builds `run --settle` sets its budget from 3–5 compiled runs on the crane fixtures it must settle, still counted in triangles before solving, and any later change is made the same way. Corrections to what the owner was first told: the question said 1,192's mesh no longer exists, and nothing builds it now, since `CraneSpreadSpec` builds the y = 1/4 fixture only at 392 triangles (the correction #556 first gave wrongly said otherwise); but the record's own crane settle, [§7](#7-examples)'s sequence and [D14](#d14-material-consumption)'s first M6 test, is still that fixture, where a crane-wing settle has 392 triangles, so "1,188 triangles and up" holds only at the root, and whether decision 34 reaches the sequence is owner decision 42. Crane-spreading, crane-body, crane-internal and the quick tier hinge at the root; crane-root keeps seven of its nine controls at y = 1/4 for comparison. At the root the spreading wing has 1,188 triangles (one solve 9.75 CPU s, one run), and the flat-preference control 2,196: one solve with the body held and its base at an angle already found took 7.53–7.58 CPU s (three runs), with the body released 1,046 (one run), and the quick tier's nine solves 183–200 (three runs) | owner decision 12 and the review's four answers (#556); #557's code review | one local run on `c17d317`, [appendix](#appendix-commands-behind-the-numbers) command 14 [measured]; CI run 38321475359 on `a303ce8`, its log read with `gh run view` [ran]: hspec's own time 515.3 s (the step 536.9 s), its 20 slowest items all study specs; `CraneSpreadSpec.hs:32`, `:143`, `craneSpread`'s default `studyHinge` and `CraneRootGallery.hs:65-73` [code]; [spreading-connected-wing.md](../docs/notes/spreading-connected-wing.md) [research]; #474's table, read with `gh issue view 474` [ran] | adopted (owner decision) | 01, 05, 07, 08, 09, 10, 11, README, glossary-additions |
| C102 | Owner decision 42 is decided (2026-10-13, #559): owner decision 34's hinge, the wing's root, reaches the crane-wing sequence. The owner chose the question's Alternative 2, "Move the hinge to the wing root", where the question recommended Alternative 3, both lines, and said the record's "before M6" was too late for the root, since M4 makes the prefix a sequence. [§10](#10-corrections) items 42 and 43 list what moves, the fold before M4 and the settle before M6, and #560 re-derives it. Measured since, four of the option's statements change. (1) "The sequence language cannot identify a wing root now. You must add this function to the language, or find two points that give the line y = 0.37585." The language needs no new function. No vertex of the pattern folds to the root's ends, (0.87585, 0.37585) and (1.12415, 0.37585) ([flap-roots.md](../docs/notes/flap-roots.md)), but the sheet's corner north-east, the tail's tip, folds onto the root's line, 0.23 to the left of its end, and corner north-west and the midpoint of edge north fold to (1, 0) and (1, 1/2). So `perpendicular to [corner north-west, midpoint of edge north] through corner north-east`, O4 with a `moving` seed, names the root on the folded crane, a flat state on which §7's own fold already constructs its line; it parses and checks now, and resolves once the resolver gains O4's case. Folded exactly, the corner and the root's ends lie at y = 1 − (√2/4)(1 + 2 sin 22.5°) ≈ 0.3758485593. `wingRoot` gives 0.3758485581, 1.2e-9 lower, because `FlapRoot` merges paper across gaps of up to a hair, 1e-9; a fixture built there and a sequence through the corner differ by up to 1.8e-9, against the 1e-12 of AC-1 and of 09 §9's prefix equivalence. The other way is a reference that finds a flap's root by owner decision 35's rule. (2) "The crease must cut more faces": the root's line crosses 40 faces of the folded crane, not 16, and turns a flap of 8, not 4. (3) "With 8 strips, the mesh has 1,188 triangles": that is the crane-spreading gallery's mesh at refinement 3 (4,324 at refinement 4, whose convergence turned on rounding, #469, until #566's fix to the contact clip, [C117](#changes-since-draft-v2)), and the gallery's wing also has a join along its widest point, folded y = 0.324, that no move writes; the same fold without it has 80 faces, not 84, 952 layer orders, not 978, and 932 and 3,300 triangles with 329 pins, not 502. (4) "You must change the tests and the settle bands": at the root the hold band is the whole base, from the hinge to the widest point, 0.0514 long rather than an eighth's 0.0470, and since a band is measured in sheet lengths, the hold band's far end and the grip band's start become irrational, typed decimals or a second place to name; and crane-root's seven controls at y = 1/4 cannot be named against a record at the root. Which way a sequence names the root and its bands, and what its settle is compared with, #560 proposes and the owner sees before it is built | owner decision 42 (#559); #561's code review | in GHCi on `examples/crane.fold`'s key frame: the folded vertices near the root's height; `FlapRoot.findRoot` with its hair lowered to 1e-13, whose ends then lie within 5e-13 of the corner's height; the folded edges crossing at the root's ends, all within 1.2e-13 of it; today's parser, checker and elaborator on that O4 fold, and the resolver on its points; `buildCraneWingAt` and `craneSpreadWithAt` at `wingRoot` and at the corner's height, and copied with the widest-point join left out [ran]. The pattern's coordinates read as exact numbers a + b√2 + (c + d√2)√(2 + √2), each within 6.4e-14, and folded exactly in Python [ran]. `layer-selection-analyse.py line examples/crane.fold 0,h 2,h 0.02,0.97` at h = `wingRoot` and 0.25 [ran]. `CraneSpread.hs:142-147`, `CraneWing.hs:166` [code]; [spreading-connected-wing.md](../docs/notes/spreading-connected-wing.md) [research] | adopted (owner decision) | 02, 04, 07, 09, 10, glossary-additions |
| C103 | Owner decisions 43 to 46 are decided (2026-10-13, [#560's answers](https://github.com/avalonalex/senbazuru/issues/560#issuecomment-6153343399)), after #560's research put four questions; 44 to 46 as recommended. 43 was decided otherwise, for `root of P` before M4, and revised the same day, as recommended, to O4 at M4 with `root of P` after, once #565's review had corrected its premises and found the costs below ([#560](https://github.com/avalonalex/senbazuru/issues/560#issuecomment-6154363309)). Measured on `aed4755` ([appendix](#appendix-commands-behind-the-numbers) command 15): (43) O4 is specified ([02 §4.3](02-language-semantics.md#43-lines)) and parsed since M1, but its resolver case is unbuilt even on flat paper (`Resolve.hs:271`): §8's M2 row promised constructions on the flat sheet, but #494 left O4 to O7 refused "until an example needs them", and no row records that or schedules them since. `FlapRoot` is 301 lines importing nothing from the study, with `Text` errors and its own tolerances and probe steps (`FlapRoot.hs:86`, `:99`, `:145`, `:219-220`, `:224`), which the question counted as four. On crane.fold it finds the wing's root's ends 1.12e-9 and 1.36e-9 low, an error that falls with the [hair](../docs/glossary.md#origami), 1e-9, across which it merges paper ([C102](#changes-since-draft-v2)); crossing the folded edges near each end puts them within 1.2e-13 of corner north-east's height. It finds no root for the tail, and for the neck a root with one end on the head, which only the turn check refuses (`FlapRootSpec.hs:39-45`). On the four corners of eleven of the thirteen `*-base.fold` files in `examples/`, all but blintz-base and book-base, it finds no root: no flap's edge meets other paper in the model's outline, the only place it looks. Correction to what the owner was told: the question said the rule "finds roots only on the crane", but the same run had found, on `kabuto.fold`, the samurai helmet, a finished model rather than a base, roots at three of its four corners that the flap turns about in the first of its nine layer orders, not yet checked against a book. A comparison fixture built at `wingRoot` misses the O4 line through corner north-east by up to 1.76e-9 (C102's 1.8e-9), against AC-1's 1e-12; one built at the ends found by crossing folded edges, by 2.1e-14. (44) Crane-spreading's curved control (refinement 3, the grip turned a further 20°) starts, without the join, with 452 layer orders reversed and 0.042 rad of crease error just above the widest line, against none with it; its solve then ends unconverged, at a strain of 4.4e-4 against the 1e-5 gate with the gallery's 20 iterations per penalty stage, and 4.1e-4 with 40. Corrections to what the owner was told: with the join that control is unconverged on `aed4755` too, at 39 iterations and a strain of 1.2e-7, and converges only with 40 iterations per stage, in 55 iterations and 207 CPU s ([#566](https://github.com/avalonalex/senbazuru/issues/566)), so the join fixes the start, not convergence; and not every root settle without the join stops converging, since the rigid control, settled at its start, is accepted. `closed across-hinge moving` takes exactly the study's root strip only with the widest line in the record, as `J` or `F` (441 vertices at refinement 3); with none there it takes the whole moving side, 425 vertices against the strip's 266. No split was built, so how its pieces and edges behave is unmeasured. The same line assigned `F` gives the study's mesh and pins exactly; assigned `U`, as a pre-crease leaves it in the working pattern, and settled as a crease spring at rest 0 (owner decision 4's default; the study's own rule rests it at π), the paper turns 3.0° there. Creasing the hinge and then the line gives the study's ids; the line first gives other ids. Pattern vertices 5, 11, 37 and 46 fold onto the widest line, none of them a named landmark; a typed point snaps to one at 9 decimal places, and at 8 is a near miss [reasoned]. (45) The decimal ends `0..0.0514` and `0..0.0514252` drop the whole widest line, 33 vertices at refinement 3 with the join, since each stops short of it, the hold's true end, by more than the band's tolerance of 1.41e-9 (by 2.5e-5 and 1.1e-8). `0..13/250`, `0..103/2000`, `8/25..` and `13/40..` select exactly `spreadPins`'s vertices at `wingRoot` and at corner north-east's height, with and without the join, at refinements 3 and 4, the study's only two; where `rigid-pose 1/3` puts the held ones, against `bentPoint`, is unmeasured (07's "Root-strip target"). An arc started at the farthest held vertex, measured from the hinge line, is off by at most 1.24e-16 at refinement 3; measured from the hinge's segments it would start at 0.0524 [reasoned]; one started from a typed end needs 11 places. A released control holds nothing on the moving side (`CraneRoot.hs:89-90`), so its `arc-grip` has no hold to start from; the question said only "one new refusal". (46) Crane-root's flat-preference control at the root, crane-body, crane-internal and the quick tier hold the rigid base of their released controls at an angle a search finds; at y = 1/4 the hinge lies below the widest point, so there is no rigid base, and seven of crane-root's nine controls use `studyHinge` | #560 and its research; #565's code review | GHCi at `aed4755` on `examples/crane.fold`'s key frame, and on the corners of the kabuto and eleven bases, [appendix](#appendix-commands-behind-the-numbers) command 15 [ran]. `FlapRoot.hs:24-50`, `:65`, `:209` (its imports and `Text` errors), `:86`, `:99`, `:145`, `:219`, `:220`, `:224` (its tolerances and probe steps); `FlapRootSpec.hs:39-45`; `Resolve.hs:271`; `CraneWing.hs:156-166`; `CraneRoot.hs:89-90`; `CraneRootGallery.hs:65-71`, `:81-93`; `CraneBodyGallery.hs:53-61`; `CraneInternalGallery.hs:93-97`; `CraneQuick.hs:68-73`; `CraneRootSpec.hs:50-51` [code]. §8's M2 row, whose constructions #494 closed with O4 still refused, and its M4 row [prd]; [#566](https://github.com/avalonalex/senbazuru/issues/566); [flap-roots.md](../docs/notes/flap-roots.md) [research] | adopted (owner decisions) | 02, 04, 05, 07, 09, 10, glossary-additions |
| C104 | O4, `perpendicular to L through P`, resolves (#567; [§10](#10-corrections) item 44's first part, for owner decision 43). `Resolve.foldLine` draws the line through where P now is, at right angles to L where L now lies. Only L's direction counts, so P may lie on L, and L is any line `foldLine` resolves, worked out first. A `nearest` that L needs goes inside L's parentheses and chooses L, not the fold, and L's own refusals are reported under the whole line ([#570](https://github.com/avalonalex/senbazuru/issues/570)). `hinge of NAME` cannot be L. A run finds a hinge from its earlier records before it calls `foldLine`, which therefore meets one only inside another line. It now says so, where its message had named `hinge of NAME` alone, a form that runs ([#570](https://github.com/avalonalex/senbazuru/issues/570)). The runner needed no change: it takes a `moving` seed for any line, which [02 §4.3](02-language-semantics.md#43-lines) asks of O4, and refuses a missing one as `SeedMissing`. Like every line's, that refusal lacks the two sides and their seeds that [02 §12](02-language-semantics.md#12-refusal-catalogue) asks for ([#571](https://github.com/avalonalex/senbazuru/issues/571)); [C112](#changes-since-draft-v2) gives them. On `examples/crane.fold` folded by its own angles, owner decision 43's line passes within 5.4e-14 of the root's ends, at y = 1 − (√2/4)(1 + 2 sin 22.5°) ([C102](#changes-since-draft-v2)). No run folds along it there yet: the crane fold starts folded and creases folded paper, and both are M4's ([10 §1](10-roadmap-risks-questions.md#1-milestones)). Both #570 gaps are closed by [C111](#changes-since-draft-v2) | §10 item 44; owner decision 43 | [code] `Resolve.foldLine`'s `PerpendicularThrough` and `HingeOf` cases; `Run.hs:640`, the missing seed's refusal. `ResolveSpec`'s "draws a line through a point at right angles to a line" and `RunSpec`'s O4 fold, each turned red by a mutation of the case: L's direction kept rather than turned; P, or L, taken where it lay on the sheet; L's refusals dropped; the hinge's old message; and O4 seeded from P [ran]. The 5.4e-14 comes from `stack ghci senbazuru:lib`: `foldLine 1e-3` on `flatState` of `foldFrameWith` of the crane's key frame, then `abs (cross2 d (V2 x y ^-^ p))` at x = 0.87585 and 1.12415 [ran] | adopted | — |
| C105 | The study's crane wing can be built without the join along its widest point (#572; [§10](#10-corrections) item 44's builder, for owner decision 44). `buildCraneWingWith WithoutWidestJoin` creases only the hinge; `buildCraneWingAt` keeps the join, so no gallery, test or golden changes. At the wing's root the build without the join has 80 faces and 952 layer orders, as [C102](#changes-since-draft-v2) measured, against the joined build's 84 and 978, and it turns 8 faces where the joined build turns 12. Leaving the join out leaves whole the four faces it would cut in two, and changes nothing else: the joined build's vertices begin with the other's, in the same places, and the 76 faces both builds share keep all 910 layer orders between them. Below the widest point the two builds are one frame. A wing records whether its join was drawn, and `CraneSpread` refuses to spread one creased above its widest point without it, whose start has 452 layer orders reversed ([C103](#changes-since-draft-v2)). M4's comparison builds at the root the study's root finder finds exactly, as the owner chose ([#560's answers](https://github.com/avalonalex/senbazuru/issues/560#issuecomment-6157138819)) | §10 item 44; owner decision 44 | [code] `CraneWing.buildCraneWingWith`, `wingSegments` and `craneJoined`; `CraneSpread.craneSpreadFromWing`. `CraneWingSpec`'s "leaves out the join along the widest point, as a fold does", at `wingRoot`, turned red by a join drawn anyway, by one drawn below the widest point and by a different stacking chosen without it; `CraneSpreadSpec`'s root test by the refusal dropped [ran]. The same counts at corner north-east's folded height, then 1.24e-9 above `wingRoot`, in `stack ghci` [ran] | adopted | — |
| C106 | The study's root finder is exact (#574), as the owner chose on 2026-10-13 ([#560's answers](https://github.com/avalonalex/senbazuru/issues/560#issuecomment-6157138819)), for M4's comparison with the crane-wing sequence. `FlapRoot.findRoot` probes a flap's root to within a few hairs, since it merges runs of paper across gaps of a hair. It now moves each end it probes onto the average crossing of the folded edges passing within ten hairs of it, among pairs whose angle has a sine above 1e-6, kept within the probe's own jump of 1e-6 of the model. The crane wing's ends land within 1.3e-13 of (1/2 + y\*, y\*) and (3/2 − y\*, y\*), where its edges meet the neck's line x − y = 1/2 and the tail's line x + y = 3/2 at y\* = 1 − (√2/4)(1 + 2 sin 22.5°), the folded height of the sheet's corner (1, 1). `wingRoot` lands 4.9e-14 above y\*, where it was 1.24e-9 below ([C102](#changes-since-draft-v2)), and refuses a root not exact at both ends. Where no two edges cross, the probed end stands and `Root` says so: on the crane tail's second end, and on one end of two of the kabuto's three roots, the run jumped because other paper ended. Which flaps the rule accepts does not change, but the tail's turn is now refused from its start. Two tolerances are new, the ten hairs and the sine, and `FlapRoot`'s move into the library under [05](05-prd-library-additions.md)'s R-05-3 must settle them with the rest (owner decision 43). The library stage could instead cross the two edges the probe's own jump finds, and refuse an end where the run gets shorter, which would refuse two of the kabuto's roots ([#560](https://github.com/avalonalex/senbazuru/issues/560)) | owner's answer on #560; [§10](#10-corrections) item 44 | [code] `FlapRoot.findRoot`, `exactEnd`; `CraneWing.wingRoot`. `FlapRootSpec`: the ends within 1e-12 of the closed form, both exact; the tail's second end probed; `wingRoot` within 1e-12 of y\*. Both tightened tests turned red with the refinement dropped [ran]. The 1.3e-13, 4.9e-14 and the 16 edges and 64 crossings at each end, in `stack ghci` [ran]. The kabuto's roots, run by #575's review [ran] | adopted | — |
| C107 | Owner decisions 47 and 48 are decided (2026-10-13, [#560's answers](https://github.com/avalonalex/senbazuru/issues/560#issuecomment-6157138819); the questions [as asked](https://github.com/avalonalex/senbazuru/issues/560#issuecomment-6159771153)), as recommended: M4 compares the crane-wing sequence with the study's wing built without its join at the root the study finds exactly (#575, [C106](#changes-since-draft-v2)), and adds a golden of the wing lowered at its root. And [§10](#10-corrections) item 42 is fixed: every passage it lists is at the wing's root, but for 07's copy, which keeps the `material` line and `settle` block with the fold at y = 1/4 they were written for. A band's ends are measured from the step's own hinge, so the same settle under the root's fold would select other vertices than the study pins, and decision 45's bands at the root wait on `split` (decision 44); so §7 and 04 carry the M4 source alone, which parses and checks today. The step names its line once, `let wing-root = …`: written out, with the `moving` seed O4 needs, the fold and its `expect refused` would run to 129 and 182 characters; a `let` is the only way to name a line, since a header holds no `let` and a `mark` names a point; and `wing-root` stays a name once `root of P` reserves `root`. 05's L11 gains a row at the root after its y = 1/4 rows, which stay. **Corrected:** C102 and owner decision 43 called corner north-east the tail's tip, and C103 named the tail's flap the neck's and the neck's the tail's. Corner north-east is the tip of the crane's head: ten crease vertices lie within 0.35 of it on the flat sheet, against one at corner (0, 0), whose folded tip lies on x + y = 3/2 and which `CranePocket` and `CraneWingSpec`'s tucked tail name the tail; `docs/notes/flap-roots.md` had the two the other way round until #575. Measured: corner north-east is vertex 57, folded to (0.646447, 0.375849); the line crosses 40 faces, and one 1e-8 lower crosses 48, the tail's eight with them, though neither flap changes; the flaps are faces 2, 3, 6, 7, 32, 34, 35, 38 and 0, 1, 4, 5, 33, 36, 37, 39; the sense as appendix command 16 has it; and the study's level hinge at `wingRoot` lies within 1.4e-14 of the sequence's O4 line between the root's ends | #560; owner decisions 42 to 44, 47 and 48 | `parseSequence` and `checkSequence` on §7's source [ran]; 02's check P at y\* with both seeds [ran]; `layer-selection-analyse.py line` 1e-9 to 1e-4 below y\* [ran]; appendix command 16 [ran]; crease vertices near each corner of `crane.fold`, in Python [ran] | adopted (owner decisions) | 02, 04, 05, 07, 09, 10 |
| C108 | A fold that re-anchors carries its fold line onto the fold held from the new face, instead of naming it again there (#569, found by #568's review). [C83](#changes-since-draft-v2)'s second naming ran after the move's own crease, where it made one, so a typed point was measured for a near miss against the vertices that crease added, which the author never saw. On the plain square, `perpendicular to edge south through (1/2, 1/2000)` and `[(1/2, 1/2000), (1/2, 1)]`, each `moving corner south-east`, were refused at `anchor (3/4, 1/4)` and ran at `anchor (1/4, 1/4)`, and `(2498/5000, 1/5000) to (2502/5000, 1/5000)` the other way round. [02 §4.3](02-language-semantics.md#43-lines) has even the moving side decided by the move's text, never by the anchor; here whether the fold ran at all depended on it. The line is now named once, on the paper as it was before the move. It is then moved by the inverse of h, the new anchor face's placement in the fold (C83), since re-rooting the fold moves every face by that inverse (`Resolve.carryLine`). The flap is still taken afresh. Without a new crease the second naming saw the same vertices, moved rigidly, so it found the same line, and a move creases only the flat sheet, where h is the identity. Measured with a temporary trace in `foldMove`, not kept, over the whole suite as it stood (2247 examples): a fold re-anchored 12 times, 7 of them onto turned paper. The carried line and the second naming agreed within 3.2e-16 in point and 1.6e-16 in direction, and every h was the identity or a half turn, which is its own inverse. So a pleat was added: a strip folded over and then back, which leaves the outer panel two flips from its neighbour, about parallel creases, and so moved half a sheet along. Its h is that move | #569 | `Sequence.Run.foldMove`, `reanchorAt`, `Resolve.carryLine` [code]. `RunSpec`: the three folds run at three anchors, one of them on the new crease, with the same crease, hinge and angles at each, and a point 1/2000 from a corner the paper had is a near miss at each; the pleat's last record has its line at x = 7/8 as folded from its new face, at either anchor. Red with the second naming put back, in the main branch or in the one off the new crease; with the line carried by h, not carried, or carried but not recorded; and with no near-miss band [ran] | adopted | — |
| C109 | Owner decisions 49 and 50 are decided (2026-10-19, [#580's answers](https://github.com/avalonalex/senbazuru/issues/580#issuecomment-6278612261)), as recommended, and built (#580). `refusalKindOf` gives no kind to 23 library refusals, 9 of folding and 14 of a flap, nor to `RefusalNotRaised` and `RefusedDifferently`, so a run passes each on as itself; the 13 library refusals that are refusals of the paper keep their kinds, each named, with no catch-all. The checker refuses an `expect refused` holding another, directly or inside a `together`, as `NestedExpectRefused`, before it looks at the outer kind; nesting through a `together` is included because it is nesting just as much, and once `together` runs it could never pass either. 02 §9 now says a flap refusal wrapping a folding refusal takes its kind, §12 says a library refusal not in its table has no kind, 04's `KIND` row says the checker accepts `refusalKinds`, and D21 says what its nesting meant. The research behind 49 found four gaps, filed as issues: angles over 360° pass the checker (#583), a 0° fold reaches the sweep (#584), a fold line a hair from a vertex cuts a sliver face (#585), and a sheet's start accepts faces every turn refuses (#586) | #580 | `Sequence.Error.refusalKindOf`, `NestedExpectRefused`; `Sequence.Check` [code]. `ErrorSpec`: one refusal of every constructor `refusalKindOf` looks at, each given its own constructor's name as its kind or, for the 25 and the four that had none, no kind, and every kind given in `refusalKinds`. `CheckSpec`: an `expect refused` inside another, directly or inside a `together`, is refused with the inner kind. The 400°, 0°, sliver and nested runs on 3121083 [ran] | adopted (owner decisions) | 02, 04 |
| C110 | One rule for a point inside a face (#579; owner decision 51, decided 2026-10-20, [the question and answer](https://github.com/avalonalex/senbazuru/issues/579#issuecomment-6295603098)). Four places chose a point in a face, each its own way. A fold that turns the anchor's paper re-anchored onto the face beside its hinge at the face's vertex mean, and refused the move as not run yet when that mean was not strictly inside the face. So on #579's sheet, two by one in the file's units with its top-left corner creased off, a fold 3/10 of a sheet length from the west edge, x = 0.6 in the file, was refused by the turn's mesh (`FlapSurface`) with the anchor west of the line, and by re-anchoring with it east, where the new face's six corners average to its own inside corner. The move off a new crease (C19) did the same. The start refused a default anchor outside its face and asked for `anchor P` (G13), and did so before reading a header `anchor P`, which D3 says overrides the default. An `L1 to L2` fold's seed was the vertex mean of the face beside L1, refused as `NotInOneFace` when that lay on a crease. Now `Geometry.Polygon.pointInside` gives all four a point clear of the face's outline by the sheet's tolerance: the vertex mean, or else the mean of the face's largest *ear*, a corner whose two neighbours are joined through the inside of the face, chosen by the start's tie rule, largest, then lowest, then leftmost, which `largestLowestLeftmost` now holds for both. A face with no such point is passed over before ranking, and a sheet with none is refused as `NoRoomForAnchor`, which replaces G13's `DefaultAnchorOutside`; a sheet 1.5e-9 high reaches it. A face that is not convex still reaches the turn, which refuses it whatever point was taken, so today the ear chosen shows only at the start, as the anchor, and in which refusal a fold gets. Whether such a face should be refused at the start, before any move, is #586 | #579; owner decision 51 | `Geometry.Polygon.ears`, `pointInside`, `largestLowestLeftmost`; `Sequence.Run.anchorIn`, `sheetState`, `reanchor`; `Sequence.Resolve.firstLineSeed` [code]. `PolygonSpec`: #579's L has ears 0, 2, 3 and 5, wound either way and moved 1e8 from the origin, where its area measured from the origin rounds to 0; a dart's corner whose triangle holds another, a corner on a straight run, and one 1e-7 high and 2e-5 in area on a square 400 across are no ears; an hourglass that touches itself keeps four; `pointInside` gives a square's centre, the L's (1/5, 1/6), and (1/3, 1/3) on a square with a spike whose ear's mean is too near the outline, either way round. QuickCheck: star-shaped rings have two ears either way round, and every L gets a point, the same wound either way, 73% of them from an ear. `RunSpec`: a thin L's default anchor is (2/3, 1/30), and it turns over from a header anchor (1/20, 1/2); the 1.5e-9 sheet is refused; #579's fold at anchors (1/20, 1/20) and (3/4, 1/4), and folding either edge of a square creased (0, 0.1)-(0.9, 0.1)-(0.9, 1) to a line, are refused by the turn the same way. `ResolveSpec`: that square's `edge east` seed is (1/3, 1/30), not its L's vertex mean (19/30, 11/30). Before: #579's east anchor was refused as not run yet on ca8ffc0, the thin L as `DefaultAnchorOutside` there with or without its header anchor, and the east edge's fold as `NotInOneFace` at (0.9, 11/30) on 2516ae5, whose resolver is ca8ffc0's [ran]. Red with the winding measured from the origin, or taken as anticlockwise; with a second pass at a corner counted against its triangles, by the old rule, or let off only at exactly the same point; with no check for a corner inside a triangle; with the tolerance held against the area in place of the height; with the vertex mean never taken; with ears ranked before their means are checked; with ties going to the highest or the rightmost; with the start or the seed taking the vertex mean; and with a sheet with no room refused as having no faces [ran] | adopted (owner decision) | 02, 01, glossary-additions |
| C111 | A line inside another is resolved and refused as itself (#570, from #568's review; the two gaps [C104](#changes-since-draft-v2) left). **Its refusal.** A refusal of O4's L was reported under the whole line: on `sheet square`, `perpendicular to ([(0, 1/2), (1, 1/2)] to [(1/2, 0), (1/2, 1)]) through (1/4, 1/4)` said only that "the construction has 2 answers", listing L's answers, not the fold's, though O4 has one answer and a `nearest` after it does not parse. `Resolve.foldLine` now works out O4's L and each line of `L1 to L2` through one helper, `within`, which wraps the refusal as `InsideLine`: it quotes the line, with any `let` name written out, and for a line that needs a `nearest` says it goes right after that line, where it is written, not after the whole line. `InsideLine` has no kind of its own: `refusalKindOf` looks through it, as it already looked through `FlapFolding`, so `expect refused NeedsNearest` still matches. **`hinge of NAME` as L.** A run found a hinge from its earlier records before calling `foldLine`, which therefore met one only inside another line and refused it as not run yet. `foldLine` now takes the run's lookup, `Name -> Either ResolveProblem [EdgeId]`, which finds the crease's pieces on the paper now, and lays them on the state it is given (`hingeLine`), so a hinge standing alone and one inside a line take one path. The code review found two older faults on that path, and both are fixed. The lookup counted every record the step made, so a step that folded and turned the paper over had "made 2" though the checker counts one turn; it now counts the records that turned paper. And a hinge a later fold had bent was taken from its first piece, so the nested fold ran along x = 1/4 or y = 1/4 by which way the crease had been written; a hinge whose pieces no longer lie on one line is now refused as not run yet ([#591](https://github.com/avalonalex/senbazuru/issues/591) asks how it should be; owner decision 52 makes it `HingeNotStraight`, [C113](#changes-since-draft-v2)). A point holding a line, `meet`, is worked out by `materialPoint`, which has neither the helper nor the lookup, and will need both when `meet` is built. Refusals still quote the elaborated text rather than a `let` name, and the `L1 to L2` seed path reports under L1 ([#590](https://github.com/avalonalex/senbazuru/issues/590)) | #570; C104 | `Resolve.foldLine`'s `within` and `HingeOf` case, `hingeLine`; `Error.InsideLine` and `refusalKindOf`; `Run.foldMove`'s `hingeNamed` [code]. On `sheet square` folded in half across its middle and unfolded, `perpendicular to hinge of half through (1/2, 1/2)` writes the same FOLD file, byte for byte, as `[(1/2, 0), (1/2, 1)]`; on b725dfe it was refused as not run yet [ran]. `RunSpec`: the nested refusal quotes L, says where the `nearest` goes and has the kind `NeedsNearest`; the hinge fold, from a step that also turns the paper over, makes the same new creases, hinges and angles as the two-point line; a turn-over's hinge is refused as of no turn; a bent hinge is refused, written either way, alone or inside a line. `ResolveSpec`: L's refusal and an `L1 to L2` operand's are wrapped, P's and `L1 to L2`'s own are not; a hinge is laid along the crease the lookup gives. `ErrorSpec`: every reference's refusal, wrapped once and twice, keeps its own kind, and only `NeedsNearest` gets the `nearest` hint. Red with an inner line's refusal, or an operand's, not wrapped; with the wrapper given no kind, or looked through only once; with the hint dropped, or given to every inner refusal; with the line unquoted; with a hinge inside another line refused as before; with every record counted; and with a bent hinge taken from its first piece [ran] | adopted | 02 |
| C112 | `NoSolution` and `SeedMissing` carry the facts [02 §12](02-language-semantics.md#12-refusal-catalogue) lists (#571, from #568's review). **`NoSolution`** had no fields, and blamed the creases even for a line that only touches the paper: on `sheet square`, `perpendicular to [corner south-west, corner north-east] through corner north-east`, which meets the square at (1, 1) alone, `perpendicular to edge south through corner south-east`, `[corner south-east, corner north-east]` and `edge east` were each refused as "the fold line runs along no crease on the paper". It now says why, as `Unsolved`: a line along which no crease runs, with the line as the author reads it, saying whether it crosses paper; or a construction none of whose answers crosses paper (§4.3 rule 2), with every answer. So `edge east` reads "the fold line is the line through (1.000000, 0.500000) along (0.000000, 1.000000), which crosses no paper, and no crease runs along it". A line is shown without the rounding folding leaves, a part within 1e-12 of 0 being 0, and `num` writes a zero without a sign. As before, a form with one answer is refused only when no crease runs along it, never for crossing no paper alone, which #571 asked to keep; 02 §4.3's rule 2 now says so. **`SeedMissing`** had no fields. It now holds a seed for each flap the fold can move, in sheet lengths. A face offers the point the anchor would take in it ([owner decision 51](#9-owner-decisions)); faces are grouped by the flap `flapOf` chooses from that point, since on folded paper one side of the line can hold two flaps, each a different fold; and for each flap the runner offers the first seed, largest face first, from which this very move runs, rounded to six places as the message prints it, in the language's own numbers (`Explain.decimal`), which have no exponent. Owner decision 53 writes each seed as an author would instead, a corner, `centre` or exact fractions where it can, and asks which flap it chooses before running it, so a flap's next seed is no longer tried ([C114](#changes-since-draft-v2)). So for `[(0, 1/8), (1, 1/8)]` on the square the message offers (0.5, 0.0625) or (0.5, 0.5625), and each, copied into the source, folds. A side whose flap no seed folds offers none, and a line no seed folds says "no moving P makes it fold". 02 §12's "both sides, each with a working seed" and D2 are amended: on paper of one layer the flaps are the two sides. The runs that check the seeds happen only if the refusal is read, as `expect refused SeedMissing` never does | #571; C104 | `Error.NoSolution`, `Unsolved`, `SeedMissing` and their words; `Resolve.lineOnto`, `hingeAlong`, `lineAsSeen`, `seedsByFlap`; `Run.foldMove`'s seed choice; `Geometry.Polygon.pointsInside`, `inPreferredOrder`; `Explain.num`, `decimal` [code]. The four lines and the seedless fold, run before and after [ran]. On #592's first commit the reviewers found offered seeds the move then refused, on the folded blintz and on striped paper, a flap left unoffered, and seeds printed as `6.250000e-2`, which does not parse; twelve of their cases, rerun with every offered seed copied in as printed, fold, and four that no seed folds say so [ran]. `RunSpec`: a seedless fold an eighth up the square offers (0.5, 0.0625) and (0.5, 0.5625), each parsed from the message and folding; the folded blintz offers only the corner's seed, from which the fold runs; along the blintz's edge 8, the corner triangle's seed and the centre; along an F crease, none, saying no seed helps; a line along the folded square's outline is shown as (0, 0.5) along (0, 1); and two lines 1.5e-9 apart are refused as having no answer on the paper. `ResolveSpec`: a line along the blintz's south side is refused with its one line, crossing no paper. A pre-creased square offers each flap's largest face's seed. `ExplainSpec`: `num` and `decimal` write zero without a sign, and `decimal` writes 1/16 as 0.0625. Red with the seeds offered without running the move, one flap only, printed by `num`, unsorted or unranked, with the rounding not snapped, with `L1 to L2`'s refusal or the one line's dropped, and with the old words for no seed [ran]. Untested: trying a flap's next seed when rounding puts the first on a crease, which no test sheet's faces are thin enough to reach | adopted | 02 |
| C113 | `hinge of NAME` on a crease that no longer lies on one line is refused as `HingeNotStraight`, a refusal of the paper with a kind (#591; owner decision 52, decided 2026-10-20, [the question and answer](https://github.com/avalonalex/senbazuru/issues/591#issuecomment-6302364672)). [C111](#changes-since-draft-v2) had refused it as not run yet, with no kind. It comes about wherever part of the paper the crease runs through has moved since the step made it: a later fold carrying part of it away, as in decision 52's example, or a crease made through several layers, which lay on one line only while they were stacked, once they are unfolded. So the words name no cause. On decision 52's example they read: "hinge of half" does not lie on one line now: as the paper lies, its pieces run (0, 0.5) to (0.25, 0.5), (0.25, 0.5) to (0.75, 0.5), (0.75, 0.25) to (0.75, 0.5); name the line another way. **Details the code review settled.** The pieces are measured against the longest piece's line, as `edgeNow` measures an edge's, not the first piece's, which a crease written the other way round puts first; a hinge on one line is that line, pointing east or north, so a fold along it, too, no longer depends on how the crease was written (a crease cut by a fold 2e-9 off vertical had been accepted one way and refused the other); each piece is named once, though stacked layers give it once a layer; and the pieces and their ends are in an order that does not depend on how the crease was written. They are where the paper lies, held by its anchor's face, in sheet lengths, which a typed point is not: a typed point is a point on the sheet, so the words ask for the line "another way" rather than "by two points". They are printed in an author's numbers (`Explain.decimal`), as `EdgeNotStraight`'s now are too, so neither prints an exponent or folding's rounding. The kind joins `EdgeNotStraight` and `CreaseNotStraight` in `refusalKinds`, so `expect refused HingeNotStraight` matches it, alone or inside another line. `unfold NAME` meets a crease bent through both layers differently, as the library's `FlapUnalignedCrease` ([#597](https://github.com/avalonalex/senbazuru/issues/597)) | owner decision 52; #591 | `Error.HingeNotStraight`, `refusalKinds`, `refusalKindOf`; `Resolve.hingeLine` [code]. `RunSpec`: a hinge a hair off one line folded to the same refusal, written either way; a fold at right angles to a hinge making the same records, written either way; decision 52's example refused with the kind `HingeNotStraight` and the three pieces above, alone and inside `perpendicular to`, with the half crease written either way, on the unit square and on a sheet two long; a crease made through two layers and unfolded refused naming both of its lines, and one bent with both layers stacked naming each stretch once. `ErrorSpec`: the constructor's kind is its name and on the list, and its words. The message on decision 52's example, by `stack run -- run` [ran]. Red with the first piece as reference, the line pointing the way the crease was written, pieces named once a layer, unsorted or with their ends unordered, not in sheet lengths, printed by `num`, and with the old cause in the words [ran] | adopted (owner decision) | 02 |
| C114 | A seedless fold's refusal offers each flap's seed as an author would write it (#593; owner decision 53, decided 2026-10-20, [the question and answer](https://github.com/avalonalex/senbazuru/issues/593#issuecomment-6304407386)). For each flap the line borders, `Resolve.seedForEachFlap` takes the first of: the sheet's corners and its centre, lowest and then leftmost (`corner south-west`, `corner south-east`, `centre`, `corner north-west`, `corner north-east`); else the flap's points, best first ([C112](#changes-since-draft-v2)), each coordinate an exact fraction where one with a denominator of 64 or less lies within the sheet's tolerance of it, else to six places. Each is kept only if `flapOf` chooses that very flap from it as written, since a name, or a point once rounded, can lie in another. The runner offers it if this very move runs from it. Every point a flap is chosen from turns the same faces about the same hinge, so a refusal once it is chosen is the flap's, and C112's retry of a flap's next seed is gone. The flaps are listed lowest and then leftmost by the seed offered, by the tie rule faces are chosen by (`inPreferredOrder`). The text is worked out from the point it names, so it parses back to the point tried. On the square, `[(0, 1/8), (1, 1/8)]` now offers corner south-west or centre, and the blintz folded behind along its south-east corner's crease corner south-west or corner south-east. An octagon, which has no corner of its box, offers (9/40, 7/12) or (31/40, 7/12) where its faces' points have such fractions, and (0.263333, 1/2) or (0.736667, 1/2) where only y has one. A flap too thin for six places at every point is offered nothing: on a sheet a third as tall as it is wide, a line 2e-7 below the top offers only centre, since the sliver's point, rounded, lies in the paper beneath and would fold that. `SeedMissing` carries the text as written, as a refusal that quotes a line does, since `Sequence.Error` may not import the printer. **Where the rule departs from the question's table.** Several names can name one flap, and the rule takes the lowest, then the leftmost. On the square folded in half, the centre lies on the line, and the upper half is offered as corner north-west, where the table had corner north-east. On the blintz, the body is offered as corner south-west, where the table had centre; owner decision 55 keeps it there, where nothing is folded, and offers centre where the corners are folded in ([C115](#changes-since-draft-v2)). Each folds the same file as the table's. **How the decision is read.** It says "an exact fraction, else the six-place decimal", and its examples have no point exact in one coordinate only. A fraction is chosen for each coordinate, as a decimal is, so the octagon's 1/2 stays 1/2. **Details the code review settled.** The first commit gave numbers no flap check, so a sliver's rounded point was offered and folded the paper beneath; listed the flaps by a point the message never showed, so the blintz read corner south-east before corner south-west; took a fraction within a billionth of a sheet length rather than the sheet's tolerance; tried a fraction and then a decimal of the same point; and asked which flap a name chooses in the runner and the resolver both | owner decision 53; #593 | `Resolve.seedForEachFlap`, `Run.foldMove`'s seed choice, `Error.SeedMissing` [code]. `RunSpec`: the blintz's edge 8, in that order; the square an eighth up and the octagons, each offered seed copied from the message into the source, parsed and folded; the folded blintz's corner alone; the sliver offered nothing [ran]. The code review's 52 seedless folds, on flat and folded paper, on squares, rectangles, a diamond, a trapezoid, a triangle and an L, through the anchor and after a turn-over, rerun on the fix: 39 offer a seed for each flap, 73 in all, each of which, written in, folds the same file, byte for byte, as the base's six-place seed for that flap; the other 13 offer none, or are refused before the seed is asked for, as on the base [ran]. Red with no names tried, no flap check, no flap check for numbers alone, no fractions, fractions up to 1000, fractions only for a whole point, the centre tried last, the flaps unordered, and a seed offered without running the move [ran] | adopted (owner decision) | 02 |
| C115 | A seedless fold's refusal offers, among the names that pick a flap, those in the flap's largest piece of paper first (#600; owner decision 55, decided 2026-10-20, replacing decision 54 of the same day; [the questions and answers](https://github.com/avalonalex/senbazuru/issues/600#issuecomment-6308075051)). [C114](#changes-since-draft-v2) tried the corners and the centre lowest and then leftmost, so on the blintz with its corners folded behind the body was offered as `corner south-west`: a corner folded in, which picks the body only through the crease that joins it on. Decision 54 tried first the names in the flap's largest face; #601's code review found that a pre-crease cuts the blintz's diamond into faces the size of a corner triangle, so the corner came back, and that face sizes moved names on flat paper. `Resolve.seedForEachFlap` now groups the flap's faces into pieces, the faces folding placed together (`liesWith`: their placements take the sheet's box to the same place, within the sheet's tolerance), takes the piece of the greatest area, ties lowest and then leftmost by its largest face's point, and tries first the names whose faces (`seedFaces`) lie in it, then the rest, each group in C114's order. Flat paper is one piece, however many creases cross it, so it keeps C114's names: the flat blintz crease pattern still offers `corner south-west or corner south-east`, a real corner there, not decision 53's table row. A corner folded in is a piece of its own, so the folded blintz, its midlines pre-creased or not, offers `centre`, and the square with corner south-west folded to the centre offers its lower half by `corner south-east`. Where no name in the largest piece picks the flap, as when one pre-crease puts the centre on a crease and so in no one face, the rest are tried, and the corner folded in is offered, as in C114 | owner decisions 54 and 55; #600 | `Resolve.seedForEachFlap`, `liesWith` [code]. `RunSpec`: the blintz's edge 8 offers corner south-west or corner south-east; a new test, each name copied from the message into the source, parsed and folded: the square folded at y = 3/4, pre-creased a quarter up or not, offers corner south-west or corner north-west; folded from (1/4, 0) to (1, 3/4), corner south-west or corner south-east, the rest first though the triangle's own point is lower; with corner south-west folded to the centre, corner south-east or corner north-west; the blintz with its corners folded behind, its midlines pre-creased or not, centre; with one midline pre-creased, corner south-west [ran]. 112 seedless folds, #600's 57 and the code review's 55 (the blintz pre-creased four ways and folded, plain squares pre-creased or folded first, the crane and bird-base crease patterns, a square creased in a T), 40 of them on folded paper, run on 7c32c7e and on this commit: it changes 13 against 7c32c7e, all on folded paper, and offers what the prototype the question was put with offered in all 112; every offered seed, written in, folds the same file as 94cd756's six-place seed for that flap, 170 seeds [ran]. Red with the names in decision 53's order, the centre first, the largest face for the largest piece, the names outside it not tried, every face one piece, every face its own piece, pieces ranked by how many faces they have rather than their area, and the flaps listed by their faces' points [ran] | adopted (owner decision) | 02 |
| C116 | Statements false at `7af4c92` are corrected (#564, from #563's review): three that later PRs made false, two wrong when written, and others of the same kind the code review of #602 found. **AC-15** quoted the crane-spreading gallery's `[True, True, True, False]`, which #470 replaced. It now runs the gallery at the PR's head and its merge base and compares `curved`'s and `fine`'s panel energy to six significant digits, with `rigid` accepted and `crossed-grip` rejected ([owner decisions 56 and 57](#9-owner-decisions); 57 replaced 56's comparison of `accepted` flags, which #566 shows flip on changes of about 1e-13). **Golden counts.** Thirteen places in the PRDs gave the count as 33, the count on 2026-09-15 at `568dcb6`, with no date; #290, #341, #512, #513, #514 and #522 tracked ten more, 43 at `7af4c92`. A requirement now names the tracked goldens, and a count keeps its date. 06's table takes the three new goldens that fit its groups and names the other seven, and 09's link follows its heading. Records under `research/` are left as written. **The 30° root.** D14 cited `CraneSpread.hs:82-83` when #226 wrote it, lines that check only the extra angle; the 30° is fixed in `bentPoint`. **The stationary side.** 07 listed it as not exported, and 05 said so three times; #344 exported `flapStationaryFace` on 2026-09-23. **`rootStrip`.** Its comments, written with it in #460, said the held root strip is the whole base whenever the hinge is above the wing's widest point. `rootStrip` is `max (h/8) (h - widest)`, so the base is longer than an eighth of the tip side only when the hinge is above 8/7 of the widest point's y, 0.3708 on the crane; below that the length is the eighth, though at refinement 3 the vertices it holds still end on the join. The rule is now stated once, in `rootStrip`'s Haddock. Below the widest point the root strip and the tip grip end exactly on mesh lines; above it, as at the wing's root, the tip grip stops at the last line short of the eighth, y = 0.0406 of 0.047, and three docs that said it holds the final eighth now say so. **Other counts.** "23 call lines" leaves R-06-2, 06's summary and D7, and 06's table of them is dated; 09's `runIO` count is dated (14 at `568dcb6`, 20 at `7af4c92`). §11 gains the rule that a requirement names the set or the check, and a count carries its date. The citations this PR's comments moved are re-anchored | #564; #563's review; #602's review | `CraneSpreadGallery.hs:56`, `:139` [code]. The gallery on `7af4c92`, one run of 1011 s user CPU, `checks.json` read; #566's table for aed4755 [ran]. `git ls-files test/golden \| wc -l` gives 33 at `568dcb6` and 43 at `7af4c92`, and `git log --diff-filter=A 568dcb6..HEAD -- test/golden` names the six PRs and ten files; `stepPage`'s call lines are 23 in 15 files at both commits, a different set; 14 and 20 spec files use `runIO` [ran]. `git show 9e84a38` and `ee79df2` for the 30° and `rootStrip` as first written; `Flap.hs:92`, and #344 by `git log -S flapStationaryFace` [code]. In GHCi on the crane: the widest point is at y = 0.32442, 8/7 of it 0.37077; at h = 0.35 `rootStrip` is 0.04375 and the base 0.02558, and the held vertices end on the join at refinement 3 and 4; at 0.376 it is the base, 0.05158; with the hinge at 1/4 the root strip's held vertices end at y = 0.21875 and the tip grip's at 0.03125, at 0.376 at 0.32442 and 0.04055, at refinement 3 and 4 alike; reviewers measured h = 0.2, 0.3 and 0.32 exact and every hinge from 0.33 to 0.376 stopping at 0.04055 [ran]. The renamed test turns red with `rootStrip` always the eighth, the root strip unheld, the root turned 31°, or the join's guard removed [ran] | adopted (owner decision) | 00, 04, 05, 06, 07, 08, 09, 10, glossary additions |
| C117 | The contact clip snaps an edge lying along a clip line (#566, which also fixes #469; [owner decisions 58 and 59](#9-owner-decisions), decided 2026-10-21, questions and answers [58](https://github.com/avalonalex/senbazuru/issues/566#issuecomment-6326253994) and [59](https://github.com/avalonalex/senbazuru/issues/566#issuecomment-6327968908)). `SurfaceContact.clippedSeparation` clips one triangle's shadow by the other's sides and differentiates each clipped point. Where an edge of the clipped triangle lies almost along a clip line, its crossing `t = dp / (dp - dq)` slides the length of the edge when either end moves by 1e-13, and its true derivative reaches 1e12. Stacked layers of the crane wing have many such edges, a few times 1e-13 off each other's lines. A corner within 1e-14 of the line, measured as a cross product (the line's length times the distance), was snapped onto it and kept its derivative. A penetrating row with a large gradient made the Gauss-Newton system's right-hand side 1e4 to 1e7 and too ill-conditioned for the stopping test's linear solve (the sparse factor refused, or conjugate gradients using all 3000 iterations), so the crane-spreading `curved` control converged or not by whether such a row was penetrating at the end: #566's flip on changes of about 1e-13, and `fine`'s, which converged at aed4755 and not at 7af4c92 (#469). The band is now 1e-12 and the snapped distance is the literal 0, with no derivative: an edge with both ends in the band does not cross the line, and one with one end in it crosses there, with no derivative. The first fix, the band kept at 1e-14 with the derivative dropped, converged at every hinge but left large rows in place (owner decision 59). A crossing with both ends past the band still differentiates as about 1 / (dp − dq). `fine` converges, so the gallery again holds it to acceptance and shows its two-resolution comparison, and the page's text for an unaccepted `fine` is removed, since the page is written only when it is accepted. The clip's gradients reach 26 study galleries' solves and its values 42 more; only crane-spreading and the quick tier were run again, and [#605](https://github.com/avalonalex/senbazuru/issues/605) lists the rest, the notes that report them and the archive readers that pin runs made before the fix ([snap-edges-along-a-clip-line.md](../docs/notes/snap-edges-along-a-clip-line.md)) | #566; #469 | `SurfaceContact.clippedSeparation`, `CraneSpreadGallery`'s guard, `crane-spreading.html` [code]. GHCi probes (compiled `-O`, one run each, 2026-10-21) of `curved` at `wingRoot` + d for d = 0, ±1e-13, ±3e-13, ±1e-12, ±1e-11: on 0bdd02f 5 of 9 converged, the others exhausting their final stage, never a failed line search; a final-stage trace and an instrumented copy of the solver show the proposed movement already below 1e-7 and the linear solve failing, its right-hand side almost all contact; rows with gradient above 1e3 numbered 25 at d = 0 (largest 1.3e12, none penetrating) and 52 at +1e-13 (16 penetrating, largest 2.4e9). Band 1e-14 with the derivative dropped: 9 of 9, with 1 to 16 such rows at every hinge (largest 4.9e9 to 3.3e11, none penetrating); band 1e-13: 4 rows near 9e8 at 2 hinges; band 1e-12: none, largest 6.6; band 1e-12 divided by the edge length: 8 rows near 7e9 at 2 hinges; the crossing fraction held fixed: none (largest 2.2) but the crease-correction study's six viable starts no longer converge and the body patch's solves block stages; all 9 converge under each band [ran]. `fine` at d = 0 and +1e-13: 17 and 5 rows up to 3e10 with the 1e-14 band, none with 1e-12 (largest 6.2), converged both [ran]. Body patch, crease correction and wing layers with the band at 1e-12 against 1e-14: the same outcomes, `bad-grip` still failing, in 8 iterations rather than 4 [ran]. The gallery on this branch, three runs: `curved` 21 iterations, 8.8 to 9.2 CPU s, panel energy 0.0131811728; `fine` converged in 39, 175 to 184 CPU s, 0.0133058371; `crossed-grip` rejected, 0.0982759325; the comparison 0.946%; the whole run 345 to 356 CPU s; on main (7af4c92, one run) `curved` took 24 iterations and `fine` ran 43 unconverged, the whole run 1011 CPU s [ran]. `--crane-quick` on this branch: base angle 28.394°, accepted, all nine solves converged, 92.3 CPU s for the solves (one run); positions within 1.1e-11 of main's, so its SVG and GLB differ from main's in their last digits [ran]. `SurfaceContactSpec`'s new pair: largest gradient 1.02, 3.0e10 with the derivative kept, 2.7e10 with the band at 1e-14 [ran]. Full test suite after a clean build: 2294 examples, 0 failures, no warnings [ran]. #605's register is from reading the code at ca1f1bd, not from runs [code] | adopted (owner decisions 58 and 59) | 07 |
| C118 | Results recorded before #566's fix to the contact clip are measured again ([#605](https://github.com/avalonalex/senbazuru/issues/605); [owner decision 60](#9-owner-decisions)). Every gallery that can run was run twice on 2026-10-21, at 0bdd02f, just before #604, and at c143a35, after it, and the two outputs compared: every JSON value except CPU times, and each FOLD's geometry and layer orders. A note is changed where the run before the fix reproduces it and the run after does not; where the run before already disagreed with a note for other reasons, the note's new paragraph says so and [#608](https://github.com/avalonalex/senbazuru/issues/608) lists the claim. **Values only** (34 galleries whose solves never read the clip's gradients, among them body-checkpoints, body-crease-seed and whole-crane's start and view): every report is identical but for CPU times, body-crease-seed's unquoted witness counts, and body-checkpoints, which re-measures body-patch's changed archive; layer orders between faces that only touch along an edge drop from exported FOLDs with unchanged geometry, 56 in 8 values-only files, 68 in whole-crane's `before.fold` and 12 in each of crane-internal's held-internal files, all slivers, while other sliver orders remain ([#609](https://github.com/avalonalex/senbazuru/issues/609)). **Gradients** (crane-root, crane-body, crane-internal, whole-crane's correction, wing-layers, crease-correction, crease-inequality, bending, body-patch, body-subdivision and body-angle-contact; crane-spreading and the quick tier in #604): crane-body's `open` trial now converges and is accepted; crane-root's `released` strip, which converged at all nine hinge offsets probed before the fix, converges at seven after it and not at the gallery's own ([#607](https://github.com/avalonalex/senbazuru/issues/607), new evidence against decision 59's premise); crane-body's `weaker` trial loses its stable-view GLB to a circular order ([#610](https://github.com/avalonalex/senbazuru/issues/610)); every other accept and convergence verdict is unchanged. Numbers move in bending's checked curl, crease correction and inequality, wing layers, crane-root (`released`, `fine`, `flat`, `held-neck`), crane-body (its sides and stable views), crane-internal (one base side), whole-crane's correction (19 accepted moves, as its note says, against 20 just before the fix), the body patch, its checkpoints, body subdivision and body angle contact (1,205 inequalities against 1,204); each note says so in a dated paragraph, and crane-root's page now marks a turn from an unaccepted control. **The body chain** stops at `--body-subdivision`, whose archive every later body gallery refuses; their 26 notes open with a dated line marking them as records of runs made before the fix (decision 60), and [#612](https://github.com/avalonalex/senbazuru/issues/612) holds the re-pinning. Every other note #605 lists opens with a dated line saying it was checked, or not measured again, or is unaffected ([snap-edges-along-a-clip-line.md](../docs/notes/snap-edges-along-a-clip-line.md)) | #605 | `senbazuru-material-study` built at each commit, every flag with the same arguments, one run each on 2026-10-21, many at once, so CPU times are not compared [ran]; which flags read the clip's gradients or values, from #605's register, traced through the code at ca1f1bd, whose clip differs from c143a35's only in the band [code]; crane-root's `released` probed in GHCi (compiled `-O`, one run each, 2026-10-21) at `studyHinge` + d for d = 0, ±1e-13, ±3e-13, ±1e-12, ±1e-11 on both commits [ran]; each dropped order's faces clipped against each other in projection along z, the largest covering 1.4e-10 of the smaller face [ran]; `--body-contact` on the regenerated subdivision archive refuses with `changed archive field: "scale"` [ran], and every other downstream reader reaches the same check through `readCorrectionArchive` [code] | adopted (owner decision 60) | — |
| C119 | The contact clip's snap band is 1e-12 as a distance ([#607](https://github.com/avalonalex/senbazuru/issues/607); [owner decisions 62 and 63](#9-owner-decisions), decided 2026-10-22, [question and answer](https://github.com/avalonalex/senbazuru/issues/607#issuecomment-6345250619), [the cause corrected](https://github.com/avalonalex/senbazuru/issues/607#issuecomment-6351653106)), revising decision 59's 1e-12 of the cross product. `SurfaceContact.clippedSeparation`'s clip compares a corner's cross product with the clipping side against 1e-12 times that side's projected length, the test `Senbazuru.Origami.Contact.clipBy` makes, so the band is the same distance at every refinement. #607 found crane-root's released strip, hinged at y = 1/4, converging at 14 of 19 hinge offsets with decision 59's band, against 19 of 19 before #604; the five failures end in one state. The cause is a jump in the contact penalty at the band's edge: a corner snapped onto a clip line counts as inside, so an overlap of no area appears, each copy of its corner a contact row at full depth. In the stalled stage five such rows at −1.09e-9 appeared at every scale of the step from 2⁻⁷ to 2⁻²⁴, and the line search kept only 2⁻²⁶. The rows the whole step drove to −1.7e-7, some 8e-10 clear at its start and some from overlaps not yet there, refuse only steps of 2⁻⁶ and longer. Under the distance band the stalled positions add no such rows, and the stage converges. The band moves the jump rather than removing it; [#617](https://github.com/avalonalex/senbazuru/issues/617) tracks removing it. Three solver changes that add the rows a step would carry into contact, tried at nine offsets, were aimed at the long steps' rows: two fixed the released strip and broke crease correction or the body patch, and with the third neither the released strip nor `curved` converged at any offset. With the new band the released strip converges at 19 of 19 offsets and the gallery accepts it again; `curved` converges at 19 of 19, with rows above 1e3 left at 5 of the endings, none penetrating, against 2 with decision 59's band; `fine`, the quick tier and the body, crease and wing-layer solves are unchanged in outcome. [#613](https://github.com/avalonalex/senbazuru/issues/613) measures the other galleries again with this band | #607; #614's code review | `SurfaceContact.clippedSeparation`; `SurfaceContactSpec`'s new length-2 pair (gradient 1.005; 2.6e10 with 1e-12 of the cross product; 3.0e10 with the derivative kept) [code] [ran]. GHCi probes, compiled `-O`, one run each: on 2026-10-21, the stalled final stage re-run with every step recorded, the linear solve converging at each step while the full movement stays at 9.918e-7, and its rows matched across the step [ran]; on 2026-10-21 and 2026-10-22, the three solver variants at d = 0, ±1e-13, ±3e-13, ±1e-12 and ±1e-11 [ran]; on 2026-10-22, the released strip and `curved` at d = 0, ±1e-13, ±3e-13, ±1e-12, ±3e-12, ±1e-11, ±3e-11, ±1e-10, ±3e-10, ±1e-9 under five bands (`curved` under four), `fine` at two hinges under four, and the body, crease and wing-layer solves under three [ran]; on 2026-10-22, in #614's code review, the stalled step's objective at every scale under both bands, its stage re-run from the stalled positions under the distance band, and two triangles across the band's edge [ran]. The crane-root, crane-spreading and quick-tier galleries at b7b3c11, 2026-10-22, one run each: released accepted with edge error 8.06e-7, every other verdict unchanged; `curved` 20 iterations, panel energy 0.0131811732, `fine` 37 and 0.0133058368, the comparison 0.946%; the quick tier 28.394° with positions within 1.6e-11 of main's [ran] | adopted (owner decisions 62 and 63) | — |
| C120 | One model's whole run is held to 10 minutes of wall clock ([#606](https://github.com/avalonalex/senbazuru/issues/606); [owner decisions 61 and 64](#9-owner-decisions), decided 2026-10-21 and 2026-10-23, questions and answers [61](https://github.com/avalonalex/senbazuru/issues/606#issuecomment-6332905612) and [64](https://github.com/avalonalex/senbazuru/issues/606#issuecomment-6370422511)). The record limited a run's work and never its time; this sets one target in time, an acceptance target timed by hand. [09 §6.4](09-testing-and-acceptance.md#64-one-models-whole-run-timed) states it and how it is timed, with rows M5 (d), M6 (d) and M8 (a) in 09 §4; 07 and 11 point there beside their budgets, and D16 names it. No code compares a time with it: D15's rejection of wall-clock settle limits and D16's "No wall-clock guard is adopted" stand, and R-07-41's triangle budget stays what `run --settle` checks. The crane is the test case and no milestone runs it whole, so its time is the sum of two sources' (decision 64): the crane-wing sequence with the settle #560 re-derives, and the crane from a square as far as it runs. For each source, the commands that write its sequence file, its step page and its settles' files are timed, each output written once and each settle solved once: decision 61's question named `senbazuru run`, which writes one output per run and skips settles from M6 to M8 (R-07-10), when only the study's `--sequence` settles. One run within 10 minutes passes whatever else is running, since other work can only slow it; a run over it fails only if 3–5 more on a quiet machine are all over too. 09 §6.1 said seconds appear only as CI job timeouts, which already left out §6.3's rule moving spec files with a test of 10 s or more into the slow job; it now names both and §6.4's target, and §6.3 item 3 gives the job timeout as the only limit CI puts on time | #606; #621's code review | 07's "Budgets count refined triangles before solving, never seconds", D15's rejected wall-clock settle limits, D16's "No wall-clock guard is adopted", 09 §6.1 and §6.3 items 3 and 5, R-07-10, D13's one output per run, §7's crane-wing source, §10 item 43, 02 §8's `not modelled` folds, and 10 §2's edges M4 → M5 and M4 → M6 [prd]. `examples/traditional-crane.foldseq`'s 28 steps, step 24 "Swivel the tail up" the first `not modelled` [code]. `sysctl -n machdep.cpu.brand_string hw.ncpu hw.perflevel0.physicalcpu hw.perflevel1.physicalcpu` prints Apple M1 Max, 10, 8 and 2 [ran]. `senbazuru run examples/traditional-crane.foldseq` on b21b96e stops at step 4, "a macro move cannot be run yet" [ran]. The question's 87–92 are the quick tier's `solveCpuSeconds` on 2026-10-21, one run each: 90.8 on main before #566's fix, 87.4 on a fix never merged, 92.3 on the fix merged; its 10,494 is the `user` line of crane-body's log from #605, whose runs went many at once (real 11,657 s) [ran]. On b21b96e, after #614, #619 and #620, the whole quick-tier gallery, `senbazuru-material-study --crane-quick DIR`, took 39.6–40.3 s of wall clock over three runs on 2026-10-23, and its solves 31.2–31.5 s of CPU time against C117's 92.3, at base angle 28.394° and accepted each time; one-minute load averages were 6.4–7.2 at each start, with other work running, so these are not §6.4 timings [ran] | adopted (owner decisions 61 and 64) | 07, 09, 11 |
| C121 | Flat figures on step pages fan their layers from their folds ([#623](https://github.com/avalonalex/senbazuru/issues/623); [owner decisions 65 to 67](#9-owner-decisions), decided 2026-10-23, [questions and answers](https://github.com/avalonalex/senbazuru/issues/623#issuecomment-6375940371)). 06 gains §10, R-06-24–28, A18–A22, two new goldens, five rejected alternatives and three risks. Each corner of a flat figure is drawn 1.5 page units toward the page's lower left for each sheet lying over it, at most 6, so a fold's two faces, which share its corners, stay one line, and paper nothing covers stays where it lies. `run -o x.svg` fans by default and `render` only with `--fan`, so `render`'s output and every tracked golden are unchanged; a figure that cannot fan is drawn unfanned. The count is taken at each corner, not from `layerDepths`' depth of a face, which is the longest chain over the face anywhere and in the prototype moved paper nothing covers. The owner's "visually a bit busy" is a risk, with fanning only the paper the last *N* moves turned as an idea, not a decision. 08 records the GLB's version for later (#624); the M3 rows of 09 §4, 10 §1 and §8, and the glossary follow | #623 | Foldinator's 3OSME paper (2001), its method and figures 1–10, read 2026-10-23 [research]. The offset view's header in `Render.CreasePattern`, `Diagram.Style.layerStep`, `Origami.Layers.layerDepths`' contract and `Origami.Visible`'s note on twists [code]. A scratch prototype, not in the tree: depths from `layerDepths` with the view reversed, in GHCi over the built library, drawn by a Python painter, on `helmet.foldseq`'s run, `bird-base-sequence.fold`, `blintz-sequence.fold`, and the crane, square base, waterbomb base, fish base and `kabuto.fold` folded and stacked; counts as in 06 §10's table, the per-face depth moving the helmet's third figure, and a cap of 6 leaving the crane no busier [ran]. `foldFrame` on eight fixtures with every crease at 97% and at 90% of its angle: seven `TornAt`, and `blintz-base.fold`, with no fold vertex inside the sheet, folds [ran]. `git ls-files test/golden`: 43 files, 32 SVG, 26 drawing folded paper or a step page [ran] | adopted (owner decisions 65 to 67) | 06, 08, 09, 10, glossary additions |

## Proposals not adopted

| Proposal | Where | Reason |
| --- | --- | --- |
| `Run` defined in `Sequence.Record` holding the abstract final `FoldState` | 01 §1.2 rule 4 note | Nothing that reads a run needs the working pattern, and a renderer able to reach it can come to depend on it; `Run` keeps displayed states instead ([D23](#d23-the-sequence-modules-and-where-run-lives)) |
| Keep the syntax constructors `Mountain`, `Valley`, `Above` beside `Fold.Types`' and export lowercase builders only | 03 note, owner question 5 | `Sequence.Run` imports both modules, so the library itself would need qualified names at every use; renaming two constructors costs less ([D1](#d1-one-first-order-syntax-tree-built-by-name-only-builders)) |
| `decodeFile`'s `explain` names the `run` verb | 04 note, following v2 D13 | Contradicts v2 D20's rule against command-line words in library messages; the hint moves to `app/` ([D13](#d13-the-run-verb-and-io)) |
| #60 closes at M3 | 10 §4 note | Its amended done-when includes the authoring test, which lands with M4 ([D16](#d16-testing-and-acceptance)) |
| `expect refused` records "the refusal" as its evidence | v2 D21; 02 §6.1 | A refusal is not a claim about a route taken, and every record consumer would have to skip it; the outcome is kept in the `Run` and printed by `--report` ([D21](#d21-repeat-checkpoint-not-modelled-expect-refused)) |
| `expect refused` and `rotate` written at top level | v2 §7 examples | A top-level move has no defined state, and the header takes no moves ([D12](#d12-the-text-syntax)) |
| `expect refused FlapEndpointOrder` in the crane example | v2 §7; 04 crane example | The selection rule refuses a covered flap before `Flap` runs, so the kind is `FlapCovered`, **UNVERIFIED** ([D21](#d21-repeat-checkpoint-not-modelled-expect-refused)) |
| The crane's `diagonals` and `midlines` steps (v2's steps 1 and 3) sharing one crease batch | v2 D22 | Contradicts the same decision's rule, and a batch across steps shows a later step's creases on an earlier figure ([D22](#d22-figures-holding-several-moves)) |
| The figure-per-corner layout reuses `checked-blintz.svg` | v2 §7 | That golden has eleven figures, halfway poses included ([D16](#d16-testing-and-acceptance)) |
| A presentation change needs every vertex to move (R-05-12) | v2 D5 | The turn-over's own axis vertices stay still: 3 of 9 on the quarter fold [py] ([D5](#d5-presentation-and-the-readers-side)) |
| One raw sense sets the sign of `Flap`'s travel | v2 D5 | The sign also depends on which way up the first segment's stationary face lies ([D5](#d5-presentation-and-the-readers-side)); since D5's amendment, the moving face beside each segment |
| The runner reads the first stationary face's way up and signs the travel itself | 02 §5.3 note, first option | Way-up decisions stay in the library, where `Flap` already holds the face's ring; an entry taking a side does the same work there |
| A checkpoint folded from its assignments | v2 D21 | It would ignore a checkpoint file's recorded angles while `start folded` keeps a sheet's ([D21](#d21-repeat-checkpoint-not-modelled-expect-refused)) |
| Test 2's clauses "every written edge inside exactly one fixture edge" and "every unmatched fixture vertex lies on a written edge" | v2 D16 | Both are false on correct frames [py]; T1–T5 replace them ([D16](#d16-testing-and-acceptance)) |
| `git diff --name-only origin/main -- test/golden/` as the golden check | v2 D16 | It mixes added with changed files, reads the working tree, and includes `main`'s own new commits ([D16](#d16-testing-and-acceptance)) |
| "No released hold" as a `NoDifference` condition | v2 D14 | Releasing a hold cannot move anything from an equilibrium start, so the clause tests nothing ([D14](#d14-material-consumption)) |
| `refine sideword INTEGER` | 04 grammar | Cannot name `CraneSpread`'s second refinement region ([D14](#d14-material-consumption)) |
| One `recordDisplay` field | v2 D14; 06 R-06-16 | Cannot say which display a `Presented` record's before-state had, or separate presentation from anchor placement for animation ([D14](#d14-material-consumption)) |
| The recorded seed "(3/4, 1)" for quarter-fold step 2 | 01 §5.8 | It lies on an edge, so it cannot fill the region slot `unfold` re-resolves it in ([D2](#d2-references-named-on-the-sheet-and-resolved-by-slot)) |
| G1's statement that the authoring test hits an anchor on a new crease | 02 §14 G1 | That test writes `anchor (3/4, 1/4)`; the rule G1 proposes is kept for sequences that do ([D3](#d3-the-runner-owns-the-state-its-start-and-the-handoffs)) |
| `Sequence.RunPlan`'s plan holding `View` and the glTF export mode | 04 "The run verb" | Those types are in row 7, which a row-6 module cannot import ([D13](#d13-the-run-verb-and-io)) |
| `stepNotes` total | v2 §5; 06 R-06-20 | It shares `writtenStates`' refusals ([D23](#d23-the-sequence-modules-and-where-run-lives)) |
| An unassigned crease with a nonzero angle takes M or V at the start | v2 D3, second clause | Intent is a claim about how a crease was made; `U` at an angle is consistent and the runner must not invent it ([D3](#d3-the-runner-owns-the-state-its-start-and-the-handoffs)) |
| A pose angle is "positive = valley as seen from the reader's side" | v2 D9 | That needs a per-layer flip, undefined for paper in the air ([D9](#d9-macro-moves-as-named-angle-relations)) |
| A macro checked only at its authored samples | v2 D9; 05 R-05-42 | Evidence would depend on an illustration choice ([D9](#d9-macro-moves-as-named-angle-relations)) |
| Existing library messages adopt "(internal …)" ids now | 05 open question | It moves sentences pinned by specs and quoted in docs; a follow-up issue ([D20](#d20-errors)) |
| An `.Internal` module exporting `FoldState`'s constructor | considered here | No precedent in `src` [ran], and nothing outside the runner needs the constructor |
| A `recordFigure` field | v2 §5 | A figure number and a step number differ once a step writes samples or nothing; records carry `recordStep` ([D24](#d24-states-figures-and-their-numbers)) |
| `RelationNotOverlapping` and `RelationsContradict` in the runner's `StackingChoiceError` | 02 §12 | The solver detects both from face ids, so they belong to the library's `StackingError` ([D11](#d11-stacking-choices-are-relations)) |

## Appendix: commands behind the numbers

Run from the repository root on 2026-09-15 at `568dcb6`, unless an entry says
otherwise. Outputs are abbreviated to what this record cites.

1. **Goldens.** `git ls-files test/golden | wc -l` prints `33`.
   `git diff --name-only --diff-filter=MD origin/main...HEAD -- test/golden/` and the
   same with `--diff-filter=A` print nothing.
2. **Vertices on a turn-over's axis** (05 L3's command):
   `python3 -c 'import json;[print(f,sum(v[0]==(min(u[0] for u in V)+max(u[0] for u in V))/2 for v in V),len(V)) for f in ["quarter-fold-steps","quarter-fold","bird-base","blintz-base"] for V in [json.load(open("examples/%s.fold"%f))["vertices_coords"]]]'`
   prints `quarter-fold-steps 3 9`, `quarter-fold 3 9`, `bird-base 5 13`,
   `blintz-base 2 8`.
3. **Rigid pairs in multi-frame examples**: 05 L3's "Outputs unchanged" command
   prints `examples/bird-base-sequence.fold 0 15` and
   `examples/quarter-fold-steps.fold 0 2`.
4. **`puffed-square.fold`.**
   `jq -c '{vertices: (.vertices_coords|length), faces: (.faces_vertices|length), edges: (.edges_vertices|length), assign: (.edges_assignment|group_by(.)|map({(.[0]): length})|add)}' examples/puffed-square.fold`
   prints `{"vertices":121,"faces":200,"edges":320,"assign":{"B":40,"F":280}}`. 08's
   silhouette script (08 "W1: an exact line drawing") prints `upward normals: 200`,
   `iso away: 0 edge-on: 0 silhouettes: 0 classes differ: 0` and
   `front away: 90 edge-on: 20 silhouettes: 27 classes differ: 46`.
5. **Test 2 on hand-built frames**: 09 §11 command 4 prints
   `0 4 4 False False True True`, `1 6 7 False True True True`,
   `2 9 12 True True True True` (state, written vertices, written edges, v2's edge
   clause, v2's vertex clause, T1, T2).
6. **Snapshot versions.** In a scratch directory,
   `sqlite3 -readonly ~/.stack/pantry/pantry.sqlite3 "select writefile('lts.yaml', contents) from blob where id = (select blob from url_blob where url like '%lts/22/44.yaml')"`,
   then `grep -nE "megaparsec-|parser-combinators-|hspec-2|QuickCheck-" lts.yaml`,
   lists `megaparsec-9.5.0`, `parser-combinators-1.3.0`, `hspec-2.11.12` and
   `QuickCheck-2.14.3`.
7. **Ulps between manifest literals and formulas.** A `python3` script stepping with
   `math.nextafter` from each formula value to the stored literal:
   - rabbit ear, m = 30:
     `2 * math.degrees(math.atan2(math.sin(math.radians(56.25)) * math.sin(m/2), math.sin(math.radians(11.25)) * math.cos(m/2)))`
     with `m = math.radians(30)` gives `97.58514830800294`, 1 ulp from the stored
     `97.58514830800293`; the `atan` form `2 * math.degrees(math.atan(a / b * math.tan(m/2)))`
     gives the literal;
   - petal, t = 175: `CheckedPetal.hs:107`'s
     `360 / math.pi * math.atan2(math.sin(math.pi/8) * math.sin(h), math.cos(h))`
     with `h = 175 * math.pi / 360`, negated, gives `-166.98236060695518`, 3 ulps from
     the stored `-166.98236060695527`; `-2 * math.degrees(math.atan(math.sin(math.pi/8) * math.tan(math.radians(175)/2)))`
     gives the literal. The count depends on the expression's order of operations,
     which is why the stored value, not a formula, is the fixture.
8. **Blintz.** [00](00-overview.md#the-problem-in-one-example)'s exact-fraction script
   prints edges `[8]`, `[9]`, `[10]`, `[11]` for the four corners and
   `centre is vertex: False`. With `rot = lambda p: (1 - p[1], p[0])`, edge 8's image
   is `[('1', '1/2'), ('1/2', '1')]`, equal to edge 9, and both file angles are −180.
9. **Quarter-fold step 2's seed.** A `python3` script listing edges with material
   y = 1 gives `[4, 5]`; both have length 1/2, the leftmost is edge 5, whose face is
   2 (`[8,6,3,7]`) with vertex mean `(0.25, 0.75)`.
10. **`crane.fold`.** `jq '[.edges_assignment[] | select(.=="U")] | length' examples/crane.fold`
    prints `0`.
11. **Lines and files.** `grep -n` for the blintz and `HingeSweep` sentences in
    `docs/architecture.md` gives lines 288, 297 and 298; `grep -n "vocabulary\|#60" README.md`
    gives line 213; `grep -n creaseEndFlag src/Senbazuru/Origami/ThroughLayers.hs`
    gives lines 96 and 196; `find src -path '*Internal*'` prints nothing;
    `grep -rn "step record" PRDs/*.md` finds four rows of `glossary-additions.md`.
    The `docs/architecture.md` and `ThroughLayers.hs` lines are as #478, #480 and
    #482 renumbered them on 2026-10-03; at `568dcb6` they were 202, 211 and 212, and
    96 and 195.
12. **Issues.** `gh issue view N --json title,state,body` for #60, #94 and #104; all
    open.
13. **Fixture setup** ([C99](#changes-since-draft-v2)), run on 2026-10-12 at
    `a71ac04` on an M1 Max. After `stack build --test --no-run-tests`, three runs of
    `/usr/bin/time -p "$(stack path --dist-dir)/build/senbazuru-test/senbazuru-test" --match no-such-example-anywhere`
    print `0 examples` in 14.67, 18.07 and 15.22 s of wall time (`real`) and 14.22,
    16.52 and 14.68 s of user CPU (`user`). The binary runs directly, so these leave
    out what `stack test` adds. A spec is stubbed out by
    `sed -i '' 's/^spec = /specOff = /'` on its file (macOS's `sed`; GNU's takes `-i`
    alone) and appending `spec = pure ()`, then rebuilding, checking that the rebuild
    succeeded, and restoring `test/` with `git checkout -- test/` between
    configurations. C99's other figures stub out every spec
    `git grep -l runIO -- test` lists, then all but one of them, then only
    `CheckedBirdSpec`, `CraneWingSpec` and `CheckedPetalSpec`, with three runs each
    and five for the last. A probe file, `BeforeAllProbe.hs`, has one example built
    by `runIO` and one by `beforeAll`, each action printing a line to stderr. Run as
    `stack runghc --package hspec -- BeforeAllProbe.hs --match <pattern>`, it prints
    only the `runIO` line for a pattern selecting no example and for one selecting
    only the `runIO` example, and both lines for one selecting the `beforeAll`
    example.
14. **Test time by spec file** ([C101](#changes-since-draft-v2)), run on 2026-10-12
    at `c17d317` on an M1 Max. After `stack build --test --no-run-tests`, one run of
    `/usr/bin/time -l stack test --test-arguments="--jobs=4 --print-slow-items=100000 +RTS -N4 -RTS"`
    prints `Finished in 417.3216 seconds` and `2238 examples, 0 failures`, in
    439.74 s of wall time (`real`) and 900.83 s of user CPU (`user`). hspec's time
    starts once the spec tree is built, so it leaves out the `runIO` setup C99
    times. `--print-slow-items` lists the 699 examples of 1 ms or more, each with
    its own wall time while four ran at once, so they add up to 1,810.2 s, over
    four times hspec's; the 1,539 it leaves out add under 2 s. Summed by file with
    `sed -nE 's/^  (test\/[^:]+):[0-9]+:[0-9]+: .*\(([0-9]+)ms\)$/\1 \2/p' | awk '{t[$1]+=$2} END {for (f in t) print t[f]/1000, f}'`,
    they give 4.0 s for `test/Senbazuru/` and 1,806.2 s for the study spec files at
    the top of `test/`; the 44 examples of 10 s or more take 1,621.9 s, in 20 files
    that take 1,745.4 s. The CI figures are one run, `main`'s run 38321475359 on
    `a303ce8`, read with `gh run view 38321475359 --log`: its
    `stack test --test-arguments="--jobs=4 --print-slow-items=20 +RTS -N4 -RTS"`
    step prints `Finished in 515.2860 seconds` and `2238 examples, 0 failures` and
    lists 20 examples of 34.9–202.4 s, all study specs. By the log's timestamps the
    step took 536.9 s, and its first example printed 20.6 s after the suite started.

15. **The wing's root, its join and its bands** ([C103](#changes-since-draft-v2)), run on
    2026-10-13 at `aed4755` in `stack exec -- ghci -isrc -istudy/fold-material -fobject-code`,
    on `examples/crane.fold`'s key frame unless named, with scratch copies of study code
    changed only as said. y* = 1 − (√2/4)(1 + 2 sin 22.5°) is the root's exact height.
    - *The root.* `FlapRoot.findRoot` with `sheetHair` passed in puts the root's ends 1.12e-9
      and 1.36e-9 below y* at a hair of 1e-9, and 4.3e-13 and 4.6e-13 below at 1e-13 or less.
      Crossing the folded panel edges within 1e-6 of each end, 64 pairs an end, puts every
      crossing within 1.2e-13 of y*. `prepare`, `findRoot` and `turnAbout`, as `writeFlapRoot`
      runs them (`FlapRoot.hs:252-263`), were run on each corner of `kabuto.fold` and of every
      `*-base.fold` but `blintz-base` and `book-base`, which a later run also refused: every
      base corner prints "the flap's edge never meets other paper", and three kabuto corners give
      a root the flap turns 90° about.
    - *Fixtures against O4's line.* `buildCraneWingAt` at `wingRoot`, at corner north-east's
      folded y and at the crossings' mean, each against `perpendicular to [corner north-west,
      midpoint of edge north] through corner north-east`, placed with `Resolve.positionOf` and
      clipped to faces 2, 3, 6, 7, 32, 34, 35 and 38: the hinge's ends lie up to 1.76e-9,
      7.6e-14 and 2.1e-14 from it.
    - *The join.* `buildCraneWingAt` with `CraneWing.hs:166`'s join left out, or assigned `F`
      or `U`, and with its hinge and join creased as two batches in each order. On each, the
      curved control (`WingOnly`, refinement 3, 20°) has its start's contact check and crease
      errors read before solving, and is then solved with the gallery's `Settings 20 1e-5` and
      with 40 iterations per stage; the rigid control is solved too, and the `U` line is given a
      rest angle of 0. The folded vertices within 1e-9 of `craneWidest` are listed.
    - *Bands.* `bentPoint` (`CraneSpread.hs:154-168`, not exported) copied with R-07-13's band
      rule, which together reproduce `spreadPins`, select with the ends C103 names, at both
      heights, with and without the join, at refinements 3 and 4, and the selected vertex ids are
      compared with `spreadPins`'s; `closed across-hinge moving` is resolved from the record's
      panels with and without the widest line. The arc is started from the farthest held vertex,
      or from a typed end rounded to 4–15 decimal places, of which 11 is the first within 1e-12.
16. **The crane wing's sense at the root, and its hinge against O4's line**
    ([C107](#changes-since-draft-v2)), run on 2026-10-13 on #575's code, its commit `1e4fb48`, in
    `stack ghci senbazuru:test:senbazuru-test`, on `examples/crane.fold`'s key frame, with
    `open = buildCraneWingWith WithoutWidestJoin h` and h = `wingRoot`, 0.37584855933367634.
    - *The sense.* `craneSide open` is face 44, whose `panelFaceUp` in `flatSheet` of
      `foldedFrame (craneStart open)` is `False`; the first hinge segment is edge 138. The
      builder accepts the turn of +90 and refuses −90 at progress 0 (`craneRefusal`).
      Vertex 2, the wing's tip, is at z = 0 in the start and at z = −0.3758485593336299
      in `flapAt (craneOpening open) 1`.
    - *The hinge against O4's line.* `Resolve.foldLine 1e-3` of the O4 construction on
      `flatState` of `foldFrameWith` of the key frame gives a line through
      (0.6464466094067096, 0.3758485593336449) along (−1, −7.7e-14); h lies 1.37e-14 above
      it at x = 1/2 + y\* and 5.5e-15 below it at x = 3/2 − y\*.
