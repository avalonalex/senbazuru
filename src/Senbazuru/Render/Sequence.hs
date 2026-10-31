-- |
-- Module      : Senbazuru.Render.Sequence
-- Description : A run of a fold sequence as one page of steps, a figure for each state it wrote.
--
-- A run hands back every state the paper reached ("Senbazuru.Sequence.Record"),
-- and "Senbazuru.Render.Steps" draws a list of frames, each with a /step
-- note/ saying what its figure carries besides the paper. This module joins
-- the two: 'stepNotes' gives each state the run writes a note, and 'runPage'
-- draws them. The first is the channel later work fills (a caption, arrows
-- read from a move's record), so it is a function of its own that a test can
-- hold to the file a run writes; the second is the one composition that
-- @run -o x.svg@ calls and a golden test is to call (#643's S37), so the two
-- cannot draw the page two ways.
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
-- it starts from. Today every note is 'silentNote', the paper and nothing
-- else, so the page is what @render --steps@ draws of the written file. The
-- arrows of an @anchor P@ step's figure stay 'NoArrows' when notes are filled
-- from records, since that move turns no paper.
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
  )
where

import Data.Bifunctor (first)
import Senbazuru.Diagram (Diagram)
import Senbazuru.Diagram.Layout (Grid)
import Senbazuru.Diagram.Style (Theme)
import Senbazuru.Fold.Types (Frame)
import Senbazuru.Origami.Stacking (Budget)
import Senbazuru.Render.Camera (View)
import Senbazuru.Render.Steps (StepError (..), StepNote, silentNote, stepPageWith)
import Senbazuru.Sequence.Error (SequenceError (..))
import Senbazuru.Sequence.Record (Run (..), StepOutcome (..), WrittenState (..), writtenStates)

-- | Each state the run writes, as its file writes it, with the note its
-- figure is drawn with: 'silentNote', for now, on every one.
--
-- Not total, because writing the states is not: it shares
-- 'writtenStates'' refusals, each a 'WriteRefused' naming the state.
stepNotes :: Run -> Either SequenceError [(Frame, StepNote)]
stepNotes run = notesFor <$> writtenStates run

-- | The run's page: 'stepPageWith' over 'stepNotes', with a figure the page
-- cannot draw refused as the step that ended at its state. 'Nothing' only for
-- a run whose states hold no geometry, which a run never writes.
runPage ::
  Theme ->
  -- | How hard to look for a layer order, for the states that need one.
  Budget ->
  Grid ->
  -- | Where to look from and which way up, as for 'stepPageWith'.
  View ->
  Run ->
  Either SequenceError (Maybe Diagram)
runPage theme budget grid view run = do
  states <- writtenStates run
  first (refused states) (stepPageWith theme budget grid view (notesFor states))
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

-- | Every state, in order, with a silent note.
notesFor :: [WrittenState] -> [(Frame, StepNote)]
notesFor states = [(stateFrame st, silentNote) | st <- states]
