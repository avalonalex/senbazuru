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
-- matrix, including one that scales — and the constructor does not check.
-- What keeps the type honest is that 'rotationAbout' and 'fitRigid' are the
-- ways anything constructs one, and 'isProperRotation' is the check for a
-- matrix built any other way.
--
-- == Proper, not merely orthogonal
--
-- A /proper/ rotation turns without mirroring: its determinant is +1. A
-- mirror is orthogonal too, and folds perfectly well — into the mirror model,
-- the one whose mountains and valleys are swapped. Paper cannot make it, so a
-- motion fitted to a model's vertices is accepted only if it is proper.
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
    inverse,

    -- * Checking and fitting
    isProperRotation,
    fitRigid,
  )
where

import Data.List (maximumBy)
import Data.Maybe (fromMaybe)
import Data.Ord (comparing)
import Senbazuru.Geometry.V3 (V3 (..), cross, modelSpan)
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

-- | The motion that undoes this one: @inverse r \`after\` r@ is 'identity' to
-- within rounding.
--
-- Folding needs this to run backwards. A face of a folded model carries the
-- motion that put it there, so inverting that motion takes a point on the
-- folded paper back to the point of the flat sheet it came from — which is how
-- a line drawn on a model already folded becomes creases on its pattern.
--
-- == Why transposing is enough
--
-- Undoing @x ↦ M x + t@ means solving for @x@, which is @x ↦ M⁻¹ (x − t)@, and
-- that is @x ↦ M⁻¹ x − M⁻¹ t@. So the only hard part is @M⁻¹@ — and there is no
-- hard part, because a rotation matrix is /orthogonal/: its rows are unit
-- vectors at right angles to each other, so the matrix that undoes it is its
-- own transpose. No determinant, no division, and nothing that can be
-- ill-conditioned.
--
-- That holds because every 'Rigid' in the program is built by 'rotationAbout'
-- or composed from ones that were — the same argument the module header makes
-- for the type being honest at all. A 'Rigid' assembled by hand out of a
-- scaling matrix would come back from here with a plausible value that is not
-- an inverse, and nothing checks. If that ever becomes possible, this is the
-- function that breaks first.
--
-- The offset is written as a subtraction from zero rather than as a
-- multiplication by minus one, which would turn a zero component into a
-- negative zero. The two compare equal and print differently, and this project
-- has been caught by that before — see @formatNumber@.
inverse :: Rigid -> Rigid
inverse (Rigid m t) = Rigid mi (V3 0 0 0 ^-^ matApply mi t)
  where
    mi = transpose m

-- | Whether a matrix turns without scaling or mirroring: its rows are unit
-- vectors at right angles to each other, and its determinant is +1, each
-- within 1e-12. The determinant alone would accept @diag(2, 1\/2, 1)@, which
-- stretches; orthonormal rows alone would accept a mirror.
isProperRotation :: Mat3 -> Bool
isProperRotation (Mat3 r0 r1 r2) =
  all
    near
    [ (dot r0 r0, 1),
      (dot r1 r1, 1),
      (dot r2 r2, 1),
      (dot r0 r1, 0),
      (dot r0 r2, 0),
      (dot r1 r2, 0),
      (dot r0 (cross r1 r2), 1)
    ]
  where
    near (a, b) = abs (a - b) <= 1e-12

-- | The one rigid motion carrying each first point onto its second, if there
-- is one: every pair within @1e-9 × max 1 (modelSpan sources)@, the tolerance
-- "Senbazuru.Origami.Step" judges a moved vertex by, and the turn a proper
-- rotation. 'Nothing' if the points do not span a plane, since then no single
-- turn is pinned down, or if no rigid motion fits.
--
-- Three points fix it: @a@, the first; @b@, the one farthest from @a@; and
-- @c@, the one farthest from the line through them. Each side builds an
-- orthonormal frame from its three, its third axis the cross product of its
-- first two, and the turn takes one frame onto the other. Every pair is then
-- checked, not only those three.
--
-- __The line that looks like a typo__ is the third axis being a cross product
-- rather than the third point's own direction. On a model lying flat at
-- @z = 0@, the mirror @(x, y, z) ↦ (−x, y, z)@ and the half turn
-- @(x, y, z) ↦ (−x, y, −z)@ put every vertex in the same place, and both fit
-- every pair. The cross product picks the half turn, which is right: paper
-- cannot make the mirror. Built that way on both sides, the turn always has
-- determinant +1, so 'isProperRotation' here only catches a construction bug.
fitRigid :: [(V3, V3)] -> Maybe Rigid
fitRigid pairs = case pairs of
  [] -> Nothing
  (a, a') : _ -> do
    let sources = map fst pairs
        tol = 1e-9 * max 1 (modelSpan sources)
        (b, b') = maximumBy (comparing (\(p, _) -> norm (p ^-^ a))) pairs
    if norm (b ^-^ a) <= tol
      then Nothing
      else do
        let offLine p = norm (cross (unitOrZero (b ^-^ a)) (p ^-^ a))
            (c, c') = maximumBy (comparing (offLine . fst)) pairs
        if offLine c <= tol
          then Nothing
          else do
            let turn = matMul (columns (frame a' b' c')) (rows (frame a b c))
                motion = Rigid turn (a' ^-^ matApply turn a)
            if isProperRotation turn && all (\(p, q) -> norm (applyRigid motion p ^-^ q) <= tol) pairs
              then Just motion
              else Nothing
  where
    -- An orthonormal frame from three points: towards the second, then
    -- towards the third with the first direction taken out, then the cross
    -- product of the two.
    frame p q r =
      let e1 = unitOrZero (q ^-^ p)
          toward = r ^-^ p
          e2 = unitOrZero (toward ^-^ (dot toward e1 *^ e1))
       in (e1, e2, cross e1 e2)
    rows (e1, e2, e3) = Mat3 e1 e2 e3
    columns (e1, e2, e3) = transpose (Mat3 e1 e2 e3)
    unitOrZero v = fromMaybe (V3 0 0 0) (normalize v)
