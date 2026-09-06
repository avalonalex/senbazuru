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
-- seen from a chosen angle. The name has stayed, because most of the work is
-- the same. What differs is which lines are drawn and how, and that is a
-- 'Notation', chosen by 'defaultNotationFor'.
--
-- == The three ways a frame gets drawn
--
-- A crease pattern is a flat subdivision of one sheet: nothing overlaps, so
-- every face is filled and every crease drawn.
--
-- A model folded __flat__ is drawn as what can be seen of it —
-- "Senbazuru.Origami.Visible" cuts each face down to the part no nearer layer
-- covers, and keeps each edge only where the paper differs across it. That
-- picture has its hidden lines gone and its two sides of paper apart, and it is
-- the only one of the three that can draw a twist at all.
--
-- Anything else — a folded form with paper still in the air — is filled face by
-- face, back to front, in the order "Senbazuru.Origami.Layers" sorts
-- @faceOrders@ into, with every crease drawn over the top. It is the oldest of
-- the three and the fallback for everything the second cannot take apart.
--
-- This module is deliberately short. All it does is choose between those and
-- join pieces that are each tested on their own: "Senbazuru.Fold.Query" for
-- validated geometry, "Senbazuru.Diagram.Style" for the line conventions, and
-- "Senbazuru.Diagram" for the output type.
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
import Senbazuru.Diagram (Colour, Diagram (..), Shape (..), diagramWithExtent)
import Senbazuru.Diagram.Style (Notation (..), Paper (..), Theme (..), arrowFor, strokeFor)
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
import Senbazuru.Fold.Types (Assignment (..), FaceId (..), FaceOrder, Frame (..))
import Senbazuru.Geometry (V2 (..), boxFromPoints, boxSize, norm, (^-^))
import Senbazuru.Geometry.V3 (V3 (..), hasRelief)
import Senbazuru.Geometry.VectorSpace ((*^))
import Senbazuru.Origami.Flat (FlatError (..))
import Senbazuru.Origami.Layers (paintOrder)
import Senbazuru.Origami.Stacking (StackingError (..), solveStacking)
import Senbazuru.Origami.Step (Motion (..))
import Senbazuru.Origami.Visible (Region (..), VisibleEdge (..), VisibleForm (..), visibleForm)
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
  extent <- maybe (Left NoVertices) Right (boxFromPoints (map (project basis) verts))
  shapes <- picture theme notation basis fr
  pure (diagramWithExtent extent shapes)

-- | Everything to draw for one frame: the paper first, then the lines.
--
-- Every fill goes under every line, whatever order the fills are in among
-- themselves, because a fill that covered a crease would defeat the point of
-- drawing the crease.
--
-- A crease pattern is one sheet cut into faces that never overlap, so they are
-- one area of paper and every crease is drawn: nothing to hide, no order to
-- work out. A folded form is drawn from what is /visible/ when senbazuru can
-- work that out — which needs it to be folded flat, and needs to know which
-- layer is on top — and back to front, face by face, otherwise. A theme with no
-- paper colour draws none of it: no fills, every crease, and no layer order
-- asked for at all.
--
-- Faces are resolved only when they are going to be drawn, so a renderer
-- refuses a file for something it was going to put on the page and never for
-- anything else. The first version validated them always, on the grounds that
-- a flag should not decide which files are acceptable; that turned a malformed
-- face on a /folded form/ — whose faces this never drew — into a hard failure
-- on a file that used to render. Complaining about data nobody looked at is a
-- validator's job, and senbazuru has a separate verb for that.
picture :: Theme -> Notation -> Basis -> Frame -> Either FoldError [Shape]
picture theme notation basis fr = case (notation, themePaper theme) of
  (CreasePatternNotation, Nothing) -> everyCrease
  (CreasePatternNotation, Just colours) -> do
    faces <- frameFaces fr
    withCreases [fill basis (paperFront colours) faces]
  -- With no paper colour there is nothing to fill and nothing to hide behind,
  -- so every crease is drawn and no layer order is asked for. That is what
  -- makes @--no-fill@ the escape hatch it is documented to be: it still renders
  -- a file whose stacking is impossible, or whose faces this cannot read.
  (FoldedFormNotation, Nothing) -> everyCrease
  (FoldedFormNotation, Just colours) -> do
    ordering <- layerOrder fr
    case ordering of
      -- Nothing is known about the layers and the file says nothing either, so
      -- there is no honest way to fill anything. A wireframe it is.
      Nothing -> everyCrease
      Just orders -> case visibleForm (seenFromAbove basis) fr orders of
        Right seen -> Right (whatIsVisible theme notation colours basis seen)
        -- The model is not flat, or has a face the region finder cannot clip.
        -- Fall back to painting whole faces in the order the layers give, which
        -- is how every folded form was drawn before regions existed.
        Left (PaperInTheAir _) -> backToFront colours orders
        Left (ConcaveFace _) -> backToFront colours orders
        Left (FlatRefused err) -> Left err
  where
    withCreases fills = (fills <>) <$> everyCrease

    everyCrease =
      mapMaybe (edgeOf theme notation basis . asDrawn)
        . sortOn (creaseOrder . creaseAssignment)
        <$> frameCreases fr

    asDrawn c = (creaseAssignment c, creaseStart c, creaseEnd c)

    -- Whole faces, furthest from the viewer first, each its own area because
    -- they overlap and the order is the picture. Every crease is drawn over
    -- them, buried or not: without regions there is no telling which are.
    backToFront colours orders = do
      faces <- frameFaces fr
      ids <- paintOrder ((-1) *^ basisForward basis) faces orders
      -- Total by construction: paintOrder returns every face exactly once, so a
      -- lookup that missed would be a bug rather than a file to tolerate.
      let byId = IM.fromList [(unFaceId (faceId f), f) | f <- faces]
          look fid = maybe (Left (FaceOrderOutOfRange fid (length faces))) Right (IM.lookup (unFaceId fid) byId)
      ordered <- traverse look ids
      withCreases [fill basis (paperFront colours) [f] | f <- ordered]

-- | The layer order to draw a folded form by: the file\'s, or one worked out,
-- or nothing at all.
--
-- A file that supplies @faceOrders@ gets its own. A file that does not gets one
-- from "Senbazuru.Origami.Stacking", which covers models folded flat with
-- convex faces; outside that it declines, having attempted nothing, and there
-- is no ordering to be had. An empty list is a real answer — no two faces
-- overlap — and is not the same as no answer.
--
-- A model the solver /tried/ and found impossible — no stacking of its layers
-- avoids the paper passing through itself — is refused rather than dropped, and
-- the drawing fails. That is the rule above rather than an exception to it:
-- these faces were going to be drawn, and the only account of how to stack them
-- is impossible. Quietly drawing something else instead is the failure mode this
-- module keeps being written to avoid, and @--no-fill@ still renders the file.
layerOrder :: Frame -> Either FoldError (Maybe [FaceOrder])
layerOrder fr = do
  supplied <- frameFaceOrders fr
  if null supplied
    then case solveStacking fr of
      Right orders -> Right (Just orders)
      Left NotFlat {} -> Right Nothing
      Left NonConvexFace {} -> Right Nothing
      Left (StackingRefused err) -> Left err
    else Right (Just supplied)

-- | Is the viewer on the @+z@ side of the model?
--
-- 'basisForward' points the way the camera looks, so the viewer is the other
-- way. A model lying flat in a plane is seen from above when the camera looks
-- down at it, and a camera exactly edge on — which shows a flat model as a line
-- — is counted as above, because the answer has to be one or the other and
-- there is nothing to see either way.
seenFromAbove :: Basis -> Bool
seenFromAbove basis = v3z (basisForward basis) <= 0

-- | The paper that shows and the lines that are not buried.
--
-- Two fills at most, one per side of the sheet, each gathering every piece of
-- paper of that side into one area — which is the whole reason a 'Fill' holds
-- rings. The pieces of a region abut, and so do the regions of neighbouring
-- faces; drawn separately they would be criss-crossed with pale seams where
-- they meet.
--
-- The two sides are drawn in a fixed order rather than a meaningful one. They
-- do not overlap, so the order is not a picture of anything; it is here so the
-- output is reproducible.
whatIsVisible :: Theme -> Notation -> Paper -> Basis -> VisibleForm -> [Shape]
whatIsVisible theme notation colours basis seen =
  [ Fill colour rings
    | (colour, side) <- [(paperFront colours, True), (paperBack colours, False)],
      let rings = paperOf side,
      not (null rings)
  ]
    <> mapMaybe (edgeOf theme notation basis . asDrawn) (sortOn (creaseOrder . visibleAssignment) (formEdges seen))
  where
    paperOf side =
      [ map (project basis) piece
        | r <- formRegions seen,
          regionTopSide r == side,
          piece <- regionPieces r
      ]

    asDrawn e = (visibleAssignment e, visibleFrom e, visibleTo e)

-- | One area of paper: a colour and the faces that make it up.
fill :: Basis -> Colour -> [Face] -> Shape
fill basis colour faces =
  Fill colour [map (project basis) (faceCorners f) | f <- faces]

-- | One line of the drawing, or nothing where the notation draws none.
--
-- The two pictures reach this from different data — a 'Crease' of the frame, or
-- a stretch of one that "Senbazuru.Origami.Visible" found not to be buried —
-- and what happens to it afterwards is the same, which is why they hand over
-- the same triple rather than each building a 'Polyline' of their own.
edgeOf :: Theme -> Notation -> Basis -> (Assignment, V3, V3) -> Maybe Shape
edgeOf theme notation basis (assignment, from, to) = do
  stroke <- strokeFor theme notation assignment
  pure (Polyline stroke [project basis from, project basis to])

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
