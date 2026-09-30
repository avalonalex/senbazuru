-- | The paper screen's measures, and its verdict, on small inputs whose
-- answers can be worked out by hand. Each example names the mistake it would
-- catch.
module PaperScreenSpec (spec) where

import Control.Monad (forM_)
import CylinderStrip (Diagonal (..), placedStrip, stripJoins)
import Data.Maybe (isNothing)
import Data.Set qualified as S
import PaperScreen
import ScreenReport (Judgement (..), Screen (..), Verdict (..), pixelsPerSheet, screenVerdict, verdictOverall)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..))
import Test.Hspec

spec :: Spec
spec = describe "the paper screen" $ do
  it "halves the excess of the pair furthest apart" $ do
    -- Material distance 1, placed 1.2: the pair can share 0.2, so one of the
    -- two points moves at least 0.1. Dropping the halving gives 0.2.
    noStretchFloor EveryChord 0 [(V2 0 0, V3 0 0 0), (V2 1 0, V3 1.2 0 0)]
      `shouldBe` Just (FloorPair ((1.2 - 1) / 2) (0, 1))

  it "lets the declared strain absorb its share of the excess" $ do
    -- At 1% the pair may be 1.01 apart, so only 0.19 remains to share.
    fmap floorDistance (noStretchFloor EveryChord 0.01 [(V2 0 0, V3 0 0 0), (V2 1 0, V3 1.2 0 0)])
      `shouldSatisfy` maybe False (\d -> abs (d - (1.2 - 1.01) / 2) < 1e-12)

  it "reports how much room is left when no pair is too far apart" $
    -- A negative floor: every pair is closer than the flat sheet allows.
    fmap floorDistance (noStretchFloor EveryChord 0 [(V2 0 0, V3 0 0 0), (V2 1 0, V3 0.5 0 0)])
      `shouldBe` Just (-0.25)

  it "takes every chord of a square, and only the chords of an L that stay on it" $ do
    sheetChords square `shouldBe` Right EveryChord
    -- The L's arm ends, vertices 2 and 4: their chord runs through the notch
    -- and meets the paper only at its ends, so only its midpoint shows it is
    -- off the paper. The chord from 1 to 4 crosses the notch's lower edge,
    -- which only the crossing test sees. The chord from 1 to 5 stays on the
    -- paper but passes through the inside corner, 3, and is left out, which
    -- only the corner test does. Dropping any one test keeps one of them.
    case sheetChords ell of
      Right (ChordsOnSheet kept) -> do
        map (`S.member` kept) [(2, 4), (1, 4), (1, 5)] `shouldBe` [False, False, False]
        -- Inside, along an inner edge, and along the paper's own edge.
        map (`S.member` kept) [(0, 4), (0, 3), (2, 3)] `shouldBe` [True, True, True]
      other -> expectationFailure ("expected the L's chords, found " <> show other)

  it "measures the paper of a folded L round its notch, not across it" $ do
    -- Three unit squares in an L, one arm folded a quarter turn up and the
    -- other a quarter turn down: paper, since nothing stretched. The arm
    -- tips, vertices 5 and 7, end 2 apart, while the chord between them on
    -- the flat sheet is sqrt 2 long, so a floor over every pair would say
    -- some point must move (2 - sqrt 2) / 2. That chord crosses the notch;
    -- along the paper the tips are 2 apart, and nothing need move.
    chords <- either (fail . show) pure (sheetChords (sheet (map fst foldedEll) ellSquares))
    fmap floorDistance (noStretchFloor chords 0 placedEll) `shouldBe` Just 0
    let everyPair = noStretchFloor EveryChord 0 placedEll
    fmap floorVertices everyPair `shouldBe` Just (5, 7)
    fmap floorDistance everyPair `shouldSatisfy` maybe False (\d -> abs (d - (2 - sqrt 2) / 2) < 1e-12)

  it "refuses a sheet with a slit, which has the area of an uncut one" $
    -- A chord from where the slit opens cannot tell which side of the cut it
    -- leaves by, and the two sides could be pulled apart without stretching.
    -- The area test alone passes this sheet.
    sheetChords slit `shouldBe` Left (RepeatedMaterialPoint 1 2)

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
    it "falls to nothing past 20 degrees under one refinement, cells cut across the bend" $ do
      -- The coarse joins bend up to 37 degrees and the fine ones 19. The
      -- threshold is A-11-2's for this strip, not the screen's 45: placed
      -- exactly, the strip never bends a join that far. Summed with no
      -- threshold, the fine joins still come to about 204, so a measure that
      -- dropped its threshold turns this red.
      coarse <- joinsOf 8 AcrossBend
      fine <- joinsOf 16 AcrossBend
      turningJoins (falseCreaseTurning 20 coarse) `shouldSatisfy` (> 0)
      falseCreaseTurning 20 fine `shouldBe` Turning 0 0
      turningTotal (falseCreaseTurning 0 fine) `shouldSatisfy` (> 100)

    it "sums to the strip's area over the radius at any resolution, cells cut along the bend" $ do
      -- Cut along the bend, every diagonal lies on a straight line of the
      -- cylinder, and the triangles either side of every other edge lie flat
      -- together, so the diagonals carry the whole bend: the strip's area
      -- over the cylinder's radius, however fine the cells. Summed with no
      -- threshold, a curve never fades, which is why the measure has one.
      -- Ten cells along make a strip a fifth wide, not a quarter, so a
      -- placement that took every strip for Y3's would bend it too little and
      -- turn this red.
      forM_ [8, 10, 16, 32] $ \n -> do
        total <- turningTotal . falseCreaseTurning 0 <$> joinsOf n AlongBend
        total `shouldSatisfy` \t -> abs (t - areaOverRadius n) < 1e-9

    it "refuses a strip with no cells across, or no turn" $ do
      isNothing (placedStrip 3 AlongBend (3 * pi / 2)) `shouldBe` True
      isNothing (placedStrip 8 AlongBend 0) `shouldBe` True

  describe "the verdict" $ do
    it "judges the floor at the declared strain, not at none" $ do
      -- 1.2 px at no strain, 0.8 px at the 1% screen: the 1 px target applies
      -- to the second. The three crossings are reported, not judged.
      let verdict = screenVerdict (screenWith 0 0)
      verdictFloor verdict `shouldBe` True
      verdictOverall verdict `shouldBe` Passes

    it "fails a pose squashed past the screen, not only one stretched" $ do
      let verdict = screenVerdict (screenWith 0.02 0)
      verdictStrain verdict `shouldBe` False
      verdictOverall verdict `shouldBe` Fails

    it "fails false creases found one level finer, where the pose's own mesh has none" $
      verdictFalseCreases (screenVerdict (screenWith 0 0) {screenTurningFiner = Just (Turning 2 91)}) `shouldBe` Fails

    it "neither passes nor fails false creases on a pose not made again one level finer" $ do
      -- Owner decision 27: half of the test was never run, so the pose has
      -- not passed it, and failing it would fail every solved pose for a
      -- reason that is not about the pose.
      let verdict = screenVerdict (screenWith 0 0) {screenTurningFiner = Nothing}
      verdictFalseCreases verdict `shouldBe` NotMeasured
      verdictOverall verdict `shouldBe` NotMeasured

    it "fails false creases on the pose's own mesh, whatever the finer level" $ do
      -- A level not measured must not hide a failure on the one that was.
      let verdict = screenVerdict (screenWith 0 0) {screenTurning = Turning 1 50, screenTurningFiner = Nothing}
      verdictFalseCreases verdict `shouldBe` Fails
      verdictOverall verdict `shouldBe` Fails

    it "fails a pose that fails a required part, whatever was not measured" $
      verdictOverall (screenVerdict (screenWith 0.02 0) {screenTurningFiner = Nothing}) `shouldBe` Fails

    it "reports the 0.1% screen without requiring it" $ do
      let verdict = screenVerdict (screenWith 0.005 0.005)
      (verdictStrain verdict, verdictStrictStrain verdict) `shouldBe` (True, False)
      verdictOverall verdict `shouldBe` Passes

-- | Every join of research note Y3's strip at @n@ cells, bent through 270
-- degrees, as length and bend.
joinsOf :: Int -> Diagonal -> IO [(Double, Double)]
joinsOf n diagonal = case placedStrip n diagonal (3 * pi / 2) of
  Nothing -> fail ("no strip at " <> show n <> " cells")
  Just strip -> either (fail . show) pure (stripJoins strip)

-- | What the joins of the strip at @n@ cells, cut along the bend, sum to in
-- sheet sides times degrees: its area over the radius of its cylinder. The
-- strip is one sheet side long and @(n \`div\` 4) / n@ wide. Across the
-- generators, at 45 degrees, it spans its length plus its width over √2,
-- and the cylinder turns that span through 270 degrees.
areaOverRadius :: Int -> Double
areaOverRadius n = width / radius * 180 / pi
  where
    width = fromIntegral (n `div` 4) / fromIntegral n
    radius = ((1 + width) / sqrt 2) / (3 * pi / 2)

-- | A pose whose floor is within 1 px only at the declared strain, with
-- three crossings and no false creases at either level, squashed and
-- stretched as given.
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
      screenTurningFiner = Just (Turning 0 0),
      screenCoreLength = Nothing,
      screenCentreFolds = (Nothing, Nothing)
    }

sheet :: [(Double, Double)] -> [(Int, Int, Int)] -> MaterialMesh
sheet points = Mesh [Sample (V2 u v) (V3 u v 0) | (u, v) <- points]

square :: MaterialMesh
square = sheet [(0, 0), (1, 0), (1, 1), (0, 1)] [(0, 1, 2), (0, 2, 3)]

ell :: MaterialMesh
ell = sheet [(0, 0), (2, 0), (2, 1), (1, 1), (1, 2), (0, 2)] [(0, 1, 2), (0, 2, 3), (0, 3, 5), (3, 4, 5)]

-- | Three unit squares in an L, the notch at the top right, as triangles of
-- 'foldedEll''s vertices.
ellSquares :: [(Int, Int, Int)]
ellSquares = [(0, 1, 4), (0, 4, 3), (1, 2, 5), (1, 5, 4), (3, 4, 7), (3, 7, 6)]

-- | The L's vertices on the flat sheet and in a pose that folds its right
-- arm a quarter turn down along x = 1 and its upper arm a quarter turn up
-- along y = 1.
foldedEll :: [((Double, Double), V3)]
foldedEll =
  [ ((0, 0), V3 0 0 0),
    ((1, 0), V3 1 0 0),
    ((2, 0), V3 1 0 (-1)),
    ((0, 1), V3 0 1 0),
    ((1, 1), V3 1 1 0),
    ((2, 1), V3 1 1 (-1)),
    ((0, 2), V3 0 1 1),
    ((1, 2), V3 1 1 1)
  ]

-- | 'foldedEll' as the floor reads it.
placedEll :: [(V2, V3)]
placedEll = [(V2 u v, x) | ((u, v), x) <- foldedEll]

-- | A unit square cut from the middle of its bottom edge to its centre:
-- vertices 1 and 2 are the two sides of the cut, at one point of the sheet.
slit :: MaterialMesh
slit = sheet [(0, 0), (0.5, 0), (0.5, 0), (1, 0), (1, 1), (0, 1), (0.5, 0.5)] [(0, 1, 6), (0, 6, 5), (2, 3, 6), (3, 4, 6), (6, 4, 5)]
