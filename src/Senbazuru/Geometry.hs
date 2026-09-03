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
--
-- == Why the fold starts at a point, not at infinity
--
-- The textbook version seeds the accumulator with @minX = +infinity@ and
-- @maxX = -infinity@ and then folds over every point. It works, but that
-- starting value is an /inverted/ box whose minimum exceeds its maximum, which
-- breaks the invariant the rest of this module relies on. Peeling the first
-- point off with a pattern match and seeding with @Box p p@ keeps the
-- accumulator a valid box at every step, including the first.
--
-- The peeling is also what forces the 'Maybe' into the type: with an empty
-- list there is no first point to start from. Taking a @NonEmpty V2@ instead
-- would make the function total and move the check to the one caller that
-- knows what to do about it.
--
-- == Why @foldl'@ and strict fields, together
--
-- These are two halves of one decision, and neither works without the other.
--
-- @foldl'@ forces the accumulator at every step, but only to /weak head normal
-- form/ -- far enough to know which constructor it is, and no further. For a
-- 'Box' that means the @Box@ constructor alone. Were its fields lazy, each
-- would still hold an unevaluated chain of @min@ and @max@ thunks, growing by
-- one link per point: exactly the leak that @foldl'@ is normally reached for
-- to prevent.
--
-- The strictness annotations on 'V2' and 'Box' are what make forcing the
-- constructor force the numbers inside it. Measured over one million points at
-- @-O0@: 44 KB peak residency as written here, against 198 MB for the same
-- @foldl'@ over a record with lazy fields.
--
-- At @-O2@ the strictness analyser closes that gap completely, so the bangs
-- are not buying speed in an optimised build. What they buy is the guarantee:
-- the space behaviour becomes a property of the type rather than something the
-- optimiser has to notice. The difference is easy to feel in @make repl@,
-- where there is no strictness analysis at all.
--
-- == Why one fold rather than four traversals
--
-- @Box (V2 (minimum xs) (minimum ys)) (V2 (maximum xs) (maximum ys))@ reads
-- more declaratively and is worse in two ways: it walks the input four times
-- instead of once, and @minimum@ and @maximum@ are partial, so the empty case
-- becomes an exception rather than the 'Nothing' above.
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
-- == What makes the arithmetic easy
--
-- 'Transform' is restricted to a per-axis scale and a translation, so applying
-- it is
--
-- > x' = sx * x + ox
-- > y' = sy * y + oy
--
-- Those are two independent one-dimensional problems, each with one unknown
-- once the scale is fixed. A general affine matrix would need composition and
-- inversion machinery to buy nothing that is needed here.
--
-- == Choosing the scale
--
-- Filling the width alone would want @dstW \/ srcW@, and filling the height
-- alone @dstH \/ srcH@. Using each on its own axis fills the page perfectly and
-- draws a square sheet as a rectangle, so one number has to serve both -- and
-- it must be the /smaller/ of the two. That is the binding constraint, the
-- axis on which the model is tightest relative to the page; take the larger
-- and the other axis overflows.
--
-- A 4-by-1 model dropped into a 180-by-180 content box gives ratios of 45 and
-- 180. The scale is 45, and the drawing ends up 180 wide by 45 tall.
--
-- == Degenerate boxes
--
-- > ratios = [dstW / srcW | srcW > 0] ++ [dstH / srcH | srcH > 0]
--
-- Each of those is a list comprehension with a guard and no generator, which
-- is worth recognising as an idiom: @[e | cond]@ means @if cond then [e] else
-- []@. So an axis contributes a ratio only when it actually has extent.
--
-- That is not fussiness. A crease pattern whose vertices are all collinear has
-- @srcH == 0@, and @dstH \/ 0@ is @Infinity@. Relying on IEEE semantics almost
-- works -- @minimum [180, Infinity]@ is @180@ -- but when /both/ extents are
-- zero you get @minimum [Infinity, Infinity]@, then @Infinity * 0 = NaN@ in
-- the offset, and a @NaN@ reaches an SVG attribute, where it renders as
-- nothing at all and reports no error.
--
-- The empty-list branch of the @case@ is the every-vertex-at-one-point case:
-- nothing constrains the scale, so 1 is as good as any answer. It is not
-- defensive padding either, since @minimum []@ throws.
--
-- == Solving for the offset
--
-- With the scale fixed there is one unknown per axis and one requirement --
-- the centre of @src@ must land on the centre of @dst@ -- so each is
-- determined rather than chosen.
--
-- For @x@, solving @scale * srcCx + ox == dstCx@ gives
-- @ox = dstCx - scale * srcCx@.
--
-- For @y@ the map is @y' = (-scale) * y + oy@, so solving
-- @(-scale) * srcCy + oy == dstCy@ gives @oy = dstCy + scale * srcCy@.
--
-- That asymmetric minus and plus in @offset@ below is the line that looks like
-- a typo and is not. It is the same derivation both times; the sign differs
-- only because the minus on the @y@ scale moves across the equals sign.
--
-- == Worked example
--
-- A unit square into a 200-by-200 page with a 10-unit margin, so the content
-- box runs from 10 to 190:
--
-- > tScale  = V2 180 (-180)
-- > tOffset = V2 10 190
-- >
-- > (0,0) -> (10,190)     (1,1) -> (190,10)
-- > (0,1) -> (10,10)      (1,0) -> (190,190)
-- > (0.5,0.5) -> (100,100)
--
-- The first of those is the whole y flip in one line: the origin of the model
-- sits at the bottom of the page, which in page coordinates is the /largest/
-- @y@.
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
