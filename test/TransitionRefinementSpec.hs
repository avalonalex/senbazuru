-- | Check the fixed placement policy independently from any claimed energy
-- improvement. Local refinement is allowed to lose to the uniform control.
module TransitionRefinementSpec (spec) where

import BendRefinement
import ClosedCrease
import Control.Monad (forM_)
import CreasePairContact
import Data.Either (isLeft)
import Data.Map.Strict qualified as M
import HeldBend
import PrescribedBend
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Test.Hspec
import TransitionRefinement

spec :: Spec
spec = describe "equal-budget transition refinement" $ do
  it "validates material columns before normalization or mesh construction" $ do
    forM_ [minBound .. maxBound] $ \mesh -> makeReferenceGrid (referenceColumns mesh) `shouldBe` Right (referenceGrid mesh)
    forM_ [[], [0, 1 / 2], [0, 1 / 8, 1 / 8, 1 / 2], [0, 1 / 4, 1 / 8, 1 / 2], [0, 1 / 8, 1 / 8 + 1 / (10 ^ (100 :: Int)), 1 / 2], [0, 1 / 8, 1 / 2, 1]] $ \cols -> makeReferenceGrid cols `shouldSatisfy` isLeft

  it "integrates the fixed density and counts overlapping windows only once" $ do
    c <- right (makeCurve 3 (1 / 8))
    intervalPriority c (3 / 32) (5 / 32) `shouldBe` 1 / 4
    intervalPriority c 0 (1 / 16) `shouldBe` 1 / 16
    intervalPriority c (1 / 16) (1 / 8) `shouldBe` 5 / 32
    short <- right (makeCurve 3 (1 / 64))
    intervalPriority short 0 (1 / 2) `shouldBe` 47 / 64

  it "keeps both ladders nested at equal budgets and retains every original coarse column" $
    forM_ [CircularArc, SmoothTransition] $ \family -> do
      c <- right (commonCurveWith family)
      grids <- mapM (\m -> right (transitionGrid m c)) [Uniform64, Uniform128, Uniform256, Uniform512, Uniform1024]
      forM_ (zip grids [9, 17, 33, 65, 129]) $ \(g, n) -> do
        length (gridColumns g) `shouldBe` n
        all (`elem` gridColumns g) (referenceColumns Uniform64) `shouldBe` True
      forM_ (zip grids (drop 1 grids)) $ \(a, b) -> all (`elem` gridColumns b) (gridColumns a) `shouldBe` True
      transitionGrid Uniform64 c `shouldBe` Right (referenceGrid Uniform64)
      transitionGrid Uneven120 c `shouldSatisfy` isLeft

  it "retains material lengths, grip diagnostics and distinct coincident layers without changing springs" $
    forM_ [CircularArc, SmoothTransition] $ \family -> do
      c <- right (commonCurveWith family)
      target <- right gripTarget
      forM_ [Uniform64, Uniform128, Uniform256, Uniform512, Uniform1024] $ \budget -> do
        grid <- right (transitionGrid budget c)
        sample <- right (gridReference grid SampledReference c)
        full <- right (gridReference grid LengthReference c)
        closedHinges sample `shouldBe` closedHinges full
        forM_ [(SampledReference, sample), (LengthReference, full)] $ \(mode, paper) -> do
          let mesh = closedMesh paper; points = M.fromList [((materialU p, materialV p), position p) | p <- samples mesh]
          length (triangles mesh) `shouldBe` 8 * (length (referenceColumns budget) - 1)
          closedRoot paper `shouldBe` [0, 1, 2]
          forM_ (samples mesh) $ \p -> M.lookup (negate (materialU p), materialV p) points `shouldBe` Just (position p)
          forM_ [p | p <- samples mesh, abs (materialU p) <= heldStart] $ \p -> position p `shouldBe` V3 (abs (materialU p)) (materialV p) 0
          measured <- right (measureProbe paper)
          near (probeLowerEnergy measured) (gridAngularCost grid c)
          near (probeUpperEnergy measured) (gridAngularCost grid c)
          probeCreaseError measured `shouldSatisfy` (< 1e-12)
          probeControlEnergy measured `shouldBe` 0
          case mode of
            LengthReference -> probeRelativeError measured `shouldSatisfy` (< 1e-11)
            SampledReference -> probeRelativeError measured `shouldSatisfy` (> 0)
          case M.lookup (0.5, 0) points of
            Nothing -> expectationFailure "missing outer grip"
            Just p -> case mode of
              SampledReference -> norm (p ^-^ target) `shouldSatisfy` (< 1e-14)
              LengthReference -> norm (p ^-^ target) `shouldSatisfy` (> 1e-8)

  it "checks exact triangle touching order on the new unequal strips" $
    forM_ [CircularArc, SmoothTransition] $ \family -> do
      c <- right (commonCurveWith family)
      grid <- right (transitionGrid Uniform256 c)
      forM_ [SampledReference, LengthReference] $ \mode -> do
        paper <- right (gridReference grid mode c)
        gaps <- right (auditPairContact (closedOwners paper) (closedMesh paper))
        pairMinimum gaps `shouldBe` 0
        pairMaximum gaps `shouldBe` 0

  it "finds the circular chord sagitta even though all shared sampled vertices agree" $ do
    c <- right commonCurve
    let coarse = referenceGrid Uniform64
        fine = referenceGrid Uniform128
        radius = 1 / curveCurvature c
        sagitta = radius * (1 - cos (curveCurvature c / 32))
    (distance, _) <- right (profileDifference coarse fine SampledReference c)
    near distance sagitta
    distance `shouldSatisfy` (> 0.001)
    forM_ [SampledReference, LengthReference] $ \mode -> profileDifference fine fine mode c `shouldBe` Right (0, 0)

near :: Double -> Double -> Expectation
near a b = abs (a - b) `shouldSatisfy` (< 1e-10)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
