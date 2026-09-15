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
23 call lines and all 33 tracked goldens are untouched. `Diagram` gains arrow heads
and bodies (defaults emit today's bytes) and one shape, `Symbol`. `Layout` places
captions. `Render.Sequence` builds the notes from a run's *move records*, one per
checked move ([glossary](glossary-additions.md#running-a-sequence)), beside the
states `Sequence.Record.writtenStates` gives, the same states the written file
holds ([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)).
Milestone M3 (`run -o x.svg`, the book-style page;
[10 §1](10-roadmap-risks-questions.md#1-milestones)).

## Problem and evidence

### What the page draws today, with real numbers

`examples/quarter-fold-steps.fold` holds three states of a unit square: flat,
folded in half, folded in quarters (the test fixture is identical, `cmp`).
`test/golden/quarter-fold-steps.svg` pins its step page with arrows
([`SvgSpec.hs:379-380`](../test/Senbazuru/Render/SvgSpec.hs#L379-L380), through
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
| Turn over ([glossary](glossary-additions.md#origami)) | [#95](https://github.com/avalonalex/senbazuru/issues/95)'s half turn about x = 0 moves figure 3 from x∈[0.5, 1] to x∈[−1, −0.5], doubling the page's shared *extent* (the model region the page shows, [glossary](../docs/glossary.md#this-project)) and halving every figure. About the box centre, inference still draws a spurious arrow of up to 0.0975 model units on the bird sequence. | research "C. Turning over and the single camera", findings 12–13 (`python3`) |
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
imports, signature, definition and comments, leaves 23 call lines in 15 files:

| Arrows on (`True`) | Arrows off (`False`) |
| --- | --- |
| `Cli.hs:854` (the flag) · `FlapSpec.hs:292`, `:312`, `:322` · `SvgSpec.hs:133` · `CraneGallery.hs:38` · `FlapGallery.hs:92` · `PetalGallery.hs:45` · `BlintzGallery.hs:39` · `HelmetGallery.hs:38` | `BirdSequenceSpec.hs:79` · `BasicBaseSpec.hs:216` · `StepsSpec.hs:46`, `:56`, `:57`, `:61`, `:62`, `:68`, `:69` · `CraneSpreadGallery.hs:128` · `WingBendingGallery.hs:42` · `BasicBaseGallery.hs:145` · `study/fold-material/Main.hs:170` |

(The research note's list omits `FlapGallery.hs:92`.)

## Goals

1. A page drawn from a sequence reads like a book: captions, arrows of the right
   kind per move, [fold-here lines](glossary-additions.md#step-pages) (the creases
   a move is about to make, drawn on the figure before it), turn-over, rotate and
   repeat marks.
2. Kinds, lines and marks come from move records, never from guessing at frames.
3. `render --steps`, every gallery and all 33 goldens stay byte-identical.
4. A view flag changes how a step is drawn, never what it means.

## Non-goals

- Persisting notes in FOLD (until [#73](https://github.com/avalonalex/senbazuru/issues/73); [D18](decisions.md#d18-non-goals), [00](00-overview.md#non-goals)); `render --steps` drawing `frame_title` ([§9](#9-frame_title-and-assurance-point-opposite-ways)).
- Drawing an `expect refused` outcome: it produces no record and no state, and `run --report` prints it ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused)).
- Font metrics, wrapping or truncation (owner decision 7, [decisions §9](decisions.md#9-owner-decisions), [10 §6](10-roadmap-risks-questions.md#6-owner-decisions)); repeat leaders crossing cells.
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
4. **A study gallery author** keeps `stepPage`, or switches to `stepPageWith` to
   state kinds by hand.

## Requirements

**Channel**

- **R-06-1.** `Render.Steps` exports `stepPageWith :: Theme -> Budget -> Grid ->
  View -> [(Frame, StepNote)] -> Either StepError (Maybe Diagram)`, with no `Bool`
  beside the notes ([D7](decisions.md#d7-a-typed-step-note-reaches-the-page)).
- **R-06-2.** `stepPage`'s signature is unchanged and it is `stepPage theme budget
  grid view arrows = stepPageWith theme budget grid view . map (\f -> (f, noteFor
  arrows))`, `noteFor True = inferNote`, `noteFor False = silentNote`. One
  implementation; none of the 23 call lines is edited.
- **R-06-3.** `StepError` is unchanged
  ([`Steps.hs:58-62`](../src/Senbazuru/Render/Steps.hs#L58-L62)), so the CLI's match
  at [`Cli.hs:855-863`](../app/Senbazuru/Cli.hs#L855-L863) compiles
  ([D7](decisions.md#d7-a-typed-step-note-reaches-the-page)). Every note is
  drawable; the only new failures are `motionsAcross`'s and `creasesToCome`'s
  `FoldError` constructors ([05](05-prd-library-additions.md)).
- **R-06-4.** A presentation mark places a `Symbol` and suppresses inference on that
  pair only. `stepPageWith` never transforms a coordinate: frames arrive presented.

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
  compiler cannot flag: [`LayoutSpec.hs:32-35`](../test/Senbazuru/Diagram/LayoutSpec.hs#L32-L35),
  [`:42-44`](../test/Senbazuru/Diagram/LayoutSpec.hs#L42-L44),
  [`CreasePatternSpec.hs:394`](../test/Senbazuru/Render/CreasePatternSpec.hs#L394).

**Views**

- **R-06-8.** `seenFrom :: Basis -> SeenFrom` gives `FromReadersSide`,
  `FromOppositeSide` or `EdgeOn` as `basisForward`'s z is negative, positive or
  zero. `EdgeOn` means the camera looks along the sheet's plane, as `front` and
  `side` do, so a flat sheet projects to a line. `pageSide :: View -> [Frame] ->
  Either StepError SeenFrom` shares `stepPageWith`'s basis choice.
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
  or half turn keeps each figure's extent, the page union (the one box covering
  every figure's extent, which sets the scale,
  [`Layout.hs:110-112`](../src/Senbazuru/Diagram/Layout.hs#L110-L112)) and the
  scale within 1e-12 × `modelSpan` (the model's size). Nothing is asserted for
  other views or rolls.
- **R-06-13.** Rotate marks show signed eighths; repeat marks show a figure range;
  both are `Symbol`s inside their figure.

**Growing graphs**

- **R-06-14.** For `InferArrows` and `InferArrowsAs`, `stepPageWith` calls
  `motionsBetween` when the graphs are equal and `motionsAcross` otherwise.
- **R-06-15.** Fold-here lines go on the figure before the move, at `before`
  positions, styled by the note's kind as seen, never by the crease's assignment.

**Several moves**

- **R-06-16.** For each moving record of a step, in order, `Render.Sequence` gives
  that record's arrows, with the record's kind, from `motionsBetween` over its
  before surface under `displayBefore` and its after surface under `displayAfter`.
  Those are the record's presentation composed with its anchor placement, before
  and after the move, which the record keeps as separate fields and applies to its
  unpresented surfaces
  ([D14](decisions.md#d14-material-consumption);
  [01 §2.2](01-architecture.md#22-contract-1-moverecord)). A move whose moving
  paper is two groups joined only through still paper gets one arrow per group, as
  `motionsBetween` already splits them
  ([`Step.hs:175-192`](../src/Senbazuru/Origami/Step.hs#L175-L192);
  [D7](decisions.md#d7-a-typed-step-note-reaches-the-page)).
- **R-06-17.** A fold-and-unfold draws its fold arrow, its unfold arrow and one
  fold-here line, although its figure's frames are identical in position
  ([D7](decisions.md#d7-a-typed-step-note-reaches-the-page)).

**Captions**

- **R-06-18.** Captions are `Label`s placed by `Layout`: baseline one gutter below
  the cell's shared box (the union of every figure's extent, in which each figure
  is centred, [`Layout.hs:110-112`](../src/Senbazuru/Diagram/Layout.hs#L110-L112),
  [`:137`](../src/Senbazuru/Diagram/Layout.hs#L137)), raised by a page-unit
  `Offset` for descenders, left-aligned with the cell.
- **R-06-19.** `gridOf`'s output is unchanged; a trailing gutter joins the page box
  only when some figure has a caption. Under owner decision 7's recommended default
  ([decisions §9](decisions.md#9-owner-decisions)), a page on which some figure has
  a caption is laid out with a gutter of at least 42/340 of a figure,
  `max (gridGutter grid) (42/340)` (**SKETCH**, §8); a page with no caption uses
  `gridGutter` ([`Layout.hs:73`](../src/Senbazuru/Diagram/Layout.hs#L73)) as given,
  so no existing page changes.

**Pages from a run**

- **R-06-20.** `Render.Sequence.stepNotes :: Run -> Either WriteProblem [(Frame, StepNote)]`
  returns exactly the frames `Sequence.Write` writes to `file_frames`, in order,
  because both take them from `Sequence.Record.writtenStates`
  ([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)). It is not
  total: it shares `writtenStates`' refusals, `WriteMissingAngles` and
  `WriteNonFiniteAngle` ([D4](decisions.md#d4-written-frames-follow-the-state-rule)).
- **R-06-21.** Figure *j* draws state *j* − 1 and its note follows
  [§2](#2-from-a-run-to-notes). Its caption is the caption of the step that starts
  from that state, which is the state's `frame_title`, or `closing` on the last
  figure ([D24](decisions.md#d24-states-figures-and-their-numbers)).
- **R-06-22.** A `mark` is labelled on each flat figure where `Origami.Visible`
  shows its material point.
- **R-06-23.** A step's authored `sample` poses are figures of their own, after the
  figure of the state the step starts from and before its end state's, in parameter
  order, each with no caption and `NoArrows`. A step that writes no state (every
  move `expect refused`) has no figure
  ([D24](decisions.md#d24-states-figures-and-their-numbers),
  [D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused)).

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
    noteMarks        :: ![(Text, V3)] }
inferNote, silentNote :: StepNote            -- InferArrows / NoArrows; every other field empty
data SeenFrom = FromReadersSide | FromOppositeSide | EdgeOn
```

Positions are in the *written frame*'s coordinates, already presented
([glossary](glossary-additions.md#the-fold-format)), and the page projects them
through its one basis as `withArrows` projects a motion
([`CreasePattern.hs:592-605`](../src/Senbazuru/Render/CreasePattern.hs#L592-L605)).
`inferNote` carries `NoFoldLines`: equal graphs have no creases to come, and a
default that could draw them is one more thing to leak into today's bytes.
`noteMarks` holds each mark's label and position, because M3 includes marks and
[D2](decisions.md#d2-references-named-on-the-sheet-and-resolved-by-slot) labels a
mark on each figure where it is visible
([D7](decisions.md#d7-a-typed-step-note-reaches-the-page);
[02 §4.5](02-language-semantics.md#45-landmarks-mark-let-step-names)).

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
holds by construction, and `stepNotes` returns `Either WriteProblem` because
`writtenStates` can refuse
([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)).

| Step holds | Note on the figure of the state the step starts from |
| --- | --- |
| Moves that turn paper (fold, unfold, macro) | `GivenArrows` per R-06-16; `GivenFoldLines` from each record's new creases at `recordBefore` positions (the record's surface before the move) under `displayBefore`, with that record's kind |
| A move that creases and turns nothing (`NoMotion`) | Its fold-here line only |
| `fold and unfold` | Two records: a valley or mountain arrow out, an unfold arrow back |
| `turn over` / `rotate` | `notePresentation`, derived because no record stores an axis. The direction comes from which turn it was (`left-right` along y, `top-bottom` along x, `rotate` along z); the axis point is the centre of the displayed state before the turn, `recordBefore` under `displayBefore`, with cz the middle of its z range ([D5](decisions.md#d5-presentation-and-the-readers-side); [02 §5.2](02-language-semantics.md#52-presentation-moves-no-paper)). Which turn it was is read from the record; see [Dependencies](#dependencies) |
| A fold then a turn | The fold's arrows and the turn's mark |
| `repeat A..B` | `noteRepeat` with those figures, plus the expanded moves' arrows ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused)) |
| `checkpoint` | `NoArrows`: the pair breaks the *prefix rule*, under which each frame's vertex list begins with the previous frame's, with equal material coordinates, so ids carry over ([D6](decisions.md#d6-crease-graphs-grow-between-frames), [D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused); [05 L5](05-prd-library-additions.md#l5-motionsacross-creasestocome-and-a-non-convex-point-test), [02 §9](02-language-semantics.md#9-repeat-checkpoint-not-modelled-expect-refused)) |
| `not modelled` | Caption, `NoArrows`. The run stops there and keeps every state before it, so this is the last figure ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused)) |
| `expect refused` | Nothing. It is a move inside a step that produces no record and no state; its outcome is kept on the step in the `Run` and printed by `run --report`, never drawn. A step whose moves are all `expect refused` writes no state, so it has no figure and its caption is drawn nowhere ([D21](decisions.md#d21-repeat-checkpoint-not-modelled-expect-refused), [D24](decisions.md#d24-states-figures-and-their-numbers)) |
| A macro's authored `sample` poses | Nothing on this figure. Each pose is a state and a figure of its own, between this figure and the end state's, with no caption and `NoArrows` (R-06-23). A macro with no `sample` adds no figure: the interior poses the runner also checks, `RunSettings.macroChecks` of them, are evidence, not states ([D9](decisions.md#d9-macro-moves-as-named-angle-relations)) |

### 3. Arrow heads, bodies and `Symbol`

The heads follow Robert Lang's diagramming conventions as summarised in research
finding 20: solid head = valley (today's), hollow one-sided head = mountain, hollow
two-sided head = unfold, cleft tail = push. Emission, **SKETCH**, with
`headLength` clamped as at [`Svg.hs:215`](../src/Senbazuru/Render/Svg.hs#L215):
`SolidHead` is today's filled triangle path byte for byte; `HollowHalfHead` is a
single barb, one stroked open line from the tip back to a point one head-length
back and 0.4 of it to one side of the shaft (in `Svg.hs`'s names, `tip` to
`base + half·across`, [`:207-217`](../src/Senbazuru/Render/Svg.hs#L207-L217));
`HollowDoubleHead` is a stroked closed triangle. Neither hollow head sets `fill`,
so the group's `fill="none"` holds.

```haskell
-- Senbazuru.Diagram (SKETCH), still FOLD-ignorant
data Glyph = TurnOverLoop !V2 | RotateMark !Int | RepeatMark !Int !Int | EdgeOnMark
data Shape = … | Symbol !Stroke !Double !V2 !Glyph   -- stroke, page-unit size, model anchor, glyph
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
([`:103-111`](../test/Senbazuru/Render/CreasePatternSpec.hs#L103-L111)). It cannot
flag the three wildcards of R-06-7; `isArrow` there would silently pass a loop
drawn in place of an arrow.

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
| Blintz and crane galleries ([`BlintzGallery.hs:38`](../study/fold-material/BlintzGallery.hs#L38), [`CraneGallery.hs:37`](../study/fold-material/CraneGallery.hs#L37)) | (−1, 0, 1), (−1, 1, √2) | opposite |

A roll leaves `basisForward` alone
([`Camera.hs:227-235`](../src/Senbazuru/Render/Camera.hs#L227-L235)), so rolling
never flips a head. The `top` and `bottom` rows are why kinds are stated from the
reader's side and only drawn as seen: if "valley" meant "as the camera sees it",
one source would write different FOLD signs under `--view bottom` and `--view top`,
which [D5](decisions.md#d5-presentation-and-the-readers-side) forbids
([02 §5.4](02-language-semantics.md#54-render-options-never-change-meaning)). The
gallery row shows the opposite side is not hypothetical: two existing galleries
already draw from it.

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
state [`usage.md:1017-1018`](../docs/usage.md) calls frame 12.

R-06-12 asserts only the "yes" rows. Seen from above, the `left-right` turn mirrors
the picture across a line parallel to model y. At a 45° roll that line lies
diagonal on the page, and a mirror across a diagonal swaps the figure's width and
height, which changes a non-square figure's box. Under `iso` the projection is not
symmetric about the axis at all. For the same reason R-06-12 leaves out `rotate` by
a quarter turn: it swaps a non-square figure's width and height on every page.

**Rotate and repeat.** `RotateMark k` draws k/8 in a circle with an arrow in the
turning sense; `RepeatMark a b` a box holding the range (Lang). Both sit inside the
figure: a leader to other figures would cross cells, and `Layout` exists so a mark
"can never collide with a different figure"
([`Layout.hs:42-45`](../src/Senbazuru/Diagram/Layout.hs#L42-L45)).

### 6. Growing crease graphs and fold-here lines

A run's frames gain creases between figures. `motionsAcross` matches vertices by
*material coordinates* (where each point lies on the unfolded sheet, which never
changes) and `creasesToCome` returns new creases at `before` positions; both are in
[05](05-prd-library-additions.md) and decided in
[D6](decisions.md#d6-crease-graphs-grow-between-frames). `motionsBetween` stays in
use whenever graphs are equal (R-06-14), which keeps the 12 arrow-bearing goldens
structurally unchanged: all pass `motionsBetween` today. One behaviour changes from
refusal to drawing: `render --steps --arrows` on a growing file with
`senbazuru:material_coords`, refused today with `FramesDiffer`.

Fold-here lines are styled by the kind as seen because the quarter fixture's second
fold makes a `V` and an `M` crease in one valley fold; styling by assignment
reproduces the half-and-half line of the existing golden.

### 7. Figures holding several moves

"Fold and unfold in front `[corner south-west, corner north-east]` moving `corner
south-east`" on `sheet square`, where `in front` means a valley as seen
([02 §5.1](02-language-semantics.md#51-the-readers-side)): the moving triangle
(0, 0), (1, 0), (1, 1) has corner mean (2/3, 1/3); folded flat across y = x it
lands on (1/3, 2/3) (`python3` arithmetic, **UNVERIFIED** through `foldFrameWith`
until M2's runner exists).

The figure's before and after frames are identical, so inference draws nothing.
The two records draw a valley arrow (2/3, 1/3) → (1/3, 2/3) and an unfold arrow
back. `arrowFor` bows "always to the same side" of its own direction
([`Style.hs:356-358`](../src/Senbazuru/Diagram/Style.hs#L356-L358), `sideways` at
[`:384`](../src/Senbazuru/Diagram/Style.hs#L384)), so the reversed arrow bows the
other way and the pair reads as out and back. One valley-dashed fold-here line lies
on the diagonal. [D22](decisions.md#d22-figures-holding-several-moves) admits a
move to a figure only if its moving paper is where the figure draws it, and counts
a fold-and-unfold pair as one move
([02 §6.5](02-language-semantics.md#65-figures-holding-several-moves)). That makes
the fold arrow true on the drawn state. The unfold arrow is drawn from the fold
record's after positions back to where the paper started.

### 8. Captions and the gutter

**Placement.** A cell is a figure's shared box plus a *gutter*, 0.1 of a figure's
size by default ([`Layout.hs:95`](../src/Senbazuru/Diagram/Layout.hs#L95),
[`:121`](../src/Senbazuru/Diagram/Layout.hs#L121);
[glossary](glossary-additions.md#step-pages)). The caption's baseline sits one
gutter below the shared box, the top of the next row's box, raised by a page-unit
`Offset` of 0.25 × type size, 3.5 units at size 14 (**SKETCH** constant). One
`rsvg-convert -z 10` render on this Mac of the caption below at 14 units of
`sans-serif`, which `fc-match` resolves to Verdana, scanned with `python3`, puts
ink 3.0–3.1 units below the baseline (at 0.1-unit resolution), so the raise clears
it by about 0.4. Glyphs grow upward into the gutter: never into another row, but
into their own figure when the gutter is thinner than the type, the trade the
numbers already make ([`Layout.hs:42-45`](../src/Senbazuru/Diagram/Layout.hs#L42-L45)).

**Overlap** (`python3`, following `gridOf` and `fitBox`,
[`Geometry.hs:193-213`](../src/Senbazuru/Geometry.hs#L193-L213)). Three figures in
a row make a page box 3.2 figure-widths wide:

| Page | Content | Scale | Gutter on page | Type ([`Style.hs:227`](../src/Senbazuru/Diagram/Style.hs#L227)) |
| --- | --- | --- | --- | --- |
| CLI default, 400 × 400, margin 16 ([`Svg.hs:96-105`](../src/Senbazuru/Render/Svg.hs#L96-L105)), `--columns 3` | 368 × 368 | 368 / 3.2 = 115 | 11.5 | 14 |
| `renderSteps` test page, 400 × 200, margin 10 | 380 × 180 | 380 / 3.2 = 118.75 | 11.875 | 14 |

The second scale is the golden's 118.75 above, so captions overlap their figure on
both default pages. On a three-column CLI page a gutter of g figures is
g × 368 / (3 + 2g) page units, which reaches 14 only when g ≥ 42/340 ≈ 0.124.
A `python3` check for this reconciliation: at g = 42/340 the CLI page's scale is
113.33 and its gutter 14.00 units; the `renderSteps` page's scale is 117.03 and its
gutter 14.46, since its own bound is 42/352. Width limits the scale on both pages,
with or without a trailing gutter.

**The recommended default.** Owner decision 7
([decisions §9](decisions.md#9-owner-decisions)) recommends exactly that bound:
captioned pages get a gutter of at least 42/340 of a figure (R-06-19), uncaptioned
pages keep the gutter they are given, and overflow across cells is accepted and
stated. It is still the owner's to decide before M3.

**Overflow.** The same render measures "Fold the left half behind, onto the right."
at about 236.5 units of ink against a stride (one figure plus one gutter,
[`Layout.hs:119-121`](../src/Senbazuru/Diagram/Layout.hs#L119-L121)) of
1.1 × 115 = 126.5, so it spills across the next figure; the backend has no font
metrics ([`Svg.hs:177-180`](../src/Senbazuru/Render/Svg.hs#L177-L180)) to wrap or
truncate by, which is why the default accepts overflow rather than guessing widths.

**Why the trailing gutter is conditional.** It makes a one-row page box 1.1 tall;
`fitBox` centres the box, so every y moves, including figure 1's number label at
`y="54.875"`: the figure's top edge, 40.625 (margin 10 plus (180 − 118.75)/2 of
vertical centring), plus the label's drop, 0.12 of the figure's height
([`Layout.hs:155`](../src/Senbazuru/Diagram/Layout.hs#L155); not the 0.1 gutter).
[`LayoutSpec.hs:85`](../test/Senbazuru/Diagram/LayoutSpec.hs#L85) pins only the
horizontal case, a one-figure page exactly one figure wide; the vertical one is
pinned by the goldens (`y="54.875"`) and by A12. The wider captioned gutter is
conditional for the same reason: it changes the scale.

### 9. `frame_title` and assurance point opposite ways

A state's `frame_title` is the caption of the step leaving it, the next step that
writes a state (`closing` on the last), and its `senbazuru:assurance` is the
evidence of the step that produced it
([D4](decisions.md#d4-written-frames-follow-the-state-rule),
[D24](decisions.md#d24-states-figures-and-their-numbers);
[caption](glossary-additions.md#step-pages),
[02 §11](02-language-semantics.md#11-written-frames)). A book puts the caption with
the arrow, on the figure before, and `run -o x.svg` does the same.

A file cannot say which convention its titles follow. The fixture puts "Step 2:
folded in half" on the half-folded state; a sequence file written from the
quarter-fold source ([04](04-prd-sequence-source-and-cli.md#a-first-source-read-line-by-line))
puts "Fold the top half down in front, onto the bottom." there. Whichever
convention `render` assumed, one of those files would get the wrong words under its
figures, and drawing anything at all would move `quarter-fold-steps.svg`. So
`render --steps` never draws `frame_title`
([D7](decisions.md#d7-a-typed-step-note-reaches-the-page)).
[#94](https://github.com/avalonalex/senbazuru/issues/94) closes at M3 through
`run -o x.svg`; its done-when (fixture titles drawn under `render`'s figures, read
with `gh issue view 94`) is amended at M0
([decisions §3](decisions.md#3-recorded-text-this-design-changes) row 7 and
[§10](decisions.md#10-corrections) item 3, written out in
[01 §4.7](01-architecture.md#47-corrections-to-six-issues)).

### 10. Rejected alternatives

| Rejected | Why |
| --- | --- |
| A `Bool` beside the notes | Two switches answer one question, arrows or not, and they can disagree ([D7](decisions.md#d7-a-typed-step-note-reaches-the-page)) |
| Changing `stepPage`'s arity | 23 lines in 15 files for no drawing change |
| A sum-type `StepError` (research sketch) | Breaks `Cli.hs:855-863`; unnecessary once every note is drawable |
| Presentation applied inside the page, about page axes | The runner would need a camera, written files would depend on `--view`, and frames that arrive presented would be presented twice ([D5](decisions.md#d5-presentation-and-the-readers-side)) |
| #95's axis at x = 0 | Doubles the union, halves the scale |
| Kind from the changed assignment (#36) | Ambiguous per motion |
| Checking a stated kind against an inferred one | Inference trusts winding as written, which a backwards-wound file breaks (AGENTS.md gotchas); records are already checked |
| Backfilling future creases | Figure 1 would show the second fold |
| A page-unit band below figures (#94) | `Layout` has no page units; the recorded bug |
| One arrow with heads at both ends for fold-and-unfold | `ArrowPath` has one head; [D7](decisions.md#d7-a-typed-step-note-reaches-the-page) draws arrows from move records, one kind each |
| One display field per record, applied to both surfaces | It cannot give a `Presented` record's before display, nor keep presentation apart from anchor placement, which animation needs as separate nodes ([D14](decisions.md#d14-material-consumption)) |
| A total `stepNotes` | It calls `writtenStates`, which refuses a frame with missing or non-finite angles ([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)) |
| Sample poses written to the file but left off the page | The page would no longer draw exactly the states the file holds ([D24](decisions.md#d24-states-figures-and-their-numbers)) |

## Acceptance criteria

[09](09-testing-and-acceptance.md) places these in CI.

| # | Criterion | Red if |
| --- | --- | --- |
| A1 | `stepPage t b g v x fs == stepPageWith t b g v (map (\f -> (f, noteFor x)) fs)` for both `x` on the quarter fixture, `bird-base-sequence.fold` and `StepsSpec`'s sheets | a default in `inferNote`/`silentNote` leaks, e.g. `InferFoldLines` |
| A2 | On the committed branch, `git diff --name-only --diff-filter=MD origin/main...HEAD -- test/golden/` prints nothing and the same command with `--diff-filter=A` lists exactly the new goldens below ([D16](decisions.md#d16-testing-and-acceptance); [09 §1.2](09-testing-and-acceptance.md#12-tracked-goldens-stay-byte-identical)). Both print nothing today (run 2026-09-15) | `SolidHead` emission reorders an attribute; a gutter appears without a caption; a golden is added that this table does not list |
| A3 | `quarter-fold-steps.svg` and the pinned `bird-base-sequence-arrows.svg` stay byte-identical, with the by-hand `cmp` of `render --steps --arrows` on both multi-frame files in `examples/`, as [09 §1.3](09-testing-and-acceptance.md#13-multi-frame-examples-draw-the-same-step-pages) sets out | presentation classification ([05](05-prd-library-additions.md)) fires on a real fold |
| A4 | Each head, body and glyph emits equal page bytes at model sizes 1 and 400, extending [`SvgSpec.hs:251-256`](../test/Senbazuru/Render/SvgSpec.hs#L251-L256) | a hollow head or loop is sized in model units |
| A5 | `seenFrom` gives §4's table for the five named views and two gallery bases, and a roll of 1 radian changes nothing | `z > 0` is read as the reader's side |
| A6 | Under `View (Just bottomUp) 0` the same notes draw `HollowHalfHead` where `top` draws `SolidHead`, with dashes swapped too | inversion reaches heads but not dashes |
| A7 | With and without a turn-over, figure extents and page box agree within 1e-12 × span on `top` and `bottom` at rolls 0, 90°, 180°, 270°, for the quarter fold and bird `file_frames[13]` (`--frame 14`) | the axis passes through x = 0 or the corner mean |
| A8 | On `iso`, bird `file_frames[13]`'s extent changes across the turn (0.4142 × 0.6118 → 0.9981 × 0.3335, within 1e-4) | the turn is computed about a page axis, or the page re-fits figures after a turn, so the `iso` extent stays equal |
| A9 | A figure with a presentation mark has one `Symbol` and no `Arrow`; `CreasePatternSpec` counts symbols beside `arrowsIn` | inference is not suppressed on the marked pair |
| A10 | On each single-move figure of the blintz sequence (M2), `GivenArrows` from its record equal `InferArrowsAs` ends within 1e-12 × span | `displayBefore` or `displayAfter` is not applied, or record ids are not in `recordBefore`'s numbering |
| A11 | For the quarter-fold run, `fmap (map fst) (stepNotes run)` equals the `file_frames` of `writeSequence`'s file, both `Right`. In review: `Render.Sequence` imports `Sequence.Record` and `Sequence.Error` and no other sequence module, and no `View` is an argument of `runSequence`, `writeSequence` or `stepNotes`. Sharing `writtenStates` makes the frames equal by construction; the test guards what the construction does not, `stepNotes` dropping or reordering states | `stepNotes` filters `writtenStates` (for example drops sample states) or rebuilds frames without the [state rule](glossary-additions.md#the-fold-format); `Render.Sequence` imports `Sequence.Write` or `Sequence.Run`; a `View` reaches the runner, the writer or `stepNotes` |
| A12 | `LayoutSpec`: for 1–60 captioned figures no caption anchor lies below its cell; the page box's height includes a trailing gutter exactly when a caption exists; under owner decision 7's default, the gutter is at least 42/340 exactly when a caption exists | the gutter is added unconditionally; a captioned page keeps a 0.1 gutter; an uncaptioned page's gutter changes |
| A13 | `motionsAcross == motionsBetween` on every consecutive pair of the quarter fixture and FlapSpec's four material-frame sequences | `motionsAcross` visits rings in another order |
| A14 | For every glyph, `shapePoints (Symbol s k a g) == [a]` and `mapShapePoints f (Symbol s k a g) == Symbol s k (f a) g` | a glyph's page-unit geometry, or `TurnOverLoop`'s vector, enters the extent or is moved by layout |
| A15 | `stepPageWith` on the quarter fixture's frames with `Rotated (-3) p` on figure 1 and `noteRepeat = Just (1, 2)` on figure 3 emits one `RotateMark (-3)` and one `RepeatMark 1 2`, each anchored inside its own figure's cell | the sign is dropped, the range is shifted, or a mark is anchored in another figure's cell |
| A16 | On the quarter fixture's state 1, a mark on a face `Origami.Visible` shows gets one `Label` and a mark on a face it hides gets none | labelling ignores `Visible` |
| A17 | Under `View (Just frontOn) 0`, the frames and notes of `quarter-fold-turn-over-steps.svg` (below) give figure 3 one `TurnOverLoop (V2 0 1)` anchored at the midpoint of that figure's bottom edge | the zero-length projected axis is normalised into NaN, or the loop is dropped because the axis has no page direction |

`run`'s warning is CLI behaviour, checked by hand (the CLI is untested by design,
[`Cli.hs:5-8`](../app/Senbazuru/Cli.hs#L5-L8);
[D13](decisions.md#d13-the-run-verb-and-io)); `pageSide` carries the tested logic.

### Goldens that must stay byte-identical (all 33, `git ls-files test/golden`)

| Group | Goldens (producer) | What here could move them |
| --- | --- | --- |
| Step pages with arrows (12) | `quarter-fold-steps.svg` (`SvgSpec.hs:380`); `quarter-fold-step-1.svg` (`:372`, `withArrows` on one frame); `checked-flap.svg`, `checked-flat-flap.svg`, `checked-stack-flap.svg`, `checked-aligned-stack.svg` (`FlapSpec.hs:294`, `:314`, `:324`); `checked-blintz.svg` (`BlintzSequenceSpec.hs:127`); `checked-helmet.svg` (`HelmetSequenceSpec.hs:187`); `checked-crane.svg` (`CraneWingSpec.hs:145`); `checked-petal.svg` (`CheckedPetalSpec.hs:138`); `checked-bird-above.svg`, `checked-bird-below.svg` (`CheckedBirdSpec.hs:173`) | `ArrowPath` defaults; `inferNote`; the `motionsBetween`/`motionsAcross` choice |
| Step pages without arrows (4) | `bird-sequence-iso.svg`, `bird-sequence-bottom.svg` (`BirdSequenceSpec.hs:84`); `frog-sequence.svg` (`BasicBaseSpec.hs:220`); `bent-strip.svg` (`WingBendingSpec.hs:100`) | `silentNote`; the trailing gutter and the captioned gutter; basis choice |
| Single figures (14) | `unit-square`, `diagonal-cp`, `bird-base`, `bird-base-folded`, `quarter-fold`, `quarter-fold-folded`, `letter-fold-folded`, `crane-folded`, `kabuto-underside`, `quarter-fold-offset`, `letter-fold-offset`, `simple-iso-offset`, `simple-iso`, `squaretwist-iso` (`.svg`, `SvgSpec.hs:334-495`) | `shapeToSvg` for `Label`, `Offset`, `Polyline`, `Fill` |
| GLB (3) | `quarter-fold-folded.glb`, `crane-folded.glb`, `simple.glb` (`GltfSpec.hs:648`, `:653`, `:658`) | nothing here reaches `Render.Gltf`; listed so a stray import shows |

### New goldens

| Golden | Input | Red if |
| --- | --- | --- |
| `quarter-fold-steps-noted.svg` | Fixture frames; hand notes: captions on 1–2, `closing` on 3, `InferArrowsAs MountainArrow` on 1 and `ValleyArrow` on 2; the `renderSteps` page | the mountain head reverts to solid; captions go in a model-unit band (the page rescales); the trailing gutter is missing; the gutter is below owner decision 7's 42/340, if that default is taken |
| `quarter-fold-steps-noted-bottom.svg` | The same notes under `View (Just bottomUp) 0` | heads or dashes are not inverted; a caption is rewritten |
| `quarter-fold-turn-over-steps.svg` | The fixture's three states, then a fourth: state 2 (folded in quarters) turned by the `left-right` rule. `TurnedOver` goes on figure 3, which draws state 2. | the axis is at x = 0 (every coordinate moves); an inferred arrow joins the loop; the loop lies along the axis or follows model size |
| `quarter-fold-growing-steps.svg` | New fixture `test/fixtures/quarter-fold-growing.fold`: an uncreased square, one fold, two folds; [state-rule](glossary-additions.md#the-fold-format) frames with `senbazuru:material_coords`. **UNVERIFIED**, not yet written: `jq` must show 4, 6, 9 vertices, each frame's list beginning with the previous one's (the prefix rule, [§2](#2-from-a-run-to-notes)). | figure 1 draws the second crease; `motionsAcross` refuses; figure 2's fold-here line is solid or half mountain |
| `diagonal-precrease-steps.svg` | A run of `sheet square` with §7's step | no arrow is drawn (inference used); the unfold head is solid; the fold-here line is missing |
| Quarter-fold test 1 and 2 pages | Owned by [09](09-testing-and-acceptance.md) ([D16](decisions.md#d16-testing-and-acceptance)) | as stated there |

## Dependencies

| On | For |
| --- | --- |
| M2 ([02](02-language-semantics.md), [04](04-prd-sequence-source-and-cli.md)) | Records carrying `recordPresentation` and `recordPlacement`, each before and after, with `displayBefore` and `displayAfter` computed from them ([D14](decisions.md#d14-material-consumption)); `Run` and `writtenStates` in `Sequence.Record` ([D23](decisions.md#d23-the-sequence-modules-and-where-run-lives)); the state-rule writer; presentation axes; which turn a `turn over` or `rotate` record was (below the table) |
| [05](05-prd-library-additions.md) | `motionsAcross`, `creasesToCome`, `fitRigid` and `Step` classification with the `Origami.Step` header rewrite ([decisions §3](decisions.md#3-recorded-text-this-design-changes) row 13, written out in [01 §4.13](01-architecture.md#413-srcsenbazuruorigamistephs30-34)) |
| M0 ([10 §1](10-roadmap-risks-questions.md#1-milestones)) | Amended done-when of [#36](https://github.com/avalonalex/senbazuru/issues/36) (reflection as turn-over cannot be met) and #94 ([decisions §3](decisions.md#3-recorded-text-this-design-changes) row 7; [§10](decisions.md#10-corrections) items 2 and 3) |
| Issues | Closes #36, #94 at M3; follows #95 (M2); advances #48 via `noteLayers`; relates to [#60](https://github.com/avalonalex/senbazuru/issues/60), [#97](https://github.com/avalonalex/senbazuru/issues/97) |

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

> **Open for the next version of decisions.** `recordKind :: MoveKind` must carry a
> rotate's written k and direction.
> [decisions §5](decisions.md#5-type-sketch) names the field and lists no
> constructors. The one sketch that does list them has a bare `Present`
> ([gap-study-consumption-contract](research/gap-study-consumption-contract.md),
> "(a) The per-step record, and who imports what"), which carries neither. The
> alternative is to decide that a rotate mark draws the same motion as a turn of at
> most four eighths, with a chosen direction for a half turn.

## Risks

- **Captions collide** with their own figure on both default pages unless owner
  decision 7's default gutter is taken, and long captions overflow across cells
  under any choice (§8); a golden records markup, not glyphs, so it catches
  neither.
- **Silent matchers** ignore `Symbol` (R-06-7); A9 guards the worst one.
- **Float noise.** Extents agree only within tolerance; eighth turns carry trig bits
  into written coordinates (owner decision 10; research finding 16).
- **`motionsAcross` byte identity** on equal graphs is argued, not run (research
  "Unverified"); R-06-14 avoids depending on it.
- **Sample figures** are decided (R-06-23) but cannot be drawn until M5's macros
  exist, so nothing exercises the rule before then.
- **Marks with paper in the air** go unlabelled: `Origami.Visible` works on
  flat-folded models ([`Visible.hs:1-8`](../src/Senbazuru/Origami/Visible.hs#L1-L8)).
- **`noteLayers`** is drawn by nothing until #48.

## Open questions for the owner ([10 §6](10-roadmap-risks-questions.md#6-owner-decisions))

Each has a recommended default in [decisions §9](decisions.md#9-owner-decisions).

- **7.** Caption overlap and overflow. Default: captioned pages get a gutter of at
  least 42/340 ≈ 0.124 (§8), uncaptioned pages are unchanged, and overflow across
  cells is accepted and stated. Otherwise: accept overlap (unreadable pages),
  squash with SVG `textLength` or truncate by estimated width (widths without font
  metrics), or refuse (some sequences cannot be drawn). Before M3.
- **9.** Does `examples/quarter-fold-steps.fold` migrate to the state rule, moving
  `quarter-fold-steps.svg` and `quarter-fold-step-1.svg`, or stay as the
  regression? Default: it stays, and the state-rule page is a new golden. Before
  M2.
- **10.** Eighth-turn presentation by trig (platform bits in written coordinates) or
  a `sheet square as diamond` start: it decides whether `RotateMark` ever shows an
  odd k. Default: trigonometry, with the platform bits stated. Before M2.

## Research links

- [gap-step-annotation-channel](research/gap-step-annotation-channel.md): "A. What the page does today", "B. What the fixture and goldens show", "C. Turning over and the single camera", "D. When the crease graph grows", "E. Prior art for the marks (ideas only)", "(b) Marks extend `Diagram`; captions are placed by `Layout`", "(d) Where a turn-over axis passes, and how its loop is drawn", "(e) Golden plan".
- [C — renderers, CLI and formats](research/C-renderers-cli-formats.md) and [E1 — sequence languages](research/E1-prior-art-sequence-languages.md) "E. The human vocabulary".
- [gap-assignment-at-rest-convention](research/gap-assignment-at-rest-convention.md): why a written precrease is `F`, so fold-here lines come from notes.
