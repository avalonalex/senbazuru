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
    creaseOrder,
    withArrows,
  )
where

import Data.IntMap.Strict qualified as IM
import Data.List (sortOn)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import Senbazuru.Diagram (Diagram (..), Shape (..), diagramWithExtent)
import Senbazuru.Diagram.Style (Notation (..), Theme (..), arrowFor, strokeFor)
import Senbazuru.Fold.Query
  ( Crease (..),
    Face (..),
    FoldError (..),
    FrameKind (..),
    frameCreases,
    frameFaceOrders,
    frameFaces,
    frameKind,
    frameVertices,
  )
import Senbazuru.Fold.Types (Assignment (..), FaceId (..), Frame (..))
import Senbazuru.Geometry (boxFromPoints)
import Senbazuru.Geometry.V3 (V3 (..), hasRelief)
import Senbazuru.Geometry.VectorSpace ((*^))
import Senbazuru.Origami.Layers (paintOrder)
import Senbazuru.Origami.Step (Motion (..))
import Senbazuru.Render.Camera (Basis, basisForward, isometric, project, topDown)

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
  -- Faces are resolved only when they are going to be drawn, so a renderer
  -- refuses a file for something it was going to put on the page and never for
  -- anything else. The first version validated them always, on the grounds that
  -- a flag should not decide which files are acceptable; that turned a
  -- malformed face on a *folded form* -- whose faces this never draws -- into a
  -- hard failure on a file that used to render. Complaining about data nobody
  -- looked at is a validator's job, and senbazuru has a separate verb for that.
  faceShapes <- case themePaper theme of
    Nothing -> pure []
    Just colour -> do
      ordered <- facesToFill basis notation fr
      pure [Polygon colour (map flatten (faceCorners f)) | f <- ordered]
  let creaseShapes = mapMaybe toShape (sortOn (creaseOrder . creaseAssignment) creases)
  -- Every face goes under every line, whatever order the faces are in among
  -- themselves, because a fill that covered a crease would defeat the point of
  -- drawing the crease.
  pure (diagramWithExtent extent (faceShapes <> creaseShapes))
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
defaultNotationFor classes verts = case frameKind classes verts of
  FoldedForm -> FoldedFormNotation
  CreasePattern -> CreasePatternNotation

-- | The faces to fill, furthest from the viewer first, or none at all.
--
-- The two kinds of picture want different things here, for one reason: whether
-- the faces overlap.
--
-- A crease pattern is a flat subdivision of one sheet. Its faces tile the paper
-- and never cover one another, so every order draws the same picture and file
-- order will do.
--
-- A folded model does overlap itself, and then the order /is/ the picture.
-- Which face is in front is not in the coordinates — in a flat-folded model
-- every layer sits in the same plane — it is in @faceOrders@ or it is nowhere.
-- A file that supplies one gets its faces filled in that order; a file that
-- does not stays a wireframe, because a wireframe is honest about not knowing
-- and a fill in file order would be a confident picture of the wrong thing.
-- Computing an order ourselves is NP-hard in general; see
-- @docs\/notes\/layer-ordering.md@.
--
-- An ordering that /contradicts itself/ is refused rather than dropped, and the
-- drawing fails. That is a change from the version before @faceOrders@ was
-- read, where such a file rendered as a wireframe because nothing looked. It is
-- deliberate and it is the rule stated above rather than an exception to it:
-- these faces were going to be drawn, and the file's own account of how to
-- stack them is impossible. Quietly drawing something else instead is the
-- failure mode this module keeps being written to avoid. @--no-fill@ still
-- renders it, for the same reason it renders a file with a broken face.
-- The faces are resolved inside each branch rather than passed in, so that a
-- corrupt face is only ever a reason to refuse a drawing that was going to
-- contain it. A folded form with no ordering draws no faces and so never looks
-- at them.
facesToFill :: Basis -> Notation -> Frame -> Either FoldError [Face]
facesToFill basis notation fr = case notation of
  CreasePatternNotation -> frameFaces fr
  FoldedFormNotation -> do
    orders <- frameFaceOrders fr
    if null orders
      then Right []
      else do
        faces <- frameFaces fr
        ids <- paintOrder towardsViewer faces orders
        -- Total by construction: paintOrder returns every face exactly once, so
        -- a lookup that missed would be a bug rather than a file to tolerate.
        let byId = IM.fromList [(unFaceId (faceId f), f) | f <- faces]
        traverse (\fid -> maybe (Left (FaceOrderOutOfRange fid (length faces))) Right (IM.lookup (unFaceId fid) byId)) ids
  where
    -- 'basisForward' points the way the camera looks, so the viewer is the
    -- other way. Getting this backwards draws every model inside out.
    towardsViewer = (-1) *^ basisForward basis

-- | Painting order for creases, lowest first.
--
-- Faces are not in this ordering. They are painted before every crease, by
-- 'creasePatternFrom', because a fill that covered a line would defeat the
-- point of drawing the line.
--
-- SVG paints in document order, so later shapes cover earlier ones. Creases in
-- a crease pattern frequently share endpoints and sometimes overlap, and it
-- looks wrong when a faint reference line paints over the heavy outline of the
-- sheet. Sorting by this key fixes that: background lines, then folds, then the
-- silhouette of the paper.
--
-- 'sortOn' is a stable sort, so edges with equal order keep their file order
-- and the generated SVG stays byte-for-byte reproducible.
creaseOrder :: Assignment -> Int
creaseOrder = \case
  Flat -> 0
  Unassigned -> 0
  Mountain -> 1
  Valley -> 1
  Border -> 2
  Cut -> 2
  Join -> 2

-- | Add the arrows for a step to a drawing of the paper before it.
--
-- Appended, so the arrows are painted after everything else and nothing covers
-- them: the arrow is the instruction, and a diagram whose instruction is hidden
-- behind a fill is not a diagram.
--
-- The extent is left alone. It is pinned to the paper on purpose — every step
-- of a sequence has to be drawn at one scale or the model appears to grow
-- between figures — and an arrow that bows a little outside the sheet is a
-- better outcome than a page that rescales because of one.
withArrows :: Theme -> Basis -> [Motion] -> Diagram -> Diagram
withArrows theme basis motions d =
  d {diagramShapes = diagramShapes d <> map arrow motions}
  where
    arrow m = Arrow (arrowFor theme (project basis (motionFrom m)) (project basis (motionTo m)))
