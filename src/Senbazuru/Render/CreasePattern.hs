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
-- == How a frame gets drawn
--
-- A crease pattern is a flat subdivision of one sheet: nothing overlaps, so
-- every face is filled and every crease drawn.
--
-- A model folded __flat__ is drawn as what can be seen of it —
-- "Senbazuru.Origami.Visible" cuts each face down to the part no nearer layer
-- covers, and keeps each edge only where the paper differs across it. That
-- picture has its hidden lines gone and its two sides of paper apart, and it is
-- handles twists whose overlapping flaps have no single painting order.
--
-- An open fold with convex planar panels uses "Senbazuru.Render.Projected":
-- their overlapping shadows determine viewing order from depth, with the
-- supplied layer orders breaking coplanar ties. The same visible-region code
-- can then hide buried creases and show the correct paper side.
--
-- Unsupported open folds retain the older fallback: whole faces in the order
-- "Senbazuru.Origami.Layers" supplies, with every crease over the top, or a
-- wireframe if no layer order is available.
--
-- The offset view is asked for rather than deduced, and is the subject of the
-- next section.
--
-- == The offset view
--
-- A model folded flat can be a picture of nothing. Fold a square into quarters
-- and the four quadrants land exactly on top of one another, so the silhouette
-- is one square, the only visible region is one square, and a reader learns
-- nothing about the four layers underneath — hidden-line removal cannot help,
-- because there is nothing hidden that is not /entirely/ hidden.
--
-- Books answer this by drawing the stack slightly opened, and so does a theme
-- whose @themeLayers@ is 'Senbazuru.Diagram.Style.OffsetBy' a distance: every
-- face is drawn whole, and each layer is nudged a
-- few points further across the page than the layer below it, the way an
-- exploded engineering drawing separates the parts of an assembly. Which layer
-- a face is in comes from 'Senbazuru.Origami.Layers.layerDepths'; how far one
-- layer moves from the next is 'Senbazuru.Diagram.Style.layerStep', in page
-- units, so the model's own coordinates are untouched and the page does not
-- rescale because a stack was opened out.
--
-- Four things follow, and all four are the point rather than side effects.
--
-- * __Nothing is hidden.__ The whole of every face is drawn, because the
--   layers underneath are exactly what the reader asked to see.
--
-- * __A shared crease is drawn twice.__ The two faces along it are at different
--   offsets, so one line cannot serve both; each face brings its own copy.
--
-- * __The paper is painted a layer at a time.__ Everywhere else in senbazuru
--   every fill goes under every line. Here a layer's fill has to cover the
--   lines of the layer below, or the stack reads as a heap of wireframes, so
--   the order is fill, lines, fill, lines, from the bottom of the stack up.
--
-- * __The drawing is in two weights.__ A buried sheet is drawn at
--   'Senbazuru.Diagram.Style.themeBuriedWidth', which is a third of a crease,
--   and the model itself — the stretches "Senbazuru.Origami.Visible" says are
--   not hidden — goes over the top at full weight, each stretch with the sheet
--   whose edge it is. Drawn all at one weight, a dozen sheet edges three points
--   apart are a black band rather than a stack; this is the difference between
--   a picture of a model standing on its layers and a picture of nothing in
--   particular.
--
-- The one thing an offset view needs and the ordinary picture of a flat model
-- does not is a single order to put every face in. A twist has none — see
-- "Senbazuru.Origami.Visible" — so a twist has no offset view either, and says
-- so rather than drawing one.
--
-- Nor can every model have its two weights. Telling the model from the
-- stack takes the visible form, and "Senbazuru.Origami.Visible" declines a
-- model with paper in the air or a concave face. The stack is then drawn
-- alone: each face filled on its own, and every line at the model's weight,
-- since none can be told apart as buried.
--
-- That refusal, and the choice between the stack with the model over it and
-- the stack alone, are the offset view's. The painting is a separate function,
-- @paintLayers@, which is told how to move each layer and refuses nothing. A
-- picture that paints the same stack a layer at a time but moves it some other
-- way can share the painter without inheriting the refusals. Moving whole
-- layers is all it can be told so far: a fan, which moves each point by its
-- own amount (PRDs\/06, R-06-27), needs more from it than a layer's number.
--
-- This module is deliberately short. All it does is choose between those and
-- join pieces that are each tested on their own: "Senbazuru.Fold.Query" for
-- validated geometry, "Senbazuru.Diagram.Style" for the line conventions, and
-- "Senbazuru.Diagram" for the output type.
module Senbazuru.Render.CreasePattern
  ( creasePattern,
    creasePatternFrom,
    creasePatternAuto,
    surfaceDiagram,
    defaultBasisFor,
    basisFor,
    defaultNotationFor,
    creaseOrder,
    withArrows,
    withKindedArrows,
    withFoldLines,
  )
where

import Data.IntMap.Strict qualified as IM
import Data.List (nub, sortOn)
import Data.Map.Strict qualified as M
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import Senbazuru.Diagram (ArrowPath, Colour, Diagram (..), Shape (..), Stroke, diagramWithExtent)
import Senbazuru.Diagram.Style
  ( ArrowKind,
    Notation (..),
    Paper (..),
    Theme (..),
    arrowFor,
    buriedEdge,
    foldLineStroke,
    layerStep,
    strokeFor,
    withKind,
  )
import Senbazuru.Fold.Query
  ( Crease (..),
    Face (..),
    FoldError (..),
    FrameKind (..),
    edgeKey,
    frameCreases,
    frameFaces,
    frameKind,
    frameVertices,
    ringEdges,
  )
import Senbazuru.Fold.Types (Assignment (..), FaceId (..), Frame (..))
import Senbazuru.Geometry (V2 (..), boxFromPoints, boxSize, norm, (^-^))
import Senbazuru.Geometry.V3 (V3 (..), hasRelief)
import Senbazuru.Geometry.VectorSpace ((*^))
import Senbazuru.Origami.Flat (FlatError (..))
import Senbazuru.Origami.Layers (layerDepths, layerOf, paintOrder, showsTopSide)
import Senbazuru.Origami.Stacking (Budget, defaultBudget, layerOrderFor)
import Senbazuru.Origami.Step (Motion (..))
import Senbazuru.Origami.Surface (Surface, surfaceFrame)
import Senbazuru.Origami.Visible (Region (..), SheetEdge (..), VisibleEdge (..), VisibleForm (..), visibleForm)
import Senbazuru.Render.Camera (Basis, SeenFrom (..), View (..), basisForward, isometric, project, seenFrom, topDown, turnedBy)
import Senbazuru.Render.Projected (projectedForm)

-- | Render one frame as a crease pattern, seen from directly above.
--
-- Equivalent to @'creasePatternFrom' theme 'defaultBudget'
-- 'CreasePatternNotation' 'topDown'@, and the right choice for a
-- @creasePattern@ frame, which is flat in the @z = 0@ plane and has nothing to
-- see from any other angle.
--
-- The budget is beside the point here and any would do: a crease pattern\'s
-- faces do not overlap, so there are no layers to look for.
creasePattern :: Theme -> Frame -> Either FoldError Diagram
creasePattern theme = creasePatternFrom theme defaultBudget CreasePatternNotation topDown

-- | Draw the current geometry of a shared material surface. Physical
-- thickness is not a page displacement; the existing theme's offset remains
-- an explicitly requested drawing aid. Material coordinates and directional
-- contact requirements do not become camera-dependent painting orders.
surfaceDiagram :: Theme -> Budget -> View -> Surface material -> Either FoldError Diagram
surfaceDiagram theme budget view = creasePatternAuto theme budget view . surfaceFrame

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
creasePatternFrom :: Theme -> Budget -> Notation -> Basis -> Frame -> Either FoldError Diagram
creasePatternFrom theme budget notation basis fr = do
  verts <- frameVertices fr
  extent <- maybe (Left NoVertices) Right (boxFromPoints (map (project basis) verts))
  shapes <- picture theme budget notation basis fr
  pure (diagramWithExtent extent shapes)

-- | Everything to draw for one frame: the paper first, then the lines.
--
-- Every fill goes under every line, whatever order the fills are in among
-- themselves, because a fill that covered a crease would defeat the point of
-- drawing the crease. The offset view is the exception, and the module header
-- says why.
--
-- A crease pattern is one sheet cut into faces that never overlap, so they are
-- one area of paper and every crease is drawn: nothing to hide, no order to
-- work out. A folded form is drawn from what is /visible/ when senbazuru can
-- work that out, using layer order for flat paper and projected depth for open
-- panels, and back to front, face by face, otherwise. A theme with no
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
picture :: Theme -> Budget -> Notation -> Basis -> Frame -> Either FoldError [Shape]
picture theme budget notation basis fr = case (notation, themePaper theme) of
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
    ordering <- layerOrderFor budget fr
    case ordering of
      -- Without layer orders, separated panels can still be ordered by actual
      -- depth. Unresolved coplanar contact remains a wireframe. An offset view
      -- still requires physical layers: with no layers there is
      -- nothing to step apart, and stepping the faces apart by anything else
      -- would be inventing a stack.
      Nothing -> case layerStep theme of
        Nothing -> spatial colours [] everyCrease
        Just _ -> everyCrease
      Just orders -> case layerStep theme of
        -- Asked for outright, so it is tried before the pictures that are
        -- deduced -- and it refuses rather than falling back, because every
        -- fallback here draws the layers on top of one another, which is the
        -- one picture the reader has said is no use to them.
        Just step -> steppedApart step colours orders
        Nothing -> case visibleForm (seenFromAbove basis) fr orders of
          Right seen -> Right (whatIsVisible theme notation colours basis seen)
          -- Open convex panels first try projected visibility. Other unsupported
          -- geometry keeps the older whole-face fallback.
          Left (PaperInTheAir _) -> spatial colours orders (backToFront colours orders)
          Left (ConcaveFace _) -> backToFront colours orders
          Left (FlatRefused err) -> Left err
  where
    withCreases fills = (fills <>) <$> everyCrease

    towardsViewer = towardsViewerOf basis

    everyCrease =
      mapMaybe (edgeOf theme notation basis . creaseLine)
        . sortOn (creaseOrder . creaseAssignment)
        <$> frameCreases fr

    spatial colours orders fallback = do
      seen <- projectedForm basis fr orders
      case seen of
        Just visible -> pure (whatIsVisible theme notation colours basis visible)
        Nothing -> fallback

    -- Whole faces, furthest from the viewer first, each its own area because
    -- they overlap and the order is the picture. Every crease is drawn over
    -- them, buried or not: without regions there is no telling which are.
    backToFront colours orders = do
      faces <- frameFaces fr
      ids <- paintOrder towardsViewer faces orders
      -- Total by construction: paintOrder returns every face exactly once, so a
      -- lookup that missed would be a bug rather than a file to tolerate.
      let byId = IM.fromList [(unFaceId (faceId f), f) | f <- faces]
          look fid = maybe (Left (FaceOrderOutOfRange fid (length faces))) Right (IM.lookup (unFaceId fid) byId)
      ordered <- traverse look ids
      withCreases [fill basis (paperFront colours) [f] | f <- ordered]

    -- The offset view: every face whole, one layer at a time from the bottom of
    -- the stack up, each layer nudged a little further across the page than the
    -- one below it. See the module header for what it is for.
    --
    -- What is decided here is whether there is an offset view to draw, and what
    -- it refuses; how one is painted is 'paintLayers'. The refusals are the
    -- offset view's own. It is asked for outright, so a model it cannot draw is
    -- refused rather than drawn some other way, and a painter that carried those
    -- refusals with it would make them for any picture it painted.
    steppedApart step colours orders = do
      faces <- frameFaces fr
      creases <- frameCreases fr
      depths <- layerDepths towardsViewer faces orders
      let paint = paintLayers theme notation colours basis (\d -> Offset (fromIntegral d *^ step)) faces creases depths
      case visibleForm (seenFromAbove basis) fr orders of
        Right seen -> Right (paint (Just seen))
        -- No visible form to be had -- paper in the air, or a face the region
        -- finder cannot clip -- is not a refusal: the stack can still be
        -- drawn, only without the model over it.
        Left (PaperInTheAir _) -> Right (paint Nothing)
        Left (ConcaveFace _) -> Right (paint Nothing)
        Left (FlatRefused err) -> Left err

-- | Which way the viewer is from the model, the way 'layerDepths' and
-- 'showsTopSide' are asked it: against the direction the camera looks.
towardsViewerOf :: Basis -> V3
towardsViewerOf basis = (-1) *^ basisForward basis

-- | A crease, and a stretch of one, as 'edgeOf' and 'edgeWith' take them.
creaseLine :: Crease -> (Assignment, V3, V3)
creaseLine c = (creaseAssignment c, creaseStart c, creaseEnd c)

stretchLine :: VisibleEdge -> (Assignment, V3, V3)
stretchLine e = (visibleAssignment e, visibleFrom e, visibleTo e)

-- | A stack painted a layer at a time, from the bottom up, each layer moved by
-- what @move@ makes of its number. The offset view hands it
-- @'Offset' (layer × step)@. Nothing here looks at what @move@ does, so a
-- picture moving whole layers by other amounts could be painted by it too.
--
-- @depths@ is each face's layer, from 'layerDepths'. With a visible form, the
-- stack is drawn fine and the model goes over it at full weight; without one
-- -- paper in the air, or a face the region finder cannot clip -- every line is
-- drawn as the model, and each face is filled on its own rather than merged
-- with the rest of its layer. The caller decides which, and what to refuse: nothing
-- here can fail.
paintLayers ::
  Theme ->
  Notation ->
  Paper ->
  Basis ->
  (Int -> Shape -> Shape) ->
  [Face] ->
  [Crease] ->
  [(FaceId, Int)] ->
  Maybe VisibleForm ->
  [Shape]
paintLayers theme notation colours basis move faces creases depths visible = case visible of
  -- What the model would look like without the offset, laid over the stack
  -- at full weight, each stretch at the offset of the sheet whose edge it
  -- is. That is the whole of the design: the reader sees the drawing they
  -- would have seen, with the layers it stands on showing behind it.
  --
  -- The visibility is worked out on the model as it lies, not as it is
  -- drawn, and the two differ. A sheet @k@ layers above the one a stretch
  -- belongs to is drawn @k@ steps away from where it was judged, so it
  -- covers, or stops covering, a band that wide along the stretch: a few
  -- points on a shallow model and most of the drawing on a deep one. The
  -- alternative is a second arrangement, computed in page space after every
  -- sheet has moved, which is a hidden-line problem of its own.
  Just seen ->
    let byLayer = modelByLayer seen
     in stacked (\d -> IM.findWithDefault [] d byLayer)
  -- No telling the model from the stack it stands on, so every line is drawn
  -- as the model, which is what the offset view did before it could tell.
  Nothing -> wholeStack
  where
    towardsViewer = towardsViewerOf basis
    byId = IM.fromList [(unFaceId (faceId f), f) | f <- faces]
    depthOf = layerOf depths
    deepest = maximum (0 : map snd depths)

    -- The layers are walked by number rather than by grouping the faces,
    -- because a picture is what comes of it and a picture has to be in an
    -- order. Costing one pass over the faces and one over the creases per layer
    -- is nothing next to the folding that produced them.
    --
    -- In the order layerDepths gave them, which is the painting order, so
    -- that two faces of one layer are drawn in a defined order and a
    -- reproducible one. The lookup cannot miss -- layerDepths returns
    -- exactly the faces it was handed, once each -- so this skips rather
    -- than growing the error path that 'backToFront' in 'picture' needs for
    -- the same reason and does not use either.
    facesAt d = [f | (fid, e) <- depths, e == d, Just f <- [IM.lookup (unFaceId fid) byId]]

    -- Every face along each edge of the sheet, grouped here rather than
    -- by 'facesAlongEdges', which refuses an edge with three faces on it.
    -- That refusal is right for folding and for stacking, which both ask
    -- \"what is the face across this crease\" and have no answer when there
    -- are two of them. This asks \"which sheets is this crease an edge
    -- of\", which is answerable for any number -- so using the strict one
    -- would let --offset decide that a file the renderer draws happily
    -- without it is unacceptable with it.
    alongEdges =
      M.fromListWith
        (<>)
        [ (edgeKey a b, [faceId f])
          | f <- faces,
            (a, b) <- ringEdges (faceVertexIds f)
        ]

    -- Which layers a crease is drawn in: one per face along it, so the
    -- crease between two faces at different depths is drawn twice, and
    -- the crease between two faces of one layer is drawn once. A crease
    -- along no face at all belongs to no layer, and is drawn where the
    -- paper is, which is layer zero.
    layersOf c = case M.findWithDefault [] (edgeKey (creaseFrom c) (creaseTo c)) alongEdges of
      [] -> [0]
      along -> map depthOf along

    -- Every crease bucketed by the layers it is drawn in, in one pass and
    -- in the order 'picture' draws every crease in, so that a faint reference
    -- line does not paint over the outline of the sheet it is drawn on.
    -- Bucketed rather than filtered per layer because both the sort and the
    -- lookup are the same work for every layer, and there are as many layers
    -- as the model is deep.
    creasesByLayer =
      IM.fromListWith
        (flip (<>))
        [ (d, [creaseLine c])
          | c <- sortOn (creaseOrder . creaseAssignment) creases,
            d <- nub (layersOf c)
        ]

    linesAt d = IM.findWithDefault [] d creasesByLayer

    -- Two fills at most per layer, one per side of the sheet, each
    -- gathering that layer's faces into one area for the reason
    -- 'whatIsVisible' does: faces of one layer abut, and drawn separately
    -- they would be criss-crossed with pale seams where they meet.
    --
    -- Sound only because faces of one layer do not overlap: a pair that
    -- did would have a @faceOrders@ entry between them and so would be at
    -- different depths. That holds for a model folded flat, which is the
    -- only kind this variant is used for.
    mergedFills d =
      [ fill basis colour group
        | (colour, side) <- [(paperFront colours, True), (paperBack colours, False)],
          let group = [f | f <- facesAt d, showsTopSide towardsViewer f == side],
          not (null group)
      ]

    -- One area per face, in the layer's own painting order. For a model
    -- with paper in the air the reasoning above fails: two faces of one
    -- layer are unordered because they do not overlap /on the paper/, and
    -- they can still cover the same patch of page once projected, one
    -- simply being nearer the camera. Merging them into one area throws
    -- away the depth order 'layerDepths' put them in, and the nearer one
    -- stops covering the further one.
    separateFills d =
      [ fill basis (if showsTopSide towardsViewer f then paperFront colours else paperBack colours) [f]
        | f <- facesAt d
      ]

    -- One layer of the picture: its paper, then the fine edges of that
    -- sheet, then whatever of the model itself belongs to it. All three
    -- move together, and a later layer's paper covers all three, which is
    -- what keeps a sheet from drawing its lines over the sheet above it.
    layer fills ink' model d =
      map (move d) (fills d <> mapMaybe (ink' basis) (linesAt d) <> model d)

    -- Every sheet, drawn fine. What survives of a layer is the sliver the
    -- layer above does not cover, and at the model's own line weight a
    -- dozen of those a few points apart add up to a black band rather
    -- than to a stack -- so the stack is drawn as a stack is engraved,
    -- and the drawing proper goes over the top of it.
    stacked model =
      concatMap (layer mergedFills (edgeWith (buriedEdge theme notation)) model) [0 .. deepest]

    wholeStack =
      concatMap (layer separateFills (edgeWith (strokeFor theme notation)) (const [])) [0 .. deepest]

    -- The stretches of the model's own drawing that belong to sheet @d@,
    -- bucketed in one pass for the reason the creases are.
    --
    -- From 'formSheetEdges' rather than 'formEdges', which is the same
    -- answer joined up across the changes of sheet this needs to keep,
    -- and across a face's straight corner, which this therefore draws as
    -- two abutting strokes.
    modelByLayer seen =
      IM.fromListWith
        (flip (<>))
        [ (maybe 0 depthOf nearest, [shape])
          | SheetEdge nearest e _ <- sortOn (creaseOrder . visibleAssignment . sheetEdgeLine) (formSheetEdges seen),
            -- A stretch with paper on neither side belongs to no sheet --
            -- it is a crease bounding nothing -- so it is drawn where the
            -- paper is.
            Just shape <- [edgeOf theme notation basis (stretchLine e)]
        ]

-- | Is the viewer on the @+z@ side of the model?
--
-- Not @== FromReadersSide@, which reads the same and is not: a camera exactly
-- edge on, which shows a flat model as a line, counts as above here, because
-- the faces have to be painted from one side or the other and there is nothing
-- to see either way. 'seenFrom' keeps edge-on apart for the marks that have to
-- know.
seenFromAbove :: Basis -> Bool
seenFromAbove basis = seenFrom basis /= FromOppositeSide

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
    <> mapMaybe (edgeOf theme notation basis . stretchLine) (sortOn (creaseOrder . visibleAssignment) (formEdges seen))
  where
    paperOf side =
      [ map (project basis) piece
        | r <- formRegions seen,
          regionTopSide r == side,
          piece <- regionPieces r
      ]

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
edgeOf theme notation = edgeWith (strokeFor theme notation)

-- | The same, with the choice of stroke handed in.
--
-- The offset view draws the same edges twice over at two weights — once as the
-- stack a model stands on and once as the model — so what varies between them
-- is exactly this function's argument, and nothing else about how an edge
-- becomes a line is written down twice.
edgeWith :: (Assignment -> Maybe Stroke) -> Basis -> (Assignment, V3, V3) -> Maybe Shape
edgeWith strokeOf basis (assignment, from, to) = do
  stroke <- strokeOf assignment
  pure (Polyline stroke [project basis from, project basis to])

-- | Render one frame, letting the frame decide what kind of picture it is and,
-- unless a basis is given, where to look at it from.
--
-- The two decisions are independent. A caller supplying a basis is overriding
-- the camera, and that says nothing about whether the frame is a crease
-- pattern, so the notation is still chosen here. There is no way to override
-- the notation yet because nobody has needed one.
creasePatternAuto :: Theme -> Budget -> View -> Frame -> Either FoldError Diagram
creasePatternAuto theme budget view fr = do
  verts <- frameVertices fr
  let notation = defaultNotationFor (frameClasses fr) verts
  creasePatternFrom theme budget notation (basisFor view verts) fr

-- | The basis a drawing will be made through: the caller's, or the one the
-- geometry picks when the caller has no opinion, turned by however much the
-- caller asked for.
--
-- Exported because anything drawn /alongside/ a diagram has to be projected the
-- same way it was, and arrows are. Two copies of this defaulting rule would
-- stay in step only by hand, and the day they stopped the arrows would land
-- somewhere else on the page with nothing failing.
basisFor :: View -> [V3] -> Basis
basisFor view verts = turnedBy (viewTurn view) (fromMaybe (defaultBasisFor verts) (viewFrom view))

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
--
-- Every arrow it draws has a solid head and states no kind, so it looks the
-- same from either side of the paper: the motions say where paper goes, not
-- whether it was folded towards the reader. 'withKindedArrows' draws arrows of
-- a stated kind.
withArrows :: Theme -> Basis -> [Motion] -> Diagram -> Diagram
withArrows theme basis motions =
  arrowsAlong theme basis [(id, motionFrom m, motionTo m) | m <- motions]

-- | 'withArrows' for arrows that each come with their kind and their two
-- ends, in the frame's coordinates: each drawn by the same rule, projected the
-- same way and skipped when it has no length on the page, with the head its
-- kind gives it ('withKind').
--
-- The kinds are the ones the page sees, as 'withFoldLines'' are: a caller
-- drawing the paper from the opposite side swaps valley and mountain first.
-- So two arrows between the same two points, one from 'withArrows' and one
-- from here, have the same curve, and differ at most in their heads.
withKindedArrows :: Theme -> Basis -> [(ArrowKind, V3, V3)] -> Diagram -> Diagram
withKindedArrows theme basis arrows =
  arrowsAlong theme basis [(withKind kind, a, b) | (kind, a, b) <- arrows]

-- | Each arrow from one point to another, given what to do to its path once
-- 'arrowFor' has made it, appended to the drawing.
arrowsAlong :: Theme -> Basis -> [(ArrowPath -> ArrowPath, V3, V3)] -> Diagram -> Diagram
arrowsAlong theme basis arrows d =
  d {diagramShapes = diagramShapes d <> concatMap arrow arrows}
  where
    arrow (finish, a, b)
      | norm (to ^-^ from) <= negligibleOn d = []
      | otherwise = [Arrow (finish (arrowFor theme from to))]
      where
        from = project basis a
        to = project basis b

-- | Add the fold-here lines for a step to a drawing of the paper before it:
-- each a dashed line between two points, in the positions the paper has
-- before the move, styled by its kind ('foldLineStroke').
--
-- The kinds are the ones the page sees. Which side the page shows is the
-- caller's to know, so a caller drawing the paper from the opposite side swaps
-- valley and mountain before it gets here ("Senbazuru.Render.Steps").
--
-- Appended, so a line is painted over the paper and its creases. Call this
-- before 'withArrows', so that an arrow crossing a line is painted over it:
-- the arrow is the instruction the eye should find first.
--
-- A line lying along a crease is drawn on top of it, and does not read. A
-- folded form draws its creases solid, in the same ink and at the same weight,
-- so the solid line shows through every gap in the dash and the two read as
-- one solid line; over a crease of the other kind the two dashes blend. A book
-- draws the instruction in place of the crease under it, which appending
-- cannot do. No page draws a line yet, and the page that will, a run's, puts
-- every line along a hinge that is usually a crease already, so S33 (#643)
-- settles it before then.
--
-- The extent is left alone, as 'withArrows' leaves it. A line whose two ends
-- land on one point of the page, a hinge seen end on, gets nothing, by the
-- rule 'withArrows' uses for an arrow, and so does an unfold, which has no
-- line ('foldLineStroke').
withFoldLines :: Theme -> Basis -> [(ArrowKind, V3, V3)] -> Diagram -> Diagram
withFoldLines theme basis foldLines d =
  d {diagramShapes = diagramShapes d <> concatMap line foldLines}
  where
    line (kind, a, b) = case foldLineStroke theme kind of
      Just stroke
        | norm (to ^-^ from) > negligibleOn d -> [Polyline stroke [from, to]]
      _ -> []
      where
        from = project basis a
        to = project basis b

-- | How short a mark can be on this drawing before it is taken to have no
-- length: a millionth of the drawing's larger side, and never less than a
-- millionth of a unit. 'withArrows' and 'withFoldLines' share it, so an arrow
-- and a line between the same two points are drawn or skipped together.
negligibleOn :: Diagram -> Double
negligibleOn d = 1e-6 * max 1 (max w h)
  where
    V2 w h = boxSize (diagramExtent d)
