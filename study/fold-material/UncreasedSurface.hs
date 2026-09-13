-- | Export one bent, uncreased material panel through the normal renderers.
-- A large curved polygon cannot be flattened to one plane. Its mesh triangles
-- become planar FOLD faces, while J (join) edges say those faces are still one
-- piece of paper. They are numerical subdivisions, not material creases.
-- See docs/glossary.md for join edges and material coordinates.
--
-- The source-panel id remains zero for every triangle in explicit metadata.
-- This adapter is deliberately for ONE uncreased panel; it cannot reconstruct
-- crease identities or layer orders for the multi-panel crane. Both SVG and
-- glTF consume this same Surface, including its original-sheet coordinates.
module UncreasedSurface (UncreasedError (..), uncreasedSurface) where

import Data.Aeson (toJSON)
import Data.Aeson.KeyMap qualified as KM
import Data.Bifunctor (first)
import Data.Map.Strict qualified as M
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface

data UncreasedError = UncreasedSurfaceFailure !SurfaceError | InvalidUncreasedEdge !Int !Int !Int
  deriving stock (Eq, Show)

instance Explain UncreasedError where
  explain (UncreasedSurfaceFailure e) = explain e
  explain (InvalidUncreasedEdge a b count) = "uncreased mesh edge " <> tshow a <> "–" <> tshow b <> " belongs to " <> tshow count <> " triangles; expected one or two"

uncreasedSurface :: MaterialMesh -> Either UncreasedError (Surface V2)
uncreasedSurface mesh = do
  assignments <- traverse assignment (M.toAscList incidence)
  first UncreasedSurfaceFailure (surfaceFromFrame (frame assignments) >>= requireMaterialCoordinates)
  where
    key a b = (min a b, max a b)
    incidence = M.fromListWith (+) [(key a b, 1 :: Int) | (i, j, k) <- triangles mesh, (a, b) <- [(i, j), (j, k), (k, i)]]
    assignment ((a, b), count) = case count of
      1 -> Right Border
      2 -> Right Join
      _ -> Left (InvalidUncreasedEdge a b count)
    coordinates (V3 x y z) = [x, y, z]
    frame assignments =
      emptyFrame
        { frameClasses = ["foldedForm"],
          frameAttributes = ["3D"],
          verticesCoords = map (coordinates . position) (samples mesh),
          edgesVertices = [(VertexId a, VertexId b) | (a, b) <- M.keys incidence],
          edgesAssignment = assignments,
          facesVertices = [map VertexId [a, b, c] | (a, b, c) <- triangles mesh],
          frameExtras =
            KM.fromList
              [ ("senbazuru:material_coords", toJSON [[materialU p, materialV p] | p <- samples mesh]),
                ("senbazuru:source_panels", toJSON (replicate (length (triangles mesh)) (0 :: Int)))
              ]
        }
