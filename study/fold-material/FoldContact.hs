-- | Check the known bottom-to-top order of the nearly flat study packets.
--
-- A layer is one panel between the prescribed creases. Project each triangle
-- onto the xy plane, intersect overlapping footprints, then compare heights
-- at every corner of that intersection. Height is linear inside a triangle,
-- so its largest ordering error occurs at one of these corners. Checking only
-- original vertices would miss crossings between projected triangle edges.
--
-- The same overlaps supply local separation constraints to the study solver.
-- This assumes the original packet order and checks different layers only.
-- It cannot certify arbitrary
-- folds, self-contact inside a panel, motion between checkpoints or clearance
-- for finite paper thickness. An edge-on triangle has no height function and
-- is counted as unchecked, never silently treated as clear. The tolerances
-- below apply to this study's unit square, not arbitrary model scales.
module FoldContact (PacketCheck (..), ContactRow (..), packetCheck, packetContacts, contactTolerance) where

import Data.IntMap.Strict qualified as IM
import Data.List (find, tails)
import Data.Maybe (mapMaybe)
import FoldMaterial
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (clipConvex, cross2, distanceToSegment, signedArea)
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace

data PacketCheck = PacketCheck
  { violatingPairs :: !Int,
    maxOrderViolation :: !Double,
    uncheckedTriangles :: !Int
  }
  deriving stock (Eq, Show)

-- | Positive gap means the upper layer is above the lower one. The gradient
-- describes how that gap changes when the listed vertices move. Shared vertex
-- contributions cancel, keeping a crease joined rather than pulling it apart.
data ContactRow = ContactRow
  { contactGap :: !Double,
    contactGradient :: ![(Int, V3)]
  }
  deriving stock (Eq, Show)

contactTolerance :: Double
contactTolerance = 1e-7

data Projected = Projected
  { layer :: !Int,
    footprint :: ![V2],
    bounds :: !(Double, Double, Double, Double),
    heightAt :: V2 -> Double,
    weightsAt :: V2 -> [(Int, Double)],
    planeNormal :: !V3,
    corners :: ![V3]
  }

-- | Positive violation means a supposedly lower layer lies ABOVE an upper
-- one. Coplanar contact is allowed: this is a zero-thickness surface study.
-- Input must be a valid indexed study mesh in its original packet orientation.
packetCheck :: FoldCase -> Mesh -> PacketCheck
packetCheck which mesh = PacketCheck (length (filter (> contactTolerance) violations)) (maximum (0 : violations)) unchecked
  where
    (pairs, unchecked) = contactPairs which mesh
    violations = [maximum (0 : map (negate . contactGap) rows) | rows <- pairs]

packetContacts :: FoldCase -> Mesh -> ([ContactRow], Int)
packetContacts which mesh = let (pairs, unchecked) = contactPairs which mesh in (concat pairs, unchecked)

contactPairs :: FoldCase -> Mesh -> ([[ContactRow]], Int)
contactPairs which mesh = (mapMaybe checkPair pairs, unchecked)
  where
    vertices = IM.fromList (zip [0 ..] (samples mesh))
    resolve (i, j, k) = (,,) <$> IM.lookup i vertices <*> IM.lookup j vertices <*> IM.lookup k vertices
    projectIndexed ids = resolve ids >>= projectTriangle ids
    projected = mapMaybe projectIndexed (triangles mesh)
    unchecked = length (triangles mesh) - length projected
    pairs = [(a, b) | a : rest <- tails projected, b <- rest, layer a /= layer b]
    projectTriangle (i, j, k) (a, b, c)
      | abs determinant <= 1e-14 = Nothing
      | otherwise = Just (Projected order ring box height weights (V3 (-slopeX) (-slopeY) 1) (map position [a, b, c]))
      where
        xy s = let V3 x y _ = position s in V2 x y
        z s = let V3 _ _ value = position s in value
        pa = xy a
        ab = xy b ^-^ pa
        ac = xy c ^-^ pa
        determinant = cross2 ab ac
        ring = if determinant > 0 then [pa, xy b, xy c] else [pa, xy c, xy b]
        xs = [x | V2 x _ <- ring]
        ys = [y | V2 _ y <- ring]
        -- Three coordinates are always present; fold from the first corner.
        V2 ax ay = pa
        box = (foldr min ax xs, foldr max ax xs, foldr min ay ys, foldr max ay ys)
        height p =
          z a
            + cross2 (p ^-^ pa) ac / determinant * (z b - z a)
            + cross2 ab (p ^-^ pa) / determinant * (z c - z a)
        -- At a fixed projected point, moving a corner horizontally also
        -- changes the triangle's height if the triangle is tilted.
        slopeX = height (pa ^+^ V2 1 0) - z a
        slopeY = height (pa ^+^ V2 0 1) - z a
        weights p =
          let wb = cross2 (p ^-^ pa) ac / determinant
              wc = cross2 ab (p ^-^ pa) / determinant
           in [(i, 1 - wb - wc), (j, wb), (k, wc)]
        u = (materialU a + materialU b + materialU c) / 3
        v = (materialV a + materialV b + materialV c) / 3
        firstHalf = if u <= 0.5 then 0 else 1
        order = if which == Single || v <= 0.5 then 2 + firstHalf else 1 - firstHalf
    checkPair (a, b)
      | separate (bounds a) (bounds b) = Nothing
      | abs (signedArea overlap) <= 1e-14 = Nothing
      | otherwise = Just (map row overlap)
      where
        overlap = clipConvex (footprint a) (footprint b)
        (lower, upper) = if layer a < layer b then (a, b) else (b, a)
        row p =
          let normal = contactNormal p lower upper
              gradient = [(i, w *^ normal) | (i, w) <- weightsAt upper p] ++ [(i, (-w) *^ normal) | (i, w) <- weightsAt lower p]
           in ContactRow (heightAt upper p - heightAt lower p) (IM.toList (IM.fromListWith (^+^) gradient))
    separate (ax, bx, ay, by) (cx, dx, cy, dy) = bx <= cx || dx <= ax || by <= cy || dy <= ay

-- | The overlap corner moves with the triangles. At a vertex/face contact use
-- the FACE normal; at an edge/edge contact use a normal to BOTH edges. Using
-- each triangle's own normal would differentiate heights at a fixed xy point,
-- missing the movement of the very intersection at which we measure the gap.
-- Normalising z to one makes the residual a vertical separation in model units.
contactNormal :: V2 -> Projected -> Projected -> V3
contactNormal p lower upper
  | atCorner lower = planeNormal upper
  | atCorner upper = planeNormal lower
  | Just lowerEdge <- edgeAt lower,
    Just upperEdge <- edgeAt upper,
    let normal@(V3 _ _ z) = cross lowerEdge upperEdge,
    abs z > 1e-14 =
      (1 / z) *^ normal
  | otherwise = planeNormal upper
  where
    xy (V3 x y _) = V2 x y
    atCorner face = any (\v -> norm (p ^-^ xy v) < 1e-10) (corners face)
    edgeAt face =
      let pairs = zip (corners face) (drop 1 (corners face) ++ take 1 (corners face))
       in fmap (\(a, b) -> b ^-^ a) (find (\(a, b) -> distanceToSegment (xy a, xy b) p < 1e-10) pairs)
