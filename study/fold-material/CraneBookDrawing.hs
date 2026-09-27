-- | An instruction-book treatment of the saved crane, not a new paper shape.
-- The input's visible polygons already say which surface is nearest. Each
-- original paper panel (the material between creases) receives one
-- broad tone from its area-weighted surface direction. This deliberately
-- leaves out lighting variations inside a curved panel; its actual outline
-- and creases still describe its shape. No outline is redrawn by hand.
--
-- A contour is an edge with empty space or a different-depth layer beside it.
-- Clipping splits these edges, so cancel shared, opposite-facing stretches
-- only where their depths agree. Cancelling by position alone would erase a
-- flap's overlap edge. Triangle joins then disappear, while real creases come
-- from the input's separately clipped feature lines. A lighter drawing may
-- omit short crease fragments, but never contours. Lengths for this choice
-- are drawing pixels at the gallery's declared 600 pixels per sheet unit.
-- This is a presentation experiment; it cannot repair stretched paper.
module CraneBookDrawing
  ( BookDrawing (..),
    bookDrawing,
    bookShapes,
    contourSegments,
    selectedCreases,
  )
where

import BodyIntersectionContext (planeDepth)
import Control.Monad (unless)
import Data.IntMap.Strict qualified as IM
import Data.List (foldl')
import Data.Map.Strict qualified as M
import Data.Text (Text)
import Senbazuru.Diagram
import Senbazuru.Fold.Query (ringEdges)
import Senbazuru.Fold.Types (Assignment (..), FaceId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (cross2, signedArea)
import Senbazuru.Geometry.V3 (V3, cross)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..))
import Senbazuru.Origami.Visible
import Senbazuru.Render.Camera

data BookDrawing = BookDrawing
  { bookTones :: ![(Colour, [[V2]])],
    bookContours :: ![(V2, V2)],
    bookCreases :: ![(V2, V2)]
  }
  deriving stock (Eq, Show)

-- | Shade the original material panel, not each subdivision triangle. This
-- coarse lighting is an explicit illustration choice; it preserves all of the
-- input visible regions, including small reverse-side patches and defects.
bookDrawing :: Basis -> [FaceId] -> MaterialMesh -> VisibleForm -> Either Text BookDrawing
bookDrawing basis owners mesh seen = do
  unless (length owners == length (triangles mesh)) (Left "book drawing requires one source panel per triangle")
  faces <- traverse triangle (zip owners (triangles mesh))
  let summed = M.fromListWith (^+^) [(owner, areaNormal) | (owner, _, areaNormal) <- faces]
      light = (1 / sqrt 1.65) *^ ((-0.4) *^ basisRight basis ^+^ 0.7 *^ basisUp basis ^-^ basisForward basis)
  directions <- traverse (unit "book drawing panel normals cancel") summed
  patches <- traverse (patch (IM.fromList (zip [0 ..] faces)) directions light) (formRegions seen)
  let tones = [(Colour colour, concat [rings | (_, level, rings) <- patches, level == index]) | (index, colour) <- [(0, "#b9aa94"), (1, "#e1d6c4"), (2, "#f7f2e7")]]
      contours = contourSegments [(ring, z) | (z, _, rings) <- patches, ring <- rings]
      creases = [(project basis (visibleFrom edge), project basis (visibleTo edge)) | edge <- formEdges seen, visibleAssignment edge `elem` [Mountain, Valley, Flat, Unassigned]]
  pure (BookDrawing tones contours creases)
  where
    points = IM.fromList (zip [0 ..] (map position (samples mesh)))
    triangle (owner, (a, b, c)) = do
      p <- point a
      q <- point b
      r <- point c
      let areaNormal = cross (q ^-^ p) (r ^-^ p)
      _ <- unit "book drawing triangle has no finite area" areaNormal
      pure (owner, [p, q, r], areaNormal)
    point i = maybe (Left "book drawing triangle has no vertex") Right (IM.lookup i points)
    unit message v
      | isNaN size || isInfinite size || size <= 0 = Left message
      | otherwise = Right ((1 / size) *^ v)
      where
        size = norm v
    patch faces directions light region = do
      (owner, ps, _) <- maybe (Left "book drawing region has no triangle") Right (IM.lookup (unFaceId (regionFace region)) faces)
      direction <- maybe (Left "book drawing panel has no direction") Right (M.lookup owner directions)
      let facing = if regionTopSide region then direction else (-1) *^ direction
          brightness = dot light facing
          level | brightness < 0.35 = 0 | brightness < 0.75 = 1 | otherwise = 2 :: Int
      z <- depthFunction basis ps
      pure (z, level, map (ccw . map (project basis)) (regionPieces region))

depthFunction :: Basis -> [V3] -> Either Text (V2 -> Double)
depthFunction basis ps = do
  a <- at (V2 0 0)
  b <- at (V2 1 0)
  c <- at (V2 0 1)
  pure (\(V2 x y) -> a + x * (b - a) + y * (c - a))
  where
    at p = maybe (Left "book drawing triangle has no depth plane") Right (planeDepth basis ps p)

-- | Convex visible pieces have disjoint interiors. Their shared boundary may
-- be one long edge against several short ones. Subtract overlapping intervals
-- instead of matching endpoint pairs; this also handles clipping's T joins.
-- The 1e-9 allowance is numerical bookkeeping, not an ink/detail threshold.
contourSegments :: [([V2], V2 -> Double)] -> [(V2, V2)]
contourSegments patches = concatMap exposed edges
  where
    edges = [(a, b, z) | (ring, z) <- patches, (a, b) <- ringEdges (ccw ring), norm (b ^-^ a) > 1e-12]
    exposed (a, b, z) =
      let direction = (1 / norm (b ^-^ a)) *^ (b ^-^ a)
          len = norm (b ^-^ a)
          along p = dot (p ^-^ a) direction
          onLine p = abs (cross2 direction (p ^-^ a)) <= 1e-9
          point t = a ^+^ t *^ direction
          covers = [(lo, hi) | (c, d, otherZ) <- edges, dot (d ^-^ c) direction < 0, onLine c, onLine d, let lo = max 0 (along d), let hi = min len (along c), hi > lo, all (\t -> abs (z (point t) - otherZ (point t)) <= 1e-9) [lo, hi]]
          remaining = foldl' (\pieces interval -> concatMap (subtractInterval interval) pieces) [(0, len)] covers
       in [(point lo, point hi) | (lo, hi) <- remaining, hi - lo > 1e-12]
    subtractInterval (c, d) (a, b)
      | d <= a || c >= b = [(a, b)]
      | otherwise = [(a, min b c) | c > a] ++ [(max a d, b) | d < b]

selectedCreases :: Double -> [(V2, V2)] -> ([(V2, V2)], [(V2, V2)])
selectedCreases minimumPixels edges =
  (filter keep edges, filter (not . keep) edges)
  where
    keep (a, b) = 600 * norm (b ^-^ a) >= minimumPixels

-- | The drawing-scale cutoff affects crease ink only. Keep missing-coverage
-- diagnostics outside this function so every presentation receives them.
bookShapes :: Double -> BookDrawing -> [Shape]
bookShapes minimumPixels drawing =
  [Fill colour rings | (colour, rings) <- bookTones drawing]
    ++ [Polyline (solid (Colour "#777568") 0.65) [a, b] | (a, b) <- fst (selectedCreases minimumPixels (bookCreases drawing))]
    ++ [Polyline (solid (Colour "#343d36") 1.15) [a, b] | (a, b) <- bookContours drawing]

ccw :: [V2] -> [V2]
ccw ring = if signedArea ring < 0 then reverse ring else ring
