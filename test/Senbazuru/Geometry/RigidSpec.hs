-- |
-- Properties of rigid motions.
--
-- The defining property is the one worth testing hardest: a rigid motion may
-- not change the distance between any two points. Everything folding relies on
-- follows from that, and a sign or transposition slip in the rotation matrix
-- breaks it immediately.
module Senbazuru.Geometry.RigidSpec (spec) where

import Data.Maybe (isJust)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (frameVertices)
import Senbazuru.Fold.Types (FoldFile (..))
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
  theta <- choose (-(2 * pi), 2 * pi)
  pure (rotationAbout p axis theta)

near :: Double -> Double -> Bool
near a b = abs (a - b) < 1e-9

nearV3 :: V3 -> V3 -> Bool
nearV3 a b = norm (a ^-^ b) < 1e-9

-- | quarter-fold-steps.fold's key frame, as points: the unit square's
-- corners, then its edge midpoints, then its centre, all at z = 0.
flatSheet :: [V3]
flatSheet = [V3 x y 0 | (x, y) <- [(0, 0), (1, 0), (1, 1), (0, 1), (0.5, 0), (1, 0.5), (0.5, 1), (0, 0.5), (0.5, 0.5)]]

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

  describe "inverse" $ do
    it "puts every point back where it started" $
      forAll ((,) <$> genRotation <*> genPoint) $ \(r, x) ->
        norm (applyRigid (inverse r) (applyRigid r x) ^-^ x) < 1e-9 * max 1 (norm x)

    it "undoes a whole chain of motions, not just one" $
      -- What folding actually hands it. A face deep in a model carries the
      -- composition of every turn on the path to it, and the transpose trick
      -- has to survive composition or the inverse is right only for the root.
      forAll ((,,) <$> genRotation <*> genRotation <*> genPoint) $ \(a, b, x) ->
        let there = a `after` b
         in norm (applyRigid (inverse there) (applyRigid there x) ^-^ x)
              < 1e-9 * max 1 (norm x)

    it "moves the offset as well as transposing the matrix" $ do
      -- The line that looks like it could be left out. For a turn about a line
      -- through the origin the offset is zero and forgetting to transform it
      -- costs nothing, so the test uses one that is not: a quarter turn about
      -- the line x = 1 along z, which carries (2,0,0) to (1,1,0). Reusing the
      -- original offset instead of -M'.t sends it back to (2,-2,0).
      let r = rotationAbout (V3 1 0 0) (V3 0 0 1) (pi / 2)
      applyRigid r (V3 2 0 0) `shouldSatisfy` nearV3 (V3 1 1 0)
      applyRigid (inverse r) (V3 1 1 0) `shouldSatisfy` nearV3 (V3 2 0 0)

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

  describe "isProperRotation" $ do
    it "accepts every rotation rotationAbout makes" $
      forAll genRotation $
        \r -> isProperRotation (rigidLinear r)

    -- The determinant alone would pass the stretch, whose determinant is 1;
    -- orthonormal rows alone would pass the mirror. Turns red if either check
    -- were dropped.
    it "refuses a stretch whose determinant is 1, and a mirror" $ do
      isProperRotation (Mat3 (V3 2 0 0) (V3 0 0.5 0) (V3 0 0 1)) `shouldBe` False
      isProperRotation (Mat3 (V3 (-1) 0 0) (V3 0 1 0) (V3 0 0 1)) `shouldBe` False

  describe "fitRigid" $ do
    -- quarter-fold-steps.fold's key frame: the unit square's corners, edge
    -- midpoints and centre, flat at z = 0. Every turn about +z keeps it at
    -- z = 0, so the mirror through that plane fits every pair too, and only
    -- the cross product's third axis, with the check that the turn is proper,
    -- refuses it. Turns red if the third axis were flipped.
    it "recovers a quarter turn, a half turn and an eighth turn of a flat sheet" $
      mapM_
        ( \theta -> do
            let turn = rotationAbout (V3 0.5 0.5 0) (V3 0 0 1) theta
            case fitRigid [(p, applyRigid turn p) | p <- flatSheet] of
              Nothing -> expectationFailure ("no fit for a turn of " <> show theta)
              Just found -> all (\p -> nearV3 (applyRigid found p) (applyRigid turn p)) (V3 0 0 1 : flatSheet) `shouldBe` True
        )
        [pi / 2, pi, pi / 4]

    -- The line that looks like a typo, at work: the flat sheet turned over
    -- left-right, (x, y, z) to (1 - x, y, -z), puts every vertex where the
    -- mirror (1 - x, y, z) does. The fit is the half turn, which sends the
    -- paper's up to its down; paper cannot make the mirror.
    it "takes a flat sheet turned over for a half turn, never the mirror" $
      case fitRigid [(p, V3 (1 - x) y 0) | p@(V3 x y _) <- flatSheet] of
        Nothing -> expectationFailure "no fit for the turn-over"
        Just found -> matApply (rigidLinear found) (V3 0 0 1) `shouldSatisfy` nearV3 (V3 0 0 (-1))

    -- A state of the bird base with paper in the air, reflected x to -x: no
    -- rigid motion makes a mirror of paper that is not flat. Turns red if
    -- only three points were checked and not every pair.
    it "finds no fit for a mirrored model with paper in the air" $ do
      file <- loadFoldFile "examples/bird-base-sequence.fold" >>= either (fail . show) pure
      points <- case drop 1 (otherFrames file) of
        frame : _ -> either (fail . show) pure (frameVertices frame)
        [] -> fail "the bird sequence has no second state"
      maximum [z | V3 _ _ z <- points] `shouldSatisfy` (> 0.1)
      fitRigid [(p, V3 (-x) y z) | p@(V3 x y z) <- points] `shouldBe` Nothing
      fitRigid [(p, p) | p <- points] `shouldSatisfy` isJust

    it "finds no fit for points that do not span a plane" $
      fitRigid [(p, p ^+^ V3 1 0 0) | p <- [V3 0 0 0, V3 1 1 1, V3 2 2 2]] `shouldBe` Nothing

  describe "matApply" $
    it "reads a matrix as three rows" $
      matApply (Mat3 (V3 1 2 3) (V3 4 5 6) (V3 7 8 9)) (V3 1 0 0)
        `shouldSatisfy` \(V3 x y z) -> near x 1 && near y 4 && near z 7
