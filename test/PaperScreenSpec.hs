-- | The paper screen's measures, and its verdict, on small inputs whose
-- answers can be worked out by hand. Each example names the mistake it would
-- catch.
module PaperScreenSpec (spec) where

import CylinderStrip (Diagonal (..), placedStrip, stripJoins)
import Data.Either (isLeft, isRight)
import PaperScreen
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..))
import Test.Hspec
import WholeCraneScreen (Screen (..), Verdict (..), pixelsPerSheet, screenVerdict, verdictPasses)

spec :: Spec
spec = describe "the paper screen" $ do
  it "halves the excess of the pair furthest apart" $ do
    -- Material distance 1, placed 1.2: the pair can share 0.2, so one of the
    -- two points moves at least 0.1. Dropping the halving gives 0.2.
    noStretchFloor 0 [(V2 0 0, V3 0 0 0), (V2 1 0, V3 1.2 0 0)]
      `shouldBe` Just (FloorPair ((1.2 - 1) / 2) (0, 1))

  it "lets the declared strain absorb its share of the excess" $ do
    -- At 1% the pair may be 1.01 apart, so only 0.19 remains to share.
    fmap floorDistance (noStretchFloor 0.01 [(V2 0 0, V3 0 0 0), (V2 1 0, V3 1.2 0 0)])
      `shouldSatisfy` maybe False (\d -> abs (d - (1.2 - 1.01) / 2) < 1e-12)

  it "reports how much room is left when no pair is too far apart" $
    -- A negative floor: every pair is closer than the flat sheet allows.
    fmap floorDistance (noStretchFloor 0 [(V2 0 0, V3 0 0 0), (V2 1 0, V3 0.5 0 0)])
      `shouldBe` Just (-0.25)

  it "accepts a square sheet and refuses one with a notch" $ do
    sheetIsConvex square `shouldSatisfy` isRight
    -- An L: its hull is larger than the paper, so a chord can leave it.
    sheetIsConvex ell `shouldSatisfy` isLeft

  it "refuses a sheet with a slit, which has the area of an uncut one" $
    -- The two sides of the slit could be pulled apart without stretching, so
    -- a floor would be set by a pair whose flat distance is 0. The area test
    -- alone passes this sheet.
    sheetIsConvex slit `shouldBe` Left (RepeatedMaterialPoint 1 2)

  it "takes the smaller reach, so a card resting on a table is barely in it" $ do
    -- The table is huge and flat; the card stands on it with one corner
    -- 0.001 below the top. Taking the larger reach would give the table's
    -- extent past the card's plane, 5.
    let table = (V3 (-5) (-5) 0, V3 5 (-5) 0, V3 0 5 0)
        card = (V3 (-1) 0 (-0.001), V3 1 0 1, V3 (-1) 0 1)
    fmap (\d -> abs (d - 0.001) < 1e-12) (reachThrough card table) `shouldBe` Just True
    fmap (\d -> abs (d - 0.001) < 1e-12) (reachThrough table card) `shouldBe` Just True

  it "gives no reach for a pair on one side of each other's plane" $
    reachThrough (V3 0 0 1, V3 1 0 1, V3 0 1 1) (V3 0 0 0, V3 1 0 0, V3 0 1 0) `shouldBe` Just 0

  it "sums length times angle over joins past the threshold, either way bent" $ do
    -- 0.1 x 50 + 0.1 x 60 = 11 over two joins. Counting every join gives 3;
    -- dropping the absolute value loses the join bent -60.
    let turning = falseCreaseTurning 45 [(0.1, 50), (0.2, 30), (0.1, -60)]
    turningJoins turning `shouldBe` 2
    abs (turningTotal turning - 11) `shouldSatisfy` (< 1e-12)

  it "splits centre creases into midlines and diagonals and takes each median" $ do
    -- Midlines bent 170, 100 and 60 either way: the median is 100, where the
    -- mean would be 110 and a median of the signed angles 60. Diagonals bent
    -- 20 and 40: the median of an even count is 30, or -10 signed.
    let centre = V2 0.5 0.5
        segments =
          [ (V2 0.5 0.5, V2 0.5 0.75, 170),
            (V2 0.5 0.25, V2 0.5 0.5, -100),
            (V2 0.25 0.5, V2 0.5 0.5, 60),
            (V2 0.5 0.5, V2 0.75 0.75, 20),
            (V2 0.25 0.25, V2 0.5 0.5, -40),
            -- Not through the centre: ignored.
            (V2 0.1 0.2, V2 0.2 0.1, 180)
          ]
    centreFolds centre segments `shouldBe` (Just 100, Just 30)

  -- PRD 11's A-11-2, the curve half. Research note Y3's strip, one sheet
  -- side by a quarter, bent through 270 degrees about generators at 45
  -- degrees and placed exactly on its cylinder: a curve, which a mesh can
  -- only sample.
  describe "false-crease turning on a curve" $ do
    it "falls to nothing under one refinement, cells cut across the bend" $ do
      -- The coarse joins bend up to 37 degrees and the fine ones 19. Summed
      -- with no threshold, the fine joins still come to about 204, so a
      -- measure that dropped its threshold turns this red.
      coarse <- joinsOf 8 AcrossBend
      fine <- joinsOf 16 AcrossBend
      turningJoins (falseCreaseTurning 20 coarse) `shouldSatisfy` (> 0)
      falseCreaseTurning 20 fine `shouldBe` Turning 0 0
      turningTotal (falseCreaseTurning 0 fine) `shouldSatisfy` (> 100)

    it "keeps its whole turning at every resolution, cells cut along the bend" $ do
      -- Summed over every join, a curve turns as far however finely it is
      -- sampled: why the measure needs its threshold.
      totals <- mapM (\n -> turningTotal . falseCreaseTurning 0 <$> joinsOf n AlongBend) [8, 16, 32]
      totals `shouldSatisfy` \ts -> maximum ts - minimum ts < 1e-9 && minimum ts > 70

  describe "the verdict" $ do
    it "judges the floor at the declared strain, not at none" $ do
      -- 1.2 px at no strain, 0.8 px at the 1% screen: the 1 px target applies
      -- to the second. The three crossings are reported, not judged.
      let verdict = screenVerdict (screenWith 0 0)
      verdictFloor verdict `shouldBe` True
      verdictPasses verdict `shouldBe` True

    it "fails a pose squashed past the screen, not only one stretched" $ do
      let verdict = screenVerdict (screenWith 0.02 0)
      verdictStrain verdict `shouldBe` False
      verdictPasses verdict `shouldBe` False

    it "fails false creases found one level finer, where the pose's own mesh has none" $
      verdictFalseCreases (screenVerdict (screenWith 0 0) {screenTurningFiner = Just (Turning 2 91)}) `shouldBe` False

    it "reports the 0.1% screen without requiring it" $ do
      let verdict = screenVerdict (screenWith 0.005 0.005)
      (verdictStrain verdict, verdictStrictStrain verdict) `shouldBe` (True, False)
      verdictPasses verdict `shouldBe` True

-- | Every join of research note Y3's strip at @n@ cells, as length and bend.
joinsOf :: Int -> Diagonal -> IO [(Double, Double)]
joinsOf n diagonal = either (fail . show) pure (stripJoins (placedStrip n diagonal (3 * pi / 2)))

-- | A pose whose floor is within 1 px only at the declared strain, with
-- three crossings and no false creases, squashed and stretched as given.
screenWith :: Double -> Double -> Screen
screenWith squash stretch =
  Screen
    { screenSquash = squash,
      screenStretch = stretch,
      screenFloor = Just (FloorPair (1.2 / pixelsPerSheet) (0, 1)),
      screenFloorAtScreen = Just (FloorPair (0.8 / pixelsPerSheet) (0, 1)),
      screenCrossings = 3,
      screenDeepestReach = Nothing,
      screenTurning = Turning 0 0,
      screenTurningFiner = Nothing,
      screenCoreLength = Nothing,
      screenCentreFolds = (Nothing, Nothing)
    }

sheet :: [(Double, Double)] -> [(Int, Int, Int)] -> MaterialMesh
sheet points = Mesh [Sample (V2 u v) (V3 u v 0) | (u, v) <- points]

square :: MaterialMesh
square = sheet [(0, 0), (1, 0), (1, 1), (0, 1)] [(0, 1, 2), (0, 2, 3)]

ell :: MaterialMesh
ell = sheet [(0, 0), (2, 0), (2, 1), (1, 1), (1, 2), (0, 2)] [(0, 1, 2), (0, 2, 3), (0, 3, 5), (3, 4, 5)]

-- | A unit square cut from the middle of its bottom edge to its centre:
-- vertices 1 and 2 are the two sides of the cut, at one point of the sheet.
slit :: MaterialMesh
slit = sheet [(0, 0), (0.5, 0), (0.5, 0), (1, 0), (1, 1), (0, 1), (0.5, 0.5)] [(0, 1, 6), (0, 6, 5), (2, 3, 6), (3, 4, 6), (6, 4, 5)]
