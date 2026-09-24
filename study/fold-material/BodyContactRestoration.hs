-- | One local projection that restores a lost linearized contact distance.
-- At a refused trial, g is a plane-distance or overlap-gap gradient on FREE
-- vertex coordinates. An overlap gap compares the heights of two triangles
-- at a moving corner of their projected overlap; its derivative comes from
-- SurfaceContact, so this projection does not freeze that corner in space.
-- The smallest sum of squared vertex movements satisfying g dot delta = loss
-- is delta = loss*g/(g dot g). Any additional component perpendicular to g
-- increases movement without repairing more distance. Held coordinates are
-- removed before this calculation, so they cannot absorb the correction.
--
-- This repairs one linear equation, not material equilibrium or all contact.
-- The caller must remeasure the moving plane, retained overlap guards, actual
-- material cost and all triangle pairs after applying it ONCE. It must not
-- silently iterate or mistake the tiny repair for a converged main direction.
module BodyContactRestoration (RestorationError (..), restorePlane, restoreOverlap) where

import BodyPlaneGuard (PlaneMeasure (..))
import Control.Monad (unless)
import Data.IntMap.Strict qualified as IM
import FoldContact (ContactRow (..))
import Senbazuru.Explain (Explain (..))
import Senbazuru.Geometry.V3 (V3)
import Senbazuru.Geometry.VectorSpace

data RestorationError = InvalidRestoration | NoFreePlaneResponse | InvalidOverlapRestoration | NoFreeOverlapResponse deriving stock (Eq, Show)

instance Explain RestorationError where
  explain InvalidRestoration = "plane restoration needs finite distance, target and gradient with a finite correction"
  explain NoFreePlaneResponse = "plane restoration cannot recover distance while all responsive coordinates are held"
  explain InvalidOverlapRestoration = "overlap restoration needs finite gap, target and gradient with a finite correction"
  explain NoFreeOverlapResponse = "overlap restoration cannot recover a gap while all responsive coordinates are held"

restorePlane :: IM.IntMap V3 -> Double -> PlaneMeasure -> Either RestorationError (IM.IntMap V3)
restorePlane pins target measure = restoreDistance InvalidRestoration NoFreePlaneResponse pins target (planeDistance measure) (planeGradient measure)

-- | Restore one measured overlap gap with the same minimum-movement rule.
-- The target is explicit: preserving an already negative starting gap is not
-- the same experiment as pulling the triangles apart to a zero gap.
restoreOverlap :: IM.IntMap V3 -> Double -> ContactRow -> Either RestorationError (IM.IntMap V3)
restoreOverlap pins target row = restoreDistance InvalidOverlapRestoration NoFreeOverlapResponse pins target (contactGap row) (IM.fromListWith (^+^) (contactGradient row))

restoreDistance :: RestorationError -> RestorationError -> IM.IntMap V3 -> Double -> Double -> IM.IntMap V3 -> Either RestorationError (IM.IntMap V3)
restoreDistance invalid noResponse pins target distance fullGradient = do
  let gradient = IM.difference fullGradient pins
      loss = max 0 (target - distance)
      squared = sum [dot g g | g <- IM.elems gradient]
  unless (all finite [target, distance, loss, squared] && all (finite . norm) (IM.elems fullGradient)) (Left invalid)
  if loss == 0
    then pure IM.empty
    else do
      unless (squared > 0) (Left noResponse)
      let correction = IM.map ((loss / squared) *^) gradient
      unless (all (finite . norm) (IM.elems correction)) (Left invalid)
      pure correction
  where
    finite x = not (isNaN x || isInfinite x)
