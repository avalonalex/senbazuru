-- |
-- Module      : Senbazuru.Diagram.Style
-- Description : How origami books draw creases, encoded as strokes.
--
-- == The Yoshizawa-Randlett system
--
-- Origami diagrams use a notation that has been essentially stable since the
-- 1950s, developed by Akira Yoshizawa and popularised in English by Samuel
-- Randlett and Robert Harbin. Nearly every instruction book you have seen uses
-- it. The part that concerns a crease-pattern renderer is the line vocabulary:
--
-- +------------------------+-------------------------------------------------+
-- | Edge of the paper      | solid line, slightly heavier                    |
-- +------------------------+-------------------------------------------------+
-- | Valley fold            | dashed line                                     |
-- +------------------------+-------------------------------------------------+
-- | Mountain fold          | dash-dot-dot line (a \"chain\" line, borrowed     |
-- |                        | from technical drawing)                         |
-- +------------------------+-------------------------------------------------+
-- | Existing crease, flat  | thin light line                                 |
-- +------------------------+-------------------------------------------------+
-- | Hidden / X-ray edge    | dotted line (not used yet)                      |
-- +------------------------+-------------------------------------------------+
--
-- There is a second, different convention you will meet in crease-pattern
-- /editors/ (and in much origami software): colour-coded lines, typically red
-- for mountain and blue for valley, all of the same weight. That convention is
-- built for screens and for editing. This module deliberately implements the
-- printed-book one instead, because it survives black-and-white printing and
-- photocopying, which is what the whole notation was designed for. A colour
-- theme is a plausible future addition, not a replacement.
--
-- == One vocabulary, two kinds of picture
--
-- The dashes in that table mean /a fold still to be made/. That is what a
-- crease pattern is: a flat sheet with the instructions drawn on it. A folded
-- form is a different kind of picture — the paper as it is now — and a book
-- draws it with solid lines only, because there is nothing left to instruct. A
-- crease that has been folded is an edge of the shape, and is drawn like one.
-- The dotted line for edges hidden behind a layer belongs to this second kind
-- of picture; it is unused because nothing yet works out which edges are
-- hidden.
--
-- 'Notation' names the two kinds, and 'strokeFor' takes one, so that whoever
-- draws a frame has to say which picture it is. The first version of the camera
-- drew folded forms with crease-pattern dashes precisely because nothing forced
-- that choice.
--
-- One thing that trips up newcomers: mountain and valley are not intrinsic
-- properties of a crease, they are relative to which side of the sheet you are
-- looking at. Turn the paper over and every mountain becomes a valley. FOLD
-- records the assignment with respect to the sheet's stated orientation, and
-- for a crease pattern that is enough, because a crease pattern is always
-- viewed from that side. Under a camera it is not enough: a face turned away
-- from the viewer has its mountains and valleys swapped from where the viewer
-- stands. Drawing folded forms with solid edges sidesteps this. A step diagram
-- that marks the /next/ fold on top of a folded form will have to face it.
--
-- == Why this module knows about 'Assignment'
--
-- It sits between the origami domain and the drawing layer, so it necessarily
-- touches both. Concentrating that knowledge here is the point: when the
-- diagrams look wrong, this is the only file to open.
module Senbazuru.Diagram.Style
  ( -- * Themes
    Theme (..),
    defaultTheme,

    -- * Mapping fold semantics to ink
    Notation (..),
    strokeFor,

    -- * Palette
    ink,
    ghost,
    paper,
  )
where

import Senbazuru.Diagram (Colour (..), Dash (..), Stroke (..), solid)
import Senbazuru.Fold.Types (Assignment (..))

-- | Near-black, as used for the drawing itself. Not pure black: printed
-- diagrams and screen rendering both read slightly softer ink as cleaner.
ink :: Colour
ink = Colour "#1a1a1a"

-- | Light grey, for reference lines that must be visible but must not compete
-- with the folds being taught.
ghost :: Colour
ghost = Colour "#bdbdbd"

-- | A faint warm off-white, for the sheet itself.
--
-- A printed book fills faces with nothing at all: the paper in the diagram is
-- the paper of the page, and the sheet reads as an object because the reader is
-- holding one. On a screen there is no such luck — a white sheet on a white
-- background is invisible, and the drawing is lines floating in a void. This is
-- the smallest tint that gives the sheet a silhouette without turning it into
-- a coloured shape competing with the creases.
paper :: Colour
paper = Colour "#faf8f3"

-- | The knobs that control how a diagram looks.
--
-- All widths and dash lengths are in __page units__ (see the two-unit rule in
-- "Senbazuru.Diagram"), tuned for a drawing a few hundred units across.
--
-- The two dash patterns only apply under 'CreasePatternNotation'. A theme does
-- not decide which notation is in use; that is a property of the frame being
-- drawn, not of how it should look.
data Theme = Theme
  { themeInk :: !Colour,
    themeGhost :: !Colour,
    -- | Heavier, so the silhouette of the sheet reads first.
    themeBorderWidth :: !Double,
    themeCreaseWidth :: !Double,
    themeGhostWidth :: !Double,
    themeValleyDash :: !Dash,
    themeMountainDash :: !Dash,
    -- | Draw @F@ creases (a crease line that is not folded)?
    themeShowFlat :: !Bool,
    -- | Draw @U@ creases (direction not yet decided)?
    themeShowUnassigned :: !Bool,
    -- | Fill faces with this colour, or 'Nothing' to leave the sheet as a
    -- wireframe.
    --
    -- Offering a colour is as far as a theme goes. Whether faces /can/ be
    -- filled is not a question about how a drawing should look: a folded model
    -- overlaps itself, so filling one means knowing which face is in front, and
    -- that is in the file or it is nowhere. See
    -- "Senbazuru.Render.CreasePattern".
    themePaper :: !(Maybe Colour)
  }
  deriving stock (Eq, Show)

-- | A conservative default modelled on printed instruction books.
defaultTheme :: Theme
defaultTheme =
  Theme
    { themeInk = ink,
      themeGhost = ghost,
      themeBorderWidth = 1.6,
      themeCreaseWidth = 1.0,
      themeGhostWidth = 0.6,
      -- Even dashes with a slightly shorter gap: unmistakably "dashed" without
      -- looking sparse at small sizes.
      themeValleyDash = Dash [6, 3.5],
      -- Long dash, dot, dot. The long segment distinguishes it from a valley at
      -- a glance; the two dots are what makes it a mountain rather than a
      -- generic centreline.
      themeMountainDash = Dash [9, 3, 1.2, 3, 1.2, 3],
      themeShowFlat = True,
      themeShowUnassigned = True,
      themePaper = Just paper
    }

-- | Which kind of picture the lines belong to.
--
-- The same edge is drawn differently depending on what the drawing is /of/. In
-- a crease pattern a mountain crease is an instruction, and gets the
-- dash-dot-dot that says \"fold this away from you\". In a folded form that
-- crease has already been folded: it is now an edge of the shape, and is drawn
-- solid like any other edge.
data Notation
  = -- | A flat sheet with the folds still to be made marked on it.
    CreasePatternNotation
  | -- | The paper as it is after folding. Every crease is an edge.
    FoldedFormNotation
  deriving stock (Eq, Show)

-- | The stroke to draw an edge with, or 'Nothing' if it should not be drawn.
--
-- \"Not drawn\" is a real answer, not an error case. A @J@ (join) edge exists
-- only to tell software that two faces are logically one piece of paper; there
-- is no crease there, so drawing a line would be actively misleading.
--
-- Only mountains and valleys depend on the 'Notation'. The border of the sheet
-- is an edge in both pictures, and a flat or unassigned crease is a line on the
-- paper in both, drawn faint so that it does not compete with the folds. The
-- widths are the same under both notations too, so the only difference between
-- a crease pattern and a folded form of the same frame is the dashes.
strokeFor :: Theme -> Notation -> Assignment -> Maybe Stroke
strokeFor theme notation = \case
  -- The boundary of the sheet, and cuts, are both real edges of paper.
  Border -> Just border
  Cut -> Just border
  Valley -> Just (crease (themeValleyDash theme))
  Mountain -> Just (crease (themeMountainDash theme))
  Flat
    | themeShowFlat theme -> Just faint
    | otherwise -> Nothing
  Unassigned
    | themeShowUnassigned theme -> Just faint
    | otherwise -> Nothing
  -- Not a fold at all: the two incident faces are the same piece of paper.
  Join -> Nothing
  where
    border = solid (themeInk theme) (themeBorderWidth theme)
    faint = solid (themeGhost theme) (themeGhostWidth theme)

    -- A fold: an instruction in a crease pattern, an edge in a folded form.
    crease dash = case notation of
      CreasePatternNotation -> Stroke (themeInk theme) (themeCreaseWidth theme) dash
      FoldedFormNotation -> solid (themeInk theme) (themeCreaseWidth theme)
