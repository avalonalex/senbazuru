-- |
-- Module      : Senbazuru.Geometry.Rigid
-- Description : Motions that move a shape without changing it.
--
-- A /rigid motion/ rotates and translates and does nothing else: no scaling, no
-- shearing, no reflection. Distances between points survive it unchanged, which
-- is the whole reason this type exists — a sheet of paper does not stretch, so
-- every face of a folded model has moved by exactly one of these.
--
-- Kept in the geometry layer, knowing nothing about origami, because none of it
-- is about paper. It is the arithmetic any 3D construction needs, and folding
-- happens to be the first caller.
--
-- == Why a matrix and an offset, rather than a 4×4
--
-- Graphics code usually writes a rigid motion as a 4×4 matrix with a row of
-- @0 0 0 1@ glued on, so that composing is one matrix multiply. That row is
-- always the same, and carrying it means every reader has to remember which
-- convention (row-major or column-major, points as rows or columns) is in play
-- before they can tell a translation from a projection. Storing the 3×3 and the
-- offset separately makes 'after' four lines of visible arithmetic instead, and
-- removes the one row that could turn a motion into a projection.
--
-- It does not make a non-rigid value unwriteable — 'Rigid' will hold any 3×3
-- matrix, including one that scales — and nothing here checks. What keeps the
-- type honest is that 'rotationAbout' is the only way anything constructs one.
module Senbazuru.Geometry.Rigid
  ( -- * Matrices
    Mat3 (..),
    matApply,
    matMul,
    matIdentity,

    -- * Rigid motions
    Rigid (..),
    identity,
    after,
    applyRigid,
    rotationAbout,
  )
where

import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace

-- | A 3×3 matrix, stored as its three __rows__.
--
-- Rows rather than columns so that 'matApply' reads as three dot products, one
-- per row, which is what the arithmetic on paper looks like.
data Mat3 = Mat3 !V3 !V3 !V3
  deriving stock (Eq, Show)

matIdentity :: Mat3
matIdentity = Mat3 (V3 1 0 0) (V3 0 1 0) (V3 0 0 1)

-- | Apply a matrix to a column vector.
matApply :: Mat3 -> V3 -> V3
matApply (Mat3 r0 r1 r2) v = V3 (dot r0 v) (dot r1 v) (dot r2 v)

-- | Matrix product. @matMul a b@ applies @b@ first, as the notation @a · b@
-- does.
matMul :: Mat3 -> Mat3 -> Mat3
matMul (Mat3 r0 r1 r2) b = Mat3 (row r0) (row r1) (row r2)
  where
    -- Entry (i, j) is row i of a dotted with column j of b, and b's columns are
    -- the rows of its transpose.
    Mat3 c0 c1 c2 = transpose b
    row r = V3 (dot r c0) (dot r c1) (dot r c2)

transpose :: Mat3 -> Mat3
transpose (Mat3 (V3 a b c) (V3 d e f) (V3 g h i)) =
  Mat3 (V3 a d g) (V3 b e h) (V3 c f i)

-- | A rotation (or any linear part) followed by a translation: @x ↦ M x + t@.
data Rigid = Rigid
  { rigidLinear :: !Mat3,
    rigidOffset :: !V3
  }
  deriving stock (Eq, Show)

-- | The motion that does nothing.
identity :: Rigid
identity = Rigid matIdentity (V3 0 0 0)

-- | Move a point.
applyRigid :: Rigid -> V3 -> V3
applyRigid (Rigid m t) v = matApply m v ^+^ t

-- | @a \`after\` b@ does @b@ first and then @a@.
--
-- The same order as function composition and as the matrix notation @a · b@, so
-- that the folding rule @M[child] = M[parent] · R@ transcribes directly as
-- @mParent \`after\` r@ with nothing to reverse in your head.
after :: Rigid -> Rigid -> Rigid
after (Rigid ma ta) (Rigid mb tb) =
  -- a(b(x)) = Ma (Mb x + tb) + ta = (Ma Mb) x + (Ma tb + ta)
  Rigid (matMul ma mb) (matApply ma tb ^+^ ta)

-- | Turn about the line through a point along an axis, by an angle in radians.
--
-- Positive angles follow the right-hand rule: with the thumb along the axis,
-- the fingers curl the way things turn.
--
-- The axis is normalised here rather than being demanded of the caller, and a
-- zero-length or non-finite one yields 'identity'. Turning about nothing is a
-- reasonable thing to ask for and a bad thing to answer with a matrix full of
-- @NaN@, which is what the formula below produces if it is handed one.
--
-- The rotation is Rodrigues' formula, written out as a matrix. Applying it to a
-- point off the axis needs the usual sandwich — translate the axis to the
-- origin, turn, translate back — which is where the offset comes from:
-- @x ↦ p + R (x − p)@ is the same map as @x ↦ R x + (p − R p)@.
rotationAbout :: V3 -> V3 -> Double -> Rigid
rotationAbout p axis theta = case normalize axis of
  Nothing -> identity
  Just u -> Rigid (rot u) (p ^-^ matApply (rot u) p)
  where
    c = cos theta
    s = sin theta
    t = 1 - c

    -- R = I cos θ + [u]× sin θ + (u ⊗ u)(1 − cos θ), with [u]× the matrix that
    -- performs `cross u` and (u ⊗ u) the outer product.
    rot (V3 x y z) =
      Mat3
        (V3 (t * x * x + c) (t * x * y - s * z) (t * x * z + s * y))
        (V3 (t * x * y + s * z) (t * y * y + c) (t * y * z - s * x))
        (V3 (t * x * z - s * y) (t * y * z + s * x) (t * z * z + c))
