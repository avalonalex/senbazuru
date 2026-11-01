# 06 — Step diagrams: notes, arrow kinds, turn-over marks and captions

Written 2026-09-14 against `568dcb6` and reconciled on 2026-09-15 with
[decisions.md](decisions.md), the decision record every file in this series
follows; [00](00-overview.md) introduces the series and gives the reading order.
Research and requirements only: nothing here is implemented. A term is defined in
one clause and linked to [glossary-additions.md](glossary-additions.md) (the one
copy of every new term) or to [the glossary](../docs/glossary.md). *D1*–*D24* are
that record's numbered decisions, each cited as a link to its section, such as
[D7](decisions.md#d7-a-typed-step-note-reaches-the-page). *M0*–*M8* are
milestones, each a group of pull requests that leaves `main` working
([10 §1](10-roadmap-risks-questions.md#1-milestones)).

This file owns the **page**: how a *step note* reaches `Render.Steps`, what
`Diagram` gains to draw it, how arrows read under different views, where captions
go, and which golden files may move. It writes out
[D7](decisions.md#d7-a-typed-step-note-reaches-the-page) and the page's side of
[D5](decisions.md#d5-presentation-and-the-readers-side),
[D6](decisions.md#d6-crease-graphs-grow-between-frames),
[D22](decisions.md#d22-figures-holding-several-moves) and
[D24](decisions.md#d24-states-figures-and-their-numbers). What notes *mean* (the
reader's side, presentation, figures holding several moves) is
[02](02-language-semantics.md). The library functions the page calls
(`motionsAcross`, `creasesToCome`, `fitRigid`) are [05](05-prd-library-additions.md).
Test placement and budgets are [09](09-testing-and-acceptance.md).

## Summary

Today a page of steps is `stepPage`: it subtracts neighbouring frames and draws
one solid-headed arrow per moving piece of paper. From frames alone it cannot draw
a caption, tell a mountain arrow from a valley arrow, show a precrease or a
turn-over, or cope with a crease graph that grows between steps.

This PRD adds `stepPageWith`, taking a typed `StepNote` beside each frame.
`stepPage` becomes `stepPageWith` with notes that reproduce today exactly, so its
call lines and every tracked golden are untouched. S25 split it in two
([C136](decisions.md#changes-since-draft-v2)): `stepFigures` draws the figures, each with its note's caption, and
`Diagram.Page.fitPage` lays them out with their captions under them, since a
caption needs the page's scale, which `stepPageWith` was not given. Where this
PRD says `stepPageWith`, read `stepFigures`, and for a run's page, `runPage`. `Diagram` gains arrow heads
and bodies (defaults emit today's bytes) and two shapes, `Symbol` and `Fanned`
(§10). `Layout` places
captions. `Render.Sequence` builds the notes from a run's *move records*, one per
checked move ([glossary](glossary-additions.md#running-a-sequence)), beside the
states `Sequence.Record.writtenStates` gives, the same states the written file
holds ([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)).
Milestone M3 (`run -o x.svg`, the book-style page;
[10 §1](10-roadmap-risks-questions.md#1-milestones)).

That page also *fans* the layers of each flat figure (§10, owner decisions 65 and
66). Each vertex of the paper is drawn toward the page's lower left, a fixed
page-unit distance for each sheet lying over it, so the sheets under a flap peek
out from it while every fold stays one line. `render` fans only when asked, so
its bytes do not change.

## Problem and evidence

### What the page draws today, with real numbers

`examples/quarter-fold-steps.fold` holds three states of a unit square: flat,
folded in half, folded in quarters (the test fixture is identical, `cmp`).
`test/golden/quarter-fold-steps.svg` pins its step page with arrows
([`SvgSpec.hs:391-392`](../test/Senbazuru/Render/SvgSpec.hs#L391-L392), through
`stepPage` at [`:133`](../test/Senbazuru/Render/SvgSpec.hs#L133)).

The page has three *figures* (one drawing on a page of several,
[glossary](../docs/glossary.md#origami)). Figures count from 1, as the page numbers
them; states count from 0
([D24](decisions.md#d24-states-figures-and-their-numbers)), so figure *k* draws
state *k* − 1. **Which frame holds state *k* depends on the file.** This fixture's
key frame holds the flat sheet (`jq` prints 9 key-frame vertices and 2
`file_frames`), so its state 0 is the key frame and state *k* is
`file_frames[k − 1]`. A written sequence file's key frame holds no vertices, so
there state *k* is `file_frames[k]`; that is why
[D16](decisions.md#d16-testing-and-acceptance)'s first quarter-fold test pairs
written `file_frames[k]` with fixture state *k*.

Figure 1's arrow starts at `M 39.688 100`, which is 10 + 0.25 × 118.75: the margin
([`SvgSpec.hs:140-147`](../test/Senbazuru/Render/SvgSpec.hs#L140-L147)), plus the
arrow's model x times the page's one scale. That scale is 118.75 = 380 / 3.2: the
380-unit content width over three figures and two gutters of 0.1 figure each
([§8](#8-captions-and-the-gutter)). Three figures fill the width exactly, so x
needs no centring term; y does, which is why the figures' top edge is at 40.625
and not 10.

The arrow's x comes from the mean of the corners of the *faces* that move (a face
is one flat region between creases). A `python3` script on the fixture's `jq`
output, applying [`Step.hs:112-113`](../src/Senbazuru/Origami/Step.hs#L112-L113)
and [`:137-142`](../src/Senbazuru/Origami/Step.hs#L137-L142), gives:

| Figures | Moved vertices | Moved faces | Arrow from | Arrow to |
| --- | --- | --- | --- | --- |
| 1 → 2 | 0, 3, 7 | 2, 3 | (0.25, 0.5) | (0.75, 0.5) |
| 2 → 3 | 2, 3, 6 | 1, 2 | (0.75, 0.75) | (0.75, 0.25) |

`stepPage` picks **one** basis (the camera's axes) from every frame's vertices
([`Steps.hs:106-107`](../src/Senbazuru/Render/Steps.hs#L106-L107)), draws each frame
([`:118-122`](../src/Senbazuru/Render/Steps.hs#L118-L122)), adds `withArrows theme
basis (motionsBetween fr next)` to every figure but the last
([`:123-129`](../src/Senbazuru/Render/Steps.hs#L123-L129)) and lays them out with
`gridOf` ([`:110`](../src/Senbazuru/Render/Steps.hs#L110)). Its only instruction
input is one `Bool` ([`:98`](../src/Senbazuru/Render/Steps.hs#L98)).

### What two frames cannot say

A *valley fold* sinks away from the viewer and is drawn dashed; a *mountain fold*
rises towards the viewer, drawn dash-dot-dot
([glossary](../docs/glossary.md#origami)). A *fold angle* is 0 when flat and ±180°
when folded flat: positive for a valley, negative for a mountain, judged from the
front of the two faces it joins. A face's front is the side from which its corners,
in the order the file lists them (its *winding*,
[glossary](../docs/glossary.md#geometry)), run anticlockwise. Paper lying upside
down therefore records a fold the viewer sees as a valley as a mountain.

| Book mark | Why subtracting frames cannot find it | Evidence |
| --- | --- | --- |
| Mountain versus valley arrow | The second fold (figures 2 → 3 above, top half down) is one motion, yet edge 9 (`V`) goes 0 → +180 **and** edge 11 (`M`) goes 0 → −180 (`jq`). Both are one valley fold seen from above. Edge 11 ending at −180 under a valley fold looks like a typo and is not: the faces it joins, 2 and 3, were turned by the first fold and lie upside down (signed areas −0.25 in state 1, the fixture's `file_frames[0]`: their corners run clockwise seen from above, so they show their backs; `python3`). "Kind from the assignment that changed" ([#36](https://github.com/avalonalex/senbazuru/issues/36)) gives both answers. | [gap-step-annotation-channel](research/gap-step-annotation-channel.md) "B. What the fixture and goldens show", finding 10 |
| Fold and unfold (*precrease*, [glossary](glossary-additions.md#origami)) | Positions end where they started, so no motion is found | [`Step.hs:137-142`](../src/Senbazuru/Origami/Step.hs#L137-L142); research finding 2 |
| Turn over ([glossary](glossary-additions.md#origami)) | [#95](https://github.com/avalonalex/senbazuru/issues/95)'s half turn about x = 0 moves figure 3 from x∈[0.5, 1] to x∈[−1, −0.5], doubling the page's shared *extent* (the model region the page shows, [glossary](../docs/glossary.md#this-project)) and halving every figure. About the box centre, inference drew a spurious arrow of up to 0.0975 model units on the bird sequence until 05 L3 ([#523](https://github.com/avalonalex/senbazuru/issues/523)): `motionsBetween` now finds no motion between two frames that one proper rigid motion maps onto each other ([`Step.hs:102-109`](../src/Senbazuru/Origami/Step.hs#L102-L109)), so inference draws nothing for a turn-over, neither an arrow nor a loop. | research "C. Turning over and the single camera", findings 12–13 (`python3`) |
| A crease graph that grows | `motionsBetween` refuses frames whose `edges_vertices` differ ([`Step.hs:94-96`](../src/Senbazuru/Origami/Step.hs#L94-L96)). *Backfilling* (every frame carrying the final graph) shows creases too early: the golden's figure 1 draws y = 0.5, the **second** fold, half valley-dashed (`M 69.375 100 L 128.75 100`, edge 9) and half mountain (edge 11). | research finding 9 |
| Caption | `frame_title` names states: "Step 1: the flat sheet", "Step 2: folded in half", "Step 3: folded in half again" (`jq`). An instruction belongs to the figure **before** the fold ([`Step.hs:17-21`](../src/Senbazuru/Origami/Step.hs#L17-L21)). | research finding 11 |
| Several instructions, one figure | "Fold and unfold both diagonals" is one figure; a *step* holds several *moves* ([glossary](glossary-additions.md#words-the-prds-narrow)) | [D22](decisions.md#d22-figures-holding-several-moves), [02 §6.5](02-language-semantics.md#65-figures-holding-several-moves) |

The code says so too: books mark a turn-over "with a loop or a pair of arrows, and
senbazuru has neither"
([`CreasePattern.hs:584-591`](../src/Senbazuru/Render/CreasePattern.hs#L584-L591));
a diagram marking the next fold on a folded form "will have to face" which side
is seen ([`Style.hs:54-62`](../src/Senbazuru/Diagram/Style.hs#L54-L62)).

### What changing the API would cost

`grep -rn "stepPage\b" --include='*.hs' src app test study`, less the export,
imports, signature, definition and comments, left 23 call lines in 15 files on
2026-09-15 at `568dcb6`:

| Arrows on (`True`) | Arrows off (`False`) |
| --- | --- |
| `Cli.hs:968` (the flag) · `FlapSpec.hs:293`, `:313`, `:323` · `SvgSpec.hs:133` · `CraneGallery.hs:38` · `FlapGallery.hs:92` · `PetalGallery.hs:45` · `BlintzGallery.hs:39` · `HelmetGallery.hs:38` | `BirdSequenceSpec.hs:79` · `BasicBaseSpec.hs:216` · `StepsSpec.hs:46`, `:56`, `:57`, `:61`, `:62`, `:68`, `:69` · `CraneSpreadGallery.hs:158` · `WingBendingGallery.hs:56` · `BasicBaseGallery.hs:145` · `study/fold-material/Main.hs:279` |

(The research note's list omits `FlapGallery.hs:92`.)

At `4fe19a5` the same grep again leaves 23 call lines in 15 files, but not the
same 15. `BlintzGallery` and `HelmetGallery` no longer call `stepPage`:
`SequenceGallery`'s `pageSvg` draws both pages, with arrows
([`SequenceGallery.hs:150`](../study/fold-material/SequenceGallery.hs#L150)),
and `BlintzRunSpec` and `HelmetRunSpec` draw `checked-blintz.svg` and
`checked-helmet.svg` through it. The other new line is `WriteSpec`'s page,
also with arrows
([`WriteSpec.hs:126`](../test/Senbazuru/Sequence/WriteSpec.hs#L126)). Some of
the table's other lines have moved since `568dcb6`; they are left as measured
then.

## Goals

1. A page drawn from a sequence reads like a book: captions, arrows of the right
   kind per move, [fold-here lines](glossary-additions.md#step-pages) (the line
   a move is about to fold along, drawn on the figure before it), turn-over,
   rotate and repeat marks. On a page drawn from a run, the fold-here lines are
   every fold's and pre-crease's [hinge](glossary-additions.md#origami) (the
   line a move turns paper about, `recordHinge`), whether or not the paper is
   already creased there: the blintz run's sheet is creased along every fold it
   makes, so its six written states all have 12 edges (owner decision 74,
   [decisions §9](decisions.md#9-owner-decisions)). `render --steps` draws
   none, since `inferNote` carries `NoFoldLines` (§1, A1); `InferFoldLines`
   infers them from `creasesToCome` (05 L5) only for a `stepPageWith` caller
   that states the kind (S28,
   [#642](https://github.com/avalonalex/senbazuru/issues/642)).
2. Kinds, lines and marks come from move records, never from guessing at frames.
3. `render --steps`, every gallery and every tracked golden stay byte-identical.
4. A view flag changes how a step is drawn, never what it means.
5. On a page drawn from a run, or by `render --fan`, a figure of a flat fold shows
   how its paper is stacked: the sheets under a flap peek out from it, joined at
   their folds, and a face with nothing over any of its vertices stays where it
   lies (§10).

## Non-goals

- Persisting notes in FOLD (until [#73](https://github.com/avalonalex/senbazuru/issues/73); [D18](decisions.md#d18-non-goals), [00](00-overview.md#non-goals)); `render --steps` drawing `frame_title` ([§9](#9-frame_title-and-assurance-point-opposite-ways)).
- Drawing an `expect refused` outcome: it produces no record and no state, and `run --report` prints it ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused)).
- Font metrics and truncation: captions wrap by an estimated width instead
  (owner decision 7, §8; [decisions §9](decisions.md#9-owner-decisions), [10
  §6](10-roadmap-risks-questions.md#6-owner-decisions)); repeat leaders crossing
  cells.
- Drawing x-ray lines ([#48](https://github.com/avalonalex/senbazuru/issues/48)) or cut-aways ([#49](https://github.com/avalonalex/senbazuru/issues/49)); the note only carries their input.
- Settled illustrations on step pages ([D14](decisions.md#d14-material-consumption), [07](07-prd-material-consumption.md)); line drawing of bent surfaces ([08](08-prd-realistic-rendering.md)).

## Users and scenarios

1. **An author** runs `senbazuru run quarter.foldseq -o quarter.svg` and gets three
   captioned figures: a mountain arrow on 1, a valley arrow on 2, and on 3 the
   `closing` caption (the source's caption for the final state,
   [04](04-prd-sequence-source-and-cli.md#requirements) R-04-5), as
   [D24](decisions.md#d24-states-figures-and-their-numbers) walks through.
2. **The same author** adds `--view bottom`. The *reader's side* is the side of the
   model the sequence faces towards the reader
   ([glossary](glossary-additions.md#running-a-sequence)); seen from behind it,
   every valley and mountain head swaps, captions stay, and `run` warns once.
3. **A `render --steps --arrows` user** on an existing file gets today's bytes.
4. **The author** runs `senbazuru run helmet.foldseq -o helmet.svg`. Under each
   flap of the helmet base the edges of the sheets below show as fine lines 1.5 to
   4.5 page units apart, and each fold is one line. `run helmet.foldseq -o
   helmet.fold`, then `render helmet.fold --steps --fan`, draws the same paper
   without captions (§9).
5. **A study gallery author** keeps `stepPage`, or switches to `stepPageWith` to
   state kinds by hand.

## Requirements

**Channel**

- **R-06-1.** `Render.Steps` exports `stepFigures :: Theme -> Budget -> View ->
  [(Frame, StepNote)] -> Either StepError [(Diagram, Maybe Text)]`, with no `Bool`
  beside the notes ([D7](decisions.md#d7-a-typed-step-note-reaches-the-page)):
  each figure drawn with its note and paired with the note's caption, laid out
  by its caller, with `gridOf` or, for a page with captions,
  `Diagram.Page.fitPage`. S21 built `stepPageWith`, which laid the page out
  itself; S25 replaced it, since it could not lay out a caption without the
  page's scale ([C136](decisions.md#changes-since-draft-v2)).
- **R-06-2.** `stepPage`'s signature is unchanged and it is `stepPage theme budget
  grid view arrows = fmap (gridOf grid . map fst) . stepFigures theme budget view .
  map (\f -> (f, noteFor arrows))`, `noteFor True = inferNote`, `noteFor False =
  silentNote`, neither with a caption. One implementation; none of its call
  lines is edited.
- **R-06-3.** `StepError` is unchanged
  ([`Steps.hs:58-62`](../src/Senbazuru/Render/Steps.hs#L58-L62)), so the CLI's
  match at [`Cli.hs:969-977`](../app/Senbazuru/Cli.hs#L969-L977) compiles
  ([D7](decisions.md#d7-a-typed-step-note-reaches-the-page)). Every note is
  drawable. The new failures are not only `motionsAcross`'s and
  `creasesToCome`'s `FoldError` constructors
  ([05](05-prd-library-additions.md)): a page drawn from a run also calls
  `motionsBetween` (R-06-16), and reading a frame's material through
  `surfaceFromFrame` fails with a `SurfaceError`
  ([`Surface.hs:125`](../src/Senbazuru/Origami/Surface.hs#L125)), which no
  `FoldError` can carry: `Origami.Surface` imports `Fold.Query`, so `Fold.Query`
  cannot import it. How each reaches a page's refusal is M3's to settle, by S5
  ([#638](https://github.com/avalonalex/senbazuru/issues/638)) and S22
  ([#641](https://github.com/avalonalex/senbazuru/issues/641)), as
  [D7](decisions.md#d7-a-typed-step-note-reaches-the-page) says. S22 settled the
  paper's as `PageRefused`, named by the step that ended at the state
  ([C132](decisions.md#changes-since-draft-v2)); `motionsBetween`'s falls to
  S32 ([#643](https://github.com/avalonalex/senbazuru/issues/643)), and `SurfaceError`'s to S5.
- **R-06-4.** A presentation mark places a `Symbol` and suppresses inference on that
  pair only. `stepFigures` never transforms a coordinate: frames arrive presented.

**Diagram**

- **R-06-5.** `ArrowPath` gains a head (`SolidHead | HollowHalfHead |
  HollowDoubleHead`) and a body (`PlainBody | CleftTail`). `arrowFor`, the only
  construction site ([`Style.hs:364-372`](../src/Senbazuru/Diagram/Style.hs#L364-L372)),
  sets `SolidHead`/`PlainBody`, for which `Render.Svg` emits today's two paths.
  `Diagram` imports no FOLD type.
- **R-06-6.** `Shape` gains `Symbol`: a glyph whose geometry is in page units at one
  model-space anchor. `shapePoints` returns only the anchor; `mapShapePoints`
  moves only the anchor.
- **R-06-7.** The PR adding `Symbol` updates by hand the wildcard matchers the
  compiler cannot flag:
  [`LayoutSpec.hs:32-35`](../test/Senbazuru/Diagram/LayoutSpec.hs#L32-L35),
  [`:42-44`](../test/Senbazuru/Diagram/LayoutSpec.hs#L42-L44),
  [`CreasePatternSpec.hs:394`](../test/Senbazuru/Render/CreasePatternSpec.hs#L394).
  The PR adding `Fanned` (R-06-28) does the same for it, and for `unwrap`
  ([`CreasePatternSpec.hs:124-126`](../test/Senbazuru/Render/CreasePatternSpec.hs#L124-L126)),
  which passes through `Offset` only. The matchers the compiler can flag are
  flagged only weakly: `-Wall` reports a missing constructor as an
  `-Wincomplete-patterns` warning, nothing sets `-Werror`
  ([`senbazuru.cabal:145-153`](../senbazuru.cabal#L145-L153)), and Stack
  compiles a module only when its source or flags change, so only a build from
  `stack clean` guarantees the warning shows ([AGENTS.md](../AGENTS.md),
  "Style"); each of these PRs builds from there. Two kinds of matcher that
  never warn are missing from the lists above. The list comprehensions that keep
  only `Offset`s, at
  [`CreasePatternSpec.hs:259`](../test/Senbazuru/Render/CreasePatternSpec.hs#L259),
  [`:281`](../test/Senbazuru/Render/CreasePatternSpec.hs#L281),
  [`:302`](../test/Senbazuru/Render/CreasePatternSpec.hs#L302),
  [`:329`](../test/Senbazuru/Render/CreasePatternSpec.hs#L329) and
  [`LayoutSpec.hs:99`](../test/Senbazuru/Diagram/LayoutSpec.hs#L99), pass over a
  `Fanned` drawn in place of an `Offset`; the PR adding `Fanned` updates them.
  `LayoutSpec`'s `labels` (above) and `StepsSpec`'s `labelsOf`
  ([`StepsSpec.hs:97-98`](../test/Senbazuru/Render/StepsSpec.hs#L97-L98)) could
  not see a caption wrapped in an `Offset` (R-06-18); the PRs that place captions
  update them. S24 updated `labels` (C134), and S25 `labelsOf` ([C136](decisions.md#changes-since-draft-v2)).

**Views**

- **R-06-8.** `seenFrom :: Basis -> SeenFrom` gives `FromReadersSide`,
  `FromOppositeSide` or `EdgeOn` as `basisForward`'s z is negative, positive or
  zero. `EdgeOn` means the camera looks along the sheet's plane, as `front` and
  `side` do, so a flat sheet projects to a line. `pageSide :: View -> [Frame] ->
  Either StepError SeenFrom` shares `stepFigures`' basis choice. The test is
  not new: `Render.CreasePattern` already makes it, privately, as `seenFromAbove
  :: Basis -> Bool`, `basisForward`'s z ≤ 0
  ([`CreasePattern.hs:431-432`](../src/Senbazuru/Render/CreasePattern.hs#L431-L432)),
  which counts edge-on as above. Rewritten over `seenFrom`, it keeps that
  answer.
- **R-06-9.** Stated kinds are drawn as seen: from the opposite side valley and
  mountain swap, in arrow heads and fold-here dashes alike; unfold and push do not
  change; edge-on draws the stated kind and puts an `EdgeOnMark` on each figure.
  Captions are never rewritten.
- **R-06-10.** `run -o x.svg` warns once when `pageSide` is `FromOppositeSide`. No
  `View` is an argument of `runSequence`, `writeSequence` or `stepNotes`, so the
  frames `run -o x.fold` writes are the frames every `--view` draws.

**Turn-over and rotate**

- **R-06-11.** A turn-over loop lies across the turn's axis as projected through the
  page basis, anchored where that projected axis leaves the figure's own extent at
  its lower end (its right end when the projection is horizontal). When the
  projected axis is shorter than 1e-6 × max(1, the figure's larger side), the loop
  is drawn as if the axis were page-vertical (§5,
  [D7](decisions.md#d7-a-typed-step-note-reaches-the-page)).
- **R-06-12.** On `top` and `bottom` pages with roll a multiple of 90°, a turn-over
  or half turn keeps each figure's extent and the page union (the one box
  covering every figure's extent, which sets the scale,
  [`Layout.hs:110-112`](../src/Senbazuru/Diagram/Layout.hs#L110-L112)) within
  1e-12 × `modelSpan` (the model's size), and the scale within 1e-12 of itself,
  since a scale is page units per model unit. Nothing is asserted for other
  views or rolls. `StepsSpec` tests it on today's `stepPage`, as A7 and A8
  ([decisions C129](decisions.md#changes-since-draft-v2)).
- **R-06-13.** Rotate marks show signed eighths; repeat marks show a figure range;
  both are `Symbol`s inside their figure.

**Growing graphs**

- **R-06-14.** For `InferArrows` and `InferArrowsAs`, `stepFigures` calls
  `motionsAcross` alone, which returns `motionsBetween` when the graphs are equal
  (R-05-16): only `motionsAcross` decides whether two graphs are equal
  ([C139](decisions.md#changes-since-draft-v2)).
- **R-06-15.** Fold-here lines go on the figure before the move, at `before`
  positions, styled by the note's kind as seen, never by the crease's assignment.

**Several moves**

- **R-06-16.** For each moving record of a step, in order, `Render.Sequence`
  gives that record's arrows, with the kind of its move as written, from
  `motionsBetween` over its before surface under `displayBefore` and its after
  surface under `displayAfter`. Those are the record's presentation composed
  with its anchor placement, before and after the move, which the record keeps
  as separate fields and applies to its unpresented surfaces
  ([D14](decisions.md#d14-material-consumption); [01
  §2.2](01-architecture.md#22-contract-1-moverecord)). That kind is not the
  record's `MoveKind`
  ([`Record.hs:260`](../src/Senbazuru/Sequence/Record.hs#L260)), which holds no
  [sense](glossary-additions.md#running-a-sequence) (valley or mountain):
  `Turn` covers a fold and an unfold alike, and `Precrease` carries none.
  The sense as written is kept only in `recordOrigin`, and `Sequence.Record`
  exports no `Sense`, `PageAxis` or `Turning`; how a page reads them is S17's
  ([#640](https://github.com/avalonalex/senbazuru/issues/640)). A move whose
  moving paper is two groups joined only through still paper gets one arrow per
  group, as `motionsBetween` already splits them
  ([`Step.hs:175-192`](../src/Senbazuru/Origami/Step.hs#L175-L192);
  [D7](decisions.md#d7-a-typed-step-note-reaches-the-page)). A pre-crease's
  before and after surfaces are one flat state, so its arrows come from its
  folded surface: the arrow out from its before surface to the surface its fold
  reached, both under `displayBefore`, and the unfold arrow the same pair
  reversed. The runner has that surface, as the after of the turn's record
  ([`Run.hs:697-699`](../src/Senbazuru/Sequence/Run.hs#L697-L699)), until
  `asPrecrease` sets the after to the before
  ([`Record.hs:518`](../src/Senbazuru/Sequence/Record.hs#L518)). By the
  decision record's choice, not the owner's, the `Precrease` record keeps it
  behind one accessor (**SKETCH** `recordFoldedPose`; S18c,
  [#640](https://github.com/avalonalex/senbazuru/issues/640)). `recordPoseAt`,
  `PoseOnRoute` and `Origami.Route` do not exist ([decisions
  C90](decisions.md#changes-since-draft-v2)).
- **R-06-17.** A pre-crease draws its fold arrow, with the sense the author wrote,
  its unfold arrow and one fold-here line, although its figure's frames are
  identical in position ([D7](decisions.md#d7-a-typed-step-note-reaches-the-page)).
  Nothing is read from its crease, which has no direction
  ([D12](decisions.md#d12-the-text-syntax)).

**Captions**

- **R-06-18.** Captions are `Label`s placed by `Layout` under the cell's shared
  box (the union of every figure's extent, in which each figure is centred,
  [`Layout.hs:110-112`](../src/Senbazuru/Diagram/Layout.hs#L110-L112),
  [`:137`](../src/Senbazuru/Diagram/Layout.hs#L137)), left-aligned with the
  cell, at the theme's label size. Each is wrapped at word boundaries into lines
  no wider on the page than the shared box, the same for every figure on the
  page: w × s page units for a box w model units wide drawn at scale s. Widths
  are estimated at 0.55 em a character, an em being the type size, so 7.7 page
  units at 14, since the backend has no font metrics; a word longer than a line
  keeps a line of its own. Line k, counted from 0, is a `Label` at the box's bottom-left
  corner, moved down a + k p page units by an `Offset`, with a and p as in
  R-06-19 (owner decision 7, decided 2026-10-28; §8).
- **R-06-19.** `gridOf`'s output is unchanged, and a page with no caption is laid
  out as today: its rows are `gridGutter`
  ([`Layout.hs:73`](../src/Senbazuru/Diagram/Layout.hs#L73)) of a figure apart,
  with no trailing gutter, so no existing page changes. On a page where some
  figure has a caption, columns stay `gridGutter` apart, and below each row r,
  the last included, lies a band of b_r = a + (L_r − 1) p + d page units in
  place of the gutter. L_r is the most lines any caption in row r wraps to, and
  1 for a row with none; p = 1.2 × the type size is the line pitch; a = 18 is
  the first baseline's drop below the figure's box; and d = 14 holds the
  descent and the gap before the next row (constants set by S24,
  [C134](decisions.md#changes-since-draft-v2), §8). `Layout` has no page units
  of its own, so it takes the page's scale s, as a `PageScale`, from the caller
  that knows the page, and turns each band into model units, b_r / s, itself:
  the wrap that decides L_r needs s too, and the rows the bands follow are the
  layout's own (`gridOfCaptioned`, built by S24, C134; §8).

**Pages from a run**

- **R-06-20.** `Render.Sequence.stepNotes :: Run -> Either SequenceError
  [(Frame, StepNote)]` returns exactly the frames `Sequence.Write` writes to
  `file_frames`, in order, because both take them from
  `Sequence.Record.writtenStates`
  ([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)). It is not
  total: it shares `writtenStates`' refusals
  ([`Record.hs:713`](../src/Senbazuru/Sequence/Record.hs#L713)), each a
  `WriteRefused` naming the state, with `WriteMissingAngles` or
  `WriteNonFinite`, the second for a material coordinate that is not finite
  ([`Record.hs:788`](../src/Senbazuru/Sequence/Record.hs#L788);
  [D4](decisions.md#d4-written-frames-follow-the-state-rule)).
- **R-06-21.** Figure *j* draws state *j* − 1 and its note follows
  [§2](#2-from-a-run-to-notes). Its caption is the caption of the step that starts
  from that state, which is the state's `frame_title`: on the last figure,
  `closing` ([D24](decisions.md#d24-states-figures-and-their-numbers)), or on a
  run stopped at `not modelled`, the caption of the step it stopped at
  ([`Record.hs:723`](../src/Senbazuru/Sequence/Record.hs#L723)). That step's
  moves made before the stop keep their records in `runRecords`
  ([`Run.hs:513`](../src/Senbazuru/Sequence/Run.hs#L513)), though no state
  shows their paper, so the page drops them. S25 draws the captions:
  `stepNotes` takes each from its state's `frame_title`, so the rule lives
  once, in `writtenStates` ([C136](decisions.md#changes-since-draft-v2)).
- **R-06-22.** A `mark` is labelled on each flat figure where `Origami.Visible`
  shows its material point.
- **R-06-23.** A step's authored `sample` poses are figures of their own, after the
  figure of the state the step starts from and before its end state's, in parameter
  order, each with no caption and `NoArrows`. A step that writes no state (every
  move `expect refused`) has no figure, and its caption is under none (S25,
  [C136](decisions.md#changes-since-draft-v2))
  ([D24](decisions.md#d24-states-figures-and-their-numbers),
  [D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused)).

**Fanned layers** (§10; owner decisions 65 and 66,
[decisions §9](decisions.md#9-owner-decisions); the numbers and names marked
**SKETCH** are this record's, not the owner's)

- **R-06-24.** A flat figure's fan counts come from 05 L16's `fanCounts`, for the
  side the page is seen from. A vertex's count is the least, over the faces with
  a corner at it, of the fewest faces nearer the viewer than that face over any
  point of it near the vertex.
- **R-06-25.** A fanned figure draws each vertex min(count, 6) × 1.5 page units
  toward the page's lower left, (−1, +1)/√2 in page axes, since page y grows
  downwards (the cap and the step **SKETCH**). Arrows, fold-here lines, `Symbol`s,
  `Label`s and captions are placed on true positions and are not fanned.
- **R-06-26.** A figure is drawn unfanned, and the page is still drawn (R-06-3),
  when it is not flat, has no face orders, is seen edge-on, or when its fan counts
  or its visible form cannot be had: an unordered pair, a cycle, a twist with no
  order to paint in, a concave face.
- **R-06-27.** A fanned figure is painted by the offset view's painter
  ([`CreasePattern.hs:277-422`](../src/Senbazuru/Render/CreasePattern.hs#L277-L422))
  with a displacement per point instead of per layer. It paints layer by layer
  from `layerDepths`, at most two merged fills per layer, then the layer's
  creases at `themeBuriedWidth` (a third of a crease's width), then the layer's
  full-weight stretches from `Origami.Visible.formSheetEdges`. A point moves by
  its own vertex's displacement. A point along a stretch, or a merged ring's
  point that is no vertex, moves by the displacements of the two vertices of the
  face edge it lies on, mixed by where it lies between them. The offset view is
  the case where every point of a face moves by its layer times `layerStep`.
- **R-06-28.** `Shape` gains `Fanned` (**SKETCH**): a polyline or a fill whose
  every point is paired with its own page-unit displacement, so the two cannot
  fall out of step. `Offset d s` is `Fanned` with every displacement `d`, and both
  emit the same bytes. `shapePoints` returns the points alone and
  `mapShapePoints` moves only the points, as for `Offset`. `Render.Svg` keeps
  each displacement with its own point when it drops a ring shorter than three
  points or turns a ring round.
- **R-06-29.** The theme carries the choice. `themeLayerOffset` becomes
  `themeLayers`, one of laid flat, offset by a distance, or fanned by a step and
  a cap (**SKETCH**), so no theme asks for both. `run -o x.svg` passes a fanning
  theme to `stepFigures`, whose signature (R-06-1) and `stepPage`'s call lines
  (R-06-2) do not change; `--no-fan` ([04](04-prd-sequence-source-and-cli.md)
  R-04-27, **SKETCH**) passes an unfanned one. `render --fan` (**SKETCH**) fans
  every flat folded frame `render` draws: `--fold`, a folded frame chosen by
  `--frame`, and `--steps`. It is refused with `--offset`, does nothing under
  `--no-fill` (which asks for no layer order, as for `--offset`), and is refused
  with W1's `--lines` as `--offset` is ([08](08-prd-realistic-rendering.md)
  R-08-21). Every golden of this file but this section's two new ones is drawn
  unfanned.

## Design

### 1. The channel

**SKETCH:**

```haskell
-- Senbazuru.Diagram.Style: kind to ink, the one file to open when marks look wrong
data ArrowKind = ValleyArrow | MountainArrow | UnfoldArrow | PushArrow  -- as seen from the reader's side
withKind       :: ArrowKind -> ArrowPath -> ArrowPath                   -- sets head and body only
foldLineStroke :: Theme -> ArrowKind -> Stroke                          -- valley or mountain dash

-- Senbazuru.Render.Steps
data Arrows    = InferArrows | InferArrowsAs !ArrowKind | GivenArrows ![(ArrowKind, V3, V3)] | NoArrows
data FoldLines = NoFoldLines | InferFoldLines !ArrowKind | GivenFoldLines ![(ArrowKind, V3, V3)]
data PresentationChange
  = TurnedOver !V3 !V3        -- a point on the axis and its direction, written coordinates
  | Rotated !Int !V3          -- signed eighths, anticlockwise from the reader's side; a point on the axis
data StepNote = StepNote
  { noteCaption      :: !(Maybe Text),
    noteArrows       :: !Arrows,
    notePresentation :: !(Maybe PresentationChange),
    noteRepeat       :: !(Maybe (Int, Int)),   -- figure numbers, from 1 as Layout counts
    noteLayers       :: !(Maybe [[V3]]),       -- selected layers' rings at before positions (#48, #49)
    noteFoldLines    :: !FoldLines,
    noteMarks        :: ![(Text, V2)] }        -- label and material point (below)
inferNote, silentNote :: StepNote            -- InferArrows / NoArrows; every other field empty
data SeenFrom = FromReadersSide | FromOppositeSide | EdgeOn
```

Positions are in the *written frame*'s coordinates, already presented
([glossary](glossary-additions.md#the-fold-format)), and the page projects them
through its one basis as `withArrows` projects a motion
([`CreasePattern.hs:592-604`](../src/Senbazuru/Render/CreasePattern.hs#L592-L604)).
`inferNote` carries `NoFoldLines`: equal graphs have no creases to come, and a
default that could draw them is one more thing to leak into today's bytes.
`noteMarks` holds each mark's label and [material
point](glossary-additions.md#references), where the mark lay on the flat sheet,
because M3 includes marks (owner decision 75) and
[D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot) labels
a mark on each figure where it is visible
([D7](decisions.md#d7-a-typed-step-note-reaches-the-page); [02
§4.5](02-language-semantics.md#45-landmarks-mark-let-step-names)). The material
point is the decision record's choice, not the owner's: a position would not
do, since two faces folded onto one point share it, and only a material point
says which of them the mark is on.

`TurnedOver` and `Rotated` are placeholders. `Sequence.Record` already exports
constructors of those names, `Presenting`'s
([`Record.hs:286-291`](../src/Senbazuru/Sequence/Record.hs#L286-L291)), and
`Render.Sequence` imports both modules, so S21
([#641](https://github.com/avalonalex/senbazuru/issues/641)) names them
`PageTurnedOver` and `PageRotated` ([C131](decisions.md#changes-since-draft-v2)). S29
([#642](https://github.com/avalonalex/senbazuru/issues/642)) adds
`PresentationChange` with `PageTurnedOver`, and S30 adds `PageRotated`.

### 2. From a run to notes

A *sequence file* ([glossary](glossary-additions.md#the-fold-format)) is a
metadata-only key frame followed by its states, numbered from 0 by their
`file_frames` index: the start state, then, for each step that writes one, its
authored `sample` poses in parameter order and its end state
([D4](decisions.md#d4-written-frames-follow-the-state-rule),
[D24](decisions.md#d24-states-figures-and-their-numbers)).
[01 §5.9](01-architecture.md#59-the-written-frame-and-the-page-note) writes three
for the two-step quarter fold. Figure *j* draws state *j* − 1, and a step's caption
and arrows go on the figure of the state it starts from. With no samples and no
step that writes nothing, N steps make N + 1 figures and figure *k* carries step
*k*'s instruction. Once a step writes samples or nothing, figure numbers and step
numbers part, which is why messages say "step N (name)" and never "figure N".

`Render.Sequence` is a renderer, so the only sequence modules it may import are
`Sequence.Record` and `Sequence.Error` ([decisions §2](decisions.md#2-shape),
row 7). It reads the `Run` that `Sequence.Record` defines, the records and each
step's outcome, never the runner's working state, and takes its frames from
`Sequence.Record.writtenStates`, which `Sequence.Write` also calls. So R-06-20
holds by construction, and `stepNotes` returns `Either SequenceError` because
`writtenStates` can refuse, with that type
([`Record.hs:713`](../src/Senbazuru/Sequence/Record.hs#L713)): a state it cannot
write is `WriteRefused k`, holding `WriteMissingAngles` or `WriteNonFinite`
([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)).

| Step holds | Note on the figure of the state the step starts from |
| --- | --- |
| Moves that turn paper (fold, unfold, macro) | `GivenArrows` per R-06-16; `GivenFoldLines` from each fold's hinge (`recordHinge`), whether or not the move creased it, at `recordBefore` positions (the record's surface before the move) under `displayBefore`, styled by the move's sense as seen (owner decision 74, §6). An unfold draws none, by the decision record's reading of decision 74, which names folds and pre-creases; S33 ([#643](https://github.com/avalonalex/senbazuru/issues/643)) asks the owner to confirm it |
| `anchor P` (an `Anchoring` record, evidence `NoMotion`) | No arrow and no fold-here line: it moves no paper, has no hinge and creases nothing, and the model stays where it stood on the page ([`Record.hs:551-556`](../src/Senbazuru/Sequence/Record.hs#L551-L556), [`Run.hs:568-571`](../src/Senbazuru/Sequence/Run.hs#L568-L571)) |
| `mark` | Caption, `NoArrows`: a mark moves no paper. It is labelled through `noteMarks` (§1) on the figures R-06-22 names. M3 runs `mark` for the point forms the resolver already evaluates on the sheet (owner decision 75); until S20 ([#640](https://github.com/avalonalex/senbazuru/issues/640)) the runner refuses it as not run yet ([`Run.hs:584`](../src/Senbazuru/Sequence/Run.hs#L584)). `meet`, and a mark used as a reference, stay not run yet until M4 ([`Resolve.hs:174`](../src/Senbazuru/Sequence/Resolve.hs#L174), [`:176`](../src/Senbazuru/Sequence/Resolve.hs#L176)) |
| `pre-crease` | One record: a valley or mountain arrow out, the sense the author wrote, from its before surface to its folded surface (§7), and an unfold arrow back, the same pair reversed, both under `displayBefore` (R-06-16, owner decision 14); and its hinge's fold-here line, as a fold's (owner decision 74) |
| `turn over` / `rotate` | `notePresentation`. The record keeps the turn as written (`Presenting`, [C82](decisions.md#changes-since-draft-v2)), so the direction comes from which turn it was (`left-right` along y, `top-bottom` along x, `rotate` along z); see [Dependencies](#dependencies). No record stores the axis point: the centre of the displayed state before the turn, `recordBefore` under `displayBefore`, with cz the middle of its z range ([D5](decisions.md#d5-presentation-and-the-readers-side); [02 §5.2](02-language-semantics.md#52-presentation-moves-no-paper)). The runner finds it with its private `middleOf` ([`Run.hs:302`](../src/Senbazuru/Sequence/Run.hs#L302)) and exports `turnOverAbout` for `StepsSpec`'s turn tests, A7 and A8 ([decisions C129](decisions.md#changes-since-draft-v2)); how the page gets the point is S18b's ([#640](https://github.com/avalonalex/senbazuru/issues/640)) |
| A fold then a turn | The fold's arrows and the turn's mark. A step may end with one turn-over or rotate, and nothing may follow it in the same step (owner decision 78), so a figure carries at most one presentation mark |
| `repeat A..B` (M4, [decisions §8](decisions.md#8-milestones)) | `noteRepeat` with those figures, plus the expanded moves' arrows ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused)) |
| `checkpoint` (M4) | `NoArrows`: the pair breaks the *prefix rule*, under which each frame's vertex list begins with the previous frame's, with equal material coordinates, so ids carry over ([D6](decisions.md#d6-crease-graphs-grow-between-frames), [D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused); [05 L5](05-prd-library-additions.md#l5-motionsacross-creasestocome-and-a-non-convex-point-test), [02 §9](02-language-semantics.md#9-repeat-checkpoint-not-modelled-expect-refused)) |
| `not modelled` | Caption, `NoArrows`. The run stops there and keeps every state before it, so this is the last figure ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused)) |
| `expect refused` | Nothing. It is a move inside a step that produces no record and no state; its outcome is kept in the run's `runExpected`, with its step ([C96](decisions.md#changes-since-draft-v2)), and printed by `run --report`, never drawn. A step whose moves are all `expect refused` writes no state, so it has no figure and its caption is drawn nowhere ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused), [D24](decisions.md#d24-states-figures-and-their-numbers)) |
| A macro's authored `sample` poses (M5) | Nothing on this figure. Each pose is a state and a figure of its own, between this figure and the end state's, with no caption and `NoArrows` (R-06-23). A macro with no `sample` adds no figure: the interior poses the runner also checks, `RunSettings.macroChecks` of them, are evidence, not states ([D9](decisions.md#d9-macro-moves-as-named-angle-relations)) |

**A record's kind is not an arrow's kind.** `MoveKind` is `Turn`, `Precrease`,
`Presentation` or `Anchoring`
([`Record.hs:260-278`](../src/Senbazuru/Sequence/Record.hs#L260-L278)). `Turn`
covers a fold and an unfold alike, and `Precrease` carries no sense, so neither
says whether an arrow is valley, mountain or unfold. The sense as written is
kept only in `recordOrigin`, and `Sequence.Record` exports no `Sense`,
`PageAxis` or `Turning`
([`:110-165`](../src/Senbazuru/Sequence/Record.hs#L110-L165)). How the page
reads them is S17's to decide
([#640](https://github.com/avalonalex/senbazuru/issues/640)).

### 3. Arrow heads, bodies and `Symbol`

The heads follow Robert Lang's diagramming conventions as summarised in research
finding 20: solid head = valley (today's), hollow one-sided head = mountain,
hollow two-sided head = unfold, cleft tail = push. Nothing at M3 pushes paper
in: the parser refuses `sink` as a move the language cannot express yet
([`Parse.hs:260`](../src/Senbazuru/Sequence/Parse.hs#L260)). So `PushArrow` (§1)
and `CleftTail` have no producer at M3, and S11
([#639](https://github.com/avalonalex/senbazuru/issues/639)) defers them, with
push and sink, to [#648](https://github.com/avalonalex/senbazuru/issues/648) in
its C row. Emission, **SKETCH**, with `headLength` clamped as at
[`Svg.hs:225`](../src/Senbazuru/Render/Svg.hs#L225): `SolidHead` is today's
filled triangle path byte for byte; `HollowHalfHead` is one stroked open line
from `base` through `tip` to `base + half·across`, in `Svg.hs`'s names
([`:217-227`](../src/Senbazuru/Render/Svg.hs#L217-L227)): from the point one
head-length back from the tip, to the tip, and back to the barb's end, 0.4 of a
head-length to one side of `base`. It starts at `base` because the curve stops
there ([`:226`](../src/Senbazuru/Render/Svg.hs#L226),
[`:231`](../src/Senbazuru/Render/Svg.hs#L231)), where the filled head takes
over, and a barb from `tip` alone would leave the shaft's last head-length
undrawn. `HollowDoubleHead` is a stroked closed triangle. Neither hollow head
sets `fill`, so the group's `fill="none"` holds.

```haskell
-- Senbazuru.Diagram (SKETCH), still FOLD-ignorant
data Glyph = TurnOverLoop !V2 | RotateMark !Int | RepeatMark !Int !Int | EdgeOnMark
data Shape = … | Symbol !Stroke !Double !V2 !Glyph   -- stroke, page-unit size, model anchor, glyph
           | Fanned …                               -- points paired with page-unit displacements (§10, R-06-28)
```

A symbol is sized in page units because a loop sized to the model would change
printed size with the column count, the units bug recorded at
[`Layout.hs:38-45`](../src/Senbazuru/Diagram/Layout.hs#L38-L45).

`TurnOverLoop`'s vector is in the same frame as the anchor: the axis direction
projected through the page basis onto (right, up), so **y up**. `Render.Svg`
negates its y, as it does for every model coordinate, but does not scale it,
because the loop's size is in page units. Beside `Offset`, whose displacement is
y-down ([`Diagram.hs:202-221`](../src/Senbazuru/Diagram.hs#L202-L221)), that reads
as a sign error; it is deliberate. `Offset`'s nudge is authored in page units; the
loop's vector is computed from model geometry, and turning it y-down in
`Render.Steps` would put a y-flip in a second place (AGENTS.md, "Three y-flips,
each in one place"). `mapShapePoints` leaves the vector alone, which is right only
because its one caller translates
([`Layout.hs:142`](../src/Senbazuru/Diagram/Layout.hs#L142)); the haddock says so.

`-Wincomplete-patterns` flags `shapePoints`, `mapShapePoints`, `shapeToSvg` and
`CreasePatternSpec`'s `kind`
([`:103-111`](../test/Senbazuru/Render/CreasePatternSpec.hs#L103-L111)), but
only as a warning: `-Wall` turns it on, the cabal file sets no `-Werror`
([`senbazuru.cabal:145-153`](../senbazuru.cabal#L145-L153)), and a warning
prints only when its module is compiled, which only a clean build guarantees
(AGENTS.md, "Style"). It cannot flag the three wildcards of R-06-7; `isArrow`
there would silently pass a loop drawn in place of an arrow. Nor can it flag a
pattern used as a filter. The comprehensions that keep `Offset` alone
([`CreasePatternSpec.hs:259`](../test/Senbazuru/Render/CreasePatternSpec.hs#L259),
[`:281`](../test/Senbazuru/Render/CreasePatternSpec.hs#L281),
[`:302`](../test/Senbazuru/Render/CreasePatternSpec.hs#L302),
[`:329`](../test/Senbazuru/Render/CreasePatternSpec.hs#L329);
[`LayoutSpec.hs:99`](../test/Senbazuru/Diagram/LayoutSpec.hs#L99)) skip a
`Fanned` shape. `StepsSpec`'s `labelsOf` matched a bare `Label`, so it missed a
caption line moved by an `Offset` (R-06-18); `LayoutSpec`'s `labels` sees one
since S24 (C134), and `labelsOf` since S25
([C136](decisions.md#changes-since-draft-v2)).

### 4. Which side the page is seen from

The reader's side is +z of the displayed model, so +z of every written frame. A
basis looks along `basisForward`
([`Camera.hs:91-98`](../src/Senbazuru/Render/Camera.hs#L91-L98)) and sees +z when
that vector's z is negative:

| Basis | Looks along | Seen from |
| --- | --- | --- |
| `top` ([`Camera.hs:106-107`](../src/Senbazuru/Render/Camera.hs#L106-L107)) | (0, 0, −1) | reader's side |
| `bottom` ([`:120-121`](../src/Senbazuru/Render/Camera.hs#L120-L121)) | (0, 0, 1) | opposite |
| `iso` ([`:135-136`](../src/Senbazuru/Render/Camera.hs#L135-L136)) | (−1, 1, −1) | reader's side |
| `front`, `side` ([`:140-145`](../src/Senbazuru/Render/Camera.hs#L140-L145)) | (0, 1, 0), (−1, 0, 0) | edge-on |
| Blintz and crane galleries (its `galleryViewDirection`, [`BlintzGallery.hs:25`](../study/fold-material/BlintzGallery.hs#L25); [`CraneGallery.hs:37`](../study/fold-material/CraneGallery.hs#L37)) | (−1, 0, 1), (−1, 1, √2) | opposite |

A roll leaves `basisForward` alone
([`Camera.hs:227-235`](../src/Senbazuru/Render/Camera.hs#L227-L235)), so rolling
never flips a head. The `top` and `bottom` rows are why kinds are stated from the
reader's side and only drawn as seen: if "valley" meant "as the camera sees it",
one source would write different FOLD signs under `--view bottom` and `--view top`,
which [D5](decisions.md#d5-presentation-and-the-readers-side) forbids
([02 §5.4](02-language-semantics.md#54-render-options-never-change-meaning)). The
gallery row shows the opposite side is not hypothetical, and those two galleries
are not alone: underside views in the basic-base, petal and bird galleries draw
from it too
([`BasicBaseGallery.hs:59`](../study/fold-material/BasicBaseGallery.hs#L59),
[`PetalGallery.hs:44`](../study/fold-material/PetalGallery.hs#L44),
[`Main.hs:264`](../study/fold-material/Main.hs#L264)), and so does the golden
`bird-sequence-bottom.svg`
([`BirdSequenceSpec.hs:71-72`](../test/BirdSequenceSpec.hs#L71-L72)).

`SeenFrom` is not a new question. `CreasePattern` already asks it, privately, as
`seenFromAbove`
([`CreasePattern.hs:431-432`](../src/Senbazuru/Render/CreasePattern.hs#L431-L432)),
a `Bool` that counts edge-on as above; `SeenFrom` gives edge-on an answer of its
own.

### 5. Turn-over and rotate marks, and the page extent

The runner turns the model about a **model-intrinsic** axis through the centre of
the current bounding box; `left-right` is (x, y, z) ↦ (2cx − x, y, 2cz − z)
([02 §5.2](02-language-semantics.md#52-presentation-moves-no-paper),
[D5](decisions.md#d5-presentation-and-the-readers-side)). The page receives frames
already turned and the axis in `TurnedOver`, and draws the loop on the figure
before the turn. Under `top` with no roll a `left-right` axis is page-vertical, so
the loop lies horizontal at the midpoint of the figure's bottom edge (Lang's
side-to-side flip, research finding 20); under `iso` the projected axis, and the
loop, slant.

**An axis that projects to a point.** Under `front` a `left-right` axis points at
the viewer, so its projection has no direction to lie across. When the projection
is shorter than 1e-6 × max(1, the figure's larger side), the cut-off `withArrows`
already uses
([`CreasePattern.hs:596-597`](../src/Senbazuru/Render/CreasePattern.hs#L596-L597)),
the loop is drawn as if the axis were page-vertical: horizontal, at the midpoint of
the figure's bottom edge ([D7](decisions.md#d7-a-typed-step-note-reaches-the-page);
A17). The figure already carries `EdgeOnMark`.

**Extent, measured.** A `python3` script on `examples/bird-base-sequence.fold`
(run on 2026-09-14, and again on 2026-09-15 with the same output): take
`file_frames[13]` ("Second petal · underside · close sides · hinge 150°"), apply
the `left-right` rule, and project both through the `topDown` and `isometric`
directions of `Camera.hs:106-136`, rolled as `turnedBy` rolls:

| Page | Figure extent before | After | Unchanged? |
| --- | --- | --- | --- |
| `top`, roll 0 | 0.7058 × 0.7058 | 0.7058 × 0.7058 | yes |
| `top`, roll 90° | 0.7058 × 0.7058 | 0.7058 × 0.7058 | yes, to 2.2e-16 |
| `top`, roll 45° | 0.9981 × 0.4142 | 0.4142 × 0.9981 | **no** |
| `iso` | 0.4142 × 0.6118 | 0.9981 × 0.3335 | **no** |

These are the numbers [D5](decisions.md#d5-presentation-and-the-readers-side)
records. **Which count "13" is:** the `file_frames` index, from 0, so the bird
sequence's state 13 in [D24](decisions.md#d24-states-figures-and-their-numbers)'s
numbering, which `render --frame 14` draws, because `--frame 0` is the key frame
([D13](decisions.md#d13-the-run-verb-and-io)). `jq` prints 16 `file_frames` and 0
key-frame vertices for this file, and `file_frames[11]` is "… hinge 90°", the
state [`usage.md:1841-1842`](../docs/usage.md) calls frame 12.

R-06-12 asserts only the "yes" rows. Seen from above, the `left-right` turn mirrors
the picture across a line parallel to model y. At a 45° roll that line lies
diagonal on the page, and a mirror across a diagonal swaps the figure's width and
height, which changes a non-square figure's box. Under `iso` the projection is not
symmetric about the axis at all. For the same reason R-06-12 leaves out `rotate` by
a quarter turn: it swaps a non-square figure's width and height on every page.

`StepsSpec` asserts the "yes" rows through `stepPage`, on `top` and `bottom` at
rolls of 0°, 90°, 180° and 270° (A7), and the `iso` row's change (A8), which a
page of the one figure gave on 2026-10-28 as 0.41421 × 0.61183 before and
0.99810 × 0.33353 after ([decisions C129](decisions.md#changes-since-draft-v2)).

**Rotate and repeat.** `RotateMark k` draws k/8 in a circle with an arrow in the
turning sense; `RepeatMark a b` a box holding the range (Lang). Both sit inside the
figure: a leader to other figures would cross cells, and `Layout` exists so a mark
"can never collide with a different figure"
([`Layout.hs:42-45`](../src/Senbazuru/Diagram/Layout.hs#L42-L45)).

### 6. Growing crease graphs and fold-here lines

A run's frames gain creases between figures. `motionsAcross` matches vertices by
*material coordinates* (where each point lies on the unfolded sheet, which never
changes) and `creasesToCome` returns new creases at `before` positions; both are
in [05](05-prd-library-additions.md) and decided in
[D6](decisions.md#d6-crease-graphs-grow-between-frames). `motionsBetween` stays
in use, inside `motionsAcross`, whenever graphs are equal (R-06-14), which keeps the 14 arrow-bearing
goldens structurally unchanged: all pass `motionsBetween` today. One behaviour
changes from refusal to drawing: `render --steps --arrows` on a growing file
with `senbazuru:material_coords`, refused today with `FramesDiffer`.

Fold-here lines are styled by the kind as seen because the quarter fixture's second
fold makes a `V` and an `M` crease in one valley fold; styling by assignment
reproduces the half-and-half line of the existing golden.

**Where a run page's lines come from** (owner decision 74). Not from the creases
a move adds: a run that folds along creases its sheet already has adds none, and
the blintz run is one, all six of its states having 12 edges (`jq` on
`examples/blintz-sequence.fold`). Every fold and pre-crease draws its hinge
(`recordHinge`) at the before positions, styled by the move's sense as seen. An
unfold draws none: that is the decision record's reading of decision 74, which
names folds and pre-creases, and S33
([#643](https://github.com/avalonalex/senbazuru/issues/643)) asks the owner to
confirm it. `render --steps` draws no fold-here line, since `inferNote` carries
`NoFoldLines` (§1, A1). `creasesToCome` is the source only for a `stepFigures`
caller that states the kind, as `InferFoldLines` (S28,
[#642](https://github.com/avalonalex/senbazuru/issues/642)).

### 7. Figures holding several moves

"Fold and unfold in front `[corner south-west, corner north-east]` moving `corner
south-east`" on `sheet square`, where `in front` means a valley as seen
([02 §5.1](02-language-semantics.md#51-the-readers-side)): the moving triangle
(0, 0), (1, 0), (1, 1) has corner mean (2/3, 1/3); folded flat across y = x it
lands on (1/3, 2/3) (`python3` arithmetic). `RunSpec` runs this pre-crease
([`RunSpec.hs:285-287`](../test/Senbazuru/Sequence/RunSpec.hs#L285-L287)) but
checks no folded position, since the record keeps none, so the numbers stay
**UNVERIFIED** through the runner until S18c
([#640](https://github.com/avalonalex/senbazuru/issues/640)) pins them.

The figure's before and after frames are identical, so inference draws nothing.
The move's one record draws a valley arrow (2/3, 1/3) → (1/3, 2/3) and an unfold
arrow back. `arrowFor` bows "always to the same side" of its own direction
([`Style.hs:356-358`](../src/Senbazuru/Diagram/Style.hs#L356-L358), `sideways`
at [`:384`](../src/Senbazuru/Diagram/Style.hs#L384)), so the reversed arrow bows
the other way and the pair reads as out and back. One valley-dashed fold-here
line lies on the diagonal. [D22](decisions.md#d22-figures-holding-several-moves)
admits a move to a figure only if its moving paper is where the figure draws it,
and a pre-crease is one move there like any other ([02
§6.5](02-language-semantics.md#65-figures-holding-several-moves)). That makes
the fold arrow true on the drawn state. The runner does not check this yet:
`MoveLeavesFigure`, the refusal D22 names, is a name `expect refused` accepts
([`Error.hs:860`](../src/Senbazuru/Sequence/Error.hs#L860)) with no constructor
until S19 ([#640](https://github.com/avalonalex/senbazuru/issues/640)). The
unfold arrow is drawn from the folded pose back to where the paper started
(R-06-16). The runner computes that pose, the turned record
([`Run.hs:697-699`](../src/Senbazuru/Sequence/Run.hs#L697-L699)), and
`asPrecrease` discards it
([`Record.hs:518`](../src/Senbazuru/Sequence/Record.hs#L518)). S18c has the
`Precrease` record keep it behind one accessor (**SKETCH** `recordFoldedPose`),
a choice of the decision record's own, since `recordPoseAt` and `PoseOnRoute`
do not exist ([C90](decisions.md#changes-since-draft-v2)).

### 8. Captions and the gutter

Owner decision 7, decided 2026-10-28 ([decisions
§9](decisions.md#9-owner-decisions); [the question as
asked](https://github.com/avalonalex/senbazuru/issues/635#issuecomment-6486583488)),
wraps each caption under its figure and spaces each captioned row for its
longest caption, in page units (R-06-18, R-06-19). Pages with no caption are
untouched. The pages the owner chose from, the scratch programs that drew them
and the command behind every number below are in [S1's secret
gist](https://gist.github.com/avalonalex/fd14965f924ea96426f10ec708ecc1b3),
built from main at f1f217d with `rsvg-convert` 2.62.3.

**Placement.** A cell is a figure's shared box plus a *gutter*, 0.1 of a figure's
size by default ([`Layout.hs:95`](../src/Senbazuru/Diagram/Layout.hs#L95),
[`:121`](../src/Senbazuru/Diagram/Layout.hs#L121);
[glossary](glossary-additions.md#step-pages)). On a captioned page the columns
keep that gutter, and each row is followed by a band, b_r = a + (L_r − 1) p + d
page units, holding its captions' lines (R-06-19). Line k of a caption has its
baseline a + k p page units below its figure's box, an `Offset` from the box's
bottom-left corner, so the two-unit rule holds: the anchor is in model units and
the drop in page units. A caption is wrapped to the shared box's width, never the
stride and never the folded figure's own smaller width, so the column gutter,
11.5 page units on the default page, is slack before a line could reach its
neighbour.

**The font, measured.** `rsvg-convert` draws `sans-serif` as Helvetica on this
Mac, though `fc-match sans-serif` names Verdana: Pango, which draws its text,
asks macOS for fonts by default, and only with `PANGOCAIRO_BACKEND=fc` does it ask
fontconfig and get Verdana. "Fold the left half behind, onto the right." measures
236.5 units of ink at 14 units in both `sans-serif` and `Helvetica`, and 276.2 in
`Verdana`, or in `sans-serif` under the fontconfig backend, the widest of the six
sans-serif families
measured here (Arial 236.8, Tahoma 242.5, Trebuchet MS 252.8, Geneva 267.0). An
earlier version of this section gave the 236.5 as Verdana's. Ink runs 10.2 units
above the baseline, 10.8 in Verdana, and 3.0 to 3.2 below it (the gist's
`ink.py`, which renders one line at 4× and scans its alpha channel).

**The estimate.** Over the crane source's 29 captions, ink runs 0.40 to 0.47 em a
character in Helvetica and 0.47 to 0.53 in Verdana. Wrapped greedily at 0.55 em,
the 48 distinct captions of the crane, blintz, quarter-fold and S1's scratch runs
make 176 lines at a figure's 115 page units, the widest 97.2 in Helvetica and
108.8 in Verdana, and 69 lines at the page's 368, the widest 297.5 and 340.5. At
115 units a caption takes 2 to 6 lines. The estimate stands in for font metrics,
which the backend does not have
([`Svg.hs:187-190`](../src/Senbazuru/Render/Svg.hs#L187-L190)), and errs wide on
purpose: a line broken too early costs a little room, and one broken too late
overruns.

**The band's constants** (set by S24,
[#641](https://github.com/avalonalex/senbazuru/issues/641),
[C134](decisions.md#changes-since-draft-v2)). The pitch p is 1.2 ×
14 = 16.8. The first baseline's drop a = 18 puts the top of a first line's ink,
at most 10.8 above its baseline, 7.2 below the figure's box, clear of the fan's
largest move, 6.4 page units down (§10); S1's pages used 15. The last term
d = 14 holds the descent, at most 3.2, and about 10.8 before the next row, whose
numbers sit 0.12 of a figure below its top
([`Layout.hs:155`](../src/Senbazuru/Diagram/Layout.hs#L155)). A row of one-line
captions gets a band of 32 page units, and a row with a six-line caption one of
116, about a figure's height on the default page. The fan is not the only thing
below the box: the turn-over loop is a page-unit `Symbol` at the lower end of its
figure's extent (§5, [D7](decisions.md#d7-a-typed-step-note-reaches-the-page)),
so the part of it that hangs below shares the band's top with a caption's first
line, which runs under the figure's middle once it is half a figure long. The loop's size is not set yet, so
a = 18 does not account for it, and S24 left a at 18; S29
([#642](https://github.com/avalonalex/senbazuru/issues/642)), which sets the
loop's size, sets a for the larger of the two or keeps the loop inside the box
([C134](decisions.md#changes-since-draft-v2)).

**The scale.** `Layout` has no page units of its own
([§11](#11-rejected-alternatives)), so the caller that knows the page hands it
the scale, a `PageScale`, and `Layout` turns each band into model units, b_r /
s, itself (S24, [C134](decisions.md#changes-since-draft-v2)). The caller asks `Diagram.Page.pageTransform`
([`Page.hs:82-89`](../src/Senbazuru/Diagram/Page.hs#L82-L89); moved there from
`Render.Svg` by S25a, [C135](decisions.md#changes-since-draft-v2)) for the scale,
which exists so that no caller fits the box again, rather than restating the
arithmetic. `run -o x.svg` with no `--height` makes the page as tall as its rows
need, so its width sets the scale: s = (W − 2m) / (w (c + (c − 1) g)) for c
columns in use, at most the figure count, of figures w model units wide, 115 on
the default page, and the page is 2m + s × R × h + Σ b_r tall for R rows of
figures h high. S1's prototype pages, drawn with a = 15, were 648.8 page units
tall at 9 figures and 1620.8 at 24; at a = 18 each band is 3 page units taller,
which makes 657.8 and 1644.8. With `--height` given, the
figures shrink to fit. The wrap width then depends on the scale, so the scale is
a fixed point. S24 chose how to find it (C134) and S25 built it, as
`Diagram.Page.fitPage` ([C136](decisions.md#changes-since-draft-v2)): start at the
scale the width alone sets, then, until the bands stop changing, wrap at the
current scale and take the largest scale a page H tall allows for those bands:
the smaller of the width's scale and (H − 2m − Σ b_r) / (R h). The bands only grow
as the scale falls, so this ends, and `pageTransform` confirms the answer. A
page too short for its bands at any scale is refused. As built, a round stops
when the bands' total no longer grows, which is the same stop while wrapping
behaves as greedy wrapping does, and is also exactly the condition under which
the page fits, so a page is never handed back that does not; a property test
holds it to the largest scale that fits, and its refusals to pages no sampled
scale fits. On S24's prototype, the
blintz's five captions under unit squares with a sixth figure uncaptioned, a
400 × 400 page settles at 84.8 in three tries, a 350-tall one at 9.4 in four,
and a 300-tall one is refused, its bands 299.2 page units against 268 of
content. Iterating `pageTransform` instead, s ← the scale of the page laid out
at s, converges only geometrically: 42 steps to within 1e-12 at 400, and not
there after 199 at 350.

**What the earlier default measured.** Until the decision, the recommended
default was one line per caption under a captioned gutter of max g (42/340),
with overflow accepted. By `gridOf`'s and `fitBox`'s formulas
([`Geometry.hs:193-213`](../src/Senbazuru/Geometry.hs#L193-L213)), three figures
in a row make a page box 3.2 figure-widths wide:

| Page | Content | Scale | Gutter on page | Type ([`Style.hs:227`](../src/Senbazuru/Diagram/Style.hs#L227)) |
| --- | --- | --- | --- | --- |
| CLI default, 400 × 400, margin 16 ([`Page.hs:61-70`](../src/Senbazuru/Diagram/Page.hs#L61-L70)), `--columns 3` | 368 × 368 | 368 / 3.2 = 115 | 11.5 | 14 |
| `renderSteps` test page, 400 × 200, margin 10 | 380 × 180 | 380 / 3.2 = 118.75 | 11.875 | 14 |

On both default pages a gutter of 0.1 left 14-unit type overlapping its
figure. On a three-column CLI page a gutter of g figures is g × 368 / (3 + 2g)
page units, which reaches 14 only when g ≥ 42/340 ≈ 0.124: at g = 42/340 the CLI
page's scale is 113.33 and its gutter 14.00 units, and the `renderSteps` page's
scale 117.03 and its gutter 14.46, since its own bound is 42/352. That held for
one or two rows of three. From three rows on height limits the scale instead,
and with the trailing gutter and a square sheet the gutter is 13.49 units at
three rows, 10.12 at four and 5.06 at eight. The pages' SVG agrees: the stride,
from figure 1's number to figure 4's, is 127.333 units at two rows, 122.666 at
three and 46 at eight. Overflow was worse. The stride at one or two rows is 127.33 page units,
against which the five captions E7's blintz page would carry measure 143.0 to
298.8 in Helvetica. Of the crane source's 29 captions, 8 fit at one or two rows,
six of them "Turn the … over.", 2 at three and none at four; in Verdana, 1. So
on S1's pages captions ran into each other at every row count.

**Why the bands are conditional.** Space under the last row changes the page box.
A trailing gutter of 0.1 would make a one-row page box 1.1 tall; `fitBox`
centres the box, so every y would move, including figure 1's number label at
`y="54.875"`: the figure's top edge, 40.625 (margin 10 plus (180 − 118.75)/2 of
vertical centring), plus the label's drop, 0.12 of the figure's height
([`Layout.hs:155`](../src/Senbazuru/Diagram/Layout.hs#L155); not the 0.1 gutter).
[`LayoutSpec.hs:85`](../test/Senbazuru/Diagram/LayoutSpec.hs#L85) pins only the
horizontal case, a one-figure page exactly one figure wide; the vertical one is
pinned by the goldens (`y="54.875"`) and by A12. A band does the same and changes
the scale besides, so a page with no caption gets neither.

### 9. `frame_title` and assurance point opposite ways

A state's `frame_title` is the caption of the step leaving it, the next step
that writes a state (`closing` on the last, or the stopped step's caption on a
run stopped at `not modelled`,
[`Record.hs:723`](../src/Senbazuru/Sequence/Record.hs#L723)), and its
`senbazuru:assurance` is the evidence of the step that produced it
([D4](decisions.md#d4-written-frames-follow-the-state-rule),
[D24](decisions.md#d24-states-figures-and-their-numbers);
[caption](glossary-additions.md#step-pages), [02
§11](02-language-semantics.md#11-written-frames)). A book puts the caption with
the arrow, on the figure before, and `run -o x.svg` does the same. So state 0 of
`examples/blintz-sequence.fold` carries step 1's instruction, and whatever shows
a state's title shows that: `info`, a single-frame `render` and a glTF's title
([`Cli.hs:1150`](../app/Senbazuru/Cli.hs#L1150),
[`:1048`](../app/Senbazuru/Cli.hs#L1048),
[`:945`](../app/Senbazuru/Cli.hs#L945)). It reads as an off-by-one and is not;
this record accepts it, and S25
([#641](https://github.com/avalonalex/senbazuru/issues/641), [C136](decisions.md#changes-since-draft-v2)) documented it,
in `docs/usage.md`, `docs/tour.md` and `docs/fold-reference.md`.

A file cannot say which convention its titles follow. The fixture puts "Step 2:
folded in half" on the half-folded state; a sequence file written from the
quarter-fold source
([04](04-prd-sequence-source-and-cli.md#a-first-source-read-line-by-line)) puts
"Fold the top half down in front, onto the bottom." there. Whichever convention
`render` assumed, one of those files would get the wrong words under its
figures, and drawing anything at all would move `quarter-fold-steps.svg`. So
`render --steps` never draws `frame_title`
([D7](decisions.md#d7-a-typed-step-note-reaches-the-page)).
[#94](https://github.com/avalonalex/senbazuru/issues/94) closes at M3 through
`run -o x.svg`, with S37
([#643](https://github.com/avalonalex/senbazuru/issues/643)); its done-when
(fixture titles drawn under `render`'s figures, read with `gh issue view 94`)
was amended on 2026-10-27, in [a
comment](https://github.com/avalonalex/senbazuru/issues/94#issuecomment-6458546438)
that S0b of [#635](https://github.com/avalonalex/senbazuru/issues/635) posted
([decisions §3](decisions.md#3-recorded-text-this-design-changes) row 7 and
[§10](decisions.md#10-corrections) item 3, written out in [01
§4.7](01-architecture.md#47-corrections-to-six-issues)).

### 10. Layers fanned from their folds

A flat fold puts sheets exactly on top of one another, so a figure that draws
every sheet where it lies draws one outline over several layers. The helmet
base's last state, the end of `helmet.foldseq`, has six faces in four layers and
is drawn as one square. A reader cannot see which edges are folds and which are
the paper's own edges, its [border](../docs/glossary.md#the-fold-format), or how
many sheets a flap holds.

Szinger's Foldinator ([3OSME paper, 2001](https://zingman.com/origami/foldinator3OSMEpaper.php))
draws aligned layers "systematically offset so that the viewer can read the
diagram". In its figures a fold stays one joined line, the border of the sheets
underneath peeks out on one side, and the point where layers meet stays
together. The owner prefers that look (owner decision 65,
[decisions §9](decisions.md#9-owner-decisions)), and `run -o x.svg` draws it
(R-06-24–29). This *fanning* departs from a true projection; the paper's
coordinates are not touched.

**One figure, worked through.** Number the helmet base's last state as its run
writes it (`file_frames[3]`). Its nine vertices lie at only four places, since
folding brings several onto one point. The sheet's four corners all land on the
model's tip, (1, 0), as vertices 0 to 3. Over them, as the page is seen, lie 0,
3, 0 and 2 sheets. So the tip is drawn at three places: where it lies, and 3 and
4.5 page units toward the lower left, the corners of the two buried sheets
peeking out. The sheet's centre, vertex 5 at (0.5, 0.5), is a vertex of all six
faces; the top faces have nothing over them, so it stays where it lies, the point
where the layers meet.

**The rule** (R-06-24, R-06-25; [05](05-prd-library-additions.md) L16 computes
it). For each vertex, and each face with a corner there, count the fewest faces
nearer the viewer than that face over any point of it near the vertex. The least
of those counts is the vertex's *fan count*
([glossary](glossary-additions.md#step-pages)). Each vertex is drawn its count,
at most 6, times 1.5 page units toward the lower left. Three things follow.

- **A fold stays one line.** The two faces a fold joins share its vertices, so
  both draw them at one place. The offset view (`render --offset`) moves each
  face by its own layer instead, and draws a shared crease twice
  ([`CreasePattern.hs:36-77`](../src/Senbazuru/Render/CreasePattern.hs#L36-L77)).
- **A face with nothing over any of its vertices stays put.** Taking the least
  over a vertex's faces gives it 0 when any of them is uncovered there. A face
  with one covered vertex leans toward it (Risks).
- **The border underneath peeks out.** Two sheets whose corners lie at one point
  are two vertices, each with its own count.

**Why the fewest, over any point.** Near a vertex the faces over a face can
differ from one side of a line through the vertex to the other. At the helmet's
tip the diagonal x + y = 1 cuts face 0's corner in two, and three faces lie over
each half, but only one, face 4, over both. Counting only faces that cover the
whole corner would give the tip 1. Counting at one point beside it, as the first
prototype did, depends on which side that point falls, and there it falls on the
diagonal.

**Not the layer number.** `layerDepths` gives each face its
[layer number](../docs/glossary.md#origami), the longest chain of faces below it,
and the offset view moves a face by that, so its top layer moves furthest
([`Layers.hs:91-112`](../src/Senbazuru/Origami/Layers.hs#L91-L112)). Read the
other way, it is the longest chain over a face anywhere, so a face partly under
one flap gets 1 even at vertices the flap does not reach; on the crane that chain
is 31 where no point holds more than 24 sheets
([layer-numbers](../docs/notes/layer-numbers.md)). On the helmet's state 2 it
would give vertices 1 and 3 counts of 3 and 2, where their fan counts are 1 and
0 (A18).
05's L9 is to count faces at a point for the same reason, but it is M4 work:
neither it nor its `CoverError` exists yet.

The counts, from a scratch prototype in Python run on 2026-10-23. For each face
at a vertex it tested 40 points of that face 1e-4 from the vertex, across the
corner, against every face nearer the viewer:

| State | Faces | Vertices | Vertices by fan count |
| --- | ---: | ---: | --- |
| Helmet base, `helmet.foldseq`'s last state | 6 | 9 | 0: 5 · 1: 2 · 2: 1 · 3: 1 |
| Square base, `examples/square-base.fold` folded | 8 | 9 | 0: 4 · 1: 2 · 2: 2 · 3: 1 |
| Bird base, `bird-base-sequence.fold` `file_frames[15]` | 16 | 13 | 0: 7 · 2: 4 · 3: 2 |
| Crane, `examples/crane.fold` folded | 72 | 58 | 0: 17 · 1–6: 27 · 7–15: 14 |

**The cap.** Uncapped, the crane's deepest vertex, under 15 sheets, would move
22.5 page units. At 6 the largest move is 9 page units, 6.4 along each page axis.
On the CLI's default page, 400 by 400 with three columns (§8), an uncaptioned
page's gutter holds that up to five rows of figures; at six rows it is 5.66 page
units, so on a longer page the fan reaches the next cell (Risks). A captioned
page's bands are in page units, the top of a first caption line's ink 7.2 below
its figure's box, so there the fan stays clear of the captions at any row count
(owner decision 7, §8). The owner saw the
prototype uncapped. The cap is this record's choice, made afterwards, and a capped
crane drawn then read no busier.

**The direction.** Deeper sheets are drawn toward the lower left of the sheets
over them, as in the offset view, whose `layerStep` moves each upper layer up and
to the right ([`Style.hs:291-336`](../src/Senbazuru/Diagram/Style.hs#L291-L336)).
The fan needs the direction without the offset view's step, which is `Nothing`
whenever no offset is asked for, so the unit direction becomes a constant both
use. In page axes it is (−1, +1)/√2. **The + is not a sign slip:** page y grows
downwards.

**One painter.** A fanned figure is painted by the offset view's painter, with a
displacement for each point instead of for each layer (R-06-27). So it keeps that
painter's merged fills, which the Fill contract needs, and paints each layer's
full-weight stretches with that layer
([`CreasePattern.hs:39-75`](../src/Senbazuru/Render/CreasePattern.hs#L39-L75)).
The painter's layers also decide faces that only overlap once fanned, which no
face order covers. On the helmet's state 2 it draws face 4 over face 2. The
prototype painted them the other way round, which made the pale wedge in its
figures.

**Where** (R-06-29; owner decision 66). `run -o x.svg` fans unless `--no-fan`
says not to. `render` fans only when asked, with `--fan`, so its output and every
tracked golden stay as they are. The default theme stays unfanned for the reason
it gives ([`Style.hs:234-237`](../src/Senbazuru/Diagram/Style.hs#L234-L237)): a
drawing that moved paper unasked would misplace it. A page from a run is asked
for, follows a book's convention, and leaves a face with nothing over any of its
vertices where it lies. The GLB shows its stack another way, lifting flat pieces
by their layers with folds drawn as strips
([PRD 08](08-prd-realistic-rendering.md#layers-lifted-off-the-stack), owner
decisions 67 to 69).

### 11. Rejected alternatives

| Rejected | Why |
| --- | --- |
| A `Bool` beside the notes | Two switches answer one question, arrows or not, and they can disagree ([D7](decisions.md#d7-a-typed-step-note-reaches-the-page)) |
| Changing `stepPage`'s arity | 23 lines in 15 files for no drawing change |
| A sum-type `StepError` (research sketch) | Breaks `Cli.hs:969-977`; unnecessary once every note is drawable |
| Presentation applied inside the page, about page axes | The runner would need a camera, written files would depend on `--view`, and frames that arrive presented would be presented twice ([D5](decisions.md#d5-presentation-and-the-readers-side)) |
| #95's axis at x = 0 | Doubles the union, halves the scale |
| Kind from the changed assignment (#36) | Ambiguous per motion |
| Checking a stated kind against an inferred one | Inference trusts winding as written, which a backwards-wound file breaks (AGENTS.md gotchas); records are already checked |
| Backfilling future creases | Figure 1 would show the second fold |
| A caption band sized inside `Layout` in model units (#94) | `Layout` has no page units of its own, so a band sized there is fixed in model units and right at one scale only, the recorded bug. Owner decision 7's band is sized in page units, turned into model units by the scale the caller that knows the page hands `Layout` (§8, [C134](decisions.md#changes-since-draft-v2)) |
| One line per caption under a captioned gutter of max g (42/340), overflow accepted | The earlier recommended default. Captions ran into each other at every row count on S1's pages: the stride is 127.33 page units and E7's captions 143 to 299 wide. The gutter cleared 14-unit type only at one or two rows (owner decision 7, §8) |
| The captions as a numbered list below the grid | `Layout` would not change, but the reader matches numbers instead of reading under each figure (owner decision 7) |
| A gutter that grows with the row count | It keeps the type off its figure, but not captions off each other along a row (§8) |
| SVG 2's `inline-size` | `rsvg-convert` 2.62.3 ignores it and draws one line (S1's gist) |
| SVG `textLength` | It would squash the crane's longest caption, 446.2 units of ink, into 127, a little over a quarter of its width |
| Truncation with an ellipsis | It drops the end of an instruction |
| One arrow with heads at both ends for a pre-crease | `ArrowPath` has one head, and a pre-crease's two arrows have two kinds: its sense out, unfold back ([D7](decisions.md#d7-a-typed-step-note-reaches-the-page)) |
| One display field per record, applied to both surfaces | It cannot give a `Presented` record's before display, nor keep presentation apart from anchor placement, which animation needs as separate nodes ([D14](decisions.md#d14-material-consumption)) |
| A total `stepNotes` | It calls `writtenStates`, which refuses a state with missing angles or a non-finite material coordinate, as `WriteRefused` ([`Record.hs:713`](../src/Senbazuru/Sequence/Record.hs#L713), [`:788`](../src/Senbazuru/Sequence/Record.hs#L788); [D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)) |
| Sample poses written to the file but left off the page | The page would no longer draw exactly the states the file holds ([D24](decisions.md#d24-states-figures-and-their-numbers)) |
| The offset view's layers on the step page | Each layer moves whole, so every fold splits into two lines, the top layer moves furthest, and arrows are refused beside it (owner decision 65) |
| Drawing each flat state slightly unfolded | A state is its fold angles (AGENTS.md), and opening every crease to 97% of its angle tears seven of eight fixtures (`TornAt`: the crane, the square, waterbomb, bird, fish and helmet bases and `kabuto.fold`; run 2026-10-23). Only `blintz-base.fold` folds, its four creases meeting at no vertex inside the sheet |
| A face's layer number as its count | The longest chain over the face anywhere, so paper nothing covers moves: on the helmet's state 2, vertices 1 and 3 get 3 and 2 where their fan counts are 1 and 0 (§10, A18) |
| Counting a covering face only where it covers the whole face near the vertex | The helmet's tip gets 1, though three sheets lie over its corner on either side of the diagonal through it (§10) |
| Counting the sheets under a vertex | The top layer moves furthest, and it is the layer the reader sees |
| Fanning `render --fold` and `--steps` by default too | Up to 22 of the 32 tracked SVG goldens could change, against Goal 3 (owner decision 66; counted in [decisions C121](decisions.md#changes-since-draft-v2)) |

## Acceptance criteria

[09](09-testing-and-acceptance.md) places these in CI.

| # | Criterion | Red if |
| --- | --- | --- |
| A1 | `stepPage t b g v x fs == fmap (gridOf g . map fst) (stepFigures t b v (map (\f -> (f, noteFor x)) fs))` (restated by S25, [C136](decisions.md#changes-since-draft-v2)) for both `x` on the quarter fixture, `bird-base-sequence.fold` and `StepsSpec`'s sheets, a wiring check that holds by construction while `stepPage` is `gridOf` over `stepFigures` with `noteFor` of its `Bool` (R-06-2). Beside it, on the quarter fixture under `top`, `inferNote` draws one `Arrow` on its first fold and `silentNote` none, `stepPage` draws its two arrows with `True` and none with `False`, and a frame skipped for having no geometry takes its note with it ([C131](decisions.md#changes-since-draft-v2)) | `stepPage` draws its page some other way, or with the other `Bool`'s note; `noteFor` ignores its `Bool`, which both sides of the equality use; a note draws what the other should; notes are matched by place to the frames left after skipping. A default leaking into `inferNote` or `silentNote`, e.g. `InferFoldLines`, shows on none of these fixtures, whose crease graphs never grow, so the PR adding a field draws both notes on a pair where that field would draw |
| A2 | On the committed branch, `git diff --name-only --diff-filter=MD origin/main...HEAD -- test/golden/` prints nothing and the same command with `--diff-filter=A` lists exactly the new goldens below ([D16](decisions.md#d16-testing-and-acceptance); [09 §1.2](09-testing-and-acceptance.md#12-tracked-goldens-stay-byte-identical)). Both print nothing today (run 2026-09-15) | `SolidHead` emission reorders an attribute; a gutter appears without a caption; a golden is added that this table does not list |
| A3 | `quarter-fold-steps.svg` and the pinned `bird-base-sequence-arrows.svg` stay byte-identical, with the by-hand `cmp` of `render --steps --arrows` on both multi-frame files in `examples/`, as [09 §1.3](09-testing-and-acceptance.md#13-multi-frame-examples-draw-the-same-step-pages) sets out | presentation classification ([05](05-prd-library-additions.md)) fires on a real fold |
| A4 | Each head, body and glyph emits equal page bytes at model sizes 1 and 400, extending [`SvgSpec.hs:263-268`](../test/Senbazuru/Render/SvgSpec.hs#L263-L268) | a hollow head or loop is sized in model units |
| A5 | `seenFrom` gives §4's table for the five named views and two gallery bases, and a roll of 1 radian changes nothing | `z > 0` is read as the reader's side |
| A6 | Under `View (Just bottomUp) 0` the same notes draw `HollowHalfHead` where `top` draws `SolidHead`, with dashes swapped too | inversion reaches heads but not dashes |
| A7 | With and without a turn-over or `rotate 4/8 turn`, figure extents and page box agree within 1e-12 × span, and the scale within 1e-12 of itself, on `top` and `bottom` at rolls 0, 90°, 180°, 270°, for the quarter fold, the same sheet folded in half only, and bird `file_frames[13]` (`--frame 14`) | the axis passes through x = 0, the corner mean or the run's anchor; a half turn turns a quarter turn |
| A8 | On `iso`, bird `file_frames[13]`'s extent changes across the turn (0.4142 × 0.6118 → 0.9981 × 0.3335, within 1e-4) | the turn is computed about a page axis, or the page re-fits figures after a turn, so the `iso` extent stays equal |
| A9 | A figure with a presentation mark has one `Symbol` and no `Arrow`; `CreasePatternSpec` counts symbols beside `arrowsIn` | inference is not suppressed on the marked pair |
| A10 | On each single-move figure of the blintz sequence (M2), `GivenArrows` from its record equal `InferArrowsAs` ends within 1e-12 × span | `displayBefore` or `displayAfter` is not applied, or record ids are not in `recordBefore`'s numbering |
| A11 | For the quarter-fold run, `fmap (map fst) (stepNotes run)` equals the `file_frames` of `writeSequence`'s file, both `Right`. In review: `Render.Sequence` imports `Sequence.Record` and `Sequence.Error` and no other sequence module, and no `View` is an argument of `runSequence`, `writeSequence` or `stepNotes`. Sharing `writtenStates` makes the frames equal by construction; the test guards what the construction does not, `stepNotes` dropping or reordering states | `stepNotes` filters `writtenStates` (for example drops sample states) or rebuilds frames without the [state rule](glossary-additions.md#the-fold-format); `Render.Sequence` imports `Sequence.Write` or `Sequence.Run`; a `View` reaches the runner, the writer or `stepNotes` |
| A12 | `LayoutSpec`, for 1–60 figures: a page whose figures have no caption, or captions of no words, equals `gridOf`'s; on a captioned page each row's band, measured on the page at scales 100 and 300, is a + (L_r − 1) p + d page units, the last row's included and a row with none counted as one line; each caption line is a `Label` at its cell's bottom-left corner moved down a + k p; and no line's estimated width exceeds the shared box's width on the page unless it is one word (restated by S24, [C134](decisions.md#changes-since-draft-v2)) | a band is added to a page with no caption; a band is sized in model units; a row's band ignores its longest caption, or a row with none gets none; the last row has no band; a line is wrapped wider than the box |
| A13 | `motionsAcross == motionsBetween` on every consecutive pair of the quarter fixture and FlapSpec's four material-frame sequences | `motionsAcross` visits rings in another order |
| A14 | For every glyph, `shapePoints (Symbol s k a g) == [a]` and `mapShapePoints f (Symbol s k a g) == Symbol s k (f a) g` | a glyph's page-unit geometry, or `TurnOverLoop`'s vector, enters the extent or is moved by layout |
| A15 | `stepFigures`, laid out by `gridOf`, on the quarter fixture's frames with `Rotated (-3) p` on figure 1 and `noteRepeat = Just (1, 2)` on figure 3 emits one `RotateMark (-3)` and one `RepeatMark 1 2`, each anchored inside its own figure's cell | the sign is dropped, the range is shifted, or a mark is anchored in another figure's cell |
| A16 | On the quarter fixture's state 1, a mark on a face `Origami.Visible` shows gets one `Label` and a mark on a face it hides gets none | labelling ignores `Visible` |
| A17 | Under `View (Just frontOn) 0`, the frames and notes of `quarter-fold-turn-over-steps.svg` (below) give figure 3 one `TurnOverLoop (V2 0 1)` anchored at the midpoint of that figure's bottom edge | the zero-length projected axis is normalised into NaN, or the loop is dropped because the axis has no page direction |
| A18 | On the helmet base's last state, a fanned figure draws vertex 1 4.5 and vertex 3 3 page units toward the lower left of where they lie, and vertices 0, 2, 4, 5 and 8 where they lie; on its state 2, vertices 1, 7 and 8 1.5 page units out and the rest where they lie; each fold's two faces draw its vertices at one page position | the count is a face's layer number (state 2 moves vertex 1 4.5 and vertex 3 3); a covering face counts only where it covers the whole corner (the tip moves 1.5); a face is moved whole; the direction's sign is flipped |
| A19 | A fanned figure emits equal page bytes at model sizes 1 and 400, extending A4 | the fan step is in model units |
| A20 | Under `View (Just bottomUp) 0`, the helmet base's last state fans by 05 L16's counts seen from −z (vertices 0 and 2 by 2, vertex 3 and vertices 6 and 7 by 1) | the counts are read from the top whatever the view |
| A21 | A page holding the folded `thirds-pinwheel.fold`, a twist whose orders run in a circle, and a figure seen edge-on among flat figures draws every figure, those two unfanned (`squaretwist.fold` is paper in the air, so it would not test the twist) | a figure that cannot fan fails the page |
| A22 | On the folded crane no vertex moves more than the cap times the fan step | the cap is dropped: 14 of its 58 vertices had 7 to 15 sheets over them on 2026-10-23 |
| A23 | On the helmet run's page, the fanned page's `Arrow`, `Symbol`, `Label` and fold-here shapes equal the unfanned page's | a mark is fanned |
| A24 | `Fanned` with every displacement `d` emits the bytes `Offset d` emits, for a polyline and for a fill of two rings, one clockwise | the two drift apart, or a turned-round ring loses its points' displacements |
| A25 | `stepPage`, and `stepFigures` with `defaultTheme`, emit no `Fanned` shape on any input of this file | an unfanned theme fans |

A12 stated owner decision 7's earlier default, a trailing gutter and a
captioned gutter of at least 42/340, until S24
([#641](https://github.com/avalonalex/senbazuru/issues/641)) restated it to
R-06-19's bands ([decisions C127, C134](decisions.md#changes-since-draft-v2)).

`run`'s warning is CLI behaviour, checked by hand (the CLI is untested by design,
[`Cli.hs:5-8`](../app/Senbazuru/Cli.hs#L5-L8);
[D13](decisions.md#d13-the-run-verb-and-io)); `pageSide` carries the tested logic.

### Goldens that must stay byte-identical (`git ls-files test/golden`)

| Group | Goldens (producer) | What here could move them |
| --- | --- | --- |
| Step pages with arrows (14) | `quarter-fold-steps.svg` (`SvgSpec.hs:392`); `bird-base-sequence-arrows.svg` (`:402`); `quarter-fold-sequence-steps.svg` (`WriteSpec.hs:127`); `quarter-fold-step-1.svg` (`:384`, `withArrows` on one frame); `checked-flap.svg`, `checked-flat-flap.svg`, `checked-stack-flap.svg`, `checked-aligned-stack.svg` (`FlapSpec.hs:295`, `:315`, `:325`); `checked-blintz.svg` (`BlintzRunSpec.hs:180`, through `SequenceGallery.pageSvg`); `checked-helmet.svg` (`HelmetRunSpec.hs:293`, the same way); `checked-crane.svg` (`CraneWingSpec.hs:173`); `checked-petal.svg` (`CheckedPetalSpec.hs:138`); `checked-bird-above.svg`, `checked-bird-below.svg` (`CheckedBirdSpec.hs:173`) | `ArrowPath` defaults; `inferNote`; the `motionsBetween`/`motionsAcross` choice |
| Step pages without arrows (4) | `bird-sequence-iso.svg`, `bird-sequence-bottom.svg` (`BirdSequenceSpec.hs:84`); `frog-sequence.svg` (`BasicBaseSpec.hs:220`); `bent-strip.svg` (`WingBendingSpec.hs:102`) | `silentNote`; the trailing gutter and the captioned gutter; basis choice |
| Single figures (14) | `unit-square`, `diagonal-cp`, `bird-base`, `bird-base-folded`, `quarter-fold`, `quarter-fold-folded`, `letter-fold-folded`, `crane-folded`, `kabuto-underside`, `quarter-fold-offset`, `letter-fold-offset`, `simple-iso-offset`, `simple-iso`, `squaretwist-iso` (`.svg`, `SvgSpec.hs:346-507`) | `shapeToSvg` for `Label`, `Offset`, `Polyline`, `Fill`; the painter the offset view shares with fanned figures (R-06-27), for the three `-offset` goldens |
| GLB (4) | `quarter-fold-folded.glb`, `crane-folded.glb`, `simple.glb` (`GltfSpec.hs:617`, `:622`, `:627`); `blintz-sequence-final.glb` (`WriteSpec.hs:206`) | nothing here reaches `Render.Gltf`; listed so a stray import shows |

The table groups the 33 tracked on 2026-09-15 at `568dcb6` and three of the ten tracked between then and `7af4c92`: `quarter-fold-sequence-steps.svg` (#512) and `bird-base-sequence-arrows.svg` (#522), drawn by `stepPage` with arrows, and `blintz-sequence-final.glb` (#514). The other seven are not grouped: `blintz.foldseq`, `every-construct.foldseq` and `quarter-fold.foldseq` (#290); `run-refused-check.txt` and `run-refused-parse.txt` (#341); and `blintz-expected-report.txt` and `quarter-fold-report.txt` (#513). [D16](decisions.md#d16-testing-and-acceptance)'s check reads `test/golden/` whole, so it covers every one, grouped or not.

### New goldens

| Golden | Input | Red if |
| --- | --- | --- |
| `blintz-sequence-arrows.svg` (S2, [#636](https://github.com/avalonalex/senbazuru/issues/636)) | `examples/blintz-sequence.fold`'s six states through `renderSteps` ([`SvgSpec.hs:416`](../test/Senbazuru/Render/SvgSpec.hs#L416)), `stepPage` with arrows as `render --steps --arrows` calls it, beside `bird-base-sequence-arrows.svg`; tracked before any M3 change to `stepPage`, so every later M3 PR keeps it byte-identical (Goal 3; [09 §1.3](09-testing-and-acceptance.md#13-multi-frame-examples-draw-the-same-step-pages)) | a pair is taken for a presentation change and loses its arrow; an arrow goes on the figure after its fold instead of the one before |
| `quarter-fold-steps-noted.svg` (S27, [#642](https://github.com/avalonalex/senbazuru/issues/642)) | Fixture frames; hand notes: captions on 1–2, `closing` on 3, `InferArrowsAs MountainArrow` on 1 and `ValleyArrow` on 2; the `renderSteps` page | the mountain head reverts to solid; a caption is not wrapped to its figure's width by owner decision 7's estimate; a captioned row's band is not in page units, so it changes with the scale; the last row has no band |
| `quarter-fold-steps-noted-bottom.svg` (S27, [#642](https://github.com/avalonalex/senbazuru/issues/642)) | The same notes under `View (Just bottomUp) 0` | heads or dashes are not inverted; a caption is rewritten |
| `quarter-fold-turn-over-steps.svg` (S29, [#642](https://github.com/avalonalex/senbazuru/issues/642)) | The fixture's three states, then a fourth: state 2 (folded in quarters) turned by the `left-right` rule. `TurnedOver` goes on figure 3, which draws state 2. | the axis is at x = 0 (every coordinate moves); an inferred arrow joins the loop; the loop lies along the axis or follows model size |
| `quarter-fold-growing-steps.svg` (S28, [#642](https://github.com/avalonalex/senbazuru/issues/642)) | New fixture `test/fixtures/quarter-fold-growing.fold`: an uncreased square, one fold, two folds; [state-rule](glossary-additions.md#the-fold-format) frames with `senbazuru:material_coords`. **UNVERIFIED**, not yet written: `jq` must show 4, 6, 9 vertices, each frame's list beginning with the previous one's (the prefix rule, [§2](#2-from-a-run-to-notes)). | figure 1 draws the second crease; `motionsAcross` refuses; figure 2's fold-here line is solid or half mountain |
| `diagonal-precrease-steps.svg` (S34, [#643](https://github.com/avalonalex/senbazuru/issues/643)) | A run of `sheet square` with §7's step | no arrow is drawn (inference used); the unfold head is solid; the fold-here line is missing |
| `blintz-sequence-steps.svg` (S37, [#643](https://github.com/avalonalex/senbazuru/issues/643)) | [09](09-testing-and-acceptance.md) E7: `runPage` on the blintz run with `defaultTheme`, unfanned: the page `run blintz.foldseq -o x.svg --no-fan` draws, a choice of the decision record's own, so that fanning can change without moving E7 | as E7 says; a step's caption goes under any figure but the one of the state the step starts from |
| `quarter-fold-run-steps.svg` (**SKETCH** name; S37, [#643](https://github.com/avalonalex/senbazuru/issues/643)) | The quarter-fold run (`test/fixtures/quarter-fold.foldseq`), drawn as `blintz-sequence-steps.svg` is | "Folded into quarters.", its `closing` caption, is not under figure 3; `blintz.foldseq` has no `closing` line, so no other golden pins it |
| `crane-folded-fanned.svg` (S38, [#644](https://github.com/avalonalex/senbazuru/issues/644)) | `renderFoldedWith` with a fanning theme and `topDown` on `test/fixtures/crane.fold`, as `crane-folded.svg` is made ([`SvgSpec.hs:85-93`](../test/Senbazuru/Render/SvgSpec.hs#L85-L93), [`:432`](../test/Senbazuru/Render/SvgSpec.hs#L432)) | as A22; a buried sheet drawn at full weight |
| `helmet-fanned-steps.svg` (S40, [#644](https://github.com/avalonalex/senbazuru/issues/644)) | The helmet run's page through `runPage` with a fanning theme (R-06-29) | a fold drawn as two lines; a face with nothing over any of its vertices moved; a buried sheet's border not shown; face 2 of state 2 drawn over face 4 |

Quarter-fold test 1's page, `quarter-fold-sequence-steps.svg`, has been tracked
since #512 and is grouped above; test 2's page comes at M4
([decisions §8](decisions.md#8-milestones)).

## Dependencies

| On | For |
| --- | --- |
| M2 ([02](02-language-semantics.md), [04](04-prd-sequence-source-and-cli.md)) | Records carrying `recordPresentation` and `recordPlacement`, each before and after, with `displayBefore` and `displayAfter` computed from them ([D14](decisions.md#d14-material-consumption)); `Run` and `writtenStates` in `Sequence.Record` ([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)); the state-rule writer; which turn a `turn over` or `rotate` record was, `Presenting` ([C82](decisions.md#changes-since-draft-v2); below the table), though not its axis point, which comes from S18b ([#640](https://github.com/avalonalex/senbazuru/issues/640)) |
| [05](05-prd-library-additions.md) L16 | `fanCounts`, and stretches that keep the face edge they lie on, at M3 (§10) |
| [05](05-prd-library-additions.md) | `motionsAcross`, `creasesToCome`, `fitRigid` and `Step` classification with the `Origami.Step` header rewrite ([decisions §3](decisions.md#3-recorded-text-this-design-changes) row 13, written out in [01 §4.13](01-architecture.md#413-srcsenbazuruorigamistephs30-34)) |
| M0 ([10 §1](10-roadmap-risks-questions.md#1-milestones)) | Amended done-when of [#36](https://github.com/avalonalex/senbazuru/issues/36) (reflection as turn-over cannot be met) and #94 ([decisions §3](decisions.md#3-recorded-text-this-design-changes) row 7; [§10](decisions.md#10-corrections) items 2 and 3). Met 2026-10-27 by S0b's comments on [#36](https://github.com/avalonalex/senbazuru/issues/36#issuecomment-6458546164) and [#94](https://github.com/avalonalex/senbazuru/issues/94#issuecomment-6458546438) ([#635](https://github.com/avalonalex/senbazuru/issues/635)) |
| Issues | Closes #36 (S35) and #94 (S37) at M3; follows #95 (M2); advances #48 via `noteLayers`, which S32b ([#643](https://github.com/avalonalex/senbazuru/issues/643)) fills with each turn's and pre-crease's moving faces, from `recordMoving` ([`Record.hs:423`](../src/Senbazuru/Sequence/Record.hs#L423)); relates to [#60](https://github.com/avalonalex/senbazuru/issues/60), [#97](https://github.com/avalonalex/senbazuru/issues/97) |

**Which turn a `turn over` or `rotate` record was.**
[D14](decisions.md#d14-material-consumption) settles what this section used to leave
open: the display a `Presented` record had before its turn. A `Presented` record is
one whose move changed only [presentation](glossary-additions.md#running-a-sequence),
the rigid motion that turns the whole model for the reader. Its before display is
`displayBefore`, as [§2](#2-from-a-run-to-notes)'s table uses. The turn itself is
the change between the two halves of `recordPresentation`,
`after pAfter (inverse pBefore)`
([`Rigid.hs:90-98`](../src/Senbazuru/Geometry/Rigid.hs#L90-L98),
[`:159-162`](../src/Senbazuru/Geometry/Rigid.hs#L159-L162)). **The order that looks
reversed:** the inverse goes on the right, because
[D5](decisions.md#d5-presentation-and-the-readers-side) turns the model in displayed
coordinates. After `rotate 1/8 turn anticlockwise` and then `turn over left-right`,
that product's linear part maps (x, y, z) to (−x, y, −z). The other order,
`after (inverse pBefore) pAfter`, maps it to (y, x, −z), a half turn about the line
x = y. The linear part names a turn-over's axis word: (−x, y, −z) is `left-right`
and (x, −y, −z) is `top-bottom`. Neither can be a rotate, because a rotate keeps z.

It cannot name a rotate's signed eighths, which R-06-13 draws. 02 accepts k from 1
to 7 in either direction ([02 §12](02-language-semantics.md#12-refusal-catalogue),
`NotEighths`), and those 14 moves make only 7 matrices: k clockwise is the same
motion as 8 − k anticlockwise, and a 4/8 turn has no direction at all. Both results
come from a `python3` check on the rotation matrices, run 2026-09-15.

**Settled at M2** ([decisions C82](decisions.md#changes-since-draft-v2)): the record
carries the turn as written. `recordKind` is `Presentation` for both moves, holding
`TurnedOver PageAxis` or `Rotated Int Turning`, so a page reads a rotate's k and
direction from the record and never from the motion. The alternative, drawing a
rotate as the same motion turned at most four eighths with a chosen direction for a
half turn, would have drawn a mark the author did not write.

## Risks

- **Captions are wrapped by an estimate.** With no font metrics, a caption is
  wrapped at 0.55 em a character (owner decision 7, §8). A font wider than
  Verdana, or a line of wide letters, can overrun its figure into the column
  gutter, and a word longer than a line overflows. A golden records markup, not
  glyphs, so it catches neither.
- **Silent matchers** ignore `Symbol` (R-06-7); A9 guards the worst one.
- **Edge-on pages overlap.** On a page seen along the paper's plane, as `--view
  front` sees flat paper (R-06-8), every figure is 0 tall, so `Layout`'s row
  stride, (1 + g) times the shared box's height
  ([`Layout.hs:121`](../src/Senbazuru/Diagram/Layout.hs#L121)), is 0, and a
  three-column page draws figure 4 over figure 1. This record states it rather
  than moving it: S29
  ([#642](https://github.com/avalonalex/senbazuru/issues/642)) says so in
  usage.md, and [#647](https://github.com/avalonalex/senbazuru/issues/647) fixes
  it after M3.
- **Float noise.** Extents agree only within tolerance; an odd eighth turn
  carries the rounding of √½ into written coordinates, though no platform
  trigonometry (owner decision 10, decided 2026-10-11; research finding 16).
- **`motionsAcross` byte identity** on equal graphs is argued, not run (research
  "Unverified"); R-06-14 avoids depending on it.
- **Sample figures** are decided (R-06-23) but cannot be drawn until M5's macros
  exist, so nothing exercises the rule before then.
- **Marks with paper in the air** go unlabelled: `Origami.Visible` works on
  flat-folded models ([`Visible.hs:1-8`](../src/Senbazuru/Origami/Visible.hs#L1-L8)).
- **`noteLayers`** is drawn by nothing until #48.
- **Fanned figures look busy.** The owner, on the prototype: "Fan from the fold
  looks a bit more realistic, although visually a bit busy, but we can figure out
  how to fix in the future (maybe only fan out for the last N steps?)". One
  reading of that idea, this record's and not decided: fan only the paper turned
  by the moves of the last *N* steps. Each record names its moving faces
  (`recordMoving`) in its own numbering, so a later figure would find them by
  material point ([D22](decisions.md#d22-figures-holding-several-moves)).
- **Leaning visible paper.** A face with nothing over some of its vertices but
  something over another is drawn leaning toward the covered one. On the
  prototype's crane, 7 faces have uncovered points on edges that move, one by 2.9
  page units. A fold-here line on true positions then sits that far from the edge
  it marks.
- **Long pages.** The fan is a fixed page length and the gutter a fraction of
  the figure, so past five rows of three uncaptioned figures the fan can reach
  the next cell (§10). `Layout` was rewritten once to stop step numbers doing
  that ([`Layout.hs:38-45`](../src/Senbazuru/Diagram/Layout.hs#L38-L45)). On any
  page, a figure that fills its box can fan its lowest vertices below it: by
  1.06 page units on the helmet's second and third figures. A captioned page's
  bands are in page units and clear the fan's largest move (§8), so the risk is
  only on pages with no caption.
- **Faces turned inside out.** On small figures the fan is large beside a thin
  face. On the folded crane drawn 56.6 page units across, the size of 16 to 18
  figures on the default page, face 61 turns over; at 33.8, the size of the
  traditional crane's 29 figures, three turn over and one crosses itself. A guard
  such as drawing a figure unfanned when a fanned ring would turn over needs the
  page's scale, which `Diagram.Page.pageTransform` gives before anything is
  written (in `Render.Svg` until S25a,
  [C135](decisions.md#changes-since-draft-v2)); the guard is **UNVERIFIED**, and
  the M3 PR tries it on that 29-figure page.
- **What `Origami.Visible` keeps.** Each stretch of `formSheetEdges` names the
  face edge it lies on and how far along it, by fractions (05 R-05-52,
  [C137](decisions.md#changes-since-draft-v2)), so R-06-27 moves it with its face without matching edges by
  tolerance. Where a top face's fold lies along a buried sheet's border, as 15
  of the crane's 99 folds do, the stretch names the fold and is drawn at border
  weight while that border fans away.
- **Hidden lines shown.** Visibility is judged on the model as it lies. Once
  faces move by different amounts, a stretch's end that met another face's edge
  leaves it, and the full-weight line runs over paper painted in front of it: on
  the folded crane, face 10's mountain edge runs 3.4 page units into face 1. The
  offset view accepts the same trade
  ([`CreasePattern.hs:404-415`](../src/Senbazuru/Render/CreasePattern.hs#L404-L415)).
  Clipping each stretch against the fanned faces painted after it would remove
  it; **UNVERIFIED**, and a rasterised crane page would check it.

## Open questions for the owner ([10 §6](10-roadmap-risks-questions.md#6-owner-decisions))

Each has a recommended default in
[decisions §9](decisions.md#9-owner-decisions).

- **7.** Caption overlap and overflow. **Decided 2026-10-28** as recommended,
  after S1 ([#635](https://github.com/avalonalex/senbazuru/issues/635)) asked it
  again with pages of 3, 6, 9 and 24 captioned figures ([the question as
  asked](https://github.com/avalonalex/senbazuru/issues/635#issuecomment-6486583488)):
  each caption wraps under its figure by an estimated width, and each captioned
  row is spaced for its longest caption in page units (§8, R-06-18, R-06-19). The earlier recommended default, a captioned gutter of at
  least 42/340 with overflow accepted, was not taken: captions ran into each
  other on every page S1 drew.
- **9.** Does `examples/quarter-fold-steps.fold` migrate to the state rule,
  moving `quarter-fold-steps.svg` and `quarter-fold-step-1.svg`, or stay as the
  regression? **Decided 2026-10-06** as recommended: it stays, and the
  state-rule page is a new golden.
- **10.** Eighth-turn presentation by trig (platform bits in written coordinates) or
  a `sheet square as diamond` start: it decides whether `RotateMark` ever shows an
  odd k. **Decided 2026-10-11** ([C91](decisions.md#changes-since-draft-v2)):
  trigonometry, with cos 45° and sin 45° both `sqrt 0.5`, which IEEE 754 rounds
  correctly, so an eighth turn adds no platform bits of its own.
- **65–67**, decided 2026-10-23 as recommended: flat figures fan from their folds
  (§10); fanned by default on `run -o x.svg`, by a flag on `render`; and the GLB's
  version later, in [08](08-prd-realistic-rendering.md#layers-lifted-off-the-stack),
  which decisions 68 and 69 made a lift by layer, asked for by a flag.
  Left open by the owner: how to make fanned figures less busy (Risks).
- **74–77**, decided 2026-10-26 as recommended ([the questions and
  answers](https://github.com/avalonalex/senbazuru/issues/635#issuecomment-6458083132)).
  74: a run page's fold-here lines come from every fold's and pre-crease's hinge
  (`recordHinge`) at the before positions, styled by the move's sense as seen
  (§2, §6). The option as asked said `render --steps` keeps inferring them from
  new creases, but it draws none (§1); `creasesToCome` serves only a
  `stepFigures` caller that states the kind (S28,
  [#642](https://github.com/avalonalex/senbazuru/issues/642)). 75: M3 runs
  `mark`, pinned by the point forms the resolver already evaluates on the
  sheet, and labels it on the figures where that paper shows; `meet`, and a
  mark used as a reference, stay not run yet until M4 (§2). That a mark note
  holds a material point is the decision record's choice, not the owner's
  (§1). 76: `run -o x.svg` ships early, as S23 after S22, and each later PR
  adds one thing to its page, such as captions or arrows, held by S22's
  structural test until E7 pins the page. 77: batching a step's creases
  ([D22](decisions.md#d22-figures-holding-several-moves), [02
  §6.5](02-language-semantics.md#65-figures-holding-several-moves)) waits for M4
  ([#646](https://github.com/avalonalex/senbazuru/issues/646)).
- **78**, what may follow a turn-over or rotate in one step, **decided
  2026-10-28** as recommended ([the question as
  asked](https://github.com/avalonalex/senbazuru/issues/635#issuecomment-6486583488)):
  a step may end with one turn-over or rotate, and any move after it in the
  same step is refused, a second turn-over or rotate, `anchor` and `mark`
  included, by an error S19
  ([#640](https://github.com/avalonalex/senbazuru/issues/640)) names. It
  settles §2's "a fold then a turn" row and D22's.

## Research links

- [gap-step-annotation-channel](research/gap-step-annotation-channel.md): "A. What the page does today", "B. What the fixture and goldens show", "C. Turning over and the single camera", "D. When the crease graph grows", "E. Prior art for the marks (ideas only)", "(b) Marks extend `Diagram`; captions are placed by `Layout`", "(d) Where a turn-over axis passes, and how its loop is drawn", "(e) Golden plan".
- [C — renderers, CLI and formats](research/C-renderers-cli-formats.md) and [E1 — sequence languages](research/E1-prior-art-sequence-languages.md) "E. The human vocabulary".
- [gap-assignment-at-rest-convention](research/gap-assignment-at-rest-convention.md): why a written precrease is `F`, so fold-here lines come from notes.
