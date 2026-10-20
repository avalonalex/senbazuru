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
-- == Two questions asked of any simple polygon
--
-- Whether a point is inside ('insideRing'), and which point is ('pointInside').
-- The mean of the corners does not answer the second for a polygon that is
-- not convex: on an L it can fall in the empty quarter, or on the inside
-- corner. The mean of an /ear/'s corners does ('ears'): a corner whose two
-- neighbours are joined by a segment through the inside of the polygon, so
-- that the triangle it cuts off lies inside. Every simple polygon of four or
-- more corners has two.
--
-- Nothing in this module knows about paper. Coordinates are plain 'V2', and the
-- polygons are lists of corners in order, closed implicitly.
module Senbazuru.Geometry.Polygon
  ( -- * The orientation predicate
    cross2,

    -- * Segments
    distanceToSegment,
    segmentsCross,

    -- * Whole polygons
    edges,
    signedArea,
    centroid,
    isConvex,
    ears,
    pointInside,
    pointsInside,
    largestLowestLeftmost,
    inPreferredOrder,

    -- * Clipping
    clipConvex,
    clipHalfPlane,
    subtractConvex,
    clipSegment,
    strictlyInside,
    insideRing,
    distanceOutside,

    -- * Segments on one line
    collinearOverlap,
  )
where

import Data.List (delete, find, foldl')
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.VectorSpace

-- | The two-dimensional cross product: positive when @v@ turns anticlockwise
-- from @u@, negative when clockwise, zero when they are parallel.
--
-- This is the orientation predicate of @docs\/notes\/robust-predicates.md@ in
-- vector form: @cross2 (b ^-^ a) (p ^-^ a)@ is positive exactly when @p@ lies
-- to the left of the line from @a@ to @b@. Its magnitude is twice the area of
-- the triangle the two vectors span, which is why most tolerances in this
-- module are areas.
--
-- __Most, not all, and each function says which.__ 'segmentsCross' and
-- 'distanceToSegment' take distances, and 'segmentsCross' divides this by a
-- segment length to get there. Two units that are both @Double@ is a real trap
-- and has been sprung: @segmentsCross@ was changed from one to the other and
-- its callers were not, which asked five hundred times the intended clearance
-- on a 400-unit sheet and was invisible to the compiler, to hlint and to a
-- review. Read the function you are calling, not this paragraph.
cross2 :: V2 -> V2 -> Double
cross2 (V2 ux uy) (V2 vx vy) = ux * vy - uy * vx

-- | How far the point is from the segment — from the segment itself, not from
-- the infinite line through it, so a point beyond an end measures to that end.
--
-- A distance rather than a predicate, for the reason 'distanceOutside' gives:
-- the interesting cases are the ones a hair either side of zero, and a
-- yes-or-no answer has already thrown away the hair the caller needs to judge
-- them by.
--
-- A segment of no length names no direction, so the distance to it is the
-- distance to its one point.
distanceToSegment :: (V2, V2) -> V2 -> Double
distanceToSegment (a, b) p
  | lengthSquared <= 0 = norm (p ^-^ a)
  | otherwise = norm (p ^-^ (a ^+^ (along *^ direction)))
  where
    direction = b ^-^ a
    lengthSquared = dot direction direction
    -- Clamped to the segment: past either end, the nearest point is that end.
    along = max 0 (min 1 (dot (p ^-^ a) direction / lengthSquared))

-- | Do the two segments cross at a point in the interior of both?
--
-- \"Interior\" is what makes this the right question for a crease pattern.
-- Segments that merely meet at a shared corner are what a crease pattern is
-- made of; segments that cross in the middle, with no vertex where they meet,
-- are the thing that stops it being a planar graph and stops its faces being
-- traceable at all.
--
-- The tolerance is a __distance__, unlike 'isConvex'\'s and unlike most of this
-- module's: each segment's endpoints have to be clear of the other's /line/ by
-- more than that, on opposite sides. 'cross2' returns twice an area, so it is
-- divided by the segment's length to get there, and that division is the whole
-- point. An area tolerance is a distance tolerance scaled by whatever the
-- segment happens to be long, so two short segments would need to be
-- implausibly far apart to count as crossing — on a unit sheet, a pair a
-- millionth long would need a clearance of a thousandth. A genuine crossing
-- between them would go unreported, and unreported by 'distanceToSegment' too,
-- since their endpoints are nowhere near a distance tolerance of each other.
-- Dividing removes the gap: both questions are then asked in the same units.
--
-- A segment of no length has no direction for the other to be on a side of, so
-- nothing crosses it.
segmentsCross :: Double -> (V2, V2) -> (V2, V2) -> Bool
segmentsCross tolerance first second =
  straddles first second && straddles second first
  where
    -- Are the ends of one segment strictly on opposite sides of the other?
    straddles (a, b) (p, q) =
      length' > 0
        && ( (sideOf p < negate tolerance && sideOf q > tolerance)
               || (sideOf p > tolerance && sideOf q < negate tolerance)
           )
      where
        length' = norm (b ^-^ a)
        sideOf x = cross2 (b ^-^ a) (x ^-^ a) / length'

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

-- | The /ears/ of a simple ring, each with its corner's index, its area and
-- the mean of its three corners.
--
-- An ear is a corner whose two neighbours are joined by a segment through the
-- inside of the ring, touching the outline only at its own two ends
-- (Meisters, 1975), so that cutting off the corner's triangle leaves a simple
-- ring with one corner fewer. The test is the usual one for a simple ring:
-- the corner turns the ring's way, and no other corner lies in its triangle
-- or on the triangle's outline. A triangle passes it at all three corners and
-- has three ears here, though its neighbours are joined by its own side.
--
-- The tolerance is a distance. The corner must turn by more than it: its
-- triangle more than that high at it, which turns away a corner turning the
-- other way and one on a straight run, rounding included. No other corner may
-- come within it of the triangle, except at the triangle's own corners, where
-- a ring that touches itself passes a second time.
--
-- Every simple ring of four or more corners has at least two ears that do not
-- overlap (the two ears theorem, Meisters 1975). The list can still be empty
-- here, for a ring whose corners all turn by less than the tolerance.
--
-- Which way the ring turns is the sign of its area measured from its first
-- corner rather than from the origin, so that rounding in the products of
-- large coordinates cannot decide it for a small ring far from the origin.
ears :: Double -> [V2] -> [(Int, Double, V2)]
ears clearance ring =
  [ (i, area, centroid triangle)
    | (i, (a, b, c)) <- zip [0 ..] (zip3 (lastFirst ring) ring (drop 1 ring <> take 1 ring)),
      let turn = way * cross2 (b ^-^ a) (c ^-^ b)
          area = 0.5 * turn
          triangle = [a, b, c]
          base = norm (c ^-^ a),
      base > 0,
      turn / base > clearance,
      not (any (blocks triangle) ring)
  ]
  where
    n = length ring
    way = case ring of
      first : _ -> signum (signedArea [p ^-^ first | p <- ring])
      [] -> 0
    lastFirst ps = drop (n - 1) ps <> take (n - 1) ps
    blocks triangle p =
      all ((> clearance) . norm . (p ^-^)) triangle
        && (insideRing 0 triangle p || any ((<= clearance) . (`distanceToSegment` p)) (edges triangle))

-- | A point inside the ring, clear of its outline by more than the given
-- distance: the mean of its corners if that is clear, and otherwise the mean
-- of an ear's corners ('ears'). Of the ears whose means are clear, the
-- largest is taken, by 'largestLowestLeftmost'. 'Nothing' if none of these
-- points is clear.
--
-- A ring that is not convex can have the mean of its corners outside it, or
-- on its outline: an L whose arms are as wide as each other has it at its
-- own inside corner. An ear's mean is inside its triangle, which is inside
-- the ring, but it can still lie nearer the outline than the tolerance, so
-- every ear is checked before the largest is chosen, not after.
pointInside :: Double -> [V2] -> Maybe V2
pointInside clearance ring
  | insideRing clearance ring mean = Just mean
  | otherwise = (\(_, _, at) -> at) <$> largestLowestLeftmost clearance [ear | ear@(_, _, at) <- ears clearance ring, insideRing clearance ring at]
  where
    mean = centroid ring

-- | Each ring that has a point inside it ('pointInside'), with its area and
-- that point, for choosing among them by 'largestLowestLeftmost'. A ring with
-- no such point is left out. The anchor is chosen among a sheet's faces this
-- way, and so is a seed among a flap's.
pointsInside :: Double -> [(a, [V2])] -> [(a, Double, V2)]
pointsInside clearance rings = [(a, abs (signedArea ring), at) | (a, ring) <- rings, Just at <- [pointInside clearance ring]]

-- | The largest of some measured things, and among those of one size the one
-- at the lowest point, and then the leftmost. Each comes with its size and
-- its point. A tie in size is a billionth of the largest; a tie in height or
-- across is the distance given. Both are there so that a rounding error in a
-- size or a point cannot decide which is taken. 'Nothing' for none.
--
-- One rule for choosing among faces and among a face's ears ('pointInside'),
-- so that the two cannot drift apart.
largestLowestLeftmost :: Double -> [(a, Double, V2)] -> Maybe (a, Double, V2)
largestLowestLeftmost room measured = case measured of
  [] -> Nothing
  _ ->
    let biggest = maximum [size | (_, size, _) <- measured]
        largest = [m | m@(_, size, _) <- measured, size >= biggest - 1e-9 * biggest]
        lowest = minimum [y | (_, _, V2 _ y) <- largest]
        low = [m | m@(_, _, V2 _ y) <- largest, y <= lowest + room]
        leftmost = minimum [x | (_, _, V2 x _) <- low]
     in find (\(_, _, V2 x _) -> x <= leftmost + room) low

-- | Every one of some measured things, in the order 'largestLowestLeftmost'
-- would take them: the one it takes, then the one it takes from the rest,
-- and so on.
inPreferredOrder :: (Eq a) => Double -> [(a, Double, V2)] -> [(a, Double, V2)]
inPreferredOrder room measured = case largestLowestLeftmost room measured of
  Nothing -> []
  Just taken -> taken : inPreferredOrder room (delete taken measured)

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
-- zero-length edges. An empty result is the empty list. The crossing point is
-- found by interpolating on the two side values, which is what makes the
-- routine safe on the coincident edges a folded model is full of; the
-- comment on @meet@ says why.
clipConvex :: [V2] -> [V2] -> [V2]
clipConvex clip subject = foldl' (flip clipHalfPlane) subject (edges clip)

-- | @clipHalfPlane (a, b) subject@ is the part of @subject@ lying to the left
-- of the directed line from @a@ to @b@, with the line itself counted as inside.
--
-- One step of 'clipConvex', which is the whole of Sutherland–Hodgman: clipping
-- by a convex ring is clipping by each of its edges in turn. It is exposed on
-- its own because 'subtractConvex' needs the /other/ half — the part outside
-- one edge — and that is this function with the edge handed to it backwards.
--
-- @subject@ may be any simple polygon; the result is a single ring when it is
-- convex. The half-plane is unbounded, so nothing here has to be a polygon at
-- all in the sense of enclosing a finite area — @a@ and @b@ only name a
-- direction and a point on it.
clipHalfPlane :: (V2, V2) -> [V2] -> [V2]
clipHalfPlane (a, b) poly = concat [step p q | (p, q) <- edges (rotateBack poly)]
  where
    -- The subject's edges as (previous, current) pairs, so that the corner
    -- emitted is always the current one and the ring stays in order.
    rotateBack ps = drop 1 ps <> take 1 ps

    -- How far inside the line each end of the subject edge is: positive on the
    -- inner side, zero on the line. Computed once and used both for the side
    -- test and for the crossing, which is what keeps the crossing well defined
    -- -- see 'meet'.
    step p q =
      let dp = cross2 (b ^-^ a) (p ^-^ a)
          dq = cross2 (b ^-^ a) (q ^-^ a)
       in case (dp >= 0, dq >= 0) of
            (True, True) -> [q]
            (True, False) -> [meet p q dp dq]
            (False, True) -> [meet p q dp dq, q]
            (False, False) -> []

    -- Where the segment from p to q crosses the line, given how far inside it
    -- each end is. Interpolating on those two values, rather than recomputing
    -- a denominator from the segment's direction, looks like a needless
    -- refactor and is not: only called when one is non-negative and the other
    -- strictly negative, the denominator is a same-sign sum, so it cannot be
    -- zero and @t@ lies in @[0, 1]@ even when the segment runs along the edge
    -- and rounding has put one end a hair outside. The textbook formula
    -- divides by a separately rounded cross product that /can/ be zero there,
    -- sends the crossing to infinity, and makes the area NaN. See
    -- @docs\/notes\/convex-clipping.md@.
    meet p q dp dq = p ^+^ ((dp / (dp - dq)) *^ (q ^-^ p))

-- | @subtractConvex tolerance cutter piece@ is what is left of @piece@ once
-- the interior of @cutter@ has been taken away.
--
-- The answer is a difference of two convex shapes, which is not convex — a
-- square with a bite out of the middle of one side is the smallest example —
-- so it comes back as several pieces rather than one ring. They are each
-- convex, they do not overlap, and together they are exactly @piece@ minus
-- @cutter@'s interior.
--
-- == How, and why it is only this much code
--
-- Walk @cutter@'s edges keeping a running \"still inside every edge so far\"
-- polygon. At each edge, the part of that polygon /outside/ the edge can never
-- be inside @cutter@ — one edge is enough to rule it out — so it is a finished
-- piece; the part inside carries on to the next edge. What survives every edge
-- is the overlap with @cutter@, and is thrown away.
--
-- The pieces are disjoint because the @i@th is outside edge @i@ while every
-- later one is inside it. That is the whole argument, and it is why this needs
-- no general polygon-boolean machinery: subtracting a convex shape is @k@
-- half-plane clips, one per edge, and nothing else.
--
-- Both @cutter@ and @piece@ must be convex and anticlockwise. @cutter@ because
-- 'clipHalfPlane' only adds up to \"inside the polygon\" for a convex one, and
-- @piece@ because Sutherland–Hodgman returns a concave subject as a single ring
-- joined by degenerate corridors: the areas would still be right and the rings
-- would not be shapes anyone could draw.
--
-- @tolerance@ is an area: pieces smaller than it are dropped, which is what
-- removes the slivers left along an edge the two shapes share. A @cutter@ with
-- fewer than three corners encloses nothing and takes nothing away, and so does
-- one whose corners do not enclose anything /between them/ — see 'realEdges'.
subtractConvex :: Double -> [V2] -> [V2] -> [[V2]]
subtractConvex tolerance cutter piece = case realEdges cutter of
  -- Nothing to be outside of. The piece comes back untouched, tolerance and
  -- all: nothing was taken away from it, so there is nothing to have left a
  -- sliver.
  [] -> [piece]
  cuts -> go piece cuts
  where
    go _ [] = []
    go inside ((a, b) : rest) =
      keep (clipHalfPlane (b, a) inside) <> go (clipHalfPlane (a, b) inside) rest

    keep p = [p | abs (signedArea p) > tolerance]

-- | The edges of a ring that have a direction, in order.
--
-- An edge of no length names no side, so 'clipHalfPlane' keeps /everything/ on
-- both sides of it: the part \"outside\" comes back as the whole polygon and is
-- emitted as a finished piece, while the part \"inside\" also comes back whole
-- and carries on to the next edge. The result is pieces that overlap and a
-- total area larger than what went in — a unit square minus a triangle with one
-- corner listed twice came back as 1.5 of paper in two overlapping pieces.
--
-- Rings like that are not hypothetical. Folding brings distinct corners of a
-- sheet together, and clipping repeats a corner wherever a cut passes exactly
-- through one, so any ring that has been through either can carry one.
--
-- The test is exact equality rather than a tolerance, which is the one place in
-- this module that is right. An edge of some tiny length still names a line, so
-- its two half-planes are still complementary and the pieces still partition
-- what went in — badly conditioned, but not wrong. Only at exactly zero does
-- @cross2@ come out zero on /both/ sides and the two halves stop being halves.
realEdges :: [V2] -> [(V2, V2)]
realEdges ring
  | length real < 3 = []
  | otherwise = real
  where
    real = [e | e@(a, b) <- edges ring, a /= b]

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
strictlyInside clearance poly x = distanceOutside poly x < negate clearance

-- | Is the point inside the ring, and clear of every edge by more than the
-- given distance? For any simple ring, convex or not, wound either way.
--
-- 'strictlyInside' asks the same question of a convex ring by half-planes,
-- which is cheaper and is all a convex ring needs. On a ring that is not
-- convex it is wrong in a way that matters: every point beyond the line of an
-- edge that turns inward is called outside, including points well inside the
-- other arm of an L. So this counts how many edges a ray from the point to
-- the right crosses, odd meaning inside, and measures the distance to each
-- edge as a segment rather than as a line.
insideRing :: Double -> [V2] -> V2 -> Bool
insideRing clearance ring x@(V2 px py) = odd crossings && all ((> clearance) . (`distanceToSegment` x)) (edges ring)
  where
    crossings = length [() | (V2 ax ay, V2 bx by) <- edges ring, (ay > py) /= (by > py), px < ax + (py - ay) * (bx - ax) / (by - ay)]

-- | How far outside the convex, anticlockwise polygon the point is: positive
-- outside, zero on the boundary, negative inside, and in either case the
-- distance to the nearest edge's line.
--
-- The whole of \"where is this point\" in one number, which is what makes it
-- possible to ask the question with a tolerance in either direction: more than
-- a hair outside, more than a hair inside, or on the boundary. A yes-or-no
-- predicate can only answer two of those three.
--
-- Preferred to clipping a segment against the polygon and looking at what
-- survives, which sounds equivalent and is not. A segment lying /along/ an edge
-- is the case a folded model produces constantly, and there the clip is decided
-- by whether rounding put the segment a hair inside the edge or a hair outside
-- it: one way it comes back whole, the other it comes back empty, and there is
-- no tolerance anywhere to say the two answers are the same. This returns the
-- hair, and lets the caller decide it is a hair.
--
-- Edges of no length are skipped. They name no direction, so the distance to
-- them is not a number; a ring that carries one — clipping leaves them wherever
-- a cut passed exactly through a corner — would otherwise report every point as
-- outside it.
distanceOutside :: [V2] -> V2 -> Double
distanceOutside poly x =
  maximum
    ( negate (1 / 0)
        : [ negate (cross2 (b ^-^ a) (x ^-^ a)) / norm (b ^-^ a)
            | (a, b) <- edges poly,
              norm (b ^-^ a) > 0
          ]
    )

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
