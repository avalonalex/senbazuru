-- |
-- Module      : Senbazuru.Geometry.V3
-- Description : Points in space, and the little algebra a camera needs.
--
-- Kept apart from "Senbazuru.Geometry", which is deliberately 2D. The
-- arithmetic both types share lives in "Senbazuru.Geometry.VectorSpace", so
-- @^+^@, @dot@ and friends work here through the instance below and mean the
-- same thing in either dimension.
--
-- What remains here is what does not generalise: the type itself, the cross
-- product, and the question of whether a set of points is flat — which only
-- makes sense once there is a third dimension to be flat in.
module Senbazuru.Geometry.V3
  ( V3 (..),
    cross,
    zSpan,
    hasRelief,
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

-- | How far a set of points is spread along @z@.
zSpan :: [V3] -> Double
zSpan verts = case map v3z verts of
  [] -> 0
  zs -> maximum zs - minimum zs

-- | Does the geometry leave the plane?
--
-- Judged relative to the points' own size, since \"small\" only means anything
-- next to something else. A drawing a thousand units wide with a thousandth of
-- a unit of relief is flat; one a thousandth of a unit wide with the same
-- relief is not. No points at all counts as flat, so that callers can go on to
-- fail with the error that actually describes the problem.
--
-- Lives here, rather than next to either of its callers, because both
-- "Senbazuru.Render.CreasePattern" and "Senbazuru.Origami.FlatFold" have to
-- answer /is this flat?/ and they must not be able to disagree. They did, once:
-- a second copy of this test with an absolute threshold called a 400-unit sheet
-- with 1e-8 of rounding noise a folded form while the renderer drew it happily.
hasRelief :: [V3] -> Bool
hasRelief verts = zSpan verts > 1e-9 * max 1 planeSpan
  where
    spanOf f = case map f verts of
      [] -> 0
      cs -> maximum cs - minimum cs
    planeSpan = max (spanOf v3x) (spanOf v3y)
