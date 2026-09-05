-- |
-- Module      : Senbazuru.Geometry.Polygon
-- Description : Convex polygons in the plane: area, clipping, and what a segment does inside one.
--
-- The layer solver in "Senbazuru.Origami.Stacking" has one geometric question
-- to ask over and over: do these two faces of a flat-folded model share any
-- /interior/? Not \"do they touch\" — in a folded model faces touch constantly,
-- along every crease and at every corner — but \"is there a patch of paper with
-- both of them over it\". This module answers that, and a few relatives, for
-- __convex__ polygons.
--
-- == Why area rather than a yes\/no test
--
-- The textbook test for polygon overlap is a pair of predicates: some edge of
-- one properly crosses an edge of the other, or some vertex of one lies
-- strictly inside the other. A flat-folded model breaks it at once. Fold a
-- square into quarters and all four faces land on the /same/ quadrant: no edge
-- crosses any other, no vertex is strictly inside anything, and the four faces
-- overlap completely. Adding cases for coincident vertices, shared edges and
-- inscribed polygons is how a predicate grows a bug for every fixture.
--
-- Computing the intersection instead is one algorithm with no cases. Clip one
-- polygon by the other with Sutherland–Hodgman ('clipConvex'), take the area of
-- what is left, and compare it with a tolerance. Two identical squares clip to
-- a square. Two squares sharing an edge clip to a sliver of zero area. A
-- triangle inscribed in a square clips to itself. Every degenerate case above
-- is answered by the same three lines, and the tolerance is the one place a
-- judgement is made. See @docs\/notes\/convex-clipping.md@.
--
-- == Why convex
--
-- Sutherland–Hodgman clips against each edge of the clip polygon in turn,
-- keeping the half-plane on the inside. That is only the polygon's interior if
-- the polygon is the intersection of those half-planes, which is what convex
-- means. Clipping by a concave polygon quietly keeps too much. The faces of a
-- flat-foldable crease pattern are convex whenever the sheet is — Kawasaki's
-- theorem forces every sector at an interior vertex under 180° — so the
-- restriction costs little here, and 'isConvex' is how a caller checks before
-- trusting the answer.
--
-- Nothing in this module knows about paper. Coordinates are plain 'V2', and the
-- polygons are lists of corners in order, closed implicitly.
module Senbazuru.Geometry.Polygon
  ( -- * The orientation predicate
    cross2,

    -- * Whole polygons
    signedArea,
    centroid,
    isConvex,

    -- * Clipping
    clipConvex,
    clipSegment,
    strictlyInside,

    -- * Segments on one line
    collinearOverlap,
  )
where

import Data.List (foldl')
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.VectorSpace

-- | The two-dimensional cross product: positive when @v@ turns anticlockwise
-- from @u@, negative when clockwise, zero when they are parallel.
--
-- This is the orientation predicate of @docs\/notes\/robust-predicates.md@ in
-- vector form: @cross2 (b ^-^ a) (p ^-^ a)@ is positive exactly when @p@ lies
-- to the left of the line from @a@ to @b@. Its magnitude is twice the area of
-- the triangle the two vectors span, which is why every tolerance in this
-- module is an area.
cross2 :: V2 -> V2 -> Double
cross2 (V2 ux uy) (V2 vx vy) = ux * vy - uy * vx

-- | The consecutive pairs around a closed ring: each corner with the next, and
-- the last with the first. Polymorphic so that it also pairs up consecutive
-- edges, which is how 'isConvex' finds the turn at each corner.
edges :: [a] -> [(a, a)]
edges ps = zip ps (drop 1 ps <> take 1 ps)

-- | The area enclosed, positive for an anticlockwise ring and negative for a
-- clockwise one.
--
-- The shoelace formula: half the sum of 'cross2' over consecutive corners. The
-- sign is the winding, which is the whole reason it is not thrown away — a face
-- of a folded model that comes out clockwise has been turned over.
signedArea :: [V2] -> Double
signedArea ps = 0.5 * sum [cross2 a b | (a, b) <- edges ps]

-- | The mean of the corners.
--
-- Not the centre of mass, which weights by area; for the one use this has —
-- deciding which side of a line a convex polygon sits on when one of its edges
-- lies along that line — the mean is enough and simpler. Every corner is on
-- the line or on one side of it, and at least one is strictly to the side, so
-- the mean is strictly to that side too.
centroid :: [V2] -> V2
centroid [] = V2 0 0
centroid ps = (1 / fromIntegral (length ps)) *^ foldl' (^+^) (V2 0 0) ps

-- | Does the ring turn the same way at every corner?
--
-- The tolerance is an area: a turn whose 'cross2' is smaller than it in
-- magnitude counts as straight on, so a corner that sits in the middle of a
-- straight side — which real crease patterns have wherever a crease ends on
-- the far side of an edge — does not make a square concave. Without it the
-- test would hang on the sign of a rounding error.
isConvex :: Double -> [V2] -> Bool
isConvex tolerance ps = not (any (> tolerance) turns && any (< negate tolerance) turns)
  where
    turns = [cross2 (b ^-^ a) (c ^-^ b) | ((a, b), (_, c)) <- edges (edges ps)]

-- | @clipConvex clip subject@ is the part of @subject@ inside @clip@.
--
-- Sutherland–Hodgman: for each edge of @clip@ in turn, walk round @subject@
-- keeping what lies on the inner side of that edge's line and inserting the
-- crossing point wherever the ring steps over it. After every edge has had its
-- turn, what remains is inside all of them, which for a convex @clip@ is inside
-- the polygon.
--
-- @clip@ must be convex and anticlockwise; @subject@ can be any simple
-- polygon, though the result is only guaranteed to be a single ring if it is
-- convex too. The output may repeat a corner where the ring touches a clip
-- edge exactly, which costs nothing when all anybody wants is its area.
--
-- Points exactly on a clip edge count as inside, so clipping a polygon by
-- itself gives it back rather than a ring of duplicated corners and
-- zero-length edges. An empty result is the empty list.
clipConvex :: [V2] -> [V2] -> [V2]
clipConvex clip subject = foldl' clipBy subject (edges clip)
  where
    clipBy poly (a, b) = concat [step (a, b) p q | (p, q) <- edges (rotateBack poly)]

    -- The subject's edges as (previous, current) pairs, so that the corner
    -- emitted is always the current one and the ring stays in order.
    rotateBack ps = drop 1 ps <> take 1 ps

    inside a b p = cross2 (b ^-^ a) (p ^-^ a) >= 0

    step (a, b) p q = case (inside a b p, inside a b q) of
      (True, True) -> [q]
      (True, False) -> [meet a b p q]
      (False, True) -> [meet a b p q, q]
      (False, False) -> []

    -- Where the segment from p to q crosses the line through a and b. Only
    -- called when p and q are on opposite sides, so the two are not parallel
    -- and the denominator is not zero.
    meet a b p q = p ^+^ (t *^ (q ^-^ p))
      where
        t = cross2 (b ^-^ a) (a ^-^ p) / cross2 (b ^-^ a) (q ^-^ p)

-- | The part of a segment that lies inside a convex, anticlockwise polygon,
-- boundary included, or 'Nothing' if it misses.
--
-- Cyrus–Beck: the segment is @p + t (q - p)@ for @t@ from 0 to 1, and each
-- edge of the polygon cuts that interval down to the side it keeps. What is
-- left is the answer. A segment lying exactly along an edge is returned whole,
-- because points on the boundary count as inside; use 'strictlyInside' on its
-- midpoint to tell that case from a segment that crosses the interior.
clipSegment :: [V2] -> (V2, V2) -> Maybe (V2, V2)
clipSegment poly (p, q) = go 0 1 (edges poly)
  where
    d = q ^-^ p

    go t0 t1 []
      | t0 <= t1 = Just (p ^+^ (t0 *^ d), p ^+^ (t1 *^ d))
      | otherwise = Nothing
    go t0 t1 ((a, b) : rest)
      -- How far inside the edge's line the segment is, as a function of t:
      -- at + slope * t. The segment is inside where that is non-negative.
      | slope == 0 = if at < 0 then Nothing else go t0 t1 rest
      | slope > 0 = go (max t0 crossing) t1 rest
      | otherwise = go t0 (min t1 crossing) rest
      where
        n = b ^-^ a
        at = cross2 n (p ^-^ a)
        slope = cross2 n d
        crossing = negate at / slope

-- | Is the point inside the convex, anticlockwise polygon by more than the
-- given distance, on every side?
--
-- The tolerance is a distance rather than an area here because that is the
-- question being asked: is this point clear of every edge. It is what tells a
-- segment that runs along an edge of a face from one that runs through it.
strictlyInside :: Double -> [V2] -> V2 -> Bool
strictlyInside clearance poly x =
  and [cross2 (b ^-^ a) (x ^-^ a) > clearance * norm (b ^-^ a) | (a, b) <- edges poly]

-- | The stretch two segments have in common, when they lie on one line.
--
-- 'Nothing' unless both ends of the second segment are within @tolerance@ of
-- the line through the first /and/ the two overlap by more than @tolerance@
-- along it. Segments that merely touch at a point, or that lie on parallel
-- lines a hair apart, share nothing. The result runs in the direction of the
-- first segment.
collinearOverlap :: Double -> (V2, V2) -> (V2, V2) -> Maybe (V2, V2)
collinearOverlap tolerance (p, q) (r, s)
  | len <= tolerance = Nothing
  | offLine r || offLine s = Nothing
  | (hi - lo) * len <= tolerance = Nothing
  | otherwise = Just (p ^+^ (lo *^ d), p ^+^ (hi *^ d))
  where
    d = q ^-^ p
    len = norm d

    offLine x = abs (cross2 d (x ^-^ p)) > tolerance * len

    -- Where a point on the line sits along the first segment, as a fraction of
    -- its length: 0 at p, 1 at q.
    along x = dot (x ^-^ p) d / (len * len)

    lo = max 0 (min (along r) (along s))
    hi = min 1 (max (along r) (along s))
