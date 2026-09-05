-- |
-- Properties of rigid motions.
--
-- The defining property is the one worth testing hardest: a rigid motion may
-- not change the distance between any two points. Everything folding relies on
-- follows from that, and a sign or transposition slip in the rotation matrix
-- breaks it immediately.
module Senbazuru.Geometry.RigidSpec (spec) where

import Senbazuru.Geometry.Rigid
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
-- hspec exports an `after` of its own, for running an action after each spec
-- item. Hidden rather than qualifying every use, since none is wanted here.
import Test.Hspec hiding (after)
import Test.QuickCheck

genCoord :: Gen Double
genCoord = choose (-100, 100)

genPoint :: Gen V3
genPoint = V3 <$> genCoord <*> genCoord <*> genCoord

-- | A rotation about some line, avoiding the degenerate zero axis.
genRotation :: Gen Rigid
genRotation = do
  p <- genPoint
  axis <- genPoint `suchThat` \v -> norm v > 0.1
  theta <- choose (-2 * pi, 2 * pi)
  pure (rotationAbout p axis theta)

near :: Double -> Double -> Bool
near a b = abs (a - b) < 1e-9

nearV3 :: V3 -> V3 -> Bool
nearV3 a b = norm (a ^-^ b) < 1e-9

spec :: Spec
spec = do
  describe "rotationAbout" $ do
    it "keeps every distance it started with" $
      -- The whole point of the type. Distances are compared relative to their
      -- own size: two points a hundred units apart, turned about a line a
      -- hundred units away, cannot be expected to land within 1e-9 absolutely.
      forAll ((,,) <$> genRotation <*> genPoint <*> genPoint) $ \(r, a, b) ->
        let apart = norm (a ^-^ b)
            stillApart = norm (applyRigid r a ^-^ applyRigid r b)
         in abs (apart - stillApart) < 1e-9 * max 1 apart

    it "leaves points on its own axis exactly where they were" $
      forAll ((,,) <$> genPoint <*> (genPoint `suchThat` \v -> norm v > 0.1) <*> choose (-pi, pi)) $
        \(p, axis, theta) ->
          forAll (choose (-10, 10)) $ \t ->
            let onAxis = p ^+^ (t *^ axis)
             in nearV3 (applyRigid (rotationAbout p axis theta) onAxis) onAxis

    it "turns the way the right hand does" $ do
      -- Thumb along +z, fingers curl x towards y.
      let quarter = rotationAbout (V3 0 0 0) (V3 0 0 1) (pi / 2)
      applyRigid quarter (V3 1 0 0) `shouldSatisfy` nearV3 (V3 0 1 0)

    it "turns about a line that is not through the origin" $
      -- Half a turn about the line x = 1 along y reflects x through 1.
      applyRigid (rotationAbout (V3 1 0 0) (V3 0 1 0) pi) (V3 2 0 0)
        `shouldSatisfy` nearV3 (V3 0 0 0)

    it "does nothing when there is no axis to turn about" $
      -- A zero axis has no rotation to describe. Answering with a matrix full
      -- of NaN would be worse than answering with identity, and NaN
      -- coordinates format as 0, so the failure would be silent.
      applyRigid (rotationAbout (V3 0 0 0) (V3 0 0 0) 1.2) (V3 3 4 5)
        `shouldSatisfy` nearV3 (V3 3 4 5)

    it "undoes itself when turned back" $
      forAll ((,,,) <$> genPoint <*> (genPoint `suchThat` \v -> norm v > 0.1) <*> choose (-pi, pi) <*> genPoint) $
        \(p, axis, theta, x) ->
          let there = rotationAbout p axis theta
              back = rotationAbout p axis (negate theta)
           in norm (applyRigid (back `after` there) x ^-^ x) < 1e-9 * max 1 (norm x)

  describe "after" $ do
    it "applies its right argument first" $ do
      -- Named to read as English, and that reading has to match the arithmetic
      -- or the folding rule M[child] = M[parent] . R transcribes backwards.
      let spin = rotationAbout (V3 0 0 0) (V3 0 0 1) (pi / 2)
          tip = rotationAbout (V3 0 0 0) (V3 1 0 0) (pi / 2)
          p = V3 0 1 0
      applyRigid (spin `after` tip) p
        `shouldSatisfy` nearV3 (applyRigid spin (applyRigid tip p))

    it "is not the same as the other order" $ do
      -- Guards the test above: if the two orders agreed on this input it would
      -- prove nothing.
      let spin = rotationAbout (V3 0 0 0) (V3 0 0 1) (pi / 2)
          tip = rotationAbout (V3 0 0 0) (V3 1 0 0) (pi / 2)
          p = V3 0 1 0
      applyRigid (spin `after` tip) p
        `shouldNotSatisfy` nearV3 (applyRigid (tip `after` spin) p)

    it "leaves a motion alone when composed with identity" $
      forAll ((,) <$> genRotation <*> genPoint) $ \(r, x) ->
        nearV3 (applyRigid (identity `after` r) x) (applyRigid r x)
          && nearV3 (applyRigid (r `after` identity) x) (applyRigid r x)

  describe "matMul" $
    it "multiplies rows into columns, not rows into rows" $ do
      -- A transposition slip here is invisible for symmetric matrices and for
      -- the identity, so the test uses a matrix that is neither.
      let a = Mat3 (V3 1 2 0) (V3 0 1 0) (V3 0 0 1)
          b = Mat3 (V3 1 0 0) (V3 3 1 0) (V3 0 0 1)
      matApply (matMul a b) (V3 1 0 0) `shouldSatisfy` nearV3 (matApply a (matApply b (V3 1 0 0)))
      matMul a b `shouldBe` Mat3 (V3 7 2 0) (V3 3 1 0) (V3 0 0 1)

  describe "identity" $
    it "leaves a point exactly alone" $
      forAll genPoint $
        \p -> applyRigid identity p == p

  describe "matApply" $
    it "reads a matrix as three rows" $
      matApply (Mat3 (V3 1 2 3) (V3 4 5 6) (V3 7 8 9)) (V3 1 0 0)
        `shouldSatisfy` \(V3 x y z) -> near x 1 && near y 4 && near z 7
