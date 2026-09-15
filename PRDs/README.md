# Fold sequences: research and PRDs

**Status.** Research and requirements only, dated 2026-09-14 against commit
`568dcb6`. Nothing is implemented. The decision record,
[decisions.md](decisions.md), and several files were written or re-checked on
2026-09-15 at the same commit. Nothing under `PRDs/` edits any other file.

## The answer

The request had three parts:

1. a Haskell library for writing *fold sequences*, the moves that fold a sheet
   into a model;
2. a `senbazuru` verb that reads the same sequences from a file;
3. the *material study*, `study/fold-material/`, turning what either one defines
   into realistic glTF and SVG output. The study is an experimental program that
   bends folded paper as a thin elastic sheet, and glTF is the 3D format `export`
   writes ([glossary](../docs/glossary.md#this-project)).

**Today.** The library folds, checks and draws one state at a time, and checks
one turn of paper about a line; it cannot be told a sequence. The only code that
performs moves in order is the study's hand-written recipes, which come in four
forms ([decisions §1](decisions.md#1-the-two-halves-today-and-what-connecting-them-means)).
The blintz recipe ([blintz](glossary-additions.md#origami): a square's four
corners folded to its centre) is five tuples of a caption, an edge id, a face id
and an angle change
([`BlintzSequence.hs:50-56`](../study/fold-material/BlintzSequence.hs#L50-L56)).
Those ids change whenever a *crease*, a line the paper bends along, is added
([00](00-overview.md#the-problem-in-one-example)).

**The design.** Connecting the library and the study takes three new pieces, and
two of them are *contracts*, boundaries between separately owned code
([decisions §1](decisions.md#1-the-two-halves-today-and-what-connecting-them-means);
[01 §2](01-architecture.md#2-what-crosses-the-boundaries)):

1. **The `Sequence` value.** A sequence is a list of *steps*, each one picture in
   an instruction book, and a step holds one or more *moves*. Haskell code builds
   it in a `do` block, and a `.foldseq` file parses to the same value. Either way,
   paper is named by where it lay on the unfolded sheet (`corner south-east`),
   never by an id. Both front ends share this value, so it is not numbered as a
   contract.
2. **Contract 1, the move record.** A pure *runner* performs the moves, using the
   library's existing checking code plus fifteen small additions, and returns one
   [move record](glossary-additions.md#running-a-sequence) per move.
3. **Contract 2, the settle input.** The material study takes one record, never a
   file, resolves the points an author holds still and moves against it, and hands
   its solver the result.

The records produce four outputs:

- a multi-frame FOLD file, the JSON format senbazuru reads
  ([glossary](../docs/glossary.md#the-fold-format));
- a page of step figures;
- a GLB, glTF's binary form;
- in the study, bent *settled* illustrations.

**Realism.** For folds of flat panels, "realistic" adds motion, texture
coordinates and lines, not bent paper. The `senbazuru` command makes no bent paper
before milestone M8; until then it comes from the study
([00](00-overview.md#what-realistic-means-honestly)).

## Reading order

| File | Read it for |
| --- | --- |
| [Decisions](decisions.md) | The decision record, D1–D24: what was decided, why, and what was rejected. Where a file and the record disagree, the record wins |
| [00 Overview](00-overview.md) | The fold solver and the material study today; goals, non-goals, the pipeline, what each milestone lets you run |
| [01 Architecture](01-architecture.md) | Module layers, levels inside `Sequence.*`, the two contracts, stated exceptions, every recorded-text change, one fold traced with real numbers |
| [02 Language semantics](02-language-semantics.md) | The specification both front ends share, down to the refusal catalogue |
| [03 Embedded DSL](03-prd-embedded-dsl.md) | Feature 1: the `Build` monad, typed references, loops, GHCi |
| [04 Sequence source and `run`](04-prd-sequence-source-and-cli.md) | Feature 2: grammar, printer, error display, the `run` verb, checked examples |
| [05 Library additions](05-prd-library-additions.md) | The fifteen fold-solver additions L1–L15, none changing an existing output |
| [06 Step diagrams](06-prd-step-diagrams.md) | Step notes, arrow kinds, turn-over marks, captions; which *goldens* (checked-in outputs compared byte for byte) may move |
| [07 Material consumption](07-prd-material-consumption.md) | Feature 3a: `settle` blocks, holds and grips, rest angles, moving the solver into the library |
| [08 Realistic rendering](08-prd-realistic-rendering.md) | Feature 3b: fidelity axes, a smooth-shaded GLB mode, animation, an exact line drawing |
| [09 Testing and acceptance](09-testing-and-acceptance.md) | Acceptance per milestone, the quarter-fold tests, end-to-end tests, budgets |
| [10 Roadmap, risks, questions](10-roadmap-risks-questions.md) | Milestones and order, issue mapping, risks, owner decisions, corrections to file |
| [glossary-additions](glossary-additions.md) | The one copy of every new term; keep it open beside the rest |
| [research/](research/README.md) | The evidence the PRDs cite |

## The design in ten points

1. **One value; a step is a figure of moves**
   ([D1](decisions.md#d1-one-first-order-syntax-tree-built-by-name-only-builders)).
   `Sequence` holds no functions, so it can be compared, printed and saved. The
   builder's binds return names, never geometry.
   [01 §2.1](01-architecture.md#21-the-sequence-value),
   [03](03-prd-embedded-dsl.md#what-a-bind-returns-names-never-geometry).
2. **Material names, resolved by slot**
   ([D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot)).
   - A [sheet compass](glossary-additions.md#references) names the unfolded sheet's
     corners and edges.
   - Coordinates are exact fractions of the sheet's larger side.
   - Fold lines come from the
     [Huzita–Hatori operations](glossary-additions.md#references), the standard
     constructions of a fold line.
   - A point resolves by the slot it fills (position, region or vertex), never by
     how it is spelled.

   [02 §3](02-language-semantics.md#3-numbers),
   [02 §4](02-language-semantics.md#4-references).
3. **The runner owns the state**
   ([D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs)).
   `Sequence.Run` is pure. It refolds from angles after every move, never patches a
   folded result, and *join-checks* each step to show the paper neither tore nor
   drifted. The paper held still is the *anchor*; by default, when a move carries
   the anchor, the runner picks a new one.
   [02 §2](02-language-semantics.md#2-the-state-a-run-threads); traced in
   [01 §5](01-architecture.md#5-one-move-end-to-end-quarter-fold-step-2).
4. **The state rule**
   ([D4](decisions.md#d4-written-frames-follow-the-state-rule)). A *fold angle* is
   0 when flat, negative for a *mountain* and positive for a *valley*
   ([glossary](../docs/glossary.md#origami)). Written *frames*, the states in the
   output file, label each crease by its current angle. Whether a crease was made
   as a mountain or a valley survives as its *intent* in records, never in the
   file.
   [02 §11](02-language-semantics.md#11-written-frames),
   [05 L1](05-prd-library-additions.md#l1-at-rest-foldqueryatrest-and-assignmentatrest).
5. **Presentation and the reader's side**
   ([D5](decisions.md#d5-presentation-and-the-readers-side)). `turn over` and
   `rotate` move no paper; they turn the model about its own bounding-box centre.
   Valley, mountain and "top layers" are read from the *reader's side*, which is
   part of the fold state. So no render flag changes what a step means. **One
   valley can write +180 on one crease and −180 on another, and that is not a
   typo:** the sign of a turn also depends on which way up the still paper beside
   each crease lies, so the library takes a side, not a signed angle.
   [02 §5](02-language-semantics.md#5-the-readers-side-and-presentation),
   [05 L14](05-prd-library-additions.md#l14-eq-on-flap-values-and-prepareflaptoward).
6. **Folding some layers** ([D8](decisions.md#d8-folding-some-layers)). `P to Q`,
   the fold laying P onto Q, moves the
   [flap](glossary-additions.md#words-the-prds-narrow) containing P: the paper
   still joined to P once the model is cut along the fold line. `top N layers`
   counts from the reader's side. One batched addition creases only the selected
   faces. The rule rests on a Python re-implementation until M4 reproduces it in
   Haskell. [02 §6.3](02-language-semantics.md#63-which-layers),
   [05 L8](05-prd-library-additions.md#l8-creaselayersthrough).
7. **Macro-moves** ([D9](decisions.md#d9-macro-moves-as-named-angle-relations)).
   `collapse`, `rabbit-ear` and `petal` turn several creases at tied rates. Each
   follows one closed-form angle relation, and its
   [signature](glossary-additions.md#macro-moves), the creases it needs at a
   vertex, must match exactly once. The binding is pinned so that `continue`
   resumes it. Anything else is written `not modelled "…"`.
   [02 §8](02-language-semantics.md#8-macro-moves),
   [05 L13](05-prd-library-additions.md#l13-origamimacro-checkedmacro-and-macroposeat).
8. **Records and assurance** ([D10](decisions.md#d10-assurance-as-evidence-values),
   [D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)). There is one
   `MoveRecord` per move. Its geometry has neither presentation nor
   [anchor placement](glossary-additions.md#running-a-sequence) applied; it keeps
   both, before and after the move, as separate fields, and every id in it uses
   the before-state's numbering. What was checked is a value: a whole turn about
   one line, sampled poses, the end state only, presentation only, or nothing
   moved. `expect refused` produces no record. The file writer and the page read
   one list of written states, so the page draws exactly the frames the file
   holds.
   [01 §2.2](01-architecture.md#22-contract-1-moverecord),
   [01 §1.3](01-architecture.md#13-levels-inside-sequence),
   [02 §10](02-language-semantics.md#10-assurance).
9. **Illustrations, not state** ([D14](decisions.md#d14-material-consumption)). A
   `settle { … }` block bends one step, starting from its flat before-state.
   *Holds* (points fixed) and *grips* (points moved) are named against the record,
   and the block must say what differs from the rigid result. Its files feed no
   later step, page or animation. It runs in the study at M6 and in the library at
   M8.
   [07](07-prd-material-consumption.md#settled-output-is-an-illustration),
   [01 §2.3](01-architecture.md#23-contract-2-the-settle-input).
10. **Realism, stated honestly** ([D19](decisions.md#d19-realistic-rendering)).
    New outputs record where they sit on geometry, motion, appearance and lines.
    For flat panels, M7 adds animation, texture coordinates and perhaps glTF crease
    lines, not bent-looking paper.
    [08 axes](08-prd-realistic-rendering.md#the-four-axes-and-where-they-are-written),
    [08 honesty](08-prd-realistic-rendering.md#what-this-makes-realistic-and-what-it-does-not).

## Decisions D1–D24

[decisions.md](decisions.md) is the decision record every file here is written
against, version 3, dated 2026-09-15. "Dn" in any file means the decision below;
the D column links to its section in the record, and *Owner* is the file that
works it out in full.

| D | Decision | Owner |
| --- | --- | --- |
| [D1](decisions.md#d1-one-first-order-syntax-tree-built-by-name-only-builders) | One first-order syntax tree; a step is a figure holding moves; the builder hands out names only | [03](03-prd-embedded-dsl.md), [01 §2.1](01-architecture.md#21-the-sequence-value) |
| [D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot) | References are named on the sheet, resolved by slot, evaluated where the paper is now | [02 §4](02-language-semantics.md#4-references) |
| [D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs) | The runner owns the state, its start, the anchor and seven handoff invariants | [02 §2](02-language-semantics.md#2-the-state-a-run-threads) |
| [D4](decisions.md#d4-written-frames-follow-the-state-rule) | Written frames follow the state rule, in a stated layout | [02 §11](02-language-semantics.md#11-written-frames) |
| [D5](decisions.md#d5-presentation-and-the-readers-side) | Presentation moves no paper; the reader's side belongs to the fold state, never a camera; a hinge turn takes a side | [02 §5](02-language-semantics.md#5-the-readers-side-and-presentation) |
| [D6](decisions.md#d6-crease-graphs-grow-between-frames) | Crease graphs grow between frames, matched by material identity | [05 L5](05-prd-library-additions.md#l5-motionsacross-creasestocome-and-a-non-convex-point-test) |
| [D7](decisions.md#d7-a-typed-step-note-reaches-the-page) | A typed step note reaches the page; default notes keep today's bytes | [06 §1](06-prd-step-diagrams.md#1-the-channel) |
| [D8](decisions.md#d8-folding-some-layers) | Folding some layers, with a small batched library addition | [02 §6.3](02-language-semantics.md#63-which-layers) |
| [D9](decisions.md#d9-macro-moves-as-named-angle-relations) | Macro-moves: named angle relations with signatures and pinned bindings | [02 §8](02-language-semantics.md#8-macro-moves) |
| [D10](decisions.md#d10-assurance-as-evidence-values) | Assurance as evidence values, with functions giving poses along a checked route | [02 §10](02-language-semantics.md#10-assurance) |
| [D11](decisions.md#d11-stacking-choices-are-relations) | A *stacking*, one complete layer order, is chosen by relations solved in `Origami.Stacking` within a budget | [02 §7](02-language-semantics.md#7-stacking-relations) |
| [D12](decisions.md#d12-the-text-syntax) | Text syntax: `foldseq 1`, braces, exact numbers, megaparsec, print-then-parse round trip | [04](04-prd-sequence-source-and-cli.md#grammar) |
| [D13](decisions.md#d13-the-run-verb-and-io) | CLI: `run`, output chosen by `-o` extension, `Fold.Load` the only reader | [04](04-prd-sequence-source-and-cli.md#the-run-verb) |
| [D14](decisions.md#d14-material-consumption) | Material consumption: records in, illustrations out | [07](07-prd-material-consumption.md) |
| [D15](decisions.md#d15-graduation-from-study-to-library) | Graduation from study to library, staged and gated | [07](07-prd-material-consumption.md#graduation-staged-and-gated) |
| [D16](decisions.md#d16-testing-and-acceptance) | Testing and acceptance | [09](09-testing-and-acceptance.md) |
| [D17](decisions.md#d17-third-party-and-external-tools) | Running external tools is not vendoring; GPL sources are ideas only | [07](07-prd-material-consumption.md#external-tools) |
| [D18](decisions.md#d18-non-goals) | Non-goals | [00](00-overview.md#non-goals) |
| [D19](decisions.md#d19-realistic-rendering) | Realistic rendering: independent axes, honest milestones | [08](08-prd-realistic-rendering.md) |
| [D20](decisions.md#d20-errors) | Errors: an `Explain` instance per type; locations and command-line words kept out of library messages | [02 §12](02-language-semantics.md#12-refusal-catalogue), [04](04-prd-sequence-source-and-cli.md#error-display) |
| [D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused) | `repeat`, `checkpoint`, `not modelled`, `expect refused` | [02 §9](02-language-semantics.md#9-repeat-checkpoint-not-modelled-expect-refused) |
| [D22](decisions.md#d22-figures-holding-several-moves) | Figures holding several moves | [02 §6.5](02-language-semantics.md#65-figures-holding-several-moves) |
| [D23](decisions.md#d23-the-sequence-modules-and-where-run-lives) | `Sequence.*` sits on six levels; `Run` lives in `Sequence.Record` without the runner's working state | [01 §1.3](01-architecture.md#13-levels-inside-sequence) |
| [D24](decisions.md#d24-states-figures-and-their-numbers) | A state is a `file_frames` entry numbered from 0; figure j draws state j − 1; captions and arrows go on the state a step starts from | [02 §11](02-language-semantics.md#11-written-frames), [06 §2](06-prd-step-diagrams.md#2-from-a-run-to-notes) |

**What changed since the draft the files were first written from.**
[Changes since draft v2](decisions.md#changes-since-draft-v2) lists every change
the record adopted, C1–C74, with the evidence checked, and
[Proposals not adopted](decisions.md#proposals-not-adopted) lists what was turned
down and why. The fourteen gaps 02 raised, G1–G14, are decided there too;
[02 §14](02-language-semantics.md#14-gaps-this-file-raised-and-where-they-were-decided)
says where each rule is now stated. A file that must still depart from a decision
says so in a marked note, and the next version of the record decides it
([decisions §11](decisions.md#11-file-plan-and-writing-rules)).

## Milestones

| M | Delivers |
| --- | --- |
| M0 | Decisions recorded in `docs/` and the issues; glossary rows moved in |
| M1 | The language without geometry: builder, parser, printer, `run --check` |
| M2 | Rigid runner on flat states and existing creases: `run -o x.fold`, `-o x.glb`, `--report`; blintz and helmet recipes matched by sequences |
| M3 | Book-style step pages: `run -o x.svg` |
| M4 | Folding some layers; `start folded`, `checkpoint`, `repeat` |
| M5 | Collapse, rabbit ear, petal; the bird base |
| M6 | The study settles steps of a sequence source |
| M7a | A smooth-shaded GLB mode on meshes the study already produces |
| M7b | Animated checked routes; an exact SVG line drawing |
| M8 | Graduation: `run --settle` |
| R | Research: thickness, creases springing back, paper settling with nothing held |

Order: M1 → M2; M2 → M3 and M2 → M4; M5 needs both M3 and M4; M4 → M6 → M8;
M2 → M7b; M7a stands alone.
[decisions §8](decisions.md#8-milestones) decides the contents and order;
[10 §1](10-roadmap-risks-questions.md#1-milestones) has each milestone's contents,
gates and issues; [00](00-overview.md#what-you-can-see-at-each-milestone) says
what you can run after each one.

## Owner decisions

Each has a recommended default, decided with its consequences in
[decisions §9](decisions.md#9-owner-decisions) and scheduled in
[10 §6](10-roadmap-risks-questions.md#6-owner-decisions).

| # | Decision | Recommended default | Before |
| --- | --- | --- | --- |
| 1 | The `.foldseq` extension and the name "sequence source" | `.foldseq`, first line `foldseq 1` | M1's parser |
| 2 | `nearMissBand`: how near a typed coordinate may come to a vertex without lying on it before it is refused as a near miss | 1e-3 sheet lengths | M2 |
| 3 | When a move carries the anchor, pick a new one or refuse | Pick a new one, printed by `--report` | M2 |
| 4 | Stiffness of a *precrease* (a crease folded, unfolded, lying flat) in a settle | A mountain or valley at 0 settles as a crease spring resting at 0 | M6 |
| 5 | SVG "wireframe": feature lines only, or mesh triangles too | `--lines features`; `--lines mesh` adds triangle edges | M7b |
| 6 | Textures: content and source | None; M7a ships normals and texture coordinates only | after M7a |
| 7 | Captions overlapping or overflowing their figure | Captioned pages get a gutter of at least 42/340 ≈ 0.124 of a figure; uncaptioned pages keep their bytes; overflow across cells is stated | M3 |
| 8 | Blintz (corners folded to the centre): behind, as the recipe does, or in front, as the study's `cases.json` does | Behind, as the recipe does | M2's blintz PR |
| 9 | Whether `examples/quarter-fold-steps.fold` moves to the state rule | It stays as the regression; the state-rule page is a new golden | M2 |
| 10 | Eighth turns (`rotate 1/8`) by trigonometry, or a `sheet square as diamond` start | Trigonometry, with platform bits in written coordinates stated | M2 |
| 11 | The external-tools rule in `AGENTS.md` | Yes, at M0 | M0 |
| 12 | Crane-sized sequences in default CI or a separate slow job, and whether that job is required; the largest mesh a settle may use | A separate slow job that is a required check; default CI settles at most 392 triangles; `run --settle` refuses above 1,192 | M4 |

[03](03-prd-embedded-dsl.md#open-questions-for-the-owner),
[05](05-prd-library-additions.md#open-questions-for-the-owner) and
[07](07-prd-material-consumption.md#open-questions-for-the-owner) add narrower
questions.

## Reading the evidence

- **Research notes** use five kinds of evidence and end with an *Unverified*
  section ([research/README.md](research/README.md#how-to-read-them)). The kinds
  are code read at cited lines, `jq` or Python on fixtures, a Python
  re-implementation, a prebuilt binary from 2026-09-07, and fetched web pages.
- **Tags** mark each claim's evidence. Each file defines the tags it uses, for
  example [02](02-language-semantics.md),
  [10 §7](10-roadmap-risks-questions.md#7-corrections-as-proposed-follow-up-issues)
  and [decisions.md](decisions.md), whose commands are in
  [its appendix](decisions.md#appendix-commands-behind-the-numbers).

  | Tag | Evidence |
  | --- | --- |
  | [code] | lines read at `568dcb6` |
  | [jq], [py] | a fixture measured by a command given beside it |
  | [py re-impl] | the research's Python, not senbazuru |
  | [bin] | the prebuilt binary |
  | [measured] | timed runs, with the run count |
  | [ran] | a `git`, `grep` or `sqlite3` command, given in the decision record's appendix |
  | [prd] | a measurement a PRD file made, whose section holds the command |
  | [research] | a research note, cited by file and heading |
  | [reasoned] | worked out from cited code, not run |

- **UNVERIFIED** marks a claim no command has checked, with what would check it.
  The load-bearing ones are risks R1–R3 in
  [10 §5](10-roadmap-risks-questions.md#5-risks).
- **SKETCH** marks a module, type, grammar, file name or message that no code has
  yet.

## Follow-ups

- **This directory edits nothing else.** Eighteen recorded-text changes to
  `AGENTS.md`, `README.md`, `docs/`, module headers, a spec's sentence and issue
  text are listed in [decisions §3](decisions.md#3-recorded-text-this-design-changes),
  written out in [01 §4](01-architecture.md#4-recorded-text-this-design-changes)
  and scheduled in
  [10 §3](10-roadmap-risks-questions.md#3-recorded-text-changes-by-milestone). The
  32 corrections the research found in the repository's own text and code are
  listed in [decisions §10](decisions.md#10-corrections) and written out as
  proposed issues in
  [10 §7](10-roadmap-risks-questions.md#7-corrections-as-proposed-follow-up-issues).
- **Glossary.** M0's first PR moves [glossary-additions](glossary-additions.md)
  into `docs/glossary.md`.
- **Suggested, not done.** If the owner accepts the series, the Docs table in
  [AGENTS.md](../AGENTS.md#docs) (lines 99–113) could gain a `PRDs/` row: "The
  design for fold sequences and material rendering, with its decision record and
  research." This series does not edit `AGENTS.md`.
