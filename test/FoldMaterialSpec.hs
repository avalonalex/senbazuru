-- | Numerical checks against material distances and independent closed forms.
module FoldMaterialSpec (spec) where

import FoldMaterial
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Test.Hspec
import Test.QuickCheck

spec :: Spec
spec = do
  describe "fold-material study" $ do
    it "uses exactly one unit of material for the single-fold cross-section" $
      2 * bendStart + pi * radius `shouldSatisfy` near 1
    it "places both straight flanks at the bend's endpoints" $ do
      paperPoint Single bendStart 0 `shouldSatisfy` nearPoint (V3 bendStart 0 0)
      paperPoint Single bendEnd 0 `shouldSatisfy` nearPoint (V3 bendStart 0 (2 * radius))
    it "preserves both material directions in the smooth single fold" $
      forAll (choose (0.001, 0.999)) $ \u ->
        let h = 1e-7
            du = (1 / (2 * h)) *^ (paperPoint Single (u + h) 0.3 ^-^ paperPoint Single (u - h) 0.3)
            dv = paperPoint Single u 0.8 ^-^ paperPoint Single u 0.3
         in abs (norm du - 1) < 1e-6 && abs (norm dv - 0.5) < 1e-10 && abs (dot du dv) < 1e-10
    it "keeps one connected surface and the topology of the original square" $
      mapM_
        ( \which -> do
            let mesh = makeMesh 16 which
            componentCount mesh `shouldBe` 1
            length (samples mesh) - length (meshEdges mesh) + length (triangles mesh) `shouldBe` 1
            length (resolvedTriangles mesh) `shouldBe` length (triangles mesh)
        )
        [Single, Double]
    it "converges to unchanged material lengths as circular arcs are refined" $ do
      let coarse = makeMesh 16 Single
          fine = makeMesh 32 Single
          worst mesh = maximum (0 : map abs (edgeStrains mesh))
      worst fine `shouldSatisfy` (< worst coarse / 3.9)
      worst fine `shouldSatisfy` (< 0.000402)
      areaRatio fine `shouldSatisfy` (\a -> abs (a - 1) < 0.00002)
    it "puts the perpendicular double fold in four distinct layer planes" $ do
      map (\(u, v) -> v3z (paperPoint Double u v)) [(0.2, 0.2), (0.8, 0.2), (0.2, 0.8), (0.8, 0.8)]
        `shouldBe` [0, 2 * radius, -(2 * radius), -(4 * radius)]
    it "exposes rather than hides the double fold's material deficit" $ do
      let mesh = makeMesh 32 Double
      maximum (edgeStrains mesh) `shouldSatisfy` (\s -> s > 1.998 && s < 2)
      -- Integrating the analytic area element gives 1 + pi*r, independently
      -- of the triangulation. More samples cannot remove the extra material.
      let exactArea = 1 + pi * radius
          coarseError = abs (areaRatio mesh - exactArea)
          fineError = abs (areaRatio (makeMesh 64 Double) - exactArea)
      coarseError `shouldSatisfy` (< 0.000061)
      fineError `shouldSatisfy` (< coarseError / 3.9)
      analyticStretch Double 0.8 0.5 `shouldBe` 2
      analyticStretch Double 0.2 0.5 `shouldBe` 0
      analyticStretch Double 0.8 0.2 `shouldBe` 0
    it "preserves all triangle edge lengths at the sharp single crease" $ do
      let mesh = sharpMesh 8 Single
      edgeStrains mesh `shouldSatisfy` all (\s -> abs s < 1e-12)
      areaRatio mesh `shouldSatisfy` near 1
    it "joins the sharp double fold at both crease lines without a gap" $
      forAll (choose (0, 1)) $ \s ->
        let h = 1e-8
            point = sharpPoint Double
         in norm (point (0.5 - h) s ^-^ point (0.5 + h) s) < 1e-7
              && norm (point s (0.5 - h) ^-^ point s (0.5 + h)) < 1e-7
    it "tapers sharp-fold layer gaps to the creases instead of using parallel offsets" $ do
      let height u v = v3z (sharpPoint Double u v)
      height 0.9 0.1 `shouldSatisfy` (> height 0.9 0.4)
      height 0.9 0.1 `shouldSatisfy` (> height 0.6 0.1)
      height 0.9 0.5 `shouldBe` 0
      height 0.5 0.1 `shouldBe` 0
      mapM_ (\which -> componentCount (sharpMesh 8 which) `shouldBe` 1) [Single, Double]
    it "retains measurable sharp-panel stretch under mesh refinement" $ do
      let worst n = maximum (edgeStrains (sharpMesh n Double))
      worst 8 `shouldSatisfy` (> 0.004)
      worst 16 `shouldSatisfy` (> worst 8)
      -- At the outer corner the analytic slopes are 2h and 4h.
      sharpStretch Double 1 1 `shouldSatisfy` near (sqrt (1 + 20 * opening * opening) - 1)
      worst 16 `shouldSatisfy` (< sharpStretch Double 1 1)
    it "does not flatten a top-panel triangle onto the lower layer at the intersection" $ do
      let mesh = sharpMesh 16 Double
          centre a b c = ((materialU a + materialU b + materialU c) / 3, (materialV a + materialV b + materialV c) / 3)
          heights =
            [ (v3z (position a) + v3z (position b) + v3z (position c)) / 3
              | (a, b, c) <- resolvedTriangles mesh,
                let (u, v) = centre a b c,
                u > 0.5 && v < 0.5
            ]
      heights `shouldSatisfy` (not . null)
      heights `shouldSatisfy` all (> 0)
  where
    near target x = abs (x - target) < 1e-10
    nearPoint target p = norm (p ^-^ target) < 1e-10
