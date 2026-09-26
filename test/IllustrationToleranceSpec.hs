module IllustrationToleranceSpec (spec) where

import IllustrationTolerance
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Render.Camera (project, topDown)
import Test.Hspec

spec :: Spec
spec = describe "illustration contact footprints" $ do
  it "clips at the gap threshold, including boundary corners" $ do
    let ring = negativeRegion 0 [(V3 0 0 0, -1), (V3 1 0 0, 1), (V3 0 1 0, 1)]
    projectedArea (map (project topDown) ring) `shouldBe` 0.125
    projectedArea (map (project topDown) (negativeRegion 0.5 [(V3 0 0 0, -1), (V3 1 0 0, 1), (V3 0 1 0, 1)])) `shouldBe` 0.03125
  it "does not equate a shallow penetration with a small affected area" $ do
    let corners = [(V3 0 0 0, -1e-12), (V3 1 0 0, -1e-12), (V3 0 1 0, -1e-12)]
    projectedArea (map (project topDown) (negativeRegion 0 corners)) `shouldBe` 0.5
    negativeRegion 1e-10 corners `shouldBe` []
  it "retains no region for touching or exactly tolerated paper" $ do
    negativeRegion 0 [(V3 0 0 0, 0), (V3 1 0 0, 0), (V3 0 1 0, 0)] `shouldBe` []
    negativeRegion 1 [(V3 0 0 0, -1), (V3 1 0 0, -1), (V3 0 1 0, -1)] `shouldBe` []
  it "distinguishes an edge-on footprint from its spatial size" $ do
    projectedArea [V2 0 0, V2 1 0, V2 2 0] `shouldBe` 0
    projectedDiameter [V2 0 0, V2 1 0, V2 2 0] `shouldBe` 2
