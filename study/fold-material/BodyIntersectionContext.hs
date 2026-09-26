-- | Locate a saved intersection in the camera's visible paper. A triangle
-- intersection is a 3D segment; its drawing can be hidden by a third layer.
-- Clip the WHOLE projected segment, not just its midpoint, against the convex
-- visible pieces. The returned intervals measure how much is covered without
-- counting overlapping pieces twice. This is a drawing audit, not a contact
-- waiver. Edge-on segments and planes have no useful depth test here.
module BodyIntersectionContext (segmentInterval, coveredFraction, positiveDepthInterval, planeDepth) where

import Data.List (foldl', sort)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (clipSegment, signedArea)
import Senbazuru.Geometry.V3 (V3, polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Render.Camera (Basis, basisForward, basisRight, basisUp)

-- | Parameters along the segment (0 at its start, 1 at its end). A point-only
-- touch contributes no length. Rings from visibility are convex but their
-- winding may reverse when projected from below; clipSegment needs anticlockwise.
segmentInterval :: (V2, V2) -> [V2] -> Maybe (Double, Double)
segmentInterval (a, b) ring
  | normSquared == 0 || length ring < 3 || signedArea ring == 0 = Nothing
  | otherwise = do
      (p, q) <- clipSegment (if signedArea ring > 0 then ring else reverse ring) (a, b)
      let t v = max 0 (min 1 (dot (v ^-^ a) delta / normSquared))
          lo = t p
          hi = t q
      if hi > lo then Just (lo, hi) else Nothing
  where
    delta = b ^-^ a
    normSquared = dot delta delta

-- | Length of the union in [0,1]. Do not sum fragments: nearly coincident
-- visibility boundaries can contribute the same segment more than once.
coveredFraction :: [(Double, Double)] -> Double
coveredFraction intervals = total + max 0 (end - start)
  where
    valid = sort [(max 0 a, min 1 b) | (a, b) <- intervals, min 1 b > max 0 a]
    (total, start, end) = foldl' add (0, 0, 0) valid
    add (amount, lo, hi) (a, b)
      | a <= hi = (amount, lo, max hi b)
      | otherwise = (amount + hi - lo, a, b)

-- | Keep the part where a linear depth margin is positive. Margins belong to
-- the ends of the supplied interval, not necessarily the whole segment. A
-- tiny wrong-side endpoint must not be counted as geometrically hidden merely
-- because the midpoint is in front. Zero-width remnants contribute no length.
positiveDepthInterval :: (Double, Double) -> (Double, Double) -> Maybe (Double, Double)
positiveDepthInterval interval@(lo, hi) (a, b)
  | hi <= lo || max a b <= 0 = Nothing
  | min a b >= 0 = Just interval
  | a > 0 = Just (lo, crossing)
  | otherwise = Just (crossing, hi)
  where
    crossing = lo + (hi - lo) * a / (a - b)

-- | Actual depth on the original triangle plane, not on the camera-plane
-- polygons returned by visibility. Smaller depth is nearer the viewer. For
-- planar triangles this varies linearly along a segment, so its two endpoints
-- suffice to bound the depth difference over each clipped interval.
planeDepth :: Basis -> [V3] -> V2 -> Maybe Double
planeDepth basis corners (V2 x y) = case corners of
  origin : _ -> do
    normal <- normalize (polygonNormal corners)
    let facing = dot normal (basisForward basis)
    if abs facing <= 1e-12
      then Nothing
      else Just ((dot normal origin - x * dot normal (basisRight basis) - y * dot normal (basisUp basis)) / facing)
  [] -> Nothing
