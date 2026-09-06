-- |
-- Module      : Senbazuru.Diagram
-- Description : A backend-independent description of what to draw.
--
-- == Why there is a layer here at all
--
-- The obvious design is to walk a FOLD frame and emit SVG strings as you go.
-- This module exists to refuse that, for three reasons:
--
-- 1. __Testability.__ Asserting \"the diagonal is drawn as a dashed line\" is a
--    statement about a 'Shape'. Against raw SVG it becomes a string match on
--    generated markup, which breaks whenever attribute order changes.
--
-- 2. __One place for style.__ Every decision about how origami diagrams look
--    lands in "Senbazuru.Diagram.Style" instead of being sprinkled through
--    string concatenation.
--
-- 3. __Other backends.__ PDF, or a raster preview, becomes another consumer of
--    'Diagram' rather than a second copy of the FOLD-walking logic.
--
-- == The two-unit rule
--
-- This is the one thing to keep straight while reading the module:
--
-- * 'Shape' /coordinates/ are in __model units__ — whatever the FOLD file
--   used. They get scaled to the page later.
--
-- * 'Stroke' /widths and dash lengths/ are in __page units__ (SVG user units,
--   effectively points) and are __not__ scaled.
--
-- That split is intentional. A crease line in a printed book is about 0.5pt
-- wide whether the paper square is 1 unit or 400 units across, so line weight
-- must not depend on the model's choice of scale. Keeping widths in page units
-- from the start avoids the alternative, which is dividing by the viewport
-- scale at emit time and getting it wrong.
--
-- 'Offset' is the one thing here that is a /position/ in page units, and it is
-- a wrapper rather than a coordinate for exactly that reason: the shape inside
-- keeps its model coordinates, and the nudge is added after they have been
-- scaled.
module Senbazuru.Diagram
  ( -- * Diagrams
    Diagram (..),
    diagram,
    diagramWithExtent,

    -- * Shapes
    Shape (..),
    ArrowPath (..),
    mapShapePoints,
    shapePoints,
    shapesBounds,

    -- * Stroke styling
    Stroke (..),
    Colour (..),
    Dash (..),
    solid,
  )
where

import Data.Text (Text)
import Senbazuru.Geometry (Box, V2, boxFromPoints)

-- | A stroke colour, as whatever string the backend understands.
--
-- Deliberately dumb for now: @\"#1a1a1a\"@ passes straight through to SVG. A
-- real colour type earns its place when a second backend needs one.
newtype Colour = Colour {colourText :: Text}
  deriving stock (Eq, Show)

-- | A dash pattern in __page units__: alternating on- and off- lengths, in the
-- same sense as SVG's @stroke-dasharray@. The empty list means a solid line.
newtype Dash = Dash {dashPattern :: [Double]}
  deriving stock (Eq, Show)

-- | How a line is drawn.
data Stroke = Stroke
  { strokeColour :: !Colour,
    -- | Page units. See the two-unit rule in the module header.
    strokeWidth :: !Double,
    strokeDash :: !Dash
  }
  deriving stock (Eq, Show)

-- | A solid stroke of the given colour and width.
solid :: Colour -> Double -> Stroke
solid c w = Stroke c w (Dash [])

-- | A curved arrow, as an origami book draws a fold.
--
-- Straight in the plane it is drawn on, and bowed, because the paper it stands
-- for swings through the air rather than sliding across the page. The path is a
-- quadratic Bézier: from 'arrowFrom', bent towards 'arrowVia', ending at
-- 'arrowTo' where the head sits.
--
-- __The head's size is in page units and its position is in model units__,
-- which is the two-unit rule of this module meeting a shape that needs both. An
-- arrowhead measured in model units would be a speck on a sheet four hundred
-- units across and would swallow one a single unit across; it has to be the
-- same size on the page whatever the drawing is of. So the backend is handed
-- the length and builds the head after projecting, which is the only place both
-- units are in scope at once.
data ArrowPath = ArrowPath
  { arrowStroke :: !Stroke,
    arrowFrom :: !V2,
    arrowVia :: !V2,
    arrowTo :: !V2,
    -- | Page units: how long the head is from tip to base.
    arrowHead :: !Double
  }
  deriving stock (Eq, Show)

-- | A drawable primitive.
--
-- Each was added by writing the constructor and letting @-Wincomplete-patterns@
-- name every place that had to handle it — which is how 'Fill' was added to
-- 'Polyline', and 'Arrow' to both.
--
-- A 'Fill' carries a colour and no stroke, which looks like an omission and is
-- not. A face and the creases bounding it are separate things in FOLD, and they
-- are separate things here: the outline of a filled area is drawn by the border
-- and crease edges that happen to run along it, each with the weight its own
-- assignment calls for. Stroking the fill as well would double every line and
-- would draw the edge of the sheet at the wrong weight.
--
-- == Why a 'Fill' holds several rings
--
-- Because an area of one colour has to be painted in one go. Two shapes of the
-- same colour that share an edge do /not/ add up to the shape they cover: each
-- is antialiased against what is behind it, so the shared edge comes out as a
-- pale seam. Measured on a square split into two triangles by its diagonal, the
-- pixels along the diagonal come out @#d6cab3@ where the whole square gives
-- @#c8b89a@. As one path with two subpaths they are identical to the whole
-- square, because the rasteriser works out the coverage of the path rather than
-- of each piece.
--
-- That matters here because paper arrives in pieces. The visible part of a face
-- in a folded model comes back as several convex pieces with nothing drawn
-- between them, and there the seams would be the whole picture. A crease pattern
-- is one sheet cut into faces that abut along every crease, and there the seam
-- usually hides under the crease drawn along it — but not under a @J@ edge,
-- which is not drawn at all, and not where a theme suppresses a flat crease.
-- Either way they are one area of one colour, and drawing them as one is both
-- cheaper and what they are.
--
-- A 'Fill' is the __union__ of its rings, whichever way round each is written.
-- Winding carries meaning elsewhere in senbazuru — it is how a folded face says
-- which side of the paper is up — and it deliberately carries none here, so
-- that a fill built from faces a file wound backwards cannot come out with
-- holes in it. A backend that adds up rings by the nonzero rule has to turn
-- them all the same way first; "Senbazuru.Render.Svg" does.
data Shape
  = -- | An open polyline through the given model-space points.
    Polyline !Stroke ![V2]
  | -- | An area filled with the given colour and not stroked, given as closed
    -- rings. The closing edge back to each ring's first point is implied.
    Fill !Colour ![[V2]]
  | -- | A curved arrow with a solid head.
    Arrow !ArrowPath
  | -- | A line of text: colour, size in __page units__, the model-space point
    -- its baseline starts at, and the text itself.
    --
    -- The second shape whose size and position are in different units, after
    -- 'ArrowPath'. A step number four hundred model units tall would be
    -- unreadable on one drawing and would fill the page on another; what it
    -- has to be is the same height in print whatever the model measures.
    Label !Colour !Double !V2 !Text
  | -- | A shape nudged across the page, by a displacement in __page units and
    -- page axes__ — so @y@ grows /downwards/, as it does in the finished
    -- document and as it does nowhere else in this module.
    --
    -- The third shape to need both units, after 'ArrowPath' and 'Label', and
    -- the first whose page-unit part is a position. It exists for the offset
    -- view of a flat-folded model, where layers that lie exactly on top of one
    -- another are drawn a few points apart so that the stack reads as a stack.
    -- How far apart is a decision about the drawing and not about the paper —
    -- four points is four points whether the sheet is one unit across or four
    -- hundred — so it cannot be a model-space displacement, and the model's own
    -- coordinates are not touched.
    --
    -- Two consequences follow from that, and both are wanted. The nudge does
    -- not enter 'shapePoints', so a diagram's extent is the paper's and the page
    -- does not rescale because layers were stepped apart. And 'mapShapePoints'
    -- passes straight through it, so laying figures out on a grid shifts the
    -- shape inside and leaves the nudge alone, exactly as it leaves a stroke
    -- width alone.
    Offset !V2 !Shape
  deriving stock (Eq, Show)

-- | The model-space points a shape passes through.
shapePoints :: Shape -> [V2]
shapePoints = \case
  Polyline _ ps -> ps
  Fill _ rings -> concat rings
  Label _ _ p _ -> [p]
  -- The control point is included even though the curve never reaches it: it is
  -- the far side of the bow, so a box that left it out could still clip the
  -- arc it produces.
  Arrow a -> [arrowFrom a, arrowVia a, arrowTo a]
  -- The nudge is deliberately not accounted for. It is in page units, and these
  -- points are in model units, so there is nothing to add it to -- and a page
  -- that grew to admit it would rescale the whole drawing because two layers
  -- were stepped apart.
  Offset _ s -> shapePoints s

-- | Move every model-space point of a shape.
--
-- Only the points move: a stroke width, an arrowhead and a label's size are all
-- in page units and mean the same thing wherever the shape ends up. That is the
-- whole reason laying several drawings out on one page can be done by shifting
-- their coordinates — nothing about how they are inked has to be recomputed.
mapShapePoints :: (V2 -> V2) -> Shape -> Shape
mapShapePoints f = \case
  Polyline s ps -> Polyline s (map f ps)
  Fill c rings -> Fill c (map (map f) rings)
  Label c size p txt -> Label c size (f p) txt
  Arrow a ->
    Arrow
      a
        { arrowFrom = f (arrowFrom a),
          arrowVia = f (arrowVia a),
          arrowTo = f (arrowTo a)
        }
  Offset v s -> Offset v (mapShapePoints f s)

-- | The tightest box containing every point of every shape, or 'Nothing' if
-- there is nothing to draw.
shapesBounds :: [Shape] -> Maybe Box
shapesBounds = boxFromPoints . concatMap shapePoints

-- | A complete drawing, ready to hand to a backend.
data Diagram = Diagram
  { -- | The model-space region the page should show.
    --
    -- Stored rather than recomputed from 'diagramShapes' on purpose. In a
    -- step-by-step sequence every step must be drawn at the /same/ scale, or the
    -- model appears to grow and shrink from figure to figure. Pinning the extent
    -- to the sheet of paper — not to whatever happens to be drawn in this
    -- particular step — is what keeps the sequence steady.
    diagramExtent :: !Box,
    diagramShapes :: ![Shape]
  }
  deriving stock (Eq, Show)

-- | Build a diagram whose extent is the bounding box of its own contents.
--
-- 'Nothing' when there is nothing to draw, since an empty drawing has no
-- meaningful extent.
diagram :: [Shape] -> Maybe Diagram
diagram shapes = (`Diagram` shapes) <$> shapesBounds shapes

-- | Build a diagram with an explicitly chosen extent. Shapes may fall outside
-- it; the backend decides whether to clip.
diagramWithExtent :: Box -> [Shape] -> Diagram
diagramWithExtent = Diagram
