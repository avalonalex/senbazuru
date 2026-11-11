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
-- run knows and its file does not (the arrows of each move, of the kind it
-- was written as, so far; lines and marks to come), so it is a function of
-- its own that a test can hold to the file a run writes; the second is the one
-- composition that @run -o x.svg@ calls and a golden test is to call (#643's
-- S37), so the two cannot draw the page two ways.
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
-- written file. Each row is followed by a band for its captions, so the rows
-- stand further apart than @render --steps@' rows, the page is as tall as
-- they need, and with a height given the figures are drawn smaller
-- ("Senbazuru.Diagram.Page").
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
-- A step that turns no paper leaves its figure 'NoArrows': @anchor P@, a
-- @mark@, a turn-over or a rotate, whose mark on the page is not an arrow,
-- and a pre-crease, whose paper ends where it began, so that comparing its
-- two surfaces finds nothing; its arrows out and back are read another way
-- (#643's S34). So has the last figure, which no step starts from.
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
import Data.List (groupBy)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NE
import Data.Maybe (mapMaybe)
import Senbazuru.Diagram.Layout (Grid)
import Senbazuru.Diagram.Page (FittedPage, Height, Page, PageFitError, fitPage)
import Senbazuru.Diagram.Style (ArrowKind (..), Theme)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types (Frame (..))
import Senbazuru.Geometry.V3 (V3)
import Senbazuru.Origami.Stacking (Budget)
import Senbazuru.Origami.Step (Motion (..), motionsAcross)
import Senbazuru.Render.Camera (View)
import Senbazuru.Render.Steps (Arrows (..), StepError (..), StepNote, noteArrows, noteCaption, silentNote, stepFigures)
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
  = -- | The run's own refusal: a state that cannot be written, or a figure
    -- the page cannot draw, named by the step that ended at its state.
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
-- their captions ('fitPage'), and a figure the page cannot draw refused as the
-- step that ended at its state. 'Nothing' only for a run whose states hold no
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
-- the arrows of the step that starts from it.
--
-- That step is the one that ended at the next state, so the states are
-- paired with their successors and the last state has no such step. The
-- pairing is by the states written and not by step numbers or captions,
-- because those disagree with it in two places. A step of only
-- @expect refused@ writes no state, so the step after it starts from the
-- state before it. And a run stopped at @not modelled@ keeps the records of
-- the moves its last step made before the stop, though that step wrote no
-- state: the last figure carries that step's caption and must not carry its
-- arrows, which would show a fold whose result the page never draws
-- (PRDs\/decisions.md, D21). No state names the stopped step as the one that
-- ended at it, so its records are found by no figure.
notesFor :: Run -> [WrittenState] -> Either SequenceError [(Frame, StepNote)]
notesFor run states = traverse noted (zip states (map stateStep (drop 1 states) <> [Nothing]))
  where
    noted (st, leaving) = do
      arrows <- maybe (pure []) (stepArrows . recordsOf) leaving
      pure
        ( stateFrame st,
          silentNote
            { noteCaption = frameTitle (stateFrame st),
              -- No arrows is 'NoArrows', never an empty list of given ones,
              -- so a figure with nothing to say is the one @render --steps@
              -- draws of its state.
              noteArrows = if null arrows then NoArrows else GivenArrows arrows
            }
        )
    recordsOf n = [record | record <- runRecords run, recordStep record == n]

-- | The arrows of one step's records, in the order its moves were written:
-- for each move that turned paper, an arrow for each piece of paper that
-- moved as one, of the kind the move was written as.
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
stepArrows :: [MoveRecord] -> Either SequenceError [(ArrowKind, V3, V3)]
stepArrows records = concat <$> traverse moveArrows moves
  where
    moves = mapMaybe NE.nonEmpty (groupBy (\a b -> recordMoveIndex a == recordMoveIndex b) records)

    moveArrows :: NonEmpty MoveRecord -> Either SequenceError [(ArrowKind, V3, V3)]
    moveArrows move@(start :| _) = case turnKind start of
      Nothing -> pure []
      Just kind -> do
        let end = NE.last move
            before = displayedFrame (recordBefore start) (displayBefore start)
            after = displayedFrame (recordAfter end) (displayAfter end)
        motions <- first (ArrowRefused (recordStep start) (recordStepName start)) (motionsAcross before after)
        pure [(kind, motionFrom motion, motionTo motion) | motion <- motions]

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
  -- Folded and laid flat again, so its two surfaces are one and comparing
  -- them finds no motion: its arrows, out and back, are read from its folded
  -- pose (#643's S34).
  Precrease -> Nothing
  -- No paper moves: the reader turns the model, holds other paper still, or
  -- a point is named. A turn's mark is not an arrow (#643's S35).
  Presentation _ -> Nothing
  Anchoring -> Nothing
  Marking _ _ -> Nothing
