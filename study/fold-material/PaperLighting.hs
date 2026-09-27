-- | Lighting directions for the curved-panel preview, without changing paper.
-- A normal is a direction perpendicular to a surface; lighting uses it to
-- decide how bright that surface looks. Flat triangle normals expose every
-- subdivision of a curved panel as a seam. Averaging neighbouring triangle
-- normals makes that panel look curved, but doing so across a crease would
-- make a deliberately sharp fold look rounded.
--
-- Group by original panel AND material vertex id. Coincident points on two
-- folded layers are not neighbours in the sheet and must never share lighting.
-- Triangle area weights the average, so a tiny triangle cannot dominate its
-- larger neighbour. This is a study presentation choice, not material physics:
-- positions, contact and the outer silhouette remain exactly as before.
-- Degenerate input is refused. If an average cancels or points behind its own
-- triangle, retain that triangle's normal rather than disguising a reversal.
module PaperLighting (panelCornerNormals, PaperLightingError (..)) where

import Control.Monad (unless)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Types (FaceId)
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (Mesh (..), Sample (..))

data PaperLightingError
  = LightingPanelCount !Int !Int
  | LightingMissingVertex !Int !Int
  | LightingBadTriangle !Int
  deriving stock (Eq, Show)

instance Explain PaperLightingError where
  explain (LightingPanelCount panels faces) = "paper lighting has " <> tshow panels <> " source panels for " <> tshow faces <> " triangles"
  explain (LightingMissingVertex face vertex) = "paper lighting triangle " <> tshow face <> " refers to missing vertex " <> tshow vertex
  explain (LightingBadTriangle face) = "paper lighting triangle " <> tshow face <> " has no finite, nonzero area"

-- | One unit normal per corner, in the input triangle's order and axes.
-- The source panel list comes from refinement, not from spatial proximity.
panelCornerNormals :: [FaceId] -> Mesh material -> Either PaperLightingError [[V3]]
panelCornerNormals owners mesh = do
  unless (length owners == length (triangles mesh)) (Left (LightingPanelCount (length owners) (length (triangles mesh))))
  faces <- traverse triangle (zip [0 ..] (triangles mesh))
  let sums = M.fromListWith (^+^) [((panel, vertex), areaNormal) | (panel, (ids, areaNormal, _)) <- zip owners faces, vertex <- ids]
      corner panel vertex areaNormal flat =
        case unit (M.findWithDefault areaNormal (panel, vertex) sums) of
          Just normal | dot normal flat > 0 -> normal
          _ -> flat
  pure [[corner panel vertex areaNormal flat | vertex <- ids] | (panel, (ids, areaNormal, flat)) <- zip owners faces]
  where
    points = IM.fromList (zip [0 ..] (map position (samples mesh)))
    triangle (face, (a, b, c)) = do
      p <- point face a
      q <- point face b
      r <- point face c
      let areaNormal = cross (q ^-^ p) (r ^-^ p)
      flat <- maybe (Left (LightingBadTriangle face)) Right (unit areaNormal)
      pure ([a, b, c], areaNormal, flat)
    point face vertex = maybe (Left (LightingMissingVertex face vertex)) Right (IM.lookup vertex points)
    unit v
      | isNaN size || isInfinite size || size <= 0 = Nothing
      | otherwise = Just ((1 / size) *^ v)
      where
        size = norm v
