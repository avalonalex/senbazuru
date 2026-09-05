-- |
-- Module      : Senbazuru.Geometry
-- Description : Points, axis-aligned boxes, and the model-to-page transform.
--
-- Everything in this module is plain 2D Euclidean geometry with 'Double'
-- coordinates. It deliberately does not depend on FOLD or on SVG, so it can be
-- property-tested on its own.
--
-- == The two coordinate systems
--
-- There are two spaces in play, and mixing them up is the single most common
-- bug in any renderer:
--
-- * __Model space__ — the coordinates stored in the FOLD file. Mathematical
--   convention: @y@ increases /upwards/. A unit square is typically
--   @(0,0)@ to @(1,1)@.
--
-- * __Page space__ — SVG user units. Screen convention: @y@ increases
--   /downwards/, and the origin is the top-left of the canvas.
--
-- A 'Transform' converts the first into the second. Because the @y@ axes point
-- in opposite directions, that transform always has a negative @y@ scale.
module Senbazuru.Geometry
  ( -- * Points and vectors
    V2 (..),
    -- | Arithmetic comes from 'VectorSpace', shared with
    -- "Senbazuru.Geometry.V3", and is re-exported here so importing this
    -- module is enough to work with 'V2'.
    module Senbazuru.Geometry.VectorSpace,
    perpendicular,

    -- * Axis-aligned bounding boxes
    Box (..),
    boxFromPoints,
    boxSize,
    boxCentre,
    padBox,
    boxContains,

    -- * Model-to-page transforms
    Transform (..),
    applyTransform,
    fitBox,
  )
where

import Data.List (foldl')
import Senbazuru.Geometry.VectorSpace

-- | A point, or equivalently a displacement, in the plane.
--
-- The fields are strict so that a list of a few thousand vertices does not
-- accumulate thunks; the whole pipeline forces them eventually anyway.
data V2 = V2
  { v2x :: !Double,
    v2y :: !Double
  }
  deriving stock (Eq, Show)

instance VectorSpace V2 where
  V2 ax ay ^+^ V2 bx by = V2 (ax + bx) (ay + by)
  V2 ax ay ^-^ V2 bx by = V2 (ax - bx) (ay - by)
  k *^ V2 x y = V2 (k * x) (k * y)
  dot (V2 ax ay) (V2 bx by) = ax * bx + ay * by

-- | An axis-aligned rectangle, given by two opposite corners.
--
-- The invariant is @boxMin <= boxMax@ componentwise. Every constructor in this
-- module establishes it; if you build a 'Box' by hand, you are on your own.
data Box = Box
  { boxMin :: !V2,
    boxMax :: !V2
  }
  deriving stock (Eq, Show)

-- | The tightest axis-aligned box containing every given point: all of them
-- inside, boundary included, and each of the four sides touched by at least
-- one point.
--
-- \"Axis-aligned\" is load-bearing. Let the rectangle rotate and this becomes
-- the /minimum-area enclosing rectangle/, a harder problem needing a convex
-- hull and rotating calipers, whose answer is often strictly smaller.
--
-- 'Nothing' for an empty list: a FOLD file with no @vertices_coords@ is legal
-- and has no sensible box. Seeding the fold from the first point is what forces
-- that case into the type, and it keeps the accumulator a valid box at every
-- step -- the textbook @+infinity@ seed is an inverted box that breaks the
-- invariant.
--
-- The strict fields on 'V2' and 'Box' are load-bearing too. @foldl'@ forces
-- only to weak head normal form, so with lazy fields this would still pile up
-- @min@ and @max@ thunks. See @docs\/notes\/strict-fields.md@ for the numbers
-- and @docs\/notes\/folds.md@ for @foldl@ versus @foldl'@ generally.
boxFromPoints :: [V2] -> Maybe Box
boxFromPoints [] = Nothing
boxFromPoints (p : ps) = Just (foldl' grow (Box p p) ps)
  where
    -- Widen each of the four bounds outward, just far enough to admit the new
    -- point. It never shrinks: if the point is already inside, every min and
    -- max keeps the bound it had. The four bounds do not interact, which is
    -- what makes one pass enough.
    grow (Box (V2 minX minY) (V2 maxX maxY)) (V2 x y) =
      Box (V2 (min minX x) (min minY y)) (V2 (max maxX x) (max maxY y))

-- | Width and height, packed into a 'V2'. Never negative, given the invariant.
boxSize :: Box -> V2
boxSize (Box lo hi) = hi ^-^ lo

-- | The midpoint of the box.
boxCentre :: Box -> V2
boxCentre (Box lo hi) = lo ^+^ (0.5 *^ (hi ^-^ lo))

-- | Grow a box by the same amount on all four sides.
padBox :: Double -> Box -> Box
padBox d (Box lo hi) = Box (lo ^-^ V2 d d) (hi ^+^ V2 d d)

-- | Is the point inside the box, boundary included?
boxContains :: Box -> V2 -> Bool
boxContains (Box (V2 lo'x lo'y) (V2 hi'x hi'y)) (V2 x y) =
  x >= lo'x && x <= hi'x && y >= lo'y && y <= hi'y

-- | An affine map restricted to a per-axis scale followed by a translation.
--
-- This is deliberately /not/ a general affine matrix. A viewport only ever
-- needs scale-and-shift, and the restricted form keeps 'fitBox' easy to reason
-- about. Rotation can be added when a feature actually needs it.
data Transform = Transform
  { tScale :: !V2,
    tOffset :: !V2
  }
  deriving stock (Eq, Show)

-- | Apply a transform to a point.
applyTransform :: Transform -> V2 -> V2
applyTransform (Transform (V2 sx sy) (V2 ox oy)) (V2 x y) =
  V2 (sx * x + ox) (sy * y + oy)

-- | @fitBox src dst@ builds the transform that maps model-space box @src@ into
-- page-space box @dst@.
--
-- Three decisions:
--
-- 1. __Uniform scale__, so a square sheet stays square. One factor serves both
--    axes, and it must be the /smaller/ of @dstW \/ srcW@ and @dstH \/ srcH@ --
--    the binding constraint. Take the larger and the other axis overflows.
--
-- 2. __Centring.__ A uniform scale generally cannot fill both axes, so the
--    leftover slack is split evenly.
--
-- 3. __Y flip.__ Model @y@ increases upwards and SVG @y@ downwards, hence the
--    negated @y@ scale.
--
-- 'Transform' is only a per-axis scale and a translation, so applying it is
-- @x' = sx*x + ox@ and @y' = sy*y + oy@: two independent one-dimensional
-- problems. Requiring the centre of @src@ to land on the centre of @dst@ then
-- determines the offset outright, one equation per axis:
--
-- >    scale  * srcCx + ox == dstCx   =>   ox = dstCx - scale * srcCx
-- > (-scale) * srcCy + oy == dstCy   =>   oy = dstCy + scale * srcCy
--
-- The asymmetric minus and plus below reads as a typo and is not. Same
-- derivation both times; the sign differs only because the minus on the @y@
-- scale crosses the equals sign.
--
-- Degenerate axes are filtered out rather than divided by. A collinear crease
-- pattern has zero height, and while @minimum [180, Infinity]@ happens to give
-- the right answer, /two/ zero extents give @Infinity * 0 = NaN@ in the offset
-- -- and a @NaN@ reaches an SVG attribute, where it draws nothing and reports
-- no error.
--
-- A unit square onto a 200-by-200 page with a 10-unit margin (content box 10
-- to 190):
--
-- > (0,0) -> (10,190)    (1,1) -> (190,10)    (0.5,0.5) -> (100,100)
--
-- The first is the y flip in one line: the origin of the model sits at the
-- bottom of the page, which in page coordinates is the /largest/ @y@.
fitBox :: Box -> Box -> Transform
fitBox src dst = Transform (V2 scale (negate scale)) offset
  where
    V2 srcW srcH = boxSize src
    V2 dstW dstH = boxSize dst

    -- List comprehensions with a boolean guard and no generator act as a
    -- filter: the element is included only when the guard holds.
    ratios :: [Double]
    ratios = [dstW / srcW | srcW > 0] ++ [dstH / srcH | srcH > 0]

    scale = case ratios of
      [] -> 1
      rs -> minimum rs

    V2 srcCx srcCy = boxCentre src
    V2 dstCx dstCy = boxCentre dst

    -- Chosen so that the centre of src lands exactly on the centre of dst.
    -- Note the sign flip on the y term, matching the negated y scale.
    offset = V2 (dstCx - scale * srcCx) (dstCy + scale * srcCy)

-- | A quarter turn anticlockwise in the plane.
--
-- Small enough to be worth writing twice and therefore worth writing once: an
-- arrowhead needs it to put its base corners either side of its axis, and an
-- arrow needs it to decide which way to bow. The two had drifted into separate
-- copies in two modules before this existed.
perpendicular :: V2 -> V2
perpendicular (V2 x y) = V2 (negate y) x
