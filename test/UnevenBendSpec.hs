-- | Prescribed references checked against interval integrals, chord lengths
-- and explicit known costs, independently of triangle-normal measurements.
module UnevenBendSpec (spec) where

import BandBoundary (BoundaryRule (..))
import BendLocations
import ClosedCrease
import Control.Monad (forM_, when)
import CoupledCrease
import CreaseInequality (materialRows)
import CreasePairContact
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import FoldBending
import FoldMaterial (componentCount)
import OuterStrip
import PrescribedBend
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Test.Hspec
import UnequalCrease (UnequalControl (..))
import UnevenBend

cases :: [(OuterMesh, ReferenceBend, BendConstruction)]
cases = [(m, r, c) | m <- [minBound .. maxBound], r <- [minBound .. maxBound], c <- [minBound .. maxBound]]

spec :: Spec
spec = describe "prescribed uneven bends" $ do
  it "retains the original material, springs and shared crease, with both layers touching" $
    forM_ cases $ \(m, r, c) -> do
      f <- right (unevenFixture m r c)
      baseline <- coupledReference <$> right (outerFixture m OriginalTurns MatchedHolds)
      measured <- right (measureProbe f)
      let mesh = closedMesh f
          points = M.fromList [((materialU p, materialV p), position p) | p <- samples mesh]
      triangles mesh `shouldBe` triangles (closedMesh baseline)
      map sampleMaterial (samples mesh) `shouldBe` map sampleMaterial (samples (closedMesh baseline))
      closedOwners f `shouldBe` closedOwners baseline
      closedHinges f `shouldBe` closedHinges baseline
      closedRoot f `shouldBe` [0, 1, 2]
      componentCount mesh `shouldBe` 1
      probeCreaseError measured `shouldSatisfy` (< 1e-12)
      probeControlEnergy measured `shouldBe` 0
      forM_ (samples mesh) $ \p -> M.lookup (negate (materialU p), materialV p) points `shouldBe` Just (position p)
      when (r == AfterHeldStrip) $
        forM_ [p | p <- samples mesh, abs (materialU p) <= 1 / 8] $
          \p -> position p `shouldBe` V3 (abs (materialU p)) (materialV p) 0

  it "keeps sampled material points identical across meshes, unlike full-length segments" $
    forM_ [(a, b, r) | (a, b) <- outerPairs, r <- [minBound .. maxBound]] $ \(a, b, r) -> do
      fa <- right (unevenFixture a r SurfaceSamples)
      fb <- right (unevenFixture b r SurfaceSamples)
      right (matching (closedMesh fa) (closedMesh fb)) `shouldReturn` 0
      ga <- right (unevenFixture a r FullSegments)
      gb <- right (unevenFixture b r FullSegments)
      difference <- right (matching (closedMesh ga) (closedMesh gb))
      difference `shouldSatisfy` (> 1e-8)

  it "agrees with the existing uniform full-edge cylinder when all strips have equal width" $
    forM_ [(Coarse, 2), (Fine, 4)] $ \(m, n) -> do
      f <- right (unevenFixture m CylinderBend FullSegments)
      g <- right (prescribedFixture n 1 FixedEdges)
      difference <- right (matching (closedMesh f) (closedMesh g))
      difference `shouldSatisfy` (< 1e-14)

  it "matches independent closed-form costs on both panels with either construction" $
    forM_ [(m, cylinder, held, c) | (m, cylinder, held) <- [(Coarse, 0.063, 0.04725), (OuterOnly, 0.06525, 0.0495), (RestOnly, 0.06525, 0.048375), (Fine, 0.0675, 0.050625)], c <- [minBound .. maxBound]] $ \(m, cylinder, held, c) ->
      forM_ [(CylinderBend, cylinder), (AfterHeldStrip, held)] $ \(r, expected) -> do
        measured <- right (unevenFixture m r c >>= measureProbe)
        near (probeLowerEnergy measured) expected
        near (probeUpperEnergy measured) expected

  it "accounts separately for missing boundary strips and averaging at the bend start" $
    forM_ cases $ \(m, r, c) -> do
      f <- right (unevenFixture m r c)
      located <- right (locateBends f)
      let supports = bendSupports m r
          missed = referenceEnergy r - sum (map supportIntegral supports)
          averaged = sum [supportIntegral s - supportEnergy s | s <- supports]
          endWidth = if m `elem` [Coarse, RestOnly] then 1 / 16 else 1 / 32
          startWidth = if m `elem` [Coarse, OuterOnly] then 1 / 16 else 1 / 32
      near missed (0.1 * curvature * curvature * (endWidth + if r == CylinderBend then startWidth else 0) / 2)
      if r == CylinderBend then near averaged 0 else averaged `shouldSatisfy` (> 0)
      forM_ supports $ \s -> do
        let rows = [h | h <- located, locatedDistance h == supportDistance s, hingeRole (measuredHinge (locatedMeasure h)) == PanelBend, Just _ <- [locatedRate h]]
        length rows `shouldBe` 4
        forM_ rows $ \h -> near (abs (measuredAngle (locatedMeasure h))) (supportTurn s)
        near (sum [measuredEnergy (locatedMeasure h) | h <- rows]) (2 * supportEnergy s)
        if supportDistance s == 1 / 8 && r == AfterHeldStrip
          then supportIntegral s `shouldSatisfy` (> supportEnergy s)
          else near (supportIntegral s) (supportEnergy s)
      near (referenceEnergy r - missed - averaged) (sum (map supportEnergy supports))

  it "counts chord shortening on sampled references and preserves lengths with full segments" $
    forM_ cases $ \(m, r, c) -> do
      f <- right (unevenFixture m r c)
      measured <- right (measureProbe f)
      let expected = predictedLengthSquares m r c
      abs (probeLengthSquares measured - expected) `shouldSatisfy` (< max 1e-25 (expected * 1e-9))
      case c of
        SurfaceSamples -> probeRelativeError measured `shouldSatisfy` (> 1e-5)
        FullSegments -> probeRelativeError measured `shouldSatisfy` (< 1e-12)
      rows <- right (materialRows (closedHinges f) IM.empty 1e10 (closedMesh f))
      let objective = 1e10 * probeLengthSquares measured + 2 * (probeLowerEnergy measured + probeUpperEnergy measured + probeControlEnergy measured + probeCreaseEnergy measured)
      near (sum [v * v | (_, v) <- rows]) objective

  it "checks exact touching order on all sixteen references without contact correction" $
    forM_ cases $ \(m, r, c) -> do
      f <- right (unevenFixture m r c)
      gaps <- right (auditPairContact (closedOwners f) (closedMesh f))
      pairMinimum gaps `shouldBe` 0
      pairMaximum gaps `shouldBe` 0

near :: Double -> Double -> Expectation
near actual expected = abs (actual - expected) `shouldSatisfy` (< 1e-11)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure

matching :: MaterialMesh -> MaterialMesh -> Either String Double
matching a b = maximum . (0 :) <$> traverse distance (samples a)
  where
    points = M.fromList [((materialU p, materialV p), position p) | p <- samples b]
    distance p = case M.lookup (materialU p, materialV p) points of
      Nothing -> Left "reference lost a matching material vertex"
      Just q -> Right (norm (position p ^-^ q))
