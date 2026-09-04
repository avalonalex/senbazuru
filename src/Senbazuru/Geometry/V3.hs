-- |
-- Module      : Senbazuru.Geometry.V3
-- Description : Points in space, and the little algebra a camera needs.
--
-- Kept apart from "Senbazuru.Geometry", which is deliberately 2D. The
-- arithmetic both types share lives in "Senbazuru.Geometry.VectorSpace", so
-- @^+^@, @dot@ and friends work here through the instance below and mean the
-- same thing in either dimension.
--
-- What remains here is what does not generalise: the type itself, and the cross
-- product.
module Senbazuru.Geometry.V3
  ( V3 (..),
    cross,
  )
where

import Senbazuru.Geometry.VectorSpace

-- | A point, or a displacement, in space.
data V3 = V3
  { v3x :: !Double,
    v3y :: !Double,
    v3z :: !Double
  }
  deriving stock (Eq, Show)

instance VectorSpace V3 where
  V3 ax ay az ^+^ V3 bx by bz = V3 (ax + bx) (ay + by) (az + bz)
  V3 ax ay az ^-^ V3 bx by bz = V3 (ax - bx) (ay - by) (az - bz)
  k *^ V3 x y z = V3 (k * x) (k * y) (k * z)
  dot (V3 ax ay az) (V3 bx by bz) = ax * bx + ay * by + az * bz

-- | The vector product: perpendicular to both arguments, with length zero
-- exactly when they are parallel.
--
-- Not a 'VectorSpace' method, because it does not generalise. The 2D analogue
-- @ax*by - ay*bx@ returns a scalar rather than a vector, so the two have
-- different types and no class can cover both.
--
-- The degenerate case is not a curiosity here. It is how a caller discovers
-- that a view direction is parallel to its \"up\" vector, which does not
-- determine a viewing basis — see "Senbazuru.Render.Camera".
cross :: V3 -> V3 -> V3
cross (V3 ax ay az) (V3 bx by bz) =
  V3 (ay * bz - az * by) (az * bx - ax * bz) (ax * by - ay * bx)
