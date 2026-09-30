-- |
-- Module      : Senbazuru.Render.Fidelity
-- Description : What an output says about how true to paper it is.
--
-- A picture of paper can be wrong in a way that does not show. A crane built
-- by placing vertices where a crane should be looks like a crane, and no
-- paper may be able to take its shape. A /fidelity record/ says which kind of
-- output a file is, on four independent axes (D19 in @PRDs/decisions.md@):
--
-- * __geometry__, where the positions came from: folded with rigid panels, or
--   placed where the shape should be rather than folded or settled, which
--   makes the pose a /shape sketch/ (see docs/glossary.md);
-- * __motion__, whether anything moves;
-- * __appearance__, how the paper is coloured and shaded;
-- * __lines__, which lines are drawn.
--
-- "Senbazuru.Render.Gltf" writes the record into a GLB as
-- @extras.senbazuru.fidelity@, beside the frame, when its caller asks.
-- Default outputs carry none: a key added to them would move the three GLB
-- golden files, and they make no claim a reader could hold them to.
--
-- It is a module apart from the GLB writer because the levels are one closed
-- type for every writer: a GLB's extras now, and an SVG's @\<desc\>@ once
-- something writes one (PRD 08, R-08-3). And whoever made the positions has
-- to name a level without importing a writer, as the study's @WholeCrane@
-- does.
--
-- Two things a newcomer would get wrong here:
--
-- * __The geometry level comes from whoever made the positions, never from
--   the positions.__ A 'Senbazuru.Origami.Surface.Surface' cannot tell a
--   folded crane from one whose vertices were placed to look folded: both
--   are triangles in space. So no writer guesses it; the caller says.
-- * __A level exists only once something writes it.__ The axes gain levels as
--   outputs appear that can honestly claim them: bent paper, animation,
--   shading that is smooth across a bend but sharp at a crease, line
--   drawings. A level that nothing produces would be a claim that nothing
--   makes, so it has no constructor yet.
module Senbazuru.Render.Fidelity
  ( Geometry (..),
    Motion (..),
    Appearance (..),
    Lines (..),
    Fidelity (..),
    geometryName,
    fidelityJson,
  )
where

import Data.Aeson (Value, object, (.=))
import Data.Text (Text)

-- | Where a model's positions came from.
data Geometry
  = -- | Folded: every panel flat and rigid, turning only at its creases.
    RigidPanels
  | -- | Placed where the shape should be, rather than folded or settled: a
    -- shape sketch, which paper may be unable to take.
    AsPrescribed
  deriving stock (Eq, Show)

-- | Whether the model moves.
data Motion = Static
  deriving stock (Eq, Show)

-- | How the paper looks.
data Appearance
  = -- | A0: one flat colour for each side of the paper.
    TwoFlatColours
  deriving stock (Eq, Show)

-- | Which lines are drawn.
data Lines
  = -- | None: an edge shows only where two faces meet at an angle.
    NoLines
  deriving stock (Eq, Show)

-- | A position on each of the four axes.
data Fidelity = Fidelity
  { fidelityGeometry :: !Geometry,
    fidelityMotion :: !Motion,
    fidelityAppearance :: !Appearance,
    fidelityLines :: !Lines
  }
  deriving stock (Eq, Show)

-- | A geometry level in the words of D19.
geometryName :: Geometry -> Text
geometryName = \case
  RigidPanels -> "rigid panels"
  AsPrescribed -> "as prescribed"

-- | The record as a GLB writes it, each level in the words of D19, except
-- lines: D19 names only the line styles of drawings (W0 to W2), so a model
-- that draws no lines says @none@, PRD 08's word for it.
fidelityJson :: Fidelity -> Value
fidelityJson f =
  object
    [ "geometry" .= geometryName (fidelityGeometry f),
      "motion" .= motionName (fidelityMotion f),
      "appearance" .= appearanceName (fidelityAppearance f),
      "lines" .= linesName (fidelityLines f)
    ]
  where
    motionName :: Motion -> Text
    motionName Static = "static"
    appearanceName :: Appearance -> Text
    appearanceName TwoFlatColours = "A0"
    linesName :: Lines -> Text
    linesName NoLines = "none"
