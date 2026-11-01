-- |
-- Module      : Senbazuru.Diagram.Page
-- Description : The canvas a diagram is drawn on, and how a diagram is fitted onto it.
--
-- A 'Diagram' places its shapes in model units, whatever size the file
-- happened to use, and a page is in page units, the units its stroke widths,
-- type sizes and nudges are already given in ("Senbazuru.Diagram" has the
-- two-unit rule). This module is where the two meet: a 'Page' says how big
-- the canvas is, and 'pageTransform' says how a diagram's shapes are scaled
-- and moved onto it.
--
-- == Why a module of its own
--
-- Both used to live in the SVG writer, "Senbazuru.Render.Svg", and neither is
-- about SVG. A PDF or PNG backend would draw on the same page through the same
-- transform, and it should not have to import an SVG writer to find out how big
-- its page is. Nor is the page only a backend's business: a page of steps with
-- captions under its figures has to know the page's scale before there is
-- anything to write, because the captions are type, sized in page units, laid
-- out against figures sized in model units, and the scale is what converts one
-- into the other (PRDs\/06-prd-step-diagrams.md §8).
--
-- "Senbazuru.Render.Svg" re-exports the page and its transform, so a caller
-- that only writes SVG still imports one module.
--
-- == The scale is a consequence, not a setting
--
-- Nothing chooses how large a page draws its model. 'pageTransform' fits the
-- diagram's extent into the page inside its margin, and the scale is whatever
-- the tighter of the two axes allows ('fitBox' has the reasoning). So a caller
-- that needs the scale asks 'pageTransform' for it, rather than fitting the box
-- again with a copy of the arithmetic that could drift from the renderer's.
--
-- == Fitting a page whose figures have captions
--
-- Captions break that rule once, and have to. Under each row of captioned
-- figures lies a band of page units for its captions' lines
-- ("Senbazuru.Diagram.Layout", 'captionedRows'), and how many lines a caption
-- wraps to depends on how wide its figure is on the page, which is the scale.
-- So the scale decides the bands, and the bands, which take room from the
-- figures, decide the scale. 'fitPage' finds the two together, and asking
-- 'pageTransform' cannot do it: lay the page out at a scale, ask what scale
-- that layout gets, lay it out again at that one, and the answers close in on
-- the right one only geometrically, 42 rounds to settle to 1e-12 on a page S24
-- measured and not settled after 199 on a shorter one (PRDs\/decisions.md,
-- C134).
--
-- What does converge is to hold the bands still while solving for the scale,
-- since with the bands fixed the page is linear in it. A page @H@ tall, with
-- a margin @m@, has @H - 2m@ inside it; @R@ rows of figures @h@ model units
-- high, drawn at scale @s@, take @s R h@ of that, and the bands, being page
-- units, take their total @B@ whatever @s@ is. So the largest scale those
-- bands allow is @(H - 2m - B) / (R h)@, and the page's width allows no more
-- than its own scale, the content box's width over the figures'. Start at the
-- width's scale, where the captions wrap to the fewest lines; wrap them
-- again at the scale the bands allow; and stop when the bands' total no
-- longer grows. The figures are drawn once, before any of this: only the
-- captions are wrapped again.
--
-- __It stops, and at the largest scale that fits.__ A caption wrapped to a
-- narrower line needs no fewer lines, because breaking greedily, as
-- 'Senbazuru.Diagram.Layout.wrapCaption' does, gives the fewest lines a
-- width allows. So each round's scale is no larger than the last, and its
-- bands no smaller, and they can grow only so far: a caption has no more
-- lines than words. Every scale at which the page fits is at or below each
-- round's scale, by the same argument, so the one the rounds stop at is the
-- largest; and if a round's bands leave the figures no room, no scale fits at
-- all, and the page is refused, unless the figures have no height and need
-- none. The bands it is refused with are a lower bound: drawn smaller, the
-- captions wrap to more lines, so a page a little taller than they are can
-- still be refused. The stopping test is the one that guarantees the
-- page fits whichever way the wrap went: bands no taller than the ones the
-- scale was solved for leave the figures their room.
--
-- That is the width's ratio written out once more, which the paragraph above
-- says not to do. It is written out because the fit solves for the very
-- height 'pageTransform' takes as given; what the renderer then draws is still
-- 'pageTransform''s, and the tests hold the two to each other.
module Senbazuru.Diagram.Page
  ( Page (..),
    defaultPage,
    pageContentBox,
    pageTransform,

    -- * Fitting a page of captioned figures
    Height (..),
    FittedPage (..),
    PageFitError (..),
    fitPage,
  )
where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Senbazuru.Diagram (Colour (..), Diagram (..))
import Senbazuru.Diagram.Layout
  ( CaptionedRows (..),
    Grid,
    captionedRows,
    gridOf,
    gridOfCaptioned,
    hasCaptions,
    pageScale,
    pageScaleValue,
  )
import Senbazuru.Diagram.Style (Theme)
import Senbazuru.Explain (Explain (..), decimal, num)
import Senbazuru.Geometry (Box (..), Transform, V2 (..), boxSize, fitBox)

-- | The canvas the diagram is drawn onto. All values are in page units.
data Page = Page
  { pageWidth :: !Double,
    pageHeight :: !Double,
    -- | Blank border kept on all four sides. Diagrams that touch the edge of
    -- their frame look cramped, and crease patterns in particular have a heavy
    -- outline right at the boundary.
    pageMargin :: !Double,
    -- | 'Nothing' leaves the SVG transparent, which is what you want when
    -- embedding it in a page that has its own background.
    pageBackground :: !(Maybe Colour),
    -- | Emitted as @\<title\>@: the accessible name of the image.
    pageTitle :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

-- | A 400x400 canvas with a 16-unit margin and a white background.
defaultPage :: Page
defaultPage =
  Page
    { pageWidth = 400,
      pageHeight = 400,
      pageMargin = 16,
      pageBackground = Just (Colour "#ffffff"),
      pageTitle = Nothing
    }

-- | The region of the page the drawing may occupy, i.e. the page inset by its
-- margin.
pageContentBox :: Page -> Box
pageContentBox p =
  Box
    (V2 m m)
    (V2 (pageWidth p - m) (pageHeight p - m))
  where
    m = pageMargin p

-- | The transform 'Senbazuru.Render.Svg.renderSvg' draws a diagram on a page
-- with, from model units to page units: the diagram's extent fitted into the
-- page's content box ('fitBox'). Its scale is the size the page draws the
-- model at, in page units per model unit. A caller that needs that size asks
-- here rather than fitting the box again, so that its answer stays the
-- renderer's own if the renderer ever lays a page out differently.
pageTransform :: Page -> Diagram -> Transform
pageTransform page d = fitBox (diagramExtent d) (pageContentBox page)

-- | How tall a page of figures is, when some have captions.
data Height
  = -- | As tall as the 'Page' says. The figures are drawn as large as that
    -- leaves room for, with their captions under them: @run --height@.
    HeightAsGiven
  | -- | As tall as the rows need, with the figures as large as the page's
    -- width allows: @run@ with no @--height@. A page with no caption is as
    -- tall as the 'Page' says, so that it is the page @render --steps@ draws
    -- (PRDs\/04-prd-sequence-source-and-cli.md, R-04-27).
    HeightToFit
  deriving stock (Eq, Show)

-- | A page fitted to its figures, and the figures laid out for it. Draw the
-- one on the other: @renderSvg (fittedPage f) (fittedDiagram f)@.
data FittedPage = FittedPage
  { fittedPage :: !Page,
    fittedDiagram :: !Diagram
  }
  deriving stock (Eq, Show)

-- | Why a page of captioned figures could not be fitted, with the numbers
-- that say why, in page units.
data PageFitError
  = -- | The page has no width inside its margins: its width and margin.
    NoRoomAcross !Double !Double
  | -- | The figures together have no width, so their captions have nothing
    -- to be wrapped to.
    FiguresHaveNoWidth
  | -- | The page is too short for its captions at any scale: its height, its
    -- margin, and the bands' total at the round where no room was left for
    -- the figures. Drawn smaller, the captions only wrap to more lines, so
    -- that total is a lower bound, not the height a page needs.
    TooShortForCaptions !Double !Double !Double
  deriving stock (Eq, Show)

-- | The page's own numbers through 'decimal', since the reader typed them;
-- the bands' total through 'num', since it is measured.
instance Explain PageFitError where
  explain = \case
    NoRoomAcross width margin ->
      "a page "
        <> decimal width
        <> " wide, with a margin of "
        <> decimal margin
        <> " on each side, has no room across for its figures and their captions"
    FiguresHaveNoWidth -> "the figures have no width, so their captions have nothing to be wrapped to"
    TooShortForCaptions height margin bands ->
      "a page "
        <> decimal height
        <> " tall is too short for its captions: however small its figures are drawn, their captions wrap to bands at least "
        <> num bands
        <> " tall, and it has "
        <> decimal (height - 2 * margin)
        <> " inside its margins of "
        <> decimal margin

-- | Lay figures out on a page, with their captions under them, and fit the
-- page to them ('Height'); the module header has how.
--
-- A page none of whose captions has a word is 'gridOf''s, on the page as
-- given, whichever the height, so every page drawn without captions stays
-- what it was. 'Nothing' when there are no figures, as for 'gridOf'.
fitPage :: Theme -> Grid -> Height -> Page -> [(Diagram, Maybe Text)] -> Either PageFitError (Maybe FittedPage)
fitPage theme grid height page captioned = case gridOf grid (map fst captioned) of
  Nothing -> Right Nothing
  Just plain
    | hasCaptions captioned -> Just <$> fitted plain
    | otherwise -> Right (Just (FittedPage page plain))
  where
    margin = pageMargin page
    V2 across inside = boxSize (pageContentBox page)

    fitted plain = do
      widest <- widthScale plain
      case height of
        HeightToFit -> pure (asTallAsNeeded plain widest)
        HeightAsGiven -> FittedPage page . laidOut plain <$> settle widest

    -- The width's scale: the content box's width over the figures'. The
    -- captioned layout keeps the uncaptioned one's columns, so the figures
    -- are as wide at every scale.
    -- A width that is not a number fails the comparison, and is refused
    -- with the rest.
    widthScale plain
      | across > 0 = maybe (Left FiguresHaveNoWidth) Right (pageScale (across / figuresWide))
      | otherwise = Left (NoRoomAcross (pageWidth page) margin)
      where
        V2 figuresWide _ = boxSize (diagramExtent plain)

    -- As tall as the layout at the width's scale needs: its extent's height
    -- drawn at that scale, and the margins.
    asTallAsNeeded plain widest = FittedPage page {pageHeight = 2 * margin + pageScaleValue widest * tall} d
      where
        d = laidOut plain widest
        V2 _ tall = boxSize (diagramExtent d)

    -- Each round takes the bands at the scale reached so far, and the largest
    -- scale the room they leave allows, until the bands stop growing.
    settle widest = go widest
      where
        figures = maybe 0 rowsFigureHeight (rowsAt widest)
        go scale
          | leaves, bandsAt next <= bands = Right next
          | leaves = go next
          | otherwise = Left (TooShortForCaptions (pageHeight page) margin bands)
          where
            bands = bandsAt scale
            room = inside - bands
            -- Whether the bands leave the figures room. Figures with no
            -- height need none, so bands that exactly fill the page leave
            -- them enough. Room that is not a number fails both comparisons,
            -- and is refused with the rest.
            leaves = room > 0 || (room == 0 && figures <= 0)
            -- Figures with no height take no room, and leave the width to
            -- bind.
            next = case pageScale (room / figures) of
              Just allowed | figures > 0 -> min widest allowed
              _ -> widest

    rowsAt scale = captionedRows theme grid scale captioned

    -- The two fallbacks below are for a page with nothing to measure, which
    -- 'fitted' is never handed: it is called only for figures with captions.
    bandsAt scale = maybe 0 (sum . rowsBands) (rowsAt scale)
    laidOut plain scale = fromMaybe plain (gridOfCaptioned theme grid scale captioned)
