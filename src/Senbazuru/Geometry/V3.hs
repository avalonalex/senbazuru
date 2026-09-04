-- |
-- Module      : Senbazuru.Geometry.V3
-- Description : Points in space, and the little algebra a camera needs.
--
-- Kept apart from "Senbazuru.Geometry", which is deliberately 2D. Only the
-- operations a viewing basis actually requires live here; this is not a general
-- linear algebra library and should not grow into one.
--
-- == Why named functions instead of operators
--
-- "Senbazuru.Geometry" already exports @^+^@, @^-^@ and @*^@ for its 2D point
-- type. Defining
-- the same operators for 'V3' would collide the moment a module imported both
-- unqualified, which the renderer does. The usual fix is a @VectorSpace@ class
-- over both types; that is a fair amount of machinery for six functions, so the
-- verbose names are the deliberate trade.
module Senbazuru.Geometry.V3
  ( V3 (..),
    addV3,
    subV3,
    scaleV3,
    dotV3,
    crossV3,
    normV3,
    normalizeV3,
  )
where

-- | A point, or a displacement, in space.
data V3 = V3
  { v3x :: !Double,
    v3y :: !Double,
    v3z :: !Double
  }
  deriving stock (Eq, Show)

-- | Componentwise addition.
addV3 :: V3 -> V3 -> V3
addV3 (V3 ax ay az) (V3 bx by bz) = V3 (ax + bx) (ay + by) (az + bz)

-- | Componentwise subtraction.
subV3 :: V3 -> V3 -> V3
subV3 (V3 ax ay az) (V3 bx by bz) = V3 (ax - bx) (ay - by) (az - bz)

-- | Scale by a number.
scaleV3 :: Double -> V3 -> V3
scaleV3 k (V3 x y z) = V3 (k * x) (k * y) (k * z)

-- | The scalar product. Geometrically, how far @a@ reaches along @b@ when @b@
-- is a unit vector — which is exactly what projecting onto an axis means, and
-- the only reason this module exists.
dotV3 :: V3 -> V3 -> Double
dotV3 (V3 ax ay az) (V3 bx by bz) = ax * bx + ay * by + az * bz

-- | The vector product: a vector perpendicular to both arguments, whose length
-- is zero exactly when they are parallel.
--
-- That degenerate case is not a curiosity here. It is how a caller discovers
-- that a requested view direction is parallel to its "up" vector, which does
-- not determine a viewing basis — see "Senbazuru.Render.Camera".
crossV3 :: V3 -> V3 -> V3
crossV3 (V3 ax ay az) (V3 bx by bz) =
  V3 (ay * bz - az * by) (az * bx - ax * bz) (ax * by - ay * bx)

-- | Euclidean length.
normV3 :: V3 -> Double
normV3 v = sqrt (dotV3 v v)

-- | Scale to unit length. 'Nothing' for the zero vector, which has no
-- direction to preserve.
normalizeV3 :: V3 -> Maybe V3
normalizeV3 v
  | n == 0 = Nothing
  | otherwise = Just (scaleV3 (1 / n) v)
  where
    n = normV3 v
