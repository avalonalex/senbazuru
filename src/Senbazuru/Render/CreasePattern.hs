-- |
-- Module      : Senbazuru.Render.CreasePattern
-- Description : Turning one FOLD frame into a 'Diagram'.
--
-- A crease pattern is the flat, unfolded sheet with every crease marked: what
-- you would see if you folded a model, then completely unfolded it again. It is
-- the simplest useful thing to draw from a FOLD file, because the coordinates
-- in the file are already the coordinates on the page — no folding simulation,
-- no layer ordering, no hidden-line removal.
--
-- Since "Senbazuru.Render.Camera" arrived this module also draws folded forms,
-- as wireframes seen from a chosen angle. The name has stayed, because the work
-- is the same: every edge becomes one line. What differs is which lines, and
-- that is a 'Notation', chosen by 'defaultNotationFor'.
--
-- This module is deliberately short. All it does is join three pieces that are
-- each tested on their own: "Senbazuru.Fold.Query" for validated geometry,
-- "Senbazuru.Diagram.Style" for the line conventions, and "Senbazuru.Diagram"
-- for the output type.
module Senbazuru.Render.CreasePattern
  ( creasePattern,
    creasePatternFrom,
    creasePatternAuto,
    defaultBasisFor,
    defaultNotationFor,
    paintOrder,
  )
where

import Data.List (sortOn)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import Senbazuru.Diagram (Diagram, Shape (..), diagramWithExtent)
import Senbazuru.Diagram.Style (Notation (..), Theme, strokeFor)
import Senbazuru.Fold.Query
  ( Crease (..),
    FoldError (..),
    frameCreases,
    frameVertices,
  )
import Senbazuru.Fold.Types (Assignment (..), Frame (..))
import Senbazuru.Geometry (boxFromPoints)
import Senbazuru.Geometry.V3 (V3 (..), hasRelief)
import Senbazuru.Render.Camera (Basis, isometric, project, topDown)

-- | Render one frame as a crease pattern, seen from directly above.
--
-- Equivalent to @'creasePatternFrom' theme 'CreasePatternNotation' 'topDown'@,
-- and the right choice for a @creasePattern@ frame, which is flat in the
-- @z = 0@ plane and has nothing to see from any other angle.
creasePattern :: Theme -> Frame -> Either FoldError Diagram
creasePattern theme = creasePatternFrom theme CreasePatternNotation topDown

-- | Render one frame in the given notation, seen through the given basis.
--
-- Both choices are the caller's. Nothing here looks at the frame to second
-- guess them, which is what makes this the right function for a golden test:
-- the output depends only on the inputs you can see.
--
-- The page extent is the bounding box of /all/ projected vertices, not of the
-- lines that end up drawn. Those differ whenever the theme suppresses some
-- assignment: with @themeShowFlat = False@ a pattern whose outermost creases
-- are all flat would otherwise silently crop itself.
--
-- Projection happens here rather than in "Senbazuru.Fold.Query" so that the
-- geometry stays true to the file until the moment a page demands a flat
-- answer. Note the extent is measured /after/ projecting: how much page a model
-- needs depends on the angle it is viewed from.
creasePatternFrom :: Theme -> Notation -> Basis -> Frame -> Either FoldError Diagram
creasePatternFrom theme notation basis fr = do
  verts <- frameVertices fr
  extent <- maybe (Left NoVertices) Right (boxFromPoints (map flatten verts))
  creases <- frameCreases fr
  let shapes = mapMaybe toShape (sortOn (paintOrder . creaseAssignment) creases)
  pure (diagramWithExtent extent shapes)
  where
    flatten = project basis

    toShape c = do
      stroke <- strokeFor theme notation (creaseAssignment c)
      pure (Polyline stroke [flatten (creaseStart c), flatten (creaseEnd c)])

-- | Render one frame, letting the frame decide what kind of picture it is and,
-- unless a basis is given, where to look at it from.
--
-- The two decisions are independent. A caller supplying a basis is overriding
-- the camera, and that says nothing about whether the frame is a crease
-- pattern, so the notation is still chosen here. There is no way to override
-- the notation yet because nobody has needed one.
creasePatternAuto :: Theme -> Maybe Basis -> Frame -> Either FoldError Diagram
creasePatternAuto theme chosenBasis fr = do
  verts <- frameVertices fr
  let notation = defaultNotationFor (frameClasses fr) verts
      basis = fromMaybe (defaultBasisFor verts) chosenBasis
  creasePatternFrom theme notation basis fr

-- | Pick a viewing basis for geometry we know nothing else about.
--
-- Flat means 'topDown'; anything with real thickness means 'isometric'.
--
-- The test is the geometry, deliberately, not @frame_classes@. A folded form is
-- not necessarily three-dimensional: the traditional crane folds /flat/, so its
-- folded form lies in a plane, and viewing it isometrically would shear a
-- correct picture into a wrong one. Asking the coordinates cannot get that
-- wrong, and it also works for the many files that declare no class at all.
defaultBasisFor :: [V3] -> Basis
defaultBasisFor verts
  | hasRelief verts = isometric
  | otherwise = topDown

-- | Pick the line convention for a frame, from its classes and its vertices.
--
-- A crease pattern is flat by definition, so any relief settles it: this is a
-- folded form, whatever the frame says about itself. A flat frame is the hard
-- case. A flat-folded model — the traditional crane again — and a crease
-- pattern have the same kind of coordinates, and no test on them tells the two
-- apart short of checking whether faces overlap. So for flat frames, and only
-- for flat frames, this asks @frame_classes@. A frame that declares nothing is
-- drawn as a crease pattern, which is what every version so far has done.
--
-- This is the one place @frame_classes@ influences rendering, and it is an
-- exception to the rule 'defaultBasisFor' follows. The two questions are
-- different. The camera asks \"where is the paper\", which a class cannot
-- answer and coordinates always can. This asks \"what is this a picture of\",
-- which is exactly what a class records and which coordinates can answer only
-- when the paper has left the plane.
--
-- The vertices are passed in, not read from the frame, because the caller has
-- already validated them and a frame with a bad coordinate should fail once,
-- with one error, in one place.
defaultNotationFor :: [Text] -> [V3] -> Notation
defaultNotationFor classes verts
  | hasRelief verts = FoldedFormNotation
  | "foldedForm" `elem` classes = FoldedFormNotation
  | otherwise = CreasePatternNotation

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
