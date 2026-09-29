-- | The paper screen of one whole-crane pose (PRD 11, R-11-1), as a record
-- the gallery writes beside each pose and the tests check.
--
-- The measures are "PaperScreen"'s; this module says which parts of the
-- crane they read. False creases are the joins, the 'Join' edges a panel was
-- cut along for the mesh: a flat crease ('Flat') is a crease line of the
-- pattern, and bending one is not a false crease. The centre creases are the
-- creases of the body core through the sheet's centre, whose fold angles tell
-- a pod, still folded along them, from a pillow, opened out across them.
--
-- The thresholds are owner decisions, not facts: 1% strain (decision 16,
-- 2026-09-29), 45 degrees for a false crease on a pose. Crossings are
-- reported with no pass or fail (the same decision).
module WholeCraneScreen
  ( Screen (..),
    PoseScreenError (..),
    strainScreen,
    falseCreaseThreshold,
    screenPose,
    screenJson,
  )
where

import CraneSpread (CraneSpread (..), SpreadError, spreadCheck, spreadSurface)
import Data.Aeson (Value, object, (.=))
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import FoldBending (BendingError, Hinge (..), HingeRole (..), hingeAngle)
import PaperScreen
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types (Assignment (..), Frame (..), VertexId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (ContactCheck (..))
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..), materialFrame)
import WholeCrane (WholeCrane (..))

-- | The strain a pose may carry and still be called paper: owner decision
-- 16, reported beside the 0.1% the study screened at before it.
strainScreen :: Double
strainScreen = 0.01

-- | A join bent further than this, in degrees, is a false crease on a pose.
falseCreaseThreshold :: Double
falseCreaseThreshold = 45

data Screen = Screen
  { -- | Largest squash and stretch, as fractions.
    screenSquash :: !Double,
    screenStretch :: !Double,
    -- | The no-stretch floor in 3D, at no strain and at 'strainScreen'.
    screenFloor :: !FloorPair,
    screenFloorAtScreen :: !FloorPair,
    -- | Pairs the study's strict test flags, and the deepest of them.
    screenCrossings :: !Int,
    screenDeepestReach :: !(Maybe (Double, (Int, Int))),
    screenTurning :: !Turning,
    screenCoreLength :: !(Maybe Double),
    -- | Median centre-crease folds in degrees: midlines, then diagonals.
    screenCentreFolds :: !(Maybe Double, Maybe Double)
  }
  deriving stock (Eq, Show)

data PoseScreenError
  = PoseSheet !SpreadError
  | PoseBend !BendingError
  | PoseScreen !ScreenError
  | -- | A pose with fewer than two vertices has no pair to set a floor.
    PoseTooSmall
  deriving stock (Show)

instance Explain PoseScreenError where
  explain (PoseSheet err) = explain err
  explain (PoseBend err) = explain err
  explain (PoseScreen err) = explain err
  explain PoseTooSmall = "a pose needs two vertices before a no-stretch floor means anything"

-- | Screen one pose of the whole-crane study.
screenPose :: WholeCrane -> MaterialMesh -> Either PoseScreenError Screen
screenPose study mesh = do
  let fixture = wholeSpread study
  first PoseScreen (sheetIsConvex mesh)
  sheet <- first PoseSheet (spreadSurface fixture mesh)
  contact <- first PoseSheet (spreadCheck fixture mesh)
  deepest <- first PoseScreen (deepestReach mesh (crossingPanels contact))
  let points = IM.fromList (zip [0 ..] (samples mesh))
  bends <- mapM (\h -> (,) h . fst <$> first PoseBend (hingeAngle h points)) (spreadHinges fixture)
  let placed = [(sampleMaterial s, position s) | s <- samples mesh]
      distance p q = norm (p ^-^ q)
      frame = materialFrame sheet
      assignments = M.fromList [(edgeKey a b, assignment) | ((VertexId a, VertexId b), assignment) <- zip (edgesVertices frame) (edgesAssignment frame)]
      material i = sampleMaterial <$> IM.lookup i points
      edgeOf h = let (a, b, _, _) = hingeVertices h in (a, b)
      degrees angle = abs angle * 180 / pi
      joins =
        [ (norm (u ^-^ v), degrees angle)
          | (h, angle) <- bends,
            hingeRole h == PanelBend,
            let (a, b) = edgeOf h,
            M.lookup (edgeKey a b) assignments == Just Join,
            Just u <- [material a],
            Just v <- [material b]
        ]
      core = wholeCore study
      centreCreases =
        [ (u, v, degrees angle)
          | (h, angle) <- bends,
            isCrease (hingeRole h),
            let (a, b) = edgeOf h,
            S.member a core && S.member b core,
            Just u <- [material a],
            Just v <- [material b]
        ]
  atRest <- maybe (Left PoseTooSmall) Right (noStretchFloor 0 distance placed)
  atScreen <- maybe (Left PoseTooSmall) Right (noStretchFloor strainScreen distance placed)
  let (squash, stretch) = strainExtremes mesh
  pure
    Screen
      { screenSquash = squash,
        screenStretch = stretch,
        screenFloor = atRest,
        screenFloorAtScreen = atScreen,
        screenCrossings = length (crossingPanels contact),
        screenDeepestReach = deepest,
        screenTurning = falseCreaseTurning falseCreaseThreshold joins,
        screenCoreLength = coreLength core mesh,
        screenCentreFolds = centreFolds (sheetCentre (map fst placed)) centreCreases
      }
  where
    edgeKey a b = (min a b, max a b)
    isCrease (SurfaceCrease _) = True
    isCrease _ = False

-- | The middle of the sheet's material extent: the square's centre.
sheetCentre :: [V2] -> V2
sheetCentre us = case us of
  [] -> V2 0 0
  _ -> V2 ((minimum xs + maximum xs) / 2) ((minimum ys + maximum ys) / 2)
  where
    xs = [x | V2 x _ <- us]
    ys = [y | V2 _ y <- us]

-- | The screen as the gallery writes it, lengths at 600 px per sheet side.
-- A pose passes when its strain and 3D floor are within the screen and no
-- join is a false crease; a picture's floor can only be smaller than the 3D
-- one, since projecting never lengthens. Crossings are reported only.
screenJson :: Screen -> Value
screenJson s =
  object
    [ "strainScreen" .= strainScreen,
      "squash" .= screenSquash s,
      "stretch" .= screenStretch s,
      "floorPixels" .= pixels (floorDistance (screenFloor s)),
      "floorPair" .= floorVertices (screenFloor s),
      "floorPixelsAtScreen" .= pixels (floorDistance (screenFloorAtScreen s)),
      "crossingPairs" .= screenCrossings s,
      "deepestReachPixels" .= fmap ((600 *) . fst) (screenDeepestReach s),
      "deepestReachPair" .= fmap snd (screenDeepestReach s),
      "falseCreaseThresholdDegrees" .= falseCreaseThreshold,
      "falseCreaseJoins" .= turningJoins (screenTurning s),
      "falseCreaseTurning" .= turningTotal (screenTurning s),
      "coreLength" .= screenCoreLength s,
      "centreMidlineFoldDegrees" .= fst (screenCentreFolds s),
      "centreDiagonalFoldDegrees" .= snd (screenCentreFolds s),
      "passes"
        .= object
          [ "strain" .= (screenSquash s <= strainScreen && screenStretch s <= strainScreen),
            "floor" .= (pixels (floorDistance (screenFloorAtScreen s)) <= 1),
            "falseCreases" .= (turningJoins (screenTurning s) == 0)
          ]
    ]
  where
    pixels d = 600 * max 0 d
