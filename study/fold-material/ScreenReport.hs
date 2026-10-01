-- | The paper screen as a report (PRD 11, R-11-1): the thresholds, each with
-- where it comes from, the record one pose's screen fills in, how it is
-- filled from what a gallery has worked out, its verdict, the JSON a
-- gallery writes beside the pose, and the script its page reads it with.
--
-- It is a module of its own because every gallery that draws poses as paper
-- is to write the same report (owner decision 26), while what a pose's
-- screen reads differs from gallery to gallery: which edges are joins, and
-- whether the paper is a crane's body. "CraneSpreadScreen" reads a crane
-- with a wing moved, "SurfaceScreen" a pose from the surface its gallery
-- writes, and "WholeCraneScreen" the whole crane. The measures themselves
-- are "PaperScreen"'s.
--
-- The non-obvious part is that the false-crease verdict has three answers,
-- not two. False-crease turning is measured on the pose's mesh and, where the
-- pose is made again with every triangle split into four, /one level finer/.
-- A pose that is not made again is judged on its own mesh, and its finer
-- level is /not measured/, which is neither a pass nor a fail. Owner decision
-- 27 rules so for a pose that only a new solve could make again, and the same
-- holds for the whole crane's first candidate, whose remake is work not yet
-- done. Reading it as a pass would claim half a test that never ran; reading
-- it as a fail would fail a pose for a reason that is not about the pose.
-- Owner decisions 29 and 31 make one exception: a gallery's own solve on the
-- mesh split into four settles a solved pose's finer level where the gallery
-- accepts that solve and it is shown to be the same pose ("FinerSolve").
--
-- The other non-obvious part is that a screen has no pixels of its own.
-- Floors and reach-throughs are measured in sheet units, and only a page
-- turns them into pixels: owner decision 30 judges the 1 px floor limit at
-- the scale the page draws its poses at, so the same pose can pass on a
-- page that draws it small and fail on one that draws it large. A screen is
-- therefore judged and written at a 'PageScale' given to 'screenVerdict' and
-- 'screenJson', never at one stored in it, and a gallery screens a pose
-- before its page's drawings, which are what fix the scale, exist.
module ScreenReport
  ( Screen (..),
    Judgement (..),
    Verdict (..),
    PageScale (..),
    Figure (..),
    figure,
    pageScale,
    screenOf,
    strainScreen,
    strictStrainScreen,
    floorLimitPixels,
    falseCreaseThreshold,
    screenVerdict,
    verdictOverall,
    floorPixels,
    screenJson,
    pictureFloorJson,
    poseScreenKeys,
    thresholdsJson,
    writeScreenScript,
  )
where

import Data.Aeson (Value, object, (.=))
import Data.Aeson.Types (Pair)
import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import PaperScreen
import Senbazuru.Diagram (Diagram)
import Senbazuru.Geometry (Transform (..), V2 (..))
import Senbazuru.Origami.Contact (ContactCheck (..))
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..))
import Senbazuru.Render.Camera (Basis)
import Senbazuru.Render.Svg (Page, pageTransform, renderSvg)
import System.Directory (copyFile)
import System.FilePath ((</>))

-- | The strain a pose may carry and still pass, squash or stretch: owner
-- decision 16 (2026-09-29), 1% principal strain outside declared
-- tension-field regions, where paper is declared to stretch, as an inflated
-- membrane does. No gallery declares one yet.
strainScreen :: Double
strainScreen = 0.01

-- | The strain reported beside 'strainScreen', and not required: the study's
-- screen before decision 16, which the decision keeps in view.
strictStrainScreen :: Double
strictStrainScreen = 0.001

-- | The largest no-stretch floor, in pixels at 'strainScreen', a pose may
-- have and still pass: PRD 11's target for the floor (R-11-3).
floorLimitPixels :: Double
floorLimitPixels = 1

-- | A join bent further than this, in degrees, is a false crease on a pose:
-- PRD 11's threshold for poses (A-11-2).
falseCreaseThreshold :: Double
falseCreaseThreshold = 45

-- | The scale a page draws its poses at, in pixels to a sheet unit, one unit
-- of the flat sheet's coordinates (docs/glossary.md). The screen gives a
-- pose's floors and reach-throughs in these pixels and judges
-- 'floorLimitPixels' in them, so that a verdict follows the size the page
-- draws a pose at (owner decision 30).
newtype PageScale = PageScale {pixelsPerSheet :: Double}
  deriving stock (Eq, Ord, Show)

-- | A drawing as a gallery writes it: its SVG, and the scale it draws at.
data Figure = Figure
  { figureSvg :: !Text,
    figureScale :: !PageScale
  }

-- | A diagram drawn on a page, with the scale 'renderSvg' draws it at. Every
-- gallery here draws one sheet unit as one unit of its model, so the
-- transform's page units per model unit are pixels per sheet unit.
figure :: Page -> Diagram -> Figure
figure page d = Figure (renderSvg page d) (PageScale across)
  where
    V2 across _ = tScale (pageTransform page d)

-- | The scale a page screens its poses at, its /page scale/
-- (docs/glossary.md): the largest at which its gallery draws the paper, in
-- the figures on the page or the drawings it writes beside them, so that a
-- pose that passes passes in every one of them. A pose drawn in none is
-- screened at that scale too. A plot of measurements, such as crane-root's
-- side profiles, is not a drawing of the paper and is not given here. A
-- page that draws no paper has no scale: its gallery writes its
-- measurements without screens and publishes no page.
pageScale :: NonEmpty Figure -> PageScale
pageScale = maximum . fmap figureScale

-- | One pose's screen. Lengths are in sheet units until 'screenJson' writes
-- them as pixels at a page's scale.
data Screen = Screen
  { -- | Largest squash and stretch, as non-negative fractions.
    screenSquash :: !Double,
    screenStretch :: !Double,
    -- | The no-stretch floor in 3D, at no strain and at 'strainScreen';
    -- nothing for a pose with no pair of vertices.
    screenFloor :: !(Maybe FloorPair),
    screenFloorAtScreen :: !(Maybe FloorPair),
    -- | On a sheet that is not convex, the pairs the floor was taken over
    -- and of how many ('keptPairs'); nothing where every pair counts.
    screenFloorPairs :: !(Maybe (Int, Int)),
    -- | Pairs the study's strict test flags, and the largest reach-through
    -- among them with its triangles: a bound on how deep that pair crosses.
    screenCrossings :: !Int,
    screenDeepestReach :: !(Maybe (Double, (Int, Int))),
    screenTurning :: !Turning,
    -- | The same on the pose made again one level finer, or on its gallery's
    -- finer solve ("FinerSolve"); nothing for a pose that is not made
    -- again, whose finer level is not measured.
    screenTurningFiner :: !(Maybe Turning),
    -- | The body core's head-to-tail length and its median centre-crease
    -- folds in degrees, midlines then diagonals; nothing for paper that is
    -- not a crane's body.
    screenCoreLength :: !(Maybe Double),
    screenCentreFolds :: !(Maybe Double, Maybe Double)
  }
  deriving stock (Eq, Show)

-- | One part of a verdict: passed, failed, or not measured, which is neither.
data Judgement = Passes | Fails | NotMeasured
  deriving stock (Eq, Show)

-- | Which parts of the screen a pose passes. Crossings have no part: owner
-- decision 16 reports them without a verdict until F2's contact states give
-- separations to compare.
data Verdict = Verdict
  { -- | Squash and stretch both within 'strainScreen'.
    verdictStrain :: !Bool,
    -- | Both within 'strictStrainScreen'; reported, not required.
    verdictStrictStrain :: !Bool,
    -- | The 3D floor at 'strainScreen' within 'floorLimitPixels' at the
    -- page's scale. A picture's floor is never larger, since projecting
    -- never lengthens, so this settles every camera at once.
    verdictFloor :: !Bool,
    -- | No join bent past 'falseCreaseThreshold', on the pose's mesh and on
    -- the pose made again one level finer. 'NotMeasured' when the pose has
    -- none there and was not made again; a join past the threshold on its
    -- own mesh fails it either way.
    verdictFalseCreases :: !Judgement
  }
  deriving stock (Eq, Show)

-- | A pose's screen from what its gallery has worked out: its sheet's
-- 'Chords', from 'sheetChords' of this mesh; its crossing check; each join's
-- length on the flat sheet and bend in degrees; and its false-crease turning
-- one level finer, if it was made again. The crane body's readings are left
-- empty, for a crane's screen to fill in.
screenOf :: Chords -> ContactCheck -> [(Double, Double)] -> Maybe Turning -> MaterialMesh -> Either ScreenError Screen
screenOf chords contact joins turningFiner mesh = do
  finitePoints mesh
  deepest <- deepestReach mesh (crossingPanels contact)
  let placed = [(sampleMaterial s, position s) | s <- samples mesh]
      (squash, stretch) = strainExtremes mesh
  pure $!
    Screen
      { screenSquash = squash,
        screenStretch = stretch,
        screenFloor = noStretchFloor chords 0 placed,
        screenFloorAtScreen = noStretchFloor chords strainScreen placed,
        screenFloorPairs = keptPairs chords (length placed),
        screenCrossings = length (crossingPanels contact),
        screenDeepestReach = deepest,
        screenTurning = falseCreaseTurning falseCreaseThreshold joins,
        screenTurningFiner = turningFiner,
        screenCoreLength = Nothing,
        screenCentreFolds = (Nothing, Nothing)
      }

-- | Which parts of the screen a pose passes, on a page drawn at this scale.
screenVerdict :: PageScale -> Screen -> Verdict
screenVerdict scale s =
  Verdict
    { verdictStrain = within strainScreen,
      verdictStrictStrain = within strictStrainScreen,
      verdictFloor = all ((<= floorLimitPixels) . floorPixels scale) (screenFloorAtScreen s),
      verdictFalseCreases = falseCreases
    }
  where
    within limit = screenSquash s <= limit && screenStretch s <= limit
    none turning = turningJoins turning == 0
    falseCreases
      | not (none (screenTurning s)) = Fails
      | otherwise = case screenTurningFiner s of
          Nothing -> NotMeasured
          Just finer -> if none finer then Passes else Fails

-- | The verdict as a whole, a failed part outranking one not measured.
-- 'verdictStrictStrain' is reported, not required.
verdictOverall :: Verdict -> Judgement
verdictOverall v
  | not (verdictStrain v) || not (verdictFloor v) || verdictFalseCreases v == Fails = Fails
  | verdictFalseCreases v == NotMeasured = NotMeasured
  | otherwise = Passes

-- | A floor in pixels at a page's scale; a negative floor, room to spare, is
-- none.
floorPixels :: PageScale -> FloorPair -> Double
floorPixels scale f = pixelsPerSheet scale * max 0 (floorDistance f)

-- | The screen as a gallery writes it, on a page drawn at this scale. Floors
-- and reaches are in that page's pixels, the core's length in sheet units
-- and the turning in sheet units times degrees, as each key says, and the
-- scale is written with them, so that a screen copied out of its gallery's
-- report still says what its pixels are. A judgement is true, false, or
-- null when not measured. The thresholds are written once for the whole
-- gallery, by 'thresholdsJson'.
screenJson :: PageScale -> Screen -> Value
screenJson scale s =
  object
    [ "pagePixelsPerSheet" .= pixelsPerSheet scale,
      "squash" .= screenSquash s,
      "stretch" .= screenStretch s,
      "floor3dPixels" .= fmap (floorPixels scale) (screenFloor s),
      "floorVertices" .= fmap floorVertices (screenFloor s),
      "floor3dPixelsAtScreen" .= fmap (floorPixels scale) (screenFloorAtScreen s),
      "floorVerticesAtScreen" .= fmap floorVertices (screenFloorAtScreen s),
      "floorPairs" .= screenFloorPairs s,
      "crossingPairCount" .= screenCrossings s,
      "deepestReachPixels" .= fmap ((pixelsPerSheet scale *) . fst) (screenDeepestReach s),
      "deepestReachTriangles" .= fmap snd (screenDeepestReach s),
      "falseCreaseJoins" .= turningJoins (screenTurning s),
      "falseCreaseTurningSheetDegrees" .= turningTotal (screenTurning s),
      "falseCreaseJoinsFiner" .= fmap turningJoins (screenTurningFiner s),
      "falseCreaseTurningFinerSheetDegrees" .= fmap turningTotal (screenTurningFiner s),
      "coreLengthSheets" .= screenCoreLength s,
      "centreMidlineFoldDegrees" .= fst (screenCentreFolds s),
      "centreDiagonalFoldDegrees" .= snd (screenCentreFolds s),
      "verdict"
        .= object
          [ "strain" .= verdictStrain verdict,
            "strictStrain" .= verdictStrictStrain verdict,
            "floor" .= verdictFloor verdict,
            "falseCreases" .= judged (verdictFalseCreases verdict),
            "passes" .= judged (verdictOverall verdict)
          ]
    ]
  where
    verdict = screenVerdict scale s
    judged = \case
      Passes -> Just True
      Fails -> Just False
      NotMeasured -> Nothing

-- | A pose's no-stretch floor in one picture a gallery draws it in, at no
-- strain and at 'strainScreen', in pixels at the page's scale, as the keys
-- the gallery writes beside the pose's screen. It is not part of 'Screen'
-- because it depends on the camera, and a pose drawn in no picture has no
-- such keys.
pictureFloorJson :: PageScale -> Chords -> Basis -> MaterialMesh -> [Pair]
pictureFloorJson scale chords basis mesh =
  [ "pictureFloorPixels" .= fmap (floorPixels scale) (pictureFloor chords basis 0 mesh),
    "pictureFloorPixelsAtScreen" .= fmap (floorPixels scale) (pictureFloor chords basis strainScreen mesh)
  ]

-- | The keys a gallery's report carries for one pose on a page drawn at
-- this scale: its screen, and, if the gallery draws the pose in a picture
-- from this camera, its floor there ('pictureFloorJson').
poseScreenKeys :: PageScale -> Screen -> Chords -> Maybe Basis -> MaterialMesh -> [Pair]
poseScreenKeys scale screen chords picture mesh = ("screen" .= screenJson scale screen) : maybe [] (\basis -> pictureFloorJson scale chords basis mesh) picture

-- | The screen's thresholds and the page's scale, for the page's labels.
-- The scale's key is not the one a screen at a fixed 600 px to a sheet unit
-- was written under, so that a page made before decision 30, beside one
-- made after it and sharing its script, shows no scale rather than 600 as
-- its own.
thresholdsJson :: PageScale -> Value
thresholdsJson scale =
  object
    [ "pagePixelsPerSheet" .= pixelsPerSheet scale,
      "strainScreen" .= strainScreen,
      "strictStrainScreen" .= strictStrainScreen,
      "floorLimitPixels" .= floorLimitPixels,
      "falseCreaseThresholdDegrees" .= falseCreaseThreshold
    ]

-- | Write @paper-screen.js@, which a page reads 'screenJson' and
-- 'thresholdsJson' with, into the directory of a gallery's page. Every page
-- with a screen loads this one script, so a verdict reads the same on each.
writeScreenScript :: FilePath -> IO ()
writeScreenScript destination = copyFile "study/fold-material/paper-screen.js" (destination </> "paper-screen.js")
