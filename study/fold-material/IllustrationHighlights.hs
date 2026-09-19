-- | Locate the area interval's contributions without drawing them wider.
-- The measurement uses y-up page coordinates at 600 pixels per sheet unit;
-- these drawings use those same coordinates as their model space. The SVG
-- backend supplies the sole y flip and applies magnification BEFORE decimal
-- formatting, so a detail can reveal geometry lost in a rounded overview.
--
-- A fixed 16-pixel grid partitions every outside or unclassified triangle.
-- Numbered tiles are navigation aids, not connected paper features or a new
-- area threshold. Keep even tiny positive pieces. Each 32x detail renders a
-- tile as 512 pixels plus margins, clipping context to the same box in Haskell.
-- One Fill per colour prevents antialiasing seams between adjacent triangles;
-- highlight fills have no stroke. Locator frames are a separate drawing.
module IllustrationHighlights
  ( HighlightTile (..),
    highlightTiles,
    tileSide,
    detailScale,
    cellRings,
    highlightPage,
    highlightDrawing,
    detailDrawing,
    locatorDrawing,
  )
where

import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Ord (Down (..))
import Data.Text (Text)
import Data.Text qualified as T
import IllustrationDistance
import Senbazuru.Diagram
import Senbazuru.Geometry (Box (..), V2 (..), boxFromPoints)
import Senbazuru.Geometry.Polygon (clipConvex, signedArea)
import Senbazuru.Render.Svg

data HighlightTile = HighlightTile
  { tileBox :: Box,
    tileOutside :: [[V2]],
    tileUnresolved :: [[V2]]
  }
  deriving stock (Eq, Show)

tileSide, detailScale :: Double
tileSide = 16
detailScale = 32

cellRings :: [AreaCell] -> [[V2]]
cellRings cells = [[a, b, c] | AreaCell _ (a, b, c) <- cells]

-- | Source triangles have disjoint interiors. Grid clipping keeps that
-- partition; tile sums recover the area up to clipping roundoff. The unchanged
-- measurement weights remain authoritative, and are exported separately.
highlightTiles :: AreaRegions -> [HighlightTile]
highlightTiles regions = sortOn (Down . area) [HighlightTile box outside unresolved | ((i, j), (a, b)) <- Map.toAscList buckets, let box = gridBox i j, let outside = clip box a, let unresolved = clip box b, not (null outside && null unresolved)]
  where
    buckets = Map.fromListWith join (concatMap (tiles False) (cellRings (outsideCells regions)) ++ concatMap (tiles True) (cellRings (unresolvedCells regions)))
    join (a, b) (c, d) = (a ++ c, b ++ d)
    tiles uncertain ring = case boxFromPoints ring of
      Nothing -> []
      Just (Box (V2 x0 y0) (V2 x1 y1)) -> [((i, j), if uncertain then ([], [ring]) else ([ring], [])) | i <- indices x0 x1, j <- indices y0 y1]
    indices a b = [floor (a / tileSide) .. floor (b / tileSide) :: Int]
    gridBox i j = let x = fromIntegral i * tileSide; y = fromIntegral j * tileSide in Box (V2 x y) (V2 (x + tileSide) (y + tileSide))
    area tile = sum (map (abs . signedArea) (tileOutside tile ++ tileUnresolved tile))

highlightPage :: Text -> Double -> Box -> Page
highlightPage title scale (Box (V2 x0 y0) (V2 x1 y1)) =
  defaultPage {pageWidth = scale * (x1 - x0) + 40, pageHeight = scale * (y1 - y0) + 40, pageMargin = 20, pageTitle = Just title, pageBackground = Nothing}

-- | Grey is the source sheet silhouette, blue is matching target-layer
-- exposure. Red means definitely outside; amber retains unclassified area.
-- Context is painted first, so it cannot obscure a measured contribution.
highlightDrawing :: Box -> [[V2]] -> [[V2]] -> [[V2]] -> [[V2]] -> Diagram
highlightDrawing extent paper target outside unresolved =
  diagramWithExtent extent [Fill (Colour "#e5e2dc") paper, Fill (Colour "#c0dce8") target, Fill (Colour "#cf2545") outside, Fill (Colour "#b67b00") unresolved]

detailDrawing :: HighlightTile -> [[V2]] -> [[V2]] -> Diagram
detailDrawing tile paper target = highlightDrawing box (clip box paper) (clip box target) (tileOutside tile) (tileUnresolved tile)
  where
    box = tileBox tile

locatorDrawing :: Box -> [HighlightTile] -> Diagram
locatorDrawing extent tiles = diagramWithExtent extent (concat [marker n (tileBox tile) | (n, tile) <- zip [1 :: Int ..] tiles])
  where
    marker n box@(Box (V2 x0 _) (V2 _ y1)) =
      [ Polyline (Stroke (Colour "#6450a0") 0.6 (Dash [2, 2])) (boxRing box ++ take 1 (boxRing box)),
        Label (Colour "#4e387f") 9 (V2 (x0 + 1) (y1 - 9)) (T.pack (show n))
      ]

clip :: Box -> [[V2]] -> [[V2]]
clip box rings = [piece | ring <- rings, let ccw = if signedArea ring < 0 then reverse ring else ring, let piece = clipConvex (boxRing box) ccw, abs (signedArea piece) > 0]

boxRing :: Box -> [V2]
boxRing (Box (V2 x0 y0) (V2 x1 y1)) = [V2 x0 y0, V2 x1 y0, V2 x1 y1, V2 x0 y1]
