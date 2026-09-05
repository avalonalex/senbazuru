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
module Senbazuru.Diagram.Layout
  ( Grid (..),
    defaultGrid,
    gridOf,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Diagram
  ( Colour,
    Diagram (..),
    Shape (..),
    diagramWithExtent,
    mapShapePoints,
  )
import Senbazuru.Geometry (Box (..), V2 (..), boxSize, (*^), (^+^), (^-^))

-- | How to arrange the figures.
data Grid = Grid
  { -- | Figures across the page before wrapping to a new row.
    gridColumns :: !Int,
    -- | The gap between figures, as a fraction of a figure's own width. A
    -- fraction rather than a length because the figures are laid out in model
    -- units, whose size is whatever the file happened to use.
    gridGutter :: !Double,
    -- | Colour and page-unit size for the step numbers, or 'Nothing' to leave
    -- the figures unnumbered.
    gridNumbering :: !(Maybe (Colour, Double))
  }
  deriving stock (Eq, Show)

-- | Three across, a tenth of a figure between them, numbered.
defaultGrid :: Colour -> Grid
defaultGrid ink =
  Grid
    { gridColumns = 3,
      gridGutter = 0.1,
      gridNumbering = Just (ink, 14)
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
  (e : es) -> Just (diagramWithExtent (page (foldr unionBox e es)) (shapes (foldr unionBox e es)))
  where
    columns = max 1 (gridColumns grid)
    count = length figures
    rows = (count + columns - 1) `div` columns
    used = min columns count

    -- A band above each figure for its number. In model units, because that is
    -- what the layout is done in, while the glyphs are sized in page units --
    -- so the two agree at ordinary scales and drift at extreme ones. A real
    -- fix wants the backend to reserve page-space rows, which is more machinery
    -- than a numbered grid has yet earned.
    bandOf h = case gridNumbering grid of
      Nothing -> 0
      Just _ -> 0.15 * h

    strideOf shared = V2 (w * (1 + gridGutter grid)) ((h + band) * (1 + gridGutter grid))
      where
        V2 w h = boxSize shared
        band = bandOf h

    -- Rows run down the page, so later rows sit at smaller y: model space has y
    -- increasing upwards and a reader goes the other way.
    offsetOf shared i = V2 (fromIntegral (i `mod` columns) * dx) (negate (fromIntegral (i `div` columns)) * dy)
      where
        V2 dx dy = strideOf shared

    -- Each figure is centred in its cell, and only the /scale/ is shared.
    -- Keeping each drawing at the absolute position its coordinates give would
    -- be defensible -- the paper really does end up in one half of where the
    -- sheet was -- but across separate figures it reads as a drawing that has
    -- slipped, and it drifts away from the number beside it. Books centre.
    centred shared d = 0.5 *^ (centreOf shared ^-^ centreOf (diagramExtent d))
      where
        centreOf (Box lo hi) = lo ^+^ hi

    shapes shared =
      concat (zipWith placed [0 ..] figures)
      where
        placed i d =
          map (mapShapePoints (^+^ shift i d)) (diagramShapes d) <> number i d (shift i d)

        shift i d = offsetOf shared i ^+^ centred shared d

        -- Above the figure's own top-left corner, not the cell's. A folded step
        -- occupies a fraction of the cell, and a number pinned to the cell
        -- drifts further from its figure the smaller that figure gets -- which
        -- is exactly the steps a reader most needs the number for.
        number i d moved = case gridNumbering grid of
          Nothing -> []
          Just (colour, size) ->
            [Label colour size (V2 left (top + 0.25 * bandOf h) ^+^ moved) (tshow (i + 1))]
          where
            Box (V2 left _) (V2 _ top) = diagramExtent d
            V2 _ h = boxSize shared

    -- The page is the grid's own bounding box: the columns actually used and
    -- the rows actually needed, with no trailing gutter on either side.
    page shared =
      Box
        (V2 x0 (y0 + h + band - (fromIntegral rows - 1) * dy - (h + band)))
        (V2 (x0 + (fromIntegral used - 1) * dx + w) (y0 + h + band))
      where
        Box (V2 x0 y0) _ = shared
        V2 w h = boxSize shared
        band = bandOf h
        V2 dx dy = strideOf shared

unionBox :: Box -> Box -> Box
unionBox (Box (V2 ax ay) (V2 bx by)) (Box (V2 cx cy) (V2 dx dy)) =
  Box (V2 (min ax cx) (min ay cy)) (V2 (max bx dx) (max by dy))

tshow :: (Show a) => a -> Text
tshow = T.pack . show
