-- | Spend the same triangle budget near two known curvature transitions.
-- Curvature is turning per material length; HeldBend supplies fixed circular
-- and smooth references. Here the grid depends on transition locations only,
-- never on measured bending cost. See docs/glossary.md for material coordinates.
--
-- Start with the original coarse columns. Repeatedly split the interval with
-- greatest weighted length: density four inside either fixed transition window,
-- one outside. Equal scores choose the earlier interval. This greedy rule is
-- a bounded experiment, not an optimal mesh or an adaptive material solver.
-- A second policy applies the same density to the entire curved interval,
-- testing whether resolving its middle avoids the windows' geometric tradeoff.
-- Both panels receive the same columns and keep only the original crease shared.
module TransitionRefinement
  ( transitionWindowRadius,
    transitionWindows,
    intervalPriority,
    transitionGrid,
    wholeBendRegion,
    wholeBendPriority,
    wholeBendGrid,
    profileDifference,
  )
where

import BendRefinement
import ClosedCrease (ClosedCreaseError (..))
import Control.Monad (forM, unless)
import Data.List (foldl', nub, sort)
import HeldBend
import Senbazuru.Geometry.V3 (V3)
import Senbazuru.Geometry.VectorSpace

transitionWindowRadius :: Rational
transitionWindowRadius = 1 / 32

transitionWindows :: HeldCurve -> [(Rational, Rational)]
transitionWindows curve = [(centre - transitionWindowRadius, centre + transitionWindowRadius) | centre <- [toRational heldStart, toRational (heldStart + curveArcLength curve)]]

-- | Integrate the prescribed density exactly on material coordinates. The
-- overlap term is a UNION, so even an unusually short bend would not double
-- the weight where the two windows overlap. No energy measurement is an input.
intervalPriority :: HeldCurve -> Rational -> Rational -> Rational
intervalPriority curve left right = max 0 (right - left) + 3 * covered
  where
    windows = transitionWindows curve
    overlap a b = max 0 (min right b - max left a)
    covered = case windows of
      [(a, b), (c, d)] -> overlap a b + overlap c d - overlap (max a c) (min b d)
      _ -> 0

transitionGrid :: ReferenceMesh -> HeldCurve -> Either ClosedCreaseError ReferenceGrid
transitionGrid budget curve = priorityGrid budget (intervalPriority curve)

-- | The region is fixed by the common curve, not by sampled positions or
-- measured energy. Its width differs from the combined transition windows;
-- equal triangle counts, rather than equal integrated density, set the budget.
wholeBendRegion :: HeldCurve -> (Rational, Rational)
wholeBendRegion curve = (toRational heldStart, toRational (heldStart + curveArcLength curve))

wholeBendPriority :: HeldCurve -> Rational -> Rational -> Rational
wholeBendPriority curve left right = max 0 (right - left) + 3 * max 0 (min right end - max left start)
  where
    (start, end) = wholeBendRegion curve

wholeBendGrid :: ReferenceMesh -> HeldCurve -> Either ClosedCreaseError ReferenceGrid
wholeBendGrid budget curve = priorityGrid budget (wholeBendPriority curve)

-- | Share the splitting and tie policy; only the prescribed density changes.
priorityGrid :: ReferenceMesh -> (Rational -> Rational -> Rational) -> Either ClosedCreaseError ReferenceGrid
priorityGrid budget priority = do
  unless (budget /= Uneven120) (Left (ClosedCreaseError "local refinement uses the five uniform ladder budgets, not the uneven anchor"))
  makeReferenceGrid (refine (referenceColumns Uniform64))
  where
    target = length (referenceColumns budget)
    refine columns
      | length columns >= target = columns
      | otherwise = case zip columns (drop 1 columns) of
          [] -> columns
          first : rest ->
            let score (left, right) = priority left right
                better best candidate = if score candidate > score best then candidate else best
                (a, b) = foldl' better first rest
             in refine (sort ((a + b) / 2 : columns))

-- | The two polygonal profiles are linear between their material columns.
-- On the UNION of their columns, each difference is a linear vector; its norm
-- is convex, so its maximum occurs at an interval end. Checking every union
-- breakpoint therefore covers the entire material sheet, including points
-- which are vertices of only one mesh. This relies on these profiles being
-- extruded unchanged across width, not on a general triangle-surface theorem.
-- Return the maximum displacement and its distance from the original crease.
profileDifference :: ReferenceGrid -> ReferenceGrid -> ReferenceConstruction -> HeldCurve -> Either ClosedCreaseError (Double, Double)
profileDifference a b construction curve = do
  let profile grid = zip (gridColumns grid) (gridProfile grid construction curve)
      locations = sort (nub (gridColumns a ++ gridColumns b))
  differences <- forM locations $ \s -> do
    p <- at s (profile a)
    q <- at s (profile b)
    pure (norm (p ^-^ q), fromRational s)
  pure (foldl' (\best candidate -> if fst candidate > fst best then candidate else best) (0, 0) differences)
  where
    at :: Rational -> [(Rational, V3)] -> Either ClosedCreaseError V3
    at s ((left, p) : rest@((right, q) : _))
      | s >= left && s <= right = let t = fromRational ((s - left) / (right - left)) in pure ((1 - t) *^ p ^+^ t *^ q)
      | otherwise = at s rest
    at s [(u, p)] | s == u = pure p
    at _ _ = Left (ClosedCreaseError "profile comparison lost a material interval")
