-- | The paper screen as a report (PRD 11, R-11-1): the thresholds, each with
-- where it comes from, the record one pose's screen fills in, its verdict,
-- and the JSON a gallery writes beside the pose.
--
-- It is a module of its own because every gallery that draws poses as paper
-- writes the same report (owner decision 26), while what a pose's screen
-- reads differs from gallery to gallery: "WholeCraneScreen" reads the crane's
-- sheet and core. The measures themselves are "PaperScreen"'s.
--
-- The non-obvious part is that the false-crease verdict has three answers,
-- not two. A pose made again one level finer is judged at both levels. A pose
-- that is not made again, because it could be only by solving it again, is
-- judged on its own mesh, and its finer level is /not measured/, which is
-- neither a pass nor a fail (owner decision 27). Reading it as a pass would
-- claim half a test that never ran; reading it as a fail would fail every
-- solved pose for a reason that is not about the pose.
module ScreenReport
  ( Screen (..),
    Judgement (..),
    Verdict (..),
    strainScreen,
    strictStrainScreen,
    floorLimitPixels,
    falseCreaseThreshold,
    pixelsPerSheet,
    screenVerdict,
    verdictOverall,
    pictureFloor,
    floorPixels,
    screenJson,
    thresholdsJson,
  )
where

import Data.Aeson (Value, object, (.=))
import PaperScreen
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..))
import Senbazuru.Render.Camera (Basis, project)

-- | The strain a pose may carry and still pass, squash or stretch: owner
-- decision 16 (2026-09-29), 1% principal strain outside declared
-- tension-field regions.
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

-- | The galleries' scale: the flat sheet's side is 600 px.
pixelsPerSheet :: Double
pixelsPerSheet = 600

-- | One pose's screen. Lengths are in sheet sides, the flat square's side
-- being 1, until 'screenJson' writes them as pixels.
data Screen = Screen
  { -- | Largest squash and stretch, as non-negative fractions.
    screenSquash :: !Double,
    screenStretch :: !Double,
    -- | The no-stretch floor in 3D, at no strain and at 'strainScreen';
    -- nothing for a pose with no pair of vertices.
    screenFloor :: !(Maybe FloorPair),
    screenFloorAtScreen :: !(Maybe FloorPair),
    -- | Pairs the study's strict test flags, and the largest reach-through
    -- among them with its triangles: a bound on how deep that pair crosses.
    screenCrossings :: !Int,
    screenDeepestReach :: !(Maybe (Double, (Int, Int))),
    screenTurning :: !Turning,
    -- | The same on the pose made again one level finer; nothing for a pose
    -- that is not made again, whose finer level is not measured.
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
    -- | The 3D floor at 'strainScreen' within 'floorLimitPixels'. A
    -- picture's floor is never larger, since projecting never lengthens, so
    -- this settles every camera at once.
    verdictFloor :: !Bool,
    -- | No join bent past 'falseCreaseThreshold', on the pose's mesh and on
    -- the pose made again one level finer.
    verdictFalseCreases :: !Judgement
  }
  deriving stock (Eq, Show)

screenVerdict :: Screen -> Verdict
screenVerdict s =
  Verdict
    { verdictStrain = within strainScreen,
      verdictStrictStrain = within strictStrainScreen,
      verdictFloor = all ((<= floorLimitPixels) . floorPixels) (screenFloorAtScreen s),
      verdictFalseCreases = falseCreases
    }
  where
    within limit = screenSquash s <= limit && screenStretch s <= limit
    none turning = turningJoins turning == 0
    -- A false crease on the pose's own mesh fails it, whatever a finer level
    -- would say. With none there, the finer level decides, if it was
    -- measured.
    falseCreases
      | not (none (screenTurning s)) = Fails
      | otherwise = case screenTurningFiner s of
          Nothing -> NotMeasured
          Just finer -> if none finer then Passes else Fails

-- | The verdict as a whole: it fails when a required part fails, is not
-- measured when none fails but one was not measured, and passes otherwise.
-- 'verdictStrictStrain' is reported, not required.
verdictOverall :: Verdict -> Judgement
verdictOverall v
  | not (verdictStrain v) || not (verdictFloor v) || verdictFalseCreases v == Fails = Fails
  | verdictFalseCreases v == NotMeasured = NotMeasured
  | otherwise = Passes

-- | The no-stretch floor in one picture: distances measured after projecting
-- onto the page, so never larger than the floor in 3D.
pictureFloor :: Chords -> Basis -> Double -> MaterialMesh -> Maybe FloorPair
pictureFloor chords basis epsilon mesh = noStretchFloor chords epsilon [(sampleMaterial s, project basis (position s)) | s <- samples mesh]

-- | A floor in pixels; a negative floor, room to spare, is none.
floorPixels :: FloorPair -> Double
floorPixels f = pixelsPerSheet * max 0 (floorDistance f)

-- | The screen as a gallery writes it. Floors and reaches are in pixels, the
-- core's length in sheet sides and the turning in sheet sides times degrees,
-- as each key says. A judgement is true, false, or null when not measured.
-- The thresholds are written once for the whole gallery, by
-- 'thresholdsJson'.
screenJson :: Screen -> Value
screenJson s =
  object
    [ "squash" .= screenSquash s,
      "stretch" .= screenStretch s,
      "floor3dPixels" .= fmap floorPixels (screenFloor s),
      "floorVertices" .= fmap floorVertices (screenFloor s),
      "floor3dPixelsAtScreen" .= fmap floorPixels (screenFloorAtScreen s),
      "floorVerticesAtScreen" .= fmap floorVertices (screenFloorAtScreen s),
      "crossingPairCount" .= screenCrossings s,
      "deepestReachPixels" .= fmap ((pixelsPerSheet *) . fst) (screenDeepestReach s),
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
    verdict = screenVerdict s
    judged = \case
      Passes -> Just True
      Fails -> Just False
      NotMeasured -> Nothing

-- | The screen's thresholds, for the page's labels.
thresholdsJson :: Value
thresholdsJson =
  object
    [ "pixelsPerSheet" .= pixelsPerSheet,
      "strainScreen" .= strainScreen,
      "strictStrainScreen" .= strictStrainScreen,
      "floorLimitPixels" .= floorLimitPixels,
      "falseCreaseThresholdDegrees" .= falseCreaseThreshold
    ]
