# 10 — Roadmap, risks and owner decisions

This file schedules the work that [decisions.md](decisions.md) decides. It says
what lands in each milestone, what must come first, and what each milestone does
to the issue tracker. It also lists the risks, the twelve owner decisions, and
the corrections the design found, written as issues to file. It decides nothing:
it writes out decisions.md's [§8 Milestones](decisions.md#8-milestones),
[§9 Owner decisions](decisions.md#9-owner-decisions) and
[§10 Corrections](decisions.md#10-corrections), and where this file and
decisions.md disagree, decisions.md wins. §7 below keeps §10's item numbers,
which is why its items are not in order.

The decisions this file cites, with the PRD that writes each one out:

| Decision | Title | Written out in |
| --- | --- | --- |
| [D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot) | References named on the sheet and resolved by slot | [02 §4](02-language-semantics.md#4-references) |
| [D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs) | The runner owns the state, its start and the handoffs | [02 §2](02-language-semantics.md#2-the-state-a-run-threads) |
| [D4](decisions.md#d4-written-frames-follow-the-state-rule) | Written frames follow the state rule | [02 §11](02-language-semantics.md#11-written-frames) |
| [D5](decisions.md#d5-presentation-and-the-readers-side) | Presentation and the reader's side | [02 §5](02-language-semantics.md#5-the-readers-side-and-presentation) |
| [D7](decisions.md#d7-a-typed-step-note-reaches-the-page) | A typed step note reaches the page | [06](06-prd-step-diagrams.md) |
| [D8](decisions.md#d8-folding-some-layers) | Folding some layers | [05](05-prd-library-additions.md#requirements-and-design) L2, L7–L11; [02 §6.3](02-language-semantics.md#63-which-layers) |
| [D9](decisions.md#d9-macro-moves-as-named-angle-relations) | Macro-moves as named angle relations | [02 §8](02-language-semantics.md#8-macro-moves) |
| [D11](decisions.md#d11-stacking-choices-are-relations) | Stacking choices are relations | [02 §7](02-language-semantics.md#7-stacking-relations) |
| [D14](decisions.md#d14-material-consumption) | Material consumption | [07](07-prd-material-consumption.md) |
| [D15](decisions.md#d15-graduation-from-study-to-library) | Graduation from study to library | [07](07-prd-material-consumption.md#graduation-staged-and-gated) |
| [D16](decisions.md#d16-testing-and-acceptance) | Testing and acceptance | [09](09-testing-and-acceptance.md) |
| [D17](decisions.md#d17-third-party-and-external-tools) | Third-party and external tools | [07](07-prd-material-consumption.md#external-tools) |
| [D18](decisions.md#d18-non-goals) | Non-goals | [00](00-overview.md#non-goals) |
| [D19](decisions.md#d19-realistic-rendering) | Realistic rendering | [08](08-prd-realistic-rendering.md) |
| [D20](decisions.md#d20-errors) | Errors | [02 §12](02-language-semantics.md#12-refusal-catalogue) |

A *Cn* link names change n in decisions.md's
[changes table](decisions.md#changes-since-draft-v2), where the evidence for it
is listed. Issue states are from `gh issue view N --json state,closedAt,labels`,
run for each issue on 2026-09-15. Code links are to lines read at `568dcb6`. A
*milestone* is a group of pull requests that leaves `main` working, not a
release. *Default CI* is the three checks every PR must pass today, the `test`,
`format` and `lint` jobs of [ci.yml](../.github/workflows/ci.yml). The *slow
job* is a fourth CI job that [D16](decisions.md#d16-testing-and-acceptance) adds
for crane-sized tests
([09 §6.3](09-testing-and-acceptance.md#63-beforeall-not-runio-and-a-slow-job));
whether it is a required check is owner decision 12, and the recommended default
is that it is.

## 1. Milestones

Terms used in the table:

- A [*step*](glossary-additions.md#words-the-prds-narrow) is one figure of a
  book and holds one or more [*moves*](glossary-additions.md#the-sequence-language).
- The [*runner*](glossary-additions.md#running-a-sequence) returns one
  [*move record*](glossary-additions.md#running-a-sequence) per move.
- [*Presentation*](glossary-additions.md#running-a-sequence) turns the model
  without moving paper.
- The [*state rule*](glossary-additions.md#the-fold-format) writes each crease
  as [mountain, valley](../docs/glossary.md#origami) or flat from its current
  angle.
- *Ln* is library addition n of
  [05](05-prd-library-additions.md#requirements-and-design), such as L2,
  `creaseAllAlongWith`. *Row n* is row n of the recorded-text table in
  [§3](#3-recorded-text-changes-by-milestone).
- *Quarter-fold test 1* refolds `examples/quarter-fold-steps.fold`'s own sheet
  and compares the frames it writes with the fixture's
  ([09 §2.2](09-testing-and-acceptance.md#22-test-1-folding-equivalence-m2));
  *test 2* writes the same two folds from a plain square
  ([09 §2.3](09-testing-and-acceptance.md#23-test-2-authoring-from-sheet-square-m3-and-m4)).
  *E1–E10* are the end-to-end assertions on the blintz
  ([09 §3](09-testing-and-acceptance.md#3-end-to-end-e1e10-on-the-blintz)).
- The *material study* is `study/fold-material/`, an executable beside the
  library that bends folded paper as a thin elastic sheet
  ([00](00-overview.md#the-material-study)).
- A [*settle*](glossary-additions.md#material) is a static solve that lets
  paper bend.
- [*Graduation*](glossary-additions.md#material) moves study code into the
  library.
- A *recipe* is a study module that folds or bends one fixture by hard-coded
  edge, face or vertex ids, such as `BlintzSequence` or `CraneWing`. The
  study's *manifest*, `study/fold-material/cases.json`, gives each case a FOLD
  file and a complete angle list per named state
  ([StudyCase.hs:5-6](../study/fold-material/StudyCase.hs#L5-L6)).
- An *equivalence* PR runs a sequence beside the recipe it replaces and
  requires the same records and byte-identical goldens; a second PR then
  deletes the recipe ([09 §9](09-testing-and-acceptance.md#9-migrating-the-study-recipes)).
- A *pin* is one mesh vertex together with the exact position a
  [hold](glossary-additions.md#material) or grip fixes it at
  ([07](07-prd-material-consumption.md#what-that-interface-cannot-survive)).
- The models named below:
  - the [*blintz*](glossary-additions.md#origami) folds a square's corners to
    its centre;
  - the *helmet* base halves a square along a diagonal, then folds both
    corners of the doubled triangle to its tip
    ([HelmetSequence.hs:1-2](../study/fold-material/HelmetSequence.hs#L1-L2));
  - the *bird* route collapses a square into a layered square base, then lifts
    two petals and presses them flat
    ([CheckedBird.hs:1-4](../study/fold-material/CheckedBird.hs#L1-L4));
  - the *crane wing* (`CraneWing`) creases one wing of `examples/crane.fold`
    and turns it through 90°
    ([CraneWing.hs:1-4](../study/fold-material/CraneWing.hs#L1-L4));
  - *crane spreading* (`CraneSpread`) bends that wing with the body held
    ([CraneSpread.hs:1-8](../study/fold-material/CraneSpread.hs#L1-L8)), and
    `CraneRoot` releases the holds at the wing's root, the line where it meets
    the body ([CraneRoot.hs:1-5](../study/fold-material/CraneRoot.hs#L1-L5));
  - the *crane opening* is the crane's first steps, from a square to a square
    base, written as an example sequence in
    [decisions §7](decisions.md#7-examples), **UNVERIFIED** throughout.
- A1, A2a and W1 are rungs on the
  [*fidelity axes*](glossary-additions.md#realistic-rendering).

| M | Name | What lands | Closes | Advances, amends or relates | Detail |
| --- | --- | --- | --- | --- | --- |
| M0 | Decisions on record | rows 1–10 and 16 ([§3](#3-recorded-text-changes-by-milestone)); `docs/notes/sequences.md`; glossary rows moved in; the issues of [§7.2](#72-new-issues-to-file) filed | — | amends [#60](https://github.com/avalonalex/senbazuru/issues/60), [#95](https://github.com/avalonalex/senbazuru/issues/95), [#97](https://github.com/avalonalex/senbazuru/issues/97), [#111](https://github.com/avalonalex/senbazuru/issues/111), [#36](https://github.com/avalonalex/senbazuru/issues/36), [#94](https://github.com/avalonalex/senbazuru/issues/94), [#104](https://github.com/avalonalex/senbazuru/issues/104), [#114](https://github.com/avalonalex/senbazuru/issues/114), [#56](https://github.com/avalonalex/senbazuru/issues/56), [#64](https://github.com/avalonalex/senbazuru/issues/64), [#96](https://github.com/avalonalex/senbazuru/issues/96) | [01](01-architecture.md#4-recorded-text-this-design-changes) |
| M1 | Language without geometry | `Sequence.Syntax`, `Error`, `Build`, `Parse`, `Pretty`, `Check`, `Elaborate`; `Fold.Load.readSequenceText`; the `decodeFile` refusal; `Sequence.RunPlan` for `--check`; `run --check`; round-trip property; whole-crane parse-and-check test; row 2 | — | advances #60 | [03](03-prd-embedded-dsl.md), [04](04-prd-sequence-source-and-cli.md) |
| M2 | Rigid runner on flat states and existing creases | `sheetState`; references on flat states; `fold`, `unfold`, `fold and unfold` along [constructions](glossary-additions.md#references) on the flat sheet and along existing creases of flat-folded states; L1 (`atRest`), L2 (`creaseAllAlongWith`), L3 (`fitRigid`, some-vertex classification), L4's `flapStationaryFace` and `Origami.Route`, L14 (`prepareFlapToward`, `Eq`); presentation; [anchors](glossary-additions.md#running-a-sequence); `Sequence.Record` with `writtenStates`; the writer; `run -o .fold`, `.glb`; `--report`; `expect refused`; `not modelled`; the bird arrows golden pinned before L3; blintz and helmet equivalence; quarter-fold test 1; E1–E6, E8–E10; rows 11, 12 (`runSequence`), 13 | #95, #97 | advances #60; [#58](https://github.com/avalonalex/senbazuru/issues/58) item 3 | [02](02-language-semantics.md), [04](04-prd-sequence-source-and-cli.md), [05](05-prd-library-additions.md) |
| M3 | Step pages that read like a book | `StepNote`, `stepPageWith`, arrow heads, `Symbol`, captions, L5 (`motionsAcross`, `creasesToCome`), figures of several moves, marks; `run -o .svg`; E7; row 12 (`stepPageWith`) | #36, #94 | advances [#48](https://github.com/avalonalex/senbazuru/issues/48) | [06](06-prd-step-diagrams.md) |
| M4 | Folding some layers | L6 (before the runner wraps `ThroughError`), L7–L12 (the untouched-fold check, `creaseLayersThrough`, ordered cover, `carryOrders`, the selection rule and `stackingWhere`); selectors; `start folded`, `checkpoint`, `repeat`; crane-wing prefix in the slow job; quarter-fold test 2 and its page; rows 15, 17, 18 | #60 | advances [#54](https://github.com/avalonalex/senbazuru/issues/54); revisits closed [#70](https://github.com/avalonalex/senbazuru/issues/70); related [#110](https://github.com/avalonalex/senbazuru/issues/110) | [02](02-language-semantics.md), [05](05-prd-library-additions.md), [09](09-testing-and-acceptance.md) |
| M5 | Coupled macros | [collapse](glossary-additions.md#words-the-prds-narrow) with `keeping`, rabbit ear, petal, `continue`, `together`, `sample`, `pose`; L13 (`CheckedMacro`, `macroPoseAt`); the study's [certificate](glossary-additions.md#assurance) registry; bird route; crane opening | — | advances #54, [#61](https://github.com/avalonalex/senbazuru/issues/61); [#55](https://github.com/avalonalex/senbazuru/issues/55) unblocked, not required | [02](02-language-semantics.md), [05](05-prd-library-additions.md) |
| M6 | Study consumes records | `Sequence.Material` in the study; `settle` and `material` blocks; [settled illustrations](glossary-additions.md#material) and failure scope; crane spreading re-expressed, pin-set equivalence first; `senbazuru-material-study --sequence SOURCE DIR`; L4's `flapPoseAt` here or at M7b, with its first consumer | — | advances [#195](https://github.com/avalonalex/senbazuru/issues/195); #114 rewritten | [07](07-prd-material-consumption.md) |
| M7a | Realistic GLB mode on existing meshes | A1 normals, split at [feature edges](glossary-additions.md#realistic-rendering); A2a texture coordinates (`TEXCOORD_0` from material coordinates); fidelity metadata; `Page.pageDescription`; shown on the crane-spread and wing-bending study meshes | — | first visible realism | [08](08-prd-realistic-rendering.md) |
| M7b | Motion and lines | G1 animation ([`SweptHinge`](glossary-additions.md#assurance) routes, `Sampled` after M5); L15 (`foldedWalk`); W1 line drawing; `--lines`; glTF crease-line spike | #56 | advances #104, #48 | [08](08-prd-realistic-rendering.md) |
| M8 | Graduation | [D15](decisions.md#d15-graduation-from-study-to-library)'s seven stages; `run --settle`; `--allow-unsettled` | — | gated on [#208](https://github.com/avalonalex/senbazuru/issues/208); [#106](https://github.com/avalonalex/senbazuru/issues/106) later | [07](07-prd-material-consumption.md) |
| R | Research | thickness offsets and crease radii at vertices; unheld equilibrium; calibration; exact contact at scale; springback rest angles; animated flexible routes | — | #114, #106, #64 | [07](07-prd-material-consumption.md), [08](08-prd-realistic-rendering.md) |

L14 and L15 are new in decisions.md
([C4](decisions.md#changes-since-draft-v2), [C5](decisions.md#changes-since-draft-v2), [C45](decisions.md#changes-since-draft-v2))
and join 05's list under those numbers. What a user can run after each milestone
is in [00](00-overview.md#what-you-can-see-at-each-milestone).

## 2. Order

```text
            ┌──► M3 ────────┐
M1 ──► M2 ──┼──► M4 ────────┴──► M5
            │     └──► M6 ──► M8
            └──► M7b            (Sampled routes join M7b once M5 lands)

M0     one hard edge: row 2 merges no later than M1's Sequence.Parse PR
M7a    no edges            R    no edges

gates  Fold.Query.atRest and #111's table amendment   ──►  M2's writer
       L6, LineStopsOnTheModel names its end          ──►  M4's runner wrapping ThroughError
       M3's motionsAcross                             ──►  M4's last PR: quarter-fold test 2, closing #60
       #208's value-only line search                  ──►  M6's crane equivalence PR, and M8
```

| Edge | Why |
| --- | --- |
| M1 → M2 | `runSequence` consumes the checked, elaborated sequence ([01](01-architecture.md)). |
| M2 → M3 | Step notes are built from move records and presentation ([06](06-prd-step-diagrams.md)). |
| M2 → M4 | Layer selectors extend M2's resolver and fold state. |
| M3 → M5 | Macro figures and `sample` poses get note rules on M3's `StepNote` ([06](06-prd-step-diagrams.md#risks)). |
| M4 → M5 | A macro's flat endpoint with several layer orders is chosen by stacking relations, and `stackingWhere` lands at M4. |
| M4 → M6 | Crane spreading starts from the crane-wing fold, which needs `start folded`, `flap containing` and folding some layers. |
| M6 → M8 | Graduation's last stage moves the consumer M6 proves. |
| M2 → M7b | Animation keys come from `recordPoseAt` on records; step pages are not needed. |
| M7a free | Needs only `Origami.Surface` and meshes the study already accepts. |
| `atRest` gate | The writer reads τ, the angle within which a crease counts as flat ([state rule](glossary-additions.md#the-fold-format)), from `Fold.Query.atRest`. #111's amended table ([01 §4.6](01-architecture.md#46-111)) records the writer's rule and names `atRest` as what the other `1e-10` readers should use. |
| L6 gate | `LineStopsOnTheModel`'s message starts with `--from` or `--to` ([ThroughLayers.hs:194-195](../src/Senbazuru/Origami/ThroughLayers.hs#L194-L195), [Query.hs:68-71](../src/Senbazuru/Fold/Query.hs#L68-L71)). An author running a sequence typed no such flag, so the message must name the end by its point before the runner shows it ([D20](decisions.md#d20-errors); row 17; [§7.2](#72-new-issues-to-file) item 31). |
| M3 → M4's last PR | Quarter-fold test 2's step 2 creases both layers of a flat-folded state, which needs `creaseLayersThrough` (M4), and its page draws crease graphs that grow between frames, which needs `motionsAcross` (M3). So the test lands with the later of the two, and #60 closes in M4's last PR, after M3 has merged ([D16](decisions.md#d16-testing-and-acceptance), [C49](decisions.md#changes-since-draft-v2), [C54](decisions.md#changes-since-draft-v2)). |
| #208 gate | #208 proposes a *value-only* line search: while it picks a step length, the solver evaluates energies without their derivatives. M6's equivalence PRs run recipe and sequence side by side in the costliest groups (R4). Without the gate, that PR compares resolved pin sets without solving and solves once in the slow job ([D15](decisions.md#d15-graduation-from-study-to-library)). |

**Why `creaseAllAlongWith` is in M2, not M4** ([D8](decisions.md#d8-folding-some-layers),
[C27](decisions.md#changes-since-draft-v2)). M2 folds along new constructions on
the flat sheet, and today's `creaseAllAlong` cannot feed a checked fold.
It returns only a frame, with no new edge ids
([Creasing.hs:138](../src/Senbazuru/Fold/Creasing.hs#L138)). When the frame
records angles, it writes each new mountain or valley at ±180 and any other
assignment at 0 ([Creasing.hs:290-292](../src/Senbazuru/Fold/Creasing.hs#L290-L292),
[:316-320](../src/Senbazuru/Fold/Creasing.hs#L316-L320)). A crease created at
±180 is already fully folded, so no turn from 0 is left for `Origami.Flap` to
check. A recipe that wants a crease at rest therefore marks it `U` and loses
its intent ([CraneWing.hs:65](../study/fold-material/CraneWing.hs#L65) finds
its hinge as the `U` edges). Move records need the new ids
([D14](decisions.md#d14-material-consumption)), and a checked fold needs the
crease made at rest. So M2 carries
[05 L2](05-prd-library-additions.md#l2-creaseallalongwith-and-newcreaseangle):
`creaseAllAlongWith AtRest`, where `AtRest` creates each new crease at angle 0.

## 3. Recorded-text changes by milestone

Each row edits text outside `PRDs/`. [decisions §3](decisions.md#3-recorded-text-this-design-changes)
numbers the rows, and [01 §4](01-architecture.md#4-recorded-text-this-design-changes)
gives the current text and the full replacement under the same row number. Row
12 lands in two PRs: M2 adds `runSequence` to the list and M3 adds
`stepPageWith` ([C65](decisions.md#changes-since-draft-v2)).

| When | Row | Where | Change |
| --- | --- | --- | --- |
| M0, first PR | 10 | `docs/glossary.md` | move [glossary-additions](glossary-additions.md) in; fix rest angle (`:19`, `:83`) and flat-folded (`:21`) |
| M0 | 1 | `docs/architecture.md:81-86` | a sequence's moves are not "a frame in, a frame out" |
| M0, no later than M1's `Sequence.Parse` PR | 2 | `AGENTS.md:193-196`, `docs/architecture.md:170-175` | a sequence source is a program: the stated exception |
| M0 | 3 | #60 | `runSequence` returning records; "one interpreter" superseded; done-when split into folding equivalence and authoring |
| M0 | 4 | #95 | turn over is presentation about a model-intrinsic axis |
| M0 | 5 | #97 | note renamed `sequences.md`; "scheme" retired; closes at M2 |
| M0 | 6 | #111 | add the writer's at-rest rule and two `1e-10` thresholds |
| M0 | 7 | #36, #94, #104, #114, #56, #64 | premise and done-when corrections ([§7.1](#71-already-carried-by-a-recorded-text-row-or-a-prd-requirement)); #94's done-when met through `run -o x.svg`; #104's names `--view front` |
| M0 | 8 | `AGENTS.md` "Third-party material" | running an external program is not vendoring |
| M0, with #96 | 9 | `docs/notes/no-sequence-solver.md` | the vocabulary is formal now; searching it stays a non-goal |
| M0 | 16 | `docs/roadmap.md:82-87`, `:368-373` | the recorded issue order replaced by the milestones |
| M2 | 11 | `AGENTS.md:173-177` | sheet and physical lengths, each converted in one place |
| M2 | 12 | `AGENTS.md:217-221` | add `runSequence` to the `--layer-budget` list |
| M2, the presentation-classification PR | 13 | `src/Senbazuru/Origami/Step.hs:30-34` | a whole-model rigid motion is a presentation change |
| M3 | 12 | `AGENTS.md:217-221` | `stepPageWith` joins that list |
| M2 or later, recipe deletion PRs | 14 | `docs/architecture.md:202-211`; `BlintzSequence`, `HelmetSequence` headers | recipes replaced by sequences |
| before M4's runner wraps `ThroughError`, in L6's PR | 17 | `test/Senbazuru/Origami/ThroughLayersSpec.hs:271-275`, `docs/usage.md:866-872` | the `LineStopsOnTheModel` sentence names the end by its point |
| M4, the PR adding the slow job | 15 | `AGENTS.md:378-379` | "all three CI checks" names the slow job and whether it is required (owner decision 12) |
| M4, the PR closing #60 | 18 | `README.md:213` roadmap item 2, `docs/roadmap.md` item 2 | the vocabulary exists |

Row 16's two passages record the old order. Lines 82-87 put #97 before #95 and
#54; lines 368-373 order #93, #96, #97, and "only then" #95, #94 and #36. M0
decides #97 without #93, and the milestones schedule #95 at M2, #94 and #36 at
M3, and #60's close at M4 ([C56](decisions.md#changes-since-draft-v2)).
[D](research/D-docs-issues-constraints.md), "B. How the relevant open issues
depend on each other — question (b)", reads the same chain from those lines.

Row 14's range ends at `docs/architecture.md:211`, the last line of the helmet
sentence; `HingeSweep`'s paragraph starts at `:212` (`sed -n 200,213p
docs/architecture.md`; [C64](decisions.md#changes-since-draft-v2)). Row 17's
sentence is the one `ThroughLayersSpec` pins and `docs/usage.md` quotes
([C66](decisions.md#changes-since-draft-v2)); row 18 is
[C74](decisions.md#changes-since-draft-v2), and row 15 is
[C51](decisions.md#changes-since-draft-v2).

## 4. Issue mapping

- **close:** the milestone meets the amended done-when.
- **advance:** part of the scope lands, and the issue stays open.
- **amend:** M0 rewrites its text.
- **depend:** a milestone relies on it or works around it.
- **untouched:** outside this design, for the reason given.

| Issue | State, 2026-09-15 | Relation | When | Why |
| --- | --- | --- | --- | --- |
| [#36](https://github.com/avalonalex/senbazuru/issues/36) arrow vocabulary | open | amend, close | M0, M3 | A reflection is the mirror model, not a turn-over; M3's arrow heads, `Symbol` and notes meet the rest. |
| [#48](https://github.com/avalonalex/senbazuru/issues/48) x-ray lines | open | advance | M3, M7b | Notes carry each move's selected layers; x-ray lines need M7b's exact visibility. |
| [#49](https://github.com/avalonalex/senbazuru/issues/49) cut-away | open | untouched | — | Named on the line-drawing axis ([D19](decisions.md#d19-realistic-rendering)), in no milestone. |
| [#50](https://github.com/avalonalex/senbazuru/issues/50) side view | open, roadmap | untouched | — | Needs thickness as geometry, which stays research ([D18](decisions.md#d18-non-goals)). |
| [#52](https://github.com/avalonalex/senbazuru/issues/52) degree-4 closed form | open, study note | untouched | — | Macros use one closed form per macro ([D9](decisions.md#d9-macro-moves-as-named-angle-relations)), not a degree-4 solve. |
| [#53](https://github.com/avalonalex/senbazuru/issues/53) simulator states | open | untouched | — | An external comparison oracle, never a CI or test dependency ([D17](decisions.md#d17-third-party-and-external-tools)). |
| [#54](https://github.com/avalonalex/senbazuru/issues/54) rotate a flap | open | advance | M4, M5 | Layer selection, then three coupled moves. Its meeting-creases, curved-wing and rigid-wing-return items stay open, so neither milestone closes it. |
| [#55](https://github.com/avalonalex/senbazuru/issues/55) angle solver | open, roadmap | untouched | — | Named macros need no general solver; requiring one is a non-goal ([D18](decisions.md#d18-non-goals)). M5 unblocks it without requiring it. |
| [#56](https://github.com/avalonalex/senbazuru/issues/56) animation | open | amend, close | M0, M7b | Step 1 is done (`foldedPlacements`); M7b animates checked routes. |
| [#58](https://github.com/avalonalex/senbazuru/issues/58) writer loose ends | open, chore | advance | M2 | Item 3 (non-finite numbers) lands with the writer; item 4 is not claimed. |
| [#60](https://github.com/avalonalex/senbazuru/issues/60) vocabulary | open, roadmap | amend, advance, close | M0; M1–M3; M4 | Rewritten around `runSequence` and records; closes in M4's last PR, below. |
| [#61](https://github.com/avalonalex/senbazuru/issues/61) checks along a motion | open | advance | M5 | Macro routes are a new motion family, checked at sampled poses. |
| [#64](https://github.com/avalonalex/senbazuru/issues/64) rigid or compliant | open, study note | amend | M0; R | "Inflate the body is outside the model" is overtaken by #106 and [README.md:158-164](../README.md). |
| [#70](https://github.com/avalonalex/senbazuru/issues/70) crease through layers | closed 2026-09-07 | revisit | M4 | `creaseLayersThrough` extends it to selected faces; `crease --folded` output unchanged. |
| [#73](https://github.com/avalonalex/senbazuru/issues/73) vendor keys | open | depend | M2 | Until it splits file and frame keys, the writer keeps extras off the key frame ([D4](decisions.md#d4-written-frames-follow-the-state-rule), [D18](decisions.md#d18-non-goals)). |
| [#93](https://github.com/avalonalex/senbazuru/issues/93) corpus sweep | open | untouched | — | Not in this design; `docs/roadmap.md` orders it before #97, and row 16 replaces that order ([§3](#3-recorded-text-changes-by-milestone)). |
| [#94](https://github.com/avalonalex/senbazuru/issues/94) captions | open | amend, close | M0, M3 | `render --steps` never draws `frame_title`, because a file cannot say whether its titles name states or instructions ([D7](decisions.md#d7-a-typed-step-note-reaches-the-page), [C35](decisions.md#changes-since-draft-v2)). M0 amends the done-when; M3 meets it through `run -o x.svg`, whose captions come from step notes. |
| [#95](https://github.com/avalonalex/senbazuru/issues/95) turn over | open | amend, close | M0, M2 | A half turn about x = 0 moves the model across the page. |
| [#96](https://github.com/avalonalex/senbazuru/issues/96) 2026 papers | open, study note | amend | M0 | Says three papers, lists four; amended with row 9. |
| [#97](https://github.com/avalonalex/senbazuru/issues/97) scheme format | open | amend, close | M0, M2 | Decided at M0; its reproduction done-when needs the runner. |
| [#102](https://github.com/avalonalex/senbazuru/issues/102) `frame_inherit` | open | untouched | — | A non-goal ([D18](decisions.md#d18-non-goals)); written frames repeat the graph. |
| [#104](https://github.com/avalonalex/senbazuru/issues/104) silhouettes | open | amend, advance | M0, M7b | Cites a missing note, and its first done-when bullet cannot be met from `--view iso`; the amended done-when names `--view front`, and W1 silhouettes behind `--lines` advance it ([D19](decisions.md#d19-realistic-rendering)). |
| [#106](https://github.com/avalonalex/senbazuru/issues/106) pockets | open | advance | R | Only as research: pressure and inflation are non-goals of M0–M8 ([D18](decisions.md#d18-non-goals)). |
| [#110](https://github.com/avalonalex/senbazuru/issues/110) `withLayerOrder` | open | related | M4 | `stackingWhere` sits beside it; neither needs the other. |
| [#111](https://github.com/avalonalex/senbazuru/issues/111) angle rule | open | amend, depend | M0, M2 | `atRest` lands before the writer, not blocked on #111's move ([D4](decisions.md#d4-written-frames-follow-the-state-rule)). |
| [#114](https://github.com/avalonalex/senbazuru/issues/114) fold radii | open | amend | M0, M6; R | `--thickness` and face lifting are gone; rewritten at M6. |
| [#195](https://github.com/avalonalex/senbazuru/issues/195) curved wing | open | advance | M6 | Crane spreading re-expressed through records. |
| [#206](https://github.com/avalonalex/senbazuru/issues/206) root visibility | open, bug | depend | M6, M7b | Settled GLBs add a visible scene only when it exports; W1 may use its 4,312-triangle mesh as a failing case. |
| [#208](https://github.com/avalonalex/senbazuru/issues/208) study CI cost | open | depend, gate | M6, M8 | Its value-only line search precedes M6's crane equivalence PR and M8. |

**#60 closes at M4** ([C54](decisions.md#changes-since-draft-v2)). Its amended
done-when ([01 §4](01-architecture.md#4-recorded-text-this-design-changes),
row 3) has two halves: folding equivalence, which is quarter-fold test 1 at M2,
and authoring, which is quarter-fold test 2. Test 2 needs M3's `motionsAcross`
and M4's `creaseLayersThrough` ([§2](#2-order)), so #60 closes in M4's last PR,
after M3 has merged. #60 carries the `roadmap` label, and roadmap item 2 of
[README.md](../README.md) (line 213) and of `docs/roadmap.md` still calls the
vocabulary missing, so that PR carries row 18
([C74](decisions.md#changes-since-draft-v2)).

**#54 is advanced, not closed** ([C55](decisions.md#changes-since-draft-v2)).
M4 and M5 each land part of it, and no milestone covers its three open checklist
items: compatible changes at meeting creases (#52, #55), a curved wing (#195),
and the rigid wing returning onto its resting surface with both wings chained
(`gh issue view 54`).

## 5. Risks

Likelihood and impact are High, Medium or Low. *Owner* is the milestone and PRD
that hold the mitigation.

| # | Risk | Likelihood | Impact | Mitigation | Owner |
| --- | --- | --- | --- | --- | --- |
| R1 | The rule that picks which layers a fold moves (the [top flap](glossary-additions.md#references) rule) is reproduced only in Python ([layer-selection-analyse.py](research/scripts/layer-selection-analyse.py)). It recovers `CraneWing`'s faces `[2,3,6,7]` there ([gap-layer-selective-folds](research/gap-layer-selective-folds.md), "Re-deriving CraneWing by rule (script)"), but senbazuru may number faces differently (same note, "Unverified"). | Medium | High | The first M4 PR reproduces those faces in Haskell ([D8](decisions.md#d8-folding-some-layers)) | M4, [05](05-prd-library-additions.md) |
| R2 | The crane's two [stacking relations](glossary-additions.md#running-a-sequence) ([D11](decisions.md#d11-stacking-choices-are-relations)) may leave several [stackings](glossary-additions.md#running-a-sequence) (layer orders) or none. **UNVERIFIED** | Medium | Medium | A test shows the two leave exactly one stacking, today's index 2 of the crane's five ([CraneWing.hs:78](../study/fold-material/CraneWing.hs#L78)), and that dropping either of the two leaves two or more ([09 §4](09-testing-and-acceptance.md#4-acceptance-by-milestone), M4); refusals name [open pairs](glossary-additions.md#running-a-sequence) | M4, [09](09-testing-and-acceptance.md) |
| R3 | Named [holds](glossary-additions.md#material) may not select the vertices `CraneSpread` fixes by id today, its pins. **UNVERIFIED**: that `hold band moving 0..1/32 at rigid-pose 1/3` gives its root-strip pins, and `arc-grip` its grip pins ([07](07-prd-material-consumption.md#every-existing-crane-control-re-expressed)) | Medium | High | First M6 PR compares resolved pin sets (same ids; positions within 1e-12) without solving (07 AC-1) | M6, [07](07-prd-material-consumption.md) |
| R4 | M6 doubles the costliest groups. In one CI run #208 records 626 s of hspec over 1,387 examples, and its log timestamps put `CraneRoot` at about 164.87 s and `CraneSpread` at 97.48 s, approximate group wall times ([gap-study-consumption-contract](research/gap-study-consumption-contract.md), "(d) What guards each recipe", finding 20) | High without the #208 gate | Medium | The #208 gate, or compare resolved sets and solve once in the slow job, a required check by owner decision 12's default; default CI settles ≤ 392 triangles | M6, [09](09-testing-and-acceptance.md) |
| R5 | Every `stack test` run filtered with `--match` pays 19.03, 19.59 and 20.95 s wall of fixture setup for 0 examples, because [`runIO`](glossary-additions.md#code-and-tests) builds fixtures before the filter applies ([gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md), "Summary", measured, 3 runs) | High | Medium | Fixtures in `beforeAll`; budgets in counted work (intervals, refolds, triangles) | M1 onward, [09](09-testing-and-acceptance.md) |
| R6 | Nine formulas act as the [*hair*](../docs/glossary.md#origami) (the distance below which points coincide); on a sheet 0.01 wide two are about 70× apart ([gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md), "A. How exact a landmark is today", finding 2) | Medium | Medium | Tolerance-unification issue ([§7.2](#72-new-issues-to-file) item 17); meanwhile each requirement names its tolerance by `path:line` | M0, [02](02-language-semantics.md) |
| R7 | One of the 33 tracked [goldens](../docs/glossary.md#this-project) moves (`git ls-files test/golden \| wc -l`) | Low | High | `stepPage` delegates with default notes; `ArrowPath` defaults emit today's bytes; the three catch-all (`_`) matches in `LayoutSpec` and `CreasePatternSpec` are changed by hand to name `Symbol`, because the compiler cannot flag them and a new `Symbol` shape would fall silently into `_` (so `isArrow` would pass a loop drawn in place of an arrow) ([06](06-prd-step-diagrams.md#requirements) R-06-7); `git diff --name-only --diff-filter=MD origin/main...HEAD -- test/golden/` prints nothing, and the same command with `--diff-filter=A` lists the goldens a PR adds ([D16](decisions.md#d16-testing-and-acceptance)) | M3, [06](06-prd-step-diagrams.md) |
| R8 | Captions overlap their figure on the default pages; goldens record markup, not glyphs | High | Medium | Owner decision 7 before M3; its recommended default widens the gutter on captioned pages only ([06 §8](06-prd-step-diagrams.md#8-captions-and-the-gutter)) | M3, [06](06-prd-step-diagrams.md) |
| R9 | An odd [`rotate k/8 turn`](glossary-additions.md#origami) needs cos 45° = √2/2, which no `Double` holds exactly. Its last bits come from `cos` and `sin`, which differ between macOS and Linux, so written coordinates can differ by platform ([09 §8](09-testing-and-acceptance.md#8-bytes-that-differ-by-platform)). GLB extras also store fold angles and material coordinates unrounded ([Gltf.hs:241-242](../src/Senbazuru/Render/Gltf.hs#L241-L242)) | Medium | Medium | Default-CI sequences avoid trigonometry ([D16](decisions.md#d16-testing-and-acceptance)); owner decision 10; [item 22](#72-new-issues-to-file) | M2, [09](09-testing-and-acceptance.md) |
| R10 | [Signatures](glossary-additions.md#macro-moves) match few patterns: petals other than 22.5° refused, the rabbit-ear rule possibly too strict, the crane's centre matching four collapses | Medium | Medium | `not modelled "…"` keeps sources parseable; refusals list each `keeping` candidate | M5, [02](02-language-semantics.md) |
| R11 | The crane opening's fold directions and `keeping` pair are unverified | Medium | Low | Derived with the runner; the four candidates become the refusal test | M5 |
| R12 | Blender imports glTF loose edges but does not render them, so crease lines go unseen | Medium | Medium | A measured spike first; fallback: lines as extras, drawn by the study viewer | M7b, [08](08-prd-realistic-rendering.md) |
| R13a | W1 visibility is too slow on large meshes; its cost at 4,312 triangles is unknown | Medium | Medium | 08 A-15 counts candidate × face pairs over 3–5 compiled runs at 392, 1,192 and 4,312 triangles before any size is promised | M7b, [08](08-prd-realistic-rendering.md) |
| R13b | 08 A-13's failing case needs a mesh on which `projectedForm` declines, returning `Nothing` instead of a fill, and the crane-spread meshes may not give one | Medium | Medium | 08 A-11 first records whether it declines on crane-spread curved and fine; if not, A-13 uses [#206](https://github.com/avalonalex/senbazuru/issues/206)'s 4,312-triangle crane-root mesh, in the slow job | M7b, [08](08-prd-realistic-rendering.md) |
| R14 | "Realistic" is read as bent paper from `senbazuru` before M8 | High | Medium | Outputs record their fidelity axes; [00](00-overview.md#what-realistic-means-honestly) says a rigid sequence gets motion and lines, not paper | [08](08-prd-realistic-rendering.md) |
| R15 | A settle must start flat, and the crane wing's second move starts at 90° | High | Medium | `SettleStartNotFlat` names the step; learning contact orders from a separated reference comes later, as an option registered by name, never a silent fallback ([07](07-prd-material-consumption.md#where-a-settle-starts)) | M6, [07](07-prd-material-consumption.md) |
| R16 | A checked step calls `foldFrameWith` about seven times (counted from code, untimed: [gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md), "Summary") | Medium | Medium | `--report` prints work counts; measure before caching ([D3](decisions.md#d3-the-runner-owns-the-state-its-start-and-the-handoffs)) | M2, [09](09-testing-and-acceptance.md) |
| R17 | The Haskell builder and the text parser drift | Medium | Medium | `parse (pretty s) == Right s`; built and parsed blintz equal with spans stripped | M1, [03](03-prd-embedded-dsl.md) |
| R18 | An owner decision arrives after the milestone that fixes it | Medium | Low | *Decide before* in [§6](#6-owner-decisions) | owner |

## 6. Owner decisions

Numbered as every PRD's open questions cite them, and as
[decisions §9](decisions.md#9-owner-decisions) records them. Each has a
recommended default and must be decided before the milestone named.

| # | Decision | Recommended default | If decided otherwise | Decide before |
| --- | --- | --- | --- | --- |
| 1 | File extension; the name "sequence source" | `.foldseq`, first line `foldseq 1` (`.fseq` is the xLights and Falcon Player format) | Extension, first-line keyword, `decodeFile`'s refusal, error goldens and glossary rows change | M1's parser PR |
| 2 | `nearMissBand`, how close a typed literal may come to a vertex before it is a [near miss](glossary-additions.md#references) | 1e-3 [sheet lengths](glossary-additions.md#references) | Smaller: a decimal near a corner becomes a separate point, leaving a crease sliver. Larger: legitimate points refused. A `RunSettings` field, so no syntax change. | M2 |
| 3 | When a move carries the [anchor](glossary-additions.md#running-a-sequence) face, re-anchor or refuse | Re-anchor, printed by `--report` | Refuse: authors write `anchor P` first, and M7b's animation needs no new glTF sub-hierarchy at each re-anchor ([08](08-prd-realistic-rendering.md#g1-animating-checked-rigid-routes) R-08-27) | M2 |
| 4 | Stiffness of a [precrease](glossary-additions.md#origami) in a settle | A mountain or valley at angle 0 settles as a *crease spring* resting at 0, weighted by its length alone; a file's flat edges stay *panel bends*, weighted also by the areas of the two triangles beside them | As panel bends: rotation concentrates differently ([07](07-prd-material-consumption.md#rest-angles-stiffness-and-nodifference)); M6's numbers change | M6 |
| 5 | SVG "wireframe": feature lines, or triangulation too | `--lines features`; `--lines mesh` adds visible triangle edges | Mesh default: every settled page draws its triangulation; visibility runs on more segments | M7b |
| 6 | Textures (A2b, the appearance rung after A2a's texture coordinates): content and source | None; M7a ships normals and texture coordinates only | Procedural: PNG writer on `bytestring`, or `zlib`/`JuicyPixels` (both in lts-22.44). Vendored: licence and provenance in `examples/README.md`. | after M7a |
| 7 | Caption overlap and overflow | Captioned pages get a gutter of at least 42/340 ≈ 0.124 of a figure, the bound at which 14-unit type clears on the default three-column page ([06 §8](06-prd-step-diagrams.md#8-captions-and-the-gutter)); uncaptioned pages unchanged; overflow across cells accepted and stated, since the backend has no font metrics | Accept overlap: unreadable pages. Squash or truncate: width estimates without font metrics. Refuse: some sequences cannot be drawn. | M3 |
| 8 | [Blintz](glossary-additions.md#origami) direction. Both routes are read from the [reader's side](glossary-additions.md#running-a-sequence), model +z. The manifest turns each corner by a positive angle, +90 then +175 (`jq -c '.[3].steps[] \| .angles' study/fold-material/cases.json`): the corner rises towards the reader, a valley as seen, written `fold in front`. The recipe turns it by −180 ([BlintzSequence.hs:51-54](../study/fold-material/BlintzSequence.hs#L51-L54)): the corner goes behind, a mountain as seen, written `fold behind`. Both end in the same flat positions ([A2](research/A2-study-recipes-as-proto-dsl.md), F3). | The recipe's `fold behind`, so migration reuses `checked-blintz.svg` | Manifest's `fold in front`: both blintz sources switch in one PR; gallery output changes | M2's blintz PR |
| 9 | `examples/quarter-fold-steps.fold`: migrate to the state rule, or stay the regression | Stays; the state-rule page is a new golden | Migrates: `quarter-fold-steps.svg` and `quarter-fold-step-1.svg` move in that PR, and the fixture's `test/fixtures` copy migrates too ([06](06-prd-step-diagrams.md)) | M2 |
| 10 | Eighth turns by trigonometry, or a `sheet square as diamond` start | Trigonometry, platform bits in written coordinates stated | Diamond: `rotate` takes even k only, because quarter turns use only 0 and ±1 ([02 §5.2](02-language-semantics.md#52-presentation-moves-no-paper)), so frames stay exact; the crane-opening example's first step becomes a header option | M2 |
| 11 | The external-tools rule in AGENTS.md | Yes, row 8 at M0 | Only in `docs/related-projects.md`: agents reading AGENTS.md miss it | M0 |
| 12 | CI placement of crane-sized sequences; the slow job's status; triangle budgets | Crane-sized sequences in a separate slow job that is a **required** check, so row 15 changes "all three CI checks" to four; default CI settles ≤ 392 triangles; `run --settle` refuses above 1,192 until 3–5 compiled runs after #208 | An optional slow job lets slow regressions merge. Crane tests in default CI pay [D16](decisions.md#d16-testing-and-acceptance)'s costs on every PR before #208 lands (R4). A higher cap admits unmeasured settles. | M4 |

decisions.md also decides, rather than leaves open, questions the PRD files
raised: a step body's own builder type and the lowercase senses, from 03
([C22](decisions.md#changes-since-draft-v2), [C23](decisions.md#changes-since-draft-v2));
τ's value, the some-vertex classification R-05-12′, `creaseAllAlongWith` at M2
and `RoutePose`'s module, from 05 ([C29](decisions.md#changes-since-draft-v2),
[C26](decisions.md#changes-since-draft-v2), [C27](decisions.md#changes-since-draft-v2),
[C28](decisions.md#changes-since-draft-v2)); and 07's proposed rules R-07-10,
-13, -16, -17, -19, -22 and -29 ([C42](decisions.md#changes-since-draft-v2)). The
full list follows the table in [decisions §9](decisions.md#9-owner-decisions).
None of them is an owner decision.

## 7. Corrections as proposed follow-up issues

[decisions §10](decisions.md#10-corrections) lists 32 findings about the
repository's own text and code, none filed; the items below keep its numbers.
Evidence tags:

- [code] lines read
- [jq] fixture measurement
- [py] Python re-implementation
- [bin] the prebuilt `senbazuru` executable built 2026-09-07 at `857fd4c`
  ([gap-assignment-at-rest-convention](research/gap-assignment-at-rest-convention.md),
  "D. Measurements", finding 17)
- [web] fetched page
- [measured] timed runs
- [ls] file listing
- [issue] issue text
- [docs] repository docs
- [research] a research note, by file and heading

### 7.1 Already carried by a recorded-text row or a PRD requirement

The PR that lands the row fixes these. Rows 1–10 and 16 land at M0, row 13 at
M2, and rows 15 and 18 at M4 ([§3](#3-recorded-text-changes-by-milestone)).
Item 21 is carried by 05's requirement L2 rather than a recorded-text row. None
needs a new issue.

| Item | What is wrong | Evidence | Row |
| --- | --- | --- | --- |
| 1 | #95's half turn about x = 0 moves and rescales the model | [jq, py] [gap-step-annotation-channel](research/gap-step-annotation-channel.md), "C. Turning over and the single camera" | 4 |
| 2 | #36's reflection-as-turn-over cannot be met; one quarter-fold motion changes a valley and a mountain together | [code, jq] [01 §4](01-architecture.md#4-recorded-text-this-design-changes) | 7 |
| 3 | #94's "nothing reads `frame_title`" is half stale | [code] [01 §4](01-architecture.md#4-recorded-text-this-design-changes) | 7 |
| 4 | #114's premises are stale | [docs] [paper-thickness.md:1-12](../docs/notes/paper-thickness.md); a second rounded bend stretches 200% ([two-bends-need-more-than-radii.md:55](../docs/notes/two-bends-need-more-than-radii.md)) | 7 |
| 5 | #56's "transforms are discarded" is stale (`foldedPlacements`) | [code] [01 §4](01-architecture.md#4-recorded-text-this-design-changes) | 7 |
| 6 | #104 cites a note that does not exist; its done-when lets default goldens move | [ls] `ls docs/notes/inflate-outside-draw-inside.md`: no such file | 7 |
| 7 | #60's done-when tests folding, not authoring; coordinates need a tolerance; macros are not compositions | [jq, code] #60's comment of 2026-09-07: refolding `quarter-fold-steps.fold` reproduces its coordinates only to within 6e-17, and as `[x, y, z]` where the file has `[x, y]`; [gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md), "B. Signatures, checked by hand" | 3 |
| 11 | Two rest-angle definitions | [code] [docs/glossary.md:19](../docs/glossary.md), `:83` | 10 |
| 21 | `creaseAllAlong` returns no new edge ids | [code] [Creasing.hs:138](../src/Senbazuru/Fold/Creasing.hs#L138) | [05 L2](05-prd-library-additions.md#l2-creaseallalongwith-and-newcreaseangle) |
| 23 | #64's framing is overtaken | [docs] [README.md:158-164](../README.md) | 7 |
| 24 | `Origami.Step`'s header calls a turn-over a motion | [code] [Step.hs:30-34](../src/Senbazuru/Origami/Step.hs#L30-L34) | 13 |
| 27 | #104's first done-when bullet cannot be met: from `--view iso` no face of `puffed-square.fold` turns away, so there is no silhouette to draw | [py] decisions.md [appendix](decisions.md#appendix-commands-behind-the-numbers) command 4 prints `iso away: 0 edge-on: 0 silhouettes: 0`; [issue]; [08 "#104, amended"](08-prd-realistic-rendering.md#104-amended) | 7 |
| 28 | `docs/roadmap.md` records the old order: #97 before #95 and #54 (`:82-87`); #93, #96, #97, then "only then" #95, #94 and #36 (`:368-373`) | [code] lines read | 16 |
| 29 | `AGENTS.md:378-379` requires "all three CI checks"; a slow job makes that count wrong or leaves the job unrequired | [code] [ci.yml](../.github/workflows/ci.yml) has jobs `test`, `format`, `lint` | 15, with owner decision 12 |
| 30 | Roadmap item 2 calls the vocabulary missing, in `README.md` (`:213`) and `docs/roadmap.md` (`:82-87`) | [code] lines read | 18 |

### 7.2 New issues to file

Titles follow the templates (Task, Bug, Study note). All are filed at M0.

| Item | Proposed issue | Evidence | What to change | Lands |
| --- | --- | --- | --- | --- |
| 9 | Task: Correct three rows of related-projects | [web] [E1](research/E1-prior-art-sequence-languages.md), "A. Languages and programs for diagrams"; [E2](research/E2-references-and-persistent-naming.md), "Open questions" | `docs/related-projects.md:38` Doodle → GPLv2. `:36` ReferenceFinder → GPL-2.0. `:24` origami-diagrams → `amkraft/`, MIT only in `package.json`. `:26` Oriedita already MIT. | M0 |
| 10 | Task: Check huzita-hatori's dates | [web] [E2](research/E2-references-and-persistent-naming.md), "B. Huzita–Justin–Hatori: the vocabulary of fold lines", finding 11 | [huzita-hatori.md:29](../docs/notes/huzita-hatori.md) says Huzita 1991, Hatori 2001; Alperin and Lang: Justin and Huzita 1989, Hatori 2001 (Lang's page: 2002) | M0 |
| 12 | Bug: `check` skips Maekawa silently beside an unassigned edge | [code] [FlatFold.hs:503-506](../src/Senbazuru/Origami/FlatFold.hs#L503-L506) reports nothing when `unassigned > 0`; the skip note names only border and bare vertices ([FlatFold.hs:574-583](../src/Senbazuru/Origami/FlatFold.hs#L574-L583)); [bin] [gap-assignment-at-rest-convention](research/gap-assignment-at-rest-convention.md), "D. Measurements" | Count and name vertices where [Maekawa](../docs/glossary.md#origami) went untested | any time |
| 13 | Bug: `existingAt` takes the first existing vertex within tolerance, not the nearest | [code] [Creasing.hs:323-327](../src/Senbazuru/Fold/Creasing.hs#L323-L327); ends added within one batch take the nearest ([Creasing.hs:224-245](../src/Senbazuru/Fold/Creasing.hs#L224-L245)) | Take the nearest, or refuse two vertices within tolerance as the runner's [vertex slot](glossary-additions.md#references) does | before M2's resolver |
| 14 | Task: Record CraneWing's reliance on the crane having no unassigned edges | [code, jq] [CraneWing.hs:65](../study/fold-material/CraneWing.hs#L65) takes every `U` edge as the hinge; `jq '[.edges_assignment[] \| select(.=="U")] \| length' examples/crane.fold` prints 0; its clip (`:98`) lacks `ThroughLayers`' guards ([gap-layer-selective-folds](research/gap-layer-selective-folds.md), "What exists") | State the assumption, or delete the recipe once the wing is a sequence | M4 |
| 16 | Task: Reconcile manifest angle literals with their formulas | [py] decisions.md [appendix](decisions.md#appendix-commands-behind-the-numbers) command 7, rerun for this file with `python3` stepping by `math.nextafter`; [gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md), "C. What can be certified, and how angles should be compared", finding 18. At rabbit-ear m = 30 (m, the mountain crease's angle, [rabbit-ear-motion.md:22](../docs/notes/rabbit-ear-motion.md)) the stored `97.58514830800293` is one [ulp](glossary-additions.md#geometry) from the `atan2` form's `97.58514830800294`. At petal t = 175 (t, the tip hinge's turn, [checked-petal.md:10](../docs/notes/checked-petal.md)) the stored `-166.98236060695527` is three ulps from the code's own `atan2` expression ([CheckedPetal.hs:107](../study/fold-material/CheckedPetal.hs#L107)), which gives `-166.98236060695518` ([C58](decisions.md#changes-since-draft-v2)). An `atan` form reproduces both literals exactly. | Change the documented formula, or the literals as a reviewed fixture change; compare with a named tolerance meanwhile | M5 |
| 17 | Task: Unify the tolerances that act as "a hair" | [code] nine-row table, [gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md), "A. How exact a landmark is today", finding 2 | One named tolerance per question; remaining differences stated in headers | [D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot)'s prerequisite (R6) |
| 19 | Task: Check that a `Rigid` is a proper rotation | [code] [Rigid.hs:25](../src/Senbazuru/Geometry/Rigid.hs#L25) "nothing here checks"; `Mat3 (..)`, `Rigid (..)` exported (`:29`, `:35`) | A checked constructor; presentation checks det = +1 within 1e-12 ([D5](decisions.md#d5-presentation-and-the-readers-side)) | M2 |
| 20 | Task: Build expensive fixtures in `beforeAll`, not `runIO` | [measured] R5 | Filtered or tagged runs skip fixture setup | before M1's specs; related #208 |
| 22 | Task: Store GLB extras' doubles as reproducibly as positions | [code] [Gltf.hs:237](../src/Senbazuru/Render/Gltf.hs#L237) packs positions; [:241-242](../src/Senbazuru/Render/Gltf.hs#L241-L242) store fold angles and material coordinates as computed | Round them too, or state the platform dependence | M7a |
| 25 | Task: Match the study viewer's paper colours to the theme | [code] [viewer.html:168](../study/fold-material/viewer.html#L168) `vec3(.84,.53,.27)`, `vec3(.96,.91,.80)`; theme `#faf8f3` ([Style.hs:114](../src/Senbazuru/Diagram/Style.hs#L114)), `#e5ded1` (`:132`) | Use the theme's colours, or say why not | M7a |
| 26 | Study note: Source a-crease-is-a-hinge's "about 200 thicknesses" and 30–40° Mylar figures | [web] [B](research/B-material-study-mechanics.md), "Unverified": the cited abstract states neither the scaling of `L*` as about 200 thicknesses nor the 30–40° Mylar rest angle in [a-crease-is-a-hinge.md:28-41](../docs/notes/a-crease-is-a-hinge.md) | Cite the passage, or mark them unverified | M0 |
| 31 | Task: Name a crease end by its point in `LineStopsOnTheModel` ([D20](decisions.md#d20-errors)) | [code] [ThroughLayers.hs:194-195](../src/Senbazuru/Origami/ThroughLayers.hs#L194-L195) starts the message with `creaseEndFlag` ([Query.hs:68-71](../src/Senbazuru/Fold/Query.hs#L68-L71)), which prints `--from` or `--to`; `grep -rn creaseEndFlag --include='*.hs' src app test study` finds it used only in `Query` and `ThroughLayers` (`:96`, `:195`) | Carry the point, as `CreaseEndMeetsNothing` does, and delete `creaseEndFlag` ([05 L6](05-prd-library-additions.md#l6-linestopsonthemodel-carries-its-point)); the pinned sentence changes as row 17 | before M4, with row 17 |

### 7.3 Settled without a new issue

| Item | What is wrong | Evidence | Settled by | When |
| --- | --- | --- | --- | --- |
| 8 | #96 says three papers and lists four | [issue]; [E1](research/E1-prior-art-sequence-languages.md), "D. The 2026 papers" [web] | Amend #96: four papers; COrigami stops at a crease pattern | M0, with row 9 |
| 15 | The blintz manifest and recipe fold corners opposite ways | [jq, code] [§6](#6-owner-decisions), decision 8 | Owner decision 8 | M2 |
| 18 | `quarter-fold-steps.fold` writes mountain and valley creases at angle 0, where the state rule would write `F` | [jq] `jq -c '[.edges_assignment, .edges_foldAngle] \| transpose \| map(select((.[0]=="M" or .[0]=="V") and .[1]==0)) \| length'` counts such creases: 4 on the [key frame](glossary-additions.md#the-fold-format) of `examples/quarter-fold-steps.fold`; the same filter over `.file_frames[]` prints 2, then 0. Migrating the file rewrites those creases and moves its goldens. | Owner decision 9 | M2 |
| 32 | The research note's count line says 7 of the crane's 12 some-layer steps hinge on existing creases; its own table marks 6 | [research] [gap-layer-selective-folds](research/gap-layer-selective-folds.md), "(e) The traditional crane, step by step" | Recorded in [D8](decisions.md#d8-folding-some-layers); the note is a snapshot and is not edited | — |

## Research links

- [gap-sequence-cost-and-test-budget](research/gap-sequence-cost-and-test-budget.md): "Summary".
- [gap-layer-selective-folds](research/gap-layer-selective-folds.md): "What exists"; "Re-deriving CraneWing by rule (script)"; "(e) The traditional crane, step by step"; "Unverified".
- [gap-exact-landmarks-and-macro-binding](research/gap-exact-landmarks-and-macro-binding.md): "A. How exact a landmark is today"; "B. Signatures, checked by hand"; "C. What can be certified, and how angles should be compared".
- [gap-study-consumption-contract](research/gap-study-consumption-contract.md): "(d) What guards each recipe", finding 20.
- [gap-assignment-at-rest-convention](research/gap-assignment-at-rest-convention.md): "D. Measurements".
- [gap-step-annotation-channel](research/gap-step-annotation-channel.md): "C. Turning over and the single camera".
- [D](research/D-docs-issues-constraints.md): "B. How the relevant open issues depend on each other — question (b)".
- [A2](research/A2-study-recipes-as-proto-dsl.md): F3.
- [E1](research/E1-prior-art-sequence-languages.md), [E2](research/E2-references-and-persistent-naming.md), [B](research/B-material-study-mechanics.md): the sections cited in §7.
