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
-- One thing that trips up newcomers: mountain and valley are not intrinsic
-- properties of a crease, they are relative to which side of the sheet you are
-- looking at. Turn the paper over and every mountain becomes a valley. FOLD
-- records the assignment with respect to the sheet's stated orientation, and
-- this module simply renders whatever the file says.
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
    strokeFor,

    -- * Palette
    ink,
    ghost,
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

-- | The knobs that control how a crease pattern looks.
--
-- All widths and dash lengths are in __page units__ (see the two-unit rule in
-- "Senbazuru.Diagram"), tuned for a drawing a few hundred units across.
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
    themeShowUnassigned :: !Bool
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
      themeShowUnassigned = True
    }

-- | The stroke to draw an edge with, or 'Nothing' if it should not be drawn.
--
-- \"Not drawn\" is a real answer, not an error case. A @J@ (join) edge exists
-- only to tell software that two faces are logically one piece of paper; there
-- is no crease there, so drawing a line would be actively misleading.
strokeFor :: Theme -> Assignment -> Maybe Stroke
strokeFor theme = \case
  -- The boundary of the sheet, and cuts, are both real edges of paper.
  Border -> Just (solid (themeInk theme) (themeBorderWidth theme))
  Cut -> Just (solid (themeInk theme) (themeBorderWidth theme))
  Valley ->
    Just (Stroke (themeInk theme) (themeCreaseWidth theme) (themeValleyDash theme))
  Mountain ->
    Just (Stroke (themeInk theme) (themeCreaseWidth theme) (themeMountainDash theme))
  Flat
    | themeShowFlat theme -> Just (faint theme)
    | otherwise -> Nothing
  Unassigned
    | themeShowUnassigned theme -> Just (faint theme)
    | otherwise -> Nothing
  -- Not a fold at all: the two incident faces are the same piece of paper.
  Join -> Nothing
  where
    faint t = solid (themeGhost t) (themeGhostWidth t)
