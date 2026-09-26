module IllustrationVisibilitySpec (spec) where

import Data.Either (isLeft)
import IllustrationVisibility
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
  it "agrees with strict visibility when its additional allowance is zero" $ do
    let fr = panels [flat, rectangle (const 1)]
    result <- audit (illustrationVisibility 0 topDown fr order)
    Right (auditForm result) `shouldBe` projectedForm topDown fr order

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
