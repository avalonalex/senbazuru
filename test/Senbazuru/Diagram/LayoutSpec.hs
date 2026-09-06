-- |
-- Tests for arranging figures on a page.
--
-- The property that matters is the one a reader would notice instantly if it
-- broke: every figure is drawn at the same scale, so a model that has been
-- folded in half looks half the size. A layout that gave each figure its own
-- scale would blow the small ones back up to fill their cells and tell the
-- reader that folding a sheet does not make it smaller.
module Senbazuru.Diagram.LayoutSpec (spec) where

import Data.Maybe (mapMaybe)
import Senbazuru.Diagram
import Senbazuru.Diagram.Layout
import Senbazuru.Diagram.Style (Theme (..), defaultTheme)
import Senbazuru.Geometry
import Test.Hspec

ink :: Colour
ink = themeInk defaultTheme

-- | A square outline of the given size, as its own figure.
square :: Double -> Diagram
square size =
  diagramWithExtent
    (Box (V2 0 0) (V2 size size))
    [Polyline (solid ink 1) [V2 0 0, V2 size 0, V2 size size, V2 0 size, V2 0 0]]

-- | How wide each polyline in a diagram is, in model units.
widths :: Diagram -> [Double]
widths d = map spread (mapMaybe points (diagramShapes d))
  where
    points = \case
      Polyline _ ps -> Just ps
      Offset _ shape -> points shape
      _ -> Nothing
    spread ps = maximum (map xOf ps) - minimum (map xOf ps)
    xOf (V2 x _) = x

labels :: Diagram -> [String]
labels d = mapMaybe text (diagramShapes d)
  where
    text = \case
      Label _ _ _ t -> Just (show t)
      _ -> Nothing

plain :: Grid
plain = (defaultGrid defaultTheme) {gridNumbering = Nothing}

-- | The page a grid lays the figures out on.
--
-- 'gridOf' has nothing to lay out for no figures, and every case below passes
-- it some, so 'Nothing' here would be a bug in the layout rather than a case
-- worth handling. Writing that as @let Just page = ...@ says so compactly and
-- costs a warning and a failure message: an irrefutable pattern that does not
-- match throws with no indication of which test it was. This says the same
-- thing and reports it.
pageOf :: Grid -> [Diagram] -> IO Diagram
pageOf grid figures =
  maybe (fail "gridOf laid out nothing for figures it was given") pure (gridOf grid figures)

spec :: Spec
spec = do
  describe "gridOf" $ do
    it "has nothing to lay out for no figures" $
      -- An empty page has no extent, and so no scale to be drawn at.
      gridOf plain [] `shouldBe` Nothing

    it "draws every figure at the one scale, so a folded model looks smaller" $ do
      -- The whole point. The figures are combined by moving their coordinates
      -- into one space, never by scaling them, so a half-size figure stays half
      -- the size of a full one.
      page <- pageOf plain [square 1, square 0.5]
      widths page `shouldBe` [1, 0.5]

    it "wraps to a new row after the column count" $ do
      wide <- pageOf plain {gridColumns = 4} (replicate 4 (square 1))
      tall <- pageOf plain {gridColumns = 2} (replicate 4 (square 1))
      let V2 wideW wideH = boxSize (diagramExtent wide)
          V2 tallW tallH = boxSize (diagramExtent tall)
      -- Four across is wider and shallower than two across; two across is a
      -- square block of four.
      wideW `shouldSatisfy` (> tallW)
      tallH `shouldSatisfy` (> wideH)

    it "leaves no trailing gutter on the page" $ do
      -- One figure in a grid is exactly as wide as that figure, not a figure
      -- and a gap.
      one <- pageOf plain [square 1]
      let V2 w _ = boxSize (diagramExtent one)
      w `shouldBe` 1

    it "moves a figure's shapes and not the page-unit nudges on them" $ do
      -- The same reason a stroke width survives being laid out: an offset is in
      -- page units, so it means the same thing wherever the figure ends up. A
      -- layout that shifted it too would step the layers of a folded model
      -- further apart in every cell but the first.
      let nudged = (square 1) {diagramShapes = map (Offset (V2 7 (-7))) (diagramShapes (square 1))}
      page <- pageOf plain [square 1, nudged]
      [v | Offset v _ <- diagramShapes page] `shouldBe` [V2 7 (-7)]
      -- And the shape inside did move, or it would have been drawn on top of
      -- the first figure.
      widths page `shouldBe` [1, 1]

  describe "numbering" $ do
    it "numbers from one, because that is what a reader counts from" $ do
      -- The frames these came from are numbered from zero, and the two stop
      -- agreeing the moment anyone lays out a subset.
      page <- pageOf (defaultGrid defaultTheme) [square 1, square 1, square 1]
      labels page `shouldBe` ["\"1\"", "\"2\"", "\"3\""]

    it "can be turned off" $ do
      page <- pageOf plain [square 1, square 1]
      labels page `shouldBe` []
