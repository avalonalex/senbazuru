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
-- == A rotation by construction
--
-- The constructor is not exported, so nothing outside this module can put a
-- mirror or a stretch into a 'Rigid'. 'identity' and 'translation' turn
-- nothing. 'rotationAbout' and 'rotationAboutDegrees' build a turn from its
-- cosine and sine, and 'fitRigid' from two frames. 'rigidFrom', the one way
-- in for a matrix made anywhere else, admits it only if 'isProperRotation'
-- does. So code holding a 'Rigid' need not ask whether it mirrors or
-- stretches, and 'inverse' can transpose rather than invert: /parse, don't
-- validate/.
--
-- __The line that looks like an oversight__ is that 'rigidLinear' and
-- 'rigidOffset' are plain functions, not record fields. A record field that
-- is exported can be updated, @r { rigidLinear = m }@, which would make a
-- 'Rigid' out of any matrix without passing the check.
--
-- What the type does not promise is a turn to the last bit. Rounding enters
-- every entry, 'rigidFrom' admits a matrix within 1e-12, and 'after' and
-- 'inverse' add rounding of their own, so a long chain drifts: turns about
-- two axes in turn, by 1, 2, 3, … radians, are 1.4e-14 from a proper
-- rotation after a hundred and fail 'isProperRotation' after some 7,300. The
-- runner's turns, by eighths about the vertical and halves about the
-- horizontal, are the exception: composed in any order they make only 32
-- matrices, each within 4.4e-16. Nor do the rotations make a turn from every
-- input. An angle that is not finite, or that overflows in radians, as
-- degrees beyond about 5.7e307 do, gives a matrix of NaN, and an axis shorter
-- than about 1e-155, whose length squared underflows, gives one that
-- stretches.
--
-- == Turns at multiples of 45°
--
-- A turn's cosine and sine usually come from 'cos' and 'sin', whose last bits
-- are the platform's own: IEEE 754 does not require them to be /correctly
-- rounded/, the exact result rounded to the nearest 'Double', and macOS and
-- Linux differ. Nor are they exact where they could be: @sin pi@ is 1.2e-16,
-- not 0, because 'pi' is not π, so a flat fold of 180° left paper about
-- 1e-16 off its plane. 'rotationAboutDegrees' takes an angle in degrees, the
-- units a FOLD file holds, and at an exact multiple of 45° uses 0 and ±1, and
-- ±√½ as @sqrt 0.5@, which IEEE 754 does require to be correctly rounded. A
-- turn by one of those angles then takes no number from the platform's
-- trigonometry, and the matrix of one about a coordinate axis holds 0, 1,
-- cos θ and ±sin θ and nothing else.
-- @docs\/notes\/exact-turns.md@ has the measurements.
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
    Rigid,
    rigidLinear,
    rigidOffset,
    identity,
    translation,
    after,
    applyRigid,
    rotationAbout,
    rotationAboutDegrees,
    cosSinDegrees,
    inverse,

    -- * Checking and fitting
    isProperRotation,
    rigidFrom,
    fitRigid,
  )
where

import Data.List (maximumBy)
import Data.Maybe (fromMaybe)
import Data.Ord (comparing)
import Senbazuru.Geometry.V3 (V3 (..), cross, modelHair)
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

-- | A turn followed by a translation: @x ↦ M x + t@. The constructor stays in
-- this module, so that no 'Rigid' mirrors or stretches (see the module
-- header).
data Rigid = Rigid !Mat3 !V3
  deriving stock (Eq, Show)

-- | The turn, @M@.
rigidLinear :: Rigid -> Mat3
rigidLinear (Rigid m _) = m

-- | The offset, @t@: where the motion takes the origin.
rigidOffset :: Rigid -> V3
rigidOffset (Rigid _ t) = t

-- | The motion that does nothing.
identity :: Rigid
identity = Rigid matIdentity (V3 0 0 0)

-- | Move every point by the same offset, turning nothing.
translation :: V3 -> Rigid
translation = Rigid matIdentity

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
rotationAbout p axis theta = turnFrom (\x -> (1 - c) * x * x + c) c s p axis
  where
    c = cos theta
    s = sin theta

-- | 'rotationAbout' by an angle in degrees, the units a crease carries, which
-- is why folding turns by this. At an exact multiple of 45° it turns by the
-- values 'cosSinDegrees' gives, and writes each diagonal entry as
-- @x² + (1 − x²) cos θ@ rather than @(1 − cos θ) x² + cos θ@. The two are one
-- number, but @1 − cos θ@ rounds when @cos θ@ is @-sqrt 0.5@, at 135°. In
-- the first form the matrix of a turn about a coordinate axis holds 0, 1,
-- cos θ and ±sin θ and nothing else, so the turn leaves its own axis exactly
-- where it was. A point's position still rounds wherever √½ multiplies it. Any other angle turns
-- exactly as 'rotationAbout' does by @d * pi / 180@, bit for bit.
rotationAboutDegrees :: V3 -> V3 -> Double -> Rigid
rotationAboutDegrees p axis d = case eighthTurn d of
  Just (c, s) -> turnFrom (\x -> x * x + (1 - x * x) * c) c s p axis
  Nothing -> rotationAbout p axis (d * pi / 180)

-- | The cosine and sine of an angle in degrees: at an exact multiple of 45°,
-- 0 and ±1, and ±√½ as @sqrt 0.5@, correctly rounded and so the same on every
-- platform; for any other angle, and one that is not a number, 'cos' and
-- 'sin' of @d * pi / 180@.
cosSinDegrees :: Double -> (Double, Double)
cosSinDegrees d = fromMaybe (cos r, sin r) (eighthTurn d)
  where
    r = d * pi / 180

-- | The cosine and sine of an angle in degrees that is exactly a multiple of
-- 45°, and nothing for any other. The test compares the angle with 45 times
-- a whole number as exact rationals, so no angle that is not a multiple is
-- moved onto one: not 90.00000000000001, not a subnormal angle that @d / 45@
-- would round to 0, and not a huge one that @d / 45@ would round to a whole
-- number. A multiple so huge that @d / 45@ itself rounds is not found, and
-- turns by 'cos' and 'sin' as any other angle does. In radians the test would
-- need a tolerance, since @pi / 2@ is not π/2 either.
eighthTurn :: Double -> Maybe (Double, Double)
eighthTurn d
  | isNaN d || isInfinite d || toRational d /= fromInteger (45 * eighths) = Nothing
  | otherwise = Just $ case eighths `mod` 8 of
      0 -> (1, 0)
      1 -> (half, half)
      2 -> (0, 1)
      3 -> (negate half, half)
      4 -> (-1, 0)
      5 -> (negate half, negate half)
      6 -> (0, -1)
      _ -> (half, negate half)
  where
    eighths = round (d / 45) :: Integer
    half = sqrt 0.5

-- | Rodrigues' formula from a turn's cosine and sine, about the line through a
-- point along an axis, with each diagonal entry given by @diagonal@ of that
-- component of the unit axis.
turnFrom :: (Double -> Double) -> Double -> Double -> V3 -> V3 -> Rigid
turnFrom diagonal c s p axis = case normalize axis of
  Nothing -> identity
  Just u -> let m = rot u in Rigid m (p ^-^ matApply m p)
  where
    t = 1 - c

    -- R = I cos θ + [u]× sin θ + (u ⊗ u)(1 − cos θ), with [u]× the matrix that
    -- performs `cross u` and (u ⊗ u) the outer product.
    rot (V3 x y z) =
      Mat3
        (V3 (diagonal x) (t * x * y - s * z) (t * x * z + s * y))
        (V3 (t * x * y + s * z) (diagonal y) (t * y * z - s * x))
        (V3 (t * x * z - s * y) (t * y * z + s * x) (diagonal z))

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
-- That holds because no 'Rigid' mirrors or stretches (see the module
-- header): a scaling matrix would come back from here as a plausible value
-- that is not an inverse, with nothing to say so. A turn a little off, by
-- rounding or by up to the 1e-12 'rigidFrom' admits, comes back an inverse
-- about as far off.
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

-- | A rigid motion from a matrix built elsewhere and an offset: 'Just' if the
-- matrix is a proper rotation ('isProperRotation'), and 'Nothing' if it
-- mirrors, stretches or skews. The one way into 'Rigid' for a matrix this
-- module did not make.
--
-- 'Maybe' rather than an error type, as for 'fitRigid': the geometry layer has
-- no error type (@docs\/architecture.md@, "Layering rules"), and the caller
-- knows better than this module why its matrix should have been a turn.
rigidFrom :: Mat3 -> V3 -> Maybe Rigid
rigidFrom m t
  | isProperRotation m = Just (Rigid m t)
  | otherwise = Nothing

-- | The one rigid motion carrying each first point onto its second, if there
-- is one: every pair within the sources' 'modelHair', the tolerance
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
-- determinant +1. 'rigidFrom''s check here refuses a construction bug, and
-- also points so nearly in a line that one Gram–Schmidt step leaves the second
-- axis off square: a third point 1e-5 off the line through the first two is
-- refused, though a turn fits them.
fitRigid :: [(V3, V3)] -> Maybe Rigid
fitRigid pairs = case pairs of
  [] -> Nothing
  (a, a') : _ -> do
    let sources = map fst pairs
        tol = modelHair sources
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
            motion <- rigidFrom turn (a' ^-^ matApply turn a)
            if all (\(p, q) -> norm (applyRigid motion p ^-^ q) <= tol) pairs
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
