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
-- "Senbazuru.Render.Svg" re-exports everything here, so a caller that only
-- writes SVG still imports one module.
--
-- == The scale is a consequence, not a setting
--
-- Nothing chooses how large a page draws its model. 'pageTransform' fits the
-- diagram's extent into the page inside its margin, and the scale is whatever
-- the tighter of the two axes allows ('fitBox' has the reasoning). So a caller
-- that needs the scale asks 'pageTransform' for it, rather than fitting the box
-- again with a copy of the arithmetic that could drift from the renderer's.
module Senbazuru.Diagram.Page
  ( Page (..),
    defaultPage,
    pageContentBox,
    pageTransform,
  )
where

import Data.Text (Text)
import Senbazuru.Diagram (Colour (..), Diagram (..))
import Senbazuru.Geometry (Box (..), Transform, V2 (..), fitBox)

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
