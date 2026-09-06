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
import Senbazuru.Geometry.VectorSpace
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

    it "refuses a non-finite direction rather than returning NaNs" $ do
      -- normalize guarding only on `n == 0` would let these through, because
      -- NaN == 0 is False. The result would be a Basis of NaNs that satisfies
      -- no invariant, and NaN page coordinates format as "0", so every point
      -- would silently stack in one place.
      basisFrom (V3 (0 / 0) 0 0) (V3 0 1 0) `shouldSatisfy` isNothing
      basisFrom (V3 (1 / 0) 0 0) (V3 0 1 0) `shouldSatisfy` isNothing

    it "produces three mutually perpendicular unit vectors" $
      forAll genBasis $ \b ->
        let r = basisRight b
            u = basisUp b
            f = basisForward b
         in all
              (near 0)
              [dot r u, dot r f, dot u f]
              && all (near 1) [norm r, norm u, norm f]

  describe "topDown" $ do
    it "is orthonormal like any other basis" $
      -- topDown is written by hand rather than generated, so the property test
      -- over random bases never reaches it. A typo in one component would
      -- otherwise change which world axis maps to the page, silently.
      let r = basisRight topDown
          u = basisUp topDown
          f = basisForward topDown
       in all (near 0) [dot r u, dot r f, dot u f]
            && all (near 1) [norm r, norm u, norm f]

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
            V2 bx by = project b (p ^+^ (t *^ basisForward b))
         in near ax bx && near ay by

    it "preserves collinearity" $
      forAll ((,,,) <$> genBasis <*> genV3 <*> genDir <*> choose (-20, 20)) $
        \(b, p, d, t) ->
          let V2 ax ay = project b p
              V2 bx by = project b (p ^+^ d)
              V2 cx cy = project b (p ^+^ (t *^ d))
              -- Twice the signed area of the triangle; zero iff collinear.
              twiceArea = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
           in abs twiceArea < 1e-6 * (1 + abs t)

    it "preserves distance for displacements across the view direction" $
      forAll ((,) <$> genBasis <*> genV3) $ \(b, p) ->
        let along = 3 *^ basisRight b
            V2 ax ay = project b p
            V2 bx by = project b (p ^+^ along)
         in near (sqrt ((bx - ax) ** 2 + (by - ay) ** 2)) 3

  describe "isometric" $ do
    it "really is isometric: all three world axes foreshorten equally" $
      -- The property that distinguishes isometric from a merely pleasing angle.
      -- Any (+-1, +-1, +-1) direction gives sqrt(2/3); an arbitrary one does not,
      -- and then lengths along different axes stop being comparable on the page.
      let lengthOf (V3 x y z) =
            let V2 px py = project isometric (V3 x y z)
             in sqrt (px * px + py * py)
          ls = map lengthOf [V3 1 0 0, V3 0 1 0, V3 0 0 1]
       in all (near (sqrt (2 / 3))) ls

  describe "namedView" $ do
    it "resolves every name it advertises" $
      all (isJust . namedView) viewNames

    it "rejects anything else" $
      namedView "banana" `shouldSatisfy` isNothing

    it "maps top to the same basis as topDown" $
      namedView "top" `shouldBe` Just topDown

    it "advertises exactly the views it can resolve" $
      -- views is the single source; this catches the list and the lookup
      -- drifting apart, which would leave a view undiscoverable in --help.
      map fst views `shouldBe` viewNames

  describe "turnedBy" $ do
    it "turns the drawing anticlockwise, not the model" $ do
      -- A point on the model's +x axis is drawn to the right of the page. Turn
      -- the drawing a quarter turn anticlockwise and it is drawn above instead.
      let V2 x y = project (turnedBy (pi / 2) topDown) (V3 1 0 0)
      x `shouldSatisfy` near 0
      y `shouldSatisfy` near 1

    it "turns a half turn to the opposite corner of the page" $
      -- Which is the one that puts the traditional crane the right way up: it
      -- lands upside down because that is how its crease pattern was drawn.
      forAll genV3 $ \p ->
        let V2 ax ay = project topDown p
            V2 bx by = project (turnedBy pi topDown) p
         in near ax (negate bx) && near ay (negate by)

    it "does nothing at all when asked for nothing" $
      forAll ((,) <$> genBasis <*> genV3) $ \(b, p) ->
        let V2 ax ay = project b p
            V2 bx by = project (turnedBy 0 b) p
         in near ax bx && near ay by

    it "keeps the basis a basis" $
      -- Turned by hand rather than rebuilt through basisFrom, so the
      -- perpendicular-and-unit-length invariant is this function's to keep.
      forAll ((,) <$> genBasis <*> choose (-10, 10)) $ \(b, angle) ->
        let t = turnedBy angle b
            r = basisRight t
            u = basisUp t
            f = basisForward t
         in all (near 0) [dot r u, dot r f, dot u f]
              && all (near 1) [norm r, norm u, norm f]

    it "turns rather than mirrors, which distance alone cannot tell you" $
      -- The property that separates the two, and the first version of this test
      -- had the wrong one. A reflection is an isometry: it preserves every
      -- length on the page exactly as a turn does, so "distances are unchanged"
      -- passes for a mirror and says nothing at all. What a mirror does not
      -- preserve is orientation.
      --
      -- The page axes cross to /minus/ forward, for every basis this module
      -- makes, because forward points away from the viewer and the two page
      -- axes are right and up as the reader sees them. It falls out of
      -- basisFrom: up is right x forward, so right x up is
      -- right x (right x forward), which is -forward. Under a reflection it
      -- comes out +forward instead, which is what this catches.
      forAll ((,) <$> genBasis <*> choose (-10, 10)) $ \(b, angle) ->
        let t = turnedBy angle b
            V3 cx cy cz = cross (basisRight t) (basisUp t)
            V3 fx fy fz = basisForward t
         in near cx (negate fx) && near cy (negate fy) && near cz (negate fz)

    it "leaves lengths on the page alone" $
      -- True, and worth pinning, but it is not what makes this a turn: see
      -- above. Measured between two points rather than from the page origin,
      -- which a turn about that origin would preserve trivially.
      forAll ((,,,) <$> genBasis <*> genV3 <*> genV3 <*> choose (-10, 10)) $ \(b, p, q, angle) ->
        let apart bs =
              let V2 px py = project bs p
                  V2 qx qy = project bs q
               in sqrt ((px - qx) ** 2 + (py - qy) ** 2)
         in near (apart b) (apart (turnedBy angle b))

    it "is no turn at all when the angle is not a number" $ do
      -- cos and sin of a non-finite angle are NaN, and a Basis of NaNs breaks
      -- every invariant this module has. Worse, NaN page coordinates format as
      -- "0", so the model would come out silently stacked on one point.
      let same a b' = project a (V3 1 2 3) == project b' (V3 1 2 3)
      turnedBy (0 / 0) topDown `shouldSatisfy` same topDown
      turnedBy (1 / 0) topDown `shouldSatisfy` same topDown

    it "adds up over two turns" $
      forAll ((,,) <$> genBasis <*> genV3 <*> choose (-3, 3)) $ \(b, p, angle) ->
        let V2 ax ay = project (turnedBy angle (turnedBy angle b)) p
            V2 bx by = project (turnedBy (2 * angle) b) p
         in near ax bx && near ay by

  describe "the named views" $
    it "are all well formed, so the total fallback never fires" $
      -- named uses a total wrapper over basisFrom with topDown as the fallback.
      -- If any named view were degenerate -- its direction parallel to its up
      -- hint, say, which is one typo away -- it would silently become topDown,
      -- and --view bottom would quietly draw the top.
      --
      -- Taken from views rather than listed by hand, for the reason views is a
      -- single source of truth in the first place: a list written out here
      -- covers the views someone remembered, and a new one added to the module
      -- and forgotten here would be exactly the one nobody checked.
      [b | (name, b) <- views, name /= "top"] `shouldSatisfy` notElem topDown
