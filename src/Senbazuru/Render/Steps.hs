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
module Senbazuru.Render.Steps
  ( stepPage,
    StepError (..),
  )
where

import Data.Bifunctor (first)
import Senbazuru.Diagram (Diagram)
import Senbazuru.Diagram.Layout (Grid, gridOf)
import Senbazuru.Diagram.Style (Theme)
import Senbazuru.Fold.Query (FoldError, frameVertices)
import Senbazuru.Fold.Types (Frame (..))
import Senbazuru.Origami.Step (motionsBetween)
import Senbazuru.Render.Camera (Basis)
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

-- | Every frame of a file as one page of numbered figures.
--
-- With @arrows@ set, each figure but the last also carries the fold that takes
-- it to the next one, as a book draws it.
--
-- 'Nothing' when the file has no frame with any geometry in it — which is not
-- the same as having no frames. FOLD keeps its file metadata in the same object
-- as the first frame, so a file that puts every step in @file_frames@ has a key
-- frame holding a title and nothing else. That is not a step, and skipping it
-- is why this takes frames rather than a count.
stepPage ::
  Theme ->
  Grid ->
  -- | The camera, or 'Nothing' to choose one from the whole sequence.
  Maybe Basis ->
  Bool ->
  [Frame] ->
  Either StepError (Maybe Diagram)
stepPage theme grid chosen arrows frames = do
  -- Numbered by their place in the file, so an error can name the frame someone
  -- would have to go and look at, and then by their place in the sequence, so
  -- "the next step" skips over a metadata-only key frame rather than tripping
  -- on it.
  resolved <- traverse withVertices [(i, fr) | (i, fr) <- zip [0 ..] frames, hasGeometry fr]
  let basis = basisFor chosen (concatMap (\(_, _, verts) -> verts) resolved)
      order = [fr | (_, fr, _) <- resolved]
  figures <- traverse (figure basis order) (zip [0 ..] resolved)
  pure (gridOf grid figures)
  where
    hasGeometry fr = not (null (verticesCoords fr))

    withVertices (i, fr) = do
      verts <- first (StepError i) (frameVertices fr)
      pure (i, fr, verts)

    figure basis order (position, (i, fr, verts)) = do
      d <-
        first
          (StepError i)
          (creasePatternFrom theme (defaultNotationFor (frameClasses fr) verts) basis fr)
      case drop (position + 1) order of
        -- The last figure of a sequence is the finished model, and a book draws
        -- no arrow on it.
        (next : _) | arrows -> do
          motions <- first (StepError i) (motionsBetween fr next)
          pure (withArrows theme basis motions d)
        _ -> pure d
