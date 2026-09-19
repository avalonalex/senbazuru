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
-- Bounds use ordinary floating-point geometry, not interval arithmetic; they
-- retain its roundoff limits. No positive area is discarded as "too small".
module IllustrationDistance
  ( DistanceError (..),
    RegionDistance (..),
    DistanceBounds (..),
    regionDistance,
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
    valid ring = all (\(V2 x y) -> finite x && finite y) ring && (finite (signedArea ring) && convex (anticlockwise ring))
    anticlockwise ring = if signedArea ring < 0 then reverse ring else ring
    convex ring = all (\(a, b) -> all (\p -> cross2 (b ^-^ a) (p ^-^ a) >= 0) ring) (edges ring)
    fan (a : b : c : rest) = (a, b, c) : fan (a : c : rest)
    fan _ = []
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
