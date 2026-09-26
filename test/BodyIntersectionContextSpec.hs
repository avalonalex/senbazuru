-- | Small geometric controls; no archived body solve runs in CI.
module BodyIntersectionContextSpec (spec) where

import BodyIntersectionContext
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Render.Camera (bottomUp, topDown)
import Test.Hspec

spec :: Spec
spec = describe "intersection drawing coverage" $ do
  let segment = (V2 0 0, V2 4 0)
      box a b = [V2 a (-1), V2 b (-1), V2 b 1, V2 a 1]
  it "clips the full segment rather than mistaking a covered midpoint for full coverage" $ do
    segmentInterval segment (box 1 3) `shouldBe` Just (0.25, 0.75)
    segmentInterval segment (reverse (box 1 3)) `shouldBe` Just (0.25, 0.75)
    segmentInterval segment (box (-1) 5) `shouldBe` Just (0, 1)
    segmentInterval segment (box 5 6) `shouldBe` Nothing
  it "unions touching/overlapping pieces without hiding gaps or double-counting" $ do
    coveredFraction [(0.5, 1), (0, 0.6), (0.1, 0.2)] `shouldBe` 1
    coveredFraction [(0, 0.25), (0.75, 1)] `shouldBe` 0.5
    coveredFraction [] `shouldBe` 0
    coveredFraction [(-1, 0.5), (0.5, 2)] `shouldBe` 1
  it "retains boundary coverage but refuses a point or a degenerate region" $ do
    segmentInterval (V2 0 1, V2 4 1) (box 0 4) `shouldBe` Just (0, 1)
    segmentInterval segment (box 4 5) `shouldBe` Nothing
    segmentInterval (V2 0 0, V2 0 0) (box 0 4) `shouldBe` Nothing
    segmentInterval segment [V2 0 0, V2 1 0, V2 2 0] `shouldBe` Nothing
  it "separates a layer-order tie from actual geometric depth coverage" $ do
    positiveDepthInterval (0, 1) (3, -1) `shouldBe` Just (0, 0.75)
    positiveDepthInterval (0.25, 0.75) (-1, 1) `shouldBe` Just (0.5, 0.75)
    positiveDepthInterval (0, 1) (0, 0) `shouldBe` Nothing
    positiveDepthInterval (0, 1) (0, 1) `shouldBe` Just (0, 1)
  it "uses original plane depth and reverses nearness when viewed from below" $ do
    let plane = [V3 0 0 2, V3 4 0 6, V3 0 4 2]
    planeDepth topDown plane (V2 1 1) `shouldBe` Just (-3)
    planeDepth bottomUp plane (V2 (-1) 1) `shouldBe` Just 3
    planeDepth topDown [V3 0 0 0, V3 0 1 0, V3 0 1 1] (V2 0 0) `shouldBe` Nothing
