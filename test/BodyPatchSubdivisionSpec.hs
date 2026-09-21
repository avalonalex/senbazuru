-- | Inherited geometry and refusal gates; no large opening solves in CI.
module BodyPatchSubdivisionSpec (spec) where

import BodyPatch
import BodyPatchSubdivision
import CranePocket
import CraneSpread
import Data.Either (isLeft)
import FoldRelaxation (maxLengthError)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Test.Hspec

spec :: Spec
spec = beforeAll load $ describe "recovered body subdivision" $ do
  it "preserves a valid closed sheet, material identities and coincident layers" $ \atlas -> do
    coarse <- right (bodyPatch atlas 0 0)
    fine <- right (bodyPatch atlas 1 0)
    split <- right (subdivideRecovered coarse fine (spreadMesh (patchSpread coarse)))
    split `shouldBe` spreadMesh (patchSpread fine)
    length (samples split) `shouldBe` 87
    length (triangles split) `shouldBe` 120
    right (seedPassed fine split) `shouldReturn` True

  it "retains current deformation instead of reapplying the original guess" $ \atlas -> do
    coarse <- right (bodyPatch atlas 0 5)
    fine <- right (bodyPatch atlas 1 5)
    let original = spreadMesh (patchSpread coarse)
        shifted = original {samples = [p {position = position p ^+^ V3 0.003 0.002 0.001} | p <- samples original]}
    split <- right (subdivideRecovered coarse fine shifted)
    take (length (samples original)) (samples split) `shouldBe` samples shifted
    maxLengthError split `shouldSatisfy` (\v -> abs (v - maxLengthError shifted) < 1e-12)
    -- A subdivision is allowed to describe invalid input; the separate gate
    -- refuses to solve it, including moved holds and the original bad guess.
    right (seedPassed fine split) `shouldReturn` False
    right (seedPassed fine (spreadMesh (patchSpread fine))) `shouldReturn` False

  it "refuses changed material, topology, opening, or source identity" $ \atlas -> do
    coarse <- right (bodyPatch atlas 0 5)
    fine <- right (bodyPatch atlas 1 5)
    wrong <- right (bodyPatch atlas 1 0)
    let original = spreadMesh (patchSpread coarse)
        altered = original {samples = [p {sampleMaterial = 2 *^ sampleMaterial p} | p <- samples original]}
    subdivideRecovered coarse fine altered `shouldSatisfy` isLeft
    subdivideRecovered coarse fine original {triangles = []} `shouldSatisfy` isLeft
    subdivideRecovered coarse wrong original `shouldSatisfy` isLeft
    subdivideRecovered coarse fine {patchFaces = reverse (patchFaces fine)} original `shouldSatisfy` isLeft

load :: IO PocketMap
load = do source <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= right); right (buildCranePocket source)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
