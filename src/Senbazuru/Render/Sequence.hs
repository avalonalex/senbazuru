-- |
-- Module      : Senbazuru.Render.Sequence
-- Description : A run of a fold sequence as one page of steps, a figure for each state it wrote.
--
-- A run hands back every state the paper reached ("Senbazuru.Sequence.Record"),
-- and "Senbazuru.Render.Steps" draws a list of frames, each with a /step
-- note/ saying what its figure carries besides the paper. This module joins
-- the two: 'stepNotes' gives each state the run writes a note, and 'runPage'
-- draws them and fits them to a page with their captions
-- ("Senbazuru.Diagram.Page"). The first is the channel later work fills
-- (arrows read from a move's record, marks), so it is a function of its own
-- that a test can hold to the file a run writes; the second is the one
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
-- it starts from. Every note is 'silentNote' with a caption, so the page is
-- what @render --steps@ draws of the written file with words under its
-- figures. The arrows of an @anchor P@ step's figure stay 'NoArrows' when
-- notes are filled from records, since that move turns no paper.
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
-- While every note is silent, a figure can be refused only for its paper, so
-- the step that ended at its state is the one to name. A refusal of a note's
-- arrows, once notes carry them, is about the step that starts from the
-- state instead, and the change that fills them says how it is named.
module Senbazuru.Render.Sequence
  ( stepNotes,
    runPage,
    RunPageError (..),
  )
where

import Data.Bifunctor (first)
import Senbazuru.Diagram.Layout (Grid)
import Senbazuru.Diagram.Page (FittedPage, Height, Page, PageFitError, fitPage)
import Senbazuru.Diagram.Style (Theme)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types (Frame (..))
import Senbazuru.Origami.Stacking (Budget)
import Senbazuru.Render.Camera (View)
import Senbazuru.Render.Steps (StepError (..), StepNote, noteCaption, silentNote, stepFigures)
import Senbazuru.Sequence.Error (SequenceError (..))
import Senbazuru.Sequence.Record (Run (..), StepOutcome (..), WrittenState (..), writtenStates)

-- | Each state the run writes, as its file writes it, with the note its
-- figure is drawn with: 'silentNote', for now, with the state's title as its
-- caption.
--
-- Not total, because writing the states is not: it shares
-- 'writtenStates'' refusals, each a 'WriteRefused' naming the state.
stepNotes :: Run -> Either SequenceError [(Frame, StepNote)]
stepNotes run = notesFor <$> writtenStates run

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
  figures <- first (RunRefused . refused states) (stepFigures theme budget view (notesFor states))
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

-- | Every state, in order, with a silent note captioned with its title.
notesFor :: [WrittenState] -> [(Frame, StepNote)]
notesFor states = [(stateFrame st, silentNote {noteCaption = frameTitle (stateFrame st)}) | st <- states]
