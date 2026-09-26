-- | Locate order errors on a saved sheet, without moving it. A contact polygon
-- is the overlap of two triangles when viewed along their declared contact
-- direction. Each corner has a signed gap: negative means the required upper
-- layer lies below the lower one. The gap varies linearly across this polygon.
--
-- Clipping at a chosen negative gap locates the affected region, rather than
-- confusing its depth with its area. We keep positions on the lower triangle;
-- this is a geometric diagnostic, including buried paper, not a visible-colour
-- mask. A broad region can have an arbitrarily small negative gap.
module IllustrationTolerance (negativeRegion, projectedArea, projectedDiameter) where

import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.Polygon (signedArea)
import Senbazuru.Geometry.V3 (V3)
import Senbazuru.Geometry.VectorSpace

-- | Nonnegative distance allowance, then cyclic (position, signed gap) corners.
-- Only the part STRICTLY below minus the allowance is relevant. Boundary
-- corners are retained when adjoining a violating part, keeping its area.
negativeRegion :: Double -> [(V3, Double)] -> [V3]
negativeRegion allowance corners
  | not (any ((< negate allowance) . snd) corners) = []
  | otherwise = concatMap clip (zip corners (drop 1 corners ++ take 1 corners))
  where
    inside (_, gap) = gap <= negate allowance
    crossing (p, a) (q, b) = p ^+^ ((negate allowance - a) / (b - a)) *^ (q ^-^ p)
    clip (a, b) = case (inside a, inside b) of
      (True, True) -> [fst b]
      (True, False) -> [crossing a b]
      (False, True) -> [crossing a b, fst b]
      (False, False) -> []

projectedArea :: [V2] -> Double
projectedArea = abs . signedArea

-- | A conservative size of the projected patch, including hidden material.
-- It does not estimate whether a human sees a colour change there.
projectedDiameter :: [V2] -> Double
projectedDiameter ring = maximum (0 : [norm (a ^-^ b) | a <- ring, b <- ring])
