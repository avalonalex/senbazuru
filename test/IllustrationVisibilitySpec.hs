module IllustrationVisibilitySpec (spec) where

import Control.Monad (forM_)
import Data.Either (isLeft)
import IllustrationVisibility
import Senbazuru.Fold.Query (FoldError (..))
import Senbazuru.Fold.Types
import Senbazuru.Origami.Visible
import Senbazuru.Render.Camera
import Senbazuru.Render.Projected (projectedForm)
import Test.Hspec

spec :: Spec
spec = describe "illustration-only depth ties" $ do
  it "resolves a shallow crossing using its declared order without relaxing production" $ do
    let fr = panels [flat, rectangle (\x -> 1e-5 * (x - 0.5))]
    projectedForm topDown fr order `shouldBe` Right Nothing
    seen <- audit (illustrationVisibility (0.1 / 600) topDown fr order)
    faces seen `shouldBe` Just [FaceId 1]
    map pairDecision (auditPairs seen) `shouldBe` ["inherited tie"]
  it "bounds wrong-side depth without bounding correct-side separation" $ do
    let fr = panels [flat, rectangle (\x -> x - 1e-5)]
    result <- audit (illustrationVisibility (0.1 / 600) topDown fr order)
    faces result `shouldBe` Just [FaceId 1]
    map pairOverriddenDepth (auditPairs result) `shouldSatisfy` all (<= 0.1 / 600)
  it "reverses near/far when viewed from below and honours opposite face winding" $ do
    let fr = panels [flat, reverse flat]
        reversed = [FaceOrder (FaceId 0) (FaceId 1) Above]
    top <- audit (illustrationVisibility 0.001 topDown fr reversed)
    bottom <- audit (illustrationVisibility 0.001 bottomUp fr reversed)
    faces top `shouldBe` Just [FaceId 1]
    faces bottom `shouldBe` Just [FaceId 0]
  it "does not invent an order for unknown touching paper" $ do
    result <- audit (illustrationVisibility 0.001 topDown (panels [flat, flat]) [])
    faces result `shouldBe` Nothing
    map pairDecision (auditPairs result) `shouldBe` ["missing order"]
  it "keeps a crossing beyond the allowance unresolved even with an order" $ do
    result <- audit (illustrationVisibility 0.001 topDown (panels [flat, rectangle (\x -> 0.1 * (x - 0.5))]) order)
    faces result `shouldBe` Nothing
    map pairDecision (auditPairs result) `shouldBe` ["crossing outside allowance"]
  it "uses actual depth for clearly separated paper despite a stale order" $ do
    result <- audit (illustrationVisibility 0.001 topDown (panels [flat, rectangle (const 1)]) [FaceOrder (FaceId 0) (FaceId 1) Above])
    faces result `shouldBe` Just [FaceId 1]
    map pairDecision (auditPairs result) `shouldBe` ["depth"]
  it "detects contradictory orders and uncovered regions from cyclic orders" $ do
    illustrationVisibility 0.001 topDown (panels [flat, flat]) (order ++ [FaceOrder (FaceId 0) (FaceId 1) Above]) `shouldSatisfy` isLeft
    result <- audit (illustrationVisibility 0.001 topDown (panels [flat, flat, flat]) [FaceOrder (FaceId 0) (FaceId 1) Above, FaceOrder (FaceId 1) (FaceId 2) Above, FaceOrder (FaceId 2) (FaceId 0) Above])
    auditUncovered result `shouldSatisfy` (not . null)
    auditStatus result `shouldBe` "partial visibility: uncovered paper"
  -- With no allowance the experiment decides each pair as production does, and
  -- it judges areas and coverage with production's own functions, so it must
  -- draw what production draws and report uncovered paper exactly where
  -- production refuses. Two of these views used to differ. In the isometric
  -- corner it measured the corner against the model's 3D speck, smaller than
  -- the picture's speck the regions were cut with, and called the corner
  -- uncovered. Under the three faces that each cover less than a speck of a
  -- corner, it counted the piece its first pass let through as uncovered,
  -- without cutting it again.
  it "agrees with strict visibility when its additional allowance is zero" $
    forM_ strictViews $ \(name, basis, fr, orders) -> do
      result <- audit (illustrationVisibility 0 basis fr orders)
      case projectedForm basis fr orders of
        Right (Just form) -> do
          (name, auditForm result) `shouldBe` (name, Just form)
          (name, auditUncovered result) `shouldBe` (name, [])
          (name, auditStatus result) `shouldBe` (name, "visible regions cover the sheet")
        Right Nothing -> (name, auditForm result) `shouldBe` (name, Nothing)
        Left (ImpossibleStacking _) -> do
          (name, null (auditUncovered result)) `shouldBe` (name, False)
          (name, auditStatus result) `shouldBe` (name, "partial visibility: uncovered paper")
        other -> expectationFailure (name <> ": production gave " <> show other)

-- | Views production draws, refuses or declines, for the agreement test.
strictViews :: [(String, Basis, Frame, [FaceOrder])]
strictViews =
  [ ("separated, looking down", topDown, panels [flat, rectangle (const 1)], order),
    ("separated, isometric", isometric, panels [flat, rectangle (const 1)], order),
    ("isometric corner between the two specks", isometric, cornerShown, []),
    ("corner covered by faces each under a speck of it", topDown, sharedCorner, []),
    ("three faces in a circle", topDown, panels [flat, flat, flat], circle),
    ("touching faces with no order", topDown, panels [flat, flat], [])
  ]
  where
    circle = [FaceOrder (FaceId 0) (FaceId 1) Above, FaceOrder (FaceId 1) (FaceId 2) Above, FaceOrder (FaceId 2) (FaceId 0) Above]
    at z = map (\(x, y) -> [x, y, z])
    -- The unit square under a copy of itself moved towards an isometric
    -- viewer with a corner cut off whose shadow is 1.6e-9: more than the 3D
    -- speck, 1.21e-9, and less than the picture's, 2e-9 (ProjectedSpec).
    cornerShown =
      let leg = sqrt (2 * sqrt 3 * 1.6e-9)
       in panels [flat, map (zipWith (+) [0.1, -0.1, 0.1]) [[0, 0, 0], [1, 0, 0], [1, 1 - leg, 0], [1 - leg, 1, 0], [0, 1, 0]]]
    -- A corner of 2.4 specks under three faces in front, each covering 0.8 of
    -- a speck of it (ProjectedSpec, from #459).
    sharedCorner =
      let e = sqrt 4.8e-9
          side t = (0.5 - t * e, 0.5 - e + t * e)
          third = sqrt (1 / 6)
       in panels
            [ at 0 [(0, 0), (0.5, 0), (0.5, 0.5), (0, 0.5)],
              at 0.1 [(0, 0), (0.5, 0), side 0, side 1, (0, 0.5)],
              at 0.2 [side 0, (1, 1), side 1],
              at 0.3 [side 0, (1, 1), side third],
              at 0.3 [side third, (1, 1), side (1 - third)],
              at 0.3 [side (1 - third), (1, 1), side 1]
            ]

order :: [FaceOrder]
order = [FaceOrder (FaceId 0) (FaceId 1) Below]

faces :: VisibilityAudit -> Maybe [FaceId]
faces = fmap (map regionFace . formRegions) . auditForm

audit :: (Show e) => Either e a -> IO a
audit = either (\err -> expectationFailure (show err) >> fail "visibility error") pure

flat :: [[Double]]
flat = rectangle (const 0)

rectangle :: (Double -> Double) -> [[Double]]
rectangle height = [[x, y, height x] | (x, y) <- [(0, 0), (1, 0), (1, 1), (0, 1)]]

panels :: [[[Double]]] -> Frame
panels rings = emptyFrame {verticesCoords = concat rings, facesVertices = ids, edgesVertices = concat [zip vs (drop 1 vs ++ take 1 vs) | vs <- ids], edgesAssignment = replicate (sum (map length rings)) Border}
  where
    ids = [map VertexId [offset .. offset + length ring - 1] | (offset, ring) <- zip (scanl (+) 0 (map length rings)) rings]
