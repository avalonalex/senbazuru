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
