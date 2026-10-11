-- | Sheet lengths: the one scale, the sheet box's longer side, on both axes,
-- measured from the box's south-west corner; and the two conversions undoing
-- each other.
module Senbazuru.Sequence.SheetLengthsSpec (spec) where

import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Sequence.SheetLengths
import Test.Hspec
import Test.QuickCheck

spec :: Spec
spec = describe "sheet lengths" $ do
  -- A sheet 4 wide and 2 tall, its south-west corner at (1, 3). One sheet
  -- length is its width, 4, so its far corner is (1, 1/2) and its top edge
  -- is at v = 1/2. Turns red if each axis were scaled by its own side, which
  -- puts the far corner at (1, 1), or if the scale were the shorter side.
  it "measures both axes in the longer side, from the south-west corner" $ do
    let wide = Box (V2 1 3) (V2 5 5)
    sheetLengthOf wide `shouldBe` 4
    inSheetLengths wide (V2 1 3) `shouldBe` V2 0 0
    inSheetLengths wide (V2 5 5) `shouldBe` V2 1 0.5
    -- (1, 1) lies above the top edge: off the paper.
    fromSheetLengths wide (V2 1 1) `shouldBe` V2 5 7
    lengthInSheetLengths wide 2 `shouldBe` 0.5

  -- The same sheet stood on end, 2 wide and 4 tall: one sheet length is now
  -- its height, so its far corner is (1/2, 1). Turns red if the scale were
  -- always the width, which the wide sheet above cannot tell from the longer
  -- side.
  it "takes the height when the sheet is taller than it is wide" $ do
    let tall = Box (V2 1 3) (V2 3 7)
    sheetLengthOf tall `shouldBe` 4
    inSheetLengths tall (V2 3 7) `shouldBe` V2 0.5 1
    lengthInSheetLengths tall 2 `shouldBe` 0.5

  it "converts there and back to the same point, within rounding" $
    forAll genBox $ \box -> forAll genPoint $ \p ->
      norm (fromSheetLengths box (inSheetLengths box p) ^-^ p) <= 1e-9 * (1 + norm p)
  where
    genPoint = V2 <$> choose (-100, 100) <*> choose (-100, 100)
    genBox = do
      lo <- genPoint
      w <- choose (0.1, 100)
      h <- choose (0.1, 100)
      pure (Box lo (lo ^+^ V2 w h))
