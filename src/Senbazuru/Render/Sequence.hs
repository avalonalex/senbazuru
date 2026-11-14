-- |
-- Module      : Senbazuru.Render.Sequence
-- Description : A run of a fold sequence as one page of steps, a figure for each state it wrote.
--
-- A run hands back every state the paper reached ("Senbazuru.Sequence.Record"),
-- and "Senbazuru.Render.Steps" draws a list of frames, each with a /step
-- note/ saying what its figure carries besides the paper. This module joins
-- the two: 'stepNotes' gives each state the run writes a note, and 'runPage'
-- draws them and fits them to a page with their captions
-- ("Senbazuru.Diagram.Page"). The first is the channel that carries what a
-- run knows and its file does not (the arrows and fold-here lines of each
-- move, of the kind it was written as, so far; marks to come), so it is a
-- function of
-- its own that a test can hold to the file a run writes; the second is the one
-- composition that @run -o x.svg@ calls and the golden tests call
-- (@diagonal-precrease-steps.svg@, and #643's S37), so the two cannot draw the
-- page two ways.
--
-- It is a module of its own because of what it may import. It is the first
-- @Render@ module to know about fold sequences at all, and from them it may
-- import only "Senbazuru.Sequence.Record", for the run, and
-- "Senbazuru.Sequence.Error", for the refusal (PRDs\/decisions.md, §2 row 7).
-- Nothing here reaches the runner or the writer, and nothing there reaches a
-- camera: a 'View' is an argument of 'runPage' and of nothing a run or a
-- written file depends on, so the frames @run -o x.fold@ writes are the frames
-- every view draws.
--
-- == Figures follow states, not steps
--
-- The figures are 'writtenStates', exactly the frames
-- "Senbazuru.Sequence.Write" puts in @file_frames@, in order, none dropped and
-- none rebuilt, so the page shows what the file holds. Figure /j/ draws state
-- /j/ − 1 (PRDs\/decisions.md, D24): the two-step quarter fold,
-- @test\/fixtures\/quarter-fold.foldseq@, writes three states, the sheet, the
-- paper folded in half and the paper folded in quarters, and draws three
-- figures. A step whose moves were all @expect refused@ moved no paper and
-- writes no state, so it has no figure, and a step that writes a state equal
-- to the one before it, such as @anchor P@, has one that looks the same.
--
-- A figure's note belongs with the step that starts from its state, which is
-- where a book prints an instruction and the arrow for it: next to the picture
-- it starts from. Every note has its state's title as its caption, so each
-- figure's paper is the one @render --steps@ draws of that state of the
-- written file. A page none of whose captions has a word, and that carries
-- no mark above its figures, is laid out as @render --steps@ lays out that
-- file; otherwise each row is followed by a band for its captions, so the
-- rows stand further apart, the page is as tall as they need, and with a
-- height given the figures are drawn smaller ("Senbazuru.Diagram.Page").
--
-- == Arrows come from records, not from the states
--
-- @render --steps --arrows@ finds a file's arrows by comparing each frame
-- with the next, and that loses the one thing a book's arrow says besides
-- where the paper goes: whether it is folded towards the reader or away. The
-- quarter fold's second step is one fold in front, a valley, and it turns
-- one crease to +180° and another to −180°, because the paper it folds is
-- already doubled; no reading of the two frames gives it one kind. A run
-- kept each move as its author wrote it (a /move record/, see
-- docs/glossary.md, "Fold sequences"), so a figure's arrows are read from the
-- records of the step that starts from it, and each has the kind its move
-- was written as: valley for @in front@, mountain for @behind@, and an
-- unfold's own. 'stepArrows' says how, and why the arrows are a move's and
-- not a record's.
--
-- A /pre-crease/ (a fold laid flat again, docs\/glossary.md) ends where it
-- began, so comparing its paper before and after finds nothing, and its
-- arrow is read from the surface its fold reached ('recordFoldedPose'): one
-- arc there and back, the fold's head at the far end and the unfold's at its
-- tail, as books draw \"fold and unfold\" (the owner's choice of
-- 2026-11-13).
--
-- A step that turns no paper leaves its figure 'NoArrows': @anchor P@, a
-- @mark@, a turn-over or a rotate, whose mark on the page is not an arrow.
-- So has the last figure, which no step starts from.
--
-- == Fold-here lines come from hinges
--
-- A book draws a dashed line on the figure before a fold, where the paper
-- is about to fold: the valley dash for a fold in front, the mountain dash
-- for one behind, as the page sees it. Each fold and each pre-crease of the
-- step that starts from a figure draws one along its /hinge/, the line it
-- turns paper about, which its record keeps whether or not the move creased
-- it (owner decision 74). An unfold draws none. 'stepFoldLines' says how.
--
-- == A caption is its state's title
--
-- The caption under figure /j/ is state /j/ − 1's @frame_title@, which
-- 'writtenStates' sets to the caption of the step that leaves the state: the
-- next step that writes one, so a step of only @expect refused@ moves, which
-- writes none, has its caption under no figure. The last state's is the
-- source's @closing@ line, or, for a run stopped at @not modelled@, the
-- caption of the step it stopped at. The rule lives there, once, and the file
-- a run writes and the page it draws cannot disagree about it. It reads as an
-- off-by-one and is not: state 0, the sheet, carries step 1's instruction,
-- because that is the picture the reader folds step 1 from (PRDs\/06 §9).
--
-- A /sample/ pose, a figure M5 will draw between a step's start and its end
-- to show a move under way, takes no caption (R-06-23). Written as a state, it
-- must therefore carry no title, or it would print one here.
--
-- == A refused page names a step, never a figure
--
-- A figure the page cannot draw is refused as 'PageRefused', naming the state
-- by the step that ended at it: @step 2 (quarter): …@. The author holds a
-- source, whose steps they wrote, and not the page, whose figures a step of
-- only @expect refused@ shifts; a figure number would send them counting.
-- State 0, the sheet laid flat, was made by no step, and is named as the
-- writer names every state, @state 0@. The refusal is a 'SequenceError'
-- rather than the page's own 'StepError' because "Senbazuru.Sequence.Error"
-- sits below every @Render@ module and cannot import one; so the index the
-- page gives is looked up here, in the states it came from.
--
-- That is the refusal of a figure's paper. An arrow the page cannot work out
-- is refused as 'ArrowRefused' instead, which names the step the arrow's move
-- is in: an arrow is drawn on the figure its step starts from, so the step
-- that ended at that figure's state is the wrong one to send the author to
-- (the owner's choice of 2026-11-11). No run is known to reach it. The last
-- state needs no rule of its own, since no step starts from it and no arrow
-- is worked out for it.
module Senbazuru.Render.Sequence
  ( stepNotes,
    runPage,
    RunPageError (..),
  )
where

import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (groupBy)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NE
import Data.Maybe (mapMaybe)
import Senbazuru.Diagram.Layout (Grid)
import Senbazuru.Diagram.Page (FittedPage, Height, Page, PageFitError, fitPage)
import Senbazuru.Diagram.Style (ArrowKind (..), Theme)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types (EdgeId (..), Frame (..), VertexId (..))
import Senbazuru.Geometry.V3 (V3 (..), modelHair)
import Senbazuru.Geometry.VectorSpace (dot, norm, (*^), (^+^), (^-^))
import Senbazuru.Origami.Stacking (Budget)
import Senbazuru.Origami.Step (Motion (..), motionsAcross)
import Senbazuru.Render.Camera (View)
import Senbazuru.Render.Steps (Arrows (..), FoldLines (..), StepError (..), StepNote, noteArrows, noteCaption, noteFoldLines, silentNote, stepFigures)
import Senbazuru.Sequence.Error (SequenceError (..))
import Senbazuru.Sequence.Record
  ( MoveKind (..),
    MoveRecord,
    Run (..),
    Sense (..),
    StepOutcome (..),
    WrittenState (..),
    displayAfter,
    displayBefore,
    displayedFrame,
    recordAfter,
    recordBefore,
    recordFoldedPose,
    recordHinge,
    recordKind,
    recordMoveIndex,
    recordSense,
    recordStep,
    recordStepName,
    recordUnfolds,
    writtenStates,
  )

-- | Each state the run writes, as its file writes it, with the note its
-- figure is drawn with: the state's title as its caption, and the arrows of
-- the step that starts from it, read from that step's move records.
--
-- Not total, because writing the states is not: it shares
-- 'writtenStates'' refusals, each a 'WriteRefused' naming the state. A move
-- whose arrow cannot be worked out is an 'ArrowRefused' naming its step.
stepNotes :: Run -> Either SequenceError [(Frame, StepNote)]
stepNotes run = writtenStates run >>= notesFor run

-- | Why a run's page could not be drawn.
data RunPageError
  = -- | The run's own refusal: a state that cannot be written; a figure
    -- the page cannot draw, named by the step that ended at its state; or
    -- an arrow it cannot work out, named by the step whose move it shows.
    RunRefused !SequenceError
  | -- | The page, as given, has no room for its figures and their captions.
    -- Not a fault of the run, which a larger page draws.
    PageDoesNotFit !PageFitError
  deriving stock (Eq, Show)

-- | Each in its own words.
instance Explain RunPageError where
  explain = \case
    RunRefused err -> explain err
    PageDoesNotFit err -> explain err

-- | The run's page: 'stepFigures' over 'stepNotes', fitted to the page with
-- their captions ('fitPage'), a figure the page cannot draw refused as the
-- step that ended at its state, and an arrow it cannot work out as the step
-- whose move it shows. 'Nothing' only for a run whose states hold no
-- geometry, which a run never writes.
runPage ::
  Theme ->
  -- | How hard to look for a layer order, for the states that need one.
  Budget ->
  Grid ->
  -- | Where to look from and which way up, as for 'stepFigures'.
  View ->
  -- | Whether the page keeps its height or grows to fit its captions.
  Height ->
  Page ->
  Run ->
  Either RunPageError (Maybe FittedPage)
runPage theme budget grid view height page run = do
  states <- first RunRefused (writtenStates run)
  notes <- first RunRefused (notesFor run states)
  figures <- first (RunRefused . refused states) (stepFigures theme budget view notes)
  first PageDoesNotFit (fitPage theme grid height page figures)
  where
    -- The page counts places in the list it was given, which are the states'
    -- numbers, since 'notesFor' keeps every one in order.
    refused states (StepError k why) = PageRefused k (producer =<< stateNumbered k states) why

    -- Unreachable for a 'Nothing': the page names only places in its list.
    -- Kept because the alternative is a partial index, and a state found
    -- under no step is still named rightly, by its number.
    stateNumbered k states = case drop k states of
      st : _ -> Just st
      [] -> Nothing

    producer st = do
      n <- stateStep st
      pure (n, nameOf n)

    -- Unreachable for a step not in 'runSteps', which every written state's
    -- step comes from; such a step would be named by its number alone.
    nameOf n = case [outcomeName outcome | outcome <- runSteps run, outcomeStep outcome == n] of
      name : _ -> name
      [] -> Nothing

-- | Every state, in order, with its note: its title as the caption, and
-- the arrows and fold-here lines of the step that starts from it.
--
-- That step is the one that ended at the next state, so the states are
-- paired with their successors and the last state has no such step. The
-- pairing is by the states written and not by step numbers or captions,
-- because those disagree with it in two places. A step of only
-- @expect refused@ writes no state, so the step after it starts from the
-- state before it. And a run stopped at @not modelled@ keeps the records of
-- the moves its last step made before the stop, though that step wrote no
-- state: the last figure carries that step's caption and must not carry its
-- arrows or lines, which would show a fold whose result the page never draws
-- (PRDs\/decisions.md, D21). No state names the stopped step as the one that
-- ended at it, so its records are found by no figure.
notesFor :: Run -> [WrittenState] -> Either SequenceError [(Frame, StepNote)]
notesFor run states = traverse noted (zip states (map stateStep (drop 1 states) <> [Nothing]))
  where
    noted (st, leaving) = do
      arrows <- maybe (pure []) (stepArrows . recordsOf) leaving
      let foldLines = maybe [] (stepFoldLines (stateFrame st) . recordsOf) leaving
      pure
        ( stateFrame st,
          silentNote
            { noteCaption = frameTitle (stateFrame st),
              -- No arrows is 'NoArrows', never an empty list of given ones,
              -- and no lines 'NoFoldLines', so a figure with nothing to say
              -- is the one @render --steps@ draws of its state.
              noteArrows = if null arrows then NoArrows else GivenArrows arrows,
              noteFoldLines = if null foldLines then NoFoldLines else GivenFoldLines foldLines
            }
        )
    recordsOf n = [record | record <- runRecords run, recordStep record == n]

-- | The arrows of one step's records, in the order its moves were written:
-- for each move that turned paper, an arrow for each piece of paper that
-- moved as one, of the kind the move was written as; and for each
-- pre-crease, an arc to where its fold took that paper and back.
--
-- == One arrow for a move, not for a record
--
-- A move usually leaves one record, and then its arrow runs from where that
-- record's paper lay before the move to where it lay after. An @unfold@
-- that turns back several folds leaves one record for each, all under its
-- own place in its step ('recordMoveIndex'), and each later record starts
-- from paper an earlier one of the same move has already turned, which no
-- figure shows: the figure is the state the step started from. An arrow for
-- each record would start its second arrow from that unseen place. So the
-- records of one move are read together, from the first one's paper before
-- to the last one's paper after, and the arrow is the one a reader comparing
-- the two figures would draw (the owner's choice of 2026-11-11).
--
-- That is why this asks 'motionsAcross' and not @motionsBetween@. Between
-- one record's two surfaces the two are the same function, since a turn
-- about a hinge never renumbers the paper. Between the first and the last
-- record of an unfold they are not: a later record that re-anchors numbers
-- its faces afresh, which @motionsBetween@ refuses and 'motionsAcross'
-- answers by where each point lay on the sheet.
--
-- == Where the ends are
--
-- Each surface is shown as its record says ('displayBefore',
-- 'displayAfter'), which is how the written states are shown
-- ('displayedFrame'), so an arrow's ends are in its figure's own
-- coordinates. For the first move of a step that is the figure's state. For
-- a later move of a step holding several, it is the paper as the earlier
-- moves left it, and the runner refuses such a move unless the paper it
-- turns still lies where the figure draws it (PRDs\/decisions.md, D22), so
-- the arrow's tail is on the figure's paper all the same.
--
-- A pre-crease's paper after the move is its paper before, and its arc's
-- head is at the surface its fold reached, its folded pose. That pose is
-- numbered as the paper before and is not yet shown as the figure shows it,
-- so it is shown under 'displayBefore', as the paper before is; a
-- pre-crease's two displays are equal, since laying paper flat again turns
-- the model no way, so 'displayAfter' would draw the same. Between the paper
-- before and the pose, 'motionsAcross' answers as @motionsBetween@ would,
-- since the two are numbered alike. No pre-crease a run can make yet moves
-- two pieces of paper: its moving paper is the one flap joined to its seed.
stepArrows :: [MoveRecord] -> Either SequenceError [(ArrowKind, V3, V3)]
stepArrows records = concat <$> traverse moveArrows moves
  where
    moves = mapMaybe NE.nonEmpty (groupBy (\a b -> recordMoveIndex a == recordMoveIndex b) records)

    moveArrows :: NonEmpty MoveRecord -> Either SequenceError [(ArrowKind, V3, V3)]
    moveArrows move@(start :| _) = case (turnKind start, reached) of
      (Just kind, Just after) -> do
        let before = displayedFrame (recordBefore start) (displayBefore start)
        motions <- first (ArrowRefused (recordStep start) (recordStepName start)) (motionsAcross before after)
        pure [(kind, motionFrom motion, motionTo motion) | motion <- motions]
      _ -> pure []
      where
        end = NE.last move
        -- Where the move took the paper, shown as the figure shows it.
        reached = case recordKind start of
          -- A pre-crease's paper after the move is its paper before, laid
          -- flat again, so its arc runs to the folded pose instead. That pose
          -- is unpresented and numbered as the paper before, so it is shown
          -- under the same display ('displayBefore'; the two displays of a
          -- pre-crease's record are equal). A pre-crease is one record, and
          -- every pre-crease's record has its pose; the 'Nothing' keeps this
          -- total rather than stands for a case that can happen.
          Precrease -> (\pose -> displayedFrame pose (displayBefore start)) <$> recordFoldedPose start
          _ -> Just (displayedFrame (recordAfter end) (displayAfter end))

-- | The fold-here lines of one step's records, in the order its moves were
-- written: for each fold and each pre-crease, a line along each edge of its
-- hinge, the line it turns paper about, where that edge lies on the figure
-- before the move, of the kind the move was written as (owner decision 74).
--
-- == Why the hinge, and not the creases a move adds
--
-- A book draws the fold-here line on the figure before a fold, and the
-- frames alone can find it only in the creases the next frame adds, which
-- is what @InferFoldLines@ draws on a file. A run's folds mostly lie along
-- creases its sheet already has, and the quarter fold, the blintz and the
-- helmet add none, so they would draw no line at all. Each record keeps its
-- hinge ('recordHinge') whether or not the move creased it, so every fold
-- shows where it goes.
--
-- An unfold draws no line, though its record carries the hinge it opens
-- along: a dash says "fold here", the opposite of what an unfold asks, and
-- the record's reading of decision 74, which names folds and pre-creases,
-- is the one the owner confirmed on 2026-11-12. So a line is drawn exactly
-- for a record written with a sense ('recordSense'), which only a fold and a
-- pre-crease have. A pre-crease's paper ends where it began, but where it
-- folds is known, and it draws its line beside its arc.
--
-- == One line for each edge, read off the paper before the move
--
-- Each edge of the hinge is looked up in the record's own paper before the
-- move, shown as the record shows it ('displayBefore'), which is how the
-- figure's state is shown, so the line's ends are in the figure's own
-- coordinates. Not in the figure's state itself: a move that creases fresh
-- paper creases before it turns, so its hinge names edges of that newly cut
-- paper, numbered afresh, which the state drawn on the figure does not have.
-- And not by carrying a stretch's two ends on the sheet over to the figure:
-- a stretch can be folded over itself, and the quarter fold's second hinge,
-- the sheet's line y = 1/2, lies doubled after its first fold, so both of
-- its ends land at (1, 1/2) and the line would be a point.
--
-- A hinge cut where other creases cross it is drawn as its pieces, one line
-- for each edge, so the dash starts again at each cut, as the owner chose on
-- 2026-11-12; the same is recorded for inferred lines (decisions C161).
--
-- == The same line drawn once
--
-- A fold through several layers has an edge on each layer, and they lie in
-- one place on the figure: the quarter fold's second hinge is two edges
-- along (1/2, 1/2)–(1, 1/2), one on each half. Two dashed lines drawn over
-- each other start their dashes at different points and fill each other's
-- gaps, so the line would read solid. Lines of one kind that lie on one line
-- and overlap by more than the model's hair ('modelHair') are drawn as one,
-- the span they cover, across every move of the step (the owner's choices of
-- 2026-11-12 and, after the code review of #695, 2026-11-13). That joins
-- the quarter's two edges in one place, and also a layer's whole edge with
-- the pieces another layer's creases cut the same line into. Lines that only
-- touch end to end stay apart, so a hinge every layer has cut is still drawn
-- in its pieces. Lines of different kinds in one place are both kept, so no
-- instruction is dropped, though their two dashes then blend. The hair is
-- the figure's, since two moves' edges are compared on its page.
stepFoldLines :: Frame -> [MoveRecord] -> [(ArrowKind, V3, V3)]
stepFoldLines figure records = foldl merge [] (concatMap recordLines records)
  where
    hair = modelHair (pointsOf figure)

    -- Each line in turn is joined with the first line already kept that it
    -- overlaps, and the span the two cover is merged in again, since it may
    -- now reach a line that neither reached alone; a line overlapping none
    -- is kept after the rest. So the lines keep the order they were written
    -- in, a joined line standing where the later of its parts would.
    merge kept line = case break (overlaps line) kept of
      (_, []) -> kept <> [line]
      (before, joined : after) -> merge (before <> after) (spanOf joined line)

    -- Of one kind, on one line, and sharing more than a hair of it: both of
    -- the second's ends lie within a hair of the first's line, and the two
    -- stretches of that line they cover overlap by more than a hair. A line
    -- of no length lies on no line, and overlaps nothing.
    overlaps (k, a, b) (l, c, d) =
      k == l
        && norm (b ^-^ a) > hair
        && offLine a b c <= hair
        && offLine a b d <= hair
        && min (along a b b) (max (along a b c) (along a b d)) - max 0 (min (along a b c) (along a b d)) > hair

    -- How far along the line from a through b a point lies, from a, and how
    -- far from that line it is, both in lengths of the model.
    along a b p = ((p ^-^ a) `dot` (b ^-^ a)) / norm (b ^-^ a)
    offLine a b p = norm ((p ^-^ a) ^-^ (along a b p / norm (b ^-^ a)) *^ (b ^-^ a))

    -- The stretch of the first line's line that two overlapping lines cover,
    -- from end to end, in the first one's direction.
    spanOf (k, a, b) (_, c, d) =
      let ts = [0, along a b b, along a b c, along a b d]
          u = (1 / norm (b ^-^ a)) *^ (b ^-^ a)
       in (k, a ^+^ minimum ts *^ u, a ^+^ maximum ts *^ u)

    recordLines record = case lineKind record of
      Nothing -> []
      Just kind ->
        let before = displayedFrame (recordBefore record) (displayBefore record)
            at = IM.fromList (zip [0 ..] (pointsOf before))
            ends = IM.fromList (zip [0 ..] (edgesVertices before))
         in [ (kind, a, b)
              | (_, edges) <- recordHinge record,
                EdgeId e <- edges,
                -- Every edge of a hinge is an edge of the record's paper
                -- before the move, in its numbering ("Senbazuru.Sequence.Record",
                -- One numbering), so both lookups find it; they keep this
                -- total rather than stand for a case that can happen.
                Just (VertexId u, VertexId v) <- [IM.lookup e ends],
                Just a <- [IM.lookup u at],
                Just b <- [IM.lookup v at]
            ]

-- | The kind of line a record's move draws: the sense it was written in, for
-- a fold or a pre-crease, and 'Nothing' for every other record, an unfold
-- among them.
lineKind :: MoveRecord -> Maybe ArrowKind
lineKind record = case recordSense record of
  Just ValleyFold -> Just ValleyArrow
  Just MountainFold -> Just MountainArrow
  Nothing -> Nothing

-- | A frame's vertices as points, with a missing z taken as 0.
pointsOf :: Frame -> [V3]
pointsOf frame = [V3 x y (case rest of z : _ -> z; [] -> 0) | x : y : rest <- verticesCoords frame]

-- | The kind of arrow a record's move draws, or 'Nothing' for a move that
-- draws none. Every kind of record is named, so a kind added later has to
-- be placed here by whoever adds it.
turnKind :: MoveRecord -> Maybe ArrowKind
turnKind record = case recordKind record of
  Turn -> case recordSense record of
    -- As written, from the reader's side: the page swaps the two when it
    -- shows the paper's other side ("Senbazuru.Render.Steps", @asSeen@).
    Just ValleyFold -> Just ValleyArrow
    Just MountainFold -> Just MountainArrow
    Nothing
      | recordUnfolds record -> Just UnfoldArrow
      -- A turn written with no sense that turns nothing back. No move makes
      -- one yet: a turn is a @fold@, which has a sense, or an @unfold@.
      -- A repeated or a macro's fold may, and whoever runs one says here
      -- what it draws.
      | otherwise -> Nothing
  -- Folded and laid flat again: one arc, there and back, with the fold's
  -- head at the far end and the unfold's at the near one, as books draw a
  -- fold and unfold (the owner's choice of 2026-11-13). A pre-crease is
  -- always written with a sense, so the 'Nothing' keeps this total.
  Precrease -> case recordSense record of
    Just ValleyFold -> Just ValleyAndUnfoldArrow
    Just MountainFold -> Just MountainAndUnfoldArrow
    Nothing -> Nothing
  -- No paper moves: the reader turns the model, holds other paper still, or
  -- a point is named. A turn's mark is not an arrow (#643's S35).
  Presentation _ -> Nothing
  Anchoring -> Nothing
  Marking _ _ -> Nothing
