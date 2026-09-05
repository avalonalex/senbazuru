-- |
-- Module      : Senbazuru.Render.Svg
-- Description : Writing a 'Diagram' out as SVG text.
--
-- == Why hand-rolled instead of an SVG library
--
-- The output needed here is a fixed, small shape: a header, an optional
-- background, and a list of stroked paths. Against that, an XML combinator
-- library mostly buys indirection, and it takes away the thing that matters
-- most for testing — exact, predictable bytes. Roughly a hundred lines of
-- 'Builder' code gives full control over attribute order and number
-- formatting, which is what makes golden tests meaningful rather than brittle.
-- If the output ever grows to need real XML (namespaces, embedded content), a
-- library can be swapped in behind 'renderSvg' without touching any caller.
--
-- == Why the geometry is transformed in Haskell
--
-- SVG could do the model-to-page mapping itself, with
-- @\<g transform=\"scale(...)\"\>@. We do not use that, because an SVG
-- transform scales /stroke widths/ along with coordinates: a model 400 units
-- across and one 1 unit across would come out with wildly different line
-- weights. Doing the arithmetic in "Senbazuru.Geometry" instead keeps line
-- weight independent of the model's scale, and keeps the mapping in code that
-- can be property-tested rather than buried in an attribute string.
module Senbazuru.Render.Svg
  ( -- * Page setup
    Page (..),
    defaultPage,
    pageContentBox,

    -- * Rendering
    renderSvg,

    -- * Formatting internals, exposed for testing
    formatNumber,
    escapeXml,
  )
where

import Data.List (dropWhileEnd)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Builder (Builder)
import Data.Text.Lazy.Builder qualified as TB
import Numeric (showFFloat)
import Senbazuru.Diagram
  ( Colour (..),
    Dash (..),
    Diagram (..),
    Shape (..),
    Stroke (..),
  )
import Senbazuru.Geometry (Box (..), Transform, V2 (..), applyTransform, fitBox)

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

-- | Render a diagram as a standalone SVG document.
renderSvg :: Page -> Diagram -> Text
renderSvg page d =
  TL.toStrict . TB.toLazyText $
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
      <> "<svg xmlns=\"http://www.w3.org/2000/svg\""
      <> attrNum "width" (pageWidth page)
      <> attrNum "height" (pageHeight page)
      <> attr
        "viewBox"
        ( T.unwords
            ["0", "0", formatNumber (pageWidth page), formatNumber (pageHeight page)]
        )
      <> ">\n"
      <> title
      <> background
      -- Stroke properties shared by every path are hoisted onto one group, so
      -- individual paths only carry what actually differs between them.
      <> "  <g fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\">\n"
      <> foldMap (shapeToSvg toPage) (diagramShapes d)
      <> "  </g>\n"
      <> "</svg>\n"
  where
    toPage :: Transform
    toPage = fitBox (diagramExtent d) (pageContentBox page)

    title = case pageTitle page of
      Nothing -> mempty
      Just t -> "  <title>" <> TB.fromText (escapeXml t) <> "</title>\n"

    background = case pageBackground page of
      Nothing -> mempty
      Just (Colour c) ->
        "  <rect x=\"0\" y=\"0\""
          <> attrNum "width" (pageWidth page)
          <> attrNum "height" (pageHeight page)
          <> attr "fill" c
          <> "/>\n"

-- | One shape as a @\<path\>@ element, or nothing at all if it has no
-- extent to draw.
--
-- Both kinds set the attribute the enclosing group does not want: the group
-- carries @fill=\"none\"@ so that stroked paths are not flooded, and a filled
-- polygon overrides it. Neither kind sets the other attribute, so a polygon is
-- unstroked (SVG's initial @stroke@ is @none@, and the group does not change
-- it) and a polyline is unfilled.
shapeToSvg :: Transform -> Shape -> Builder
shapeToSvg toPage (Polygon (Colour c) pts)
  -- Two points enclose no area, so a fill would paint nothing. 'frameFaces'
  -- rejects such a face outright; this guard is for diagrams built by hand.
  | length pts < 3 = mempty
  | otherwise =
      "    <path"
        <> attr "d" (closedPathData (map (applyTransform toPage) pts))
        <> attr "fill" c
        <> "/>\n"
shapeToSvg toPage (Polyline stroke pts)
  -- A polyline of fewer than two points has no length. Emitting it would
  -- produce a stray dot under a round line cap.
  | length pts < 2 = mempty
  | otherwise =
      "    <path"
        <> attr "d" (pathData (map (applyTransform toPage) pts))
        <> attr "stroke" (colourText (strokeColour stroke))
        <> attrNum "stroke-width" (strokeWidth stroke)
        <> dashAttr (strokeDash stroke)
        <> "/>\n"
  where
    dashAttr (Dash []) = mempty
    dashAttr (Dash ds) = attr "stroke-dasharray" (T.unwords (map formatNumber ds))

-- | An SVG path closed with @Z@, so the fill has a boundary all the way round.
closedPathData :: [V2] -> Text
closedPathData pts = pathData pts <> " Z"

-- | An SVG path: move to the first point, then draw straight lines to the rest.
pathData :: [V2] -> Text
pathData [] = ""
pathData (p : ps) = T.concat ("M " : point p : concatMap segment ps)
  where
    segment q = [" L ", point q]
    point (V2 x y) = formatNumber x <> " " <> formatNumber y

attr :: Text -> Text -> Builder
attr k v =
  " " <> TB.fromText k <> "=\"" <> TB.fromText (escapeXml v) <> "\""

attrNum :: Text -> Double -> Builder
attrNum k = attr k . formatNumber

-- | Format a number for SVG output.
--
-- Golden tests compare generated files byte for byte, so this has to be
-- completely deterministic. Three properties are needed and none of them come
-- free from 'show':
--
-- * __Fixed precision, never scientific notation.__ @show (0.0001 :: Double)@
--   gives @\"1.0e-4\"@, which SVG does accept but which makes output depend on
--   the magnitude of the value.
--
-- * __No trailing zeros.__ Purely cosmetic, but it roughly halves the size of
--   a large path and makes diffs between golden files readable.
--
-- * __No negative zero.__ @-0.0@ and @0.0@ are distinct 'Double' values that
--   compare equal, so a y-flip can turn a coordinate into @\"-0\"@ in one run
--   and @\"0\"@ in the next, depending on which side of the axis it started.
--   Normalising here removes a genuinely confusing source of golden churn.
--
-- Non-finite values collapse to @0@: they cannot appear given the guards in
-- 'fitBox', and silently writing @NaN@ into an attribute would produce an SVG
-- that fails to render with no clue why.
formatNumber :: Double -> Text
formatNumber x
  | isNaN x || isInfinite x = "0"
  | otherwise = T.pack (normalise (showFFloat (Just decimals) x ""))
  where
    decimals = 3

    normalise s = case trimTrailingZeros s of
      "-0" -> "0"
      trimmed -> trimmed

    trimTrailingZeros s
      | '.' `elem` s = dropWhileEnd (== '.') (dropWhileEnd (== '0') s)
      | otherwise = s

-- | Escape the five characters that cannot appear literally in XML text or in
-- a double-quoted attribute value.
--
-- Titles and descriptions come straight out of user-supplied FOLD files, so an
-- unescaped @&@ in an author's name is enough to produce a malformed document.
escapeXml :: Text -> Text
escapeXml = T.concatMap $ \case
  '&' -> "&amp;"
  '<' -> "&lt;"
  '>' -> "&gt;"
  '"' -> "&quot;"
  '\'' -> "&apos;"
  c -> T.singleton c
