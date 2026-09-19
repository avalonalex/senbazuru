-- | Compare actual mesh measurements with a scalar curve calculation and the
-- previous archived constructions. No equilibrium solves run in these tests.
module BendRefinementSpec (spec) where

import BendRefinement
import ClosedCrease
import Control.Monad (forM_)
import CreasePairContact
import Data.Map.Strict qualified as M
import FoldMaterial (componentCount)
import HeldBend
import OuterStrip
import PrescribedBend
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Test.Hspec hiding (after, before)

spec :: Spec
spec = describe "fixed bend refinement ladder" $ do
  it "halves every length interval while retaining the original holds and width rows" $ do
    let meshes = [Uniform64, Uniform128, Uniform256, Uniform512, Uniform1024]
    forM_ (zip meshes (drop 1 meshes)) $ \(a, b) -> do
      let before = referenceColumns a; after = referenceColumns b
      all (`elem` after) before `shouldBe` True
      length after `shouldBe` 2 * length before - 1
      all (`elem` after) [0, 1 / 8, 1 / 2] `shouldBe` True
    referenceColumns Uniform64 `shouldBe` outerColumns Coarse
    referenceColumns Uniform128 `shouldBe` outerColumns Fine
    referenceColumns Uneven120 `shouldBe` outerColumns RestOnly

  it "reproduces the coarse, uneven and fully refined controls without refitting curves" $
    forM_ [CircularArc, SmoothTransition] $ \family -> do
      curve <- right (commonCurveWith family)
      forM_ [(Uniform64, Coarse), (Uniform128, Fine), (Uneven120, RestOnly)] $ \(n, m) ->
        forM_ [(SampledReference, CurveSamples), (LengthReference, FullLengthReference)] $ \(c, d) -> do
          paper <- right (fixedReference n c curve)
          old <- heldPaper <$> right (heldProbeWith family m d)
          triangles (closedMesh paper) `shouldBe` triangles (closedMesh old)
          map sampleMaterial (samples (closedMesh paper)) `shouldBe` map sampleMaterial (samples (closedMesh old))
          closedHinges paper `shouldBe` closedHinges old
          forM_ (zip (samples (closedMesh paper)) (samples (closedMesh old))) $ \(p, q) -> norm (position p ^-^ position q) `shouldSatisfy` (< 1e-14)
          p <- right (measureProbe paper)
          q <- right (measureProbe old)
          near (probeLowerEnergy p) (probeLowerEnergy q)

  it "measures unchanged material stiffness, full lengths and coincident distinct layers at every level" $
    forM_ [CircularArc, SmoothTransition] $ \family -> do
      curve <- right (commonCurveWith family)
      target <- right gripTarget
      forM_ referenceMeshes $ \(choice, _, _) -> do
        sampled <- right (fixedReference choice SampledReference curve)
        full <- right (fixedReference choice LengthReference curve)
        sm <- right (measureProbe sampled)
        fm <- right (measureProbe full)
        closedHinges sampled `shouldBe` closedHinges full
        probeRelativeError fm `shouldSatisfy` (< 1e-11)
        probeRelativeError sm `shouldSatisfy` (> 1e-7)
        near (probeLowerEnergy sm) (probeLowerEnergy fm)
        forM_ [(sampled, sm), (full, fm)] $ \(paper, measured) -> do
          let mesh = closedMesh paper
              points = M.fromList [((materialU p, materialV p), position p) | p <- samples mesh]
          length (triangles mesh) `shouldBe` 8 * (length (referenceColumns choice) - 1)
          componentCount mesh `shouldBe` 1
          closedRoot paper `shouldBe` [0, 1, 2]
          forM_ (samples mesh) $ \p -> M.lookup (negate (materialU p), materialV p) points `shouldBe` Just (position p)
          forM_ [p | p <- samples mesh, abs (materialU p) <= heldStart] $ \p -> position p `shouldBe` V3 (abs (materialU p)) (materialV p) 0
          probeCreaseError measured `shouldSatisfy` (< 1e-12)
          probeControlEnergy measured `shouldBe` 0
          near (probeLowerEnergy measured) (referenceAngularCost choice curve)
          near (probeUpperEnergy measured) (referenceAngularCost choice curve)
        let endpoint paper = [position p | p <- samples (closedMesh paper), materialU p == 0.5, materialV p == 0]
        forM_ (endpoint sampled) $ \p -> norm (p ^-^ target) `shouldSatisfy` (< 1e-14)
        forM_ (endpoint full) $ \p -> norm (p ^-^ target) `shouldSatisfy` (> 1e-7)

  it "checks exact triangle contact on a refined mesh across both reference constructions" $
    forM_ [CircularArc, SmoothTransition] $ \family -> do
      curve <- right (commonCurveWith family)
      forM_ [SampledReference, LengthReference] $ \c -> do
        paper <- right (fixedReference Uniform256 c curve)
        gaps <- right (auditPairContact (closedOwners paper) (closedMesh paper))
        pairMinimum gaps `shouldBe` 0
        pairMaximum gaps `shouldBe` 0

  it "approaches each fixed analytic cost without fitting a new shape on finer meshes" $
    forM_ [CircularArc, SmoothTransition] $ \family -> do
      curve <- right (commonCurveWith family)
      let cost = curveEnergy curve
          errors = [abs (referenceAngularCost m curve / cost - 1) | m <- [Uniform64, Uniform128, Uniform256, Uniform512, Uniform1024]]
      and (zipWith (>) errors (drop 1 errors)) `shouldBe` True
      abs (referenceAngularCost Uniform1024 curve / cost - 1) `shouldSatisfy` (< abs (referenceAngularCost Uniform64 curve / cost - 1) / 8)

near :: Double -> Double -> Expectation
near a b = abs (a - b) `shouldSatisfy` (< 1e-10)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
