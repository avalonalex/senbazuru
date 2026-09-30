-- | The paper screen of a crane with one wing moved (PRD 11, R-11-1): the
-- poses of the crane-spreading, crane-root and crane-body galleries. Each is
-- a 'CraneSpread', the finished crane with one wing turned by its grips,
-- solved with the body held, all of it or all but a patch beside the wing.
--
-- The measures are "PaperScreen"'s and the report "ScreenReport"'s. What
-- this module says is which edges are /joins/: the edges a panel was cut
-- along to make the mesh, where the crease pattern has no crease, so that a
-- join bent past 45 degrees is a false crease (docs/glossary.md). The whole
-- crane's screen, "WholeCraneScreen", reads its joins here too.
--
-- Two readings are left out, and each looks like an omission. The false
-- creases one level finer are not measured: a solved pose can be made again
-- one level finer only by solving it again, and owner decision 27 judges
-- such a pose on its own mesh. Two of the galleries do solve one control
-- again at refinement 4, but that is not the pose with every triangle split
-- into four: only the wing's panels, and in crane-root the root's
-- neighbours, are divided again, and the panels beside them are split only
-- where they meet. The curved wing's 392 triangles become 1,192 rather than
-- 1,568, so each run is judged on its own mesh. And the body core's length
-- and centre folds are left empty. They tell a pod from a pillow, and here
-- the core is held where the finished crane has it, so they would read the
-- same on every pose.
module CraneSpreadScreen
  ( PoseScreenError (..),
    spreadScreen,
    joinBends,
  )
where

import CraneSpread (CraneSpread (..), SpreadError, refinedAssignment)
import Data.Bifunctor (first)
import FoldBending (BendingError, Hinge, bentEdges, hingeBends)
import PaperScreen (Chords, ScreenError)
import ScreenReport (Screen, screenOf)
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Types (Assignment (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (ContactCheck)
import Senbazuru.Origami.Surface (MaterialMesh, RefinedSurface (..))

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

-- | Screen one solved pose of a crane with a wing moved, given the chords of
-- the fixture's flat sheet ('PaperScreen.sheetChords') and this pose's
-- crossing check ('CraneSpread.spreadCheck'). Its finer level is not
-- measured.
spreadScreen :: CraneSpread -> Chords -> ContactCheck -> MaterialMesh -> Either PoseScreenError Screen
spreadScreen fixture chords contact mesh = do
  bends <- first PoseBend (hingeBends (spreadHinges fixture) mesh)
  first PoseScreen (screenOf chords contact (joinBends fixture (spreadRefined fixture) bends) Nothing mesh)

-- | Each join of a refinement of the fixture's sheet that a pose bends, as
-- its length on the flat sheet and its bend in degrees. A join is an edge a
-- written frame assigns 'Join', and 'refinedAssignment' is the rule every
-- frame the study writes follows; reading it without writing a frame works
-- at levels nothing writes. The @2@ is the edge's triangle count: a hinge
-- has one either side.
joinBends :: CraneSpread -> RefinedSurface -> [(Hinge, Double)] -> [(Double, Double)]
joinBends fixture refined bends =
  [ (norm (u ^-^ v), angle)
    | (_, (a, b), (u, v), angle) <- bentEdges (refinedMesh refined) bends,
      assignment (min a b, max a b) 2 == Join
  ]
  where
    assignment = refinedAssignment (spreadSource fixture) refined
