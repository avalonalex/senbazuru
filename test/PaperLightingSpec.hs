-- | Distinguish lighting continuity from paper continuity and coincident layers.
module PaperLightingSpec (spec) where

import Data.Either (isLeft)
import PaperLighting
import Senbazuru.Fold.Types (FaceId (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (Mesh (..), Sample (..))
import Test.Hspec

spec :: Spec
spec = describe "lighting within original paper panels" $ do
  it "shares area-weighted directions only at common material corners" $ do
    let common = V3 0 (2 / sqrt 5) (1 / sqrt 5)
    normals <- right (panelCornerNormals [FaceId 7, FaceId 7] bent)
    normals `shouldSatisfy` close [[common, common, V3 0 0 1], [common, common, V3 0 1 0]]

  it "keeps a sharp crease between different source panels" $
    panelCornerNormals [FaceId 7, FaceId 8] bent `shouldBe` Right [replicate 3 (V3 0 0 1), replicate 3 (V3 0 1 0)]

  it "does not weld separate material vertices at coincident positions" $ do
    let separate = bent {samples = samples bent ++ map (Sample ()) [V3 0 0 0, V3 1 0 0], triangles = [(0, 1, 2), (5, 4, 3)]}
    panelCornerNormals [FaceId 7, FaceId 7] separate `shouldBe` Right [replicate 3 (V3 0 0 1), replicate 3 (V3 0 1 0)]

  it "retains flat lighting where opposite triangles cancel the average" $
    panelCornerNormals [FaceId 7, FaceId 7] bent {triangles = [(0, 1, 2), (1, 0, 2)]} `shouldBe` Right [replicate 3 (V3 0 0 1), replicate 3 (V3 0 0 (-1))]

  it "does not let a larger reversed triangle turn its neighbour's lighting inside out" $ do
    let reversed = bent {samples = samples bent ++ [Sample () (V3 0 2 0)], triangles = [(0, 1, 2), (1, 0, 4)]}
    panelCornerNormals [FaceId 7, FaceId 7] reversed `shouldBe` Right [replicate 3 (V3 0 0 1), replicate 3 (V3 0 0 (-1))]

  it "refuses missing panel identities, missing vertices and degenerate triangles" $ do
    panelCornerNormals [FaceId 7] bent `shouldBe` Left (LightingPanelCount 1 2)
    panelCornerNormals [FaceId 7] bent {triangles = [(0, 1, 9)]} `shouldBe` Left (LightingMissingVertex 0 9)
    panelCornerNormals [FaceId 7] bent {triangles = [(0, 1, 1)]} `shouldBe` Left (LightingBadTriangle 0)
    panelCornerNormals [FaceId 7] (Mesh (map (Sample ()) [V3 (0 / 0) 0 0, V3 1 0 0, V3 0 1 0]) [(0, 1, 2)]) `shouldSatisfy` isLeft
  where
    bent = Mesh (map (Sample ()) [V3 0 0 0, V3 1 0 0, V3 0 1 0, V3 0 0 2]) [(0, 1, 2), (1, 0, 3)]
    close expected actual = map length actual == map length expected && and (zipWith (\a b -> norm (a ^-^ b) < 1e-12) (concat expected) (concat actual))
    right = either (\err -> expectationFailure (show err) >> pure []) pure
