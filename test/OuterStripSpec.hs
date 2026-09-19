-- | Mesh and loading controls are tested analytically. Complete opt-in solves
-- remain outside CI; the existing solver suite covers the numerical policy.
module OuterStripSpec (spec) where

import BandBoundary
import BendLocations
import ClosedCrease
import Control.Monad (forM_)
import CoupledCrease
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import FoldBending
import FoldMaterial (componentCount)
import FoldRelaxation (maxLengthError)
import OuterStrip
import PrescribedBend
import Senbazuru.Origami.Surface
import Test.Hspec
import UnequalCrease

spec :: Spec
spec = describe "outer-strip refinement controls" $ do
  it "reproduces both original uniform fixtures exactly under both band rules" $
    forM_ [(mesh, n, rule, control) | (mesh, n) <- [(Coarse, 2), (Fine, 4)], rule <- [OriginalTurns, FractionalTurns], control <- [MatchedHolds, UpperBand, BandWithoutContact]] $ \(mesh, n, rule, control) -> do
      expected <- right (bandBoundaryFixture rule n 1 control)
      actual <- right (outerFixture mesh rule control)
      show actual `shouldBe` show expected

  it "changes only the selected columns and retains one isometric connected sheet" $ do
    fine <- right (outerFixture Fine OriginalTurns MatchedHolds)
    let points = M.fromList [((materialU p, materialV p), position p) | p <- samples (coupledSeed fine)]
    forM_ [(Coarse, 64), (OuterOnly, 72), (RestOnly, 120), (Fine, 128)] $ \(choice, count) -> do
      fixture <- right (outerFixture choice OriginalTurns MatchedHolds)
      let mesh = coupledSeed fixture
          pins = coupledPins fixture
      length (triangles mesh) `shouldBe` count
      componentCount mesh `shouldBe` 1
      maxLengthError mesh `shouldSatisfy` (< 1e-14)
      checkCoupledMaterial fixture mesh `shouldBe` Right ()
      closedRoot (coupledReference fixture) `shouldBe` [0, 1, 2]
      forM_ (zip [0 ..] (samples mesh)) $ \(i, p) -> do
        M.lookup (materialU p, materialV p) points `shouldBe` Just (position p)
        IM.member i pins `shouldBe` (abs (materialU p) <= 1 / 8 || abs (materialU p) == 1 / 2)
    filter (/= 15 / 32) (outerColumns OuterOnly) `shouldBe` outerColumns Coarse
    filter (/= 15 / 32) (outerColumns Fine) `shouldBe` outerColumns RestOnly

  it "keeps on/off fixtures identical and preserves band extent, turn and flat energy" $
    forM_ [(choice, rule) | choice <- [minBound .. maxBound], rule <- [OriginalTurns, FractionalTurns]] $ \(choice, rule) -> do
      on <- right (outerFixture choice rule UpperBand)
      off <- right (outerFixture choice rule BandWithoutContact)
      show on `shouldBe` show off
      preference <- right bandPreference
      rows <- right (outerBoundaryMeasures choice (coupledReference on))
      let width r = snd (boundaryWidthRange r) - fst (boundaryWidthRange r)
          flatEnergy h = hingeStiffness h * hingeRest h ^ (2 :: Int) / 2
          spring r = if rule == OriginalTurns then boundaryOriginal r else boundaryCandidate r
          fraction r = if rule == OriginalTurns then 1 else boundaryFraction r
      near (sum [width r * (snd (boundaryInterval r) - fst (boundaryInterval r)) | r <- rows]) (5 / 16)
      near (sum [width r * fraction r * hingeRest (spring r) | r <- rows]) (bandDesiredTurn preference)
      near (sum [flatEnergy (spring r) | r <- rows]) (bandReferenceEnergy preference)
      all (\r -> fst (boundaryInterval r) >= 1 / 8 && snd (boundaryInterval r) <= 7 / 16) rows `shouldBe` True

  it "records unequal end supports without putting load outside the band" $ do
    outerInterval OuterOnly (7 / 16) `shouldBe` Just ((13 / 32, 29 / 64), (13 / 32, 7 / 16))
    outerInterval RestOnly (7 / 16) `shouldBe` Just ((27 / 64, 15 / 32), (27 / 64, 7 / 16))
    forM_ [minBound .. maxBound] $ \choice -> do
      outerInterval choice (15 / 32) `shouldBe` Nothing
      fixture <- right (outerFixture choice FractionalTurns UpperBand)
      rows <- right (outerBoundaryMeasures choice (coupledReference fixture))
      let expected = case choice of Coarse -> 1 / 2; OuterOnly -> 2 / 3; RestOnly -> 1 / 3; Fine -> 1 / 2
      forM_ [r | r <- rows, boundaryDistance r == 7 / 16] $ \r -> near (boundaryFraction r) expected

  it "recovers cylinder rates and fractional energy on the two nonuniform grids" $ do
    preference <- right bandPreference
    let expected = bandBendingWeight preference * (5 / 16) / 2 * (negate curvature - bandDesiredTurn preference / (5 / 16)) ^ (2 :: Int)
    forM_ [OuterOnly, RestOnly] $ \choice -> do
      fixture <- right (outerFixture choice FractionalTurns UpperBand)
      let reference = coupledReference fixture
          mesh = closedMesh reference
          curved = reference {closedMesh = mesh {samples = [p {position = cylinderPoint (abs (materialU p)) (materialV p)} | p <- samples mesh]}}
      rows <- right (outerBoundaryMeasures choice curved)
      near (sum (map boundaryNewEnergy rows)) expected
      located <- right (locateBends curved)
      forM_ [h | h <- located, hingeRole (measuredHinge (locatedMeasure h)) == PanelBend, Just _ <- [locatedRate h]] $ \h -> case locatedRate h of
        Just rate -> near (abs rate) curvature
        Nothing -> expectationFailure "transverse bend lost its angular rate"

  it "refuses unrelated controls and mismatched band supports" $ do
    forM_ [0 / 0, 1 / 0, negate (1 / 0)] $ \x -> outerInterval OuterOnly x `shouldBe` Nothing
    outerFixture OuterOnly OriginalTurns OpenUpperGrip `shouldSatisfy` isLeft
    fixture <- right (outerFixture Coarse OriginalTurns UpperBand)
    outerBoundaryMeasures Fine (coupledReference fixture) `shouldSatisfy` isLeft

near :: Double -> Double -> Expectation
near a b = abs (a - b) `shouldSatisfy` (< 1e-11)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
