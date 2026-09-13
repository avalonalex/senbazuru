-- | Fold all four corners of the existing blintz fixture to the centre, then
-- reopen the first. A blintz base is that smaller square with four triangular
-- flaps; see docs/glossary.md for crease angles and material coordinates.
-- This is a recipe for examples/blintz-base.fold, not an instruction language.
-- Its edge ids refer to that fixture after cutting and tracing. The central
-- diamond is put first ONCE, before any motion: Folding anchors its first
-- face, and anchoring a corner would turn the whole model when that corner
-- becomes the moving flap. This recipe's face ids use the reordered pattern.
--
-- Every move inherits the accepted endpoint's angles AND face orders on the
-- original material pattern. Feeding its folded coordinates back as the
-- material pattern would fold the already folded sheet a second time.
-- Here the central diamond is stationary throughout. Check the join anyway,
-- so a changed fixture cannot
-- silently insert a rigid jump between individually checked turns.
module BlintzSequence (BlintzMove (..), buildBlintzSequence, blintzStates, blintzFile) where

import Control.Monad (unless)
import Data.Bifunctor (first)
import Data.Text (Text)
import Senbazuru.Explain (explain, tshow)
import Senbazuru.Fold.Query (frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.V3 (modelSpan)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Flap
import Senbazuru.Origami.Folding
import Senbazuru.Origami.HingeSweep (defaultSweepSettings)
import Senbazuru.Origami.Surface

data BlintzMove = BlintzMove
  { blintzTitle :: !Text,
    blintzStart :: !Folded,
    blintzMotion :: !CheckedFlap,
    blintzEnd :: !(Surface V2)
  }
  deriving stock (Show)

buildBlintzSequence :: Frame -> Either Text [BlintzMove]
buildBlintzSequence source = do
  traced <- first explain (foldFrameWith source {edgesFoldAngle = replicate (length (edgesVertices source)) 0, faceOrders = [], frameExtras = mempty})
  let material = foldedPattern traced
  rings <- case facesVertices material of
    [a, b, c, d, centre] | map length [a, b, c, d, centre] == [3, 3, 3, 3, 4] -> Right [centre, a, b, c, d]
    _ -> Left "expected the five faces of examples/blintz-base.fold"
  start <- first explain (foldFrameWith material {facesVertices = rings})
  go start recipe
  where
    recipe =
      [ ("Fold the first corner to the centre", EdgeId 8, FaceId 2, -180),
        ("Fold the second corner to the centre", EdgeId 9, FaceId 3, -180),
        ("Fold the third corner to the centre", EdgeId 10, FaceId 4, -180),
        ("Fold the last corner: blintz base", EdgeId 11, FaceId 1, -180),
        ("Reopen the first corner", EdgeId 8, FaceId 2, 180)
      ]
    go _ [] = Right []
    go start ((title, crease, side, travel) : rest) = do
      (move, next) <- first (\message -> title <> ": " <> message) $ do
        motion <- first explain (prepareFlap crease side travel start >>= checkFlap defaultSweepSettings)
        end <- first explain (flapAt motion 1)
        let accepted = surfaceFrame end
            nextPattern = (foldedPattern start) {edgesFoldAngle = edgesFoldAngle accepted, faceOrders = faceOrders accepted, frameExtras = mempty}
        next <- first explain (foldFrameWith nextPattern)
        expected <- first explain (frameVertices accepted)
        actual <- first explain (frameVertices (foldedFrame next))
        material <- first explain (frameVertices nextPattern)
        let scale = modelSpan material
        unless (length expected == length actual && and (zipWith (\a b -> norm (a ^-^ b) < 1e-12 * scale) expected actual)) $
          Left "refolding the accepted endpoint changed its position"
        pure (BlintzMove title start motion end, next)
      remaining <- go next rest
      pure (move : remaining)

-- | Eleven poses: the initial square, then 90 degrees and the endpoint of
-- each move. The common endpoints occur only once on the instruction page.
-- The interval check covers the turns between these illustrations too.
blintzStates :: [BlintzMove] -> Either Text [(Text, Surface V2)]
blintzStates [] = Left "blintz sequence has no moves"
blintzStates moves@(opening : _) = do
  start <- first explain (flapAt (blintzMotion opening) 0)
  states <- traverse statesFor (zip [1 :: Int ..] moves)
  pure (("Start with the open square", start) : concat states)
  where
    statesFor (i, move) = do
      midway <- first explain (flapAt (blintzMotion move) 0.5)
      pure [("Move " <> tshow i <> " · halfway", midway), (blintzTitle move, blintzEnd move)]

blintzFile :: [(Text, Surface V2)] -> FoldFile
blintzFile states =
  FoldFile
    (Just 1.2)
    (Just "senbazuru checked blintz sequence")
    Nothing
    (Just "Blintz base, then reopen one corner")
    Nothing
    ["diagrams"]
    emptyFrame
    [(materialFrame surface) {frameTitle = Just title} | (title, surface) <- states]
