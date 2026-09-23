-- | Coordinate-scale repairs exercise the projection without another body
-- solve in CI. An orthogonal displacement proves minimum movement; a held
-- plane gives an independently exact finite-distance repair.
module BodyContactRestorationSpec (spec) where

import BodyContactRestoration
import BodyPlaneGuard
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Test.Hspec

spec :: Spec
spec = describe "one plane-distance restoration" $ do
  it "recovers a known linear loss with the least squared movement" $ do
    let g = IM.fromList [(0, V3 1 0 0), (1, V3 0 2 0)]
        m = PlaneMeasure (-0.01) g
    d <- right (restorePlane IM.empty 0 m)
    let a = IM.findWithDefault (V3 0 0 0) 0 d; b = IM.findWithDefault (V3 0 0 0) 1 d
    a `shouldBe` V3 0.002 0 0
    b `shouldBe` V3 0 0.004 0
    abs (dot a (V3 1 0 0) + dot b (V3 0 2 0) - 0.01) `shouldSatisfy` (< 1e-15)
    -- (2,-1) is perpendicular to the combined gradient (1,2).
    mapM_ (\s -> dot a a + dot b b `shouldSatisfy` (< dot (a ^+^ V3 (2 * s) 0 0) (a ^+^ V3 (2 * s) 0 0) + dot (b ^+^ V3 0 (-s) 0) (b ^+^ V3 0 (-s) 0))) [-1, -0.1, 0.1, 1]

  it "restores a held plane at the study's tiny loss scale without moving holds" $ do
    let sheet = Mesh [Sample (V2 (fromIntegral i) 0) p | (i, p) <- zip [0 :: Int ..] [V3 0 0 0, V3 1 0 0, V3 0 1 0, V3 2 0.25 (-1.00004e-7)]] [(0, 1, 2)]
        pins = IM.fromList [(i, position p) | (i, p) <- zip [0 ..] (samples sheet), i < 3]
        target = -9.99988e-8
    initialMeasure <- right (measurePlane sheet 3 0)
    d <- right (restorePlane pins target initialMeasure)
    IM.keys d `shouldBe` [3]
    let result = sheet {samples = [p {position = position p ^+^ IM.findWithDefault (V3 0 0 0) i d} | (i, p) <- zip [0 ..] (samples sheet)]}
    take 3 (samples result) `shouldBe` take 3 (samples sheet)
    finalMeasure <- right (measurePlane result 3 0)
    abs (planeDistance finalMeasure - target) `shouldSatisfy` (< 1e-20)

  it "does nothing when the existing distance already reaches the target" $ do
    restorePlane IM.empty (-0.1) (PlaneMeasure 0 IM.empty) `shouldBe` Right IM.empty

  it "refuses a lost distance when every responsive coordinate is held" $ do
    restorePlane (IM.singleton 3 (V3 0 0 0)) 0 (PlaneMeasure (-0.1) (IM.singleton 3 (V3 0 0 1))) `shouldBe` Left NoFreePlaneResponse

  it "rejects nonfinite inputs or an overflowing correction" $ do
    restorePlane IM.empty (0 / 0) (PlaneMeasure 0 IM.empty) `shouldSatisfy` isLeft
    restorePlane IM.empty 0 (PlaneMeasure (-1) (IM.singleton 1 (V3 (1 / 0) 0 0))) `shouldSatisfy` isLeft
    restorePlane IM.empty 1e308 (PlaneMeasure 0 (IM.singleton 1 (V3 1e-100 0 0))) `shouldSatisfy` isLeft

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
