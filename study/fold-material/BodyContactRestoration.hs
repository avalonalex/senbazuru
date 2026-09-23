-- | One local projection that restores a lost linearized plane distance.
-- At a refused trial, g is the distance gradient on FREE vertex coordinates.
-- The smallest sum of squared vertex movements satisfying g dot delta = loss
-- is delta = loss*g/(g dot g). Any additional component perpendicular to g
-- increases movement without repairing more distance. Held coordinates are
-- removed before this calculation, so they cannot absorb the correction.
--
-- This repairs one linear equation, not material equilibrium or all contact.
-- The caller must remeasure the moving plane, retained overlap guards, actual
-- material cost and all triangle pairs after applying it ONCE. It must not
-- silently iterate or mistake the tiny repair for a converged main direction.
module BodyContactRestoration (RestorationError (..), restorePlane) where

import BodyPlaneGuard (PlaneMeasure (..))
import Control.Monad (unless)
import Data.IntMap.Strict qualified as IM
import Senbazuru.Explain (Explain (..))
import Senbazuru.Geometry.V3 (V3)
import Senbazuru.Geometry.VectorSpace

data RestorationError = InvalidRestoration | NoFreePlaneResponse deriving stock (Eq, Show)

instance Explain RestorationError where
  explain InvalidRestoration = "plane restoration needs finite distance, target and gradient with a finite correction"
  explain NoFreePlaneResponse = "plane restoration cannot recover distance while all responsive coordinates are held"

restorePlane :: IM.IntMap V3 -> Double -> PlaneMeasure -> Either RestorationError (IM.IntMap V3)
restorePlane pins target measure = do
  let gradient = IM.difference (planeGradient measure) pins
      loss = max 0 (target - planeDistance measure)
      squared = sum [dot g g | g <- IM.elems gradient]
  unless (all finite [target, planeDistance measure, loss, squared] && all (finite . norm) (IM.elems (planeGradient measure))) (Left InvalidRestoration)
  if loss == 0
    then pure IM.empty
    else do
      unless (squared > 0) (Left NoFreePlaneResponse)
      let correction = IM.map ((loss / squared) *^) gradient
      unless (all (finite . norm) (IM.elems correction)) (Left InvalidRestoration)
      pure correction
  where
    finite x = not (isNaN x || isInfinite x)
