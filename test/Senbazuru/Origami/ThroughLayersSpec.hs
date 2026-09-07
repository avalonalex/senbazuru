-- |
-- Tests for creasing a folded model through its layers.
--
-- Two worked examples carry almost all of it, and both were chosen because the
-- answer can be worked out on paper before the code is run.
--
-- __The diagonal fold__ is a square folded in half, so a line across it is two
-- creases. They must be mirror images about the existing fold and they must be
-- __of opposite kinds__, and it is the second half that matters: getting the
-- positions right and the assignments wrong leaves a file that folds into a
-- different model with nothing to show for it. So every assertion here names
-- the assignment.
--
-- __The quarter fold__ is the same question at four layers, where the pattern
-- the kinds make — valley, mountain, valley, mountain outwards from the middle
-- — is visible rather than a coin toss that happened to land right.
module Senbazuru.Origami.ThroughLayersSpec (spec) where

import Data.ByteString qualified as BS
import Data.List (sort)
import Senbazuru.Fold.Load (decodeFile, renderLoadError)
import Senbazuru.Fold.Types
  ( Assignment (..),
    Frame (..),
    VertexId (..),
    keyFrame,
  )
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Origami.Folding (foldFrame)
import Senbazuru.Origami.Stacking (defaultBudget, layerOrderFor)
import Senbazuru.Origami.ThroughLayers
import Test.Hspec

-- | Load a fixture's key frame, in whatever format it is in.
fixture :: FilePath -> IO Frame
fixture name = do
  let path = "test/fixtures/" <> name
  bytes <- BS.readFile path
  case decodeFile path bytes of
    Left err -> fail (show (renderLoadError err))
    Right f -> pure (keyFrame f)

creased :: Frame -> (Double, Double) -> (Double, Double) -> Assignment -> IO Frame
creased fr (x0, y0) (x1, y1) a =
  case creaseThroughLayers (V2 x0 y0) (V2 x1 y1) a fr of
    Left err -> fail (show (renderThroughError err))
    Right out -> pure out

-- | Every crease the paper actually folds along, as endpoints and kind.
--
-- Sorted, and each segment written with its lower end first, so that a test
-- says which creases came out without also pinning the order they happen to be
-- listed in — which is a fact about how cutting appends, not about the move.
folds :: Frame -> [((Double, Double), (Double, Double), Assignment)]
folds fr =
  sort
    [ (min p q, max p q, a)
      | ((u, v), a) <- zip (edgesVertices fr) (edgesAssignment fr <> repeat Unassigned),
        a `elem` [Mountain, Valley],
        let p = at u,
        let q = at v
    ]
  where
    at (VertexId i) = case drop i (verticesCoords fr) of
      ((x : y : _) : _) -> (rounded x, rounded y)
      _ -> (0, 0)

-- | Rounded, so a coordinate landing on 2e-16 compares as the zero it is.
rounded :: Double -> Double
rounded x = fromIntegral (round (x * 1e9) :: Integer) / 1e9

spec :: Spec
spec = do
  describe "a square folded in half" $ do
    it "turns one line across the model into two creases on the sheet" $ do
      -- diagonal-cp.fold is the unit square with a valley along the diagonal
      -- from (0,1) to (1,0), and it folds exactly in half onto the triangle
      -- (0,0), (1,0), (0,1). Drawing that triangle's midline touches both
      -- layers, and the two creases it leaves are the reflections of it in the
      -- existing fold: x + y = 0.5 and x + y = 1.5.
      --
      -- The kinds are the point. The layer that did not move takes the valley
      -- that was asked for; the one that folded over is upside down, so the
      -- same physical fold is a mountain where it lies on the sheet.
      flat <- fixture "diagonal-cp.fold"
      out <- creased flat (0, 0.5) (0.5, 0) Valley
      folds out
        `shouldBe` [ ((0, 0.5), (0.5, 0), Valley),
                     ((0, 1), (1, 0), Valley),
                     ((0.5, 1), (1, 0.5), Mountain)
                   ]

    it "asks for a mountain and gets the other pair the same way round" $ do
      -- Guards the test above. If the assignment were ignored rather than
      -- turned over, both would read Valley here and the first test would still
      -- pass.
      flat <- fixture "diagonal-cp.fold"
      out <- creased flat (0, 0.5) (0.5, 0) Mountain
      folds out
        `shouldBe` [ ((0, 0.5), (0.5, 0), Mountain),
                     ((0, 1), (1, 0), Valley),
                     ((0.5, 1), (1, 0.5), Valley)
                   ]

    it "leaves a pattern that folds and stacks" $ do
      -- The creases are written at plus or minus 180, so the result is the next
      -- state of the model and not a drawing of one. Three parallel creases
      -- with no interior vertex between them, which pleats.
      flat <- fixture "diagonal-cp.fold"
      out <- creased flat (0, 0.5) (0.5, 0) Valley
      case foldFrame out of
        Left err -> expectationFailure ("expected a fold, got " <> show err)
        Right f -> case layerOrderFor defaultBudget f of
          Left err -> expectationFailure ("expected a stacking, got " <> show err)
          Right Nothing -> expectationFailure "expected a layer order"
          Right (Just _) -> length (facesVertices f) `shouldBe` 4

  describe "a square folded into quarters" $ do
    it "alternates the kind outwards through four layers" $ do
      -- The same question with more layers, where the alternation is a pattern
      -- rather than a coin toss that landed right. A vertical line at x = 0.6
      -- on the folded quarter reaches all four, and they are the four quarters
      -- of the sheet reflected about x = 0.5 and y = 0.5 in turn: two land at
      -- x = 0.6 and two at x = 0.4, and the kind flips with each turning over.
      flat <- fixture "quarter-fold.fold"
      out <- creased flat (0.6, 0) (0.6, 0.5) Valley
      -- The drawn line was vertical and every fold it was reflected in is
      -- vertical or horizontal, so every crease it made is upright too. The
      -- file's own upright pair, down the middle at x = 0.5, is listed here as
      -- well rather than filtered away: it is two creases in the file already,
      -- meeting at the centre, and this move leaves both exactly as they were.
      let upright = [c | c@((x0, _), (x1, _), _) <- folds out, x0 == x1]
      upright
        `shouldBe` [ ((0.4, 0), (0.4, 0.5), Mountain),
                     ((0.4, 0.5), (0.4, 1), Valley),
                     ((0.5, 0), (0.5, 0.5), Mountain),
                     ((0.5, 0.5), (0.5, 1), Mountain),
                     ((0.6, 0), (0.6, 0.5), Valley),
                     ((0.6, 0.5), (0.6, 1), Mountain)
                   ]

    it "cuts the creases already there where the new ones meet them" $ do
      -- The four creases the file had run from the middle to the four edge
      -- midpoints. Two of them are crossed, so they arrive as two pieces each,
      -- which is six -- plus the four above. Anything that added creases
      -- without cutting what they crossed would leave eight.
      flat <- fixture "quarter-fold.fold"
      out <- creased flat (0.6, 0) (0.6, 0.5) Valley
      length (folds out) `shouldBe` 10

  describe "a whole model" $
    it "creases the crane through every layer it reaches" $ do
      -- At the scale the module header quotes. What is worth pinning is not the
      -- count -- that is a fact about where the line was drawn -- but that a
      -- single request for a valley comes back as both kinds, and that a
      -- pattern with that many new creases in it still folds and stacks.
      flat <- fixture "crane.fold"
      out <- creased flat (0.66, 0.25) (1.34, 0.25) Valley
      let added = length (folds out) - length (folds flat)
      added `shouldSatisfy` (> 0)
      map (\(_, _, a) -> a) (folds out) `shouldSatisfy` elem Mountain
      map (\(_, _, a) -> a) (folds out) `shouldSatisfy` elem Valley
      case foldFrame out of
        Left err -> expectationFailure ("expected a fold, got " <> show err)
        Right f -> case layerOrderFor defaultBudget f of
          Left err -> expectationFailure ("expected a stacking, got " <> show err)
          Right Nothing -> expectationFailure "expected a layer order"
          Right (Just _) -> pure ()

  describe "lines it will not crease along" $ do
    it "refuses a model with paper still in the air" $ do
      -- A line drawn on the page of such a model is a ray and not a point:
      -- there is no one place on the paper it came from. simple.fold is
      -- already a folded form, so it is refused a step earlier still -- there
      -- is no pattern under it to write anything onto.
      folded <- fixture "simple.fold"
      case creaseThroughLayers (V2 0 0) (V2 1 1) Valley folded of
        Left (CannotFold _) -> pure ()
        other -> expectationFailure ("expected a refusal, got " <> show (fmap frameClasses other))

    it "refuses a line that misses the model" $ do
      flat <- fixture "diagonal-cp.fold"
      creaseThroughLayers (V2 5 5) (V2 6 6) Valley flat
        `shouldBe` Left NoPaperUnderTheLine

    it "refuses a line drawn down a fold rather than across the paper" $ do
      -- The folded triangle's hypotenuse is the existing crease, so this line
      -- lies along the edge of both faces and properly inside neither. Refused
      -- here rather than reaching the sheet, where it would be two creases lying
      -- on top of one that is already there.
      flat <- fixture "diagonal-cp.fold"
      creaseThroughLayers (V2 0 1) (V2 1 0) Valley flat
        `shouldBe` Left NoPaperUnderTheLine

    it "refuses two ends that are the same point" $ do
      flat <- fixture "diagonal-cp.fold"
      creaseThroughLayers (V2 0.2 0.2) (V2 0.2 0.2) Valley flat
        `shouldBe` Left LineWithoutLength

    it "refuses a sheet whose faces cannot be worked out" $ do
      -- three-crease.fold has three creases meeting at a point and no faces to
      -- trace around them, so there is nothing to fold and nothing to draw on.
      flat <- fixture "three-crease.fold"
      case creaseThroughLayers (V2 0.2 0.2) (V2 0.8 0.8) Valley flat of
        Left (CannotFold _) -> pure ()
        other -> expectationFailure ("expected a refusal, got " <> show (fmap frameClasses other))
