# Decisions: connecting the fold solver and the material study

**Status.** The current decision record, version 3. Dated 2026-09-15, against
commit `568dcb6`. Nothing is implemented. Every PRD file in this directory is
written against this record, and where a file and this record disagree, this
record wins and the file is to be corrected.

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
[the glossary](../docs/glossary.md). Evidence tags:

| Tag | Meaning |
| --- | --- |
| [code] | lines read on 2026-09-15 at `568dcb6`, cited as `path:line` |
| [jq], [py] | a fixture measurement by a command run for this record; the commands are in [the appendix](#appendix-commands-behind-the-numbers) |
| [ran] | a `git`, `grep` or `sqlite3` command run for this record, also in the appendix |
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
          Sequence.Elaborate (let, fold-and-unfold; keeps provenance)
                         |
          Sequence.Run  (Budget, RunSettings, sheets) over Fold.* / Origami.*
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

| # | Where | Change (summary) | Lands |
| --- | --- | --- | --- |
| 1 | `docs/architecture.md:81-86` | `Fold.Creasing` is frame in, frame out; a sequence's moves are not: `Sequence.Run` returns records, and what reaches the pipeline as a file is the written `FoldFile` | M0 |
| 2 | `AGENTS.md:193-196`, `docs/architecture.md:170-175` | stated exception: a sequence source is a program, not an input format | M0, no later than M1's `Sequence.Parse` PR |
| 3 | [#60](https://github.com/avalonalex/senbazuru/issues/60) | `runSequence` returning a run of records; "one interpreter" superseded; done-when split into folding equivalence and authoring ([D16](#d16-testing-and-acceptance)) | M0 |
| 4 | [#95](https://github.com/avalonalex/senbazuru/issues/95) | turn over is presentation about a model-intrinsic axis ([D5](#d5-presentation-and-the-readers-side)) | M0 |
| 5 | [#97](https://github.com/avalonalex/senbazuru/issues/97) | note named `docs/notes/sequences.md`; "scheme" retired; closes at M2 | M0 |
| 6 | [#111](https://github.com/avalonalex/senbazuru/issues/111) | add the writer's at-rest rule and the two `1e-10` thresholds ([`Surface.hs:278`](../src/Senbazuru/Origami/Surface.hs#L278), [`StudyCase.hs:208`](../study/fold-material/StudyCase.hs#L208)) that should read `Fold.Query.atRest` | M0 |
| 7 | #36, #94, #104, #114, #56, #64 | premise and done-when corrections ([§10](#10-corrections)); #104's done-when names `--view front` ([D19](#d19-realistic-rendering)) | M0 |
| 8 | `AGENTS.md` "Third-party material" | running an external program is not vendoring ([D17](#d17-third-party-and-external-tools)) | M0 |
| 9 | `docs/notes/no-sequence-solver.md` | the vocabulary is formal now; searching it stays a non-goal | M0, with [#96](https://github.com/avalonalex/senbazuru/issues/96) |
| 10 | `docs/glossary.md` | move glossary-additions rows in; fix rest angle (`:19`, `:83`) and flat-folded (`:21`) | M0, first PR |
| 11 | `AGENTS.md:173-177` "Two unit systems" | sheet lengths and physical lengths, each converted in one named place | with M2 |
| 12 | `AGENTS.md:217-221`, the `--layer-budget` list | add `runSequence` at M2 and `stepPageWith` at M3 | M2, M3 |
| 13 | `src/Senbazuru/Origami/Step.hs:30-34` | a whole-model rigid motion is a presentation change, tested as "some vertex moves" ([D5](#d5-presentation-and-the-readers-side)) | the M2 PR classifying presentation |
| 14 | `docs/architecture.md:202-211`; `BlintzSequence`, `HelmetSequence` headers | recipes replaced by sequences | the recipe deletion PRs |
| 15 | `AGENTS.md:378-379` "all three CI checks" | name the slow job, and whether it is required (owner decision 12) | the M4 PR adding the slow job |
| 16 | `docs/roadmap.md:82-87`, `:368-373` | the recorded order (#93, #96, #97, "only then" #95, #94, #36) replaced by the milestones | M0 |
| 17 | `test/Senbazuru/Origami/ThroughLayersSpec.hs:271-275`, `docs/usage.md:866-872` | the `LineStopsOnTheModel` sentence names the end by its point ([D20](#d20-errors)) | the follow-up PR, before M4 |
| 18 | `README.md:213` roadmap item 2, `docs/roadmap.md` item 2 | the vocabulary exists | the PR closing #60 (M4) |

Row 14's range was `202-213` in v2. `grep -n` puts the blintz sentence at
`docs/architecture.md:202` and the end of the helmet sentence at `:211`, with
`HingeSweep`'s paragraph starting at `:212` [code], so `202-211` is right.

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
  segments are collinear within `Fold.Faces.tolerance`; `crease [P, Q]` (Lucero's
  eighth, along existing creases); `hinge of NAME`, `crease of NAME`; and the
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
  both sides with a working seed for each.
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
  beyond `nearMissBand`.

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
- **Intent at angle 0 is kept on purpose.** A precrease lying flat stays M or V on
  the working pattern, departing from `Fold.Creasing`'s "a valley with an angle of
  nought is not a valley" ([`Creasing.hs:281-286`](../src/Senbazuru/Fold/Creasing.hs#L281-L286)).
  It is needed because `Flap` turns only M, V or U
  ([`Flap.hs:187`](../src/Senbazuru/Origami/Flap.hs#L187)) [code] and a collapse
  binds on direction; it is safe because folding reads explicit angles first and
  stacking reads an assignment only at angle 0, where a crease orders nothing.
  Written frames restore the FOLD rule ([D4](#d4-written-frames-follow-the-state-rule)).
- **Starting.** `Sequence.Run.sheetState :: SheetStart -> Frame -> Either SheetProblem FoldState`
  is pure; the CLI only loads bytes.
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
     ([`Folding.hs:507-533`](../src/Senbazuru/Origami/Folding.hs#L507-L533)) [code],
     then chooses a stacking by [D11](#d11-stacking-choices-are-relations).
     `sheet square` is the unit square.
- **Default anchor** ([C20](#changes-since-draft-v2)): the *vertex mean* (the
  average of the corner coordinates) of the initial pattern's largest face, ties
  to the lowest then leftmost vertex mean. That is `StudyCase`'s rule, which ranks
  by area, then negated mean y, then negated mean x
  ([`StudyCase.hs:242-248`](../study/fold-material/StudyCase.hs#L242-L248)) [code];
  v2 and the glossary said "centroid", which differs on a general quadrilateral.
  The header's `anchor P` overrides. A vertex mean not strictly inside its own
  non-convex face is refused, asking for `anchor P` (G13).
- **Re-anchoring** (owner decision 3, default re-anchor). When a move's moving
  side contains the anchor's face, the new anchor face is the stationary face
  beside the hinge with the largest material area, ties by lowest then leftmost
  material vertex mean, never by face id; its vertex mean becomes the anchor.
  Mechanism: read h, that face's placement in the current raw fold, before
  reordering; anchor placement := anchor placement ``after`` h; put that face
  first; re-map orders and requirement pairs; refold; join-check displayed
  positions. Refused as `ReanchorNotFlat` if the new face's displayed normal is
  not ±ẑ. The move `anchor P` does the same on demand.
- **An anchor that a new crease passes through** (G1, [C19](#changes-since-draft-v2)).
  After creasing, if the anchor point is no longer strictly inside one face, the
  anchor moves to the vertex mean of the largest face whose closed polygon contains
  the old point and which this move does not turn, ties lowest then leftmost.
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
     pattern, refold. Never attach orders to a `Folded` as `CraneWing.hs:79` does;
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
  "From reading the code (counts, not timings)"); measure before caching.

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
  or V at 0.
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
- **Exactness.** Turn-overs, half turns and quarter turns use exact 0/±1 entries.
  Eighth turns use `rotationAbout` (owner decision 10); joins compare unpresented
  positions, so exactness is not needed, and written coordinates carry platform
  trigonometry bits, stated. Every presentation `Rigid` is checked by
  `isProperRotation`: rows orthonormal and det = +1, each within 1e-12, since
  `Rigid` "will hold any 3×3 matrix … and nothing here checks"
  ([`Rigid.hs:24-26`](../src/Senbazuru/Geometry/Rigid.hs#L24-L26)).
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
  [`:201-216`](../src/Senbazuru/Origami/Flap.hs#L201-L216)) [code]. Edge 11's
  stationary face was turned over by step 1, so the same physical turn is −180
  there; with edge 11 listed first the valley would need travel −180
  ([01 §5.6](01-architecture.md#56-travel-per-segment)) [py]. So the sign of
  travel depends on the raw sense **and** on which way up the first segment's
  stationary face lies, and v2's "one raw sense sets the sign of Flap's travel" was
  wrong. The fix stays in the library, where v2 wanted every way-up decision:
  `Origami.Flap` gains an entry taking a magnitude and a raw side,
  `prepareFlapToward :: [EdgeId] -> FaceId -> Double -> Toward -> Folded -> Either FlapError FlapMotion`
  with `data Toward = TowardRawPlusZ | TowardRawMinusZ` (**SKETCH**, 05 L14). It
  reads the first segment's stationary face normal from its placement and sets
  travel to +A when "towards +z" agrees with that normal's z sign, −A otherwise;
  a normal not ±ẑ within `isProperRotation`'s 1e-12 is refused as
  `FlapStationaryNotFlat`. The runner passes `TowardRawPlusZ` for a raw valley.

  | Raw sense | Stationary face shows its top | shows its back |
  | --- | --- | --- |
  | valley | +A (edge 9 in step 2) | −A (edge 11 in step 2) |
  | mountain | −A (edges 8, 10 in step 1) | +A (the crane wing's accepted `behind`) [reasoned] |
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
- **Residue.** `Rigid(..)` stays exported unchecked; a checked constructor is a
  follow-up ([§10](#10-corrections) item 19).

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
  `stepPageWith` over `noteFor arrows` (`inferNote` or `silentNote`), so its 23
  call lines in 15 files are untouched
  ([06](06-prd-step-diagrams.md#what-changing-the-api-would-cost)) [prd].
- **`StepError` is unchanged** ([C37](#changes-since-draft-v2)). It is a record of
  a frame index and a `FoldError`
  ([`Steps.hs:58-62`](../src/Senbazuru/Render/Steps.hs#L58-L62)) and the CLI takes
  it apart by pattern ([`Cli.hs:855-863`](../app/Senbazuru/Cli.hs#L855-L863))
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
  ([C36](#changes-since-draft-v2)). A fold-and-unfold draws its fold arrow, its
  unfold arrow and one fold-here line although its frames are identical.
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
  ([`CraneWing.hs:65`](../study/fold-material/CraneWing.hs#L65)) [code].
- **`AtRest`** writes every new piece at 0 with its requested assignment; cut
  pieces of old edges keep their parent's angle. On a frame with no
  `edges_foldAngle`, it writes the whole array, existing edges as `foldAnglesOf`
  reads them, new pieces 0 ([C30](#changes-since-draft-v2)); leaving it absent
  would fold the new valley to 180. `FlatForAssignment` is today's code path, so
  `creaseAllAlong = fmap fst . creaseAllAlongWith FlatForAssignment`.
- **Per-layer intent.** `creaseLayersThrough AtRest` still flips a requested
  valley to M on face-down layers
  ([`ThroughLayers.hs:338-339`](../src/Senbazuru/Origami/ThroughLayers.hs#L338-L339))
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
  ([`Flap.hs:187`](../src/Senbazuru/Origami/Flap.hs#L187)) [code], so such a fold
  is refused as `ExistingHingeFlat`.
- **Unselected layers get no crease.**
- **Evidence status.** The rule reproduces `CraneWing`'s faces `[2,3,6,7]` on
  `crane.fold` only in a Python re-implementation
  ([`research/scripts/layer-selection-analyse.py`](research/scripts/layer-selection-analyse.py));
  the first M4 PR must reproduce it in Haskell before anything relies on it.
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
  ([02 §8.2](02-language-semantics.md#82-collapse)) [prd]; on a square with both
  diagonals and both midlines precreased there are four, **UNVERIFIED**.
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
  from their documented formulas ([§10](#10-corrections) item 16).

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
  `PoseOnRoute` as `NoRoute` for `StateOnly`, `NoMotion` and `Presented`.
- **Records derive `Eq`, which needs a library change** ([C4](#changes-since-draft-v2)).
  `FlapMotion` and `CheckedFlap` derive only `Show`
  ([`Flap.hs:93`](../src/Senbazuru/Origami/Flap.hs#L93),
  [`:96`](../src/Senbazuru/Origami/Flap.hs#L96)), although every field type derives
  `Eq`: `Folded` ([`Folding.hs:324`](../src/Senbazuru/Origami/Folding.hs#L324)),
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
  every geometric output.
- **Rejected.** Filtering an enumerated list, which meets the per-component cap;
  reporting an exhausted budget as ambiguity.

### D12. The text syntax

The full EBNF, lexical table, reserved words and printer rules are owned by
[04](04-prd-sequence-source-and-cli.md#grammar); [§6](#6-grammar) points there.
The decisions:

- **Extension** `.foldseq`, a placeholder (`.fseq` is the xLights and Falcon Player
  format); first line `foldseq 1`, nothing before it (owner decision 1).
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
  `unfold NAME…`; `fold and unfold SENSE LINE [LAYERS] [moving P]` (alias
  `precrease`), which takes **no angle** because `FoldAndUnfold` has no field for
  one; `turn over`; `rotate`; `anchor P`; `mark`; `let`; the macros; `continue`;
  `together { … }`; `pose { … }`; `repeat NAME[..NAME] [mirrored across [P, Q] | turned k/4 about P]`;
  `checkpoint "path" { … }`; `not modelled "…"`; `expect refused KIND { move }`;
  and `settle { … }` last in a step.
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
- **Printer.** Canonical words (`valley`, `mountain`, `fold and unfold`, `°`,
  `moving P`, `top layer`); numbers as integers or `n/d` in lowest terms, except
  `rotate` and `turned` denominators, printed as stored; defaults left out.
- **Round trip.** QuickCheck:
  `isRight (checkSequence s) ==> fmap stripSpans (parseSequence "gen" (prettySequence s)) == Right (canonical s)`,
  covering every constructor with `checkCoverage`; goldens of printed sources and
  of error text; the Haskell blintz equals the parsed blintz with spans stripped.
- **Parser.** megaparsec 9.5.0 and parser-combinators 1.3.0, both in the pinned
  lts-22.44 snapshot, plus `transformers`, all in the library stanza. The versions
  were read from the snapshot file in Stack's pantry cache (appendix command 6)
  [py]; a stackage.org package page served LTS 24.59 and is not evidence.
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
  ([`Cli.hs:484-493`](../app/Senbazuru/Cli.hs#L484-L493)) [code]. A written
  sequence file's key frame has no vertices, so state k is `--frame k+1`, as
  `bird-base-sequence.fold`'s "frames 1–16 are the folding states"
  ([`usage.md:1017-1018`](../docs/usage.md)) [code]. `run -o x.glb --frame N`
  therefore writes the same bytes as `export` of `run`'s `.fold` at `--frame N`.
  `--frame 0` and out-of-range values are refused, naming the state count.
- **I/O.** `Fold.Load.readSequenceText :: FilePath -> IO (Either LoadError Text)`
  is the only reader of source bytes: strict UTF-8, a byte-order mark stripped,
  no `Sequence` import. `sheet` and `checkpoint` paths are relative to the source's
  directory (`Sequence.Syntax.sourceFiles`); the CLI loads each distinct path with
  `loadFile`, so `.cp` and `.opx` sheets work, and passes the pure runner a
  `Map FilePath Frame` keyed by the path as written.
- **`decodeFile` refuses a `.foldseq` path, and the library's words name no command**
  ([C25](#changes-since-draft-v2)). Today every unrecognised extension decodes as
  FOLD ([`Load.hs:102-106`](../src/Senbazuru/Fold/Load.hs#L102-L106)) [code], so a
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
  `Render.Gltf.ExportMode` ([`Gltf.hs:147`](../src/Senbazuru/Render/Gltf.hs#L147))
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
  and after; a re-anchoring fold changes placement while positions stay put. v2's
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
  accepting a 30° root and 0–20° extra, as `craneSpreadWith` does
  ([`CraneSpread.hs:82-83`](../study/fold-material/CraneSpread.hs#L82-L83)) [code];
  else `GripOutOfRange`. A generator also sets the start positions of free vertices
  on its side; other free vertices start at their side's `rigid-pose` target if
  one exists, else at `recordBefore` (R-07-16). A vertex whose targets differ by
  more than 1e-12 × `modelSpan` is `ConflictingTargets` (R-07-17).
- **Rest angles.** `RestAngles = RestAtPose PoseRef | RestAtPoseExcept PoseRef [(CreaseLine, Rational)]`, where a `CreaseLine` is written `crease [P, Q]`, `hinge of NAME` or `crease of NAME` inside `except { … }` ([04 grammar](04-prd-sequence-source-and-cli.md#grammar));
  every active crease rests at its angle in that pose; never derived from an
  assignment, so `CraneSpread`'s rule, −π for a mountain and +π otherwise
  ([`CraneSpread.hs:89-93`](../study/fold-material/CraneSpread.hs#L89-L93)) [code],
  is deleted when the crane is re-expressed. Rest comes from the settle, else the
  material block; neither is `SettleNoRest` (R-07-19).
- **`NoDifference` is computable** ([C39](#changes-since-draft-v2)): refused when the
  rest is `RestAtPose PoseBefore` with no exceptions and every target lies within
  1e-12 × `modelSpan` of `recordBefore`. A checked rigid state is already an
  equilibrium: the rigid 30° control ends with edge error 1.39e-11 and panel energy
  1.44e-27 ([07](07-prd-material-consumption.md#a-rigid-state-is-already-settled),
  from `docs/notes/spreading-connected-wing.md:35-39`) [research]. v2 also required
  "no released hold"; releasing a hold cannot move anything from an equilibrium
  start, so that clause tests nothing.
- **Stiffness.** A named preset; v1's `illustrative` is `Bending 1 0.2`, as
  `CraneSpread` builds its hinges ([`CraneSpread.hs:98`](../study/fold-material/CraneSpread.hs#L98))
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
  ([`CraneRoot.hs:72`](../study/fold-material/CraneRoot.hs#L72),
  [`CraneBody.hs:70`](../study/fold-material/CraneBody.hs#L70)) [code], which one
  global preset cannot say; `CraneInternal`'s force restriction and borrowed orders,
  `crossedGrip`'s offset and `WingBending`'s own mesh are also fixtures.
- **First M6 test.** The wing record's resolved pins equal `spreadPins` of
  `craneSpread source 3 20` (same ids, positions within 1e-12), without solving.
  **UNVERIFIED**: `hold band moving 0..1/32 at rigid-pose 1/3` giving the root-strip
  pins, and `arc-grip` giving the grip pins. **The slacks differ:** `CraneSpread`
  adds `1e-8` in its fraction units, 2.5e-9 sheet lengths on a 1/4-long wing, and
  the band adds 1.41e-9, so the test fails if a refined vertex lies between them.
- **Rejected.** A surface as the whole interface; two records per crease-and-turn
  move; state-rule surfaces with a separate intent field; settling from
  `recordAfter`; a default settle; rest from assignments or by `EdgeId`; holds by
  id; substituting rigid meshes or an external solver on failure.
- **Residue.** Few settles start flat (the wing's next move starts at 90°);
  per-spring controls stay fixtures; results move 3.95% between the two accepted
  crane meshes ([B](research/B-material-study-mechanics.md) "Capability table
  (question a)").

### D15. Graduation from study to library

**Staged and gated.** One PR per stage, in order; the 33 goldens and the study's
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

- **Gates.** #208's value-only line search lands before M6's crane equivalence PR
  (or that PR compares resolved pin sets without solving and solves once in the slow
  job) and before M8. `run --settle` refuses more than 1,192 refined triangles,
  counted before solving, until 3–5 compiled runs after #208 justify another
  number; default CI settles at most 392. The accepted crane-wing meshes solved in
  5.76 CPU s at 392 triangles and 64.30 CPU s at 1,192, one recorded run each
  ([07](07-prd-material-consumption.md#one-move-fed-by-hand)) [research].
- **Stays in the study:** `ContactQuadratic`, `CreasePairContact`, `CoupledCrease`,
  `UnequalCrease`, `CreaseInequality`; discovery, history and correction-sweep
  modes; barrier rows; `ClosedCrease`; `FoldMaterial`'s rounded bends; the `Crane*`
  and `Wing*` recipes and galleries; `PetalCertificate` and the certificate
  registry.
- **Rejected.** Graduating barrier rows no graduated solve uses; wall-clock settle
  limits.

### D16. Testing and acceptance

- **Every assertion names the change that turns it red.**
- **Tracked goldens stay byte-identical.** There are 33 (`git ls-files test/golden | wc -l`)
  [ran]. The check is two commands on the committed branch
  ([C53](#changes-since-draft-v2)):
  `git diff --name-only --diff-filter=MD origin/main...HEAD -- test/golden/` must
  print nothing, and `--diff-filter=A` lists the goldens a PR adds. Both print
  nothing today [ran]. v2's `git diff --name-only origin/main -- test/golden/`
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
  `angle + progress * travel` ([`Flap.hs:343`](../src/Senbazuru/Origami/Flap.hs#L343))
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
  ([`BlintzSequenceSpec.hs:110-115`](../test/BlintzSequenceSpec.hs#L110-L115)) [code].
- **Budgets are counted work**: sweep intervals (4096 cap), refolds, triangles,
  pairs, stacking guesses, settle triangles. Measured: a `stack test` run matching
  nothing took 19.03, 19.59 and 20.95 s of wall time building fixtures in `runIO`
  (3 runs, loaded M1 Max); `CraneWingSpec` took 1.21–1.25 s and `CheckedBirdSpec`
  12.50–12.52 s by hspec's own timer
  ([gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md)
  "Measured", "Addendum") [research]. No wall-clock guard is adopted.
- **Where tests run.** New sequence specs build fixtures in `beforeAll`; crane-sized
  fixtures sit under `describe "slow"`; the default job runs `--skip /slow/` and a
  new slow job `--match /slow/` (hspec 2.11.12 in the snapshot, appendix command 6
  [py]). Existing `runIO` specs stay as they are until their recipe's deletion PR
  ([C71](#changes-since-draft-v2)). A slow job is a fourth CI job beside today's
  `test`, `format` and `lint` ([`ci.yml`](../.github/workflows/ci.yml)) [code], and
  `AGENTS.md:378` requires "all three CI checks": owner decision 12 and
  [§3](#3-recorded-text-this-design-changes) row 15 ([C51](#changes-since-draft-v2)).
- **Angle equality.** Exact for driving parameters, copied literals, endpoints
  pinned by a guard, flap endpoints on whole-number angles, and two outputs of one
  binary; formula-derived angles within 1e-12°, as `RabbitEarSpec.hs:49` and
  `CheckedPetalSpec.hs:146` compare, until the tolerance issue names one. A sample
  is written as a driving-parameter value, never as a fraction, because
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

- **Running an external program and reading its output is not vendoring.** It
  needs a row in `docs/related-projects.md` giving the licence of the program *as
  built*, since a permissive source can link GPL code by default; provenance in
  `examples/README.md` for any output kept; and no CI job or test depending on it
  (the build, format and lint tools excepted). External solvers are comparison
  oracles, never ahead of the in-repo path, and the design-licence rule applies to
  any pattern fed to one. The wording goes to `AGENTS.md` at M0 (owner decision 11;
  [01 §4.8](01-architecture.md#48-agentsmd-third-party-material)).
- Origami Simulator (MIT): an oracle through #53, manual or browser-automated.
  ipc-toolkit (MIT): a library, not a simulator; a driver is a toolchain decision.
  Codim-IPC: Apache-2.0 source whose default build links GPL CHOLMOD; user-installed
  only, with `WITH_GPL=OFF` or Eigen. IPC-family tools cannot start from a
  zero-thickness flat stack without a thickness offset
  ([G](research/G-realistic-rendering-and-simulation.md) "B. Geometry models, and
  whether a sequence could feed them", finding 13), so they apply to open states
  only ([gap-study-consumption-contract](research/gap-study-consumption-contract.md)
  "(e) Licences for driving external solvers") [research].
- GPL sources (Doodle GPLv2, Rabbit Ear GPL-3.0, ReferenceFinder GPL-2.0, Creasy
  GPL-3.0, ORIPA GPL-3.0) are ideas only. Example sequences fold traditional or
  generated models only.

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
  new optional `Page.pageDescription`; default outputs and the 33 goldens carry
  none.
  - *Geometry:* rigid panels · bent zero-thickness (settled, [D14](#d14-material-consumption))
    · thickness offsets (research) · **as read**, for a file senbazuru did not
    produce ([C47](#changes-since-draft-v2)). `export --smooth` of an arbitrary file
    cannot know whether its panels are rigid (`puffed-square.fold` is a hand-made
    dome), so it must not claim either.
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
  ([`Projected.hs:123`](../src/Senbazuru/Render/Projected.hs#L123)) [code]; a band
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
    ([`Folding.hs:572-577`](../src/Senbazuru/Origami/Folding.hs#L572-L577)), and
    `Folding` insists on "one spanning walk and not two implementations of it that
    can drift" ([`:328-330`](../src/Senbazuru/Origami/Folding.hs#L328-L330)) [code].
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
    opposite quaternions has no defined direction.
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
  `sheetState`'s or the writer's refusals, and no step on `StaticRefused`.
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
  [`:195`](../src/Senbazuru/Origami/ThroughLayers.hs#L195)) [code]. That PR changes
  the sentence at `ThroughLayersSpec.hs:271-275` and the example at
  `docs/usage.md:866-872` ([§3](#3-recorded-text-this-design-changes) row 17), and
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
  `SignNotAllowed`) and `EmptyStep`, `UnfoldChangedSince`, `FlapStationaryNotFlat`
  are added.
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
  (`RefusalNotRaised` if accepted, `RefusedDifferently` if refused otherwise), leaves
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
  identity; in practice no earlier move of the step moved that paper. Otherwise
  `MoveLeavesFigure`, with a hint to start a new `step`. A `fold and unfold` pair
  counts as one move here. All four blintz corners in one step pass; "fold the
  corner to the centre, then fold that flap in half" fails.
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
  are all at 0 now is skipped, which covers every `fold and unfold`. If a later move
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
  | 4 | `Sequence.Record` | `RouteEvidence`, `MoveRecord`, `MacroBinding`, `recordPoseAt`, `Run`, `writtenStates`, `runRefusal`, `renderRunReport`; re-exports `RoutePose` |
  | 5 | `Sequence.Run` | `FoldState`, `sheetState`, `RunSettings`, `runSequence` |
  | 6 | `Sequence.Write`, `Sequence.RunPlan`, `Sequence.Material` | the file writer, the flag rules, the settle consumer |

- **`Run` is defined in `Sequence.Record`**, and it holds what a reader of a run
  needs: the start state (surface and display), every record, each step's outcome
  (name, caption, which records, authored samples, expected refusals), the closing
  caption and the stop, if any. **It does not hold `FoldState`.**
- **`writtenStates :: Run -> Either WriteProblem [WrittenState]`** applies the state
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
listed in [the changes table](#changes-since-draft-v2).

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
  | SheetRefused Span Text SheetProblem                          -- the sheet path as written
  | ResolveRefused Int (Maybe Name) Span Text ResolveProblem
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
  | NotAProperRotation Double
sourceLocation :: SequenceError -> Maybe Text
excerpt :: Text -> SequenceError -> Maybe Text

-- Senbazuru.Sequence.Parse / Pretty / Check / Elaborate
parseSequence :: FilePath -> Text -> Either SequenceError Sequence
prettySequence :: Sequence -> Text
checkSequence :: Sequence -> Either SequenceError Checked
elaborate :: Checked -> Elaborated

-- Senbazuru.Sequence.Record
data RouteEvidence = NoMotion | Presented | StateOnly | Sampled CheckedMacro SampleReport | SweptHinge CheckedFlap
data PoseRef = PoseBefore | PoseAfter | PoseOnRoute Rational
data PoseError = NoRoute RouteEvidence | PoseFlap FlapError | PoseMacro MacroError
recordPoseAt :: MoveRecord -> PoseRef -> Either PoseError RoutePose   -- RoutePose from Origami.Route
data MoveRecord = MoveRecord
  { recordStep :: !Int, recordMoveIndex :: !Int, recordSpan :: !Span, recordLabel :: !(Maybe Text)
  , recordPath :: ![Name], recordKind :: !MoveKind
  , recordBefore, recordAfter :: !(Surface V2)                   -- unpresented; one numbering
  , recordPresentation, recordPlacement :: !(Rigid, Rigid)       -- before, after
  , recordEvidence :: !RouteEvidence
  , recordHinge :: ![(MaterialSegment, [EdgeId])], recordMoving :: ![(MaterialPoint, [FaceId])]
  , recordStationary :: !(Maybe (MaterialPoint, FaceId))
  , recordNewCreases :: ![(MaterialSegment, [EdgeId], Assignment)]
  , recordAngles :: !([Double], [Double]), recordStacking :: !(Maybe StackingChoice)
  , recordAnchor :: !(MaterialPoint, MaterialPoint)               -- before, after
  , recordResolved :: ![ResolvedReference], recordMacros :: ![MacroBinding], recordCost :: !StepCost }
  deriving stock (Eq, Show)
displayBefore, displayAfter :: MoveRecord -> Rigid                -- presentation `after` placement
data MacroBinding = MacroBinding { bindLine :: Name, bindMacro :: MacroName, bindRoles :: [(Role, MaterialSegment)]
                                 , bindBranch :: Branch, bindDisambiguator :: Maybe ResolvedReference, bindReached :: Rational }
data Run = Run { runStart :: StateView, runSteps :: [StepOutcome], runRecords :: [MoveRecord]
               , runClosing :: Maybe Text, runStop :: Maybe (Int, Maybe Name, Text) }
writtenStates :: Run -> Either WriteProblem [WrittenState]
runRefusal :: Run -> Maybe SequenceError
renderRunReport :: Run -> [Text]

-- Senbazuru.Sequence.Run
data RunSettings = RunSettings { sweep :: SweepSettings, nearMissBand :: Rational, keyDensity :: Int
                               , keySubdivisionBudget :: Int, macroChecks :: Int }
data FoldState                                                   -- abstract
sheetState :: SheetStart -> Frame -> Either SheetProblem FoldState
runSequence :: Budget -> RunSettings -> Map FilePath Frame -> Elaborated -> Either SequenceError Run

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
isProperRotation :: Mat3 -> Bool; fitRigid :: [(V3, V3)] -> Maybe Rigid
flapStationaryFace :: CheckedFlap -> FaceId
flapPoseAt :: CheckedFlap -> Double -> Either FlapError RoutePose
data Toward = TowardRawPlusZ | TowardRawMinusZ                   -- L14, with Eq on FlapMotion and CheckedFlap
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
`fold and unfold` with no angle, `midpoint of edge S`, `stacking first` alone in its
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
[C41](#changes-since-draft-v2)):

```text
foldseq 1
title "Lower one crane wing"
sheet "examples/crane.fold"
anchor (19/20, 1/3)        # strictly inside face 0
start folded {
  layers (1/4, 1/5) above (3/8, 5/9)     # UNVERIFIED: must leave exactly the tail-tucked stacking
  layers (4/9, 3/8) above (1/4, 1/5)
}
material { stiffness illustrative }

step wing "Fold the underneath wing away from you until it stands straight out." {
  expect refused FlapCovered { fold in front 90° corner north-west to midpoint of edge north }   # UNVERIFIED kind
  fold behind 90° corner north-west to midpoint of edge north
  settle {
    refine side moving 3
    rest at rigid-pose 1/3
    hold closed side stationary
    hold band moving 0..1/32 at rigid-pose 1/3    # UNVERIFIED: equals CraneSpread's root-strip pins
    grip band moving 7/32.. arc-grip 30° 20°      # UNVERIFIED: equals CraneSpread's grip pins
  }
}
```

Facts ([02 §6.3](02-language-semantics.md#63-which-layers), check C and check P)
[prd]: the anchor and the three relation points each lie strictly inside one face
(0, 10, 27, 29); corner north-west is vertex 2 and the midpoint of edge north vertex
28, which the Python re-implementation folds to (1, 4.6e-14) and (1, 0.5), so the
line is folded y = 1/4, crossing 16 faces; the flap containing corner north-west is
faces 2, 3, 6 and 7, `CraneWing`'s hand-picked set. That flap and the sense rest on
Python, not senbazuru. **The valley at 90° being refused while the mountain is
accepted is not a sign slip:** wing A's first hinge segment's stationary face shows
its back, so its accepted `behind` is +90 in FOLD terms ([D5](#d5-presentation-and-the-readers-side)).

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
| M2 | Rigid runner on flat states and existing creases | `sheetState`; references on flat states; `fold`, `unfold`, `fold and unfold` along constructions on the flat sheet and along existing creases of flat-folded states; 05 L1 (`atRest`), L2 (`creaseAllAlongWith`), L3 (`fitRigid`, some-vertex classification), L4's `flapStationaryFace` and `Origami.Route`, L14 (`prepareFlapToward`, `Eq`); presentation; anchors; `Sequence.Record` with `writtenStates`; the writer; `run -o .fold`, `.glb`; `--report`; `expect refused`; `not modelled`; the bird arrows golden pinned before L3; blintz and helmet equivalence; quarter-fold test 1; E1–E6, E8–E10; rows 11, 12 (`runSequence`), 13 | closes #95, #97; advances #60; #58 item 3 |
| M3 | Step pages that read like a book | `StepNote`, `stepPageWith`, arrow heads, `Symbol`, captions, 05 L5 (`motionsAcross`, `creasesToCome`), steps of several moves, marks; `run -o .svg`; E7; row 12 (`stepPageWith`) | closes #36, #94; advances #48 |
| M4 | Folding some layers | 05 L6 (before the runner wraps `ThroughError`), L7–L12; selectors; `stackingWhere`; `start folded`, `checkpoint`, `repeat`; crane-wing prefix in the slow job; quarter-fold test 2 and its page; rows 15, 17, 18 | closes #60; advances #54; revisits #70; related #110 |
| M5 | Coupled macros | collapse with `keeping`, rabbit ear, petal, `continue`, `together`, `sample`, `pose`; 05 L13 (`CheckedMacro`, `macroPoseAt`); the study's certificate registry; bird route; crane opening | advances #54, #61; #55 unblocked, not required |
| M6 | Study consumes records | `Sequence.Material` in the study; `settle` and `material` blocks; settled illustrations and failure scope; crane spreading re-expressed, pin-set equivalence first; `senbazuru-material-study --sequence SOURCE DIR`; 05 L4's `flapPoseAt` here or at M7b, with its first consumer | advances #195; #114 rewritten |
| M7a | Realistic GLB mode on existing meshes | A1 normals, A2a texture coordinates, fidelity metadata, `Page.pageDescription`; shown on the crane-spread and wing-bending study meshes | first visible realism |
| M7b | Motion and lines | G1 animation (`SweptHinge` routes, `Sampled` after M5); 05 L15 (`foldedWalk`); W1 line drawing; `--lines`; glTF crease-line spike | closes #56; advances #104, #48 |
| M8 | Graduation | [D15](#d15-graduation-from-study-to-library)'s seven stages; `run --settle`; `--allow-unsettled` | gated on #208; #106 later |
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
- #208's value-only line search lands before M6's crane equivalence PR (or that PR
  solves nothing) and before M8.

## 9. Owner decisions

Numbered as every PRD's open questions cite them. Each has a recommended default,
and each has to be decided before the milestone named.

| # | Decision | Recommended default | If decided otherwise | Before |
| --- | --- | --- | --- | --- |
| 1 | File extension; the name "sequence source" | `.foldseq`, first line `foldseq 1` (`.fseq` is the xLights and Falcon Player format) | the extension, the first-line keyword, `decodeFile`'s refusal, error goldens and glossary rows change | M1's parser PR |
| 2 | `nearMissBand` | 1e-3 sheet lengths | smaller: a decimal near a vertex becomes a separate point and a crease sliver; larger: legitimate points refused. A `RunSettings` field, so no syntax change | M2 |
| 3 | A move carrying the anchor's face: re-anchor or refuse | re-anchor, printed by `--report` | refuse: authors write `anchor P` first, and animation needs no sub-hierarchy per re-anchor | M2 |
| 4 | A precrease's stiffness in a settle | an M or V crease at 0 settles as a crease spring resting at 0, weighted by length; a sheet file's `F` edges stay panel bends, weighted also by the two triangles' areas | as panel bends: turning concentrates differently, and M6's numbers change | M6 |
| 5 | SVG "wireframe": feature lines, or triangulation too | `--lines features` default; `--lines mesh` adds visible triangle edges | mesh default: every settled page draws its triangulation, and visibility runs on more segments | M7b |
| 6 | Textures (A2b): content and source | none; M7a ships normals and texture coordinates only | procedural: a PNG writer on `bytestring`, or `zlib`/`JuicyPixels` from lts-22.44; vendored: licence and provenance in `examples/README.md` | after M7a |
| 7 | Caption overlap and overflow | captioned pages get a gutter of at least 42/340 ≈ 0.124 of a figure, the bound at which 14-unit type clears on the default three-column page; uncaptioned pages unchanged; overflow across cells accepted and stated, since the backend has no font metrics | accept overlap: unreadable pages; squash or truncate: width estimates without metrics; refuse: some sequences cannot be drawn | M3 |
| 8 | Blintz direction: the recipe folds corners behind (−180), the study's manifest in front (+90 then +175) | the recipe's `fold behind`, so migration reuses `checked-blintz.svg` | both blintz sources switch to `fold in front` in one PR, and gallery output changes | M2's blintz PR |
| 9 | Whether `examples/quarter-fold-steps.fold` moves to the state rule | it stays as the regression; the state-rule page is a new golden | `quarter-fold-steps.svg` and `quarter-fold-step-1.svg` move in that PR, and their `test/fixtures` copy migrates too | M2 |
| 10 | Eighth turns by trigonometry, or a `sheet square as diamond` start | trigonometry, platform bits in written coordinates stated | `rotate` takes even k only, so frames stay exact; the crane-opening example's first step becomes a header option | M2 |
| 11 | The external-tools rule in `AGENTS.md` | yes, [§3](#3-recorded-text-this-design-changes) row 8 at M0 | only in `docs/related-projects.md`: agents reading `AGENTS.md` miss it | M0 |
| 12 | CI placement of crane-sized sequences; the slow job's status; triangle budgets | crane-sized sequences in a separate slow job that is a **required** check, so row 15 changes "all three CI checks" to four; default CI settles ≤ 392 triangles; `run --settle` refuses above 1,192 until 3–5 compiled runs after #208 | an optional slow job lets slow regressions merge; crane tests in default CI pay [D16](#d16-testing-and-acceptance)'s costs on every PR before #208 lands; a higher cap admits unmeasured settles | M4 |

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

Findings about the repository's own text and code, proposed as follow-ups; none is
filed yet. Items 1–26 keep v2's numbers; 27–32 are new. *Row* means a
[§3](#3-recorded-text-this-design-changes) row carries it; *issue* means M0 files a
new issue ([10 §7](10-roadmap-risks-questions.md#7-corrections-as-proposed-follow-up-issues)
writes each out).

| # | Finding | Evidence | Disposition |
| --- | --- | --- | --- |
| 1 | #95's half turn about x = 0 moves the model across the page and doubles the page width | [prd] [02 §5.2](02-language-semantics.md#52-presentation-moves-no-paper) | row 4 |
| 2 | #36's done-when 1 (a reflection is a turn-over) cannot be met, and one motion can change a V and an M crease together | [prd] quarter-fold step 2 | row 7 |
| 3 | #94's "nothing reads `frame_title`" is half stale (the CLI reads it for `info`, page and glTF titles); captions drawn by `render` would move goldens | [code] | row 7 |
| 4 | #114's premises are stale: `--thickness` and face lifting were removed, and a second rounded bend stretches 200% | [code] `docs/notes/paper-thickness.md`, `two-bends-need-more-than-radii.md:55` | row 7 |
| 5 | #56's "per-face transforms are discarded" is stale: `foldFrameWith` returns `foldedPlacements` | [code] [`Folding.hs:318-322`](../src/Senbazuru/Origami/Folding.hs#L318-L322) | row 7 |
| 6 | #104 cites `docs/notes/inflate-outside-draw-inside.md`, which does not exist, and its done-when lets two goldens change | [ls], issue text | row 7 |
| 7 | #60's done-when tests folding, not authoring; coordinates need a tolerance; "macro-moves are compositions" is false | [code] issue text read with `gh issue view 60` | row 3 |
| 8 | #96 says three papers and lists four | [web] [E1](research/E1-prior-art-sequence-languages.md) "D. The 2026 papers" | amend #96 with row 9 |
| 9 | `docs/related-projects.md`: Doodle is GPLv2, ReferenceFinder GPL-2.0, origami-diagrams moved to `amkraft/` and MIT only in `package.json` | [web] [E1](research/E1-prior-art-sequence-languages.md), [E2](research/E2-references-and-persistent-naming.md) | issue |
| 10 | `docs/notes/huzita-hatori.md`'s dates disagree with Alperin and Lang | [web] [E2](research/E2-references-and-persistent-naming.md) finding 11 | issue |
| 11 | `docs/glossary.md` defines rest angle twice, differently (`:19`, `:83`) | [code] | row 10 |
| 12 | `check` silently skips Maekawa at a vertex touching a `U` edge | [code] `FlatFold.hs:503-506`; [bin] | issue |
| 13 | `Creasing.existingAt` takes the first vertex within tolerance, not the nearest | [code] [`Creasing.hs:323-327`](../src/Senbazuru/Fold/Creasing.hs#L323-L327) | issue, before M2's resolver |
| 14 | `CraneWing` takes every `U` edge as its hinge, which works only because `crane.fold` has no `U` edge; its clip lacks `ThroughLayers`' guards | [code] [`CraneWing.hs:65`](../study/fold-material/CraneWing.hs#L65); [jq] 0 `U` edges | issue |
| 15 | The blintz manifest and recipe fold corners in opposite directions | [jq, code] | owner decision 8 |
| 16 | Manifest angle literals are not the documented formulas' `Double`s. Rabbit ear at m = 30: the stored `97.58514830800293` is one ulp from the `atan2` form. Petal at t = 175: the stored `-166.98236060695527` is **three** ulps from the code's own `atan2` expression ([`CheckedPetal.hs:107`](../study/fold-material/CheckedPetal.hs#L107)), which gives `…518`. v2 said one ulp for both ([C58](#changes-since-draft-v2)) | [py] appendix command 7 | issue, M5 |
| 17 | At least nine tolerance formulas act as "a hair" | [code] [gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md) finding 2 | issue, D2's prerequisite |
| 18 | `quarter-fold-steps.fold` writes M and V at angle 0 (4 creases on its key frame, 2 on its first state) | [jq] [10 §7.3](10-roadmap-risks-questions.md#73-settled-without-a-new-issue) | owner decision 9 |
| 19 | `Rigid(..)` and `Mat3(..)` are exported and nothing checks a proper rotation | [code] [`Rigid.hs:24-26`](../src/Senbazuru/Geometry/Rigid.hs#L24-L26) | issue, M2 |
| 20 | Any filtered `stack test` run pays 19–21 s of `runIO` fixture setup | [research] 3 runs | issue, before M1's specs |
| 21 | `creaseAllAlong` returns no new edge ids | [code] [`Creasing.hs:138`](../src/Senbazuru/Fold/Creasing.hs#L138) | 05 L2 |
| 22 | GLB `extras.senbazuru.frame` stores fold angles and material coordinates unrounded | [code] `Gltf.hs:241-242` | issue, M7a |
| 23 | #64's "inflating a body is outside the model" is overtaken by #106 and the README | [docs] | row 7 |
| 24 | `Origami.Step`'s header says a turn-over is a motion | [code] [`Step.hs:30-34`](../src/Senbazuru/Origami/Step.hs#L30-L34) | row 13 |
| 25 | The study viewer's paper colours disagree with `Diagram.Style`'s | [code] `viewer.html:168` | issue, M7a |
| 26 | `docs/notes/a-crease-is-a-hinge.md`'s "about 200 thicknesses" and 30–40° Mylar figures are not in the cited abstract | [web] [B](research/B-material-study-mechanics.md) "Unverified" | study-note issue, M0 |
| 27 | #104's first done-when bullet cannot be met: from `--view iso` no face of `puffed-square.fold` turns away | [py] appendix command 4; issue text | row 7 |
| 28 | `docs/roadmap.md` records the old order: #97 before #95 and #54, and #93, #96, #97 "only then" #95, #94, #36 | [code] `docs/roadmap.md:82-87`, `:368-373` | row 16 |
| 29 | `AGENTS.md:378` requires "all three CI checks"; a slow job makes that count wrong or leaves the job unrequired | [code]; `ci.yml` has `test`, `format`, `lint` | row 15, owner decision 12 |
| 30 | `README.md:213` and `docs/roadmap.md` item 2 call the vocabulary missing | [ran] `grep -n` | row 18 |
| 31 | A library message names CLI flags: `LineStopsOnTheModel` starts with `creaseEndFlag`'s `--from`/`--to` | [code] [`ThroughLayers.hs:195`](../src/Senbazuru/Origami/ThroughLayers.hs#L195), [`Query.hs:68-71`](../src/Senbazuru/Fold/Query.hs#L68-L71) | issue, before M4; row 17 |
| 32 | The research note's count line says 7 of the crane's 12 some-layer steps hinge on existing creases; its own table marks 6 | [research] [gap-layer-selective-folds](research/gap-layer-selective-folds.md) "(e) The traditional crane, step by step" | recorded here; the note is a snapshot and is not edited |

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
  [Changes since draft v2](#changes-since-draft-v2); owner decisions 7 and 12 take
  §9's defaults.
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
  at M4; §6 takes §9's defaults for 7 and 12.
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
| C4 | `FlapMotion` and `CheckedFlap` derive `Eq` (05 L14) | 01 §2.2 note | `Flap.hs:93`, `:96`; field types' derivings at `Folding.hs:324`, `HingeSweep.hs:89`, `:101`, `Surface.hs:123`, `Rigid.hs:80` [code] | adopted | 01, 05 |
| C5 | The hinge turn takes a raw side; `Flap` sets the first segment's sign from its stationary face (`prepareFlapToward`, `FlapStationaryNotFlat`) | 02 §5.3 note; 01 §5.5 note | `Flap.hs:10-16`, `:201-216` [code]; edge 9 +180, edge 11 −180 [prd] | adopted-modified | 01, 02, 05 |
| C6 | Two settle error types: `SettleStepError` wraps `Material.Settle`'s `SettleError` | 07 "SettleSpec and SettleInput" note | layer rule: `Material.*` knows no moves (§2) | adopted | 01, 02, 07 |
| C7 | `closing` is written after the last step, stored as `hClosing` | 04 ambiguity table | 04 grammar `source` production | adopted | 02, 03, 04 |
| C8 | `expect refused` is a move inside a step, produces no record and no state, and is kept in the `Run` | 02 §6.1, §9; 04 ambiguity table; 06 §2; 09 E10; 02 G12 | v2 D10 has no refusal constructor; `BlintzSequenceSpec.hs:110-115` [code] | adopted-modified | 02, 04, 06, 09 |
| C9 | The crane example expects `FlapCovered`, **UNVERIFIED** | 02 §9 | selection rule order (D8); finding 14 is inferred [research] | adopted | 04, 07 |
| C10 | A `not modelled` stop returns `Right` a `Run` with `runStop`; `runRefusal` gives the CLI its error | 04 R-04-28, A18; 09 M2 (g) | v2 D21 text against its `Either SequenceError Run` type | adopted-modified | 02, 04, 09 |
| C11 | `SequenceError` gains `SheetRefused` and `WriteRefused`; `StaticRefused` carries a `Place` | 02 §14 G14; 03 "Refusals from a built sequence" | v2 §5 errors sketch | adopted | 02, 03, 04 |
| C12 | `together` is one record with `recordMacros :: [MacroBinding]`, each naming its line | here (02 §8.4, §8.5) | v2 `recordMacro :: Maybe MacroBinding`; bird press step | adopted-modified | 02, 05, 07 |
| C13 | Tree refinements: `MidpointOfEdge`, `StackingSpec`, `Located` header fields and `together` members | 04 ambiguity table | v2 grammar `midpoint of edge north` in its crane example | adopted | 02, 03, 04 |
| C14 | No move outside a step; the diamond start is a first step | here | v2 §7 crane opening and crane wing examples against v2 §6 grammar | adopted | 04, 09 |
| C15 | Optional captions; `fold and unfold` takes no angle; string escapes; `n/0` a parse error; reserved words never names | 04 lexical and ambiguity tables; 03 note | v2 grammar allowed a precrease angle | adopted | 02, 03, 04 |
| C16 | Batching stays inside one step; corrected example | here (02 §6.5) | v2 D22 lines 939-940 contradict themselves | adopted-modified | 02, 05 |
| C17 | Intent at start: F beyond τ becomes M or V; U stays U | 02 §2.2 note | `StudyCase.hs:208`, `Flap.hs:187` [code] | adopted | 02, glossary-additions |
| C18 | `checkpoint` reads angles by `foldAnglesOf`, as `start folded` does | here | `Folding.hs:507-533` [code]; v2 D21 | adopted-modified | 02 |
| C19 | An anchor a new crease passes through moves to the largest unturned piece; 02's claim that the authoring test hits it is removed | 02 §14 G1 | 09 §2.3 writes `anchor (3/4, 1/4)` [prd] | adopted-modified | 02, 09 |
| C20 | The default anchor is a vertex mean, not a centroid | 02 §2.3 note | `StudyCase.hs:242-248` [code] | adopted | 02, glossary-additions |
| C21 | G2–G13 decided: moving side of O5–O7 (G2); `turned` direction and `white side up` axis (G3); repeat compares hinge turns (G4); `UnfoldChangedSince` (G5); lockstep (G6); weakest order and `NoMotion` for `anchor`, `mark` (G7); folded positions in material slots (G8); macro landing with several stackings refused (G9); sample range (G10); compass names need a square outline (G11); `expect refused`-only steps (G12); default anchor outside its face (G13) | 02 §14 | blintz quarter-turn image [py]; `crane.fold` corners 5.8e-15 off [prd] | adopted (G4, G7, G11 modified) | 02 |
| C22 | A step's body has its own type, `Moves` | 03 note; owner question 4 | v2 `step :: … -> Build () -> …` | adopted | 03 |
| C23 | Syntax constructors renamed `ValleyFold`, `MountainFold`, `LayerAbove`; lowercase builders; `SettleRegion` | 03 note; owner question 5 | `Types.hs:302-305`, `:334-336`; `Visible.hs:103` [code] | adopted-modified | 02, 03, 04, 07 |
| C24 | `canonical` normaliser in the round-trip property | 04 "Canonical form" | 04's four-row table | adopted | 03, 04 |
| C25 | `decodeFile`'s message names no command; `app/` adds the `run` hint | 04 §"Reading a source" note | `Load.hs:102-106`, `Query.hs:68-71` [code] | adopted-modified | 04 |
| C26 | Presentation change: *some* vertex moves (R-05-12′) | 05 L3 note; 01 §4.13 note | 3 of 9, 3 of 9, 5 of 13, 2 of 8 axis vertices; 0 of 15 and 0 of 2 rigid pairs [py] | adopted | 01, 05 |
| C27 | `creaseAllAlongWith` at M2 | 05 L2; 10 §2 note | `Creasing.hs:138`, `:290-292`, `:316-320`; `CraneWing.hs:65` [code] | adopted | 05, 10 |
| C28 | `RoutePose` in `Origami.Route`, re-exported by `Sequence.Record` | 05 L4 note | layer rows 4 and 6 | adopted | 05 |
| C29 | τ = 1e-10 degrees | 05 L1 | `Surface.hs:278`, `StudyCase.hs:208` [code] | adopted | 05 |
| C30 | `AtRest` writes the whole angle array when a frame has none | 05 R-05-8 | `Folding.hs:507-533` [code] | adopted | 05 |
| C31 | `RequestRefused` wraps refusals only in batches of two or more | 05 R-05-30 | 05's `ThroughLayersSpec` cases [prd] | adopted | 05 |
| C32 | Library `StackingError` holds face-id relation errors; `StackingChoiceError` holds the counting policy | here (05 L12 against 02 §12) | `Stacking.hs:386-400` [code] | adopted-modified | 02, 05 |
| C33 | `StepNote` carries marks | 06 §1 | v2 D7 field list lacks marks while M3 includes them | adopted | 06 |
| C34 | A turn-over axis projecting to a point draws its loop as if page-vertical | 06 §5 | `withArrows`' 1e-6 cut-off [prd] | adopted | 06 |
| C35 | `render --steps` never draws `frame_title`; #94 closes at M3 through `run -o .svg` | 06 §9 | #94 done-when read with `gh issue view 94` [ran] | adopted | 01, 06, 10 |
| C36 | `GivenArrows` per connected moving group | 06 R-06-16 | `Step.hs:175-192` [code] | adopted | 06 |
| C37 | `StepError` unchanged | 06 R-06-3 | `Steps.hs:58-62`, `Cli.hs:855-863` [code] | adopted | 06 |
| C38 | Authored samples are states and figures without caption or arrows; checking adds `RunSettings.macroChecks` interior poses | 06 §2; 03 A-6 | v2 D9 ties evidence to illustration | adopted-modified | 02, 05, 06 |
| C39 | `NoDifference` without the "released hold" clause | 07 note | rigid control 1.39e-11 / 1.44e-27 [research] | adopted | 07 |
| C40 | Controls the vocabulary cannot name stay fixtures | 07 control table | `CraneRoot.hs:72`, `CraneBody.hs:70` [code] | adopted | 07 |
| C41 | `refine REGION INTEGER` and a `rest` line in the crane settle | 07 note under the crane block | control 2 needs a region; R-07-19 | adopted | 04, 07 |
| C42 | 07's proposed rules R-07-10, -13, -16, -17, -19, -22, -29 | 07 "Points this file adds" | each against v2 D14 | adopted | 07 |
| C43 | Silhouettes from edges of any assignment; #104's done-when names `--view front` | 08 R-08-17, "#104, amended" | 27 silhouettes front, 0 iso [py]; 40 `B`, 280 `F` [jq]; #104 text [ran] | adopted | 01, 08 |
| C44 | One animation hierarchy per checkpoint interval; `StateOnly` transitions switch sub-hierarchies; complete scene | 08 R-08-24, -27, -30 | `checkpoint` breaks the prefix rule (D6) | adopted | 08 |
| C45 | `Origami.Folding` exports its walk's tree (05 L15) | 08 Dependencies | `Folding.hs:572-577`, `:328-330` [code] | adopted | 05, 08 |
| C46 | Records keep presentation and anchor placement, before and after | 06 Dependencies | v2 single `recordDisplay` | adopted-modified | 01, 02, 06, 08 |
| C47 | Geometry level "as read"; W1's edge-on threshold 1e-9 | 08 Design | `Projected.hs:123` [code] | adopted | 08 |
| C48 | Test 2 matching rules T1–T5 | 09 §2.3 note | hand-built frames: v2 clauses false, T1–T2 true [py] | adopted | 01, 09 |
| C49 | Test 2 lands with the later of M3 and M4 | 09 §2.3 note | step 2 creases two layers (L8, M4); page needs L5 (M3) | adopted | 09, 10 |
| C50 | Recipe goldens rebuilt from records through `flapAt` | 09 §9 note | `BlintzSequence.hs:75-87`, `HelmetSequence.hs:70-86` [code] | adopted | 09 |
| C51 | A slow job and "all three CI checks": row 15 and owner decision 12 | 09 §6.3 note | `AGENTS.md:378`; `ci.yml` jobs [code] | adopted-modified (owner decision with default) | 09, 10 |
| C52 | Test 1 compares angles exactly | 09 §2.2 note | `Flap.hs:343` [code] | adopted | 09 |
| C53 | Golden check with `--diff-filter` and three dots | 09 §1.2 | both commands print nothing [ran] | adopted | 06, 08, 09 |
| C54 | #60 closes at M4 | here (10 §4 note said M3) | 09 §2.3's milestone | adopted-modified | 10 |
| C55 | #54 advanced, not closed; #96 amended at M0 | 10 §4 | issue checklists per 10 [prd] | adopted | 10 |
| C56 | `docs/roadmap.md` order passages as row 16 | 10 §3 | `docs/roadmap.md:82-87`, `:368-373` [code] | adopted | 01, 10 |
| C57 | Caption overlap: recommended gutter ≥ 42/340 on captioned pages | 06 open question 7; 10 §6 | 06 §8 arithmetic [prd] | adopted-modified (owner decision 7 with default) | 06, 10 |
| C58 | The petal literal is three ulps from the code's `atan2` form | 10 §7.2 item 16 | `CheckedPetal.hs:107` [code]; [py] | adopted | 10 |
| C59 | States numbered from 0 as `file_frames` index; `--frame k+1` | here (01/06/09 against 02) | `Types.hs:209-210`, `Cli.hs:484-493`, `usage.md:1017-1018` [code] | adopted-modified | 01, 02, 04, 06, 09 |
| C60 | "Anchor placement", "move record"; "step record" retired | glossary-additions; v2 D3 | `grep` of "step record" [ran] | adopted | glossary-additions |
| C61 | Pose angles converted once for the whole model | 02 §8.6 note | quarter-fold half-way pose [prd] | adopted | 02 |
| C62 | `Sequence.RunPlan` holds its own option types | here (04 `Plan`) | `Camera.hs:188`, `Gltf.hs:147` [code] | adopted-modified | 04 |
| C63 | Glossary *Sequence file* counts state 0 | 03 A-6 note | 02 §11 layout | adopted | glossary-additions |
| C64 | Row 14's range is `docs/architecture.md:202-211` | 01 §4.14 | `grep -n` [ran] | adopted | 10 |
| C65 | Row 12 lands in two PRs (`runSequence` at M2, `stepPageWith` at M3) | 01 §4.12; 10 §3 | `stepPageWith` takes a `Budget` | adopted | 01, 10 |
| C66 | The `LineStopsOnTheModel` sentence as row 17 | 10 §3 | `ThroughLayers.hs:195` [code] | adopted | 01, 10 |
| C67 | Existing library messages keep bare ids in v1 | 05 open question | pinned sentences in specs and docs [prd] | adopted-modified (decided, follow-up issue) | 05 |
| C68 | A record's seed for `L1 to L2` is the vertex mean of the face beside L1's longest segment | here (01 §5.8 left it to 02) | (1/4, 3/4) on quarter-fold step 2 [py] | adopted-modified | 01, 02 |
| C69 | An existing `F` hinge is refused as `ExistingHingeFlat`, with residue | 02 §6.2 | `Flap.hs:187` [code] | adopted | 02 |
| C70 | `bird-base-sequence-arrows.svg` pinned before 05 L3 | 09 §1.3; open question 7 | no golden draws that file with arrows (`BirdSequenceSpec.hs:79` passes `False`) [prd] | adopted | 09 |
| C71 | Existing `runIO` specs unchanged until their deletion PRs | 09 open question 6 | 14 spec files use `runIO` [prd] | adopted | 09 |
| C72 | The crane's existing-crease count is 6 (the research note's count line says 7) | 02 §6.2 | the note's table [research] | adopted | 02 |
| C73 | A step with no move other than `let` is refused as `EmptyStep` | here | 04 grammar allows an empty block | adopted | 02, 04 |
| C74 | `README.md` and `docs/roadmap.md` roadmap item 2 as row 18 | 10 §4 note | `README.md:213` [ran] | adopted | 01, 10 |

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
| One raw sense sets the sign of `Flap`'s travel | v2 D5 | The sign also depends on which way up the first segment's stationary face lies ([D5](#d5-presentation-and-the-readers-side)) |
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

Run from the repository root on 2026-09-15 at `568dcb6`. Outputs are abbreviated to
what this record cites.

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
    `docs/architecture.md` gives lines 202, 211 and 212; `grep -n "vocabulary\|#60" README.md`
    gives line 213; `grep -n creaseEndFlag src/Senbazuru/Origami/ThroughLayers.hs`
    gives lines 96 and 195; `find src -path '*Internal*'` prints nothing;
    `grep -rn "step record" PRDs/*.md` finds four rows of `glossary-additions.md`.
12. **Issues.** `gh issue view N --json title,state,body` for #60, #94 and #104; all
    open.
