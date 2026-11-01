-- |
-- Module      : Senbazuru.Render.Steps
-- Description : A whole folding sequence as one page of numbered figures.
--
-- Joins the three pieces a page of instructions needs: "Senbazuru.Origami.Step"
-- for what each fold does, "Senbazuru.Render.CreasePattern" for drawing the
-- paper, and "Senbazuru.Diagram.Layout" for putting the figures side by side.
--
-- It lives in the library rather than in the command line because it is a
-- decision, not plumbing — and because a copy of it in the test suite is how
-- the mixed-camera bug below survived a golden test that was meant to catch it.
--
-- == One camera for the whole page
--
-- Every figure is drawn through __one basis__, chosen from every frame's
-- vertices together rather than each frame's own.
--
-- Letting each figure choose is the mistake, and it is a quiet one. A sequence
-- that starts flat and ends with the paper out of the plane would draw its
-- early steps from above and its later ones isometrically, so the reader is
-- moved around the model between figures without being told. Worse, the shared
-- extent that keeps every figure at one scale would then be a union of boxes
-- measured in different projections, and an isometric box is wider than the
-- top-down box of the same sheet — so the folded model would come out /larger/
-- than the sheet it came from, which is the exact thing
-- "Senbazuru.Diagram.Layout" exists to prevent.
--
-- The /notation/ is still chosen per frame, and that is not the same question:
-- a crease pattern's creases are instructions and a folded form's are edges,
-- however you are looking at either.
--
-- Which side of the paper the page shows ('pageSide') is read off that same
-- camera, chosen in one place ('pageCamera'). Today no file can change the
-- answer: a view that names a camera gets that camera's side, and the two
-- cameras a page chooses for itself, from above and isometric, both look down
-- onto the reader's side. The one place still matters. 'pageSide' refuses
-- exactly the frames choosing the camera refuses, and a default that one day
-- looked from below or edge-on could not split the page from the side it
-- reports.
--
-- == One note for each figure
--
-- A book prints more beside a figure than the paper: the arrow for the next
-- fold, the step's instruction, a mark for turning the model over. Two frames
-- cannot say most of that, so it reaches the page as a /step note/, one for
-- each figure, from whoever knows it ('stepFigures'). A note says two things
-- so far: whether to infer arrows to the next figure, and what caption to
-- print under it.
--
-- 'stepFigures' draws each figure with its note and hands it back with its
-- caption, and lays out no page, because laying out a caption needs the
-- scale the page draws at, which is the page's to know
-- ("Senbazuru.Diagram.Page", @fitPage@) and which 'stepPage' does not take.
-- So the drawing, the costly part, is done in one place and once, and two
-- pages of the same figures differ only in how they are laid out: 'stepPage'
-- lays them out with 'gridOf', and a run's page ("Senbazuru.Render.Sequence")
-- fits them to a page with their captions under them.
--
-- 'stepPage' is 'stepFigures' with the same note on every figure, picked by
-- its 'Bool' ('noteFor'), rather than a second way of drawing the same
-- figures, which would be free to drift from the first as the test suite's
-- copy did. 'noteFor' gives no figure a caption, so 'stepPage' has none to
-- leave out.
--
-- Nothing here reads a frame's @frame_title@, so @render --steps@ never draws
-- one, because a file cannot say what its titles are.
-- @examples/quarter-fold-steps.fold@ titles its half-folded state \"Step 2:
-- folded in half\", naming the state, while a run of the same fold from its
-- source, @test/fixtures/quarter-fold.foldseq@, titles that state with the
-- next instruction, step @quarter@'s caption, \"Fold the top half down in
-- front, onto the bottom.\" Drawn under its figure, one of the two would be
-- wrong whichever this assumed.
-- Words under a figure have to arrive in its note, from a caller that knows
-- which kind its titles are, as a run does ("Senbazuru.Render.Sequence").
--
-- The note's constructor is not exported. Every note made outside this
-- module starts as 'inferNote' or 'silentNote' and changes the fields it
-- means to, so a field added later is filled, for every caller that does not
-- set it, by those two definitions. Every page @render --steps@ and the
-- studies draw comes through 'stepPage', whose notes 'noteFor' picks from the
-- same two, and a run's page starts each of its notes from 'silentNote', so a
-- default that changed those pages would have to be in one of the three.
module Senbazuru.Render.Steps
  ( -- * A page of steps
    stepPage,
    stepFigures,
    StepError (..),

    -- * What each figure carries
    StepNote,
    noteArrows,
    noteCaption,
    Arrows (..),
    inferNote,
    silentNote,
    noteFor,

    -- * Which side the page shows
    pageSide,
  )
where

import Data.Bifunctor (first)
import Data.Text (Text)
import Senbazuru.Diagram (Diagram)
import Senbazuru.Diagram.Layout (Grid, gridOf)
import Senbazuru.Diagram.Style (Theme)
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Query (FoldError, frameVertices)
import Senbazuru.Fold.Types (Frame (..))
import Senbazuru.Geometry.V3 (V3)
import Senbazuru.Origami.Stacking (Budget)
import Senbazuru.Origami.Step (motionsBetween)
import Senbazuru.Render.Camera (Basis, SeenFrom, View, seenFrom)
import Senbazuru.Render.CreasePattern
  ( basisFor,
    creasePatternFrom,
    defaultNotationFor,
    withArrows,
  )

-- | Something wrong with one frame of a sequence, and which frame it was.
--
-- The index matters. Told only that a file will not draw, someone holding a
-- twenty-step sequence has to bisect it by hand.
data StepError = StepError
  { stepFrame :: !Int,
    stepReason :: !FoldError
  }
  deriving stock (Eq, Show)

-- | The frame number, then the frame's own complaint.
--
-- The index leads, because it is the part the reader does not have: they are
-- holding a file, not a frame, and a message that opens with a face number
-- makes them count steps to find out whose face it is.
--
-- The CLI does not use this, and cannot: it says @cannot render frame 2 of
-- a.fold: …@, with the file name /between/ the index and the reason, which no
-- ordering of one method's output produces. So it takes the error apart and
-- writes those words itself, and this instance is what a caller holding a
-- 'StepError' and no file name gets. Two spellings of one message is a real
-- cost; the alternative was to change what @senbazuru render --steps@ prints,
-- which is not this change's to do.
instance Explain StepError where
  explain (StepError i err) = "frame " <> tshow i <> ": " <> explain err

-- | What a figure carries besides the paper. See the module header for why
-- its constructor is not exported.
data StepNote = StepNote
  { -- | Whether the figure carries the fold that takes it to the next one.
    noteArrows :: !Arrows,
    -- | The words printed under the figure, if any: the instruction of the
    -- step that starts from it.
    noteCaption :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

-- | Which arrows a figure carries.
data Arrows
  = -- | The ones 'motionsBetween' finds from this figure's frame to the next
    -- figure's, as @render --steps --arrows@ draws them.
    InferArrows
  | -- | None.
    NoArrows
  deriving stock (Eq, Show)

-- | Arrows inferred from the frames, and nothing else: no caption.
inferNote :: StepNote
inferNote = StepNote {noteArrows = InferArrows, noteCaption = Nothing}

-- | The paper and nothing else.
silentNote :: StepNote
silentNote = StepNote {noteArrows = NoArrows, noteCaption = Nothing}

-- | The note 'stepPage' gives every figure: 'inferNote' with arrows asked for,
-- 'silentNote' without.
noteFor :: Bool -> StepNote
noteFor True = inferNote
noteFor False = silentNote

-- | Every frame of a file drawn as a figure, with its note, in order, each
-- with the caption its note gives it: the figures of a page of steps, before
-- they are laid out.
--
-- Empty when the file has no frame with any geometry in it — which is not the
-- same as having no frames. FOLD keeps its file metadata in the same object
-- as the first frame, so a file that puts every step in @file_frames@ has a key
-- frame holding a title and nothing else. That is not a step, and skipping it
-- is why this takes frames rather than a count. Its note is skipped with it,
-- so every other note stays with its own frame, and a frame that will not draw
-- is still named by its place in the list.
stepFigures ::
  Theme ->
  -- | How hard to look for a layer order, for the frames that need one.
  Budget ->
  -- | Where to look from and which way up, with the camera chosen from the
  -- whole sequence when the view does not name one.
  View ->
  [(Frame, StepNote)] ->
  Either StepError [(Diagram, Maybe Text)]
stepFigures theme budget view notes = do
  (resolved, basis) <- pageCamera view notes
  -- Numbered by their place in the sequence too, so "the next step" skips
  -- over a metadata-only key frame rather than tripping on it.
  let order = [fr | (_, fr, _, _) <- resolved]
  traverse (figure basis order) (zip [0 ..] resolved)
  where
    figure basis order (position, (i, fr, note, verts)) = do
      d <-
        first
          (StepError i)
          (creasePatternFrom theme budget (defaultNotationFor (frameClasses fr) verts) basis fr)
      drawn <- case (noteArrows note, drop (position + 1) order) of
        -- The last figure of a sequence is the finished model, and a book draws
        -- no arrow on it, whatever its note asks for.
        (InferArrows, next : _) -> do
          motions <- first (StepError i) (motionsBetween fr next)
          pure (withArrows theme basis motions d)
        _ -> pure d
      pure (drawn, noteCaption note)

-- | Every frame of a file as one page of numbered figures: 'stepFigures' with
-- 'noteFor' on every figure, laid out by 'gridOf'.
--
-- With @arrows@ set, each figure but the last also carries the fold that takes
-- it to the next one, as a book draws it.
--
-- 'Nothing' when the file has no frame with any geometry in it, as
-- 'stepFigures' says.
stepPage ::
  Theme ->
  Budget ->
  Grid ->
  View ->
  Bool ->
  [Frame] ->
  Either StepError (Maybe Diagram)
stepPage theme budget grid view arrows frames =
  gridOf grid . map fst <$> stepFigures theme budget view [(fr, noteFor arrows) | fr <- frames]

-- | Which side of the paper a page of these frames shows: the side its one
-- camera sees, so under @--view bottom@ a page is seen from the opposite side
-- however its frames lie.
--
-- A frame whose vertices cannot be read is refused, naming the frame
-- 'stepFigures' would name, because the camera is chosen from every frame's
-- vertices. The side itself does not need them, as the module header says. A
-- frame 'stepFigures' cannot draw for another reason still has a side. A list
-- with no geometry in it has no page, and is given the side of the view's own
-- camera, or of 'topDown' when the view names none.
pageSide :: View -> [Frame] -> Either StepError SeenFrom
pageSide view frames = seenFrom . snd <$> pageCamera view [(fr, ()) | fr <- frames]

-- | The frames a page draws, each with whatever rides with it, and the one
-- camera it draws them through.
--
-- Each frame that holds geometry comes with its place in the list, so an error
-- can name the frame someone would have to go and look at, and with its
-- vertices. A frame with none is dropped together with what rides with it. The
-- camera is chosen from every frame's vertices together, and from nothing that
-- rides with them, which the type says: this works for a @note@ of any type,
-- so it cannot look inside one.
pageCamera :: View -> [(Frame, note)] -> Either StepError ([(Int, Frame, note, [V3])], Basis)
pageCamera view frames = do
  resolved <- traverse withVertices [(i, fr, note) | (i, (fr, note)) <- zip [0 ..] frames, hasGeometry fr]
  pure (resolved, basisFor view (concatMap (\(_, _, _, verts) -> verts) resolved))
  where
    hasGeometry fr = not (null (verticesCoords fr))

    withVertices (i, fr, note) = do
      verts <- first (StepError i) (frameVertices fr)
      pure (i, fr, note, verts)
