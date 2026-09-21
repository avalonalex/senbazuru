-- | Locate a saved triangle crossing without correcting paper. A plane section
-- is the line segment cut out of a triangle by the other triangle's plane.
-- Its overlap measures how far their intersection runs ALONG the paper; a
-- directional contact gap measures separation THROUGH the overlapping paper.
-- These are different distances. A long, shallow sliver can fail the crossing
-- check while every sampled height difference stays within its tolerance.
--
-- This study exposes actual section endpoints and the solver's own contact
-- witnesses (corners of the overlapping projected outlines). It does not
-- reinterpret a crossing as valid or certify motion between recorded states.
module BodyContactDiagnosis (PairSection (..), pairSection, sectionCrosses) where

import Control.Monad (unless)
import CraneSpread (SpreadError (..))
import Data.IntMap.Strict qualified as IM
import Senbazuru.Geometry.V3 (V3, cross)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (panelTolerance)
import Senbazuru.Origami.Surface

-- Distances of A's vertices from B's plane, and conversely. Section endpoints
-- have no distance snap: snapping a nearby corner would artificially lengthen
-- the cut when planes meet at a small angle. The tolerance is applied only to
-- straddling and common interval length, as in the independent checker.
data PairSection = PairSection
  { sectionFirst :: ![V3],
    sectionSecond :: ![V3],
    firstDistances :: ![Double],
    secondDistances :: ![Double],
    intersectionEnds :: ![V3],
    intersectionLength :: !Double
  }
  deriving stock (Eq, Show)

pairSection :: MaterialMesh -> (Int, Int) -> Either SpreadError PairSection
pairSection mesh (i, j) = do
  (a, na) <- triangle i
  (b, nb) <- triangle j
  case (a, b) of
    (pa : _, pb : _) -> do
      let da p = dot na (p ^-^ pa)
          db p = dot nb (p ^-^ pb)
          sa = section db a
          sb = section da b
          line = cross na nb
          overlap = if norm line < 1e-12 then [] else common ((1 / norm line) *^ line) sa sb
      pure (PairSection sa sb (map db a) (map da b) overlap (case overlap of [x, y] -> norm (y ^-^ x); _ -> 0))
    _ -> Left (SpreadError "contact diagnosis needs two triangles")
  where
    points = IM.fromList (zip [0 ..] (samples mesh))
    topology = IM.fromList (zip [0 ..] (triangles mesh))
    point k = maybe (Left (SpreadError "contact diagnosis lost a vertex")) (Right . position) (IM.lookup k points)
    triangle k = do
      (a, b, c) <- maybe (Left (SpreadError "contact diagnosis names an absent triangle")) Right (IM.lookup k topology)
      p <- point a
      q <- point b
      r <- point c
      let n = cross (q ^-^ p) (r ^-^ p)
      unless (all finite [norm p, norm q, norm r, norm n] && norm n > 1e-12) (Left (SpreadError "contact diagnosis needs finite nondegenerate triangles"))
      pure ([p, q, r], (1 / norm n) *^ n)
    finite x = not (isNaN x || isInfinite x)

sectionCrosses :: PairSection -> Bool
sectionCrosses s = straddles (firstDistances s) && straddles (secondDistances s) && intersectionLength s > panelTolerance
  where
    straddles ds = any (< negate panelTolerance) ds && any (> panelTolerance) ds

section :: (V3 -> Double) -> [V3] -> [V3]
section distance points =
  [p | p <- points, distance p == 0]
    ++ [p ^+^ ((dp / (dp - dq)) *^ (q ^-^ p)) | (p, q) <- zip points (drop 1 points ++ take 1 points), let dp = distance p, let dq = distance q, dp * dq < 0]

common :: V3 -> [V3] -> [V3] -> [V3]
common direction as bs = case (as, bs) of
  (origin : _, _ : _) ->
    let xs = map (dot direction) as
        ys = map (dot direction) bs
        lo = max (minimum xs) (minimum ys)
        hi = min (maximum xs) (maximum ys)
        at t = origin ^+^ ((t - dot direction origin) *^ direction)
     in if hi > lo then [at lo, at hi] else []
  _ -> []
