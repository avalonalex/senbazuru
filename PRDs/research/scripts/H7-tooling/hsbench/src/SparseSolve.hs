-- | Coupled preconditioning for the material study's stiff normal equations.
-- Two touching coordinates can move together without changing their gap.
-- Rescaling each coordinate independently misses that easy shared movement
-- when penetration is penalized very strongly. A preconditioner is an easier
-- system used to choose better search directions for the original one.
--
-- The rows of J describe how each measured error changes with each unknown.
-- Factor J^T J + damping I as L D L^T: D is diagonal and L triangular, so
-- applying its inverse takes two substitutions. This keeps couplings between
-- coordinates. I is the identity; ^T swaps rows and columns.
-- This changes the search, never the energy or held vertices.
-- Damping adds a small cost to movement so unconstrained directions still
-- have a unique correction. See docs/notes/coupled-touching-layer-solve.md.
--
-- Eliminate the least-connected remaining unknown first to limit fill (new
-- matrix entries created by elimination). This is a small-study implementation,
-- not a bounded-memory solver for arbitrary meshes. A nonpositive/nonfinite
-- pivot refuses the factor; the caller retains its previous preconditioner.
-- The iterative solver must still check the ORIGINAL row-based residual:
-- forming and factoring the normal matrix introduces floating-point error.
module SparseSolve (Factor, factorNormal, applyFactor, conjugateGradient, LinearReport (..)) where

import Data.IntMap.Strict qualified as IM
import Data.List (foldl')
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace

newtype Factor = Factor [(Int, Double, IM.IntMap Double)] deriving stock (Show)

-- | Residual is measured against the original operator, never the factor.
-- Keep this small report rather than retaining every inner search vector.
data LinearReport = LinearReport
  { linearConverged :: !Bool,
    linearIterations :: !Int,
    linearResidual :: !Double,
    linearThreshold :: !Double
  }
  deriving stock (Eq, Show)

-- | Scalar ids name only free coordinates; gradients may also mention held
-- ones, which are removed before assembling the matrix. Repeated contributions
-- to one scalar must already be combined in its IntMap.
factorNormal :: Double -> [Int] -> [IM.IntMap Double] -> Maybe Factor
factorNormal damping ids gradients
  | damping <= 0 || not (finite damping) = Nothing
  | otherwise = Factor <$> eliminate [] matrix
  where
    initial = IM.fromList [(i, IM.singleton i damping) | i <- ids]
    matrix = foldl' addGradient initial gradients
    addGradient acc gradient =
      let free = IM.filter (/= 0) (IM.intersection gradient initial)
       in IM.foldlWithKey' (\m i a -> IM.adjust (IM.unionWith (+) (IM.map (a *) free)) i m) acc free
    eliminate history current = case IM.toList current of
      [] -> Just (reverse history)
      first : rest ->
        let smaller a b = if IM.size (snd a) <= IM.size (snd b) then a else b
            (i, row) = foldl' smaller first rest
            diagonal = IM.findWithDefault 0 i row
            others = IM.delete i row
            column = IM.map (/ diagonal) others
            remaining = IM.delete i current
            -- Substituting the eliminated unknown subtracts a_j*a_k/d
            -- from each remaining connected pair. Keep both symmetric rows.
            reduced = IM.foldlWithKey' (\m j a -> IM.adjust (IM.delete i . IM.unionWith (+) (IM.map (negate a *) column)) j m) remaining others
         in if diagonal <= 0 || not (finite diagonal) || not (all finite column)
              then Nothing
              else eliminate ((i, diagonal, column) : history) reduced

-- | Missing right-side entries mean zero. Return every factor coordinate,
-- including those whose value becomes nonzero during substitution.
applyFactor :: Factor -> IM.IntMap Double -> IM.IntMap Double
applyFactor (Factor columns) rhs = foldr backward divided columns
  where
    forward values (i, _, column) =
      let value = IM.findWithDefault 0 i values
       in IM.foldlWithKey' (\acc j a -> IM.adjust (subtract (a * value)) j acc) values column
    lower = foldl' forward (IM.fromList [(i, IM.findWithDefault 0 i rhs) | (i, _, _) <- columns]) columns
    divided = foldl' (\values (i, diagonal, _) -> IM.adjust (/ diagonal) i values) lower columns
    backward (i, _, column) values =
      let correction = sum (IM.elems (IM.intersectionWith (*) column values))
       in IM.adjust (subtract correction) i values

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)

-- | Solve a symmetric positive definite linear system by repeatedly choosing
-- a search direction conjugate to the earlier ones. Only matrix-vector
-- products are needed, so the edge graph stays sparse. This is an inner
-- numerical solve, not a physical time integration. The report records
-- whether the linear residual passed: a failed solve returning no movement
-- must not make the outer elastic problem appear to be at equilibrium.
-- A residual floor is needed near a penalised equilibrium: forces from the
-- 1e8 length penalty nearly cancel the angular forces, and their floating-point
-- subtraction cannot promise a relative error on an arbitrarily tiny remainder.
-- Recursive residual updates accumulate roundoff. Before accepting, recompute
-- b - A*x with the original operator; restart from that residual if it fails.
-- Restarts consume the same work budget and cannot weaken the threshold.
conjugateGradient :: Int -> Double -> (IM.IntMap V3 -> IM.IntMap V3) -> (IM.IntMap V3 -> IM.IntMap V3) -> IM.IntMap V3 -> (IM.IntMap V3, LinearReport)
conjugateGradient limit residualFloor precondition action rhs = go limit zero rhs (precondition rhs) (inner rhs (precondition rhs))
  where
    zero = IM.map (const (V3 0 0 0)) rhs
    threshold = max (residualFloor * residualFloor) (inner rhs rhs * 1e-16)
    inner a b = sum (IM.elems (IM.intersectionWith dot a b))
    add a scale b = IM.unionWith (^+^) a (IM.map (scale *^) b)
    finish remaining solution settled =
      let actual = add rhs (-1) (action solution)
       in (solution, LinearReport settled (limit - remaining) (sqrt (inner actual actual)) (sqrt threshold))
    go remaining solution residual direction productResidual
      | finite (inner residual residual) && inner residual residual <= threshold =
          let actual = add rhs (-1) (action solution)
           in if finite (inner actual actual) && inner actual actual <= threshold
                then finish remaining solution True
                else
                  if remaining <= 0
                    then finish remaining solution False
                    else go (remaining - 1) solution actual (precondition actual) (inner actual (precondition actual))
      | remaining <= 0 = finish remaining solution False
      | otherwise =
          let product' = action direction
              denominator = inner direction product'
           in if denominator <= 0 || not (finite denominator)
                then finish remaining solution False
                else
                  let alpha = productResidual / denominator
                      solution' = add solution alpha direction
                      residual' = add residual (-alpha) product'
                      scaled = precondition residual'
                      productResidual' = inner residual' scaled
                      direction' = add scaled (productResidual' / productResidual) direction
                   in go (remaining - 1) solution' residual' direction' productResidual'
