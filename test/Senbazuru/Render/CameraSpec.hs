-- |
-- Tests for orthographic projection.
--
-- The example tests pin the two things that must not drift: that 'topDown'
-- reproduces the old z-dropping behaviour /exactly/, and that a degenerate
-- view is rejected rather than silently producing nonsense. The properties
-- check what projection is supposed to preserve.
module Senbazuru.Render.CameraSpec (spec) where

import Data.Maybe (fromMaybe, isJust, isNothing)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3
import Senbazuru.Render.Camera
import Test.Hspec
import Test.QuickCheck

genV3 :: Gen V3
genV3 = V3 <$> c <*> c <*> c
  where
    c = choose (-100, 100)

-- | A direction, kept clear of zero so it has one.
genDir :: Gen V3
genDir = V3 <$> c <*> c <*> c
  where
    c = (\x -> if abs x < 0.25 then x + 1 else x) <$> choose (-10, 10)

-- | Exactly parallel direction and up is a measure-zero event for random
-- doubles, so the fallback here effectively never fires.
genBasis :: Gen Basis
genBasis = fromMaybe topDown <$> (basisFrom <$> genDir <*> genDir)

near :: Double -> Double -> Bool
near a b = abs (a - b) < 1e-6

spec :: Spec
spec = do
  describe "basisFrom" $ do
    it "builds a basis from a sane direction and up" $
      basisFrom (V3 0 0 (-1)) (V3 0 1 0) `shouldSatisfy` isJust

    it "refuses a direction parallel to up, which leaves the roll undecided" $
      basisFrom (V3 0 0 1) (V3 0 0 1) `shouldSatisfy` isNothing

    it "refuses an antiparallel up for the same reason" $
      basisFrom (V3 0 0 1) (V3 0 0 (-2)) `shouldSatisfy` isNothing

    it "refuses a zero direction" $
      basisFrom (V3 0 0 0) (V3 0 1 0) `shouldSatisfy` isNothing

    it "produces three mutually perpendicular unit vectors" $
      forAll genBasis $ \b ->
        let r = basisRight b
            u = basisUp b
            f = basisForward b
         in all
              (near 0)
              [dotV3 r u, dotV3 r f, dotV3 u f]
              && all (near 1) [normV3 r, normV3 u, normV3 f]

  describe "topDown" $ do
    it "keeps x and y exactly, so crease patterns cannot drift" $
      -- Exact equality on purpose. The basis is the coordinate axes themselves,
      -- so projecting multiplies by one and adds zero. If this ever becomes
      -- approximate, every committed golden file changes.
      forAll genV3 $
        \p@(V3 x y _) -> project topDown p == V2 x y

    it "measures depth so that larger z is nearer the viewer" $
      depth topDown (V3 0 0 1) < depth topDown (V3 0 0 0)

  describe "project" $ do
    it "ignores movement along the view axis" $
      -- The defining property of an orthographic projection: sliding a point
      -- towards or away from the camera does not move it on the page.
      forAll ((,,) <$> genBasis <*> genV3 <*> choose (-50, 50)) $ \(b, p, t) ->
        let V2 ax ay = project b p
            V2 bx by = project b (addV3 p (scaleV3 t (basisForward b)))
         in near ax bx && near ay by

    it "preserves collinearity" $
      forAll ((,,,) <$> genBasis <*> genV3 <*> genDir <*> choose (-20, 20)) $
        \(b, p, d, t) ->
          let V2 ax ay = project b p
              V2 bx by = project b (addV3 p d)
              V2 cx cy = project b (addV3 p (scaleV3 t d))
              -- Twice the signed area of the triangle; zero iff collinear.
              cross = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
           in abs cross < 1e-6 * (1 + abs t)

    it "preserves distance for displacements across the view direction" $
      forAll ((,) <$> genBasis <*> genV3) $ \(b, p) ->
        let along = scaleV3 3 (basisRight b)
            V2 ax ay = project b p
            V2 bx by = project b (addV3 p along)
         in near (sqrt ((bx - ax) ** 2 + (by - ay) ** 2)) 3

  describe "namedView" $ do
    it "resolves every name it advertises" $
      all (isJust . namedView) viewNames

    it "rejects anything else" $
      namedView "banana" `shouldSatisfy` isNothing

    it "maps top to the same basis as topDown" $
      namedView "top" `shouldBe` Just topDown

  describe "the named views" $
    it "are all well formed, so the total fallback never fires" $
      -- named uses a total wrapper over basisFrom with topDown as the fallback.
      -- If any named view were degenerate it would silently become topDown,
      -- which this catches.
      [isometric, frontOn, sideOn] `shouldSatisfy` notElem topDown
