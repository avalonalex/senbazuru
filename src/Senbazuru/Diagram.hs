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
module Senbazuru.Diagram
  ( -- * Diagrams
    Diagram (..),
    diagram,
    diagramWithExtent,

    -- * Shapes
    Shape (..),
    ArrowPath (..),
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
-- name every place that had to handle it — which is how 'Polygon' was added to
-- 'Polyline', and 'Arrow' to both.
--
-- A 'Polygon' carries a fill and no stroke, which looks like an omission and is
-- not. A face and the creases bounding it are separate things in FOLD, and they
-- are separate things here: the outline of a filled face is drawn by the border
-- and crease edges that happen to run along it, each with the weight its own
-- assignment calls for. Stroking the polygon as well would double every line
-- and would draw the edge of the sheet at the wrong weight.
data Shape
  = -- | An open polyline through the given model-space points.
    Polyline !Stroke ![V2]
  | -- | A closed polygon, filled with the given colour and not stroked. The
    -- closing edge back to the first point is implied.
    Polygon !Colour ![V2]
  | -- | A curved arrow with a solid head.
    Arrow !ArrowPath
  deriving stock (Eq, Show)

-- | The model-space points a shape passes through.
shapePoints :: Shape -> [V2]
shapePoints = \case
  Polyline _ ps -> ps
  Polygon _ ps -> ps
  -- The control point is included even though the curve never reaches it: it is
  -- the far side of the bow, so a box that left it out could still clip the
  -- arc it produces.
  Arrow a -> [arrowFrom a, arrowVia a, arrowTo a]

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
