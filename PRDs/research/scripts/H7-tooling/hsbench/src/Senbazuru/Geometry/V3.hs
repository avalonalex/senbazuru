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
    spanAlong,
    modelSpan,
    hasRelief,
    polygonNormal,
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

-- | How far a set of points is spread along one axis.
--
-- One implementation, because \"how big is this?\" is asked by several callers
-- with different policies about which axes count, and a second copy of the
-- arithmetic is how two of them come to disagree.
spanAlong :: (V3 -> Double) -> [V3] -> Double
spanAlong f verts = case map f verts of
  [] -> 0
  cs -> maximum cs - minimum cs

-- | How far a set of points is spread along @z@.
zSpan :: [V3] -> Double
zSpan = spanAlong v3z

-- | The largest spread along any axis: how big the thing is, roughly.
--
-- The measure to compare a distance against when asking whether it is
-- significant, since \"small\" only means anything next to something else.
modelSpan :: [V3] -> Double
modelSpan verts = maximum [0, spanAlong v3x verts, spanAlong v3y verts, spanAlong v3z verts]

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
    -- Deliberately the spread across the plane and not 'modelSpan': the
    -- question is whether the relief is small next to the /sheet/, and folding
    -- the sheet in half out of the plane must not make its own relief look
    -- negligible by growing the yardstick.
    planeSpan = max (spanAlong v3x verts) (spanAlong v3y verts)

-- | Which way a polygon faces, from the order its corners are listed in.
--
-- Counterclockwise as seen from the tip of the result, by the right-hand rule:
-- a square listed counterclockwise in the plane @z = 0@ gives @+z@. Listing the
-- same square backwards gives @-z@, which is the whole point — this is a
-- question about the /order/, not about the shape.
--
-- The length is twice the polygon's area, which is useful for spotting a
-- degenerate face and is why the result is left unnormalised.
--
-- Newell's method, rather than the cross product of two edges. For a triangle
-- they agree; for anything else the cross product picks two edges arbitrarily
-- and gets a wrong answer on a polygon that is not quite planar, which a folded
-- form's faces routinely are not once rounding has been through them. Newell's
-- averages over every edge instead, and reduces to the cross product when the
-- polygon really is flat.
polygonNormal :: [V3] -> V3
polygonNormal corners = foldr add (V3 0 0 0) (zip corners (drop 1 corners <> take 1 corners))
  where
    add (V3 xi yi zi, V3 xj yj zj) (V3 nx ny nz) =
      V3
        (nx + (yi - yj) * (zi + zj))
        (ny + (zi - zj) * (xi + xj))
        (nz + (xi - xj) * (yi + yj))
