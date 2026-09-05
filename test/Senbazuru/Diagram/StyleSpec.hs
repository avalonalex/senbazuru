-- |
-- Tests for the line conventions.
--
-- The rule worth pinning is the one the camera broke without anyone noticing:
-- a folded form is drawn with solid edges, because the dashes mean "a fold
-- still to be made". The exact dash patterns are pinned by the golden files.
module Senbazuru.Diagram.StyleSpec (spec) where

import Control.Monad (forM_)
import Data.Maybe (mapMaybe)
import Senbazuru.Diagram (Dash (..), Stroke (..))
import Senbazuru.Diagram.Style
import Senbazuru.Fold.Types (Assignment (..))
import Test.Hspec

spec :: Spec
spec = do
  describe "strokeFor" $ do
    it "never dashes an edge of a folded form" $
      map strokeDash (strokesUnder FoldedFormNotation) `shouldSatisfy` all (== Dash [])

    it "dashes exactly the mountains and valleys of a crease pattern" $
      forM_ everyAssignment $ \a ->
        case strokeFor defaultTheme CreasePatternNotation a of
          Nothing -> pure ()
          Just s -> (a, strokeDash s /= Dash []) `shouldBe` (a, a `elem` [Mountain, Valley])

    it "differs between the notations only in the dashes" $
      -- Same colours, same widths, same set of edges drawn at all. The
      -- folded-form picture of a frame is its crease-pattern picture with the
      -- instructions removed, nothing more.
      forM_ everyAssignment $ \a ->
        fmap undashed (strokeFor defaultTheme CreasePatternNotation a)
          `shouldBe` fmap undashed (strokeFor defaultTheme FoldedFormNotation a)
  where
    everyAssignment = [minBound .. maxBound] :: [Assignment]
    strokesUnder notation = mapMaybe (strokeFor defaultTheme notation) everyAssignment
    undashed s = s {strokeDash = Dash []}
