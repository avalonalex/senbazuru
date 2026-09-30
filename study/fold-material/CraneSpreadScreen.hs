-- | The paper screen of a crane with one wing moved (PRD 11, R-11-1): the
-- poses of the crane-spreading, crane-root and crane-body galleries. Each is
-- a 'CraneSpread', the finished crane with one wing turned by its grips,
-- solved with the body held, all of it or all but a patch beside the wing.
-- The whole crane is one too, and "WholeCraneScreen" screens it here before
-- adding its body's readings.
--
-- The measures are "PaperScreen"'s and the report "ScreenReport"'s. What
-- this module says is which edges are /joins/: the edges a panel was cut
-- along to make the mesh, where the crease pattern has no crease, so that a
-- join bent past 45 degrees is a false crease (docs/glossary.md).
--
-- Two readings are left out for the three galleries, and each looks like an
-- omission. The false creases one level finer are not measured: a solved
-- pose can be made again one level finer only by solving it again, and owner
-- decision 27 judges such a pose on its own mesh. Two of the galleries do
-- solve one control again at refinement 4, but that is not the pose with
-- every triangle split into four: only the wing's panels, and in crane-root
-- the root's neighbours, are divided again, and the panels beside them are
-- split only where they meet. The curved wing's 392 triangles become 1,192
-- rather than 1,568, so each run is judged on its own mesh. And the body
-- core's length and centre folds are left empty. They tell a pod from a
-- pillow, and here the core is held where the finished crane has it, so they
-- would read the same on every pose.
module CraneSpreadScreen
  ( poseScreen,
    spreadScreen,
    joinBends,
  )
where

import CraneSpread (CraneSpread (..), refinedAssignment)
import FoldBending (Hinge, bentEdges)
import PaperScreen (Chords, ScreenError, Turning)
import ScreenReport (Screen, screenOf)
import Senbazuru.Fold.Types (Assignment (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (ContactCheck)
import Senbazuru.Origami.Surface (MaterialMesh, RefinedSurface (..))

-- | Screen a pose of a crane with a wing moved, given the chords of the
-- fixture's flat sheet ('PaperScreen.sheetChords'); this pose's crossing
-- check ('CraneSpread.spreadCheck') and each hinge's bend on it, in radians
-- ('FoldBending.hingeBends'); and its false-crease turning on the pose made
-- again one level finer, if it was made again.
poseScreen :: CraneSpread -> Chords -> ContactCheck -> [(Hinge, Double)] -> Maybe Turning -> MaterialMesh -> Either ScreenError Screen
poseScreen fixture chords contact bends =
  screenOf chords contact (joinBends fixture (spreadRefined fixture) bends)

-- | Screen a solved pose, which only a new solve could make again, so its
-- finer level is not measured.
spreadScreen :: CraneSpread -> Chords -> ContactCheck -> [(Hinge, Double)] -> MaterialMesh -> Either ScreenError Screen
spreadScreen fixture chords contact bends = poseScreen fixture chords contact bends Nothing

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
