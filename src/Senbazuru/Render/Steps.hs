-- |
-- Module      : Senbazuru.Render.Steps
-- Description : A whole folding sequence as one page of numbered figures.
--
-- Joins the three pieces a page of instructions needs: "Senbazuru.Origami.Step"
-- for what each fold does, "Senbazuru.Render.CreasePattern" for drawing the
-- paper, and "Senbazuru.Diagram.Layout" for putting the figures side by side.
--
-- It lives in the library rather than in the command line because it is a
-- decision, not plumbing — and because a copy of it in the test suite is how
-- the mixed-camera bug below survived a golden test that was meant to catch it.
--
-- == One camera for the whole page
--
-- Every figure is drawn through __one basis__, chosen from every frame's
-- vertices together rather than each frame's own.
--
-- Letting each figure choose is the mistake, and it is a quiet one. A sequence
-- that starts flat and ends with the paper out of the plane would draw its
-- early steps from above and its later ones isometrically, so the reader is
-- moved around the model between figures without being told. Worse, the shared
-- extent that keeps every figure at one scale would then be a union of boxes
-- measured in different projections, and an isometric box is wider than the
-- top-down box of the same sheet — so the folded model would come out /larger/
-- than the sheet it came from, which is the exact thing
-- "Senbazuru.Diagram.Layout" exists to prevent.
--
-- The /notation/ is still chosen per frame, and that is not the same question:
-- a crease pattern's creases are instructions and a folded form's are edges,
-- however you are looking at either.
--
-- Which side of the paper the page shows ('pageSide') is read off that same
-- camera, chosen in one place ('pageCamera'). Today no file can change the
-- answer: a view that names a camera gets that camera's side, and the two
-- cameras a page chooses for itself, from above and isometric, both look down
-- onto the reader's side. The one place still matters. 'pageSide' refuses
-- exactly the frames choosing the camera refuses, and a default that one day
-- looked from below or edge-on could not split the page from the side it
-- reports.
--
-- == One note for each figure
--
-- A book prints more beside a figure than the paper: the arrow for the next
-- fold, the step's instruction, a mark for turning the model over. Two frames
-- cannot say most of that, so it reaches the page as a /step note/, one for
-- each figure, from whoever knows it ('stepFigures'). A note says six
-- things so far: which arrows the figure carries, inferred to the next
-- figure or given, which fold-here lines to draw on it, what caption to
-- print under it, whether the reader turns the model over or round before
-- the next figure, which draws the turn-over loop or the rotate mark and no
-- arrow inferred across the turn ('PresentationChange'), and which earlier
-- figures its step repeats, which draws the repeat range ('noteRepeat');
-- and which marked points of the paper to label where they show
-- ('noteMarks', 'markLabels').
--
-- A rotate mark and a repeat range stand above the figure's top-right
-- corner, clear of its step number, which stands at its top-left, and of
-- the paper ('rotateMark', 'repeatMark'). Both carry words, the amount and
-- the range, drawn by the backend as part of the glyph: a mark's words are
-- its glyph's, never a 'Senbazuru.Diagram.Label'.
--
-- == Kinds as the page sees them
--
-- An arrow or a fold-here line, the dashed line a book draws where the paper
-- is about to fold, can come with its kind, valley, mountain or unfold,
-- stated as the move was written: from the reader's side. A valley fold seen
-- from behind the paper is a mountain fold, so a page that shows the
-- opposite side swaps the two before drawing ('asSeen'), in an arrow's head
-- and a line's dash alike; an unfold is an unfold from either side.
--
-- An arrow inferred from two frames alone ('InferArrows') states no kind,
-- and keeps the solid head from every side. The frames say where paper went,
-- not whether it was folded towards the reader, and pages drawn from below
-- with such arrows already exist and must not change.
--
-- A page seen edge on, looking along the paper's plane, shows neither side,
-- so it draws each kind as stated and puts an eye over every figure's step
-- number to say so ('edgeOnMark'). Every figure, because a mark on one alone
-- would read as that figure's own view; and only when some figure states a
-- valley or a mountain, or turns the model round, the marks whose look
-- depends on the side, so a page of inferred arrows, as every
-- @render --steps@ page is, gets none. Edge on
-- is a fact about the camera alone, its line of sight lying exactly in the
-- plane ("Senbazuru.Render.Camera", @seenFrom@): a model standing in the air
-- seen from the front is edge on too, and a camera tilted by a hair is not.
--
-- The kind is never read off the crease a line lies along. In
-- @examples/quarter-fold-steps.fold@ the second fold is one valley fold seen
-- from above, yet it folds one crease lettered @V@ and one lettered @M@,
-- because the first fold turned the second crease's paper upside down. A line
-- styled by the letters would be half valley and half mountain.
--
-- 'stepFigures' draws each figure with its note and hands it back with its
-- caption, and lays out no page, because laying out a caption needs the
-- scale the page draws at, which is the page's to know
-- ("Senbazuru.Diagram.Page", @fitPage@) and which 'stepPage' does not take.
-- So the drawing, the costly part, is done in one place and once, and two
-- pages of the same figures differ only in how they are laid out: 'stepPage'
-- lays them out with 'gridOf', and a run's page ("Senbazuru.Render.Sequence")
-- fits them to a page with their captions under them.
--
-- 'stepPage' is 'stepFigures' with the same note on every figure, picked by
-- its 'Bool' ('noteFor'), rather than a second way of drawing the same
-- figures, which would be free to drift from the first as the test suite's
-- copy did. 'noteFor' gives no figure a caption, so 'stepPage' has none to
-- leave out.
--
-- Nothing here reads a frame's @frame_title@, so @render --steps@ never draws
-- one, because a file cannot say what its titles are.
-- @examples/quarter-fold-steps.fold@ titles its half-folded state \"Step 2:
-- folded in half\", naming the state, while a run of the same fold from its
-- source, @test/fixtures/quarter-fold.foldseq@, titles that state with the
-- next instruction, step @quarter@'s caption, \"Fold the top half down in
-- front, onto the bottom.\" Drawn under its figure, one of the two would be
-- wrong whichever this assumed.
-- Words under a figure have to arrive in its note, from a caller that knows
-- which kind its titles are, as a run does ("Senbazuru.Render.Sequence").
--
-- The note's constructor is not exported. Every note made outside this
-- module starts as 'inferNote' or 'silentNote' and changes the fields it
-- means to, so a field added later is filled, for every caller that does not
-- set it, by those two definitions. Every page @render --steps@ and the
-- studies draw comes through 'stepPage', whose notes 'noteFor' picks from the
-- same two, and a run's page starts each of its notes from 'silentNote', so a
-- default that changed those pages would have to be in one of the three.
module Senbazuru.Render.Steps
  ( -- * A page of steps
    stepPage,
    stepFigures,
    StepError (..),

    -- * What each figure carries
    StepNote,
    noteArrows,
    noteFoldLines,
    notePresentation,
    noteRepeat,
    noteMarks,
    noteCaption,
    Arrows (..),
    FoldLines (..),
    PresentationChange (..),
    inferNote,
    silentNote,
    noteFor,

    -- * Which side the page shows
    pageSide,
  )
where

import Data.Bifunctor (first)
import Data.Either (fromRight)
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Diagram (Diagram (..), Glyph (..), Shape (..), glyphReach, solid)
import Senbazuru.Diagram.Layout (Grid, gridOf)
import Senbazuru.Diagram.Style (ArrowKind (..), Theme (..))
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Crossings (withPlanarFaces)
import Senbazuru.Fold.Faces (toleranceOf)
import Senbazuru.Fold.Query (FoldError, frameVertices)
import Senbazuru.Fold.Types (Frame (..))
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.Polygon (distanceOutside, distanceToSegment, edges, insideRing)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace (VectorSpace (..))
import Senbazuru.Origami.Stacking (Budget, layerOrderFor)
import Senbazuru.Origami.Step (Motion (..), creasesToCome, motionsAcross)
import Senbazuru.Origami.Surface (Sample (..), surfaceFromFrame, surfacePanelSamples)
import Senbazuru.Origami.Visible (Region (..), VisibleForm (..), visibleForm)
import Senbazuru.Render.Camera (Basis, SeenFrom (..), View, project, seenFrom)
import Senbazuru.Render.CreasePattern
  ( basisFor,
    creasePatternFrom,
    defaultNotationFor,
    withArrows,
    withFoldLines,
    withKindedArrows,
  )

-- | Something wrong with one frame of a sequence, and which frame it was.
--
-- The index matters. Told only that a file will not draw, someone holding a
-- twenty-step sequence has to bisect it by hand.
data StepError = StepError
  { stepFrame :: !Int,
    stepReason :: !FoldError
  }
  deriving stock (Eq, Show)

-- | The frame number, then the frame's own complaint.
--
-- The index leads, because it is the part the reader does not have: they are
-- holding a file, not a frame, and a message that opens with a face number
-- makes them count steps to find out whose face it is.
--
-- The CLI does not use this, and cannot: it says @cannot render frame 2 of
-- a.fold: …@, with the file name /between/ the index and the reason, which no
-- ordering of one method's output produces. So it takes the error apart and
-- writes those words itself, and this instance is what a caller holding a
-- 'StepError' and no file name gets. Two spellings of one message is a real
-- cost; the alternative was to change what @senbazuru render --steps@ prints,
-- which is not this change's to do.
instance Explain StepError where
  explain (StepError i err) = "frame " <> tshow i <> ": " <> explain err

-- | What a figure carries besides the paper. See the module header for why
-- its constructor is not exported.
data StepNote = StepNote
  { -- | Whether the figure carries the fold that takes it to the next one.
    noteArrows :: !Arrows,
    -- | The lines on the figure where its paper is about to fold.
    noteFoldLines :: !FoldLines,
    -- | The words printed under the figure, if any: the instruction of the
    -- step that starts from it.
    noteCaption :: !(Maybe Text),
    -- | What the reader does to the whole model before the next figure, if
    -- anything: turn it over, or turn it round on the table. Drawn as a mark
    -- on this figure, and the arrows this figure would infer to the next are
    -- not drawn ('PresentationChange').
    notePresentation :: !(Maybe PresentationChange),
    -- | The figures whose steps the step starting from this figure repeats,
    -- if any: their numbers as the page numbers them, from 1, first and last.
    -- Drawn as a box holding the range above the figure ('repeatMark'), and
    -- drawn as given: a hand-written note may name figures that are not on
    -- the page, or a range backwards, and the page says what it was told.
    noteRepeat :: !(Maybe (Int, Int)),
    -- | The marked points to label on this figure where their paper shows:
    -- each a name and a point of the paper as it lay on the sheet, its
    -- material point, not a place on the page, since two layers folded onto
    -- one place are two points ('markLabels'). Drawn as a dot with the name
    -- beside it, and not at all where the paper is hidden, not lying flat,
    -- seen edge on, or without material coordinates.
    noteMarks :: ![(Text, V2)]
  }
  deriving stock (Eq, Show)

-- | Which arrows a figure carries.
data Arrows
  = -- | The ones 'motionsAcross' finds from this figure's frame to the next
    -- figure's, as @render --steps --arrows@ draws them: between two states of
    -- one crease pattern, or across a crease pattern the next state grows,
    -- matched by where each point lay on the sheet. They state no kind, so
    -- each has the solid head from either side of the paper.
    InferArrows
  | -- | The same arrows, each of this kind as the move was written, from the
    -- reader's side, and drawn as the page sees it ('asSeen'). None on the
    -- last figure, as for 'InferArrows': there is no next frame to infer from.
    InferArrowsAs !ArrowKind
  | -- | These, each a kind as the move was written and its two ends, in the
    -- frame's own coordinates, drawn as the page sees each kind. Drawn on the
    -- figure whichever place it has, the last included, since nothing is
    -- inferred, and projected as an inferred arrow between the same two
    -- points is, so the two differ at most in their heads.
    GivenArrows ![(ArrowKind, V3, V3)]
  | -- | None.
    NoArrows
  deriving stock (Eq, Show)

-- | Which fold-here lines a figure carries: the dashed lines a book draws on
-- the figure before a fold, where the paper is about to fold.
data FoldLines
  = -- | None.
    NoFoldLines
  | -- | These, each a kind as the move was written, from the reader's side,
    -- and its two ends, in the frame's own coordinates: where the paper is
    -- on this figure, before the move. Drawn on the figure whichever place
    -- it has, the last included, since nothing is inferred; drawn as the page
    -- sees each kind ('asSeen'); and drawn not at all for an unfold, which
    -- has no line ("Senbazuru.Diagram.Style", @foldLineStroke@).
    GivenFoldLines ![(ArrowKind, V3, V3)]
  | -- | The creases the next figure's frame adds, each where the paper is on
    -- this figure ('creasesToCome'), all of this kind as the move was
    -- written, drawn as the page sees it. None on the last figure, which has
    -- no next frame, and none between two states of one crease pattern,
    -- which add no crease; a fold along a crease the paper already has gets
    -- none here, and a run's page draws it from its record's hinge instead
    -- (owner decision 74; "Senbazuru.Render.Sequence"). Drawn on a
    -- figure the reader turns, unlike inferred arrows, since a crease to come
    -- is placed on this figure by the point of paper it runs through, which
    -- a turn does not move. A crease an older one crosses comes as its
    -- pieces, so its dash starts again at each cut.
    InferFoldLines !ArrowKind
  deriving stock (Eq, Show)

-- | A change of presentation: the reader moving the whole model, not folding
-- it, between this figure and the next.
--
-- The page draws it as a mark and does not infer arrows across it. Two frames
-- that differ by a turn and nothing else already infer none, since the whole
-- model moving is no fold (@motionsBetween@); but a step may fold and then
-- turn, and the arrows inferred across that pair would follow every face to
-- where the turn left it, which no reader folding along could follow. So the
-- mark stands for the pair, and a fold's arrow on it has to be given
-- ('GivenArrows'), as a run's records give it ("Senbazuru.Render.Sequence").
data PresentationChange
  = -- | Turned over about the line through this point in this direction,
    -- both in the frame's own coordinates: the turn's axis, as
    -- "Senbazuru.Sequence.Record"'s @presentationAxis@ gives it for a run.
    -- Drawn as the turn-over loop below the figure ('turnOverMark').
    PageTurnedOver !V3 !V3
  | -- | Turned round on the table by this many eighths of a turn,
    -- anticlockwise as the reader sees the model and signed so, about the
    -- line up through this point, in the frame's own coordinates: the
    -- turn's axis as @presentationAxis@ gives it, whose direction is always
    -- towards the reader. Drawn as the rotate mark above the figure
    -- ('rotateMark'), its sense as the page sees it.
    --
    -- The point is carried, and not read: the mark stands at the figure's
    -- corner, since at the point, the model's middle, it would cover the
    -- folds. It is kept so that a run's record maps onto this as it does
    -- onto 'PageTurnedOver', point and direction both, and a later page
    -- that wants the axis has it.
    PageRotated !Int !V3
  deriving stock (Eq, Show)

-- | Arrows inferred from the frames, and nothing else: no fold-here line and
-- no caption.
--
-- No fold-here line. Two frames do say which creases a fold turned, by
-- their fold angles, but not the line's kind: the quarter fold's second fold
-- is one valley fold that turns a @V@ crease and an @M@ crease, as the module
-- header says, and a frame carries no move to take the kind from. Nor is
-- there a new crease to draw: the quarter and blintz folds run along creases
-- the sheet already has. And @render --steps@ draws its pages from this note,
-- so a line here would change every arrowed page.
inferNote :: StepNote
inferNote = StepNote {noteArrows = InferArrows, noteFoldLines = NoFoldLines, noteCaption = Nothing, notePresentation = Nothing, noteRepeat = Nothing, noteMarks = []}

-- | The paper and nothing else.
silentNote :: StepNote
silentNote = StepNote {noteArrows = NoArrows, noteFoldLines = NoFoldLines, noteCaption = Nothing, notePresentation = Nothing, noteRepeat = Nothing, noteMarks = []}

-- | The note 'stepPage' gives every figure: 'inferNote' with arrows asked for,
-- 'silentNote' without.
noteFor :: Bool -> StepNote
noteFor True = inferNote
noteFor False = silentNote

-- | Every frame of a file drawn as a figure, with its note, in order, each
-- with the caption its note gives it: the figures of a page of steps, before
-- they are laid out.
--
-- Empty when the file has no frame with any geometry in it — which is not the
-- same as having no frames. FOLD keeps its file metadata in the same object
-- as the first frame, so a file that puts every step in @file_frames@ has a key
-- frame holding a title and nothing else. That is not a step, and skipping it
-- is why this takes frames rather than a count. Its note is skipped with it,
-- so every other note stays with its own frame, and a frame that will not draw
-- is still named by its place in the list.
stepFigures ::
  Theme ->
  -- | How hard to look for a layer order, for the frames that need one.
  Budget ->
  -- | Where to look from and which way up, with the camera chosen from the
  -- whole sequence when the view does not name one.
  View ->
  [(Frame, StepNote)] ->
  Either StepError [(Diagram, Maybe Text)]
stepFigures theme budget view notes = do
  (resolved, basis) <- pageCamera view notes
  -- Numbered by their place in the sequence too, so "the next step" skips
  -- over a metadata-only key frame rather than tripping on it.
  let order = [fr | (_, fr, _, _) <- resolved]
  let side = seenFrom basis
      -- Seen edge on, every figure says so, when any figure states a kind
      -- that depends on the side the page shows: one figure marked alone
      -- would read as that figure's own view.
      marked = side == EdgeOn && or [statesSidedKind note (position + 1 < length order) | (position, (_, _, note, _)) <- zip [0 :: Int ..] resolved]
  traverse (figure basis side marked order) (zip [0 ..] resolved)
  where
    figure basis side marked order (position, (i, fr, note, verts)) = do
      paper <-
        first
          (StepError i)
          (creasePatternFrom theme budget (defaultNotationFor (frameClasses fr) verts) basis fr)
      -- Lines before arrows, so an arrow is painted over a line it crosses.
      lined <- case (noteFoldLines note, drop (position + 1) order) of
        (NoFoldLines, _) -> pure paper
        (GivenFoldLines foldLines, _) ->
          pure (withFoldLines theme basis [(asSeen side kind, a, b) | (kind, a, b) <- foldLines] paper)
        (InferFoldLines kind, next : _) -> do
          coming <- first (StepError i) (creasesToCome fr next)
          pure (withFoldLines theme basis [(asSeen side kind, a, b) | (_, a, b) <- coming] paper)
        (InferFoldLines _, []) -> pure paper
      let unpresented = isNothing (notePresentation note)
      arrowed <- case (noteArrows note, drop (position + 1) order) of
        (InferArrows, next : _) | unpresented -> do
          motions <- first (StepError i) (motionsAcross fr next)
          pure (withArrows theme basis motions lined)
        (InferArrowsAs kind, next : _) | unpresented -> do
          motions <- first (StepError i) (motionsAcross fr next)
          pure (withKindedArrows theme basis [(asSeen side kind, motionFrom m, motionTo m) | m <- motions] lined)
        (GivenArrows arrows, _) ->
          pure (withKindedArrows theme basis [(asSeen side kind, a, b) | (kind, a, b) <- arrows] lined)
        -- The last figure of a sequence is the finished model, and a book draws
        -- no arrow on it, whatever its note asks it to infer; a figure the
        -- reader turns infers none across the turn ('PresentationChange').
        (InferArrows, _) -> pure lined
        (InferArrowsAs _, _) -> pure lined
        (NoArrows, _) -> pure lined
      let presented = case notePresentation note of
            Nothing -> arrowed
            Just (PageTurnedOver point direction) ->
              arrowed {diagramShapes = diagramShapes arrowed <> [turnOverMark theme basis paper point direction]}
            Just (PageRotated eighths _) ->
              arrowed {diagramShapes = diagramShapes arrowed <> rotateMark theme marked paper (asSeenTurn side eighths)}
          repeated = case noteRepeat note of
            Nothing -> presented
            Just (from, to) ->
              presented {diagramShapes = diagramShapes presented <> [repeatMark theme marked paper (rotating note) from to]}
          labelled = case noteMarks note of
            [] -> repeated
            marks -> repeated {diagramShapes = diagramShapes repeated <> markLabels theme budget basis side fr marks}
          drawn
            | marked = labelled {diagramShapes = diagramShapes labelled <> [edgeOnMark theme paper]}
            | otherwise = labelled
      pure (drawn, noteCaption note)

-- | Whether a note states a kind whose look depends on the side the page
-- shows: a valley or a mountain, in its arrows or its fold-here lines.
-- An unfold looks the same from either side, so it does not count, nor does
-- an empty list, nor arrows inferred on the last figure or across a turn,
-- which draw none. A rotate counts: its arrow turns one way seen from the
-- reader's side and the other from behind.
statesSidedKind :: StepNote -> Bool -> Bool
statesSidedKind note hasNext = arrows || foldLines || rotates
  where
    -- A rotate's sense is the side's too, as the owner chose on 2026-11-08.
    rotates = rotating note
    -- Named one by one, so a kind added later, such as a push, has to be
    -- placed here by whoever adds it.
    sided = \case
      ValleyArrow -> True
      MountainArrow -> True
      UnfoldArrow -> False
      ValleyAndUnfoldArrow -> True
      MountainAndUnfoldArrow -> True
    arrows = case noteArrows note of
      InferArrowsAs kind -> hasNext && isNothing (notePresentation note) && sided kind
      GivenArrows given -> any (\(kind, _, _) -> sided kind) given
      InferArrows -> False
      NoArrows -> False
    foldLines = case noteFoldLines note of
      GivenFoldLines given -> any (\(kind, _, _) -> sided kind) given
      InferFoldLines kind -> hasNext && sided kind
      NoFoldLines -> False

-- | The labels of marked points on a figure: for each mark, a dot at every
-- place its point of paper shows, and its name beside the dot, toward the
-- middle of the piece of paper it shows on, clear of the dot however long
-- the name, so that at a corner it leans onto the paper (the owner's
-- choices of 2026-11-08). A name wider than the paper there still runs past
-- its edge, and nothing makes room for it.
--
-- A mark names a material point, where the paper lay on the sheet, because a
-- place on the page cannot tell two layers folded onto it apart: on the
-- quarter fold's state 1, the paper at (3/4, 3/4) and at (1/4, 3/4) lie at
-- one place, and only the first shows from above. So the point is carried to
-- the page through each face of the paper that holds it ('shownPositions'),
-- and labelled only where that face is the one the viewer sees there.
--
-- Nothing is labelled, and nothing refused, on a figure seen edge on, where
-- no layer is nearer than another; on one whose paper does not lie flat, or
-- whose layers cannot be ordered, or has a face that is not convex, which
-- the visible form refuses; or on one without material coordinates. A label
-- that lands on the step number, at the figure's top-left corner, stays
-- there: the figure is drawn before the page knows where its number sits.
markLabels :: Theme -> Budget -> Basis -> SeenFrom -> Frame -> [(Text, V2)] -> [Shape]
markLabels theme budget basis side fr marks
  | side == EdgeOn = []
  | otherwise = case shownPositions budget (side /= FromOppositeSide) fr of
      Nothing -> []
      Just shown -> concat [labelAt name (project basis place) (project basis toward) | (name, point) <- marks, (place, toward) <- shown point]
  where
    -- 11 and 3.6 page units at the default theme: the name a little smaller
    -- than the step number, so it does not read as one, and the dot a
    -- fraction of the glyph size.
    -- Multiplied first, so the default theme's 14 and 24 give 11 and 3.6
    -- exactly.
    labelSize = themeLabelSize theme * 11 / 14
    dotSize = themeGlyphSize theme * 3 / 20
    labelAt name at toward =
      [ Symbol (solid (themeInk theme) (themeCreaseWidth theme)) dotSize at PointDot,
        Offset (V2 (nudge * ux - 0.5 * wide) (nudge * uy + 0.35 * labelSize)) (Label (themeInk theme) labelSize at name)
      ]
      where
        -- Toward the middle of the piece of paper the place shows on, on the
        -- page, whose y grows downwards; straight down from a point at that
        -- middle itself. The piece is convex, so its middle is on the paper,
        -- which the middle of the figure's box is not at an acute corner.
        V2 dx dy = toward ^-^ at
        len = sqrt (dx * dx + dy * dy)
        V2 ux uy = if len > 0 then V2 (dx / len) (negate dy / len) else V2 0 1
        -- The name, at the width and height a caption's words are estimated
        -- at, is centred far enough along that direction that its box clears
        -- the dot by 2 page units however long the name is: the dot's radius,
        -- the gap, and the box's half extent along the direction. A name
        -- wider than the paper there still runs past its edge.
        wide = 0.55 * labelSize * fromIntegral (T.length name)
        tall = 10.8 / 14 * labelSize
        nudge = 0.5 * dotSize + 2 + abs ux * 0.5 * wide + abs uy * 0.5 * tall

-- | For a flat figure, where each point of the paper shows to a viewer
-- above it, or below it: for a material point, the positions of the faces
-- holding it at which those faces are the paper the viewer sees, each place
-- once, each with the middle of the visible piece of paper it shows on, for
-- the label to lean toward. 'Nothing' when the figure has no such answer: its paper does not lie
-- flat, its layers cannot be ordered within the budget, a face is not
-- convex, or it has no material coordinates.
--
-- A face holds a point when its ring on the sheet does, its outline
-- included: inside it, or within the sheet's tolerance of one of its edges,
-- as the runner judges an anchor. Inside alone would hold no point on an
-- outline, so it would never label a corner. The point is carried to the
-- face's position by the face's own affine map, sheet to place, found from
-- the three of its corners spanning the widest triangle on the sheet. And
-- the face is seen there when the visible region of that face covers the
-- place, again within the tolerance, since a corner lies on a region's edge.
shownPositions :: Budget -> Bool -> Frame -> Maybe (V2 -> [(V3, V3)])
shownPositions budget fromAbove given = do
  -- A file that records no faces has them rebuilt from its creases, as
  -- anything needing paper rather than lines does.
  fr <- if null (facesVertices given) then either (const Nothing) Just (withPlanarFaces given) else Just given
  orders <- fromRight Nothing (layerOrderFor budget fr)
  form <- either (const Nothing) Just (visibleForm fromAbove fr orders)
  sheet <- either (const Nothing) Just (surfaceFromFrame fr)
  panels <- either (const Nothing) Just (surfacePanelSamples sheet)
  faces <- traverse (\(fid, samples) -> (,) fid <$> traverse (\smp -> (,) <$> sampleMaterial smp <*> pure (position smp)) samples) panels
  let room = toleranceOf [m | (_, corners) <- faces, (m, _) <- corners]
      -- The middle of the first piece of the face's visible region covering
      -- the place, or 'Nothing' when none does.
      seen fid place = case [piece | region <- formRegions form, regionFace region == fid, piece <- regionPieces region, distanceOutside (map flat piece) (flat place) <= room] of
        piece@(_ : _) : _ -> Just ((1 / fromIntegral (length piece)) *^ foldr (^+^) (V3 0 0 0) piece)
        _ -> Nothing
      holds corners m = let ring = map fst corners in insideRing room ring m || any ((<= room) . (`distanceToSegment` m)) (edges ring)
      shown m = nubPlaces room [(place, toward) | (fid, corners) <- faces, holds corners m, Just place <- [carry corners m], Just toward <- [seen fid place]]
  pure shown
  where
    flat (V3 x y _) = V2 x y
    nubPlaces room = foldr (\p kept -> if any (near room (fst p) . fst) kept then kept else p : kept) []
    near room (V3 a b c) (V3 d e f) = sqrt ((a - d) ^ (2 :: Int) + (b - e) ^ (2 :: Int) + (c - f) ^ (2 :: Int)) <= room

-- | A point of the sheet carried to a face's position by the face's affine
-- map: its barycentric coordinates in the triangle of three of the face's
-- corners that spans the most area on the sheet, applied to those corners'
-- positions. 'Nothing' for a face whose corners span no area.
carry :: [(V2, V3)] -> V2 -> Maybe V3
carry corners m = case [(area a b c, (a, b, c)) | (a, b, c) <- triples corners] of
  [] -> Nothing
  first' : rest ->
    let (best, ((ma, pa), (mb, pb), (mc, pc))) = foldr widest first' rest
        (wb, wc) = barycentric ma mb mc m
     in if best <= 0 then Nothing else Just (pa ^+^ (wb *^ (pb ^-^ pa)) ^+^ (wc *^ (pc ^-^ pa)))
  where
    area (V2 ax ay, _) (V2 bx by, _) (V2 cx cy, _) = abs ((bx - ax) * (cy - ay) - (cx - ax) * (by - ay))
    triples xs = [(a, b, c) | (i, a) <- zip [0 :: Int ..] xs, (j, b) <- zip [0 ..] xs, i < j, (k, c) <- zip [0 ..] xs, j < k]
    widest a b = if fst a >= fst b then a else b
    barycentric (V2 ax ay) (V2 bx by) (V2 cx cy) (V2 px py) =
      let d = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
       in (((px - ax) * (cy - ay) - (cx - ax) * (py - ay)) / d, ((bx - ax) * (py - ay) - (px - ax) * (by - ay)) / d)

-- | Whether a note turns the model round by an amount the rotate mark draws:
-- 1 to 7 eighths either way, the turns a run makes.
rotating :: StepNote -> Bool
rotating note = case notePresentation note of
  Just (PageRotated eighths _) -> eighths /= 0 && eighths >= -7 && eighths <= 7
  _ -> False

-- | A turn on the table as the page sees it: anticlockwise from the reader's
-- side is clockwise from the other, so a page that shows the opposite side
-- negates it, as 'asSeen' swaps valley and mountain; seen edge on, it is
-- drawn as stated, and the eye says so.
asSeenTurn :: SeenFrom -> Int -> Int
asSeenTurn FromOppositeSide eighths = negate eighths
asSeenTurn _ eighths = eighths

-- | The rotate mark for a figure turned round by these eighths as the page
-- sees them, above the figure's top-right corner: the owner's choices of
-- 2026-11-08, 06's sketch at the theme's glyph size, on the line the edge-on
-- eye stands on but at the right end. Its bottom is 1 page unit above the
-- highest the step number's ink reaches, 10.8 of the number's 14 above its
-- baseline, which is never above the figure's top, so it clears the number
-- at any scale; and above the figure it covers no paper and meets no
-- turn-over loop. "Senbazuru.Diagram.Layout" leaves room above the row for
-- it (@markRise@). None for a turn of no eighths or of eight or more, which
-- draws nothing.
rotateMark :: Theme -> Bool -> Diagram -> Int -> [Shape]
rotateMark theme eyed paper eighths
  | eighths == 0 || eighths < -7 || eighths > 7 = []
  | otherwise =
      [Offset (V2 (negate across) (negate (clear + up))) (Symbol (solid (themeInk theme) (themeArrowWidth theme)) size (V2 right top) glyph)]
  where
    glyph = RotateMark eighths
    size = themeGlyphSize theme
    V2 across up = glyphReach size glyph
    clear = markClearance theme eyed
    Box _ (V2 right top) = diagramExtent paper

-- | The repeat mark for a figure whose step repeats these figures' steps: the
-- box holding the range, on the rotate mark's line, its bottom with the
-- rotate mark's, at its right end when the figure has no rotate mark and to
-- its left, a quarter of the glyph size apart, when it has.
repeatMark :: Theme -> Bool -> Diagram -> Bool -> Int -> Int -> Shape
repeatMark theme eyed paper besideRotate from to =
  Offset (V2 (negate (beside + across)) (negate (clear + up))) (Symbol (solid (themeInk theme) (themeCreaseWidth theme)) size (V2 right top) glyph)
  where
    glyph = RepeatMark from to
    size = themeGlyphSize theme
    V2 across up = glyphReach size glyph
    V2 rotateAcross _ = glyphReach size (RotateMark 1)
    beside = if besideRotate then 2 * rotateAcross + 0.25 * size else 0
    clear = markClearance theme eyed
    Box _ (V2 right top) = diagramExtent paper

-- | How far above a figure's top the marks over its corner start, in page
-- units: the most the step number's ink rises above the figure's top, 10.8 at
-- the number's size of 14 and as much again in proportion at any other, and
-- a page unit to spare. On a figure that carries the edge-on eye, above the
-- eye's top instead, 2.2 of the number's size: the eye stands over the
-- number at the figure's left end and these marks at its right, and on a
-- figure narrower on the page than the two together they would meet, which
-- the figure, drawn before the page knows its scale, cannot tell. One line
-- higher, they meet nothing at any width.
markClearance :: Theme -> Bool -> Double
markClearance theme eyed
  | eyed = 2.2 * themeLabelSize theme + 1
  | otherwise = 10.8 / 14 * themeLabelSize theme + 1

-- | The eye that marks a figure seen edge on, centred above the figure's step
-- number. "Senbazuru.Diagram.Layout" puts the number's baseline at the
-- figure's top-left corner, a little below it when the page has any height,
-- so the eye stands at that corner and is moved up the page in page units:
-- half its size to the right, over the number, and 1.7 of its size up, clear
-- of the number's glyph. Moved by an 'Offset' rather than placed in model
-- units because a figure seen edge on has no height to place it in, and
-- because the number it sits over is a fixed size in print. It is the step
-- number's own size, @themeLabelSize@, not the theme's glyph size, since it
-- is sized to sit over the number (the owner's choice of 2026-11-07), and
-- drawn at a crease's weight.
edgeOnMark :: Theme -> Diagram -> Shape
edgeOnMark theme paper =
  Offset (V2 (0.5 * size) (-1.7 * size)) (Symbol (solid (themeInk theme) (themeCreaseWidth theme)) size (V2 left top) EdgeOnMark)
  where
    size = themeLabelSize theme
    Box (V2 left _) (V2 _ top) = diagramExtent paper

-- | The turn-over loop for a figure the reader turns over about the line
-- through this point in this direction: below the figure, lying across the
-- turn's axis as the page shows it.
--
-- R-06-11 anchors the loop where the projected axis leaves the figure's own
-- extent, at its lower end, or its right end when the axis runs across the
-- page ('placeLoop'). Drawn there, the stem lies along the paper's edge and
-- vanishes into it, so the loop is moved on past that point, away from the
-- figure, by three quarters of its size, in page units: below the figure for
-- a left-right turn seen from above, as books draw it (the owner's choice of
-- 2026-11-07). Its vector points back into the figure, so the loop rises
-- towards the paper it stands for. "Senbazuru.Diagram.Layout" leaves room
-- for it where it lies past its figure's cell, below the row for an axis up
-- the page and beside the column for one across it (@markDrop@,
-- @markRight@), so it never lies across a neighbour.
-- The theme's glyph size sizes it, and it is drawn at an arrow's weight,
-- since it is an arrow.
--
-- The nudge is in page axes, whose @y@ grows down the page, so the inward
-- vector's @y@ is negated in it: (0, 1) inward moves the loop down.
turnOverMark :: Theme -> Basis -> Diagram -> V3 -> V3 -> Shape
turnOverMark theme basis paper point direction =
  Offset (V2 (negate ix * away) (iy * away)) (Symbol (solid (themeInk theme) (themeArrowWidth theme)) size anchor (TurnOverLoop inward))
  where
    size = themeGlyphSize theme
    away = 0.75 * size
    (anchor, inward@(V2 ix iy)) = placeLoop (diagramExtent paper) (project basis point) (unitProjection basis direction)

-- | A direction as the page shows it, as a unit vector on the page.
-- 'Nothing' when its projection, per unit of its length in the model, is
-- shorter than 1e-6, an axis seen end on, which R-06-11 draws as if it ran
-- up the page, and when the direction has no length or is not a number.
--
-- A direction has no size of its own, so R-06-11's cut-off, a millionth of
-- the figure's larger side, which is a length, is taken per unit of the
-- direction's length: the same test on a direction as long as the figure.
unitProjection :: Basis -> V3 -> Maybe V2
unitProjection basis direction
  | isNaN biggest || isInfinite biggest || biggest <= 0 = Nothing
  | isNaN shown || shown <= 1e-6 = Nothing
  | otherwise = Just (V2 (x / shown') (y / shown'))
  where
    V3 dx dy dz = direction
    -- Divided by its largest part first, so that a direction too long or too
    -- short to square keeps its length: only its direction counts.
    biggest = maximum [abs dx, abs dy, abs dz]
    scaled = V3 (dx / biggest) (dy / biggest) (dz / biggest)
    V3 sx sy sz = scaled
    len = sqrt (sx * sx + sy * sy + sz * sz)
    V2 x y = project basis scaled
    shown' = sqrt (x * x + y * y)
    shown = shown' / len

-- | Where the turn-over loop stands on a figure's extent, and the unit vector
-- pointing from there back into the figure: where the line through the
-- point along the direction leaves the box, at its lower end, or at its right
-- end when the line runs across the page, within 1e-9 of level, since a roll
-- of a quarter turn leaves a horizontal axis 6e-17 off level. A direction of
-- 'Nothing' is taken as up the page.
--
-- A line that misses the box, or only touches it at a corner, falls back to
-- the midpoint of the box's bottom edge, with the loop rising up the page:
-- an axis given by hand need not cross the figure, and the bottom middle is
-- where a left-right turn seen from above puts it anyway. A box with no
-- height or no width, a figure seen edge on, is crossed at a single point,
-- and that point is the anchor. The inward vector is a unit vector on the
-- page, so the loop is moved by exactly three quarters of its size.
placeLoop :: Box -> V2 -> Maybe V2 -> (V2, V2)
placeLoop (Box (V2 x0 y0) (V2 x1 y1)) (V2 px py) shown =
  case (inRange x0 x1 px ux, inRange y0 y1 py uy) of
    (Just (ax, bx), Just (ay, by))
      | low < high || (low == high && flat) ->
          if level
            then (at high, V2 (negate ux) (negate uy))
            else (at low, V2 ux uy)
      where
        low = max ax ay
        high = min bx by
    _ -> fallback
  where
    fallback = (V2 (0.5 * (x0 + x1)) y0, V2 0 1)
    -- A box with no height or no width, a figure seen edge on, is crossed at
    -- one point; any other box a line meets at one point is only touched,
    -- at a corner, and the line does not cross the figure.
    flat = y0 == y1 || x0 == x1
    -- Oriented so that the lower end comes first along it, or, for a level
    -- line, the left end: then the exit is at the smallest parameter, or the
    -- largest for a level line, and the inward vector is the direction
    -- itself, or its reverse.
    level = maybe False (\(V2 _ y) -> abs y <= 1e-9) shown
    V2 ux uy = case shown of
      Nothing -> V2 0 1
      Just (V2 x y)
        | level -> if x < 0 then V2 (negate x) (negate y) else V2 x y
        | y < 0 -> V2 (negate x) (negate y)
        | otherwise -> V2 x y
    at t = V2 (px + t * ux) (py + t * uy)
    -- The parameters along one axis for which the line lies between lo and
    -- hi, or 'Nothing' when it runs alongside that slab outside it. A part
    -- of the unit direction within 1e-9 of 0 is taken as 0, as for level:
    -- a quarter-turn roll leaves 6e-17, which would otherwise make the slab
    -- a sliver of parameters around the given point and put the loop there.
    inRange lo hi p u
      | abs u <= 1e-9 = if lo <= p && p <= hi then Just (-1 / 0, 1 / 0) else Nothing
      | otherwise = let a = (lo - p) / u; b = (hi - p) / u in Just (min a b, max a b)

-- | A kind stated from the reader's side, as a page showing this side sees
-- it: valley and mountain swapped from the opposite side, as the module
-- header says. Seen edge on, the page cannot show which way the paper turns,
-- so the stated kind is drawn as it is.
asSeen :: SeenFrom -> ArrowKind -> ArrowKind
asSeen FromOppositeSide = \case
  ValleyArrow -> MountainArrow
  MountainArrow -> ValleyArrow
  UnfoldArrow -> UnfoldArrow
  ValleyAndUnfoldArrow -> MountainAndUnfoldArrow
  MountainAndUnfoldArrow -> ValleyAndUnfoldArrow
asSeen _ = id

-- | Every frame of a file as one page of numbered figures: 'stepFigures' with
-- 'noteFor' on every figure, laid out by 'gridOf'.
--
-- With @arrows@ set, each figure but the last also carries the fold that takes
-- it to the next one, as a book draws it.
--
-- 'Nothing' when the file has no frame with any geometry in it, as
-- 'stepFigures' says.
stepPage ::
  Theme ->
  Budget ->
  Grid ->
  View ->
  Bool ->
  [Frame] ->
  Either StepError (Maybe Diagram)
stepPage theme budget grid view arrows frames =
  gridOf grid . map fst <$> stepFigures theme budget view [(fr, noteFor arrows) | fr <- frames]

-- | Which side of the paper a page of these frames shows: the side its one
-- camera sees, so under @--view bottom@ a page is seen from the opposite side
-- however its frames lie.
--
-- A frame whose vertices cannot be read is refused, naming the frame
-- 'stepFigures' would name, because the camera is chosen from every frame's
-- vertices. The side itself does not need them, as the module header says. A
-- frame 'stepFigures' cannot draw for another reason still has a side. A list
-- with no geometry in it has no page, and is given the side of the view's own
-- camera, or of 'topDown' when the view names none.
pageSide :: View -> [Frame] -> Either StepError SeenFrom
pageSide view frames = seenFrom . snd <$> pageCamera view [(fr, ()) | fr <- frames]

-- | The frames a page draws, each with whatever rides with it, and the one
-- camera it draws them through.
--
-- Each frame that holds geometry comes with its place in the list, so an error
-- can name the frame someone would have to go and look at, and with its
-- vertices. A frame with none is dropped together with what rides with it. The
-- camera is chosen from every frame's vertices together, and from nothing that
-- rides with them, which the type says: this works for a @note@ of any type,
-- so it cannot look inside one.
pageCamera :: View -> [(Frame, note)] -> Either StepError ([(Int, Frame, note, [V3])], Basis)
pageCamera view frames = do
  resolved <- traverse withVertices [(i, fr, note) | (i, (fr, note)) <- zip [0 ..] frames, hasGeometry fr]
  pure (resolved, basisFor view (concatMap (\(_, _, _, verts) -> verts) resolved))
  where
    hasGeometry fr = not (null (verticesCoords fr))

    withVertices (i, fr, note) = do
      verts <- first (StepError i) (frameVertices fr)
      pure (i, fr, note, verts)
