-- | The paper screen of one whole-crane pose (PRD 11, R-11-1), as a record
-- the gallery writes beside each pose and the tests check.
--
-- The measures are "PaperScreen"'s; this module says which parts of the
-- crane they read, and holds the thresholds, each with where it comes from.
--
-- False creases are the joins, the 'Join' edges a panel was cut along for the
-- mesh. A flat crease ('Flat') is a line the crease pattern has and this
-- crane leaves unfolded, so bending paper there bends it along a line the
-- pattern allows, and it is not counted; on More tucked it would add 32.7
-- sheet sides times degrees.
--
-- The centre creases are the pattern's folded creases, mountain and valley,
-- in the body core and through the sheet's centre. Their fold angles tell a
-- pod, still folded along them, from a pillow, opened out across them. A flat
-- crease is left out here too: it has no fold for a pose to keep or undo, so
-- it cannot say which of the two a pose is.
--
-- False-crease turning is measured twice (R-11-1): on the pose's mesh, and
-- on the pose made again with every triangle split into four. A fold keeps
-- its turning on the finer mesh; a curve that the mesh only samples bends
-- each join less there, and loses it (A-11-2). The first candidate is
-- placed around a saved body that exists only at the study's resolution, so
-- it cannot be made again, and its verdict rests on its own mesh.
--
-- No region of the crane is declared a tension field, where paper is
-- expected to stretch, so the strain screen applies to the whole mesh.
module WholeCraneScreen
  ( Screen (..),
    Verdict (..),
    PoseScreenError (..),
    strainScreen,
    strictStrainScreen,
    floorLimitPixels,
    falseCreaseThreshold,
    pixelsPerSheet,
    screenPose,
    screenFrom,
    screenVerdict,
    verdictPasses,
    pictureFloor,
    floorPixels,
    joinBends,
    turningOn,
    screenJson,
    thresholdsJson,
  )
where

import Control.Monad (forM)
import CraneSpread (CraneSpread (..), SpreadError, spreadCheck, spreadSurface)
import Data.Aeson (Value, object, (.=))
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Maybe (maybeToList)
import Data.Set qualified as S
import FoldBending (BendingError, Hinge (..), HingeRole (..), hingeAngle)
import PaperScreen
import Senbazuru.Explain (Explain (..))
import Senbazuru.Geometry (V2 (..), boxCentre, boxFromPoints)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (ContactCheck (..))
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), RefinedSurface (..), Sample (..))
import Senbazuru.Render.Camera (Basis, project)
import WholeCrane (CranePose (..), WholeCrane (..), refinedCrane, remadeOn, studyLevel)

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

-- | The gallery's scale: the flat sheet's side is 600 px.
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
    -- that cannot be made again.
    screenTurningFiner :: !(Maybe Turning),
    screenCoreLength :: !(Maybe Double),
    -- | Median centre-crease folds in degrees: midlines, then diagonals.
    screenCentreFolds :: !(Maybe Double, Maybe Double)
  }
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
    -- | No join bent past 'falseCreaseThreshold', on the pose's mesh or one
    -- level finer.
    verdictFalseCreases :: !Bool
  }
  deriving stock (Eq, Show)

data PoseScreenError
  = PoseSheet !SpreadError
  | PoseBend !BendingError
  | PoseScreen !ScreenError
  deriving stock (Show)

instance Explain PoseScreenError where
  explain (PoseSheet err) = explain err
  explain (PoseBend err) = explain err
  explain (PoseScreen err) = explain err

-- | Screen one pose of the whole-crane study, working out everything the
-- screen reads from the pose alone.
screenPose :: WholeCrane -> CranePose -> Either PoseScreenError Screen
screenPose study pose = do
  let fixture = wholeSpread study
      mesh = craneMesh pose
      points = IM.fromList (zip [0 ..] (samples mesh))
  _ <- first PoseSheet (spreadSurface fixture mesh)
  contact <- first PoseSheet (spreadCheck fixture mesh)
  bends <- mapM (\h -> (,) h . fst <$> first PoseBend (hingeAngle h points)) (spreadHinges fixture)
  finer <- first PoseSheet (refinedCrane (studyLevel + 1) (wholeMap study))
  turningFiner <- turningOn finer study pose
  screenFrom study contact bends turningFiner mesh

-- | Screen one pose from what the gallery has already worked out for it: its
-- crossing check, each hinge's bend in radians, and its turning one level
-- finer. All must be of this mesh.
screenFrom :: WholeCrane -> ContactCheck -> [(Hinge, Double)] -> Maybe Turning -> MaterialMesh -> Either PoseScreenError Screen
screenFrom study contact bends turningFiner mesh = do
  first PoseScreen (sheetIsConvex mesh)
  deepest <- first PoseScreen (deepestReach mesh (crossingPanels contact))
  let placed = [(sampleMaterial s, position s) | s <- samples mesh]
      (squash, stretch) = strainExtremes mesh
      core = wholeCore study
      centreCreases =
        [ (u, v, angle)
          | (h, (a, b), (u, v), angle) <- bentEdges mesh bends,
            S.member a core && S.member b core,
            SurfaceCrease _ <- [hingeRole h]
        ]
      centre = boxCentre <$> boxFromPoints (map fst placed)
  pure $!
    Screen
      { screenSquash = squash,
        screenStretch = stretch,
        screenFloor = noStretchFloor 0 placed,
        screenFloorAtScreen = noStretchFloor strainScreen placed,
        screenCrossings = length (crossingPanels contact),
        screenDeepestReach = deepest,
        screenTurning = falseCreaseTurning falseCreaseThreshold (joinBends (spreadRefined (wholeSpread study)) bends),
        screenTurningFiner = turningFiner,
        screenCoreLength = coreLength core mesh,
        screenCentreFolds = maybe (Nothing, Nothing) (`centreFolds` centreCreases) centre
      }

-- | Each join a pose bends, as its length on the flat sheet and its bend in
-- degrees: the 'PanelBend' hinges on edges the refinement made, which lie on
-- no edge of the sheet it refined. Those are exactly the edges a written
-- frame assigns 'Join'; the refinement says so at any level, with no frame
-- to write.
joinBends :: RefinedSurface -> [(Hinge, Double)] -> [(Double, Double)]
joinBends refined bends =
  [ (norm (u ^-^ v), angle)
    | (h, (a, b), (u, v), angle) <- bentEdges (refinedMesh refined) bends,
      hingeRole h == PanelBend,
      S.notMember (min a b, max a b) sheetEdges
  ]
  where
    sheetEdges = S.fromList [(min a b, max a b) | (_, (a, b)) <- refinedEdges refined]

-- | False-crease turning of a pose made again on another refinement of the
-- sheet, given that refinement and its hinges; nothing for a pose that cannot
-- be made again.
turningOn :: (RefinedSurface, [Hinge]) -> WholeCrane -> CranePose -> Either PoseScreenError (Maybe Turning)
turningOn (refined, hinges) study pose = do
  remade <- first PoseSheet (remadeOn study refined (craneConstruction pose))
  forM remade $ \mesh -> do
    let points = IM.fromList (zip [0 ..] (samples mesh))
    bends <- mapM (\h -> (,) h . fst <$> first PoseBend (hingeAngle h points)) hinges
    pure (falseCreaseTurning falseCreaseThreshold (joinBends refined bends))

-- | Each hinge with its edge, the edge's two ends on the flat sheet, and its
-- bend in degrees. A hinge's first two vertices are its edge; the other two
-- are the far corners of the triangles either side.
bentEdges :: MaterialMesh -> [(Hinge, Double)] -> [(Hinge, (Int, Int), (V2, V2), Double)]
bentEdges mesh bends =
  [ (h, (a, b), (u, v), angle * 180 / pi)
    | (h, angle) <- bends,
      let (a, b, _, _) = hingeVertices h,
      Just u <- [IM.lookup a material],
      Just v <- [IM.lookup b material]
  ]
  where
    material = IM.fromList (zip [0 ..] (map sampleMaterial (samples mesh)))

-- | The no-stretch floor in one picture: distances measured after projecting
-- onto the page, so never larger than the floor in 3D.
pictureFloor :: Basis -> Double -> MaterialMesh -> Maybe FloorPair
pictureFloor basis epsilon mesh = noStretchFloor epsilon [(sampleMaterial s, project basis (position s)) | s <- samples mesh]

-- | A floor in pixels; a negative floor, room to spare, is none.
floorPixels :: FloorPair -> Double
floorPixels f = pixelsPerSheet * max 0 (floorDistance f)

screenVerdict :: Screen -> Verdict
screenVerdict s =
  Verdict
    { verdictStrain = within strainScreen,
      verdictStrictStrain = within strictStrainScreen,
      verdictFloor = all ((<= floorLimitPixels) . floorPixels) (screenFloorAtScreen s),
      verdictFalseCreases = all ((== 0) . turningJoins) (screenTurning s : maybeToList (screenTurningFiner s))
    }
  where
    within limit = screenSquash s <= limit && screenStretch s <= limit

-- | A pose passes when every required part does; 'verdictStrictStrain' is
-- reported, not required.
verdictPasses :: Verdict -> Bool
verdictPasses v = verdictStrain v && verdictFloor v && verdictFalseCreases v

-- | The screen as the gallery writes it. Floors and reaches are in pixels,
-- the core's length in sheet sides and the turning in sheet sides times
-- degrees, as each key says. The thresholds are written once for the whole
-- gallery, by 'thresholdsJson'.
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
            "falseCreases" .= verdictFalseCreases verdict,
            "passes" .= verdictPasses verdict
          ]
    ]
  where
    verdict = screenVerdict s

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
