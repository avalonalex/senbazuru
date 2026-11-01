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
        -- A caption with no words is no caption, a non-breaking space being
        -- no word.
        gridOfCaptioned defaultTheme numbered (scaleOf 100) [(f, Just " ") | f <- figures] `shouldBe` gridOf numbered figures
        gridOfCaptioned defaultTheme numbered (scaleOf 100) [(f, Just "\x00A0") | f <- figures] `shouldBe` gridOf numbered figures

    -- The band below each row is in page units: the same on the page at two
    -- scales, so a band sized in model units is red at one of them. Each row's
    -- is a + (L - 1) p + d for its longest caption, a row of none included,
    -- with a = 18, p = 1.2 x 14 and d = 14, and L counted by wrapping the
    -- captions given, not the lines drawn, so a wrap to the wrong width moves
    -- the band and not the expectation. Columns keep the gutter, a tenth of
    -- the shared box's width.
    it "follows each row with a band in page units for its longest caption, the last included" $
      forM_ [(n, s) | n <- [1 .. 60], s <- [100, 300]] $ \(n, s) -> do
        page <- captionedPage s n
        let cells = cellsOf n page
            rows = rowsOf cells
            bottoms = [minimum [y0 | Box (V2 _ y0) _ <- row] | row <- rows]
            tops = [maximum [y1 | Box _ (V2 _ y1) <- row] | row <- rows]
            Box (V2 _ pageBottom) _ = diagramExtent page
            gaps = zipWith (-) bottoms (drop 1 tops ++ [pageBottom])
            expected = [18 + fromIntegral (longest row - 1) * 16.8 + 14 | row <- rowsOf (map (length . wrapped s) (captionsFor n))]
        length cells `shouldBe` n
        length gaps `shouldBe` length expected
        forM_ (zip gaps expected) $ \(gap, band) ->
          (n, s, gap * s) `shouldSatisfy` (\(_, _, g) -> abs (g - band) < 1e-9)
        [x | Box (V2 x _) _ <- take 3 cells] `shouldSatisfy` (and . zipWith near1 [0, 1.1, 2.2])

    -- Each caption sits under its own figure: its lines are a label at that
    -- figure's cell's bottom-left corner, the shared box's and not the
    -- figure's own, line k moved 18 + k p page units down, and they are the
    -- caption wrapped to the box's width on the page, 1 x s, not to the
    -- figure's own width or the box's height. No line is wider on the page
    -- than the box, by the estimate, unless it is one word, and every line is
    -- in the theme's ink and label size.
    it "sets each caption's lines at its own cell's bottom-left corner, wrapped to the box on the page" $
      forM_ [(n, s) | n <- [1 .. 60], s <- [100, 300]] $ \(n, s) -> do
        page <- captionedPage s n
        let expected =
              [ (corner, [18 + fromIntegral k * 16.8 | k <- [0 .. length ls - 1]], ls)
                | (Box corner _, caption) <- zip (cellsOf n page) (captionsFor n),
                  let ls = wrapped s caption,
                  not (null ls)
              ]
            actual = captionLines page
        (n, s, length actual) `shouldBe` (n, s, length expected)
        forM_ (zip actual expected) $ \((at, drops, texts), (corner, drops', texts')) -> do
          (n, s, at) `shouldSatisfy` (\(_, _, c) -> near c corner)
          drops `shouldBe` drops'
          texts `shouldBe` texts'
          forM_ texts $ \line ->
            (n, s, line) `shouldSatisfy` (\(_, _, l) -> fromIntegral (T.length l) * 0.55 * 14 <= s || length (T.words l) == 1)
        [(colour, size) | Offset _ (Label colour size _ _) <- diagramShapes page] `shouldSatisfy` all (== (ink, 14))

    -- The numbers are the bare labels, one per figure and in order; the
    -- captions' lines are the labels moved by an Offset.
    it "keeps every figure's number" $ do
      page <- captionedPage 100 4
      [t | Label _ _ _ t <- diagramShapes page] `shouldBe` ["1", "2", "3", "4"]
      length (labels page) `shouldBe` 4 + sum [length ts | (_, _, ts) <- captionLines page]

  describe "pageScale" $
    it "refuses a scale that is not positive and finite" $
      map (void . pageScale) [1, 1e-300, 0, -1, 0 / 0, 1 / 0] `shouldBe` [Just (), Just (), Nothing, Nothing, Nothing, Nothing]

  describe "wrapCaption" $ do
    -- 115 page units hold 14 characters at 0.55 em of 14-unit type.
    it "breaks greedily at word boundaries, by 0.55 em a character" $ do
      wrapCaption 14 115 "Fold the left half behind, onto the right."
        `shouldBe` ["Fold the left", "half behind,", "onto the", "right."]
      -- Ten characters of 10-unit type are 55 units wide at 0.55 em: they fit
      -- in 55.01 and not in 54.99, so 0.551 em is red at the first and 0.549
      -- at the second.
      wrapCaption 10 55.01 "abcd efghi" `shouldBe` ["abcd efghi"]
      wrapCaption 10 54.99 "abcd efghi" `shouldBe` ["abcd", "efghi"]

    it "never breaks at a non-breaking space, and keeps it" $
      wrapCaption 14 115 "Fold to 90\x00A0\&degrees and then some more"
        `shouldBe` ["Fold to", "90\x00A0\&degrees and", "then some more"]

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

-- | A rectangle outline, w across and h tall, as its own figure.
rectangle :: Double -> Double -> Diagram
rectangle w h =
  diagramWithExtent
    (Box (V2 0 0) (V2 w h))
    [Polyline (solid ink 1) [V2 0 0, V2 w 0, V2 w h, V2 0 h, V2 0 0]]

-- | n figures of three shapes, laid out at scale s, three across. The box
-- every figure is centred in, 1 across and 0.9 tall from two figures on, is
-- none of theirs, so
-- a caption placed or wrapped by its figure's own outline, or by the box's
-- height, lands in the wrong place.
captionedPage :: Double -> Int -> IO Diagram
captionedPage s n =
  maybe (fail "gridOfCaptioned laid out nothing") pure $
    gridOfCaptioned defaultTheme numbered (scaleOf s) (zip (map figure [0 .. n - 1]) (captionsFor n))
  where
    figure i = case i `mod` 3 of
      0 -> rectangle 1 0.6
      1 -> rectangle 0.5 0.9
      _ -> rectangle 0.8 0.3

-- | captionedPage's captions: 0 to 11 words, which wrap to 0 to 7 lines at
-- s = 100 and 0 to 2 at s = 300, and every fourth row with none, so that
-- some rows have a one-line band of their own.
captionsFor :: Int -> [Maybe Text]
captionsFor n = map captionFor [0 .. n - 1]
  where
    captionFor i
      | (i `div` 3) `mod` 4 == 3 = Nothing
      | otherwise = Just (T.unwords (take ((i * 7 + 3) `mod` 12) (cycle ["Fold", "the", "corner", "behind,", "to", "the", "centre."])))

-- | A caption's lines on captionedPage's box at scale s, 1 x s page units
-- wide.
wrapped :: Double -> Maybe Text -> [Text]
wrapped s = maybe [] (wrapCaption 14 s)

-- | Each figure's cell on captionedPage's page of n, in the order laid out:
-- the shared box centred on the figure's outline. That box is 1 x 0.9, but
-- a page of one figure has only that figure's 1 x 0.6.
cellsOf :: Int -> Diagram -> [Box]
cellsOf n d =
  [ Box (V2 (cx - 0.5) (cy - h / 2)) (V2 (cx + 0.5) (cy + h / 2))
    | Polyline _ ps <- diagramShapes d,
      let xs = [x | V2 x _ <- ps]
          ys = [y | V2 _ y <- ps]
          cx = (minimum xs + maximum xs) / 2
          cy = (minimum ys + maximum ys) / 2
  ]
  where
    h = if n == 1 then 0.6 else 0.9

near :: V2 -> V2 -> Bool
near (V2 x y) (V2 x' y') = near1 x x' && near1 y y'

near1 :: Double -> Double -> Bool
near1 a b = abs (a - b) < 1e-9

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

-- | The most lines in a row, and 1 for a row with none.
longest :: [Int] -> Int
longest = maximum . (1 :)
