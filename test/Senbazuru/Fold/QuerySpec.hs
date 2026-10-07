-- | The state rule, 'assignmentAtRest': the letter a crease's angle says it
-- has, which every frame a fold sequence writes follows
-- (PRDs\/05-prd-library-additions.md, L1).
module Senbazuru.Fold.QuerySpec (spec) where

import Data.Map.Strict qualified as M
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (Crease (..), assignmentAtRest, atRest, edgeKey, frameCreases)
import Senbazuru.Fold.Types
import Senbazuru.Origami.Stacking (creaseDirections)
import Test.Hspec
import Test.QuickCheck

spec :: Spec
spec = describe "assignmentAtRest, the state rule" $ do
  -- Stated as the design states it, not as the code is written: a border,
  -- cut or join comes out exactly when one goes in, and otherwise the angle
  -- alone decides. Turns red if U passed through, or the threshold were
  -- applied to a border.
  it "keeps B, C and J, and letters every other crease by its angle alone" $
    property $
      forAll (elements [minBound .. maxBound]) $ \letter ->
        forAll angles $ \angle ->
          let written = assignmentAtRest letter angle
              kept = letter `elem` [Border, Cut, Join]
           in (written `elem` [Border, Cut, Join]) == kept
                && (not kept || written == letter)
                && (kept || ((written == Mountain) == (angle < negate atRest) && (written == Valley) == (angle > atRest) && written /= Unassigned))

  -- The fixture's key frame draws its four creases M, V, M, M at angle 0:
  -- what each will be, not what it is.
  it "writes a sheet's creases drawn M and V at angle 0 as F" $ do
    file <- loadFoldFile "examples/quarter-fold-steps.fold" >>= either (fail . show) pure
    let frame = keyFrame file
    zipWith assignmentAtRest (edgesAssignment frame) (edgesFoldAngle frame) `shouldBe` replicate 8 Border ++ replicate 4 Flat

  -- The fixture's state after its first fold, with edge 9 nudged to 5e-11, a
  -- crease at rest by the rule but not by an exact test. Written as the rule
  -- writes it, F with its angle exactly 0, creaseDirections names a
  -- direction for each M or V and none for each F.
  it "agrees with creaseDirections once an F's angle is written as exactly 0" $ do
    file <- loadFoldFile "examples/quarter-fold-steps.fold" >>= either (fail . show) pure
    frame <- case otherFrames file of
      first' : _ -> pure first' {edgesFoldAngle = [if e == 9 then 5e-11 else a | (e, a) <- zip [0 :: Int ..] (edgesFoldAngle first')]}
      [] -> fail "expected the fixture's states"
    let letters = zipWith assignmentAtRest (edgesAssignment frame) (edgesFoldAngle frame)
        written = frame {edgesAssignment = letters, edgesFoldAngle = zipWith (\l a -> if l == Flat then 0 else a) letters (edgesFoldAngle frame)}
    creases <- either (fail . show) pure (frameCreases written)
    directions <- either (fail . show) pure (creaseDirections written creases)
    [(creaseAssignment c, M.lookup (edgeKey (creaseFrom c) (creaseTo c)) directions) | c <- creases, creaseAssignment c /= Border]
      `shouldBe` [(Mountain, Just (Just False)), (Flat, Just Nothing), (Mountain, Just (Just False)), (Flat, Just Nothing)]
  where
    -- Ordinary angles, and the ones either side of the threshold.
    angles = oneof [choose (-180, 180), elements [0, atRest, negate atRest, 2 * atRest, -2 * atRest, 5e-11, -5e-11, 180, -180]]
