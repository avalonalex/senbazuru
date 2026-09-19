-- | Compare the partial-angle interpretation with independent scalar formulas
-- and finite differences. No equilibrium solves belong in this study gate.
module BandBoundarySpec (spec) where

import BandBoundary
import ClosedCrease
import Control.Monad (forM_)
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import FoldBending
import PrescribedBend
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Test.Hspec
import UnequalCrease

spec :: Spec
spec = describe "band-boundary turn fractions" $ do
  it "preserves full-interval springs and changes only partial control springs" $
    forM_ probeMeshes $ \(n, w) -> do
      fixture <- right (prescribedFixture n w FixedEdges)
      rows <- right (measureBandBoundary n fixture)
      let originals = filter ((== BendControl) . hingeRole) (closedHinges fixture)
      map boundaryOriginal rows `shouldBe` originals
      forM_ rows $ \r -> do
        let old = boundaryOriginal r
            candidate = boundaryCandidate r
        hingeVertices candidate `shouldBe` hingeVertices old
        hingeRole candidate `shouldBe` BendControl
        if boundaryFraction r == 1
          then candidate `shouldBe` old
          else do
            boundaryFraction r `shouldBe` 0.5
            near (hingeRest candidate) (2 * hingeRest old)
            near (hingeStiffness candidate) (hingeStiffness old / 4)
      length (filter ((< 1) . boundaryFraction) rows) `shouldBe` (if n == 1 then 2 * w else 4 * w)

  it "retains flat energy and total allocated preferred turn on every mesh" $ do
    preference <- right bandPreference
    forM_ probeMeshes $ \(n, w) -> do
      fixture <- right (prescribedFixture n w FlatPanels)
      rows <- right (measureBandBoundary n fixture)
      near (sum (map boundaryOldEnergy rows)) (bandReferenceEnergy preference)
      near (sum (map boundaryNewEnergy rows)) (bandReferenceEnergy preference)
      let width r = snd (boundaryWidthRange r) - fst (boundaryWidthRange r)
      near (sum [width r * boundaryFraction r * hingeRest (boundaryCandidate r) | r <- rows]) (bandDesiredTurn preference)

  it "gives both cylinder probes the same candidate energy across length and width" $ do
    preference <- right bandPreference
    let (lo, hi) = bandBounds preference
        expected = bandBendingWeight preference * (hi - lo) / 2 * (negate curvature - bandDesiredTurn preference / (hi - lo)) ^ (2 :: Int)
    forM_ [(n, w, p) | (n, w) <- probeMeshes, p <- [SampledCylinder, FixedEdges]] $ \(n, w, p) -> do
      fixture <- right (prescribedFixture n w p)
      rows <- right (measureBandBoundary n fixture)
      measured <- right (measureProbe fixture)
      near (sum (map boundaryNewEnergy rows)) expected
      near (sum (map boundaryOldEnergy rows)) (probeControlEnergy measured)
      (_, candidateEnergy) <- right (bendingEnergy (map boundaryCandidate rows) (closedMesh fixture))
      near candidateEnergy expected

  it "retains the fixed-corner control and accounts for full and clipped intervals" $ do
    preference <- right bandPreference
    forM_ probeMeshes $ \(n, w) -> do
      fixture <- right (prescribedFixture n w FixedCorners)
      rows <- right (measureBandBoundary n fixture)
      forM_ rows $ \r -> do
        let u = boundaryDistance r
            -- Fixed turns occur only at the original three strip boundaries.
            actual
              | u == 0.125 = negate (2 * atan 0.1)
              | u == 0.25 = negate (2 * (atan 0.2 - atan 0.1))
              | u == 0.375 = negate (2 * (atan 0.3 - atan 0.2))
              | otherwise = 0
            (a, b) = boundaryInterval r
            d = b - a
            spanWidth = snd (boundaryWidthRange r) - fst (boundaryWidthRange r)
            target = bandDesiredTurn preference * d / (5 / 16)
            weight = bandBendingWeight preference * spanWidth / d
        near (boundaryAngle r) actual
        near (boundaryOldEnergy r) (weight * (actual - target) ^ (2 :: Int) / 2)
        near (boundaryNewEnergy r) (weight * (d * fromIntegral (8 * n) * actual - target) ^ (2 :: Int) / 2)

  it "differentiates the attributed turn as well as its preferred value" $
    forM_ [minBound .. maxBound] $ \probe -> do
      fixture <- right (prescribedFixture 2 1 probe)
      rows <- right (measureBandBoundary 2 fixture)
      forM_ rows $ \r -> do
        let f = boundaryFraction r
            k = hingeStiffness (boundaryOriginal r)
            target = hingeRest (boundaryOriginal r)
            theta = boundaryAngle r
            candidateEnergy a = k * (f * a - target) ^ (2 :: Int) / 2
            epsilon = 1e-6
            difference = (candidateEnergy (theta + epsilon) - candidateEnergy (theta - epsilon)) / (2 * epsilon)
        near (boundaryNewSlope r) (k * f * (f * theta - target))
        abs (boundaryNewSlope r - difference) `shouldSatisfy` (< 1e-9)

  it "matches the existing spring's spatial derivative without moving a fixture" $ do
    fixture <- right (prescribedFixture 2 1 FixedEdges)
    rows <- right (measureBandBoundary 2 fixture)
    forM_ (filter ((< 1) . boundaryFraction) rows) $ \r -> do
      let h = boundaryCandidate r
          (_, _, c, _) = hingeVertices h
          mesh = closedMesh fixture
          epsilon = 1e-6
          shifted delta = mesh {samples = [if i == c then p {position = position p ^+^ V3 0 0 delta} else p | (i, p) <- zip [0 ..] (samples mesh)]}
      linear <- right (bendingRows [h] mesh)
      let derivative = sum [residual * z | (gradient, residual) <- linear, (i, V3 _ _ z) <- gradient, i == c]
      (_, above) <- right (bendingEnergy [h] (shifted epsilon))
      (_, below) <- right (bendingEnergy [h] (shifted (negate epsilon)))
      abs (derivative - (above - below) / (2 * epsilon)) `shouldSatisfy` (< 1e-6)
      (_, oldGradient) <- right (hingeAngle (boundaryOriginal r) (IM.fromList (zip [0 ..] (samples mesh))))
      near derivative (sum [boundaryNewSlope r * z | (i, V3 _ _ z) <- oldGradient, i == c])

  it "refuses missing controls, mismatched support sizes and invalid spring data" $ do
    fixture <- right (prescribedFixture 2 1 FlatPanels)
    measureBandBoundary 0 fixture `shouldSatisfy` isLeft
    measureBandBoundary 3 fixture `shouldSatisfy` isLeft
    measureBandBoundary 4 fixture `shouldSatisfy` isLeft
    measureBandBoundary 2 fixture {closedHinges = filter ((/= BendControl) . hingeRole) (closedHinges fixture)} `shouldSatisfy` isLeft
    let bad h = if hingeRole h == BendControl then h {hingeStiffness = 1 / 0} else h
    measureBandBoundary 2 fixture {closedHinges = map bad (closedHinges fixture)} `shouldSatisfy` isLeft

near :: Double -> Double -> Expectation
near actual expected = abs (actual - expected) `shouldSatisfy` (< 1e-11)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
