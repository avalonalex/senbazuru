-- | Distance to violating an existing lower/upper triangle relationship.
--
-- Imagine extending the upper triangle indefinitely along the contact axis.
-- The lower triangle must stay outside that volume. Unlike a height sampled
-- only where shadows overlap, distance to this volume also shrinks when a
-- wrongly ordered triangle approaches from the side. That supplies a warning
-- before the projected overlap appears. This is a directional layer constraint,
-- not ordinary unsigned distance between two pieces of paper.
--
-- For points a on the lower and b on the upper triangle, minimise
-- |(b-a)_perpendicular|^2 + max(0, (b-a)_along_axis)^2.
-- If the along-axis difference is positive, the closest features are ordinary
-- 3D triangle features. If negative, they are closest projected features.
-- At zero the two quadratics have the same derivative. Enumerating both sets
-- therefore covers the minimum, including its boundary. Parallel feature ties
-- can give more than one gradient; the selected witness gives one local branch.
--
-- Inputs are already validated by SurfaceContact: a unit axis and finite,
-- nondegenerate triangles. Barycentric weights express each closest point as a
-- weighted average of its three material vertices. At a minimizing witness, differentiating its weights is
-- unnecessary: the derivative of distance along those free coordinates is zero.
-- The endpoint weights distribute equal and opposite positional derivatives
-- back to the original shared vertex ids. No vertex is copied or welded.
module DirectionalDistance (TrianglePoints, DistanceSample (..), orderDistance) where

import Data.IntMap.Strict qualified as IM
import Data.List (foldl')
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace

type TrianglePoints = ((Int, V3), (Int, V3), (Int, V3))

data DistanceSample = DistanceSample
  { distanceValue :: !Double,
    distanceGradient :: ![(Int, V3)]
  }
  deriving stock (Eq, Show)

data Point = Point !V3 ![(Int, Double)]

data Witness = Witness !Point !Point

orderDistance :: V3 -> TrianglePoints -> TrianglePoints -> DistanceSample
orderDistance axis lower upper =
  let as = points lower
      bs = points upper
      perpendicular p = p ^-^ (dot axis p *^ axis)
      vector (Witness (Point a _) (Point b _)) =
        let delta = b ^-^ a
         in delta ^-^ (min 0 (dot axis delta) *^ axis)
      squared witness = let d = vector witness in dot d d
      initial = Witness (single (first lower)) (single (first upper))
      witnesses = features id as bs ++ features perpendicular as bs
      best = foldl' (\a b -> if squared b < squared a then b else a) initial witnesses
      size = sqrt (squared best)
      normal = if size > 0 then (1 / size) *^ vector best else V3 0 0 0
      Witness (Point _ aw) (Point _ bw) = best
      gradient = IM.fromListWith (^+^) ([(i, (-w) *^ normal) | (i, w) <- aw] ++ [(i, w *^ normal) | (i, w) <- bw])
   in DistanceSample size (IM.toList gradient)
  where
    first (a, _, _) = a
    single (i, p) = Point p [(i, 1)]
    points (a, b, c) = map single [a, b, c]

-- All boundary cases are included explicitly: vertex/vertex, vertex/edge,
-- vertex/interior and edge/edge. A parallel pair has a closest endpoint witness;
-- no division by its zero determinant is needed.
features :: (V3 -> V3) -> [Point] -> [Point] -> [Witness]
features metric as bs =
  [Witness a b | a <- as, b <- bs]
    ++ [Witness a (onEdge metric a b c) | a <- as, (b, c) <- edges bs]
    ++ [Witness (onEdge metric b a c) b | b <- bs, (a, c) <- edges as]
    ++ [Witness a b | a <- as, b <- onFace metric a bs]
    ++ [Witness a b | b <- bs, a <- onFace metric b as]
    ++ [Witness a b | ae <- edges as, be <- edges bs, (a, b) <- betweenEdges metric ae be]

edges :: [a] -> [(a, a)]
edges xs = zip xs (drop 1 xs ++ take 1 xs)

pointValue :: Point -> V3
pointValue (Point p _) = p

blend :: [(Double, Point)] -> Point
blend terms = Point (foldl' (^+^) (V3 0 0 0) [w *^ p | (w, Point p _) <- terms]) [(i, w * v) | (w, Point _ weights) <- terms, (i, v) <- weights]

onEdge :: (V3 -> V3) -> Point -> Point -> Point -> Point
onEdge metric p a b =
  let u = metric (pointValue b ^-^ pointValue a)
      v = metric (pointValue p ^-^ pointValue a)
      size = dot u u
      t = if size > 0 then max 0 (min 1 (dot v u / size)) else 0
   in blend [(1 - t, a), (t, b)]

onFace :: (V3 -> V3) -> Point -> [Point] -> [Point]
onFace metric p [a, b, c] =
  let u = metric (pointValue b ^-^ pointValue a)
      v = metric (pointValue c ^-^ pointValue a)
      w = metric (pointValue p ^-^ pointValue a)
      n = cross u v
      determinant = dot n n
      s = dot (cross w v) n / determinant
      t = dot (cross u w) n / determinant
   in [blend [(1 - s - t, a), (s, b), (t, c)] | determinant > 0, s >= 0, t >= 0, s + t <= 1]
onFace _ _ _ = []

betweenEdges :: (V3 -> V3) -> (Point, Point) -> (Point, Point) -> [(Point, Point)]
betweenEdges metric (pa, qa) (pb, qb) =
  let u = metric (pointValue qa ^-^ pointValue pa)
      v = metric (pointValue qb ^-^ pointValue pb)
      w = metric (pointValue pa ^-^ pointValue pb)
      a = dot u u
      b = dot u v
      c = dot v v
      d = dot u w
      e = dot v w
      n = cross u v
      determinant = dot n n
      s = (b * e - c * d) / determinant
      t = (a * e - b * d) / determinant
   in [(blend [(1 - s, pa), (s, qa)], blend [(1 - t, pb), (t, qb)]) | determinant > 0, s >= 0, s <= 1, t >= 0, t <= 1]
