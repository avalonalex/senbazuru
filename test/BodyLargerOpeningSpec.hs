-- | Test the new static guess without a costly body solve in ordinary CI.
module BodyLargerOpeningSpec (spec) where

import BodyLargerOpening
import BodyPatch
import CranePocket
import CraneSpread
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Test.Hspec

spec :: Spec
spec = beforeAll load $ describe "recovered body opening guess" $ do
  it "retains free-vertex recovery, installs exact new holds and keeps material identity" $ \(old, new) -> do
    let a = patchSpread old
        b = patchSpread new
        delta = V3 0.0001 (-0.0002) 0.0003
        recovered = (spreadMesh a) {samples = [if IM.member i (spreadPins a) then p else p {position = position p ^+^ delta} | (i, p) <- zip [0 ..] (samples (spreadMesh a))]}
    guess <- right (openingGuess old new recovered)
    triangles guess `shouldBe` triangles recovered
    map sampleMaterial (samples guess) `shouldBe` map sampleMaterial (samples recovered)
    spreadHeldError b guess `shouldBe` 0
    let differences = zipWith (\p q -> position p ^-^ position q) (samples guess) (samples (spreadMesh b))
    and [norm (d ^-^ if IM.member i (spreadPins b) then V3 0 0 0 else delta) < 1e-14 | (i, d) <- zip [0 ..] differences] `shouldBe` True

  it "refuses another target, changed material, and a moved original hold" $ \(old, new) -> do
    let mesh = spreadMesh (patchSpread old)
    openingGuess old new {patchDegrees = 7} mesh `shouldSatisfy` isLeft
    openingGuess old new mesh {samples = [p {sampleMaterial = sampleMaterial p ^+^ V2 0.01 0} | p <- samples mesh]} `shouldSatisfy` isLeft
    openingGuess old new mesh {samples = [p {position = position p ^+^ V3 0 0.001 0} | p <- samples mesh]} `shouldSatisfy` isLeft

load :: IO (BodyPatch, BodyPatch)
load = do
  source <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= right)
  atlas <- right (buildCranePocket source)
  (,) <$> right (bodyPatch atlas 1 5) <*> right (bodyPatch atlas 1 10)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
