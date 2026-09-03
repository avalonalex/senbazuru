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
    (^+^),
    (^-^),
    (*^),

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

-- | A point, or equivalently a displacement, in the plane.
--
-- The fields are strict so that a list of a few thousand vertices does not
-- accumulate thunks; the whole pipeline forces them eventually anyway.
data V2 = V2
  { v2x :: !Double,
    v2y :: !Double
  }
  deriving stock (Eq, Show)

infixl 6 ^+^, ^-^

infixl 7 *^

-- | Componentwise addition.
(^+^) :: V2 -> V2 -> V2
V2 ax ay ^+^ V2 bx by = V2 (ax + bx) (ay + by)

-- | Componentwise subtraction.
(^-^) :: V2 -> V2 -> V2
V2 ax ay ^-^ V2 bx by = V2 (ax - bx) (ay - by)

-- | Scale a vector by a number.
(*^) :: Double -> V2 -> V2
k *^ V2 x y = V2 (k * x) (k * y)

-- | An axis-aligned rectangle, given by two opposite corners.
--
-- The invariant is @boxMin <= boxMax@ componentwise. Every constructor in this
-- module establishes it; if you build a 'Box' by hand, you are on your own.
data Box = Box
  { boxMin :: !V2,
    boxMax :: !V2
  }
  deriving stock (Eq, Show)

-- | The tightest box containing every given point.
--
-- Returns 'Nothing' for an empty list. That is not pedantry: a FOLD file with
-- no @vertices_coords@ is legal, and there is genuinely no sensible box for it.
-- Making the caller handle the case is cheaper than debugging an @infinity@
-- that has leaked into an SVG @viewBox@.
boxFromPoints :: [V2] -> Maybe Box
boxFromPoints [] = Nothing
boxFromPoints (p : ps) = Just (foldl' grow (Box p p) ps)
  where
    grow (Box (V2 lo'x lo'y) (V2 hi'x hi'y)) (V2 x y) =
      Box (V2 (min lo'x x) (min lo'y y)) (V2 (max hi'x x) (max hi'y y))

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
-- Three things happen at once, and each is a decision:
--
-- 1. __Uniform scale.__ The same factor is used for @x@ and @y@, so a square
--    sheet of paper stays square. Anything else would distort the model.
--
-- 2. __Centring.__ Since the scale is uniform, @src@ generally cannot fill
--    @dst@ exactly; the leftover slack is split evenly, so the drawing sits in
--    the middle of the page.
--
-- 3. __Y flip.__ The @y@ scale is negated to convert mathematical @y@-up
--    coordinates into SVG @y@-down ones.
--
-- Degenerate inputs are handled rather than avoided. A crease pattern whose
-- vertices are all collinear has a zero-height box; dividing by that height
-- would give an infinite scale, so a zero-extent axis simply does not
-- constrain the fit. If /both/ axes are degenerate (every vertex at the same
-- point) the scale falls back to 1.
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
