-- | The paper screen of a solved pose that its gallery writes as a triangle
-- surface (PRD 11, R-11-1): the wing-bending and wing-layers galleries.
--
-- The measures are "PaperScreen"'s and the report "ScreenReport"'s. What
-- this module adds is where the joins come from. A join is an edge a panel
-- was cut along to make the mesh, where the crease pattern has no crease,
-- so that a join bent past 45 degrees is a false crease (docs/glossary.md).
-- Each of these galleries writes its pose through a surface writer that
-- marks every join J in the frame it writes: "UncreasedSurface" for one
-- uncreased panel, 'WingLayers.layersSurface' for two layers joined along
-- one crease. The screen reads its joins from that frame, so it counts
-- exactly the edges the pose's own FOLD file calls joins, each once
-- however many hinges it carries ('FoldBending.joinsWhere').
-- "CraneSpreadScreen" reads the same rule without a frame, because the
-- whole crane is screened again on a refinement nothing writes.
--
-- The false creases one level finer are whatever the gallery gives. For a
-- solved pose that is usually nothing, not measured: a pose that only a new
-- solve can /make again/ (docs/glossary.md) is judged on its own mesh (owner
-- decision 27). Both wing galleries solve some poses again on the mesh split
-- into four, and there the finer level is that solve's turning where
-- "FinerSolve" counts it (owner decisions 29 and 31).
module SurfaceScreen
  ( surfaceJoins,
    surfaceScreen,
  )
where

import Control.Monad (unless)
import Data.Set qualified as S
import FoldBending (Hinge, joinsWhere)
import PaperScreen (Chords, ScreenError (..), Turning)
import ScreenReport (Screen, screenOf)
import Senbazuru.Fold.Query (edgeKey)
import Senbazuru.Fold.Types (Assignment (..), Frame (..), VertexId (..))
import Senbazuru.Geometry (V2)
import Senbazuru.Origami.Contact (ContactCheck)
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Surface, surfaceFrame)

-- | The joins of a written surface: the edges its frame assigns 'Join', each
-- as its two vertices, the lower first. A surface keeps its frame's vertex
-- numbers, which are its mesh's.
surfaceJoins :: Surface V2 -> S.Set (Int, Int)
surfaceJoins sheet = S.fromList [edgeKey a b | ((a, b), Join) <- zip (edgesVertices frame) (edgesAssignment frame)]
  where
    frame = surfaceFrame sheet

-- | Screen a solved pose from the surface its gallery writes for it, given
-- the chords of its flat sheet ('PaperScreen.sheetChords'), its crossing
-- check, and each hinge's bend on it in radians ('FoldBending.hingeBends'),
-- all of this mesh, and its false-crease turning one level finer: nothing,
-- not measured, or its gallery's finer solve's ("FinerSolve"). A surface
-- written for another mesh is refused: its joins would name other edges.
surfaceScreen :: Surface V2 -> Chords -> ContactCheck -> [(Hinge, Double)] -> Maybe Turning -> MaterialMesh -> Either ScreenError Screen
surfaceScreen sheet chords contact bends finer mesh = do
  unless (facesVertices (surfaceFrame sheet) == [map VertexId [a, b, c] | (a, b, c) <- triangles mesh]) (Left SurfaceOfAnotherMesh)
  screenOf chords contact (joinsWhere (`S.member` written) mesh bends) finer mesh
  where
    written = surfaceJoins sheet
