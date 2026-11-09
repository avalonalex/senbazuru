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
-- 'Offset' and 'Fanned' are the two things here that hold a /position/ in page
-- units, and neither is a coordinate, for exactly that reason. An 'Offset'
-- wraps a shape that keeps its model coordinates, and a 'Fanned' shape pairs
-- each model point with its own page-unit displacement; either way the nudge
-- is added after the model coordinates have been scaled.
--
-- 'Arrow', 'Label' and 'Symbol' need both units too: an arrow's curve is in
-- model units and its head's size in page units, a label is a model-space
-- point with a page-unit type size, and a symbol is a page-unit mark at one
-- model-space point. All five are finished by the backend /after/ projection,
-- which is the only place both units are in scope. That is what
-- lets "Senbazuru.Diagram.Layout" combine figures by shifting their
-- coordinates without recomputing how anything is inked.
module Senbazuru.Diagram
  ( -- * Diagrams
    Diagram (..),
    diagram,
    diagramWithExtent,

    -- * Shapes
    Shape (..),
    ArrowPath (..),
    ArrowHead (..),
    Glyph (..),
    glyphReach,
    repeatTypeSize,
    repeatText,
    Fan (..),
    FanPoint (..),
    fanPoints,
    mapShapePoints,
    shapePoints,
    shapesBounds,

    -- * Stroke styling
    Stroke (..),
    Colour (..),
    colourComponents,
    Dash (..),
    solid,
  )
where

import Data.Char (digitToInt, isHexDigit)
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Geometry (Box, V2 (..), boxFromPoints)

-- | A stroke colour, as whatever string the backend understands.
--
-- Deliberately dumb for now: @\"#1a1a1a\"@ passes straight through to SVG. A
-- real colour type earns its place when a second backend needs one.
newtype Colour = Colour {colourText :: Text}
  deriving stock (Eq, Show)

-- | The red, green and blue of a colour, each from 0 to 1, or 'Nothing' for a
-- colour that is not six hex digits.
--
-- The one thing anybody has needed to know about a colour besides its text:
-- a 3D file wants numbers rather than a CSS string. They come back in the
-- space the hex digits are written in, which is sRGB — the gamma-encoded
-- space every @#rrggbb@ on the web is in — and a consumer that wants linear
-- light, as glTF does, has to undo the encoding itself. That transfer is the
-- consumer\'s convention, not the colour\'s, so it does not live here.
colourComponents :: Colour -> Maybe (Double, Double, Double)
colourComponents (Colour t) = case T.unpack t of
  ['#', r1, r2, g1, g2, b1, b2] ->
    (,,) <$> channel r1 r2 <*> channel g1 g2 <*> channel b1 b2
  _ -> Nothing
  where
    channel hi lo = do
      h <- hex hi
      l <- hex lo
      pure (fromIntegral (16 * h + l) / 255)
    hex c
      | isHexDigit c = Just (digitToInt c)
      | otherwise = Nothing

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
    -- | Which head the arrow ends in.
    arrowHead :: !ArrowHead,
    -- | Page units: how long the head is from tip to base.
    arrowHeadLength :: !Double
  }
  deriving stock (Eq, Show)

-- | The three heads an origami book puts on a fold arrow, which tell the reader
-- what kind of fold it is: a solid head for a valley fold, a hollow head with
-- one barb for a mountain fold, and a hollow head with two for unfolding.
--
-- A head, not a kind of fold, because this module knows nothing about folding:
-- which kind of fold gets which head is "Senbazuru.Diagram.Style"'s
-- @withKind@, and a valley fold seen from behind the paper is a mountain fold,
-- which only the renderer, knowing which side it is looking at, can say.
data ArrowHead
  = -- | A filled triangle.
    SolidHead
  | -- | The outline of half a head: the end of the curve, the tip, and one
    -- barb on the side the arrow bows to, the outside of the curve, or, for
    -- a straight arrow, on its left.
    HollowHalfHead
  | -- | The outline of a whole head, its back edge across the end of the
    -- curve.
    HollowDoubleHead
  deriving stock (Eq, Show, Enum, Bounded)

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
  | -- | A curved arrow, ending in the head its path names.
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
  | -- | A mark of a fixed size on the page at one model-space point: its
    -- stroke, its size in __page units__, the point, and which mark.
    --
    -- The fourth shape to need both units, and the one whose page-unit part
    -- is its whole geometry. A turn-over loop sized to the model would change
    -- its printed size with the number of columns a page has; what it has to
    -- be is the same size in print whatever the model measures, so only the
    -- point it stands at is the model's.
    Symbol !Stroke !Double !V2 !Glyph
  | -- | A polyline or a fill whose every point moves across the page by a
    -- displacement of its own, in __page units and page axes__ as an
    -- 'Offset''s is, so @y@ grows downwards.
    --
    -- The fifth shape to need both units, and the second whose page-unit part
    -- is a position. It exists for a fanned figure (docs\/glossary.md, and
    -- PRDs\/06-prd-step-diagrams.md §10), where each corner
    -- of the paper is drawn toward the lower left by an amount that depends on
    -- how many sheets lie over it there: two corners of one face can move by
    -- different amounts, so no one 'Offset' around the face can say it.
    --
    -- Each point carries its displacement, rather than the shape carrying a
    -- list of displacements beside its list of points, so that nothing which
    -- drops a point or turns a ring round can leave the two out of step. A
    -- 'Fanned' shape whose every displacement is @d@ draws exactly what
    -- @'Offset' d@ around the same polyline or fill draws, byte for byte.
    --
    -- The displacements stay out of 'shapePoints' and are left alone by
    -- 'mapShapePoints', for the reasons an 'Offset''s nudge is.
    Fanned !Fan
  deriving stock (Eq, Show)

-- | What a 'Fanned' shape draws: a polyline, or a fill of closed rings, each
-- point with its own displacement. The two shapes a fanned figure is made of,
-- its paper and its lines, and so the two that are worth moving point by point.
data Fan
  = -- | An open polyline, as 'Polyline'.
    FanLine !Stroke ![FanPoint]
  | -- | An area of one colour, as 'Fill': the union of its rings, whichever
    -- way round each is written where it lies in the model.
    --
    -- With one exception the backend does not mend. Which way a ring runs is
    -- judged where it lies, not where it is drawn, so a ring its displacements
    -- turn round on the page, a face drawn inside out, stays turned, and cuts a
    -- hole where it overlaps another ring. Whoever fans a figure has to keep
    -- such a face off the page; "Senbazuru.Render.Svg"'s @runsClockwise@ says
    -- why the backend does not.
    FanFill !Colour ![[FanPoint]]
  deriving stock (Eq, Show)

-- | A model-space point and how far across the page it is drawn from where it
-- lies.
data FanPoint = FanPoint
  { -- | Where the point is, in __model units__.
    fanAt :: !V2,
    -- | How far it is moved once on the page, in __page units and page axes__.
    fanBy :: !V2
  }
  deriving stock (Eq, Show)

-- | Every point a 'Fan' passes through, with its displacement, ring after ring.
fanPoints :: Fan -> [FanPoint]
fanPoints = \case
  FanLine _ ps -> ps
  FanFill _ rings -> concat rings

-- | The marks a 'Symbol' draws.
data Glyph
  = -- | The loop that says \"turn the model over\": an arrow whose stem
    -- crosses the turn's axis at the symbol's point, loops once, and goes on
    -- across. The vector is the axis's direction as the page shows it, in
    -- model axes, so @y@ up; only its direction counts, and the loop rises on
    -- the side it points to. Whoever places the loop points that side into
    -- its figure, so the loop never lies across a neighbour.
    TurnOverLoop !V2
  | -- | An eye, centred on the symbol's point and as wide as its size: the
    -- mark that says \"this figure is seen edge on\". Looking along the
    -- paper's plane, a page cannot show which side of the sheet faces the
    -- reader, so it draws each fold's kind as the move was written rather
    -- than as seen, and marks every figure so a reader knows
    -- ("Senbazuru.Render.Steps"). Symmetric, so it has no direction to turn.
    EdgeOnMark
  | -- | The mark that says \"turn the model round on the table\": seven
    -- eighths of a circle with an arrowhead in the turning sense, and the
    -- amount inside, as written, in eighths of a turn (@3/8@). The number is
    -- signed eighths as the page shows the turn: positive anticlockwise, in
    -- model axes, so a page that turns the drawing round keeps its sense.
    -- Whoever places it has already flipped the sign for a page seen from
    -- the paper's other side. One that is not 1 to 7 eighths either way is
    -- no turn a run makes, and draws nothing.
    RotateMark !Int
  | -- | The mark that says \"repeat these figures' steps\": a box holding the
    -- range of figure numbers, "1–2", or the one number when the two
    -- are equal. Its width grows with its digits ('glyphReach').
    RepeatMark !Int !Int
  | -- | A filled dot as wide as its size, centred on its point: where a
    -- marked point of the paper lies, its name beside it as a 'Label'
    -- ("Senbazuru.Render.Steps").
    PointDot
  deriving stock (Eq, Show)

-- | How far a glyph of the given size reaches from its point, across and up
-- or down, in __page units__: half its width and half its height.
--
-- Every glyph but the repeat mark fits in a square as wide as its size. The
-- repeat mark's box is as wide as its words, estimated at 0.55 of its type
-- size a character, as captions are ("Senbazuru.Diagram.Layout"), so a range
-- of two-digit figures is wider than one of single digits. One function for
-- this, used by the backend to draw the box and by the layout to leave room
-- for it, so the two cannot disagree about how wide a mark is.
glyphReach :: Double -> Glyph -> V2
glyphReach size = \case
  RepeatMark from to -> V2 (0.5 * (0.55 * typeSize * fromIntegral (T.length (repeatText from to)) + 2 * pad)) (0.5 * 1.45 * typeSize)
  _ -> V2 (0.5 * size) (0.5 * size)
  where
    typeSize = repeatTypeSize size
    pad = 0.3 * typeSize

-- | The type size of a repeat mark's words, for a mark of the given size:
-- seven twelfths of it, so 14 page units, the step number's size, at the
-- theme's 24.
repeatTypeSize :: Double -> Double
repeatTypeSize size = 7 / 12 * size

-- | A repeat mark's words: the range with an en dash between, or the one
-- figure number when the range is one figure.
repeatText :: Int -> Int -> Text
repeatText from to
  | from == to = T.pack (show from)
  | otherwise = T.pack (show from) <> "\x2013" <> T.pack (show to)

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
  -- The point alone: the mark around it is in page units, as an Offset's
  -- nudge is, and a page that grew to admit it would rescale the drawing.
  Symbol _ _ p _ -> [p]
  -- The points without their displacements, as an Offset's shape without its
  -- nudge.
  Fanned fan -> map fanAt (fanPoints fan)

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
  -- The point moves, and a turn-over loop's axis does not, which is right only
  -- because the one caller, laying figures out on a page, only shifts them; a
  -- caller that turned a figure would have to turn the axis too.
  Symbol s size p glyph -> Symbol s size (f p) glyph
  -- Each point moves and keeps its own displacement, as an Offset's shape
  -- moves inside its nudge.
  Fanned (FanLine s ps) -> Fanned (FanLine s (map moved ps))
  Fanned (FanFill c rings) -> Fanned (FanFill c (map (map moved) rings))
  where
    moved p = p {fanAt = f (fanAt p)}

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
