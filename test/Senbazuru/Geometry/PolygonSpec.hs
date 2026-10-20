-- QuickCheck's Arbitrary is somebody else's class and V2 and Box2 are the
-- library's types, so instances for them are orphans wherever they are written.
-- The alternatives are worse: putting them in the library drags QuickCheck into
-- it, and wrapping every generated point in a newtype obscures every property
-- here. A test suite is the one place an orphan costs nothing, since nothing
-- else imports it.
{-# OPTIONS_GHC -Wno-orphans #-}

-- |
-- Tests for convex polygons in the plane.
--
-- Clipping gets property tests, because the interesting failures are at inputs
-- nobody would write down: boxes that share an edge, a corner exactly on a
-- line, a polygon clipped by itself. Axis-aligned boxes make a good generator
-- for that, since the area of their intersection can be worked out by hand —
-- overlap in @x@ times overlap in @y@ — and compared with what the clipper
-- produces on the same input.
--
-- The rest are examples, chosen as the cases the layer solver depends on: a
-- segment along a face's edge is not a segment through its interior, and two
-- segments that touch at a point share nothing.
module Senbazuru.Geometry.PolygonSpec (spec) where

import Data.List (tails)
import Senbazuru.Geometry (V2 (..), norm, (*^), (^+^), (^-^))
import Senbazuru.Geometry.Polygon
import Test.Hspec
import Test.QuickCheck

-- | An axis-aligned box as its corners, anticlockwise.
data Box2 = Box2 !Double !Double !Double !Double
  deriving stock (Show)

-- | Points on a modest grid rather than anywhere in the plane.
--
-- Whole tenths over a small range, so that a counterexample is a pair of
-- numbers a reader can plot rather than eighteen digits of float, and so that
-- coincidences worth hitting -- the same point twice, three points in a line --
-- come up often instead of never. See docs/notes/shrinking.md.
instance Arbitrary V2 where
  arbitrary = V2 <$> coordinate <*> coordinate
    where
      coordinate = (/ 10) . fromIntegral <$> choose (-30 :: Int, 30)
  shrink (V2 x y) = [V2 x' y | x' <- shrink x] <> [V2 x y' | y' <- shrink y]

instance Arbitrary Box2 where
  arbitrary = do
    -- Integer coordinates on purpose: they make coincident edges and corners
    -- common rather than measure-zero, which is what the degenerate cases
    -- need. Widths of zero are excluded so every box has an area.
    x0 <- choose (-5, 5)
    y0 <- choose (-5, 5)
    w <- choose (1, 6)
    h <- choose (1, 6)
    pure (Box2 x0 y0 (x0 + w) (y0 + h))

corners :: Box2 -> [V2]
corners (Box2 x0 y0 x1 y1) = [V2 x0 y0, V2 x1 y0, V2 x1 y1, V2 x0 y1]

area :: Box2 -> Double
area (Box2 x0 y0 x1 y1) = (x1 - x0) * (y1 - y0)

-- | The area two boxes have in common, worked out directly.
boxOverlap :: Box2 -> Box2 -> Double
boxOverlap (Box2 ax0 ay0 ax1 ay1) (Box2 bx0 by0 bx1 by1) =
  max 0 (min ax1 bx1 - max ax0 bx0) * max 0 (min ay1 by1 - max ay0 by0)

unitSquare :: [V2]
unitSquare = [V2 0 0, V2 1 0, V2 1 1, V2 0 1]

-- | A simple ring, often not convex: three to nine corners at increasing
-- angles round the origin, each in its own slice of the turn, at radii from 1
-- to 3. With four or more corners, consecutive corners are less than half a
-- turn apart, so the ring is star-shaped about the origin, which makes it
-- simple. Three corners are a triangle, simple however they fall, though the
-- origin can lie outside it and it can run clockwise.
starRing :: Gen [V2]
starRing = do
  n <- choose (3, 9 :: Int)
  sequence
    [ do
        t <- choose (0, 0.9)
        r <- choose (1, 3)
        let angle = 2 * pi * (fromIntegral k + t) / fromIntegral n
        pure (r *^ V2 (cos angle) (sin angle))
      | k <- [0 .. n - 1]
    ]

-- | An L-shaped ring: arms 1 to 3 long and 0.05 to 1 wide, turned any way,
-- moved anywhere within 10 of the origin, and starting at any corner. Its
-- mean of corners is off it, in the square its arms leave empty, whenever
-- each arm is at least twice as long as the other is wide, which is most of
-- the time.
lRing :: Gen [V2]
lRing = do
  long <- choose (1, 3)
  tall <- choose (1, 3)
  wide <- choose (0.05, 1)
  high <- choose (0.05, 1)
  angle <- choose (0, 2 * pi)
  shift <- V2 <$> choose (-10, 10) <*> choose (-10, 10)
  start <- choose (0, 5)
  let turned (V2 x y) = V2 (x * cos angle - y * sin angle) (x * sin angle + y * cos angle) ^+^ shift
      placed = map turned [V2 0 0, V2 long 0, V2 long high, V2 wide high, V2 wide tall, V2 0 tall]
  pure (drop start placed <> take start placed)

-- | Issue #579's L-shaped face: a rectangle 0.6 by 1 with its top-left
-- quarter, 0.3 by 0.5, missing.
lShape :: [V2]
lShape = [V2 0 0, V2 0.6 0, V2 0.6 1, V2 0.3 1, V2 0.3 0.5, V2 0 0.5]

-- | Close enough, for numbers that came out of a few multiplications.
near :: Double -> Double -> Bool
near a b = abs (a - b) < 1e-9

spec :: Spec
spec = do
  describe "distanceToSegment" $ do
    it "measures to the segment, not to the line through it" $ do
      -- The clamp is the whole of it: a point beyond an end is as far away as
      -- that end, where the infinite line would call it a distance of nothing.
      distanceToSegment (V2 0 0, V2 1 0) (V2 2 0) `shouldBe` 1
      distanceToSegment (V2 0 0, V2 1 0) (V2 0.5 3) `shouldBe` 3

    it "measures to the one point of a segment with no length" $
      distanceToSegment (V2 1 1, V2 1 1) (V2 4 5) `shouldBe` 5

    it "is never more than the distance to either end" $
      -- The property that says the clamp is a clamp and not a cut-off: some
      -- point of the segment is always at least as close as its ends.
      property $ \a b p ->
        distanceToSegment (a, b) p <= norm (p ^-^ a) + 1e-9
          && distanceToSegment (a, b) p <= norm (p ^-^ b) + 1e-9

    it "is zero along the segment and nowhere else" $
      property $ \a b (t :: Double) ->
        a /= b ==>
          let along = max 0 (min 1 t)
              on = a ^+^ (along *^ (b ^-^ a))
           in distanceToSegment (a, b) on < 1e-9

  describe "segmentsCross" $ do
    it "reports a plain crossing" $
      segmentsCross 1e-9 (V2 0 0, V2 2 2) (V2 0 2, V2 2 0) `shouldBe` True

    it "does not report segments that only meet at an end" $
      -- What a crease pattern is made of. If this were a crossing, every
      -- corner of every sheet would be one.
      segmentsCross 1e-9 (V2 0 0, V2 1 0) (V2 1 0, V2 1 1) `shouldBe` False

    it "does not report segments that miss each other" $
      segmentsCross 1e-9 (V2 0 0, V2 1 0) (V2 0 1, V2 1 1) `shouldBe` False

    it "does not report a T, where one segment ends on the other" $
      -- Touching is not crossing: the stem's end is on the bar, not through
      -- it. It is Senbazuru.Fold.Faces's distanceToSegment check that has to
      -- notice a T, and it does.
      segmentsCross 1e-9 (V2 0 0, V2 2 0) (V2 1 0, V2 1 1) `shouldBe` False

    it "reports a crossing between two very short segments" $ do
      -- The reason the tolerance is a distance and not an area. cross2 returns
      -- twice an area, so against an area tolerance the clearance a pair needs
      -- grows as they get shorter: a millionth-long pair on a unit sheet would
      -- have needed a thousandth of clearance, and a real crossing between
      -- them would have gone unreported by this and by every distance check
      -- too.
      let tiny = 1e-6
      segmentsCross 1e-9 (V2 0 0, V2 tiny tiny) (V2 0 tiny, V2 tiny 0) `shouldBe` True

    it "nothing crosses a segment of no length" $
      segmentsCross 1e-9 (V2 1 1, V2 1 1) (V2 0 0, V2 2 2) `shouldBe` False

    it "does not care which segment is named first" $
      property $ \a b c d ->
        segmentsCross 1e-9 (a, b) (c, d) === segmentsCross 1e-9 (c, d) (a, b)

  describe "signedArea" $ do
    it "is positive anticlockwise and negative clockwise" $ do
      signedArea unitSquare `shouldBe` 1
      signedArea (reverse unitSquare) `shouldBe` (-1)

    it "is the box's area for any box" $
      property $
        \b -> signedArea (corners b) `near` area b

  describe "clipConvex" $ do
    it "matches the overlap of two boxes worked out by hand" $
      -- The whole point of the module in one property. Shared edges, touching
      -- corners and nested boxes all come up under this generator, and the
      -- clipper has to agree with plain arithmetic on every one.
      property $ \a b ->
        abs (signedArea (clipConvex (corners a) (corners b))) `near` boxOverlap a b

    it "gives a polygon back when clipped by itself" $
      property $
        \b -> abs (signedArea (clipConvex (corners b) (corners b))) `near` area b

    it "keeps an inscribed triangle whole" $ do
      -- No vertex of the triangle is strictly inside the square and no edge
      -- crosses another, which is the case a predicate-based overlap test gets
      -- wrong. The area comes out right because nothing is being tested for.
      let triangle = [V2 0.5 0, V2 1 0.5, V2 0.5 1]
      abs (signedArea (clipConvex unitSquare triangle)) `shouldSatisfy` near 0.25

    it "leaves nothing of two squares sharing an edge" $
      abs (signedArea (clipConvex unitSquare [V2 1 0, V2 2 0, V2 2 1, V2 1 1]))
        `shouldSatisfy` near 0

    it "survives a subject edge lying along a clip edge, one end a hair outside" $ do
      -- The case that silently dropped constraints in the layer solver. The
      -- subject's first edge runs along the clip's diagonal: one end is 1e-17
      -- below the line and tests as outside, the other is exactly on it and
      -- tests as inside -- but the edge direction rounds to exactly parallel.
      -- The textbook crossing formula divides by that direction's cross
      -- product, which is 0.0 here, so it gave t = Infinity in one orientation
      -- and 0/0 = NaN in the other; either way the area came back NaN, which
      -- fails every comparison, including "is this above the tolerance". The
      -- subject lies inside the clip, so the answer is its own area, 0.25.
      let clip = [V2 0 0, V2 1 1, V2 0 1]
          outsideFirst = [V2 0 (-1e-17), V2 0.5 0.5, V2 0 1]
          insideFirst = [V2 0.5 0.5, V2 0 (-1e-17), V2 0 1]
      abs (signedArea (clipConvex clip outsideFirst)) `shouldSatisfy` near 0.25
      abs (signedArea (clipConvex clip insideFirst)) `shouldSatisfy` near 0.25

  describe "clipHalfPlane" $ do
    it "splits a polygon into two parts that add up to the whole" $
      -- Run backwards, the same edge keeps the other side, and the two sides
      -- are what 'subtractConvex' is built out of.
      property $ \b ->
        let cut = (V2 (-10) 0.5, V2 10 0.5)
            flipped = (V2 10 0.5, V2 (-10) 0.5)
            half side = abs (signedArea (clipHalfPlane side (corners b)))
         in (half cut + half flipped) `near` area b

    it "keeps a polygon whole when the line misses it" $
      clipHalfPlane (V2 (-1) (-1), V2 1 (-1)) unitSquare `shouldSatisfy` (near 1 . signedArea)

    it "keeps a polygon that lies exactly on the line" $
      -- Points on the line count as inside, as they do for 'clipConvex', so
      -- subtracting a shape that shares an edge does not eat into the shape.
      clipHalfPlane (V2 0 0, V2 1 0) unitSquare `shouldSatisfy` (near 1 . signedArea)

  describe "subtractConvex" $ do
    it "takes away exactly the overlap" $
      -- Against arithmetic again, and over the same awkward boxes: the pieces
      -- left after a subtraction have to account for the whole of what went in
      -- minus the whole of what overlapped.
      property $ \a b ->
        sum (map (abs . signedArea) (subtractConvex 1e-12 (corners b) (corners a)))
          `near` (area a - boxOverlap a b)

    it "leaves pieces that do not overlap what was taken away" $
      property $ \a b ->
        all
          (near 0 . abs . signedArea . clipConvex (corners b))
          (subtractConvex 1e-12 (corners b) (corners a))

    it "leaves pieces that do not overlap one another" $
      property $ \a b ->
        and
          [ near 0 (abs (signedArea (clipConvex p q)))
            | (p : rest) <- tails (subtractConvex 1e-12 (corners b) (corners a)),
              q <- rest
          ]

    it "leaves nothing of a box taken away from itself" $
      property $
        \b -> null (subtractConvex 1e-12 (corners b) (corners b))

    it "leaves a ring of pieces around a hole" $ do
      -- The case that has no answer as a single convex polygon, and the reason
      -- a region is kept as pieces: a flap landing in the middle of a larger
      -- face leaves the face visible all around it.
      let hole = [V2 0.25 0.25, V2 0.75 0.25, V2 0.75 0.75, V2 0.25 0.75]
          pieces = subtractConvex 1e-12 hole unitSquare
      sum (map (abs . signedArea) pieces) `shouldSatisfy` near 0.75
      -- Nothing is left over the hole itself.
      all (near 0 . abs . signedArea . clipConvex hole) pieces `shouldBe` True

    it "takes nothing away when the cutter encloses nothing" $
      subtractConvex 1e-12 [V2 0 0, V2 1 0] unitSquare `shouldBe` [unitSquare]

    it "keeps a piece smaller than the tolerance when nothing was taken from it" $ do
      -- The tolerance is for slivers a subtraction left behind. Where there was
      -- no subtraction there is no sliver, and applying it anyway deletes paper
      -- nothing was cutting.
      let speck = [V2 0 0, V2 0.01 0, V2 0 0.01]
      subtractConvex 1e-3 [V2 0 0, V2 1 0] speck `shouldBe` [speck]

    it "is not fooled by a cutter that lists a corner twice" $ do
      -- An edge of no length names no side, so clipping by it keeps everything
      -- both ways: the part "outside" comes back whole and is emitted as a
      -- finished piece, and the part "inside" comes back whole and carries on.
      -- Before this was guarded, a unit square minus a corner-repeating triangle
      -- came back as 1.5 of paper in two pieces overlapping by 0.5.
      let repeated = [V2 0 0, V2 0 0, V2 1 0, V2 0 1]
          honest = [V2 0 0, V2 1 0, V2 0 1]
          area' = sum . map (abs . signedArea)
      area' (subtractConvex 1e-12 repeated unitSquare)
        `shouldSatisfy` near (area' (subtractConvex 1e-12 honest unitSquare))
      area' (subtractConvex 1e-12 repeated unitSquare) `shouldSatisfy` near 0.5

    it "leaves no overlap when the cutter lists a corner twice" $ do
      let repeated = [V2 0 0, V2 0 0, V2 1 0, V2 0 1]
          pieces = subtractConvex 1e-12 repeated unitSquare
      and [near 0 (abs (signedArea (clipConvex p q))) | (p : rest) <- tails pieces, q <- rest]
        `shouldBe` True

  describe "ears" $ do
    -- Issue #579's L: its six corners average to (0.3, 0.5), its own inside
    -- corner, which is on the outline and so no point inside it. Its ears are
    -- the four outer corners but (0.6, 0), whose triangle has the inside
    -- corner on its long side. Turns red if a reflex corner, or a corner whose
    -- triangle touches another, were taken.
    it "finds the ears of an L, each with its mean inside it, where the mean of all six is not" $ do
      let found = ears 1e-9 lShape
      insideRing 1e-9 lShape (centroid lShape) `shouldBe` False
      [i | (i, _, _) <- found] `shouldBe` [0, 2, 3, 5]
      [insideRing 1e-9 lShape at | (_, _, at) <- found] `shouldBe` replicate 4 True

    -- A dart: corner 3's triangle holds the reflex corner (1, 1) strictly
    -- inside it, where the L's corner 1 has its blocker on the outline. Turns
    -- red if a corner inside a triangle did not count against it.
    it "takes no corner whose triangle holds another" $
      [i | (i, _, _) <- ears 1e-9 [V2 0 0, V2 1 1, V2 2 0, V2 1 2]] `shouldBe` [0, 2]

    -- The L wound clockwise, numbered from its other end, has the same four
    -- ears, at corners 5, 3, 2 and 0 of the first numbering. Turns red if
    -- ears took every ring to run anticlockwise, which finds only the inside
    -- corner of a clockwise L.
    it "finds the same ears in a ring wound clockwise" $
      [(i, size) | (i, size, _) <- ears 1e-9 (reverse lShape)] `shouldBe` [(0, 0.075), (2, 0.075), (3, 0.15), (5, 0.15)]

    -- An L a half by one with a quarter by a half missing, moved 1e8 along
    -- both axes, which every corner survives exactly. Its area measured from
    -- the origin rounds to 0, which would give it no way to turn; from its
    -- first corner it is 0.375. Turns red if the winding were measured from
    -- the origin.
    it "finds the ears of a ring far from the origin" $
      [i | (i, _, _) <- ears 1e-9 [p ^+^ V2 1e8 1e8 | p <- [V2 0 0, V2 0.5 0, V2 0.5 1, V2 0.25 1, V2 0.25 0.5, V2 0 0.5]]] `shouldBe` [0, 2, 3, 5]

    -- The second ring's corner 1 turns the ring's way by a rounding error, a
    -- triangle 1e-12 high. Turns red if the height were not held to the
    -- tolerance, or not asked at all, which lets a reflex corner in too.
    it "takes no corner on a straight run, rounding included" $ do
      [i | (i, _, _) <- ears 1e-9 [V2 0 0, V2 0.5 0, V2 1 0, V2 1 1, V2 0 1]] `shouldBe` [0, 2, 3, 4]
      [i | (i, _, _) <- ears 1e-9 [V2 0 0, V2 0.5 (-1e-12), V2 1 0, V2 1 1, V2 0 1]] `shouldBe` [0, 2, 3, 4]

    -- A square 400 across whose bottom dips 1e-7 at corner 1, with the
    -- tolerance a sheet that size has, a billionth of its diagonal. Corner 1's
    -- triangle is 1e-7 high, under the tolerance, but 2e-5 in area, over it.
    -- Turns red if the tolerance were held against the area rather than the
    -- height.
    it "measures a corner's turn by its height, not its area" $
      [i | (i, _, _) <- ears 5.66e-7 [V2 0 0, V2 200 (-1e-7), V2 400 0, V2 400 400, V2 0 400]] `shouldBe` [0, 2, 3, 4]

    -- An hourglass, one ring that touches itself at (1, 1) and passes it
    -- twice, as corners 2 and 5; the second ring passes it again 1e-12 away,
    -- within the tolerance. Turns red if the second pass counted against the
    -- triangles that have the first as a corner, which leaves no ears, or if
    -- only a second pass at exactly the same point were let off.
    it "keeps the ears of a ring that touches itself at a corner" $
      [[i | (i, _, _) <- ears 1e-9 [V2 0 0, V2 2 0, V2 1 1, V2 2 2, V2 0 2, pinch]] | pinch <- [V2 1 1, V2 1 (1 + 1e-12)]] `shouldBe` [[0, 1, 3, 4], [0, 1, 3, 4]]

    -- Every simple ring of four or more corners has at least two ears (the
    -- two ears theorem), and a triangle three. Turns red if ears were missed,
    -- in a ring wound either way, or an ear's mean could fall outside the
    -- ring or within the tolerance of its outline.
    it "gives a simple ring at least two ears either way round, each with its mean inside it" $
      forAll starRing $ \ring ->
        let found = ears 1e-9 ring
         in (length found >= 2, length (ears 1e-9 (reverse ring)) == length found, and [insideRing 1e-9 ring at | (_, _, at) <- found]) === (True, True, True)

  describe "pointInside" $ do
    -- Turns red if the mean of the corners were passed over when it is
    -- inside.
    it "gives the mean of a convex ring's corners" $
      pointInside 1e-9 unitSquare `shouldBe` Just (V2 0.5 0.5)

    -- The L's mean of corners is its inside corner. Its two largest ears,
    -- corners 0 and 2, tie at 0.15, and corner 0's mean is the lower. Turns
    -- red if the mean of the corners were taken, or the tie went the other
    -- way.
    it "gives the largest ear's mean where the mean of the corners is on the outline" $
      fmap (\(V2 x y) -> near x 0.2 && near y (1 / 6)) (pointInside 1e-9 lShape) `shouldBe` Just True

    -- A square with a spike 99 long and 0.2 wide at its base on top. The
    -- spike's tip is the largest ear by far, but its mean, (0.5, 34), is
    -- under 0.1 from the spike's sides; so is the mean of all seven corners.
    -- Corners 0 and 1 tie next, and corner 0's mean is the further left,
    -- whichever comes first round the ring. Turns red if the largest ear were
    -- chosen before its mean was checked, or a tie went to the first listed.
    it "passes over an ear whose mean is too near the outline" $ do
      let spiked = [V2 0 0, V2 1 0, V2 1 1, V2 0.6 1, V2 0.5 100, V2 0.4 1, V2 0 1]
      [fmap (\(V2 x y) -> near x (1 / 3) && near y (1 / 3)) (pointInside 0.1 ring) | ring <- [spiked, reverse spiked]] `shouldBe` [Just True, Just True]

    -- Most of these Ls have their mean of corners off them, so the point is
    -- an ear's, and the coverage check holds the generator to that. Turns red
    -- if an L could have no point found in it, or the point depended on
    -- which way the ring was wound.
    it "finds a point in every L, the same wound either way" $
      checkCoverage . forAll lRing $ \ring ->
        cover 50 (not (insideRing 1e-9 ring (centroid ring))) "mean of corners off the L" $
          case (pointInside 1e-9 ring, pointInside 1e-9 (reverse ring)) of
            (Just p, Just q) -> counterexample (show (p, q)) (norm (p ^-^ q) < 1e-12)
            missing -> counterexample (show missing) False

  describe "isConvex" $ do
    it "accepts a square and a triangle" $ do
      isConvex 1e-9 unitSquare `shouldBe` True
      isConvex 1e-9 [V2 0 0, V2 1 0, V2 0 1] `shouldBe` True

    it "rejects an L" $
      isConvex 1e-9 [V2 0 0, V2 2 0, V2 2 1, V2 1 1, V2 1 2, V2 0 2] `shouldBe` False

    it "tolerates a corner in the middle of a straight side" $
      -- Real crease patterns have these wherever a crease ends on the far side
      -- of an edge; the turn there is zero up to rounding, and its sign is
      -- noise.
      isConvex 1e-9 [V2 0 0, V2 0.5 1e-12, V2 1 0, V2 1 1, V2 0 1] `shouldBe` True

    it "does not care which way round the ring is" $
      isConvex 1e-9 (reverse unitSquare) `shouldBe` True

  describe "clipSegment" $ do
    it "keeps the part of a segment that crosses the interior" $
      clipSegment unitSquare (V2 (-1) 0.5, V2 2 0.5) `shouldBe` Just (V2 0 0.5, V2 1 0.5)

    it "returns a segment along an edge whole, and its midpoint is not strictly inside" $ do
      -- The two together are how the layer solver tells a crease that runs
      -- along a face's edge from one that runs through the face.
      let alongEdge = (V2 0 0, V2 1 0)
      clipSegment unitSquare alongEdge `shouldBe` Just alongEdge
      strictlyInside 1e-9 unitSquare (V2 0.5 0) `shouldBe` False
      strictlyInside 1e-9 unitSquare (V2 0.5 0.5) `shouldBe` True

    it "clips a segment through a corner to a point" $
      case clipSegment unitSquare (V2 (-1) 1, V2 1 (-1)) of
        Just (u, v) -> u `shouldBe` v
        Nothing -> expectationFailure "expected the corner itself"

    it "misses a segment that passes by" $
      clipSegment unitSquare (V2 2 0, V2 2 1) `shouldBe` Nothing

  describe "distanceOutside" $ do
    it "is negative inside, zero on the boundary, positive outside" $ do
      distanceOutside unitSquare (V2 0.5 0.5) `shouldSatisfy` near (-0.5)
      distanceOutside unitSquare (V2 0.5 0) `shouldSatisfy` near 0
      distanceOutside unitSquare (V2 0.5 (-0.25)) `shouldSatisfy` near 0.25

    it "measures to the nearest edge, not to the corner" $
      distanceOutside unitSquare (V2 0.1 0.25) `shouldSatisfy` near (-0.1)

    it "ignores an edge of no length" $ do
      -- Clipping leaves these wherever a cut passed exactly through a corner.
      -- An edge with no direction has no side, and treating it as one would
      -- report every point in the world as outside the polygon.
      let repeated = [V2 0 0, V2 1 0, V2 1 0, V2 1 1, V2 0 1]
      distanceOutside repeated (V2 0.5 0.5) `shouldSatisfy` near (-0.5)

    it "agrees with strictlyInside, which is one comparison against it" $
      property $ \b ->
        let p = V2 0 0
         in strictlyInside 0.5 (corners b) p == (distanceOutside (corners b) p < -0.5)

  describe "collinearOverlap" $ do
    it "finds the stretch two segments share, in the first one's direction" $ do
      collinearOverlap 1e-9 (V2 0 0, V2 2 0) (V2 1 0, V2 3 0) `shouldBe` Just (V2 1 0, V2 2 0)
      -- The second segment written backwards changes nothing.
      collinearOverlap 1e-9 (V2 0 0, V2 2 0) (V2 3 0, V2 1 0) `shouldBe` Just (V2 1 0, V2 2 0)

    it "shares nothing between segments that only touch" $
      -- Two creases meeting end to end at a vertex lie on one line and are not
      -- folded on the same stretch of it. Treating them as overlapping would
      -- invent a taco-taco constraint between faces that never meet.
      collinearOverlap 1e-9 (V2 0 0, V2 1 0) (V2 1 0, V2 2 0) `shouldBe` Nothing

    it "shares nothing between parallel segments a hair apart" $
      collinearOverlap 1e-9 (V2 0 0, V2 2 0) (V2 0 0.001, V2 2 0.001) `shouldBe` Nothing

    it "shares nothing between segments that cross" $
      collinearOverlap 1e-9 (V2 0 0, V2 2 0) (V2 1 (-1), V2 1 1) `shouldBe` Nothing
