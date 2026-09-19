-- | Closed-form checks for the prescribed probes. These use one-dimensional
-- arc/chord formulas and edge counts, independently of spatial triangle normals.
module PrescribedBendSpec (spec) where

import ClosedCrease
import Control.Monad (forM_)
import CreaseInequality (materialRows)
import CreasePairContact
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import FoldMaterial (componentCount)
import PrescribedBend
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Test.Hspec
import UnequalCrease

spec :: Spec
spec = describe "prescribed bends without optimization" $ do
  it "retains one connected sheet, distinct touching layers and the original closed crease" $
    forM_ [(n, w, p) | (n, w) <- probeMeshes, p <- [minBound .. maxBound]] $ \(n, w, p) -> do
      f <- right (prescribedFixture n w p)
      baseline <- right (closedCreaseWithWidth n w BentTouching)
      m <- right (measureProbe f)
      let mesh = closedMesh f
          points = M.fromList [((materialU x, materialV x), position x) | x <- samples mesh]
      triangles mesh `shouldBe` triangles (closedMesh baseline)
      map sampleMaterial (samples mesh) `shouldBe` map sampleMaterial (samples (closedMesh baseline))
      componentCount mesh `shouldBe` 1
      length (triangles mesh) `shouldBe` 32 * n * w
      closedRoot f `shouldBe` closedRoot baseline
      probeCreaseError m `shouldSatisfy` (< 1e-12)
      forM_ (samples mesh) $ \x -> M.lookup (negate (materialU x), materialV x) points `shouldBe` Just (position x)

  it "samples identical cylindrical material points while fixed edges only approximate them" $ do
    coarse <- right (prescribedFixture 1 1 SampledCylinder)
    fine <- right (prescribedFixture 8 2 SampledCylinder)
    let points = M.fromList [((materialU p, materialV p), position p) | p <- samples (closedMesh fine)]
    forM_ (samples (closedMesh coarse)) $ \p -> M.lookup (materialU p, materialV p) points `shouldBe` Just (position p)
    forM_ probeMeshes $ \(n, w) -> do
      f <- right (prescribedFixture n w FixedEdges)
      m <- right (measureProbe f)
      probeRelativeError m `shouldSatisfy` (< 1e-12)
      let h = 1 / fromIntegral (8 * n)
          scale = (curvature * h / 2) / sin (curvature * h / 2)
      forM_ (samples (closedMesh f)) $ \p -> do
        let V3 x y z = cylinderPoint (abs (materialU p)) (materialV p)
        norm (position p ^-^ V3 (scale * x) y (scale * z)) `shouldSatisfy` (< 1e-14)

  it "has zero passive/length cost on flat paper and preserves band flat energy" $ do
    band <- right bandPreference
    forM_ probeMeshes $ \(n, w) -> do
      f <- right (prescribedFixture n w FlatPanels)
      m <- right (measureProbe f)
      near (probeLowerEnergy m) 0
      near (probeUpperEnergy m) 0
      near (probeLengthSquares m) 0
      near (probeControlEnergy m) (bandReferenceEnergy band)

  it "doubles fixed-corner passive cost per length doubling with no width dependence" $
    forM_ probeMeshes $ \(n, w) -> do
      f <- right (prescribedFixture n w FixedCorners)
      m <- right (measureProbe f)
      let angles = map ((2 *) . atan) [0, 0.1, 0.2, 0.3]
          turns = zipWith (-) (drop 1 angles) angles
          expected = 0.1 * fromIntegral (8 * n) * sum (map (\x -> x * x) turns)
      near (probeLowerEnergy m) expected
      near (probeUpperEnergy m) expected
      probeRelativeError m `shouldSatisfy` (< 1e-12)

  it "matches cylinder passive and clipped-band energies from interval formulas" $ do
    band <- right bandPreference
    forM_ [(n, w, p) | (n, w) <- probeMeshes, p <- [SampledCylinder, FixedEdges]] $ \(n, w, p) -> do
      f <- right (prescribedFixture n w p)
      m <- right (measureProbe f)
      let h = 1 / fromIntegral (8 * n)
          passive = 0.1 * curvature * curvature * (0.5 - h)
          (start, end) = bandBounds band
          intervals = [min end (fromIntegral i * h + h / 2) - max start (fromIntegral i * h - h / 2) | i <- [1 .. 4 * n - 1], fromIntegral i * h + h / 2 > start, fromIntegral i * h - h / 2 < end]
          imposed = sum [bandBendingWeight band / (2 * d) * (negate (curvature * h) - bandDesiredTurn band * d / (end - start)) ^ (2 :: Int) | d <- intervals]
      near (probeLowerEnergy m) passive
      near (probeUpperEnergy m) passive
      near (probeControlEnergy m) imposed

  it "measures cylinder chord shortening and counts the actual absolute-length residuals" $
    forM_ probeMeshes $ \(n, w) -> do
      f <- right (prescribedFixture n w SampledCylinder)
      m <- right (measureProbe f)
      let h = 1 / fromIntegral (8 * n)
          dy = 1 / fromIntegral (2 * w)
          chord = 2 * sin (curvature * h / 2) / curvature
          short = chord - h
          diagonalShort = sqrt (chord * chord + dy * dy) - sqrt (h * h + dy * dy)
          expected = fromIntegral (2 * (4 * n) * (2 * w + 1)) * short * short + fromIntegral (2 * (4 * n) * (2 * w)) * diagonalShort * diagonalShort
      near (probeRelativeError m) (1 - chord / h)
      abs (probeLengthSquares m - expected) `shouldSatisfy` (< max 1e-25 (expected * 1e-9))
      (probeRelativeError m <= 1e-5) `shouldBe` False

  it "accounts for the factor of two in the existing line-search objective" $
    forM_ [minBound .. maxBound] $ \p -> do
      f <- right (prescribedFixture 2 1 p)
      m <- right (measureProbe f)
      rows <- right (materialRows (closedHinges f) IM.empty 1e10 (closedMesh f))
      let halfEnergy = 1e10 * probeLengthSquares m / 2 + probeLowerEnergy m + probeUpperEnergy m + probeControlEnergy m + probeCreaseEnergy m
      abs (sum [r * r | (_, r) <- rows] - 2 * halfEnergy) `shouldSatisfy` (< 1e-10)

  it "passes exact touching-order checks without a repair and rejects unsupported meshes" $ do
    forM_ [minBound .. maxBound] $ \p -> do
      f <- right (prescribedFixture 2 2 p)
      gaps <- right (auditPairContact (closedOwners f) (closedMesh f))
      pairMinimum gaps `shouldBe` 0
      pairMaximum gaps `shouldBe` 0
    prescribedFixture 0 1 SampledCylinder `shouldSatisfy` isLeft
    prescribedFixture 8 0 FixedEdges `shouldSatisfy` isLeft
    prescribedFixture 9 1 FlatPanels `shouldSatisfy` isLeft

near :: Double -> Double -> Expectation
near actual expected = abs (actual - expected) `shouldSatisfy` (< 1e-11)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
