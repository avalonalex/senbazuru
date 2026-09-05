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

import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon
import Test.Hspec
import Test.QuickCheck

-- | An axis-aligned box as its corners, anticlockwise.
data Box2 = Box2 !Double !Double !Double !Double
  deriving stock (Show)

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
