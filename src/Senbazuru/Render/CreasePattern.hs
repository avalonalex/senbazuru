-- |
-- Module      : Senbazuru.Render.CreasePattern
-- Description : Turning one FOLD frame into a crease-pattern 'Diagram'.
--
-- A crease pattern is the flat, unfolded sheet with every crease marked: what
-- you would see if you folded a model, then completely unfolded it again. It is
-- the simplest useful thing to draw from a FOLD file, because the coordinates
-- in the file are already the coordinates on the page — no folding simulation,
-- no layer ordering, no hidden-line removal.
--
-- This module is deliberately short. All it does is join three pieces that are
-- each tested on their own: "Senbazuru.Fold.Query" for validated geometry,
-- "Senbazuru.Diagram.Style" for the line conventions, and "Senbazuru.Diagram"
-- for the output type.
module Senbazuru.Render.CreasePattern
  ( creasePattern,
    paintOrder,
  )
where

import Data.List (sortOn)
import Data.Maybe (mapMaybe)
import Senbazuru.Diagram (Diagram, Shape (..), diagramWithExtent)
import Senbazuru.Diagram.Style (Theme, strokeFor)
import Senbazuru.Fold.Query
  ( Crease (..),
    FoldError (..),
    frameCreases,
    frameVertices,
  )
import Senbazuru.Fold.Types (Assignment (..), Frame)
import Senbazuru.Geometry (boxFromPoints)

-- | Render one frame as a crease pattern.
--
-- The page extent is the bounding box of /all/ vertices, not of the lines that
-- end up drawn. Those differ whenever the theme suppresses some assignment: with
-- @themeShowFlat = False@ a pattern whose outermost creases are all flat would
-- otherwise silently crop itself.
creasePattern :: Theme -> Frame -> Either FoldError Diagram
creasePattern theme fr = do
  verts <- frameVertices fr
  extent <- maybe (Left NoVertices) Right (boxFromPoints verts)
  creases <- frameCreases fr
  let shapes = mapMaybe toShape (sortOn (paintOrder . creaseAssignment) creases)
  pure (diagramWithExtent extent shapes)
  where
    toShape c = do
      stroke <- strokeFor theme (creaseAssignment c)
      pure (Polyline stroke [creaseStart c, creaseEnd c])

-- | Painting order, lowest first.
--
-- SVG paints in document order, so later shapes cover earlier ones. Creases in
-- a crease pattern frequently share endpoints and sometimes overlap, and it
-- looks wrong when a faint reference line paints over the heavy outline of the
-- sheet. Sorting by this key fixes that: background lines, then folds, then the
-- silhouette of the paper.
--
-- 'sortOn' is a stable sort, so edges with equal order keep their file order
-- and the generated SVG stays byte-for-byte reproducible.
paintOrder :: Assignment -> Int
paintOrder = \case
  Flat -> 0
  Unassigned -> 0
  Mountain -> 1
  Valley -> 1
  Border -> 2
  Cut -> 2
  Join -> 2
