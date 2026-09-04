-- |
-- Properties of the geometry layer.
--
-- These are QuickCheck /property/ tests rather than examples: instead of
-- asserting that one particular box maps to one particular result, they state a
-- rule that must hold for every input and let QuickCheck hunt for a
-- counterexample. That style suits 'fitBox' well, because the rules ("the
-- drawing lands on the page", "the scale is uniform") are easy to state and the
-- interesting failures are at awkward inputs a human would not think to write
-- down.
module Senbazuru.GeometrySpec (spec) where

import Senbazuru.Geometry
import Test.Hspec
import Test.QuickCheck

-- Coordinates and sizes are kept to modest ranges. Unbounded 'Double'
-- generation would produce infinities and 1e300 values, where the properties
-- below fail for floating-point reasons rather than because the code is wrong.
genCoord :: Gen Double
genCoord = choose (-100, 100)

genPoint :: Gen V2
genPoint = V2 <$> genCoord <*> genCoord

-- | A box with strictly positive width and height.
genBox :: Gen Box
genBox = do
  lo <- genPoint
  w <- choose (0.1, 100)
  h <- choose (0.1, 100)
  pure (Box lo (lo ^+^ V2 w h))

-- | A point somewhere inside the given box.
genPointIn :: Box -> Gen V2
genPointIn (Box (V2 lx ly) (V2 hx hy)) = V2 <$> choose (lx, hx) <*> choose (ly, hy)

-- Comparisons on transformed coordinates need slack: the pipeline multiplies
-- and adds, and exact 'Double' equality would fail on rounding alone.
epsilon :: Double
epsilon = 1e-6

closeTo :: Double -> Double -> Bool
closeTo a b = abs (a - b) < epsilon

nearV2 :: V2 -> V2 -> Bool
nearV2 (V2 ax ay) (V2 bx by) = closeTo ax bx && closeTo ay by

spec :: Spec
spec = do
  describe "the VectorSpace instance for V2" $ do
    it "gives V2 a dot product it never had before" $
      -- Shared with V3 through the class, so 2D angle work -- Kawasaki's
      -- theorem, for one -- gets it without a second implementation.
      dot (V2 3 4) (V2 2 1) `shouldBe` 10

    it "derives norm from dot" $
      norm (V2 3 4) `shouldBe` 5

    it "derives normalize, and refuses the zero vector" $ do
      -- Compared with a tolerance, not exactly. normalize scales by the
      -- reciprocal, so this computes 3 * (1/5); 1/5 is not exact in binary and
      -- the product lands one ulp off 0.6. Dividing componentwise would hit it
      -- exactly, at the cost of a division per component -- the usual
      -- reciprocal-versus-divide trade, and worth knowing it is being made.
      normalize (V2 3 4) `shouldSatisfy` maybe False (nearV2 (V2 0.6 0.8))
      normalize (V2 0 0) `shouldBe` Nothing

    it "refuses non-finite input, the default method's whole point" $
      -- The guard lives once in the class default, so V2 and V3 cannot disagree
      -- about it -- which is what the old per-type functions risked.
      normalize (V2 (0 / 0) 1) `shouldBe` Nothing

  describe "boxFromPoints" $ do
    it "has no answer for no points" $
      boxFromPoints [] `shouldBe` Nothing

    it "contains every point it was built from" $
      forAll (listOf1 genPoint) $ \ps ->
        case boxFromPoints ps of
          Nothing -> False
          Just b -> all (boxContains b) ps

    it "is tight: every one of the four sides is touched by a point" $
      forAll (listOf1 genPoint) $ \ps ->
        case boxFromPoints ps of
          Nothing -> False
          Just (Box (V2 lx ly) (V2 hx hy)) ->
            -- Checking all four sides individually matters. An earlier version
            -- of this property shrank the box and asserted that some point fell
            -- outside, which a box correct in x and slack in y passes happily:
            -- the excluded point only has to be near *one* side.
            --
            -- Exact equality is right here. min and max select one of their
            -- arguments rather than computing a new value, so a bound is always
            -- literally one of the input coordinates -- no arithmetic, no
            -- rounding, nothing to tolerate.
            any ((== lx) . v2x) ps
              && any ((== hx) . v2x) ps
              && any ((== ly) . v2y) ps
              && any ((== hy) . v2y) ps

  describe "fitBox" $ do
    it "keeps everything in the source box on the page" $
      forAll ((,) <$> genBox <*> genBox) $ \(src, dst) ->
        forAll (genPointIn src) $ \p ->
          -- Padding by epsilon rather than testing the raw box: a point exactly
          -- on the source boundary lands exactly on the destination boundary,
          -- where rounding can put it a fraction outside.
          boxContains (padBox epsilon dst) (applyTransform (fitBox src dst) p)

    it "puts the centre of the drawing at the centre of the page" $
      forAll ((,) <$> genBox <*> genBox) $ \(src, dst) ->
        let V2 gx gy = applyTransform (fitBox src dst) (boxCentre src)
            V2 ex ey = boxCentre dst
         in closeTo gx ex && closeTo gy ey

    it "scales x and y by the same amount, so shapes are not distorted" $
      forAll ((,) <$> genBox <*> genBox) $ \(src, dst) ->
        let V2 sx sy = tScale (fitBox src dst)
         in closeTo (abs sx) (abs sy)

    it "flips the y axis, because SVG measures y downwards" $
      forAll ((,) <$> genBox <*> genBox) $ \(src, dst) ->
        v2y (tScale (fitBox src dst)) < 0

    it "fills the page in at least one direction" $
      forAll ((,) <$> genBox <*> genBox) $ \(src, dst) ->
        let t = fitBox src dst
            Box lo hi = src
            V2 w h = boxSize dst
            -- Map the source corners and measure the result.
            V2 ax ay = applyTransform t lo
            V2 bx by = applyTransform t hi
            fittedW = abs (bx - ax)
            fittedH = abs (by - ay)
         in closeTo fittedW w || closeTo fittedH h

    it "does not produce NaN or infinity for a degenerate source box" $
      forAll genBox $ \dst ->
        let flat = Box (V2 3 7) (V2 3 7) -- every vertex at the same point
            V2 x y = applyTransform (fitBox flat dst) (V2 3 7)
         in not (isNaN x || isInfinite x || isNaN y || isInfinite y)

    it "handles a collinear source box, where one axis has zero extent" $
      forAll genBox $ \dst ->
        let line = Box (V2 0 5) (V2 10 5) -- all vertices on a horizontal line
            V2 x y = applyTransform (fitBox line dst) (V2 5 5)
         in not (isNaN x || isInfinite x || isNaN y || isInfinite y)
