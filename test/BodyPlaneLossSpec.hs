-- | Exact small-plane examples distinguish first-order cancellation from its
-- finite remainder without running a material or quadratic solve.
module BodyPlaneLossSpec (spec) where

import BodyPlaneLoss
import Data.Either (isLeft)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Test.Hspec

spec :: Spec
spec = describe "saved moving-plane distance accounting" $ do
  it "keeps every contribution zero for a common translation" $ do
    let shift = V3 0.2 (-0.1) 0.3; proposal = mapPose (^+^ shift) start
    m <- right (decomposePlane start proposal 0.5 (interpolate 0.5 start proposal))
    mapM_ (\x -> abs x `shouldSatisfy` (< 1e-14)) [relativeLinear m, rotationLinear m, rotationRemainder m, motionInteraction m, actualDistance m - initialDistance m]

  it "measures motion against a fixed plane exactly" $ do
    let proposal = PlanePose (V3 0.2 0.3 0.4) a b c
    m <- right (decomposePlane start proposal 0.5 (interpolate 0.5 start proposal))
    abs (actualDistance m - 0.3) `shouldSatisfy` (< 1e-14)
    relativeLinear m `shouldBe` 0.1
    mapM_ (`shouldBe` 0) [rotationLinear m, rotationRemainder m, motionInteraction m]

  it "separates cancelling linear terms from a negative quadratic interaction" $ do
    -- Plane z=s*x, measured point (1+s,0,s): distance=-s^2/sqrt(1+s^2).
    let origin = PlanePose (V3 1 0 0) a b c
        proposal = PlanePose (V3 2 0 1) a (V3 1 0 1) c
    m <- right (decomposePlane origin proposal 0.1 (interpolate 0.1 origin proposal))
    abs (actualDistance m + 0.01 / sqrt 1.01) `shouldSatisfy` (< 1e-14)
    abs (relativeLinear m + rotationLinear m) `shouldSatisfy` (< 1e-14)
    abs (quadraticDistance m + 0.01) `shouldSatisfy` (< 1e-14)
    motionInteraction m `shouldSatisfy` (< 0)
    abs (reconciliationError m) `shouldSatisfy` (< 1e-14)

  it "is invariant to cycling the triangle's centroid reference and rigid coordinates" $ do
    let proposal = PlanePose (V3 0.5 0.2 0.1) a (V3 1 0 0.2) (V3 0 1 (-0.1))
        trial = interpolate 0.2 start proposal
        cyclePose (PlanePose p x y z) = PlanePose p y z x
        rotate (V3 x y z) = V3 (-y + 2) (x - 3) (z + 1)
    m <- right (decomposePlane start proposal 0.2 trial)
    mapM_ (\transform -> do other <- right (decomposePlane (transform start) (transform proposal) 0.2 (transform trial)); mapM_ (\f -> abs (f m - f other) `shouldSatisfy` (< 1e-13)) terms) [cyclePose, mapPose rotate]

  it "reverses signed terms with the original winding" $ do
    let proposal = PlanePose (V3 0.5 0.2 0.1) a (V3 1 0 0.2) c
        trial = interpolate 0.2 start proposal
        reversePose (PlanePose p x y z) = PlanePose p x z y
    m <- right (decomposePlane start proposal 0.2 trial)
    backwards <- right (decomposePlane (reversePose start) (reversePose proposal) 0.2 (reversePose trial))
    mapM_ (\f -> abs (f m + f backwards) `shouldSatisfy` (< 1e-13)) terms

  it "retains off-path rounding separately from the proposed direction" $ do
    let proposal = PlanePose (V3 0.2 0.3 0.4) a b c; trial = PlanePose (V3 0.2 0.3 (0.3 + 1e-10)) a b c
    m <- right (decomposePlane start proposal 0.5 trial)
    abs (relativeRounding m - 1e-10) `shouldSatisfy` (< 1e-15)
    abs (reconciliationError m) `shouldSatisfy` (< 1e-15)

  it "rejects invalid fractions, nonfinite coordinates and collapsed planes" $ do
    decomposePlane start start (-1) start `shouldBe` Left InvalidPlaneFraction
    decomposePlane start start (0 / 0) start `shouldBe` Left InvalidPlaneFraction
    decomposePlane start start 0.5 (PlanePose a a a a) `shouldBe` Left InvalidPlanePose
    decomposePlane start (mapPose ((0 / 0) *^) start) 0.5 start `shouldSatisfy` isLeft

a, b, c :: V3
a = V3 0 0 0
b = V3 1 0 0
c = V3 0 1 0

start :: PlanePose
start = PlanePose (V3 0.2 0.3 0.2) a b c

terms :: [PlaneLoss -> Double]
terms = [initialDistance, actualDistance, linearDistance, quadraticDistance, relativeLinear, rotationLinear, rotationRemainder, motionInteraction, relativeRounding, rotationSecondOrder, interactionSecondOrder]

mapPose :: (V3 -> V3) -> PlanePose -> PlanePose
mapPose f (PlanePose p x y z) = PlanePose (f p) (f x) (f y) (f z)

interpolate :: Double -> PlanePose -> PlanePose -> PlanePose
interpolate s (PlanePose p x y z) (PlanePose q u v w) = PlanePose (mix p q) (mix x u) (mix y v) (mix z w)
  where
    mix a0 b0 = a0 ^+^ s *^ (b0 ^-^ a0)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
