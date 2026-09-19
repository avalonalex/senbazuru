-- | Compare two interpretations of a partial interval at the ends of the
-- imposed bending band. A band asks an uncreased region to curve; material
-- coordinates locate that region on the unfolded sheet (docs/glossary.md).
-- The old spring clips its preferred turn to the interval but measures the
-- full angle between neighboring triangles. The candidate attributes the
-- same fraction of actual turn to that interval, assuming constant curvature
-- across the two strips. This is a loading experiment, not a new paper law.
--
-- For original stiffness k, preferred turn t and represented fraction f,
-- k*(f*theta-t)^2/2 equals k*f^2*(theta-t/f)^2/2 on the same angle branch.
-- The f^2 is essential: changing only the target would change the load's
-- flat-reference energy. Wrap the FULL angle error before scaling it, using
-- the existing hinge convention. No solver or fixture default adopts this
-- candidate; keeping both springs allows energy and derivative checks first.
module BandBoundary (BoundaryMeasure (..), measureBandBoundary) where

import ClosedCrease
import Control.Monad (forM, unless, when)
import CreaseInequality (InequalityError (..))
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import FoldBending
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Origami.Surface
import UnequalCrease (bandInterval)

data BoundaryMeasure = BoundaryMeasure
  { boundaryOriginal :: !Hinge,
    boundaryCandidate :: !Hinge,
    boundaryInterval :: !(Double, Double),
    boundaryFullSpan :: !Double,
    boundaryFraction :: !Double,
    boundaryDistance :: !Double,
    boundaryWidthRange :: !(Double, Double),
    boundaryAngle :: !Double,
    boundaryOldEnergy :: !Double,
    boundaryNewEnergy :: !Double,
    boundaryOldSlope :: !Double,
    boundaryNewSlope :: !Double
  }
  deriving stock (Eq, Show)

-- | This comparison is deliberately restricted to the existing uniform,
-- transversely extruded band fixtures. Refuse missing or incompatible supports
-- instead of silently treating a different grid as a full interval.
measureBandBoundary :: Int -> ClosedCrease -> Either InequalityError [BoundaryMeasure]
measureBandBoundary count fixture = do
  unless (count `elem` [1, 2, 4, 8]) (Left (InequalityError "band-boundary subdivision must be 1, 2, 4 or 8"))
  let controls = filter ((== BendControl) . hingeRole) (closedHinges fixture)
  when (null controls) (Left (InequalityError "band-boundary comparison needs the upper-band controls"))
  forM controls $ \h -> do
    let (a, b, c, d) = hingeVertices h
    p <- vertex a
    q <- vertex b
    r <- vertex c
    s <- vertex d
    let u = materialU p
        distance = abs u
        column = round (distance / fullSpan)
        close x y = abs (x - y) <= 1e-12
    unless (u < 0 && materialU q == u && materialV p /= materialV q && close distance (fromIntegral column * fullSpan) && close (abs (materialU r - u)) fullSpan && close (abs (materialU s - u)) fullSpan && (materialU r - u) * (materialU s - u) < 0) $
      Left (InequalityError ("band-boundary control has incompatible neighboring strips at " <> tshow (a, b)))
    interval@(lo, hi) <- maybe (Left (InequalityError "band-boundary control lies outside the prescribed band")) Right (bandInterval count column)
    let fraction = (hi - lo) / fullSpan
        candidate = if fraction == 1 then h else h {hingeRest = hingeRest h / fraction, hingeStiffness = hingeStiffness h * fraction * fraction}
    unless (all (\x -> not (isNaN x || isInfinite x)) [fraction, hingeRest candidate, hingeStiffness candidate] && fraction > 0 && fraction <= 1 && abs (hingeRest candidate) <= pi && hingeStiffness candidate > 0) (Left (InequalityError "band-boundary candidate needs a finite positive fraction and an unambiguous full-angle target"))
    (actual, _) <- first (InequalityError . explain) (hingeAngle h vertices)
    let oldError = angleError actual (hingeRest h)
        newError = angleError actual (hingeRest candidate)
        energy spring err = hingeStiffness spring * err * err / 2
        slope spring err = hingeStiffness spring * err
    pure (BoundaryMeasure h candidate interval fullSpan fraction distance (min (materialV p) (materialV q), max (materialV p) (materialV q)) actual (energy h oldError) (energy candidate newError) (slope h oldError) (slope candidate newError))
  where
    fullSpan = 1 / fromIntegral (8 * count)
    vertices = IM.fromList (zip [0 ..] (samples (closedMesh fixture)))
    vertex i = maybe (Left (InequalityError ("band-boundary control lost vertex " <> tshow i))) Right (IM.lookup i vertices)
