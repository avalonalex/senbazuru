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
-- seen from a chosen angle and filled face by face where the layer order is
-- known. The name has stayed, because the work is the same: every edge becomes
-- one line. What differs is which lines, and that is a 'Notation', chosen by
-- 'defaultNotationFor'.
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
    basisFor,
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
import Senbazuru.Geometry (V2 (..), boxFromPoints, boxSize, norm, (^-^))
import Senbazuru.Geometry.V3 (V3 (..), hasRelief)
import Senbazuru.Geometry.VectorSpace ((*^))
import Senbazuru.Origami.Layers (paintOrder)
import Senbazuru.Origami.Stacking (StackingError (..), solveStacking)
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
  creasePatternFrom theme notation (basisFor chosenBasis verts) fr

-- | The basis a drawing will be made through: the caller's, or the one the
-- geometry picks when the caller has no opinion.
--
-- Exported because anything drawn /alongside/ a diagram has to be projected the
-- same way it was, and arrows are. Two copies of this defaulting rule would
-- stay in step only by hand, and the day they stopped the arrows would land
-- somewhere else on the page with nothing failing.
basisFor :: Maybe Basis -> [V3] -> Basis
basisFor chosen verts = fromMaybe (defaultBasisFor verts) chosen

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
-- every layer sits in the same plane — so it has to come from somewhere else.
-- A file that supplies @faceOrders@ gets its faces filled in that order. A
-- file that does not gets one worked out by "Senbazuru.Origami.Stacking",
-- which is what a folded form senbazuru computed itself always needs.
--
-- The solver covers flat-folded models with convex faces. Outside that it
-- declines, having attempted nothing, and the frame stays a wireframe — as
-- every folded form without an ordering was drawn before the solver existed.
-- A wireframe is honest about not knowing, where a fill in file order would be
-- a confident picture of the wrong thing.
--
-- An ordering that /contradicts itself/ — a file's that runs in a circle, or
-- a model whose layers cannot be stacked at all — is refused rather than
-- dropped, and the drawing fails. That is the rule stated above rather than an
-- exception to it: these faces were going to be drawn, and the only account of
-- how to stack them is impossible. Quietly drawing something else instead is
-- the failure mode this module keeps being written to avoid. @--no-fill@ still
-- renders it, for the same reason it renders a file with a broken face.
--
-- The faces are resolved only once it is known they will be drawn, so that a
-- corrupt face is only ever a reason to refuse a drawing that was going to
-- contain it. The solver keeps that promise too: it declines a model with paper
-- in the air on its vertices alone, before looking at a face.
facesToFill :: Basis -> Notation -> Frame -> Either FoldError [Face]
facesToFill basis notation fr = case notation of
  CreasePatternNotation -> frameFaces fr
  FoldedFormNotation -> do
    supplied <- frameFaceOrders fr
    ordering <-
      if null supplied
        then computed
        else Right (Just supplied)
    case ordering of
      Nothing -> Right []
      Just orders -> do
        faces <- frameFaces fr
        ids <- paintOrder towardsViewer faces orders
        -- Total by construction: paintOrder returns every face exactly once, so
        -- a lookup that missed would be a bug rather than a file to tolerate.
        let byId = IM.fromList [(unFaceId (faceId f), f) | f <- faces]
        traverse (\fid -> maybe (Left (FaceOrderOutOfRange fid (length faces))) Right (IM.lookup (unFaceId fid) byId)) ids
  where
    -- An ordering worked out from the geometry, or Nothing when the solver
    -- does not cover this model. An empty list is a real answer -- no two faces
    -- overlap, so any order draws the same picture -- and is filled.
    computed = case solveStacking fr of
      Right orders -> Right (Just orders)
      Left NotFlat {} -> Right Nothing
      Left NonConvexFace {} -> Right Nothing
      Left (StackingRefused err) -> Left err

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
-- A motion whose two ends land on the same point of the page gets no arrow.
-- That is not a failure to draw one: it is paper that moved without going
-- anywhere the reader can see it go — a model turned over, or a flap folded
-- straight up out of the page and looked at from above. Books mark those with a
-- different symbol altogether, a loop or a pair of arrows, and senbazuru has
-- neither. An arrow with no length would be given a direction by whatever the
-- arithmetic happened to produce, and would say something confident and untrue.
withArrows :: Theme -> Basis -> [Motion] -> Diagram -> Diagram
withArrows theme basis motions d =
  d {diagramShapes = diagramShapes d <> concatMap arrow motions}
  where
    V2 w h = boxSize (diagramExtent d)
    negligible = 1e-6 * max 1 (max w h)

    arrow m
      | norm (to ^-^ from) <= negligible = []
      | otherwise = [Arrow (arrowFor theme from to)]
      where
        from = project basis (motionFrom m)
        to = project basis (motionTo m)
