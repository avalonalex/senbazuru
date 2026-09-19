-- | Bound the distance between filled visible regions, before pixel sampling.
-- A region is a union of convex polygons in page coordinates. This study-only
-- module knows nothing about paper, cameras or rasterization; the gallery
-- supplies the already resolved visible regions in pixels.
--
-- For each source point, find the nearest point in the target union. We want
-- the largest such distance over the entire source, then repeat with source
-- and target exchanged. Corners alone are insufficient: a hole in the target
-- can put the largest distance inside a source triangle.
--
-- A sampled point supplies a lower bound and a witness. Distance to ONE convex
-- target piece is convex, so its maximum over a source triangle occurs at a
-- corner. The smallest of those per-piece maxima bounds distance to the union
-- from above. These two operations must not be exchanged: max(min(...)) at
-- the corners is only a lower bound when the nearest target piece changes.
-- Bisect the longest edge of the triangle with the largest remaining upper
-- bound until the global interval is narrow enough or the work limit is met.
-- An optional drawing budget also stops subdivision once the whole interval
-- is on one side of that budget; that decision does not need a precise maximum.
-- The area measurement instead classifies whole triangles against a distance
-- budget, retaining every unclassified cell in its error bound. Distance and
-- area answer different questions: a remote sliver can dominate distance while
-- contributing almost no area. Neither measurement waives the other.
--
-- Bounds use ordinary floating-point geometry, not interval arithmetic; they
-- retain its roundoff limits. No positive area is discarded as "too small".
module IllustrationDistance
  ( DistanceError (..),
    RegionDistance (..),
    DistanceBounds (..),
    regionDistance,
    AreaBounds (..),
    areaBeyondBudget,
    AreaRegions (..),
    AreaCell (..),
    areaRegionsBeyondBudget,
  )
where

import Data.List (foldl', transpose)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (cross2, signedArea)
import Senbazuru.Geometry.VectorSpace

newtype DistanceError = DistanceError Text deriving stock (Eq, Show)

instance Explain DistanceError where explain (DistanceError message) = message

data RegionDistance = EmptySource | MissingTarget | BoundedDistance DistanceBounds
  deriving stock (Eq, Show)

data DistanceBounds = DistanceBounds
  { distanceLower :: Double,
    distanceUpper :: Double,
    witnessFrom :: V2,
    witnessTo :: V2,
    distanceSplits :: Int
  }
  deriving stock (Eq, Show)

type Triangle = (V2, V2, V2)

data Witness = Witness Double V2 V2

-- | Convex rings may have either winding and repeated corners. Zero-area
-- rings represent no filled exposure. Invalid/nonconvex input is an error;
-- an empty source has nothing to compare, while a nonempty source with an
-- empty target has disappeared and has no finite distance.
regionDistance :: Double -> Maybe Double -> Int -> [[V2]] -> [[V2]] -> Either DistanceError RegionDistance
regionDistance accuracy budget limit source target
  | not (finite accuracy) || accuracy <= 0 || limit < 0 || maybe False (\b -> not (finite b) || b < 0) budget = Left (DistanceError "distance accuracy must be positive and finite; budget and work limit must be nonnegative")
  | not (all valid (source ++ target)) = Left (DistanceError "distance regions require finite convex polygons")
  | null sources = Right EmptySource
  | null targets = Right MissingTarget
  | otherwise = Right (BoundedDistance (search 0 initialWitness initialQueue))
  where
    sources = filter ((> 0) . abs . signedArea) source
    targets = map anticlockwise (filter ((> 0) . abs . signedArea) target)
    initial = map measure (concatMap fan sources)
    initialWitness = foldl' farther (Witness 0 (V2 0 0) (V2 0 0)) [w | (_, w, _) <- initial]
    initialQueue = Map.fromList [((upper, index), triangle) | (index, (upper, _, triangle)) <- zip [0 ..] initial]
    measure triangle@(a, b, c) =
      let corners = [a, b, c]
          distances = [[nearestIn ring p | p <- corners] | ring <- targets]
          upper = minimum [maximum [d | Witness d _ _ <- ws] | ws <- distances]
          middle = (1 / 3) *^ (a ^+^ b ^+^ c)
          lower = foldl' farther (nearest middle) [foldl1 nearer ws | ws <- transpose distances]
       in (upper, lower, triangle)
    nearest p = foldl1 nearer [nearestIn ring p | ring <- targets]
    search count witness@(Witness lower from to) queue = case Map.maxViewWithKey queue of
      Nothing -> DistanceBounds lower lower from to count
      Just (((upper, _), triangle), remaining)
        | upper - lower <= accuracy || maybe False (\b -> lower > b || upper <= b) budget || count >= limit -> DistanceBounds lower (max lower upper) from to count
        | otherwise ->
            let children = map measure (bisect triangle)
                nextWitness = foldl' farther witness [w | (_, w, _) <- children]
                nextQueue = foldl' (\q (index, (u, _, t)) -> Map.insert (u, index) t q) remaining (zip [length initial + 2 * count ..] children)
             in search (count + 1) nextWitness nextQueue

-- | Area is in squared page units. The true area beyond the distance budget
-- lies between 'areaOutside' and 'areaOutside' + 'areaUnresolved'. Source
-- polygons must have disjoint interiors, as visible-region pieces do; shared
-- edges are harmless. This precondition is not checked here. Target polygons
-- are a union and may overlap. Empty targets put all source area outside.
data AreaBounds = AreaBounds
  { areaTotal :: Double,
    areaOutside :: Double,
    areaUnresolved :: Double,
    areaSplits :: Int
  }
  deriving stock (Eq, Show)

-- | Keep the very cells that establish the area interval, so a diagnostic
-- drawing can locate its contributions without making another approximation.
-- Cell coordinates use the input's y-up page units; the SVG backend handles
-- the y flip. 'cellArea' is the bisection weight, before coordinate roundoff.
data AreaCell = AreaCell
  { cellArea :: Double,
    cellTriangle :: (V2, V2, V2)
  }
  deriving stock (Eq, Show)

data AreaRegions = AreaRegions
  { regionAreaBounds :: AreaBounds,
    outsideCells :: [AreaCell],
    unresolvedCells :: [AreaCell]
  }
  deriving stock (Eq, Show)

-- | Classify whole triangles, never just their sampled points. The same
-- convex-distance upper bound as 'regionDistance' proves a triangle within
-- budget. Distance to the target region changes by at most the distance moved,
-- so distance at the centroid (the mean of its corners) minus the farthest
-- corner radius bounds every point from below. Only a strictly positive excess proves the whole cell outside.
-- Split the largest unclassified area first. The stopping accuracy is an
-- error allowance on this measurement, NOT an illustration acceptance rule.
-- Each longest-edge bisection halves its parent's area; carry that weight
-- rather than repeatedly subtracting near-collinear coordinates for tiny cells.
areaBeyondBudget :: Double -> Double -> Int -> [[V2]] -> [[V2]] -> Either DistanceError AreaBounds
areaBeyondBudget budget accuracy limit source target = regionAreaBounds <$> areaRegionsBeyondBudget budget accuracy limit source target

-- | The same calculation as 'areaBeyondBudget', retaining the definite and
-- unclassified source regions. Nothing is widened for display, and regions
-- remaining at a work limit are not labelled definitely outside.
areaRegionsBeyondBudget :: Double -> Double -> Int -> [[V2]] -> [[V2]] -> Either DistanceError AreaRegions
areaRegionsBeyondBudget budget accuracy limit source target
  | not (finite budget) || budget < 0 || not (finite accuracy) || accuracy <= 0 || limit < 0 = Left (DistanceError "area accuracy must be positive and finite; distance budget and work limit must be nonnegative")
  | not (all valid (source ++ target)) = Left (DistanceError "area regions require finite convex polygons")
  | null targets = Right (AreaRegions (AreaBounds total total 0 0) [AreaCell area t | (area, t) <- initial, area > 0] [])
  | otherwise = Right (search 0 outside unresolved retained queue)
  where
    sources = filter ((> 0) . abs . signedArea) source
    targets = map anticlockwise (filter ((> 0) . abs . signedArea) target)
    initial = [(abs (cross2 (b ^-^ a) (c ^-^ a)) / 2, t) | t@(a, b, c) <- concatMap fan sources]
    total = sum (map fst initial)
    (outside, unresolved, retained, queue) = foldl' classify (0, 0, [], Map.empty) (zip [0 ..] initial)
    classify (out, pending, kept, cells) (index, (area, t@(a, b, c)))
      | area <= 0 || upper <= budget = (out, pending, kept, cells)
      | lower > budget = (out + area, pending, AreaCell area t : kept, cells)
      | otherwise = (out, pending + area, kept, Map.insert (area, index) t cells)
      where
        corners = [a, b, c]
        upper = minimum [maximum [d | p <- corners, let Witness d _ _ = nearestIn ring p] | ring <- targets]
        middle = (1 / 3) *^ (a ^+^ b ^+^ c)
        nearest = minimum [d | ring <- targets, let Witness d _ _ = nearestIn ring middle]
        radius = maximum [norm (p ^-^ middle) | p <- corners]
        lower = nearest - radius
    search count out pending kept cells
      | pending <= accuracy || count >= limit =
          -- Re-sum the actual remaining cells: incremental subtraction can
          -- leave a roundoff remainder even when every cell was classified.
          let remaining = sum [area | ((area, _), _) <- Map.toList cells]
           in if remaining <= accuracy || count >= limit
                then finish count out remaining kept cells
                else step count out remaining kept cells
      | otherwise = step count out pending kept cells
    step count out pending kept cells = case Map.maxViewWithKey cells of
      Nothing -> finish count out 0 kept cells
      Just (((area, _), triangle), rest) ->
        let children = [(area / 2, t) | t <- bisect triangle]
            (nextOut, nextPending, nextKept, nextCells) = foldl' classify (out, pending - area, kept, rest) (zip [length initial + 2 * count ..] children)
         in search (count + 1) nextOut nextPending nextKept nextCells

    finish count out pending kept cells =
      AreaRegions (AreaBounds total out pending count) (reverse kept) [AreaCell area t | ((area, _), t) <- Map.toList cells]

valid :: [V2] -> Bool
valid ring = all (\(V2 x y) -> finite x && finite y) ring && (finite (signedArea ring) && convex (anticlockwise ring))
  where
    convex points = all (\(a, b) -> all (\p -> cross2 (b ^-^ a) (p ^-^ a) >= 0) points) (edges points)

anticlockwise :: [V2] -> [V2]
anticlockwise ring = if signedArea ring < 0 then reverse ring else ring

fan :: [V2] -> [Triangle]
fan (a : b : c : rest) = (a, b, c) : fan (a : c : rest)
fan _ = []

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)

edges :: [a] -> [(a, a)]
edges ring = zip ring (drop 1 ring ++ take 1 ring)

nearer :: Witness -> Witness -> Witness
nearer a@(Witness x _ _) b@(Witness y _ _) = if x <= y then a else b

farther :: Witness -> Witness -> Witness
farther a@(Witness x _ _) b@(Witness y _ _) = if x > y then a else b

nearestIn :: [V2] -> V2 -> Witness
nearestIn ring p
  | all (\(a, b) -> cross2 (b ^-^ a) (p ^-^ a) >= 0) (edges ring) = Witness 0 p p
  | otherwise = foldl1 nearer [onSegment a b | (a, b) <- edges ring]
  where
    onSegment a b =
      let direction = b ^-^ a
          squared = dot direction direction
          along = if squared <= 0 then 0 else max 0 (min 1 (dot (p ^-^ a) direction / squared))
          q = a ^+^ (along *^ direction)
       in Witness (norm (p ^-^ q)) p q

bisect :: Triangle -> [Triangle]
bisect (a, b, c)
  | ab >= bc && ab >= ca = split a b c
  | bc >= ca = split b c a
  | otherwise = split c a b
  where
    ab = norm (a ^-^ b)
    bc = norm (b ^-^ c)
    ca = norm (c ^-^ a)
    split x y z = let middle = 0.5 *^ (x ^+^ y) in [(x, middle, z), (middle, y, z)]
