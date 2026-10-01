-- | The paper screen's measures, and its verdict, on small inputs whose
-- answers can be worked out by hand. Each example names the mistake it would
-- catch.
module PaperScreenSpec (spec) where

import Control.Monad (forM_)
import CylinderStrip (Diagonal (..), placedStrip, stripJoins)
import Data.Aeson (Value (..), object)
import Data.Aeson.Key (Key)
import Data.Aeson.KeyMap qualified as KM
import Data.List.NonEmpty (NonEmpty (..))
import Data.Maybe (isNothing)
import Data.Set qualified as S
import PaperScreen
import ScreenReport (Figure (..), Judgement (..), PageScale (..), Screen (..), Verdict (..), figure, floorPixels, pageScale, pictureFloorJson, poseScreenKeys, screenJson, screenOf, screenVerdict, thresholdsJson, verdictOverall)
import Senbazuru.Diagram (Colour (..), Shape (..), diagramWithExtent, solid)
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Contact (ContactCheck (..))
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..))
import Senbazuru.Render.Camera (topDown)
import Senbazuru.Render.Svg (Page (..), defaultPage)
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

  it "takes every chord of a square, and only the chords of a U that stay on it" $ do
    sheetChords square `shouldBe` Right EveryChord
    -- The U's notch has walls x = 1 and x = 2 and floor y = 1, and is open at
    -- the top; vertex i is at (i mod 4, i div 4). The chord from 9 to 10
    -- spans the notch's mouth and meets the paper only at its ends, so only
    -- its midpoint shows it is off the paper. The chord from 0 to 11 crosses
    -- the notch's floor, where its midpoint lies, so only the crossing test
    -- sees it. The chord from 0 to 10 passes through the inside corner, 5,
    -- into the notch; its midpoint is that corner, so only splitting it
    -- there finds the piece off the paper. Dropping any one test keeps one.
    case sheetChords uSheet of
      Right (ChordsOnSheet kept) -> do
        map (`S.member` kept) [(9, 10), (0, 11), (0, 10)] `shouldBe` [False, False, False]
        -- Through the inside corner with paper either side of it, along the
        -- notch's floor, and along the paper's own edge.
        map (`S.member` kept) [(2, 8), (4, 6), (0, 3)] `shouldBe` [True, True, True]
      other -> expectationFailure ("expected the U's chords, found " <> show other)

  it "counts the pairs a floor keeps, of every pair of vertices" $ do
    keptPairs EveryChord 4 `shouldBe` Nothing
    keptPairs (ChordsOnSheet (S.fromList [(0, 1), (1, 2)])) 4 `shouldBe` Just (2, 6)

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

  it "refuses a cut sheet, however the cut is stored" $ do
    -- A cut removes no area, so the area test alone passes all three, and a
    -- straight line from a point on the cut cannot tell which side it leaves
    -- by. The first stores the cut as one material point twice, the second
    -- as two points 1e-8 apart, the third as a vertex hanging on one side.
    sheetChords slit `shouldBe` Left (RepeatedMaterialPoint 1 2)
    sheetChords (slitOpenedBy 1e-8) `shouldBe` Left (CutAlong 1 6)
    sheetChords hangingCut `shouldBe` Left (CutAlong 1 5)

  it "refuses a sheet it cannot read" $ do
    sheetChords (sheet [(0, 0), (1, 0), (0, 1)] []) `shouldBe` Left EmptySheet
    -- Vertex 4 lies on the diagonal, so triangle 2 has no area. Read as
    -- paper, it would put every point of its line on the sheet.
    sheetChords (sheet [(0, 0), (1, 0), (1, 1), (0, 1), (0.5, 0.5)] [(0, 1, 2), (0, 2, 3), (0, 4, 2)])
      `shouldBe` Left (DegenerateSheetTriangle 2)
    -- A pose with a NaN: its floor would read as 0 px and pass.
    let nanPose = Mesh [Sample (V2 0 0) (V3 (0 / 0) 0 0), Sample (V2 1 0) (V3 1 0 0), Sample (V2 0 1) (V3 0 1 0)] [(0, 1, 2)]
    screenOf EveryChord (ContactCheck 0 [] [] [] []) [] Nothing nanPose `shouldBe` Left (NonFinitePoint 0)

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
      let verdict = screenVerdict page (screenWith 0 0)
      verdictFloor verdict `shouldBe` True
      verdictOverall verdict `shouldBe` Passes

    it "fails a pose squashed past the screen, not only one stretched" $ do
      let verdict = screenVerdict page (screenWith 0.02 0)
      verdictStrain verdict `shouldBe` False
      verdictOverall verdict `shouldBe` Fails

    it "fails false creases found one level finer, where the pose's own mesh has none" $
      verdictFalseCreases (screenVerdict page (screenWith 0 0) {screenTurningFiner = Just (Turning 2 91)}) `shouldBe` Fails

    it "neither passes nor fails false creases on a pose not made again one level finer" $ do
      -- Owner decision 27: half of the test was never run, so the pose has
      -- not passed it, and failing it would fail every solved pose for a
      -- reason that is not about the pose.
      let verdict = screenVerdict page (screenWith 0 0) {screenTurningFiner = Nothing}
      verdictFalseCreases verdict `shouldBe` NotMeasured
      verdictOverall verdict `shouldBe` NotMeasured

    it "fails false creases on the pose's own mesh, whatever the finer level" $ do
      -- A level not measured must not hide a failure on the one that was.
      let verdict = screenVerdict page (screenWith 0 0) {screenTurning = Turning 1 50, screenTurningFiner = Nothing}
      verdictFalseCreases verdict `shouldBe` Fails
      verdictOverall verdict `shouldBe` Fails

    it "fails a pose that fails a required part, whatever was not measured" $ do
      verdictOverall (screenVerdict page (screenWith 0.02 0) {screenTurningFiner = Nothing}) `shouldBe` Fails
      -- The floor too: 5 px at the declared strain.
      verdictOverall (screenVerdict page (screenWith 0 0) {screenFloorAtScreen = Just (FloorPair (5 / pixelsPerSheet page) (0, 1)), screenTurningFiner = Nothing})
        `shouldBe` Fails

    it "writes a part not measured as null, which the page reads as neither" $ do
      let written = screenJson page (screenWith 0 0) {screenTurningFiner = Nothing}
      map (`verdictKey` written) ["falseCreases", "passes", "strain"] `shouldBe` [Just Null, Just Null, Just (Bool True)]

    it "judges the floor in the pixels of the page, so a larger drawing can fail what a smaller one passes" $ do
      -- Owner decision 30: the floor that is 0.8 px on a page drawn at 600
      -- px to a sheet unit is 1.2 px on one drawn at 900, past the 1 px
      -- limit, and the screen itself is the same.
      let floorAt scale = fmap (floorPixels scale) (screenFloorAtScreen (screenWith 0 0))
      [floorAt page, floorAt larger] `shouldSatisfy` closeTo [0.8, 1.2]
      verdictFloor (screenVerdict page (screenWith 0 0)) `shouldBe` True
      verdictFloor (screenVerdict larger (screenWith 0 0)) `shouldBe` False
      verdictOverall (screenVerdict larger (screenWith 0 0)) `shouldBe` Fails

    it "writes floors, reach-throughs and a picture's floor in the page's pixels" $ do
      -- On a page drawn at 900 px to a sheet unit, the floors that are 1.2
      -- and 0.8 px at 600 are 1.8 and 1.2, and a reach of a thousandth of a
      -- sheet unit is 0.9 px. The square stretched by 3% one way, seen from
      -- above, is 0.015 of a sheet unit from paper in the picture, 13.5 px,
      -- and 0.01 at the 1% screen, 9 px. The screen also says which pixels
      -- it is in, so that a copy of it made away from its page's thresholds
      -- still says so.
      let written = screenJson larger (screenWith 0 0) {screenDeepestReach = Just (0.001, (0, 1))}
      map (`pixelsOf` written) ["pagePixelsPerSheet", "floor3dPixels", "floor3dPixelsAtScreen", "deepestReachPixels"] `shouldSatisfy` closeTo [900, 1.8, 1.2, 0.9]
      map (`pixelsOf` object (pictureFloorJson larger EveryChord topDown stretched)) ["pictureFloorPixels", "pictureFloorPixelsAtScreen"] `shouldSatisfy` closeTo [13.5, 9]

    it "carries the page's scale into every key a gallery writes for a pose, and into its thresholds" $ do
      -- What a gallery writes for a pose drawn in a picture: its screen and
      -- its floor there, both at the page's scale, and the scale once more
      -- for the caption.
      let written = object (poseScreenKeys larger (screenWith 0 0) EveryChord (Just topDown) stretched)
          screen = case written of
            Object keys -> KM.lookup "screen" keys
            _ -> Nothing
      map (`pixelsOf` written) ["pictureFloorPixels", "pictureFloorPixelsAtScreen"] `shouldSatisfy` closeTo [13.5, 9]
      map (\key -> screen >>= pixelsOf key) ["pagePixelsPerSheet", "floor3dPixelsAtScreen"] `shouldSatisfy` closeTo [900, 1.2]
      [pixelsOf "pagePixelsPerSheet" (thresholdsJson larger)] `shouldSatisfy` closeTo [900]

    it "takes a page's scale from its drawings, the largest of them" $ do
      -- On a 200-unit page with a 10-unit margin, a drawing one sheet unit
      -- across and one tall fills the 180-unit box, at 180 px to the unit;
      -- one twice as wide as it is tall fills it across, at 90. Reading the
      -- transform's y scale instead, which is negative because the page
      -- flips y, would screen every floor as none.
      let page200 = defaultPage {pageWidth = 200, pageHeight = 200, pageMargin = 10}
          drawn width = figure page200 (diagramWithExtent (Box (V2 0 0) (V2 width 1)) [Polyline (solid (Colour "#000000") 1) [V2 0 0, V2 width 0]])
      map (figureScale . drawn) [1, 2] `shouldBe` [PageScale 180, PageScale 90]
      map pageScale [drawn 1 :| [drawn 2], drawn 2 :| [drawn 1]] `shouldBe` [PageScale 180, PageScale 180]

    it "reports the 0.1% screen without requiring it" $ do
      let verdict = screenVerdict page (screenWith 0.005 0.005)
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

-- | A page drawn at 600 px to a sheet unit, as the whole crane's, and one
-- drawn half as large again.
page, larger :: PageScale
page = PageScale 600
larger = PageScale 900

-- | The square stretched by 3% along x: 0.015 of a sheet unit from paper,
-- and 0.01 at the 1% screen, its floor set by the sides along the stretch.
stretched :: MaterialMesh
stretched = square {samples = [Sample (V2 u v) (V3 (1.03 * u) v 0) | Sample (V2 u v) _ <- samples square]}

-- | A pose whose floor is within 1 px on 'page' only at the declared strain,
-- with three crossings and no false creases at either level, squashed and
-- stretched as given.
screenWith :: Double -> Double -> Screen
screenWith squash stretch =
  Screen
    { screenSquash = squash,
      screenStretch = stretch,
      screenFloor = Just (FloorPair (1.2 / pixelsPerSheet page) (0, 1)),
      screenFloorAtScreen = Just (FloorPair (0.8 / pixelsPerSheet page) (0, 1)),
      screenFloorPairs = Nothing,
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

-- | Five unit squares in a U, open at the top between x = 1 and x = 2:
-- vertex i is at (i mod 4, i div 4).
uSheet :: MaterialMesh
uSheet = sheet [(fromIntegral (i `mod` 4), fromIntegral (i `div` 4)) | i <- [0 .. 11 :: Int]] (concatMap cell [(0, 0), (1, 0), (2, 0), (0, 1), (2, 1)])
  where
    cell (x, y) = let a = 4 * y + x in [(a, a + 1, a + 5), (a, a + 5, a + 4)]

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
slit = slitOpenedBy 0

-- | The same cut with its right side moved along the bottom edge.
slitOpenedBy :: Double -> MaterialMesh
slitOpenedBy gap = sheet [(0, 0), (0.5, 0), (0.5 + gap, 0), (1, 0), (1, 1), (0, 1), (0.5, 0.5)] [(0, 1, 6), (0, 6, 5), (2, 3, 6), (3, 4, 6), (6, 4, 5)]

-- | The same square cut from (0.5, 0) to (0.5, 0.5), stored with no point
-- twice: the right side has a vertex, 6, at (0.5, 0.25), on the edge 1-5
-- that bounds the left side.
hangingCut :: MaterialMesh
hangingCut = sheet [(0, 0), (0.5, 0), (1, 0), (1, 1), (0, 1), (0.5, 0.5), (0.5, 0.25)] [(0, 1, 5), (0, 5, 4), (5, 3, 4), (1, 2, 6), (6, 2, 3), (6, 3, 5)]

-- | A number a report writes under this key.
pixelsOf :: Key -> Value -> Maybe Double
pixelsOf key (Object written) | Just (Number n) <- KM.lookup key written = Just (realToFrac n)
pixelsOf _ _ = Nothing

-- | Every number present, and each within rounding of the one expected.
closeTo :: [Double] -> [Maybe Double] -> Bool
closeTo expected actual = length expected == length actual && and (zipWith (\e a -> maybe False (\x -> abs (x - e) < 1e-9) a) expected actual)

-- | One key of a screen's JSON verdict.
verdictKey :: Key -> Value -> Maybe Value
verdictKey key (Object written) | Just (Object verdict) <- KM.lookup "verdict" written = KM.lookup key verdict
verdictKey _ _ = Nothing
