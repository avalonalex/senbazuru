-- |
-- Tests for arranging figures on a page.
--
-- The property that matters is the one a reader would notice instantly if it
-- broke: every figure is drawn at the same scale, so a model that has been
-- folded in half looks half the size. A layout that gave each figure its own
-- scale would blow the small ones back up to fill their cells and tell the
-- reader that folding a sheet does not make it smaller.
module Senbazuru.Diagram.LayoutSpec (spec) where

import Control.Monad (forM_, void)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
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

-- | Every label's text, a caption's lines among them, which are 'Label's
-- moved by an 'Offset'.
labels :: Diagram -> [String]
labels d = mapMaybe text (diagramShapes d)
  where
    text = \case
      Label _ _ _ t -> Just (show t)
      Offset _ shape -> text shape
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

  -- A12, restated for owner decision 7 (PRDs/06 §8, R-06-18, R-06-19).
  describe "gridOfCaptioned" $ do
    -- Red if a band is added whether or not a figure has a caption, or if
    -- the captioned layout's arithmetic leaks into an uncaptioned page.
    it "lays a page with no caption out as gridOf does, for 1 to 60 figures" $
      forM_ [1 .. 60] $ \n -> do
        let figures = [square (1 / fromIntegral (1 + i `mod` 3)) | i <- [1 .. n :: Int]]
        gridOfCaptioned defaultTheme numbered (scaleOf 100) [(f, Nothing) | f <- figures] `shouldBe` gridOf numbered figures
        -- A caption with no words is no caption.
        gridOfCaptioned defaultTheme numbered (scaleOf 100) [(f, Just " ") | f <- figures] `shouldBe` gridOf numbered figures

    -- The band below each row is in page units: the same on the page at two
    -- scales, so a band sized in model units is red at one of them. Each row's
    -- is a + (L - 1) p + d for its longest caption, a row of none included,
    -- with a = 18, p = 1.2 x 14 and d = 14. Columns keep the gutter.
    it "follows each row with a band in page units for its longest caption, the last included" $
      forM_ [(n, s) | n <- [1 .. 60], s <- [100, 300]] $ \(n, s) -> do
        page <- captionedPage s n
        let figures = figureBoxes page
            rows = rowsOf figures
            bottoms = [minimum [y0 | Box (V2 _ y0) _ <- row] | row <- rows]
            tops = [maximum [y1 | Box _ (V2 _ y1) <- row] | row <- rows]
            Box (V2 _ pageBottom) _ = diagramExtent page
            gaps = zipWith (-) bottoms (drop 1 tops ++ [pageBottom])
            expected = [18 + fromIntegral (longest row - 1) * 16.8 + 14 | row <- rowCaptions page rows]
        length figures `shouldBe` n
        forM_ (zip gaps expected) $ \(gap, band) ->
          (n, s, gap * s) `shouldSatisfy` (\(_, _, g) -> abs (g - band) < 1e-9)
        [x | Box (V2 x _) _ <- take 3 figures] `shouldBe` take n [0, 1.1, 2.2]

    -- Each line is a label at its figure's cell's bottom-left corner, line k
    -- moved 18 + k p page units down, and no line is wider on the page than
    -- the box, by the estimate, unless it is one word.
    it "sets each caption's lines at its cell's bottom-left corner, none wider than the box" $
      forM_ [(n, s) | n <- [1 .. 60], s <- [100, 300]] $ \(n, s) -> do
        page <- captionedPage s n
        let cornerOf = [(i, V2 x0 y0) | (i, Box (V2 x0 y0) _) <- zip [0 :: Int ..] (figureBoxes page)]
        forM_ (captionLines page) $ \(corner, drops, texts) -> do
          (n, s, corner) `shouldSatisfy` (\(_, _, c) -> c `elem` map snd cornerOf)
          drops `shouldBe` [18 + fromIntegral k * 16.8 | k <- [0 .. length drops - 1]]
          forM_ texts $ \line ->
            (n, s, line) `shouldSatisfy` (\(_, _, t) -> fromIntegral (T.length t) * 0.55 * 14 <= s || length (T.words t) == 1)

    -- The numbers are the bare labels, each inside its figure as gridOf puts
    -- it; the captions' lines are the labels moved by an Offset.
    it "keeps every figure's number" $ do
      page <- captionedPage 100 4
      [t | Label _ _ _ t <- diagramShapes page] `shouldBe` ["1", "2", "3", "4"]
      length (labels page) `shouldBe` 4 + sum [length ts | (_, _, ts) <- captionLines page]

  describe "pageScale" $
    it "refuses a scale that is not positive and finite" $
      map (void . pageScale) [1, 1e-300, 0, -1, 0 / 0, 1 / 0] `shouldBe` [Just (), Just (), Nothing, Nothing, Nothing, Nothing]

  describe "wrapCaption" $ do
    -- 115 page units hold 14 characters at 0.55 em of 14-unit type.
    it "breaks greedily at word boundaries, by 0.55 em a character" $
      wrapCaption 14 115 "Fold the left half behind, onto the right."
        `shouldBe` ["Fold the left", "half behind,", "onto the", "right."]

    it "gives a word longer than a line a line of its own" $
      wrapCaption 14 30 "a extraordinarily b" `shouldBe` ["a", "extraordinarily", "b"]

    it "counts a run of spaces as one, and a caption of only spaces as none" $ do
      wrapCaption 14 115 "  Fold   the  left  " `shouldBe` ["Fold the left"]
      wrapCaption 14 115 "   " `shouldBe` []

-- | Numbered, three across, as a run's page is.
numbered :: Grid
numbered = defaultGrid defaultTheme

scaleOf :: Double -> PageScale
scaleOf s = fromMaybe (error ("not a scale: " <> show s)) (pageScale s)

-- | n unit squares, laid out at scale s, three across, with captions of 0 to
-- 11 words, which wrap to 1 to 4 lines at s = 100, and every fourth row
-- with none, so that some rows have a one-line band of their own.
captionedPage :: Double -> Int -> IO Diagram
captionedPage s n =
  maybe (fail "gridOfCaptioned laid out nothing") pure $
    gridOfCaptioned defaultTheme numbered (scaleOf s) [(square 1, captionFor i) | i <- [0 .. n - 1]]
  where
    captionFor i
      | (i `div` 3) `mod` 4 == 3 = Nothing
      | otherwise = Just (T.unwords (take ((i * 7 + 3) `mod` 12) (cycle ["Fold", "the", "corner", "behind,", "to", "the", "centre."])))

-- | Each figure's box, by its outline, in the order laid out.
figureBoxes :: Diagram -> [Box]
figureBoxes d = [Box (V2 (minimum xs) (minimum ys)) (V2 (maximum xs) (maximum ys)) | Polyline _ ps <- diagramShapes d, let xs = [x | V2 x _ <- ps]; ys = [y | V2 _ y <- ps]]

-- | Figures in rows of three.
rowsOf :: [a] -> [[a]]
rowsOf = \case
  [] -> []
  xs -> take 3 xs : rowsOf (drop 3 xs)

-- | Each caption's anchor, the drops of its lines, and their text.
captionLines :: Diagram -> [(V2, [Double], [Text])]
captionLines d = foldr gather [] [(at, y, t) | Offset (V2 0 y) (Label _ _ at t) <- diagramShapes d]
  where
    gather (at, y, t) = \case
      (at', ys, ts) : rest | at' == at -> (at, y : ys, t : ts) : rest
      rest -> (at, [y], [t]) : rest

-- | For each row, how many lines each of its figures' captions has.
rowCaptions :: Diagram -> [[Box]] -> [[Int]]
rowCaptions d rows = [[linesAt (corner b) | b <- row] | row <- rows]
  where
    corner (Box lo _) = lo
    linesAt c = sum [length ds | (at, ds, _) <- captionLines d, at == c]

-- | The most lines in a row, and 1 for a row with none.
longest :: [Int] -> Int
longest = maximum . (1 :)
