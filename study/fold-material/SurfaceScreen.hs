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
-- exactly the edges the pose's own FOLD file calls joins.
-- "CraneSpreadScreen" reads the same rule without a frame, because the
-- whole crane is also screened on a refinement nothing writes.
--
-- The false creases one level finer are not measured, as for every solved
-- pose (owner decision 27), and here that looks most like an omission:
-- wing-bending's 16-division wing is its 8-division wing with every triangle
-- split into four. But it is that shape solved again, not made again, and
-- decision 27 judges a pose that only a new solve could make again on its
-- own mesh, so each wing is judged on its own.
module SurfaceScreen
  ( surfaceJoins,
    surfaceScreen,
  )
where

import Data.Set qualified as S
import FoldBending (Hinge, bentEdges)
import PaperScreen (Chords, ScreenError)
import ScreenReport (Screen, screenOf)
import Senbazuru.Fold.Types (Assignment (..), Frame (..), VertexId (..))
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (ContactCheck)
import Senbazuru.Origami.Surface (MaterialMesh, Surface, surfaceFrame)

-- | The joins of a written surface: the edges its frame assigns 'Join', each
-- as its two vertices, the lower first. A surface keeps its frame's vertex
-- numbers, which are its mesh's.
surfaceJoins :: Surface V2 -> S.Set (Int, Int)
surfaceJoins sheet =
  S.fromList
    [ (min a b, max a b)
      | ((VertexId a, VertexId b), Join) <- zip (edgesVertices frame) (edgesAssignment frame)
    ]
  where
    frame = surfaceFrame sheet

-- | Screen a solved pose from the surface its gallery writes for it, given
-- the chords of its flat sheet ('PaperScreen.sheetChords'), its crossing
-- check, and each hinge's bend on it in radians ('FoldBending.hingeBends'),
-- all of this mesh. Its finer level is not measured.
surfaceScreen :: Surface V2 -> Chords -> ContactCheck -> [(Hinge, Double)] -> MaterialMesh -> Either ScreenError Screen
surfaceScreen sheet chords contact bends mesh = screenOf chords contact joins Nothing mesh
  where
    written = surfaceJoins sheet
    joins =
      [ (norm (u ^-^ v), angle)
        | (_, (a, b), (u, v), angle) <- bentEdges mesh bends,
          S.member (min a b, max a b) written
      ]
