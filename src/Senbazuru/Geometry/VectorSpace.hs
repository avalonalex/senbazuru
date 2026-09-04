-- |
-- Module      : Senbazuru.Geometry.VectorSpace
-- Description : The arithmetic 2D and 3D points have in common.
--
-- @V2@ and @V3@ support the same handful of operations, so they share one
-- vocabulary rather than each carrying its own spelling of it. Without this,
-- the two modules would either export colliding operators or resort to names
-- like @addV3@, and every call site would say which dimension it is in when the
-- types already do.
--
-- == What is deliberately not here
--
-- __The cross product.__ Not an oversight, and not a gap in @V2@: it is simply
-- not a vector-space operation. In 3D it takes two vectors and returns a
-- vector; the 2D analogue @ax*by - ay*bx@ returns a /scalar/. The signatures
-- differ, so no class could unify them, and @cross@ stays in
-- "Senbazuru.Geometry.V3" where it belongs. (The 2D scalar version is not
-- missing either — it is the orientation predicate that convex hulls turn on.)
--
-- __Dimension polymorphism.__ A @V (n :: Nat)@ indexed by a type-level natural
-- would generalise both types into one, at the cost of @DataKinds@, @KnownNat@
-- and considerably worse error messages. It would earn that if the set of
-- dimensions were open. It is not: paper is two-dimensional, space is three,
-- and there is no fourth case coming.
module Senbazuru.Geometry.VectorSpace
  ( VectorSpace (..),
  )
where

infixl 6 ^+^, ^-^

infixl 7 *^

-- | Points that can be added, scaled, and measured against each other.
--
-- Four primitives; 'norm' and 'normalize' are derived from them and come with
-- defaults, so an instance only has to supply the arithmetic.
--
-- The scalar is fixed to 'Double' rather than being a second class parameter.
-- That keeps inference unambiguous — a numeric literal in @2 *^ v@ needs no
-- annotation — and this project has no use for vectors over anything else.
class VectorSpace v where
  -- | Componentwise addition.
  (^+^) :: v -> v -> v

  -- | Componentwise subtraction.
  (^-^) :: v -> v -> v

  -- | Scale by a number.
  (*^) :: Double -> v -> v

  -- | The scalar product. Geometrically, how far one vector reaches along
  -- another when that other is a unit vector — which is exactly what projecting
  -- onto an axis means.
  dot :: v -> v -> Double

  -- | Euclidean length.
  norm :: v -> Double
  norm v = sqrt (dot v v)

  -- | Scale to unit length. 'Nothing' when there is no unit vector to return.
  --
  -- The guard rejects more than the zero vector. Testing @n == 0@ alone would
  -- let non-finite input through, because @NaN == 0@ is 'False', and the result
  -- would be a @Just@ full of NaNs claiming to be a unit vector. Downstream
  -- that is silent: NaN coordinates format as @0@, so every point stacks in one
  -- place and nothing reports an error.
  normalize :: v -> Maybe v
  normalize v
    | n > 0, not (isInfinite n) = Just ((1 / n) *^ v)
    | otherwise = Nothing
    where
      n = norm v
