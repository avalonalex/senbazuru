-- | Three checked turns make the traditional helmet base: halve a square
-- diagonally, then fold both corners of the doubled triangle to its tip.
-- See docs/glossary.md for faces, crease angles and material coordinates.
-- This fixture-specific recipe exercises one hinge made of several edges.
-- After the diagonal fold, distinct material creases coincide in space; their
-- stationary panels face opposite ways, so one turn needs opposite FOLD signs.
--
-- Put the central southeast face first once, before folding, so Folding keeps
-- that face stationary through all three moves. Carry accepted angles and
-- layer orders onto the original material pattern and verify each join. The
-- production Flap operation owns selection, angle propagation and contact;
-- this module supplies only the recipe, not a second motion checker.
module HelmetSequence (HelmetMove (..), buildHelmetSequence, helmetStates, helmetFile) where

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

data HelmetMove = HelmetMove
  { helmetTitle :: !Text,
    helmetStart :: !Folded,
    helmetMotion :: !CheckedFlap,
    helmetEnd :: !(Surface V2)
  }
  deriving stock (Show)

buildHelmetSequence :: Frame -> Either Text [HelmetMove]
buildHelmetSequence source = do
  traced <- first explain (foldFrameWith source {edgesFoldAngle = replicate (length (edgesVertices source)) 0, faceOrders = [], frameExtras = mempty})
  let material = foldedPattern traced
  rings <- case facesVertices material of
    [a, centre, b, c, d, e] | map length [a, centre, b, c, d, e] == [3, 4, 3, 3, 4, 3] -> Right [centre, a, b, c, d, e]
    _ -> Left "expected the six faces of examples/helmet-base.fold"
  start <- first explain (foldFrameWith material {facesVertices = rings})
  go start recipe
  where
    recipe =
      [ ("Fold the square diagonally in half", [EdgeId 8, EdgeId 9], FaceId 5, 180),
        ("Bring the first doubled corner to the tip", [EdgeId 10, EdgeId 12], FaceId 1, 180),
        ("Bring the other doubled corner to the tip: helmet base", [EdgeId 13, EdgeId 11], FaceId 2, 180)
      ]
    go _ [] = Right []
    go start ((title, crease, side, travel) : rest) = do
      (move, next) <- first (\message -> title <> ": " <> message) $ do
        motion <- first explain (prepareFlapAlong crease side travel start >>= checkFlap defaultSweepSettings)
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
        pure (HelmetMove title start motion end, next)
      remaining <- go next rest
      pure (move : remaining)

-- | Seven illustrations: the open square, then an intermediate and flat pose
-- of each turn. At this camera's 45-degree elevation the first 90-degree pose
-- has the open sheet's silhouette, so show 120 degrees instead. The corner
-- turns use 90 degrees. The interval check covers all the motion between them.
helmetStates :: [HelmetMove] -> Either Text [(Text, Surface V2)]
helmetStates [] = Left "helmet sequence has no moves"
helmetStates moves@(opening : _) = do
  start <- first explain (flapAt (helmetMotion opening) 0)
  states <- traverse statesFor (zip [1 :: Int ..] moves)
  pure (("Start with the open square", start) : concat states)
  where
    statesFor (i, move) = do
      let degrees = if i == 1 then 120 else 90 :: Double
      midway <- first explain (flapAt (helmetMotion move) (degrees / 180))
      pure [("Move " <> tshow i <> " · " <> tshow (round degrees :: Int) <> "°", midway), (helmetTitle move, helmetEnd move)]

helmetFile :: [(Text, Surface V2)] -> FoldFile
helmetFile states =
  FoldFile
    (Just 1.2)
    (Just "senbazuru checked helmet sequence")
    Nothing
    (Just "Three turns to the helmet base")
    Nothing
    ["diagrams"]
    emptyFrame
    [(materialFrame surface) {frameTitle = Just title} | (title, surface) <- states]
