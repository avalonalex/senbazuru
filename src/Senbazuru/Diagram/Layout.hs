-- |
-- Module      : Senbazuru.Diagram.Layout
-- Description : Putting several drawings on one page.
--
-- A folding sequence is a page of numbered figures, not a stack of separate
-- pictures. This arranges the figures.
--
-- == Everything at one scale, which is the whole point
--
-- Each step is drawn against the __same extent__: the union of every step's
-- own, which for a folding sequence is the flat sheet, because that is the
-- largest the paper ever is. So every figure is drawn through one uniform
-- scale, and the model genuinely shrinks as it is folded — a quarter fold ends
-- up a quarter of the size, on the page, that it started.
--
-- Giving each figure its own extent instead is the mistake worth naming,
-- because it looks like the tidier option: every drawing would then be blown up
-- to fill its cell, so the folded model would come out the same size as the
-- unfolded one and the reader would be told, in the most convincing way a
-- picture can, that folding a sheet in half does not make it smaller.
--
-- == How the figures are combined
--
-- By moving their coordinates, not by giving each a transform of its own. Every
-- figure's shapes are shifted into one shared model space and handed to the
-- backend as a single drawing, so nothing downstream learns what a grid is.
--
-- That works because of the two-unit rule in "Senbazuru.Diagram": a stroke
-- width, an arrowhead and a label's size are all in page units, so shifting a
-- shape does not disturb how it is inked. If they were in model units this
-- would silently reweight every line on the page.
--
-- == Where the numbers go, and why not above
--
-- Each figure's number sits /inside/ its own top-left corner, a fraction of the
-- figure's height below the top edge.
--
-- The first version reserved a band above each figure instead, and that was a
-- units bug wearing a comment. The band was measured in model units and the
-- glyph in page units, so the two only agreed at the scale it was tuned at: a
-- page of twenty-four figures already pushed the top row's numbers off the page,
-- and one of sixty painted every number over the row above. Anchoring inside
-- the figure has no such failure mode. The number can overlap its own drawing
-- when figures get very small, which is untidy; it can never collide with a
-- different figure, which would be wrong.
--
-- == Captions, and the one place page units reach the layout
--
-- A /caption/ is text under a figure (docs\/glossary.md, Caption), set by
-- 'gridOfCaptioned'. It is wrapped at word boundaries to
-- the width of the box every figure is centred in, the same for every figure,
-- and each line is a 'Label' at that box's bottom-left corner, moved down by
-- an 'Offset' in page units. Text is sized in page units and a figure in
-- model units, so the two-unit rule decides the rest: the anchor moves with
-- the figure, and the drop below it stays the same on any page.
--
-- The text needs room, and room is where the units meet. A row's captions
-- need so many page units, whatever the page's scale, but the layout works in
-- model units and does not know the scale. So the caller hands it in, as
-- 'PageScale', and each row of a captioned page is followed by a /band/, a
-- page-unit height turned into model units by that scale, in place of the
-- gutter below it, the last row's included. The band is sized for the row's
-- longest caption, so a row of one-line captions is not spaced for six
-- (owner decision 7, PRDs\/06-prd-step-diagrams.md §8). The same band in model
-- units would be the units bug the numbers above once had: right at one
-- scale, and type running into the next row at any other.
--
-- __A page with no caption is 'gridOf''s__, byte for byte. Captions are the
-- one thing that adds bands, so every page drawn before them keeps its layout.
--
-- __The widths are estimates.__ The backend has no font metrics, so a line is
-- taken to be 0.55 of the type size per character, wider than the sans-serif
-- faces measured for owner decision 7, so that a line breaks a little early
-- rather than late. A word longer than a line keeps a line of its own, and
-- overruns.
module Senbazuru.Diagram.Layout
  ( Grid (..),
    defaultGrid,
    gridOf,

    -- * Captions
    PageScale,
    pageScale,
    gridOfCaptioned,
    wrapCaption,
  )
where

import Data.Char (isSpace)
import Data.List (foldl')
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Diagram
  ( Colour,
    Diagram (..),
    Shape (..),
    diagramWithExtent,
    mapShapePoints,
  )
import Senbazuru.Diagram.Style (Theme (..))
import Senbazuru.Geometry (Box (..), V2 (..), boxCentre, boxSize, (^+^), (^-^))

-- | How to arrange the figures.
data Grid = Grid
  { -- | Figures across the page before wrapping to a new row.
    gridColumns :: !Int,
    -- | The gap between figures, as a fraction of a figure's own size. A
    -- fraction rather than a length because the figures are laid out in model
    -- units, whose size is whatever the file happened to use.
    gridGutter :: !Double,
    -- | Colour and page-unit size for the step numbers, or 'Nothing' to leave
    -- the figures unnumbered.
    --
    -- The size is in page units and a figure shrinks as more are added, so a
    -- page crowded far enough gets numbers larger than the drawings they label.
    -- That is a limit of type on a small page rather than a layout error --
    -- twenty figures on a postcard cannot be legibly numbered by any means --
    -- and the answers are a bigger page, fewer columns, or 'Nothing' here.
    gridNumbering :: !(Maybe (Colour, Double))
  }
  deriving stock (Eq, Show)

-- | Three across, a tenth of a figure between them, numbered in the theme's own
-- ink and type size.
--
-- Taken from the theme rather than chosen here so that a caller who retunes how
-- a drawing looks does not end up with new line weights and the old numbers.
defaultGrid :: Theme -> Grid
defaultGrid theme =
  Grid
    { gridColumns = 3,
      gridGutter = 0.1,
      gridNumbering = Just (themeInk theme, themeLabelSize theme)
    }

-- | Lay figures out left to right and top to bottom, numbered from one.
--
-- 'Nothing' when there is nothing to lay out, since an empty page has no extent
-- and no scale to be drawn at.
--
-- Numbering starts at one because that is what a reader counts from. The frames
-- they come from are numbered from zero, and the two stop agreeing the moment
-- anybody lays out a subset.
gridOf :: Grid -> [Diagram] -> Maybe Diagram
gridOf grid figures = arrange grid evenRows figures
  where
    rowCount = rowCountOf grid (length figures)

    -- One figure plus one gutter apart, and the page ends at the last row's
    -- bottom, with no trailing gutter. Written as the layout always wrote it,
    -- so that the pages drawn before captions keep their bytes.
    evenRows shared =
      Rows
        { rowDrop = \r -> fromIntegral r * dy,
          pageBottom = \top -> top - (fromIntegral rowCount - 1) * dy - h,
          underneath = repeat (const [])
        }
      where
        V2 _ h = boxSize shared
        dy = (1 + gridGutter grid) * h

-- | Page units per model unit: the scale the page draws a layout at, as
-- "Senbazuru.Diagram.Page"'s @pageTransform@ reports it. Positive and finite,
-- which 'pageScale' checks once, so that the layout never divides a band by
-- zero or by something that is not a number.
newtype PageScale = PageScale Double
  deriving stock (Eq, Show)

-- | A scale, if it is one: positive and finite. A page that leaves no room
-- for its drawing has a scale of zero or less, and is no page to set type on.
pageScale :: Double -> Maybe PageScale
pageScale s
  -- A NaN fails the comparison, and so is refused with the rest.
  | s > 0 && not (isInfinite s) = Just (PageScale s)
  | otherwise = Nothing

-- | 'gridOf', with a caption under each figure that has one, in the theme's
-- ink and label size, for a page drawn at the given scale.
--
-- Each caption is wrapped ('wrapCaption') to the width the shared box has on
-- the page, and its line @k@, counted from 0, is a 'Label' at the cell's
-- bottom-left corner moved down @a + k p@ page units by an 'Offset'. Columns
-- keep the grid's gutter. Below each row, the last included, lies a band of
-- @a + (L - 1) p + d@ page units in place of the gutter, @L@ being the most
-- lines any caption in the row wraps to, and 1 for a row with none; @p@ is
-- 1.2 times the type size, @a@ is 18 and @d@ is 14 (PRDs\/06, R-06-19).
--
-- A page none of whose captions has a word is 'gridOf''s page, unchanged.
gridOfCaptioned :: Theme -> Grid -> PageScale -> [(Diagram, Maybe Text)] -> Maybe Diagram
gridOfCaptioned theme grid (PageScale scale) captioned
  | all (null . captionWords . snd) captioned = gridOf grid figures
  | otherwise = arrange grid bandedRows figures
  where
    figures = map fst captioned
    columns = columnsOf grid
    rowCount = rowCountOf grid (length figures)
    size = themeLabelSize theme
    pitch = 1.2 * size

    bandedRows shared =
      Rows
        { rowDrop = below,
          pageBottom = \top -> top - below rowCount,
          underneath = map linesAt wrapped
        }
      where
        V2 w h = boxSize shared

        -- Each figure's caption as lines, wrapped to the shared box's width
        -- on the page.
        wrapped = [maybe [] (wrapCaption size (w * scale)) caption | (_, caption) <- captioned]

        -- Row r's band, in model units: page units over the scale, for the
        -- most lines any caption in the row has, and 1 for a row with none.
        bands =
          [ (captionDrop + fromIntegral (lineCount - 1) * pitch + captionGap) / scale
            | r <- [0 .. rowCount - 1],
              let lineCount = maximum (1 : [length ls | (i, ls) <- zip [0 ..] wrapped, i `div` columns == r])
          ]

        -- How far below the first row's top row r's top lies: every row above
        -- it, and the band below each.
        below r = foldl' (+) 0 [h + b | b <- take r bands]

        -- The drop is a positive y, and that is not a sign slip beside the
        -- negated row offsets: an 'Offset' is in page axes, whose y grows
        -- down the page, while model y grows up it.
        linesAt ls corner =
          [ Offset (V2 0 (captionDrop + fromIntegral k * pitch)) (Label (themeInk theme) size corner line)
            | (k, line) <- zip [0 :: Int ..] ls
          ]

-- | How far the first line's baseline sits below its figure's box, in page
-- units: far enough that the line's ink, at most 10.8 above the baseline at
-- the default type size, clears a fanned figure's largest move of 6.4
-- (PRDs\/06 §8). Set with 'captionGap' by S24 at 06's figures (C134); the
-- turn-over loop, whose size is not set yet, may need more (S29).
captionDrop :: Double
captionDrop = 18

-- | Page units below a band's last baseline, for the line's descent and the
-- gap before the next row's numbers.
captionGap :: Double
captionGap = 14

-- | The words of a caption. One with none is no caption.
captionWords :: Maybe Text -> [Text]
captionWords = maybe [] wordsOf

-- | The words of a text: what lies between the places a line may break.
--
-- Not 'T.words', which breaks at every character 'isSpace' admits, a
-- non-breaking space among them, so a caption that joins 90 to degrees with
-- one would be split exactly where its author asked it not to be, and the
-- space lost when the words are joined again. A non-breaking space between
-- two characters of a word stays inside it. One beside a break is part of
-- that run of spaces, which counts as one, so a word never starts or ends
-- with one, and a word of nothing but such spaces is no word.
wordsOf :: Text -> [Text]
wordsOf = filter (not . T.null) . map T.strip . T.split breaks
  where
    breaks c = isSpace c && c `notElem` ['\x00A0', '\x2007', '\x202F']

-- | A caption broken at word boundaries into lines no wider than the given
-- width, both in page units, for type of the given size.
--
-- Greedy, taking each word onto the line while the line still fits, and with
-- a line's width estimated at 0.55 of the type size per character, spaces
-- included, since nothing here knows the font. A word longer than a line
-- keeps a line of its own. Runs of spaces count as one, and a caption of none
-- but spaces has no lines. A non-breaking space is part of its word.
wrapCaption :: Double -> Double -> Text -> [Text]
wrapCaption size width caption = go (wordsOf caption)
  where
    fits n = fromIntegral n * 0.55 * size <= width
    go = \case
      [] -> []
      word : rest -> let (line, later) = fill word rest in line : go later
    fill line = \case
      word : rest | fits (T.length line + 1 + T.length word) -> fill (line <> " " <> word) rest
      rest -> (line, rest)

-- | Figures across a row: the grid's columns, and at least one.
columnsOf :: Grid -> Int
columnsOf grid = max 1 (gridColumns grid)

-- | How many rows the given number of figures fills.
rowCountOf :: Grid -> Int -> Int
rowCountOf grid count = (count + columns - 1) `div` columns
  where
    columns = columnsOf grid

-- | How a page's rows stack, given the box every figure is centred in.
data Rows = Rows
  { -- | How far below the first row's top row r's top lies.
    rowDrop :: Int -> Double,
    -- | Where the page ends, given the first row's top.
    pageBottom :: Double -> Double,
    -- | What goes under each figure, in order, given its cell's bottom-left
    -- corner.
    underneath :: [V2 -> [Shape]]
  }

-- | The figures in rows, each centred in a cell of the shared box, numbered,
-- and with what the rows put under it.
arrange :: Grid -> (Box -> Rows) -> [Diagram] -> Maybe Diagram
arrange grid rowsFor figures = case map diagramExtent figures of
  [] -> Nothing
  (e : es) -> Just (diagramWithExtent (page shared rows) (shapes shared rows))
    where
      shared = foldl' unionBox e es
      rows = rowsFor shared
  where
    columns = columnsOf grid
    used = min columns (length figures)

    -- One figure plus one gutter, across. The gutter is a fraction of the
    -- figure and of nothing else, which is what its documentation says.
    columnStep shared = (1 + gridGutter grid) * w
      where
        V2 w _ = boxSize shared

    -- Rows run down the page, so later rows sit at smaller y: model space has y
    -- increasing upwards and a reader goes the other way.
    offsetOf shared rows i =
      V2 (fromIntegral (i `mod` columns) * columnStep shared) (negate (rowDrop rows (i `div` columns)))

    -- Only the scale is shared; each figure is centred in its cell. Keeping a
    -- figure at the absolute position its coordinates give is defensible -- the
    -- folded paper really does end up in one half of where the sheet was -- but
    -- across separate figures it reads as a drawing that has slipped, and it
    -- drifts away from the number beside it. Books centre.
    centred shared d = boxCentre shared ^-^ boxCentre (diagramExtent d)

    shapes shared rows = concat (zipWith3 placed [0 ..] figures (underneath rows))
      where
        placed i d under =
          map (mapShapePoints (^+^ shift i d)) (diagramShapes d)
            <> number i d (shift i d)
            <> under (corner ^+^ offsetOf shared rows i)

        shift i d = offsetOf shared rows i ^+^ centred shared d

        Box corner _ = shared

        number i d moved = case gridNumbering grid of
          Nothing -> []
          Just (colour, size) ->
            [Label colour size (V2 left (top - drop') ^+^ moved) (tshow (i + 1))]
          where
            Box (V2 left _) (V2 _ top) = diagramExtent d
            V2 _ h = boxSize shared
            -- Far enough below the top edge that the glyph, which grows upwards
            -- from its baseline, stays inside the figure at any scale.
            drop' = 0.12 * h

    -- The page is the grid's own bounding box: the columns actually used, with
    -- no trailing gutter, and the rows down to where the rows say it ends.
    page shared rows =
      Box
        (V2 x0 (pageBottom rows y1))
        (V2 (x0 + (fromIntegral used - 1) * columnStep shared + w) y1)
      where
        Box (V2 x0 _) (V2 _ y1) = shared
        V2 w _ = boxSize shared

unionBox :: Box -> Box -> Box
unionBox (Box (V2 ax ay) (V2 bx by)) (Box (V2 cx cy) (V2 dx dy)) =
  Box (V2 (min ax cx) (min ay cy)) (V2 (max bx dx) (max by dy))

tshow :: (Show a) => a -> Text
tshow = T.pack . show
