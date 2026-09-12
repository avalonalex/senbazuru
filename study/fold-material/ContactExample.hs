-- | A connected unit sheet with two opposing flaps. Both crease preferences
-- are 150 degrees, which makes the unconstrained flaps cross. The declared
-- order asks the left flap to remain below the right. No final positions or
-- contact angles are prescribed; this is a control for the numerical solve.
-- Start the left flap farther closed so it approaches below the right, as
-- declared. The 1e-6 numerical clearance applies only to those disjoint flaps;
-- both remain joined to the middle panel with zero clearance at their creases.
module ContactExample (ContactExample (..), ExampleError (..), opposingFlaps, opposingFlapsAt, ApproachPose (..), opposingApproach, rightFlapSweep) where

import ContactDiscovery qualified as Discovery
import Data.Bifunctor (first)
import Data.Map.Strict qualified as M
import Data.Text (Text)
import FoldBending
import HingeSweep qualified as Sweep
import PanelContact
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types (Assignment (..), EdgeId (..), Frame (..), VertexId (..), emptyFrame)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface qualified as Paper
import StudyCase
import SurfaceContact qualified as Contact

data ContactExample = ContactExample
  { exampleSurface :: !(Paper.Surface V2),
    exampleRefined :: !Paper.RefinedSurface,
    exampleHinges :: ![Hinge],
    exampleContact :: !Contact.OrderedContact,
    exampleClearance :: !Double
  }
  deriving stock (Eq, Show)

newtype ExampleError = ExampleError Text
  deriving stock (Eq, Show)

instance Explain ExampleError where
  explain (ExampleError message) = message

-- | Each pose comes from crease angles on the same sheet. Its history contains
-- only the observations up to that pose, never knowledge from later frames.
data ApproachPose = ApproachPose
  { approachAngles :: !(Double, Double),
    approachExample :: !ContactExample,
    approachHistory :: !Discovery.ReferenceContact
  }
  deriving stock (Eq, Show)

-- | Start with separated flap projections, then close the right flap until
-- the first sampled overlap. This is an authored approach, not motion planning.
-- The fixture's declared pairs remain an independent test oracle; discovery
-- consumes only mesh positions, source-panel ownership and a model direction.
opposingApproach :: Int -> Either ExampleError [ApproachPose]
opposingApproach level = do
  initial <- opposingFlapsAt level 145 105
  let refined = exampleRefined initial
  reference <- first (ExampleError . explain) (Discovery.discoverReference (exampleClearance initial) (V3 0 0 1) (Paper.refinedPanels refined) (Paper.refinedMesh refined))
  later <- observe reference initial 105 [110, 115, 120, 121]
  pure (ApproachPose (145, 105) initial reference : later)
  where
    observe _ _ _ [] = Right []
    observe reference previous from (angle : rest) = do
      fixture <- opposingFlapsAt level 145 angle
      motion <- first (ExampleError . explain) (rightFlapSweep (angle - from) (Paper.refinedMesh (exampleRefined previous)))
      learned <- first (ExampleError . explain) (Discovery.observeContactSweep Sweep.defaultSweepSettings reference motion (Paper.refinedMesh (exampleRefined fixture)))
      later <- observe learned fixture angle rest
      pure (ApproachPose (145, angle) fixture learned : later)

-- | Signed angular travel in degrees for this unit-sheet control. Increasing
-- its valley angle lifts the right side, hence the NEGATIVE y hinge direction.
rightFlapSweep :: Double -> Paper.MaterialMesh -> Either Sweep.SweepError Sweep.HingeSweep
rightFlapSweep angle mesh = Sweep.prepareSweep (V3 0.7 0 0) (V3 0 (-1) 0) (angle * pi / 180) moving mesh
  where
    moving = [i | (i, sample) <- zip [0 ..] (Paper.samples mesh), let V2 u _ = Paper.sampleMaterial sample, u >= 0.7]

opposingFlaps :: Int -> Either ExampleError ContactExample
opposingFlaps level = opposingFlapsAt level 145 105

-- | Vary the reference pose while retaining the same material and targets.
-- The authored order remains an independent oracle for discovery tests.
opposingFlapsAt :: Int -> Double -> Double -> Either ExampleError ContactExample
opposingFlapsAt level leftAngle rightAngle = do
  pose <- first (ExampleError . explain) (buildCasePose 0 spec sheet (PoseSpec "Open flaps" (replicate 8 0 ++ [leftAngle, rightAngle])))
  let surface = poseSurface pose
      clearance = 1e-6
      targets = M.fromList [(EdgeId 8, 150 * pi / 180), (EdgeId 9, 150 * pi / 180)]
  (refined, hinges) <- first (ExampleError . explain) (buildSurfaceHinges defaultBending level surface targets)
  (axis, orders) <- maybe (Left (ExampleError "opposing flaps need declared layer requirements")) Right (Paper.surfaceLayerRequirements surface)
  contact <- first (ExampleError . explain) (Contact.prepareContact clearance axis orders (Paper.refinedPanels refined) (Paper.refinedMesh refined))
  pure (ContactExample surface refined hinges contact clearance)
  where
    spec = CaseSpec "opposing-flaps" "Opposing flaps" "" "" [] (Just (0.5, 0.5)) (Just (ContactSpec (V3 0 0 1) [PanelTag "base" (V2 0.5 0.5), PanelTag "left" (V2 0.15 0.5), PanelTag "right" (V2 0.85 0.5)] [("base", "left"), ("base", "right"), ("left", "right")]))
    sheet =
      emptyFrame
        { verticesCoords = [[0, 0], [0.3, 0], [0.7, 0], [1, 0], [1, 1], [0.7, 1], [0.3, 1], [0, 1]],
          edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 7), (7, 0), (1, 6), (2, 5)]],
          edgesAssignment = replicate 8 Border ++ [Valley, Valley],
          facesVertices = [map VertexId [0, 1, 6, 7], map VertexId [1, 2, 5, 6], map VertexId [2, 3, 4, 5]]
        }
