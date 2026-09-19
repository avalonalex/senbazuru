-- | Geometric-reference checks without material optimization. Finite
-- differences verify the fit's derivatives independently; the final meshes
-- are measured only after the original grips have been copied back exactly.
module HeldBendSpec (spec) where

import ClosedCrease
import Control.Monad (forM_, when)
import CoupledCrease
import CreasePairContact
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import FoldMaterial (componentCount)
import HeldBend
import OuterStrip
import PrescribedBend
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Test.Hspec

cases :: [(OuterMesh, HeldConstruction)]
cases = [(m, c) | m <- [minBound .. maxBound], c <- [minBound .. maxBound]]

spec :: Spec
spec = describe "prescribed bend retaining both grips" $ do
  it "constructs a unit-speed arc and straight section reaching the authored outer grip" $ do
    c <- right commonCurve
    target <- right gripTarget
    norm (curvePoint c 0.5 0 ^-^ target) `shouldSatisfy` (< 1e-14)
    near (curveCurvature c) 3.0580801512553832
    near (curveArcLength c) 0.16386821585740233
    let h = 1e-6
        derivative s = (1 / (2 * h)) *^ (curvePoint c (s + h) 0 ^-^ curvePoint c (s - h) 0)
    forM_ [0.05, heldStart, 0.2, heldStart + curveArcLength c, 0.4] $ \s -> abs (norm (derivative s) - 1) `shouldSatisfy` (< 1e-9)
    forM_ [heldStart, heldStart + curveArcLength c] $ \s -> norm (derivative (s - h) ^-^ derivative (s + h)) `shouldSatisfy` (< 1e-5)

  it "matches independent differences of curve and polygon endpoints to the analytic Jacobian" $ do
    c <- right commonCurve
    let h = 1e-5
    kp <- right (makeCurve (curveCurvature c + h) (curveArcLength c))
    km <- right (makeCurve (curveCurvature c - h) (curveArcLength c))
    ap <- right (makeCurve (curveCurvature c) (curveArcLength c + h))
    am <- right (makeCurve (curveCurvature c) (curveArcLength c - h))
    let check f (_, k, a) = do
          norm (k ^-^ ((1 / (2 * h)) *^ (f kp ^-^ f km))) `shouldSatisfy` (< 1e-8)
          norm (a ^-^ ((1 / (2 * h)) *^ (f ap ^-^ f am))) `shouldSatisfy` (< 1e-8)
    forM_ [0.05, 0.15, 0.25, 0.35, 0.5] $ \s -> check (\v -> curvePoint v s 0) (curveDifferential c s)
    forM_ [minBound .. maxBound] $ \m -> check (\v -> let (p, _, _) = polygonEndpoint m v in p) (polygonEndpoint m c)

  it "retains all original material, passive springs, crease ids and exact touching order" $
    forM_ cases $ \(m, c) -> do
      probe <- right (heldProbe m c)
      let paper = heldPaper probe
          mesh = closedMesh paper
          base = coupledReference (heldOriginal probe)
          points = M.fromList [((materialU p, materialV p), position p) | p <- samples mesh]
      triangles mesh `shouldBe` triangles (closedMesh base)
      map sampleMaterial (samples mesh) `shouldBe` map sampleMaterial (samples (closedMesh base))
      closedHinges paper `shouldBe` closedHinges base
      closedOwners paper `shouldBe` closedOwners base
      closedRoot paper `shouldBe` [0, 1, 2]
      componentCount mesh `shouldBe` 1
      forM_ (samples mesh) $ \p -> M.lookup (negate (materialU p), materialV p) points `shouldBe` Just (position p)
      measured <- right (measureProbe paper)
      probeCreaseError measured `shouldSatisfy` (< 1e-12)
      probeControlEnergy measured `shouldBe` 0
      gaps <- right (auditPairContact (closedOwners paper) mesh)
      pairMinimum gaps `shouldBe` 0
      pairMaximum gaps `shouldBe` 0

  it "preserves both grip regions on the sampled and fitted references, never snapping the drifting control" $
    forM_ cases $ \(m, c) -> do
      p <- right (heldProbe m c)
      target <- right gripTarget
      let mesh = closedMesh (heldPaper p); points = IM.fromList (zip [0 ..] (samples mesh)); pins = coupledPins (heldOriginal p)
      if c == FullLengthReference
        then do
          norm (heldRawEndpoint p ^-^ target) `shouldSatisfy` (> 1e-6)
          heldPinAdjustment p `shouldBe` 0
        else do
          forM_ (IM.toList pins) $ \(i, q) -> fmap position (IM.lookup i points) `shouldBe` Just q
          heldPinAdjustment p `shouldSatisfy` (<= 1e-14)
      forM_ [q | q <- samples mesh, abs (materialU q) <= heldStart] $ \q -> position q `shouldBe` V3 (abs (materialU q)) (materialV q) 0

  it "separates sampled chord strain from full-length geometry and its identical angular cost" $
    forM_ [minBound .. maxBound] $ \m -> do
      ps <- right (heldProbe m CurveSamples)
      pr <- right (heldProbe m FullLengthReference)
      ph <- right (heldProbe m FullLengthHeld)
      ms <- right (measureProbe (heldPaper ps))
      mr <- right (measureProbe (heldPaper pr))
      mh <- right (measureProbe (heldPaper ph))
      probeRelativeError ms `shouldSatisfy` (> 1e-5)
      forM_ [mr, mh] $ \v -> probeRelativeError v `shouldSatisfy` (< 1e-11)
      near (probeUpperEnergy ms) (probeUpperEnergy mr)
      near (probeLowerEnergy ms) (probeLowerEnergy mr)
      forM_ [(ps, ms), (pr, mr), (ph, mh)] $ \(p, v) -> do
        near (probeLowerEnergy v) (predictedPassive m (heldCurve p))
        near (probeUpperEnergy v) (predictedPassive m (heldCurve p))

  it "records a decreasing bounded geometric fit and distinguishes it from a common smooth curve" $
    forM_ cases $ \(m, c) -> do
      p <- right (heldProbe m c)
      reference <- right commonCurve
      if c == FullLengthHeld
        then do
          length (heldFitSteps p) `shouldSatisfy` (\n -> n > 1 && n <= 17)
          let residuals = map fitResidual (heldFitSteps p)
          and (zipWith (>) residuals (drop 1 residuals)) `shouldBe` True
          norm (heldRawEndpoint p ^-^ curvePoint reference 0.5 0) `shouldSatisfy` (< 2e-14)
          abs (curveCurvature (heldCurve p) - curveCurvature reference) `shouldSatisfy` (> 1e-3)
        else heldFitSteps p `shouldBe` []
      when (c /= FullLengthHeld) $ heldCurve p `shouldBe` reference

  it "refuses invalid reference parameters before they can create degenerate chords" $
    forM_ [(0, 0.1), (-1, 0.1), (3, 0), (3, freeLength), (20, 0.2), (0 / 0, 0.1), (3, 1 / 0)] $
      \(k, a) -> makeCurve k a `shouldSatisfy` isLeft

near :: Double -> Double -> Expectation
near a b = abs (a - b) `shouldSatisfy` (< 1e-10)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
