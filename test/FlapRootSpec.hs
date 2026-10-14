-- | A flap's root, the line it turns from, found by a rule rather than chosen
-- by eye (owner decisions 34 and 35). On the crane the rule has to find the
-- wing's root where the owner placed it, at the neck and tail bases, and has
-- to refuse the neck and the tail, whose roots lie between the body's layers.
module FlapRootSpec (spec) where

import Control.Monad (forM_)
import CraneWing (CraneWing (..), buildCraneWingAt, wingRoot)
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.List (sortOn)
import FlapRoot
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Origami.Flat (Panel (..), Sheet (..))
import Test.Hspec

spec :: Spec
spec = describe "a flap's root" $ do
  source <- runIO (loadFoldFile "examples/crane.fold" >>= either (fail . show) (pure . keyFrame))
  -- The neck and tail bases are the folded crane outline's two reflex
  -- corners beside the wing, where its edges meet the neck's line x - y = 1/2
  -- and the tail's line x + y = 3/2, at the height the sheet's corner (1, 1),
  -- the tip of the head, folds to: y* = 1 - (sqrt 2 / 4)(1 + 2 sin 22.5 degrees)
  -- (PRDs/decisions.md, C102). So the ends are exactly (1/2 + y*, y*) and
  -- (3/2 - y*, y*). Probing alone finds them 1.1e-9 and 1.4e-9 low; turns red
  -- if the ends were not made exact.
  it "finds the crane wing's root at the neck and tail bases from either wing's tip" $
    forM_ [V2 0 1, V2 1 0] $ \corner -> do
      root <- right (prepare source corner >>= findRoot)
      rootExact root `shouldBe` (True, True)
      let (a, b) = rootEnds root
      case sortOn v2x [a, b] of
        [V2 x1 y1, V2 x2 y2] -> do
          [x1, y1, x2, y2] `shouldSatisfy` and . zipWith near [0.5 + rootHeight, rootHeight, 1.5 - rootHeight, rootHeight]
        _ -> expectationFailure "expected two ends"
  it "turns the wing about its root, moving the wing's eight faces" $ do
    prepared <- right (prepare source (V2 0 1))
    root <- right (findRoot prepared)
    turned <- right (turnAbout prepared 2 (rootEnds root))
    turnResult turned `shouldBe` Right (90, 8)
  -- The tail, at the sheet's corner (0, 0), has an outline that meets the
  -- paper beside it on one side only, where its end is made exact. On the
  -- other it runs inside the body, where the run jumps because other paper
  -- ends, no edges cross, and the end stands as probed. So the rule's second
  -- end is wrong and the turn check refuses the root, from the start of the
  -- turn. The neck, at (1, 1), has an edge that never meets other paper.
  it "refuses the tail and the neck, whose roots lie between the body's layers" $ do
    tail' <- right (prepare source (V2 0 0))
    tailRoot <- right (findRoot tail')
    rootExact tailRoot `shouldBe` (True, False)
    turned <- right (turnAbout tail' 2 (rootEnds tailRoot))
    turnResult turned `shouldSatisfy` isLeft
    neck <- right (prepare source (V2 1 1))
    isLeft (findRoot neck) `shouldBe` True
  it "refuses a pattern whose own unassigned creases it could mistake for its crease" $ do
    let marked = source {edgesAssignment = Unassigned : drop 1 (edgesAssignment source)}
    isLeft (prepare marked (V2 0 1)) `shouldBe` True
  -- A flap whose edges meet the paper beside it at 5 degrees, on a sheet made
  -- here: the square x in [1/2, 3/2], y in [0, 3/2], with paper on each side
  -- whose edge meets the flap's at (1/2, 1) and (3/2, 1). Probing stops where
  -- the gap closes to a hair, which at so narrow an angle is more than ten
  -- hairs from each corner. Turns red if only crossings within ten hairs of
  -- the end probed were kept.
  it "makes exact the ends of a root whose edges meet at a narrow angle" $ do
    prepared <- right (prepare source (V2 0 1))
    let angle = 5 * pi / 180
        flap = [V2 0.5 0, V2 1.5 0, V2 1.5 1.5, V2 0.5 1.5]
        beside = [V2 (1.5 + 0.5 * sin angle) (1 - 0.5 * cos angle), V2 2.5 (1 - 0.5 * cos angle), V2 2.5 1.5, V2 1.5 1.5, V2 1.5 1]
        mirrored = reverse [V2 (2 - x) y | V2 x y <- beside]
        sheet = Sheet {sheetFaces = [], sheetPanels = [Panel (FaceId 0) flap True, Panel (FaceId 1) beside True, Panel (FaceId 2) mirrored True], sheetCreases = [], sheetPositions = IM.empty, sheetPlane = 0, sheetHair = 1e-9, sheetSpeck = 1e-9}
    root <- right (findRoot prepared {preparedSheet = sheet, preparedTip = V2 1 0, preparedScale = 2})
    rootExact root `shouldBe` (True, True)
    case sortOn v2x [fst (rootEnds root), snd (rootEnds root)] of
      [V2 x1 y1, V2 x2 y2] -> [x1, y1, x2, y2] `shouldSatisfy` and . zipWith near [0.5, 1, 1.5, 1]
      _ -> expectationFailure "expected two ends"
  it "gives CraneWing a level line to crease the wing along" $ do
    hinge <- right (wingRoot source)
    hinge `shouldSatisfy` near rootHeight
    wing <- right (buildCraneWingAt hinge source)
    craneHingeY wing `shouldBe` hinge
  where
    near expected actual = abs (expected - actual) < 1e-12
    rootHeight = 1 - (sqrt 2 / 4) * (1 + 2 * sin (pi / 8))

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
