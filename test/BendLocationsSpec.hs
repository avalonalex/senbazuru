-- | Analytic profiles and bookkeeping checks without equilibrium solves.
module BendLocationsSpec (spec) where

import BandBoundary
import BendLocations
import ClosedCrease
import Control.Monad (forM_)
import CoupledCrease
import Data.Either (isLeft)
import Data.Maybe (isNothing)
import FoldBending
import PrescribedBend
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface
import Test.Hspec
import UnequalCrease

spec :: Spec
spec = describe "bending locations on saved paper" $ do
  it "accounts for every spring once and reconciles regions and cumulative totals" $
    forM_ [(n, rule, c) | n <- [2, 4], rule <- [OriginalTurns, FractionalTurns], c <- [MatchedHolds, UpperBand, BandWithoutContact]] $ \(n, rule, c) -> do
      fixture <- right (bandBoundaryFixture rule n 1 c)
      let reference = coupledReference fixture
      rows <- right (locateBends reference)
      map (measuredHinge . locatedMeasure) rows `shouldBe` closedHinges reference
      forM_ [False, True] $ \upper -> forM_ [PanelBend, BendControl] $ \role -> do
        let selected = filter (\h -> measuredUpper (locatedMeasure h) == upper && hingeRole (measuredHinge (locatedMeasure h)) == role) rows
            total = sum (map (measuredEnergy . locatedMeasure) selected)
        near (sum (map snd (regionEnergy selected))) total
        reverse (cumulativeEnergy selected) `shouldSatisfy` (\case V2 0.5 y : _ -> abs (y - total) < 1e-12; _ -> False)

  it "recovers the same cylindrical angular rate under length and width refinement" $
    forM_ [(n, w) | n <- [2, 4], w <- [1, 2]] $ \(n, w) -> do
      fixture <- right (prescribedFixture n w FixedEdges)
      rows <- right (locateBends fixture)
      forM_ [False, True] $ \upper -> do
        let passive = [h | h <- rows, measuredUpper (locatedMeasure h) == upper, hingeRole (measuredHinge (locatedMeasure h)) == PanelBend]
        length (transverseRates passive) `shouldBe` (4 * n - 1)
        forM_ (transverseRates passive) $ \(_, mean, lo, hi) -> do
          near (abs mean) curvature
          near lo hi

  it "separates both exact band lines and preserves flat-energy normalization" $
    forM_ [2, 4] $ \n -> do
      fixture <- right (prescribedFixture n 1 FlatPanels)
      preference <- right bandPreference
      rows <- right (locateBends fixture)
      let imposed = [h | h <- rows, hingeRole (measuredHinge (locatedMeasure h)) == BendControl]
          costs = regionEnergy imposed
      near (sum (map snd costs)) (bandReferenceEnergy preference)
      near (sum [e | (r, e) <- costs, r `elem` [HeldBoundary, BandEnd]]) (bandReferenceEnergy preference * 0.4 / fromIntegral n)
      forM_ [h | h <- rows, hingeRole (measuredHinge (locatedMeasure h)) == PanelBend] $ \h -> near (measuredEnergy (locatedMeasure h)) 0

  it "retains non-transverse energy when a panel varies across its width" $ do
    fixture <- right (prescribedFixture 2 1 FixedEdges)
    let mesh = closedMesh fixture
        shifted p = if materialU p == 0.25 && materialV p == 0 then p {position = let V3 x y z = position p in V3 x y (z + 0.002)} else p
    rows <- right (locateBends fixture {closedMesh = mesh {samples = map shifted (samples mesh)}})
    let other = [h | h <- rows, isNothing (locatedRate h), hingeRole (measuredHinge (locatedMeasure h)) == PanelBend]
    sum (map (measuredEnergy . locatedMeasure) other) `shouldSatisfy` (> 1e-6)
    near (sum (map snd (regionEnergy other))) (sum (map (measuredEnergy . locatedMeasure) other))

  it "reloads an identical sheet and refuses changed holds, winding and orders" $ do
    fixture <- right (bandBoundaryFixture FractionalTurns 2 1 UpperBand)
    let mesh = coupledSeed fixture
    fr <- materialFrame <$> right (coupledSurface fixture mesh)
    savedBendMesh fixture fr `shouldBe` Right mesh
    savedBendMesh fixture fr {faceOrders = []} `shouldSatisfy` isLeft
    savedBendMesh fixture fr {facesVertices = map reverse (facesVertices fr)} `shouldSatisfy` isLeft
    let moved = mesh {samples = [if materialU p == 0 then p {position = V3 0 (materialV p) 0.01} else p | p <- samples mesh]}
    -- Export from the reference surface avoids changing fixture holds to
    -- manufacture a supposedly valid input for the reader.
    sheet <- right (closedSurface (coupledReference fixture) {closedMesh = moved})
    savedBendMesh fixture (materialFrame sheet) `shouldSatisfy` isLeft

near :: Double -> Double -> Expectation
near a b = abs (a - b) `shouldSatisfy` (< 1e-11)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
