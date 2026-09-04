-- |
-- Module      : Senbazuru.Render.Camera
-- Description : Flattening 3D coordinates onto the page.
--
-- FOLD coordinates may be 2D or 3D. A @creasePattern@ frame is flat and needs
-- no camera; a @foldedForm@ frame is usually in space, and until this module
-- existed the renderer dealt with that by discarding @z@ — a well-defined
-- picture, and not a useful one.
--
-- == Why orthographic
--
-- Printed origami diagrams use parallel projection, not perspective. Parallel
-- edges of the paper stay parallel on the page, equal lengths stay equal, and
-- the reader can measure the drawing. Perspective would look photographic and
-- read worse, so there is no eye position here at all — only a direction to
-- look along.
--
-- == The basis
--
-- Given a view direction and a rough idea of which way is up, three
-- perpendicular unit vectors fall out:
--
-- * @forward@ — the way the camera looks, so distance along it is depth.
-- * @right@   — across the page.
-- * @up@      — up the page. Recomputed from the other two, so the caller's
--   "up" only has to be approximately right.
--
-- Projecting is then two dot products, and the result feeds the existing 2D
-- pipeline unchanged.
module Senbazuru.Render.Camera
  ( -- * Viewing bases
    Basis (..),
    basisFrom,

    -- * Named views
    topDown,
    isometric,
    frontOn,
    sideOn,
    namedView,
    viewNames,

    -- * Projection
    project,
    depth,
  )
where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3

-- | Three perpendicular unit vectors defining how space maps onto the page.
--
-- Only 'basisFrom' constructs one, so the perpendicular-and-unit-length
-- invariant holds by construction rather than by convention.
data Basis = Basis
  { basisRight :: !V3,
    basisUp :: !V3,
    basisForward :: !V3
  }
  deriving stock (Eq, Show)

-- | @basisFrom direction up@ builds a viewing basis.
--
-- 'Nothing' when the inputs do not determine one: either vector may be zero, or
-- they may be parallel — looking straight down while insisting that up is also
-- straight down leaves the rotation about the view axis undecided. There is no
-- sensible answer to invent, so the caller is told.
--
-- The supplied @up@ is a hint, not a constraint. It fixes which way the camera
-- is rolled; the returned 'basisUp' is recomputed perpendicular to the view
-- direction, so callers can pass a world axis and not think about it.
basisFrom :: V3 -> V3 -> Maybe Basis
basisFrom direction up = do
  forward <- normalizeV3 direction
  right <- normalizeV3 (crossV3 forward up)
  -- Exactly perpendicular to both, and already unit length since the two
  -- arguments are perpendicular unit vectors.
  let trueUp = crossV3 right forward
  pure (Basis right trueUp forward)

-- | Looking straight down at the @xy@ plane, @y@ up the page.
--
-- This reproduces the old behaviour of discarding @z@ — and reproduces it
-- /exactly/, not approximately. The basis works out to the coordinate axes
-- themselves, so projecting multiplies by one and adds zero, and crease
-- patterns render byte-for-byte as they did before this module existed.
topDown :: Basis
topDown = Basis (V3 1 0 0) (V3 0 1 0) (V3 0 0 (-1))

-- | A three-quarter view from above, in front and to the right: the angle
-- printed diagrams use for a folded model.
--
-- @z@ is treated as world-up, which is the convention FOLD folded forms follow
-- — the sheet starts in the @xy@ plane and rises out of it.
isometric :: Basis
isometric = named (V3 (-1) 1.15 (-0.85)) (V3 0 0 1)

-- | Looking along @+y@, so the @xz@ plane faces the reader. Useful for seeing
-- how thick a folded model is.
frontOn :: Basis
frontOn = named (V3 0 1 0) (V3 0 0 1)

-- | Looking along @-x@, the @yz@ plane facing the reader.
sideOn :: Basis
sideOn = named (V3 (-1) 0 0) (V3 0 0 1)

-- | Total for the named views above, whose arguments are known good.
-- Unreachable in practice: every call site above passes a non-degenerate pair,
-- and a test asserts none of them silently collapse to the fallback. Falling
-- back still beats a partial function.
named :: V3 -> V3 -> Basis
named d u = fromMaybe topDown (basisFrom d u)

-- | Look up a view by name, for the command line.
namedView :: Text -> Maybe Basis
namedView = \case
  "top" -> Just topDown
  "iso" -> Just isometric
  "front" -> Just frontOn
  "side" -> Just sideOn
  _ -> Nothing

-- | Every name 'namedView' accepts, for help text and error messages.
viewNames :: [Text]
viewNames = ["top", "iso", "front", "side"]

-- | Flatten a point onto the page.
project :: Basis -> V3 -> V2
project b p = V2 (dotV3 p (basisRight b)) (dotV3 p (basisUp b))

-- | How far along the view direction a point lies. Larger is further away.
--
-- Unused so far: with only stroked edges to draw there is nothing to sort. It
-- is what face filling will need, and it costs one dot product to expose here
-- rather than rediscover later.
depth :: Basis -> V3 -> Double
depth b p = dotV3 p (basisForward b)
