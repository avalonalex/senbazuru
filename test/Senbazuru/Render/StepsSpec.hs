-- |
-- Tests for laying a whole folding sequence out as one page.
--
-- The property worth stating loudest is that every figure is drawn through one
-- camera. It is easy to get wrong by asking each frame what /it/ would like,
-- and the result is subtle rather than obviously broken: the reader is moved
-- around the model between figures, and the shared extent that holds the scale
-- steady becomes a union of boxes measured in different projections.
module Senbazuru.Render.StepsSpec (spec) where

import Control.Monad (forM)
import Data.Map.Strict qualified as M
import Senbazuru.Diagram (Diagram (..), Shape (..))
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid)
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (FoldError (..), frameVertices)
import Senbazuru.Fold.Types (Assignment (..), FoldFile (..), Frame (..), VertexId (..), allFrames, emptyFrame)
import Senbazuru.Geometry (Box (..), Transform (..), V2 (..), boxSize)
import Senbazuru.Geometry.Rigid (applyRigid)
import Senbazuru.Geometry.V3 (V3 (..), modelSpan)
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Render.Camera (Basis, SeenFrom (..), View (..), bottomUp, defaultView, frontOn, isometric, topDown)
import Senbazuru.Render.Steps
import Senbazuru.Render.Svg (defaultPage, pageTransform)
import Senbazuru.Sequence.Build (rotate, sequenceOf, step_, turnOver)
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Record (WrittenState (..), writtenStates)
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence, turnOverAbout)
import Senbazuru.Sequence.Syntax (PageAxis (..), Sequence (..), Turning (..))
import Test.Hspec
import Test.SequenceExamples (quarterFold)

-- | A square sheet at the given heights, one per corner, so that passing
-- anything but zeroes makes the frame leave the plane.
sheet :: [Double] -> Frame
sheet zs =
  emptyFrame
    { verticesCoords = zipWith (\(x, y) z -> [x, y, z]) [(0, 0), (1, 0), (1, 1), (0, 1)] zs,
      edgesVertices =
        [ (VertexId 0, VertexId 1),
          (VertexId 1, VertexId 2),
          (VertexId 2, VertexId 3),
          (VertexId 3, VertexId 0)
        ],
      edgesAssignment = replicate 4 Border
    }

flatSheet :: Frame
flatSheet = sheet [0, 0, 0, 0]

solidSheet :: Frame
solidSheet = sheet [0, 0, 0.7, 0]

grid :: Grid
grid = defaultGrid defaultTheme

page :: [Frame] -> Either StepError (Maybe Diagram)
page = stepPage defaultTheme defaultBudget grid defaultView False

spec :: Spec
spec = do
  describe "one camera for the whole page" $ do
    it "views a sequence that ends in the air isometrically throughout" $ do
      -- Not one figure from above and the next from an angle. Asserted against
      -- the explicit camera rather than by inspecting coordinates, so the test
      -- says what it means.
      let frames = [flatSheet, solidSheet]
      stepPage defaultTheme defaultBudget grid defaultView False frames
        `shouldBe` stepPage defaultTheme defaultBudget grid (View (Just isometric) 0) False frames

    it "views a sequence that stays flat from above throughout" $ do
      let frames = [flatSheet, flatSheet]
      stepPage defaultTheme defaultBudget grid defaultView False frames
        `shouldBe` stepPage defaultTheme defaultBudget grid (View (Just topDown) 0) False frames

    it "is not the same page either way, so the tests above can fail" $ do
      -- Guards the two above: if the cameras happened to agree on this input
      -- they would pass without saying anything.
      let frames = [flatSheet, solidSheet]
      stepPage defaultTheme defaultBudget grid (View (Just topDown) 0) False frames
        `shouldNotBe` stepPage defaultTheme defaultBudget grid (View (Just isometric) 0) False frames

  describe "which frames are steps" $ do
    it "skips a frame with no geometry in it" $ do
      -- FOLD keeps file metadata in the same object as the first frame, so a
      -- file that puts every step in file_frames has a key frame holding a
      -- title and nothing else. That is not a step.
      let withMetadataFrame = [emptyFrame {frameTitle = Just "just a title"}, flatSheet, flatSheet]
      fmap (fmap (length . labelsOf)) (page withMetadataFrame)
        `shouldBe` Right (Just 2)

    it "has nothing to lay out when no frame has any geometry" $
      page [emptyFrame, emptyFrame] `shouldBe` Right Nothing

    it "numbers the figures, not the frames they came from" $ do
      let withMetadataFrame = [emptyFrame, flatSheet, flatSheet]
      fmap (fmap labelsOf) (page withMetadataFrame)
        `shouldBe` Right (Just ["1", "2"])

  describe "when a frame will not draw" $
    it "says which frame it was" $ do
      -- Told only that a file will not draw, someone holding a twenty-step
      -- sequence has to bisect it by hand. Note the index counts frames in the
      -- file, so the skipped metadata frame still occupies number zero.
      let broken = flatSheet {verticesCoords = [[0]]}
      page [emptyFrame, flatSheet, broken]
        `shouldBe` Left (StepError 2 (VertexCoordTooShort (VertexId 0) 1))

  describe "what each figure's note draws" $ do
    -- The quarter fold's first fold, from the flat sheet to the half-folded
    -- state, which test/golden/quarter-fold-step-1.svg draws with its one
    -- arrow. Red if either note draws what the other one should.
    it "draws one arrow for inferNote and none for silentNote on the quarter fold's first fold" $ do
      frames <- take 2 <$> quarterFrames "test/fixtures/quarter-fold-steps.fold"
      let arrowsWith note = fmap (fmap arrowsOf) (pageWith top [(fr, note) | fr <- frames])
      (arrowsWith inferNote, arrowsWith silentNote) `shouldBe` (Right (Just 1), Right (Just 0))

    -- A1 of PRDs/06-prd-step-diagrams.md. It holds by construction while
    -- stepPage hands its frames to stepPageWith, so it is red only if
    -- stepPage is given a way of drawing of its own that disagrees. What each
    -- note draws is the business of the examples around it.
    it "draws stepPage's page as stepPageWith with noteFor on every figure (A1)" $ do
      quarter <- quarterFrames "examples/quarter-fold-steps.fold"
      bird <- allFrames <$> (loadFoldFile "examples/bird-base-sequence.fold" >>= right)
      let pages :: [(String, [Frame])]
          pages = [("the quarter fold", quarter), ("the bird", bird), ("the spec's sheets", [flatSheet, solidSheet])]
      [ (name, arrows)
        | (name, frames) <- pages,
          arrows <- [False, True],
          stepPage defaultTheme defaultBudget grid defaultView arrows frames
            /= stepPageWith defaultTheme defaultBudget grid defaultView [(fr, noteFor arrows) | fr <- frames]
        ]
        `shouldBe` []

    -- What stepPage's Bool asks for, which A1 cannot see, since both of its
    -- sides pick their notes with noteFor. Red if noteFor gave inferNote
    -- whatever its Bool, or stepPage handed it the opposite one.
    it "draws the quarter fold's two arrows with arrows asked for, and none without" $ do
      frames <- quarterFrames "test/fixtures/quarter-fold-steps.fold"
      let arrowsWith arrows = fmap (fmap arrowsOf) (stepPage defaultTheme defaultBudget grid top arrows frames)
      (arrowsWith True, arrowsWith False) `shouldBe` (Right (Just 2), Right (Just 0))

    -- A frame with no geometry is skipped together with its note, so every
    -- other note stays on its own frame. Red if the notes were matched by
    -- their place in the list to the frames left after skipping, which puts
    -- the arrow from b to c on a instead.
    it "skips a frame with no geometry together with its note" $ do
      (a, b, c) <- quarterThree
      pageWith top [(emptyFrame, inferNote), (a, silentNote), (b, inferNote), (c, silentNote)]
        `shouldBe` pageWith top [(a, silentNote), (b, inferNote), (c, silentNote)]

    -- Guards the example above, which would pass if moving the arrow to the
    -- figure before it drew the same page.
    it "draws another page when every note moves one figure earlier" $ do
      (a, b, c) <- quarterThree
      pageWith top [(a, inferNote), (b, silentNote), (c, inferNote)]
        `shouldNotBe` pageWith top [(a, silentNote), (b, inferNote), (c, silentNote)]

    -- The flat sheet and the creased one have different creases, which
    -- motionsBetween refuses to compare. So inferring the arrows between them
    -- is refused, naming the figure whose note asked by its place in the
    -- list, the skipped frame counted, while a silent note on that figure
    -- draws the page. Red if arrows were worked out for every figure and
    -- dropped where a note says none.
    it "refuses only the arrows a note asks for, naming its frame by its place in the list" $ do
      let creased = flatSheet {edgesVertices = edgesVertices flatSheet <> [(VertexId 0, VertexId 2)], edgesAssignment = edgesAssignment flatSheet <> [Valley]}
      pageWith defaultView [(emptyFrame, silentNote), (flatSheet, inferNote), (creased, silentNote)]
        `shouldBe` Left (StepError 1 (FramesDiffer "edges_vertices" 4 5))
      fmap (fmap labelsOf) (pageWith defaultView [(emptyFrame, inferNote), (flatSheet, silentNote), (creased, inferNote)])
        `shouldBe` Right (Just ["1", "2"])

  describe "which side a page shows" $ do
    it "sees the bird from the opposite side under bottom, and from the reader's side by default" $ do
      -- The bird is not flat, so with no view named the page looks at it
      -- isometrically, from above. A pageSide that ignored the view's camera
      -- would see it from the reader's side under bottom and front too. Both
      -- cameras a page chooses for itself look from above, so the default line
      -- pins that, not which frames chose between them.
      bird <- allFrames <$> (loadFoldFile "examples/bird-base-sequence.fold" >>= right)
      pageSide (View (Just bottomUp) 0) bird `shouldBe` Right FromOppositeSide
      pageSide defaultView bird `shouldBe` Right FromReadersSide
      pageSide (View (Just frontOn) 0) bird `shouldBe` Right EdgeOn

    it "refuses a frame whose vertices cannot be read, naming it as stepPage does" $ do
      -- The camera is chosen from every frame's vertices, as stepPage chooses
      -- it, so a frame it cannot read is refused here too, though the side
      -- would not need it. Counted among the file's frames, metadata frame and
      -- all, as the page counts them above.
      let broken = flatSheet {verticesCoords = [[0]]}
      pageSide defaultView [emptyFrame, flatSheet, broken]
        `shouldBe` Left (StepError 2 (VertexCoordTooShort (VertexId 0) 1))

  turning

labelsOf :: Diagram -> [String]
labelsOf d = [show' t | Label _ _ _ t <- diagramShapes d]
  where
    show' = filter (/= '"') . show

arrowsOf :: Diagram -> Int
arrowsOf d = length [() | Arrow _ <- diagramShapes d]

-- | A page of notes, drawn as 'page' draws its frames.
pageWith :: View -> [(Frame, StepNote)] -> Either StepError (Maybe Diagram)
pageWith = stepPageWith defaultTheme defaultBudget grid

-- | Looking straight down, as test/golden/quarter-fold-step-1.svg does.
top :: View
top = View (Just topDown) 0

-- | Every frame of a copy of the quarter fold: the flat sheet, folded in
-- half, folded in half again.
quarterFrames :: FilePath -> IO [Frame]
quarterFrames path = allFrames <$> (loadFoldFile path >>= right)

quarterThree :: IO (Frame, Frame, Frame)
quarterThree =
  quarterFrames "test/fixtures/quarter-fold-steps.fold" >>= \case
    [a, b, c] -> pure (a, b, c)
    frames -> fail ("expected the quarter fold's 3 frames, got " <> show (length frames))

-- | What a turn does to a page: R-06-12, A7 and A8 of
-- PRDs/06-prd-step-diagrams.md.
--
-- A turn-over shows the model from its other side, as turning it over on the
-- table would, and @rotate 4/8 turn@ spins it half a turn on the page.
-- Neither moves any paper, and the runner makes both about the model's own
-- middle, the centre of its bounding box (@middleOf@ in
-- "Senbazuru.Sequence.Run"). Seen from straight above or below, a left-right
-- turn-over mirrors the drawing across the line through that centre along the
-- model's y axis, a top-bottom one across the line along its x axis, and a
-- half turn spins it about the centre: each sends the model's box onto
-- itself. So the figure after the turn is drawn in the box of
-- the figure before it, and the page's box, which covers every figure's box
-- and sets the scale, stays where it was.
--
-- That holds only while the page's axes run along the model's, so only for a
-- roll (the drawing turned on the page, 'viewTurn') of a whole number of
-- quarter turns. At 45° the mirror line runs diagonally across the page and
-- swaps the width and height of a box that is not square, and under @iso@ the
-- drawing is not symmetric about the line at all, so a turn changes the box
-- there, which A8 checks the bird for.
--
-- The turns ('turns') are the quarter fold, a square folded in half and in
-- half again, turned over and turned half round; the same square folded in
-- half only, turned over top to bottom and turned half round; and the bird: a
-- state of @examples/bird-base-sequence.fold@ part way through a petal fold
-- (see docs/glossary.md), so not flat, turned over. The quarter fold is a
-- square whose middle is the run's anchor, so a turn about the anchor, or a
-- quarter turn, draws it in the same box; the half-folded sheet is half as
-- wide as it is high, and its middle, (3/4, 1/2), is not the anchor,
-- (3/4, 1/4), so either turns it off its box.
turning :: Spec
turning = beforeAll turns . describe "a turn-over or half turn on the page" $ do
  -- Red when a turn's axis misses the middle of the model's box across the
  -- page, as an axis through x = 0 or through the vertex mean would. On the
  -- bird the vertex mean is 0.6444 in x and the box's middle 0.6471, so a
  -- turn-over about the mean moves its figure 0.0055 seen from above. On the
  -- quarter fold the mean is (0.8333, 0.1667) and the middle (0.75, 0.25),
  -- since four of its nine vertices, the sheet's corners, lie on one corner of
  -- the folded square. A flat square, as in RunSpec, cannot tell the two
  -- apart: its mean and its middle are both (1/2, 1/2). Red too, on the
  -- half-folded sheet, when a turn is about the anchor rather than the
  -- middle, or when @rotate 4/8 turn@ turns a quarter turn.
  it "keeps each figure's box, the page's box and its scale, from above and below at every quarter-turn roll (A7)" $ \inputs ->
    concat <$> forM [(t, v, q) | t <- everyTurn inputs, v <- [("top", topDown), ("bottom", bottomUp)], q <- [0 .. 3]] missesFor
      `shouldReturn` []

  -- Guards the example above, which would pass if a turn drew the model
  -- exactly as before. Each turn moves some vertex.
  it "moves some vertex in each of those turns" $ \inputs ->
    [(turnName t, frameVertices (turnFrom t) /= frameVertices (turnTo t)) | t <- everyTurn inputs]
      `shouldBe` [(turnName t, True) | t <- everyTurn inputs]

  -- The numbers D5 records, which 06 §5 measured with a script projecting the
  -- bird by hand; here they come through the page. Red when the turn is about
  -- a line on the page rather than one in the model, or turns nothing, since
  -- either leaves the size of the box seen isometrically unchanged. It
  -- compares sizes, which do not depend on where the box lies, so a turn
  -- about the wrong point is A7's to catch, not this one's.
  it "changes the bird's box seen isometrically, 0.4142 by 0.6118 to 0.9981 by 0.3335 (A8)" $ \inputs -> do
    let bird = birdTurnedOver inputs
    from <- boxSize <$> figureBox iso (turnFrom bird)
    to <- boxSize <$> figureBox iso (turnTo bird)
    let within (V2 w h) (ew, eh) = abs (w - ew) <= 1e-4 && abs (h - eh) <= 1e-4
    (from, to) `shouldSatisfy` \(f, t) -> within f (0.4142, 0.6118) && within t (0.9981, 0.3335)

  -- The figures above are each read from a page of their own, so they
  -- cannot see one figure fitted to another. This page holds both. Red when
  -- the page re-fits a figure after a turn to the box of the one before it,
  -- which would leave the page's box what it is with the state before the
  -- turn drawn twice (A8's second red case).
  it "draws the bird after its turn in its own box, on a page with the bird before it (A8)" $ \inputs -> do
    let bird = birdTurnedOver inputs
    twice <- diagramExtent <$> pageOf iso [turnFrom bird, turnFrom bird]
    turned <- diagramExtent <$> pageOf iso [turnFrom bird, turnTo bird]
    (twice, turned) `shouldSatisfy` \(a, b) -> not (boxesNear 1e-4 a b)
  where
    iso = View (Just isometric) 0

-- | A turn to draw: the frames a page shows before it, the state it starts
-- from and the state it ends in.
data Turn = Turn
  { turnName :: String,
    turnEarlier :: [Frame],
    turnFrom :: Frame,
    turnTo :: Frame
  }

-- | The turns A7 names, made once for every example that uses them.
data Turns = Turns
  { quarterTurnedOver :: Turn,
    quarterHalfTurned :: Turn,
    halfTurnedOver :: Turn,
    halfHalfTurned :: Turn,
    birdTurnedOver :: Turn
  }

everyTurn :: Turns -> [Turn]
everyTurn inputs = map ($ inputs) [quarterTurnedOver, quarterHalfTurned, halfTurnedOver, halfHalfTurned, birdTurnedOver]

-- | The quarter fold run with a turn as one more step, the same after its
-- first step only, and the bird's @file_frames[13]@ ("Second petal ·
-- underside · close sides · hinge 150°", @render --frame 14@) turned over by
-- the runner's own rule. The quarter fold is built from 'quarterFold', not
-- read from @test/golden/quarter-fold.foldseq@, which is the printer's golden
-- output.
turns :: IO Turns
turns = do
  quarterPaper <- loadFoldFile quarterSheet >>= right
  let -- The quarter fold's first @kept@ steps, then the turn.
      ran name kept moves = do
        let sequence' = quarterFold {seqSteps = take kept (seqSteps quarterFold) <> seqSteps (sequenceOf (seqHeader quarterFold) (step_ "Turn the model." moves))}
        run <- right (checkSequence sequence' >>= runSequence defaultRunSettings (M.singleton quarterSheet quarterPaper) . elaborate)
        states <- right (writtenStates run)
        case splitAt kept (map stateFrame states) of
          (earlier, [from, turned]) -> pure (Turn name earlier from turned)
          _ -> fail ("expected " <> show (kept + 2) <> " states, got " <> show (length states))
  overTurn <- ran "the quarter fold turned over left-right" 2 (turnOver LeftRight)
  halfTurn <- ran "the quarter fold turned half a turn clockwise" 2 (rotate 4 Clockwise)
  halfOver <- ran "the sheet folded in half, turned over top-bottom" 1 (turnOver TopBottom)
  halfHalf <- ran "the sheet folded in half, turned half a turn clockwise" 1 (rotate 4 Clockwise)
  bird <- loadFoldFile "examples/bird-base-sequence.fold" >>= right
  (earlier, petal) <- case splitAt 13 (otherFrames bird) of
    (frames, frame : _) -> pure (frames, frame)
    _ -> fail "the bird has fewer than 14 file_frames"
  points <- right (frameVertices petal)
  let over = turnOverAbout LeftRight points
      turned = petal {verticesCoords = [[x, y, z] | V3 x y z <- map (applyRigid over) points]}
  pure (Turns overTurn halfTurn halfOver halfHalf (Turn "the bird's file_frames[13] turned over left-right" earlier petal turned))
  where
    quarterSheet = "examples/quarter-fold-steps.fold"

-- | Every way one turn misses R-06-12 under one view and roll, as text
-- naming it, or none: the figure after the turn drawn in another box than
-- the figure before it; the page with the turn in another box, or at another
-- scale, than the page with the state before the turn drawn in its place.
-- That page has as many figures, since the page's box depends on how many
-- figures its grid lays out as well as on their boxes.
--
-- Boxes agree within 1e-12 of the model's size ('modelSpan'), not exactly. A
-- roll goes through 'cos' and 'sin', and @cos (pi / 2)@ is about 6e-17, not
-- 0; and the turn's own additions round, so even with no roll the right edge
-- of the bird's box moves from 1.0000000000000002 to 1.0000000000000004. A
-- scale is in page units per model unit, so it is compared as a fraction of
-- itself.
missesFor :: (Turn, (String, Basis), Int) -> IO [String]
missesFor (t, (viewName, basis), quarters) = do
  let view = View (Just basis) (fromIntegral quarters * pi / 2)
  hair <- (1e-12 *) . modelSpan <$> right (frameVertices (turnFrom t))
  from <- figureBox view (turnFrom t)
  to <- figureBox view (turnTo t)
  unturned <- pageOf view (turnEarlier t <> [turnFrom t, turnFrom t])
  turned <- pageOf view (turnEarlier t <> [turnFrom t, turnTo t])
  let V2 scale _ = tScale (pageTransform defaultPage unturned)
      V2 scale' _ = tScale (pageTransform defaultPage turned)
      named what = turnName t <> ", " <> viewName <> " rolled " <> show (90 * quarters) <> " degrees: " <> what
  pure $
    [named ("figure " <> show from <> " became " <> show to) | not (boxesNear hair from to)]
      <> [named ("page " <> show (diagramExtent unturned) <> " became " <> show (diagramExtent turned)) | not (boxesNear hair (diagramExtent unturned) (diagramExtent turned))]
      <> [named ("scale " <> show scale <> " became " <> show scale') | abs (scale - scale') > 1e-12 * abs scale]

boxesNear :: Double -> Box -> Box -> Bool
boxesNear hair (Box (V2 a b) (V2 c d)) (Box (V2 a' b') (V2 c' d')) =
  all ((<= hair) . abs) [a - a', b - b', c - c', d - d']

-- | The box a figure is drawn in, as a page draws it: the box of a page
-- holding that figure alone. A page's box is its figures' boxes laid out in a
-- grid, and a grid of one figure is that figure's box, to rounding. With the
-- view naming where to look from, the page's camera does not depend on which
-- frames the page holds ('Senbazuru.Render.CreasePattern.basisFor'), so this
-- is the box the figure has among the rest of its page.
figureBox :: View -> Frame -> IO Box
figureBox view fr = diagramExtent <$> pageOf view [fr]

pageOf :: View -> [Frame] -> IO Diagram
pageOf view frames = case stepPage defaultTheme defaultBudget grid view False frames of
  Right (Just d) -> pure d
  Right Nothing -> fail "no frame holds any geometry"
  Left err -> fail (show err)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
