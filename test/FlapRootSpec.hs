-- | A flap's root, the line it turns from, found by a rule rather than chosen
-- by eye (owner decisions 34 and 35). On the crane the rule has to find the
-- wing's root where the owner placed it, at the neck and tail bases, and has
-- to refuse the neck and the tail, whose roots lie between the body's layers.
module FlapRootSpec (spec) where

import Control.Monad (forM_)
import CraneWing (CraneWing (..), buildCraneWingAt, wingRoot)
import Data.Either (isLeft)
import Data.List (sortOn)
import FlapRoot
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Test.Hspec

spec :: Spec
spec = describe "a flap's root" $ do
  source <- runIO (loadFoldFile "examples/crane.fold" >>= either (fail . show) (pure . keyFrame))
  -- The neck and tail bases are the folded crane outline's two reflex
  -- corners beside the wing, computed independently by unioning the faces'
  -- shadows and walking the outline from the wing's tip at (1, 0).
  it "finds the crane wing's root at the neck and tail bases from either wing's tip" $
    forM_ [V2 0 1, V2 1 0] $ \corner -> do
      root <- right (prepare source corner >>= findRoot)
      let (a, b) = rootEnds root
      case sortOn v2x [a, b] of
        [V2 x1 y1, V2 x2 y2] -> do
          [x1, y1, x2, y2] `shouldSatisfy` and . zipWith near [0.87584856, 0.37584856, 1.12415144, 0.37584856]
        _ -> expectationFailure "expected two ends"
  it "turns the wing about its root, moving the wing's eight faces" $ do
    prepared <- right (prepare source (V2 0 1))
    root <- right (findRoot prepared)
    turned <- right (turnAbout prepared 2 (rootEnds root))
    turnResult turned `shouldBe` Right (90, 8)
  -- The neck's outline meets the paper beside it on one side only; on the
  -- other it runs inside the body, so the rule's second end is wrong and the
  -- turn check refuses it. The tail's edge never meets other paper at all.
  it "refuses the neck and the tail, whose roots lie between the body's layers" $ do
    neck <- right (prepare source (V2 0 0))
    neckRoot <- right (findRoot neck)
    turned <- right (turnAbout neck 2 (rootEnds neckRoot))
    turnResult turned `shouldSatisfy` isLeft
    tail' <- right (prepare source (V2 1 1))
    isLeft (findRoot tail') `shouldBe` True
  it "gives CraneWing a level line to crease the wing along" $ do
    hinge <- right (wingRoot source)
    hinge `shouldSatisfy` near 0.37584856
    wing <- right (buildCraneWingAt hinge source)
    craneHingeY wing `shouldBe` hinge
  where
    near expected actual = abs (expected - actual) < 1e-7

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
