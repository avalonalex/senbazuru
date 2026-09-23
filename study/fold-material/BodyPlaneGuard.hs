-- | A local derivative of one vertex's distance to a moving triangle plane.
-- A plane extends beyond the triangle's edges, so this is not a discovered
-- physical contact. The body experiment explicitly selects a vertex outside
-- the overlap after inspecting its saved crossing refusal.
--
-- For vertex p and triangle (a,b,c), distance is n dot (p-a), where n is
-- the unit normal in the ORIGINAL vertex winding. Differentiating only p
-- would freeze the plane by mistake: all three triangle vertices contribute.
-- Normalizing the cross product also contributes a derivative; omitting that
-- term changes the answer when the triangle changes area.
--
-- The guard uses the existing incremental floor min(0,d): a negative starting
-- distance is preserved in the linear prediction, not repaired. This is a local policy,
-- never a substitute for the unchanged all-pair geometry checks. See
-- docs/notes/body-plane-guard.md and docs/glossary.md for contact terminology.
module BodyPlaneGuard (PlaneMeasure (..), PlaneGuardError (..), measurePlane, planeGuardRow) where

import BodyContactDirection (contactGuard)
import ContactQuadratic (QuadraticRow)
import Control.Monad (unless, when)
import Data.IntMap.Strict qualified as IM
import FoldContact (ContactRow (..))
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface

data PlaneMeasure = PlaneMeasure
  { planeDistance :: !Double,
    planeGradient :: !(IM.IntMap V3)
  }
  deriving stock (Eq, Show)

data PlaneGuardError = MissingPlaneVertex Int | MissingPlaneTriangle Int | InvalidPlaneVertex Int | DegeneratePlane Int | IncidentPlaneVertex Int Int
  deriving stock (Eq, Show)

instance Explain PlaneGuardError where
  explain (MissingPlaneVertex v) = "plane guard cannot find vertex " <> tshow v
  explain (MissingPlaneTriangle t) = "plane guard cannot find triangle " <> tshow t
  explain (InvalidPlaneVertex v) = "plane guard needs finite coordinates at vertex " <> tshow v
  explain (DegeneratePlane t) = "plane guard needs a nondegenerate finite triangle " <> tshow t
  explain (IncidentPlaneVertex v t) = "plane guard vertex " <> tshow v <> " belongs to its own triangle " <> tshow t

measurePlane :: MaterialMesh -> Int -> Int -> Either PlaneGuardError PlaneMeasure
measurePlane mesh vertex triangle = do
  (ia, ib, ic) <- maybe (Left (MissingPlaneTriangle triangle)) Right (IM.lookup triangle topology)
  when (vertex `elem` [ia, ib, ic]) (Left (IncidentPlaneVertex vertex triangle))
  p <- point vertex
  a <- point ia
  b <- point ib
  c <- point ic
  let e = b ^-^ a
      f = c ^-^ a
      rawNormal = cross e f
      area = norm rawNormal
  unless (finite area && area > 1e-12) (Left (DegeneratePlane triangle))
  let n = (1 / area) *^ rawNormal
      r = p ^-^ a
      distance = dot n r
      -- Only the component of r tangent to the plane changes n dot r
      -- when the unit normal turns; division by area differentiates its scale.
      tangent = (1 / area) *^ (r ^-^ distance *^ n)
      gb = cross f tangent
      gc = cross tangent e
      ga = (-1) *^ (n ^+^ gb ^+^ gc)
      gradient = IM.fromList [(vertex, n), (ia, ga), (ib, gb), (ic, gc)]
  unless (finite distance && all (finite . norm) (IM.elems gradient)) (Left (DegeneratePlane triangle))
  pure (PlaneMeasure distance gradient)
  where
    topology = IM.fromList (zip [0 ..] (triangles mesh))
    points = IM.fromList (zip [0 ..] (samples mesh))
    point v = do
      p <- maybe (Left (MissingPlaneVertex v)) (Right . position) (IM.lookup v points)
      unless (finite (norm p)) (Left (InvalidPlaneVertex v))
      pure p
    finite x = not (isNaN x || isInfinite x)

-- | Exact holds have zero displacement, so remove their derivative entries.
-- Reuse the existing floor rule rather than introducing another gap policy.
planeGuardRow :: IM.IntMap V3 -> PlaneMeasure -> QuadraticRow
planeGuardRow pins m = contactGuard pins (ContactRow (planeDistance m) (IM.toList (planeGradient m)))
