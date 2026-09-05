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
module Senbazuru.Diagram.Layout
  ( Grid (..),
    defaultGrid,
    gridOf,
  )
where

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
gridOf grid figures = case map diagramExtent figures of
  [] -> Nothing
  (e : es) -> Just (diagramWithExtent (page shared) (shapes shared))
    where
      shared = foldl' unionBox e es
  where
    columns = max 1 (gridColumns grid)
    count = length figures
    rows = (count + columns - 1) `div` columns
    used = min columns count

    -- One figure plus one gutter, in each direction. The gutter is a fraction
    -- of the figure and of nothing else, which is what its documentation says.
    strideOf shared = (1 + gridGutter grid) *^| boxSize shared
      where
        s *^| V2 x y = V2 (s * x) (s * y)

    -- Rows run down the page, so later rows sit at smaller y: model space has y
    -- increasing upwards and a reader goes the other way.
    offsetOf shared i =
      V2 (fromIntegral (i `mod` columns) * dx) (negate (fromIntegral (i `div` columns)) * dy)
      where
        V2 dx dy = strideOf shared

    -- Only the scale is shared; each figure is centred in its cell. Keeping a
    -- figure at the absolute position its coordinates give is defensible -- the
    -- folded paper really does end up in one half of where the sheet was -- but
    -- across separate figures it reads as a drawing that has slipped, and it
    -- drifts away from the number beside it. Books centre.
    centred shared d = boxCentre shared ^-^ boxCentre (diagramExtent d)

    shapes shared = concat (zipWith placed [0 ..] figures)
      where
        placed i d =
          map (mapShapePoints (^+^ shift i d)) (diagramShapes d) <> number i d (shift i d)

        shift i d = offsetOf shared i ^+^ centred shared d

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

    -- The page is the grid's own bounding box: the columns actually used and
    -- the rows actually needed, with no trailing gutter on either side.
    page shared =
      Box
        (V2 x0 (y1 - (fromIntegral rows - 1) * dy - h))
        (V2 (x0 + (fromIntegral used - 1) * dx + w) y1)
      where
        Box (V2 x0 _) (V2 _ y1) = shared
        V2 w h = boxSize shared
        V2 dx dy = strideOf shared

unionBox :: Box -> Box -> Box
unionBox (Box (V2 ax ay) (V2 bx by)) (Box (V2 cx cy) (V2 dx dy)) =
  Box (V2 (min ax cx) (min ay cy)) (V2 (max bx dx) (max by dy))

tshow :: (Show a) => a -> Text
tshow = T.pack . show
