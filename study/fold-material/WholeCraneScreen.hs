-- | The paper screen of one whole-crane pose (PRD 11, R-11-1), as the record
-- the gallery writes beside each pose and the tests check.
--
-- The measures are "PaperScreen"'s and the report, thresholds and verdict
-- "ScreenReport"'s; this module says which parts of the crane they read.
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
-- its turning on the finer mesh, while a curve that the mesh only samples
-- bends each join less there and loses it (A-11-2); a bend narrower than
-- the mesh can keep it for several levels before it goes
-- (docs/notes/fold-or-curve.md). The first candidate is not made again, so
-- its finer level is not measured ("ScreenReport"), and it fails on its own
-- mesh anyway, where four joins bend past 45 degrees.
--
-- No region of the crane is declared a tension field, where paper is
-- expected to stretch, so the strain screen applies to the whole mesh.
module WholeCraneScreen
  ( PoseScreenError (..),
    screenPose,
    screenFrom,
    turningOn,
  )
where

import Control.Monad (forM)
import CraneSpread (CraneSpread (..), SpreadError, refinedAssignment, spreadCheck, spreadSurface)
import Data.Bifunctor (first)
import Data.Set qualified as S
import FoldBending (BendingError, Hinge (..), HingeRole (..), bentEdges, hingeBends)
import PaperScreen
import ScreenReport
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Types (Assignment (..))
import Senbazuru.Geometry (boxCentre, boxFromPoints)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (ContactCheck (..))
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), RefinedSurface (..), Sample (..))
import WholeCrane (Construction, CranePose, WholeCrane (..), craneConstruction, craneMesh, finerCrane, remadeOn)

data PoseScreenError
  = PoseSheet !SpreadError
  | PoseBend !BendingError
  | PoseScreen !ScreenError
  | -- | An error on the pose made again on a refinement with this many
    -- triangles, not on the pose's own mesh. Its vertex numbers are the
    -- remade mesh's, which no file the gallery writes contains.
    PoseRemade !Int !PoseScreenError
  deriving stock (Show)

instance Explain PoseScreenError where
  explain (PoseSheet err) = explain err
  explain (PoseBend err) = explain err
  explain (PoseScreen err) = explain err
  explain (PoseRemade triangleCount err) = "on the pose made again on " <> tshow triangleCount <> " triangles: " <> explain err

-- | Screen one pose of the whole-crane study, working out everything the
-- screen reads from the pose alone.
screenPose :: WholeCrane -> CranePose -> Either PoseScreenError Screen
screenPose study pose = do
  let fixture = wholeSpread study
      mesh = craneMesh pose
  _ <- first PoseSheet (spreadSurface fixture mesh)
  contact <- first PoseSheet (spreadCheck fixture mesh)
  bends <- first PoseBend (hingeBends (spreadHinges fixture) mesh)
  chords <- first PoseScreen (sheetChords mesh)
  finer <- first PoseSheet (finerCrane study)
  turningFiner <- turningOn finer study (craneConstruction pose)
  screenFrom study chords contact bends turningFiner mesh

-- | Screen one pose from what the gallery has already worked out for it: its
-- sheet's chords, its crossing check and each hinge's bend in radians, all
-- of this mesh, and its false-crease turning on the pose made again one
-- level finer ('turningOn' on 'finerCrane'). "ScreenReport"'s 'screenOf'
-- does the rest; this adds the crane body's readings.
screenFrom :: WholeCrane -> Chords -> ContactCheck -> [(Hinge, Double)] -> Maybe Turning -> MaterialMesh -> Either PoseScreenError Screen
screenFrom study chords contact bends turningFiner mesh = do
  screen <- first PoseScreen (screenOf chords contact (joinBends study (spreadRefined (wholeSpread study)) bends) turningFiner mesh)
  let core = wholeCore study
      centreCreases =
        [ (u, v, angle)
          | (h, (a, b), (u, v), angle) <- bentEdges mesh bends,
            S.member a core && S.member b core,
            SurfaceCrease _ <- [hingeRole h]
        ]
      centre = boxCentre <$> boxFromPoints (map sampleMaterial (samples mesh))
  pure $!
    screen
      { screenCoreLength = coreLength core mesh,
        screenCentreFolds = maybe (Nothing, Nothing) (`centreFolds` centreCreases) centre
      }

-- | Each join of a refinement that a pose bends, as its length on the flat
-- sheet and its bend in degrees. A join is an edge a written frame assigns
-- 'Join', and 'refinedAssignment' is the rule every frame the study writes
-- follows; reading it without writing a frame works at levels nothing
-- writes. The @2@ is the edge's triangle count: a hinge has one either side.
joinBends :: WholeCrane -> RefinedSurface -> [(Hinge, Double)] -> [(Double, Double)]
joinBends study refined bends =
  [ (norm (u ^-^ v), angle)
    | (_, (a, b), (u, v), angle) <- bentEdges (refinedMesh refined) bends,
      assignment (min a b, max a b) 2 == Join
  ]
  where
    assignment = refinedAssignment (spreadSource (wholeSpread study)) refined

-- | False-crease turning of a pose made again from its construction on a
-- refinement of the sheet, given that refinement and its hinges; nothing for
-- a pose that is not made again. An error says which refinement it came
-- from.
turningOn :: (RefinedSurface, [Hinge]) -> WholeCrane -> Construction -> Either PoseScreenError (Maybe Turning)
turningOn (refined, hinges) study construction = first (PoseRemade (length (triangles (refinedMesh refined)))) $ do
  remade <- first PoseSheet (remadeOn study refined construction)
  forM remade $ \mesh -> do
    bends <- first PoseBend (hingeBends hinges mesh)
    pure (falseCreaseTurning falseCreaseThreshold (joinBends study refined bends))
