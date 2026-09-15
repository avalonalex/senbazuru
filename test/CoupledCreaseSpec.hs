-- | The released lower panel must actually move, while contact, shared
-- material and authored crease checks still apply to the complete sheet.
module CoupledCreaseSpec (spec) where

import ClosedCrease
import ContactQuadratic
import Control.Monad (forM_, when)
import CoupledCrease
import CreaseInequality
import CreasePairContact
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import FoldBending
import FoldRelaxation
import Senbazuru.Fold.Types (FaceId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Surface
import Test.Hspec

spec :: Spec
spec = describe "both crease panels bending" $ do
  it "releases both interiors and shares only the real crease vertices" $
    forM_ [1, 2] $ \n -> do
      f <- right (coupledCrease n BothTouching)
      let m = coupledSeed f
          free = [p | (i, p) <- zip [0 ..] (samples m), IM.notMember i (coupledPins f)]
      length [p | p <- free, materialU p > 0] `shouldBe` (9 * n - 3)
      length [p | p <- free, materialU p < 0] `shouldBe` (9 * n - 3)
      forM_ (closedRoot (coupledReference f)) $ \i -> IM.member i (coupledPins f) `shouldBe` True
      audit <- right (auditPairContact (closedOwners (coupledReference f)) m)
      pairMinimum audit `shouldBe` 0

  it "repairs penetration on both sides without moving holds or horizontal coordinates" $
    forM_ [(n, c) | n <- [1, 2], c <- [BothPenetrating, BothTiny]] $ \(n, c) -> do
      f <- right (coupledCrease n c)
      repair <- right (repairCoupled f (coupledSeed f))
      let m = repairedMesh repair
          expected = if c == BothTiny then 1e-8 else 0.001 :: Double
      abs (fromRational (commonLift repair) - expected) `shouldSatisfy` (< 1e-15)
      checkCoupledMaterial f m `shouldBe` Right ()
      forM_ (zip3 [0 ..] (samples (coupledSeed f)) (samples m)) $ \(i, a, b) -> do
        let V3 ax ay az = position a; V3 bx by bz = position b
        (ax, ay) `shouldBe` (bx, by)
        when (IM.notMember i (coupledPins f)) $
          if materialU a < 0 then bz `shouldSatisfy` (> az) else bz `shouldSatisfy` (< az)
      audit <- right (auditPairContact (closedOwners (coupledReference f)) m)
      pairMinimum audit `shouldBe` 0
      again <- right (repairCoupled f m)
      repairedMesh again `shouldBe` m
      commonLift again `shouldBe` 0

  it "converges with both panels moving and passing complete endpoint checks" $
    forM_ [(1, BothPenetrating), (2, BothTouching)] $ \(n, control) -> do
      f <- right (coupledCrease n control)
      result <- right (solveCoupled (Settings 40 1e-5) f)
      let mesh = inequalityMesh result
          reference = closedMesh (coupledReference f)
          vertices = IM.fromList (zip [0 ..] (samples mesh))
      inequalityConverged result `shouldBe` True
      maxLengthError mesh `shouldSatisfy` (<= 1e-5)
      checkCoupledMaterial f mesh `shouldBe` Right ()
      forM_ [1, -1] $ \side -> maximum (0 : [norm (position a ^-^ position b) | (a, b) <- zip (samples reference) (samples mesh), signum (materialU a) == side]) `shouldSatisfy` (> 1e-3)
      audit <- right (auditPairContact (closedOwners (coupledReference f)) mesh)
      pairMinimum audit `shouldBe` 0
      contact <- right (checkTriangleContact (V3 0 0 1) [(FaceId 0, FaceId 1)] (closedOwners (coupledReference f)) mesh)
      contactPassed contact `shouldBe` True
      forM_ [h | h <- closedHinges (coupledReference f), SurfaceCrease _ <- [hingeRole h]] $ \h -> do
        (angle, _) <- right (hingeAngle h vertices)
        abs (angleError angle pi) `shouldSatisfy` (<= 1e-5)
      surface <- right (coupledSurface f mesh)
      surfaceSamples surface `shouldBe` samples mesh
      forM_ (inequalitySteps result) $ \step -> do
        stepMinGap step `shouldSatisfy` (>= 0)
        when (stepAccepted step) $ stepEnergyAfter step `shouldSatisfy` (< stepEnergyBefore step)
      case reverse (inequalitySteps result) of
        [] -> expectationFailure "missing convergence evidence"
        final : _ -> do
          stepSettled final `shouldBe` True
          stepMovement final `shouldSatisfy` (<= 1e-7)
          quadraticConverged (stepQuadratic final) `shouldBe` True

  it "refuses incompatible holds, lost shared holds and changed material" $ do
    forM_ [1, 2] $ \n -> do
      impossible <- right (coupledCrease n IncompatibleHolds)
      solveCoupled (Settings 40 1e-5) impossible `shouldSatisfy` isLeft
    f <- right (coupledCrease 1 BothTouching)
    repairCoupled f {coupledPins = IM.empty} (coupledSeed f) `shouldSatisfy` isLeft
    let changed = (coupledSeed f) {samples = [p {sampleMaterial = V2 99 99} | p <- samples (coupledSeed f)]}
    repairCoupled f changed `shouldSatisfy` isLeft
    solveCoupled (Settings 0 1e-5) f `shouldSatisfy` isLeft
    exhausted <- right (solveCoupled (Settings 1 1e-5) f)
    inequalityConverged exhausted `shouldBe` False

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
