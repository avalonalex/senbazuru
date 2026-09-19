-- | Locate angular spring costs on the original sheet, not on its folded
-- projection. Material coordinates and panel bends are defined in
-- docs/glossary.md. Every passive/control spring contributes once; the
-- original closed crease stays separate. Regions classify an edge's material
-- midpoint, with the two band boundary lines kept distinct. This is discrete
-- spring bookkeeping, not a claim that energy is uniformly spread over paper.
--
-- A finer mesh shares a turn among more edges. For transverse edges (parallel
-- to the shared crease), divide the signed turn by the mean distance to the
-- neighboring material columns. This angular rate is comparable across the
-- strip grids; it is not a recovered smooth curvature field. Other edge
-- directions retain their full energy and raw angles without this rate.
module BendLocations
  ( BendRegion (..),
    LocatedBend (..),
    savedBendMesh,
    locateBends,
    regionEnergy,
    cumulativeEnergy,
    transverseRates,
  )
where

import ClosedCrease
import Control.Monad (forM, unless)
import CoupledCrease
import CreaseInequality (InequalityError (..))
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (nub, sort)
import FoldBending
import PrescribedBend
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface

-- The held-strip boundary is also the beginning of the upper loading band.
data BendRegion = HeldStrip | HeldBoundary | BandInterior | BandEnd | OuterStrip
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data LocatedBend = LocatedBend
  { locatedMeasure :: !HingeMeasure,
    locatedFrom :: !V2,
    locatedTo :: !V2,
    locatedDistance :: !Double,
    locatedRegion :: !BendRegion,
    locatedRate :: !(Maybe Double)
  }
  deriving stock (Eq, Show)

-- | Bind saved positions to the authored fixture before measuring them. A
-- changed hold, winding, triangulation or retained layer order is refused;
-- a crossing geometry is retained for the gallery's independent contact audit.
savedBendMesh :: CoupledFixture -> Frame -> Either InequalityError MaterialMesh
savedBendMesh fixture fr = do
  sheet <- adapt (surfaceFromFrame fr >>= requireMaterialCoordinates)
  faces <- forM (facesVertices fr) $ \case
    [VertexId a, VertexId b, VertexId c] -> pure (a, b, c)
    _ -> Left (InequalityError "bending locations require triangulated saved paper")
  let mesh = Mesh (surfaceSamples sheet) faces
  checkCoupledMaterial fixture mesh
  expected <- materialFrame <$> coupledSurface fixture mesh
  unless (edgesVertices fr == edgesVertices expected && edgesAssignment fr == edgesAssignment expected && faceOrders fr == faceOrders expected && frameExtras fr == frameExtras expected) $
    Left (InequalityError "saved endpoint changed edge, source-panel or layer identities")
  pure mesh
  where
    adapt = first (InequalityError . explain)

locateBends :: ClosedCrease -> Either InequalityError [LocatedBend]
locateBends fixture = do
  measured <- measureProbe fixture
  forM (probeHinges measured) $ \m -> do
    let (a, b, c, d) = hingeVertices (measuredHinge m)
    p <- point a
    q <- point b
    r <- point c
    s <- point d
    let V2 u v = p
        V2 u' v' = q
        V2 ur _ = r
        V2 us _ = s
        distance = (abs u + abs u') / 2
        spanLength = (abs (ur - u) + abs (us - u)) / 2
        transverse = u == u' && v /= v'
        region
          | distance < 1 / 8 = HeldStrip
          | distance == 1 / 8 = HeldBoundary
          | distance < 7 / 16 = BandInterior
          | distance == 7 / 16 = BandEnd
          | otherwise = OuterStrip
    unless (not transverse || spanLength > 0) (Left (InequalityError "transverse bend has no material span"))
    pure (LocatedBend m p q distance region (if transverse then Just (measuredAngle m / spanLength) else Nothing))
  where
    points = IM.fromList (zip [0 ..] (map sampleMaterial (samples (closedMesh fixture))))
    point i = maybe (Left (InequalityError ("bend location lost vertex " <> tshow i))) Right (IM.lookup i points)

regionEnergy :: [LocatedBend] -> [(BendRegion, Double)]
regionEnergy rows = [(r, sum [measuredEnergy (locatedMeasure h) | h <- rows, locatedRegion h == r]) | r <- [minBound .. maxBound]]

-- | The staircase assigns each complete spring cost to its edge midpoint.
-- It ends at exactly the same total as the region table, including bends
-- along the panel and along triangulation diagonals.
cumulativeEnergy :: [LocatedBend] -> [V2]
cumulativeEnergy rows = V2 0 0 : concat [let before = total (< x); after = total (<= x) in [V2 x before, V2 x after] | x <- distances] ++ [V2 0.5 (total (const True))]
  where
    distances = sort (nub (map locatedDistance rows))
    total keep = sum [measuredEnergy (locatedMeasure h) | h <- rows, keep (locatedDistance h)]

-- | Width-weighted mean and range, so twisting across the width is not lost
-- behind one mean. Only transverse passive edges belong in these profiles.
transverseRates :: [LocatedBend] -> [(Double, Double, Double, Double)]
transverseRates rows =
  [ (x, sum [w * a | (a, w) <- values] / sum (map snd values), minimum (map fst values), maximum (map fst values))
    | x <- sort (nub [locatedDistance h | h <- rows, Just _ <- [locatedRate h]]),
      let values = [(a, norm (locatedTo h ^-^ locatedFrom h)) | h <- rows, locatedDistance h == x, Just a <- [locatedRate h]],
      not (null values)
  ]
