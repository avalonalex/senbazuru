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
--
-- A filled polygon has no distinguished first corner. Clipping can choose a
-- different cyclic start on macOS and Linux because their trigonometry differs
-- in the last bits. Closed fill paths choose the lexicographically smallest
-- rotation of their FORMATTED page coordinates. Comparing unrounded Doubles
-- would let invisible numerical noise choose different visible bytes again.
-- This preserves winding, subpath order and all geometry; open strokes and
-- arrows retain their meaningful endpoints.
--
-- == The page is not this module's
--
-- How big the canvas is, and how a diagram is fitted onto it, are
-- "Senbazuru.Diagram.Page"'s, because neither is about SVG and a page of
-- steps needs the page's scale before anything is written. This module
-- re-exports them, so a caller that writes SVG imports only this.
module Senbazuru.Render.Svg
  ( -- * Page setup, from "Senbazuru.Diagram.Page"
    Page (..),
    defaultPage,
    pageContentBox,
    pageTransform,

    -- * Rendering
    renderSvg,

    -- * Formatting internals, exposed for testing
    formatNumber,
    escapeXml,
  )
where

import Data.List (dropWhileEnd, foldl')
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Text.Lazy.Builder (Builder)
import Data.Text.Lazy.Builder qualified as TB
import Numeric (showFFloat)
import Senbazuru.Diagram
  ( ArrowHead (..),
    ArrowPath (..),
    Colour (..),
    Dash (..),
    Diagram (..),
    Shape (..),
    Stroke (..),
  )
import Senbazuru.Diagram.Page (Page (..), defaultPage, pageContentBox, pageTransform)
import Senbazuru.Geometry
  ( Transform,
    V2 (..),
    applyTransform,
    dot,
    movedBy,
    norm,
    normalize,
    perpendicular,
    (*^),
    (^+^),
    (^-^),
  )
import Senbazuru.Geometry.Polygon (signedArea)

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
    toPage = pageTransform page d

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

-- | One shape as an SVG element, or nothing at all if it has no extent to draw.
--
-- Most shapes become a @\<path\>@; a 'Label' becomes a @\<text\>@, whose content
-- has to be escaped because a label can carry a title straight out of a
-- user-supplied file.
--
-- The stroked kinds and the filled kinds each set the attribute the enclosing
-- group does not want: the group carries @fill=\"none\"@ so that stroked paths
-- are not flooded, and a filled polygon overrides it. Neither sets the other, so
-- a polygon is unstroked (SVG's initial @stroke@ is @none@, and the group does
-- not change it) and a polyline is unfilled.
--
-- An 'Arrow' is two elements rather than one: a solid head is filled and its
-- curve is stroked, and a hollow head is stroked without the dash the curve
-- may have, since a head drawn in dashes would not read as one.
--
-- An 'Offset' emits no element of its own. It moves the /transform/ rather than
-- the points, which is what makes its displacement a page-unit one: the shape
-- inside is projected exactly as it would have been and then slid, so nothing
-- inside it — a stroke width, an arrowhead, a type size — has any idea it moved.
shapeToSvg :: Transform -> Shape -> Builder
shapeToSvg toPage (Offset v s) = shapeToSvg (movedBy v toPage) s
-- Text is emitted as <text> rather than as outlines, so the file stays small and
-- the number stays selectable. The trade is that the exact shape depends on the
-- viewer's fonts: `sans-serif` is a generic family every renderer resolves to
-- something, and a golden file records the markup rather than the glyphs.
shapeToSvg toPage (Label (Colour c) size p txt) =
  "    <text"
    <> attrNum "x" x
    <> attrNum "y" y
    <> attrNum "font-size" size
    <> attr "font-family" "sans-serif"
    <> attr "fill" c
    <> ">"
    <> TB.fromText (escapeXml txt)
    <> "</text>\n"
  where
    V2 x y = applyTransform toPage p

-- The arrow is the one shape whose size is not entirely in model units: the
-- curve is, and the head is in page units. Both are in scope here and nowhere
-- else, which is why the head is built at this point rather than upstream.
shapeToSvg toPage (Arrow a) =
  curve <> head'
  where
    from = applyTransform toPage (arrowFrom a)
    via = applyTransform toPage (arrowVia a)
    tip = applyTransform toPage (arrowTo a)

    -- Along the curve's own tangent at the tip, not along the straight line
    -- from where it started: a head aimed down the chord sits visibly askew to
    -- the arc it terminates.
    along = fromMaybe (V2 1 0) (normalize (tip ^-^ via))
    across = perpendicular along

    -- Clamped against the arrow's own length on the page, which is the only
    -- place that length is known. A head is a fixed size in page units, and a
    -- short motion on a large sheet can be shorter than one: unclamped, the
    -- curve is pulled back past its own start and drawn backwards underneath a
    -- head that swallows it.
    headLength = min (arrowHeadLength a) (0.5 * norm (tip ^-^ from))
    base = tip ^-^ (headLength *^ along)
    half = 0.4 * headLength

    -- The barb of a one-sided head goes out on the side the arrow bows to,
    -- the outside of the curve. 'across' is square to the curve at the tip,
    -- and the control point lies on the tangent there, so the chord says
    -- which way along 'across' that side is. A straight arrow, its control
    -- point on the chord, has no outside, and the sign of a dot product that
    -- is zero but for rounding would put its barb on either side depending on
    -- where it sits; so it takes the side 'arrowFor' bows to, left of travel.
    -- Rounding leaves at most about 3e-13 of the chord's length here, and a
    -- bow of a thousandth of the chord already gives 4e-3.
    bowSide = if dot across (tip ^-^ from) > 1e-9 * norm (tip ^-^ from) then 1 else -1
    barb = base ^+^ ((bowSide * half) *^ across)

    curve =
      "    <path"
        <> attr "d" (quadratic from via base)
        <> attr "stroke" (colourText (strokeColour (arrowStroke a)))
        <> attrNum "stroke-width" (strokeWidth (arrowStroke a))
        <> dashAttr (strokeDash (arrowStroke a))
        <> "/>\n"

    head' = case arrowHead a of
      SolidHead ->
        "    <path"
          <> attr
            "d"
            ( pathData [tip, base ^+^ (half *^ across), base ^-^ (half *^ across)] <> " Z"
            )
          <> attr "fill" (colourText (strokeColour (arrowStroke a)))
          <> "/>\n"
      -- Half of the double head's outline, from the end of the curve, which
      -- stops at the base, through the tip and out to the barb: a barb drawn
      -- from the tip alone would leave the last head-length of the shaft
      -- undrawn.
      HollowHalfHead -> hollow (pathData [base, tip, barb] <> " Z")
      -- Closed, so its back edge runs across the end of the curve.
      HollowDoubleHead -> hollow (pathData [tip, base ^+^ (half *^ across), base ^-^ (half *^ across)] <> " Z")

    -- No fill attribute, so the group's fill="none" holds and the head stays
    -- open.
    hollow d =
      "    <path"
        <> attr "d" d
        <> attr "stroke" (colourText (strokeColour (arrowStroke a)))
        <> attrNum "stroke-width" hollowWidth
        <> "/>\n"

    -- A clamped hollow head is the full-size head scaled down, its outline
    -- with it. Stroked at the curve's width, the outline of a whole head
    -- under about 3.3 page units long, or of a half head under about 5.6,
    -- covers its own inside, and an unfold's head would read as a valley's
    -- solid one: the default theme's 11 and 1.8 on an arrow under about 6.6
    -- page units, which a step page draws.
    hollowWidth
      | headLength < arrowHeadLength a = strokeWidth (arrowStroke a) * headLength / arrowHeadLength a
      | otherwise = strokeWidth (arrowStroke a)
shapeToSvg toPage (Fill (Colour c) rings)
  -- Two points enclose no area, so a ring of them would paint nothing.
  -- 'frameFaces' rejects such a face outright; this guard is for diagrams built
  -- by hand.
  | null drawable = mempty
  | otherwise =
      "    <path"
        -- Every ring in one path, which is what keeps an area of one colour
        -- free of seams where its pieces meet. See "Senbazuru.Diagram".
        <> attr "d" (T.unwords (map (closedPathData . map (applyTransform toPage)) drawable))
        <> attr "fill" c
        <> "/>\n"
  where
    -- Turned the same way here rather than by whoever built the shape, because
    -- SVG adds overlapping subpaths up by the nonzero rule and two rings wound
    -- against each other would cut a hole in the paper. A 'Fill' means the
    -- union of its rings, so this is where that promise is kept -- and it has to
    -- be kept somewhere no producer can forget.
    drawable = map sameWayRound (filter ((>= 3) . length) rings)
    sameWayRound ring = if signedArea ring < 0 then reverse ring else ring
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

-- | A stroke's dash pattern, or nothing at all for a solid one.
dashAttr :: Dash -> Builder
dashAttr (Dash []) = mempty
dashAttr (Dash ds) = attr "stroke-dasharray" (T.unwords (map formatNumber ds))

-- | A quadratic Bézier: move to the first point, curve through the second to
-- the third.
quadratic :: V2 -> V2 -> V2 -> Text
quadratic a b c =
  T.concat ["M ", point a, " Q ", point b, " ", point c]
  where
    point (V2 x y) = formatNumber x <> " " <> formatNumber y

-- | An SVG path closed with @Z@, so the fill has a boundary all the way round.
closedPathData :: [V2] -> Text
closedPathData pts = case map point pts of
  [] -> " Z"
  first : rest ->
    let initial = first : rest
        ordered = foldl' min initial (rotations rest [first])
     in "M " <> T.intercalate " L " ordered <> " Z"
  where
    point (V2 x y) = formatNumber x <> " " <> formatNumber y
    -- Compare the whole rotation when rounded corners tie. Selecting only
    -- the smallest corner would still depend on the input's cyclic start.
    rotations [] _ = []
    rotations remaining@(next : rest) preceding =
      (remaining ++ reverse preceding) : rotations rest (next : preceding)

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
-- 'Senbazuru.Geometry.fitBox', and silently writing @NaN@ into an attribute
-- would produce an SVG that fails to render with no clue why.
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
-- a double-quoted attribute value, and replace with U+FFFD, the replacement
-- character, each character XML 1.0 cannot carry at all.
--
-- Titles and descriptions come straight out of user-supplied FOLD files, so an
-- unescaped @&@ in an author's name is enough to produce a malformed document.
--
-- Escaping is not enough for every character. XML 1.0 has no way to write the
-- control characters below U+0020 other than tab, newline and carriage
-- return, nor U+FFFE or U+FFFF ('xmlChar'), and a character reference does not
-- help, because @\&#7;@ must name a character the document could hold too. A
-- @frame_title@ can hold one, and so can a caption a fold sequence's source
-- writes with @\\u{7}@. A document holding one is not XML: a strict reader
-- refuses the whole page. Replacing the character keeps the rest of the text
-- and leaves a visible mark where it was, rather than dropping it unseen.
escapeXml :: Text -> Text
escapeXml = T.concatMap $ \case
  '&' -> "&amp;"
  '<' -> "&lt;"
  '>' -> "&gt;"
  '"' -> "&quot;"
  '\'' -> "&apos;"
  c
    | xmlChar c -> T.singleton c
    | otherwise -> "\xFFFD"

-- | Whether XML 1.0 can carry a character: its @Char@ production
-- (<https://www.w3.org/TR/xml/#charsets>), written as the specification
-- writes it. 'Text' cannot hold the surrogates it leaves out, U+D800 to
-- U+DFFF, so of its gaps only the controls and U+FFFE and U+FFFF can reach
-- 'escapeXml'.
xmlChar :: Char -> Bool
xmlChar c =
  c == '\x9'
    || c == '\xA'
    || c == '\xD'
    || ('\x20' <= c && c <= '\xD7FF')
    || ('\xE000' <= c && c <= '\xFFFD')
    || ('\x10000' <= c && c <= '\x10FFFF')
