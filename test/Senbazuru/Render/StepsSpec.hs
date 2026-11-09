-- |
-- Tests for laying a whole folding sequence out as one page.
--
-- The property worth stating loudest is that every figure is drawn through one
-- camera. It is easy to get wrong by asking each frame what /it/ would like,
-- and the result is subtle rather than obviously broken: the reader is moved
-- around the model between figures, and the shared extent that holds the scale
-- steady becomes a union of boxes measured in different projections.
module Senbazuru.Render.StepsSpec (spec) where

import Control.Monad (forM, forM_, void, (>=>))
import Data.Map.Strict qualified as M
import Data.Maybe (mapMaybe)
import Data.Text qualified as T
import Senbazuru.Diagram (ArrowHead (..), ArrowPath (..), Diagram (..), Glyph (..), Shape (..), Stroke (..), glyphReach, solid)
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid, gridOf)
import Senbazuru.Diagram.Page (FittedPage (..), Height (..), Page (..), PageFitError (..), fitPage)
import Senbazuru.Diagram.Style (ArrowKind (..), Theme (..), defaultTheme)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (FoldError (..), frameVertices)
import Senbazuru.Fold.Types (Assignment (..), FoldFile (..), Frame (..), VertexId (..), allFrames, emptyFrame)
import Senbazuru.Geometry (Box (..), Transform (..), V2 (..), boxSize)
import Senbazuru.Geometry.Rigid (applyRigid, rotationAboutDegrees)
import Senbazuru.Geometry.V3 (V3 (..), modelSpan)
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Step (Motion (..), motionsBetween)
import Senbazuru.Render.Camera (Basis, SeenFrom (..), View (..), bottomUp, defaultView, frontOn, isometric, topDown)
import Senbazuru.Render.Steps
import Senbazuru.Render.Svg (defaultPage, pageTransform, renderSvg)
import Senbazuru.Sequence.Build (edge, fold, inFront, rotate, sequenceOf, step_, turnOver)
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Record (Run (..), WrittenState (..), presentationAxis, writtenStates)
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence, turnOverAbout)
import Senbazuru.Sequence.Syntax (Compass (..), Line (..), PageAxis (..), Sequence (..), Turning (..))
import Test.Golden (goldenText)
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

    -- A1 of PRDs/06-prd-step-diagrams.md, restated by S25 (C136). It holds
    -- by construction while stepPage is gridOf over stepFigures with noteFor
    -- of its Bool, so it is red only when stepPage's page is not that one:
    -- drawn some other way, laid out some other way, or with the note for
    -- the other Bool. It cannot see a fault in noteFor itself, which both of
    -- its sides use. What each note draws is the business of the examples
    -- around it.
    it "draws stepPage's page as gridOf over stepFigures with noteFor on every figure (A1)" $ do
      quarter <- quarterFrames "examples/quarter-fold-steps.fold"
      bird <- allFrames <$> (loadFoldFile "examples/bird-base-sequence.fold" >>= right)
      let pages :: [(String, [Frame])]
          pages = [("the quarter fold", quarter), ("the bird", bird), ("the spec's sheets", [flatSheet, solidSheet])]
      [ (name, arrows)
        | (name, frames) <- pages,
          arrows <- [False, True],
          stepPage defaultTheme defaultBudget grid defaultView arrows frames
            /= fmap (gridOf grid . map fst) (stepFigures defaultTheme defaultBudget defaultView [(fr, noteFor arrows) | fr <- frames])
        ]
        `shouldBe` []

    -- render --steps never draws a frame's title (D7, 06 §9), because a file
    -- cannot say whether its titles name the state they sit on, as this
    -- example's "Step 2: folded in half" does, or give the next instruction,
    -- as a run's do. Its frames are titled, which the first line checks, so
    -- the rest can fail: red if noteFor's notes took a frame's title as their
    -- caption, and, through labelsOf, which sees a caption's lines, if
    -- stepPage laid captions out.
    it "draws only the figures' numbers on a file whose frames are titled" $ do
      frames <- quarterFrames "examples/quarter-fold-steps.fold"
      map frameTitle frames `shouldSatisfy` notElem Nothing
      forM_ [False, True] $ \arrows -> do
        figures <- right (stepFigures defaultTheme defaultBudget defaultView [(fr, noteFor arrows) | fr <- frames])
        (arrows, map snd figures) `shouldBe` (arrows, [Nothing, Nothing, Nothing])
        drawn <- right (stepPage defaultTheme defaultBudget grid defaultView arrows frames)
        (arrows, fmap labelsOf drawn) `shouldBe` (arrows, Just ["1", "2", "3"])

    -- The caption is the note's to give, and comes back with its own figure:
    -- a frame with no geometry is skipped with its note, so its caption is
    -- on no figure, and every other caption stays with its frame. Red if
    -- captions were matched to figures by place after the skip, or dropped.
    it "hands each figure back with its own note's caption" $ do
      (a, b, c) <- quarterThree
      let captioned t = silentNote {noteCaption = Just t}
      figures <- right (stepFigures defaultTheme defaultBudget top [(emptyFrame, captioned "skipped"), (a, captioned "first"), (b, silentNote), (c, captioned "third")])
      map snd figures `shouldBe` [Just "first", Nothing, Just "third"]
      (noteCaption inferNote, noteCaption silentNote) `shouldBe` (Nothing, Nothing)

    -- What stepPage's Bool asks for. Red if noteFor gave inferNote whatever
    -- its Bool, which A1 cannot see since both of its sides pick their notes
    -- with noteFor, and if stepPage handed noteFor the opposite Bool, which
    -- A1 sees too.
    it "draws the quarter fold's two arrows with arrows asked for, and none without" $ do
      frames <- quarterFrames "test/fixtures/quarter-fold-steps.fold"
      let arrowsWith arrows = fmap (fmap arrowsOf) (stepPage defaultTheme defaultBudget grid top arrows frames)
      (arrowsWith True, arrowsWith False) `shouldBe` (Right (Just 2), Right (Just 0))

    -- A frame with no geometry is skipped together with its note, so every
    -- other note stays on its own frame. Red if the notes were matched by
    -- their place in the list to the frames left after skipping: a would get
    -- the empty frame's inferNote and b the silentNote meant for a, so the
    -- page would draw the fold from a to b and not the one from b to c.
    it "skips a frame with no geometry together with its note" $ do
      (a, b, c) <- quarterThree
      pageWith top [(emptyFrame, inferNote), (a, silentNote), (b, inferNote), (c, silentNote)]
        `shouldBe` pageWith top [(a, silentNote), (b, inferNote), (c, silentNote)]

    -- Guards the example above, which would pass if the notes that mismatch
    -- hands out, inferNote, silentNote and inferNote, drew the same page as
    -- the right ones.
    it "draws another page with the notes matching by place would give" $ do
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

  foldHere
  statedKinds
  turningOver
  rotatingAndRepeating
  labellingMarks
  turning

-- | Fold-here lines (R-06-15 of PRDs/06-prd-step-diagrams.md): the dashed
-- line a book draws on the figure before a fold, where the paper is about to
-- fold. Each comes in a note with its kind as the move was written, from the
-- reader's side, and is drawn as the page sees it.
--
-- The sheet carries a diagonal crease lettered @F@, the letter a written
-- pre-crease gets, which the default theme draws as a faint solid line. A
-- valley line along it has to be drawn with the valley dash all the same:
-- styling a line by the crease under it ('strokeFor'), rather than by its
-- note's kind, draws it faint and turns the first example red.
foldHere :: Spec
foldHere = describe "fold-here lines" $ do
  it "draws a valley line on an F crease with the valley dash, over the paper" $ do
    (added, crease) <- drawnLines top [(ValleyArrow, V3 0 0 0, V3 1 1 0)]
    added `shouldBe` [Polyline valleyDash crease]

  -- R-06-9's fold-here half: from the opposite side valley and mountain
  -- swap. Red if the page drew the stated kind from every side.
  it "swaps valley and mountain dashes seen from below, and only there" $ do
    let below = View (Just bottomUp) 0
    forM_
      [ (below, ValleyArrow, mountainDash),
        (below, MountainArrow, valleyDash),
        (top, MountainArrow, mountainDash)
      ]
      $ \(view, kind, dash) -> do
        (added, crease) <- drawnLines view [(kind, V3 0 0 0, V3 1 1 0)]
        added `shouldBe` [Polyline dash crease]

  -- Edge on, the page cannot show which way the paper turns, so the stated
  -- kind is drawn. Red if edge-on counted as the opposite side. The line
  -- runs from (0, 0) to (1, 0) on the page: looking along +y with z up, a
  -- point's x stays and its height is its z.
  -- The figure seen edge on also carries the eye that says so, since a
  -- valley line is a kind whose look depends on the side.
  it "draws the stated kind seen edge on" $ do
    (added, _) <- drawnLines (View (Just frontOn) 0) [(ValleyArrow, V3 0 0 0, V3 1 1 0)]
    added `shouldBe` [Polyline valleyDash [V2 0 0, V2 1 0], eyeAt (V2 0 0)]

  -- An unfold turns paper back along a crease it has, so it gets no line,
  -- from either side: red if the page turned an unfold into a valley or a
  -- mountain when it swaps the two. A line whose ends land on one point of
  -- the page, as one standing straight up does seen from above, has no
  -- direction to draw.
  it "draws nothing for an unfold from either side, or for a line seen end on" $ do
    forM_ [top, View (Just bottomUp) 0] $ \view -> do
      (added, _) <- drawnLines view [(UnfoldArrow, V3 0 0 0, V3 1 1 0)]
      added `shouldBe` []
    (added, _) <- drawnLines top [(ValleyArrow, V3 0 0 0, V3 0 0 1)]
    added `shouldBe` []

  -- On the quarter fold's first figure, the line along the fold it is about
  -- to make, x = 1/2, comes after the paper and before the inferred arrow,
  -- so the arrow is painted over it. Given lines are drawn on the last
  -- figure too, which carries no inferred arrow: nothing is inferred. The
  -- line is matched by its points as well as its stroke, since the figure's
  -- own valley creases are drawn with the same stroke elsewhere.
  it "paints a line before the figure's arrow, and draws given lines on the last figure" $ do
    (a, b, _) <- quarterThree
    let along = GivenFoldLines [(ValleyArrow, V3 0.5 0 0, V3 0.5 1 0)]
        line = Polyline valleyDash [V2 0.5 0, V2 0.5 1]
    figures <- right (stepFigures defaultTheme defaultBudget top [(a, inferNote {noteFoldLines = along}), (b, silentNote {noteFoldLines = along})])
    [(take 1 shapes, length [() | Arrow _ <- drop 1 shapes]) | (d, _) <- figures, let shapes = dropWhile (/= line) (diagramShapes d)]
      `shouldBe` [([line], 1), ([line], 0)]
    [length [() | Arrow _ <- diagramShapes d] | (d, _) <- figures] `shouldBe` [1, 0]
    (noteFoldLines inferNote, noteFoldLines silentNote) `shouldBe` (NoFoldLines, NoFoldLines)
  where
    valleyDash = Stroke (themeInk defaultTheme) (themeCreaseWidth defaultTheme) (themeValleyDash defaultTheme)
    mountainDash = Stroke (themeInk defaultTheme) (themeCreaseWidth defaultTheme) (themeMountainDash defaultTheme)

-- | Stated kinds, drawn as seen (R-06-9 and A6 of
-- PRDs/06-prd-step-diagrams.md): an arrow or a fold-here line of a stated
-- kind is drawn as the page sees it, valley and mountain swapped from the
-- side opposite the reader's; an inferred arrow states no kind and stays
-- solid; and a page seen edge on, which can show neither side, draws the
-- kind as stated and marks every figure with an eye.
statedKinds :: Spec
statedKinds = describe "stated kinds" $ do
  -- A6, on the quarter fold's first figure: a valley arrow and a valley line
  -- along its fold. Red if the page drew the stated kind from every side, or
  -- swapped the line and not the head.
  it "draws a valley's head and line as a mountain's from below (A6)" $ do
    (a, b, _) <- quarterThree
    let note = silentNote {noteArrows = InferArrowsAs ValleyArrow, noteFoldLines = GivenFoldLines [(ValleyArrow, V3 0.5 0 0, V3 0.5 1 0)]}
    [map summary (added view [(a, note), (b, silentNote)] [(a, silentNote), (b, silentNote)]) | view <- [top, View (Just bottomUp) 0]]
      `shouldBe` [[Right valleyDash, Left (Just SolidHead)], [Right mountainDash, Left (Just HollowHalfHead)]]
    -- A given arrow's kind is drawn as seen too.
    let given = silentNote {noteArrows = GivenArrows [(ValleyArrow, V3 0.25 0.5 0, V3 0.75 0.5 0)]}
    [map summary (added view [(a, given), (b, silentNote)] [(a, silentNote), (b, silentNote)]) | view <- [top, View (Just bottomUp) 0]]
      `shouldBe` [[Left (Just SolidHead)], [Left (Just HollowHalfHead)]]

  -- Plain InferArrows states no kind, which is what keeps every arrowed
  -- page drawn from below, checked-bird-below.svg among them, as it is. An
  -- unfold is an unfold from either side.
  it "keeps an inferred arrow solid from below, and an unfold's head from either side" $ do
    (a, b, _) <- quarterThree
    let heads view note = [arrowHead p | Arrow p <- added view [(a, note), (b, silentNote)] [(a, silentNote), (b, silentNote)]]
    heads (View (Just bottomUp) 0) inferNote `shouldBe` [SolidHead]
    forM_ [top, View (Just bottomUp) 0] $ \view ->
      heads view silentNote {noteArrows = InferArrowsAs UnfoldArrow} `shouldBe` [HollowDoubleHead]

  -- A given arrow between the ends an inferred one has is the same arrow,
  -- which #643's S32 relies on when it gives a run's arrows from its records
  -- (A10). Given arrows are drawn on the last figure too, which infers none.
  it "draws a given arrow as the inferred arrow between the same ends, on any figure" $ do
    (a, b, _) <- quarterThree
    motions <- right (motionsBetween a b)
    let given = GivenArrows [(MountainArrow, motionFrom m, motionTo m) | m <- motions]
        arrowsWith notes = [[p | Arrow p <- diagramShapes d] | Right figures <- [stepFigures defaultTheme defaultBudget top notes], (d, _) <- figures]
    inferred <- case arrowsWith [(a, silentNote {noteArrows = InferArrowsAs MountainArrow}), (b, silentNote)] of
      [first', []] -> pure first'
      other -> fail ("expected arrows on the first figure only, got " <> show other)
    arrowsWith [(a, silentNote {noteArrows = given}), (b, silentNote {noteArrows = given})] `shouldBe` [inferred, inferred]
    map arrowHead inferred `shouldBe` [HollowHalfHead]

  -- Edge on, every figure gets one eye when any figure draws a valley or a
  -- mountain, and none otherwise: not for inferred arrows, which state no
  -- kind, an unfold, which looks the same from either side, an empty list,
  -- or arrows asked of the last figure, which draws none. Seen from above
  -- the same notes give no eye. Red if the eye went only on the figure that
  -- states the kind, or on every edge-on page.
  it "marks every figure seen edge on when any figure states a valley or a mountain, and only then" $ do
    (a, b, c) <- quarterThree
    let front = View (Just frontOn) 0
        eyes view notes = case stepFigures defaultTheme defaultBudget view (zip [a, b, c] notes) of
          Right figures -> Right [length [() | Offset _ (Symbol _ _ _ EdgeOnMark) <- diagramShapes d] | (d, _) <- figures]
          Left err -> Left err
        on1 note = [note, silentNote, silentNote]
    eyes front (on1 silentNote {noteArrows = InferArrowsAs MountainArrow}) `shouldBe` Right [1, 1, 1]
    eyes front [silentNote, silentNote, silentNote {noteFoldLines = GivenFoldLines [(ValleyArrow, V3 0.5 0 0, V3 0.5 1 0)]}] `shouldBe` Right [1, 1, 1]
    eyes front (on1 silentNote {noteArrows = GivenArrows [(ValleyArrow, V3 0.25 0.5 0, V3 0.75 0.5 0)]}) `shouldBe` Right [1, 1, 1]
    eyes top (on1 silentNote {noteArrows = InferArrowsAs MountainArrow}) `shouldBe` Right [0, 0, 0]
    forM_
      [ on1 inferNote,
        on1 silentNote {noteArrows = InferArrowsAs UnfoldArrow},
        on1 silentNote {noteArrows = GivenArrows []},
        on1 silentNote {noteFoldLines = GivenFoldLines [(UnfoldArrow, V3 0.5 0 0, V3 0.5 1 0)]},
        [silentNote, silentNote, silentNote {noteArrows = InferArrowsAs ValleyArrow}]
      ]
      $ \notes -> eyes front notes `shouldBe` Right [0, 0, 0]

  -- The eye stands at the figure's top-left corner, where the step number's
  -- baseline is on an edge-on page, moved over and above the number in page
  -- units. A4 for the whole page: the same bytes at model sizes 1 and 400,
  -- so neither the eye nor its nudge is sized to the model.
  it "puts the eye over the step number, the same on the page at model sizes 1 and 400 (A4)" $ do
    (a, b, c) <- quarterThree
    let front = View (Just frontOn) 0
        notesAt k =
          [ silentNote {noteArrows = InferArrowsAs MountainArrow, noteFoldLines = GivenFoldLines [(MountainArrow, V3 0 0 0, V3 (k * 0.5) k 0)]},
            silentNote {noteArrows = GivenArrows [(ValleyArrow, V3 (k * 0.75) (k * 0.75) 0, V3 (k * 0.75) (k * 0.25) 0)]},
            silentNote
          ]
        scaled k fr = fr {verticesCoords = map (map (* k)) (verticesCoords fr)}
        pageAt k = fmap (fmap (renderSvg defaultPage)) (pageWith front (zip (map (scaled k) [a, b, c]) (notesAt k)))
    figures <- right (stepFigures defaultTheme defaultBudget front (zip [a, b, c] (notesAt 1)))
    [[shape | shape@(Offset _ (Symbol {})) <- diagramShapes d] | (d, _) <- take 1 figures] `shouldBe` [[eyeAt (V2 0 0)]]
    pageAt 400 `shouldBe` pageAt 1
    fmap (fmap (T.count "<circle")) (pageAt 1) `shouldBe` Right (Just 3)

  -- On a page fitted as a run's page is, with captions, every eye lies on the
  -- page and clear of the captions above it: the first row's eyes in the
  -- room the page leaves above it, the second row's in the room between the
  -- first row's captions and its numbers. Each eye's outline spans 7 either
  -- side of its pupil's centre and 3.92 above and below it; a caption's ink
  -- spans 10.8 above its baseline and about 3 below. Red if no room were
  -- reserved: the first row's eyes then lie above the page.
  it "keeps every eye on a fitted page, clear of the captions above it" $ do
    (a, b, c) <- quarterThree
    let front = View (Just frontOn) 0
        captioned t = silentNote {noteCaption = Just t}
        notes = [(captioned "Fold the left half behind, onto the right.") {noteArrows = InferArrowsAs MountainArrow}, captioned "Fold the top half down in front, onto the bottom.", captioned "Done.", captioned "Again."]
    figures <- right (stepFigures defaultTheme defaultBudget front (zip [a, b, c, a] notes))
    fitted <- right (fitPage defaultTheme (defaultGrid defaultTheme) HeightToFit defaultPage {pageWidth = 400} figures) >>= maybe (fail "nothing to lay out") pure
    let svg = renderSvg (fittedPage fitted) (fittedDiagram fitted)
        number key line = case T.splitOn (" " <> key <> "=\"") line of
          [_, rest] -> Just (read (T.unpack (T.takeWhile (/= '"') rest)) :: Double)
          _ -> Nothing
        eyeCentres = [(x, y) | l <- T.lines svg, "<circle" `T.isInfixOf` l, Just x <- [number "cx" l], Just y <- [number "cy" l]]
        texts = [(x, y) | l <- T.lines svg, "<text" `T.isInfixOf` l, Just x <- [number "x" l], Just y <- [number "y" l]]
        tall = pageHeight (fittedPage fitted)
        clashes (ex, ey) = [(tx, ty) | (tx, ty) <- texts, ty - 10.8 < ey + 3.92, ty + 3 > ey - 3.92, abs (tx - ex) < 60, ty < ey]
    length eyeCentres `shouldBe` 4
    length texts `shouldBe` 14
    [(x, y) | (x, y) <- eyeCentres, y - 3.92 < 0 || y + 3.92 > tall || x - 7 < 0 || x + 7 > 400] `shouldBe` []
    concatMap clashes eyeCentres `shouldBe` []

  -- A page of a given height shrinks figures with height to leave room for
  -- their captions' bands, and has to leave the eyes' room too: the sheet
  -- with a corner raised 0.7, seen from the front, in two rows of one, on a
  -- page 200 tall. Row 2's eye then sits 21 page units below row 1's caption
  -- baseline: the 14 left of row 1's band, the 30.8 of room above row 2, and
  -- the eye 23.8 back up from row 2's top. Red if the fit left out the room:
  -- the page is then drawn at a smaller scale than the fit chose, so bands
  -- and room, turned into model units at the fit's scale, come out short.
  it "leaves the eyes' room when a page of a given height shrinks its figures" $ do
    let front = View (Just frontOn) 0
        note t = silentNote {noteCaption = Just t, noteFoldLines = GivenFoldLines [(ValleyArrow, V3 0 0 0, V3 1 0 0)]}
        grid1 = (defaultGrid defaultTheme) {gridColumns = 1}
    figures <- right (stepFigures defaultTheme defaultBudget front [(solidSheet, note "First."), (solidSheet, note "Second.")])
    fitted <- right (fitPage defaultTheme grid1 HeightAsGiven defaultPage {pageWidth = 400, pageHeight = 200} figures) >>= maybe (fail "nothing to lay out") pure
    let svg = renderSvg (fittedPage fitted) (fittedDiagram fitted)
        number key line = case T.splitOn (" " <> key <> "=\"") line of
          [_, rest] -> Just (read (T.unpack (T.takeWhile (/= '"') rest)) :: Double)
          _ -> Nothing
        ys tag key = [y | l <- T.lines svg, tag `T.isInfixOf` l, Just y <- [number key l]]
        firstCaption = [y | l <- T.lines svg, ">First.</text>" `T.isInfixOf` l, Just y <- [number "y" l]]
    case (ys "<circle" "cy", firstCaption) of
      ([eye1, eye2], [caption]) -> do
        [y | y <- [eye1, eye2], y - 3.92 < 0] `shouldBe` []
        (eye2 - caption) `shouldSatisfy` (\gap -> abs (gap - 21) < 1e-6)
      other -> expectationFailure ("expected two eyes and one first caption, got " <> show other)

  -- Edge on is the camera's alone: the spec's sheet with one corner raised
  -- 0.7 is not flat, yet seen from the front it is edge on and marked. Its
  -- figure has height, from (0, 0) up to (1, 0.7) on the page, so the eye
  -- stands at its top-left corner, (0, 0.7), not its bottom, and is the
  -- step number's size however big the sheet is.
  it "marks a model in the air seen from the front, at its figure's top-left corner" $ do
    let note = silentNote {noteFoldLines = GivenFoldLines [(ValleyArrow, V3 0 0 0, V3 1 0 0)]}
        eyes fr = [[shape | shape@(Offset _ (Symbol {})) <- diagramShapes d] | Right figures <- [stepFigures defaultTheme defaultBudget (View (Just frontOn) 0) [(fr, note)]], (d, _) <- figures]
    eyes solidSheet `shouldBe` [[eyeAt (V2 0 0.7)]]
    eyes solidSheet {verticesCoords = map (map (* 3)) (verticesCoords solidSheet)} `shouldBe` [[eyeAt (V2 0 (0.7 * 3))]]
  where
    valleyDash = Stroke (themeInk defaultTheme) (themeCreaseWidth defaultTheme) (themeValleyDash defaultTheme)
    mountainDash = Stroke (themeInk defaultTheme) (themeCreaseWidth defaultTheme) (themeMountainDash defaultTheme)

    -- What a note adds to the first figure, past the figure drawn without it.
    added view noted plain = case (stepFigures defaultTheme defaultBudget view noted, stepFigures defaultTheme defaultBudget view plain) of
      (Right ((with, _) : _), Right ((without, _) : _)) -> drop (length (diagramShapes without)) (diagramShapes with)
      _ -> []

    -- An arrow by its head, a line by its stroke, and anything else as
    -- neither, which no expected list holds.
    summary = \case
      Arrow p -> Left (Just (arrowHead p))
      Polyline stroke _ -> Right stroke
      _ -> Left Nothing

-- | The turn-over loop (R-06-4, R-06-11, A9, A17 of
-- PRDs/06-prd-step-diagrams.md): a note's 'PageTurnedOver' puts the loop
-- below its figure and draws no arrow inferred across the turn.
--
-- Two runs of the quarter fold give the frames and the axes: one turns the
-- model over left-right after its two folds, a turn and nothing else; the
-- other folds the top half down and turns over in one step, so its pair of
-- states differs by a fold and a turn. The axes are the runner's own,
-- 'presentationAxis' of each turn's record: (3/4, 1/4) along y, the middle
-- of the quarter-folded paper.
turningOver :: Spec
turningOver = beforeAll turnRuns . describe "a turn-over loop" $ do
  -- A9, restated on a pair that folds and turns, since a pure turn infers
  -- no arrow anyway (05 L3). Without a note the pair infers one arrow, every
  -- face followed to where the turn left it; with the note it has the loop
  -- and no arrow, whether the note infers arrows of no kind or of a kind. A
  -- given arrow is still drawn: only inference is suppressed. Red if the
  -- note did not suppress inference, or suppressed given arrows too.
  it "draws the loop and no inferred arrow on a pair that folds and turns (A9)" $ \runs -> do
    let (from, to) = (foldTurnFrom runs, foldTurnTo runs)
        turned note = note {notePresentation = Just (uncurry PageTurnedOver (foldTurnAxis runs))}
        counted note = case stepFigures defaultTheme defaultBudget top [(from, note), (to, silentNote)] of
          Right ((d, _) : _) -> Right (arrowsOf d, loopsOf d)
          other -> Left (fmap (map snd) other)
    counted inferNote `shouldBe` Right (1, 0)
    counted (turned inferNote) `shouldBe` Right (0, 1)
    counted (turned silentNote {noteArrows = InferArrowsAs ValleyArrow}) `shouldBe` Right (0, 1)
    counted (turned silentNote {noteArrows = GivenArrows [(ValleyArrow, V3 0.75 0.75 0, V3 0.75 0.25 0)]}) `shouldBe` Right (1, 1)

  -- 05's L3 still holds: two states a turn apart infer no arrow, note or no
  -- note.
  it "infers no arrow across a pure turn, with or without the loop" $ \runs ->
    case drop 2 (quarterStates runs) of
      [from, to] ->
        [ fmap (map (arrowsOf . fst)) (stepFigures defaultTheme defaultBudget top [(from, note), (to, silentNote)])
          | note <- [inferNote, inferNote {notePresentation = Just (uncurry PageTurnedOver (quarterAxis runs))}]
        ]
          `shouldBe` [Right [0, 0], Right [0, 0]]
      states -> expectationFailure ("expected four states, got " <> show (length states + 2))

  -- From above, the left-right axis runs up the page through x = 3/4 and
  -- leaves figure 3's extent, [1/2, 1] by [0, 1/2], at the middle of its
  -- bottom edge. The loop stands there, pointing up into the figure, moved
  -- 18 page units down the page, three quarters of the theme's glyph size,
  -- 24, at an arrow's weight. Red if the loop stood on the edge, pointed
  -- away from the figure, or took the eye's size.
  it "stands the loop below the figure, under where the axis leaves it" $ \runs ->
    loopOn top (quarterFigure3 runs) (quarterAxis runs) `shouldBe` Right [loopAt (V2 0 18) (V2 0.75 0) (V2 0 1)]

  -- The anchor rule on axes a run would not give. An axis up the page off
  -- the middle leaves the bottom edge under itself; one across the page
  -- leaves at the right end, and the loop then stands to the right,
  -- pointing left; one that misses the figure falls back to the bottom
  -- edge's middle. Red if every loop took the fallback, or the right end
  -- were the left.
  it "stands the loop where an off-centre axis leaves the figure, and falls back when the axis misses it" $ \runs -> do
    let figure3 = quarterFigure3 runs
    loopOn top figure3 (V3 0.6 0.3 0, V3 0 1 0) `shouldBe` Right [loopAt (V2 0 18) (V2 0.6 0) (V2 0 1)]
    loopOn top figure3 (V3 0.7 0.25 0, V3 1 0 0) `shouldBe` Right [loopAt (V2 18 0) (V2 1 0.25) (V2 (-1) 0)]
    loopOn top figure3 (V3 0 2 0, V3 1 0 0) `shouldBe` Right [loopAt (V2 0 18) (V2 0.75 0) (V2 0 1)]
    -- A line through the figure's top-right corner running down to the
    -- right at 45° only touches it, (1, 1/2) being the one point of the
    -- figure on it: the loop falls back too, rather than standing on that
    -- corner pointing away from the paper.
    loopOn top figure3 (V3 1 0.5 0, V3 1 (-1) 0) `shouldBe` Right [loopAt (V2 0 18) (V2 0.75 0) (V2 0 1)]

  -- Only an axis's direction counts: one too long or too short to square
  -- gives the loop a unit one does, and one tilted out of the paper, whose
  -- projection is shorter than it, still moves the loop three quarters of
  -- its size. Red if the length overflowed into an axis seen end on, or the
  -- nudge followed the projection's length.
  it "moves the loop by three quarters of its size, however long or tilted the axis is" $ \runs -> do
    let figure3 = quarterFigure3 runs
        nudges axis = [n | Right shapes <- [loopOn top figure3 axis], Offset n _ <- shapes]
    forM_ [V3 0 1e200 0, V3 0 1e-200 0] $ \direction ->
      loopOn top figure3 (V3 0.6 0.3 0, direction) `shouldBe` Right [loopAt (V2 0 18) (V2 0.6 0) (V2 0 1)]
    loopOn top figure3 (V3 0.7 0.25 0, V3 1e200 0 0) `shouldBe` Right [loopAt (V2 18 0) (V2 1 0.25) (V2 (-1) 0)]
    map (\(V2 x y) -> abs (sqrt (x * x + y * y) - 18) < 1e-9) (nudges (V3 0.6 0.3 0, V3 0 1 1)) `shouldBe` [True]

  -- On a page turned a quarter, an axis across it is level only to within
  -- 6e-17, and an axis up it has a part of that size across: both still
  -- count as level or upright. So the left-right axis of figure 3, across
  -- this page, leaves at the figure's right end, and an axis lying along
  -- the figure's left side leaves at its lower end, the corner, not where
  -- its given point is. Red if either test were exact.
  it "takes an axis 6e-17 off level or upright on a page turned a quarter as level or upright" $ \runs -> do
    let turned = View (Just topDown) (pi / 2)
        figure3 = quarterFigure3 runs
        extentOf frame = [diagramExtent d | Right ((d, _) : _) <- [stepFigures defaultTheme defaultBudget turned [(frame, silentNote)]]]
        anchors axis = [(p, v) | Right shapes <- [loopOn turned figure3 axis], Offset _ (Symbol _ _ p (TurnOverLoop v)) <- shapes]
        near (V2 a b) (V2 c d) = abs (a - c) < 1e-12 && abs (b - d) < 1e-12
    case (extentOf figure3, anchors (quarterAxis runs), anchors (V3 0.75 0.5 0, V3 1 0 0)) of
      ([Box (V2 left bottom) (V2 rightSide _)], [(acrossAt, acrossBy)], [(uprightAt, uprightBy)]) -> do
        let V2 acrossX _ = acrossAt
        (abs (acrossX - rightSide) < 1e-12, near acrossBy (V2 (-1) 0)) `shouldBe` (True, True)
        (near uprightAt (V2 left bottom), near uprightBy (V2 0 1)) `shouldBe` (True, True)
      other -> expectationFailure ("expected one figure and two loops, got " <> show other)
    -- Turned the other way, the left-right axis shows as (1, +6e-17): taken
    -- as upright it would leave at the left end, taken as level it leaves at
    -- the right. Red if the level test were exact.
    let other' = View (Just topDown) (-pi / 2)
        acrossOn = [(p, v) | Right shapes <- [loopOn other' figure3 (quarterAxis runs)], Offset _ (Symbol _ _ p (TurnOverLoop v)) <- shapes]
        rightOf = [r | Right ((d, _) : _) <- [stepFigures defaultTheme defaultBudget other' [(figure3, silentNote)]], let Box _ (V2 r _) = diagramExtent d]
    case (acrossOn, rightOf) of
      ([(V2 x _, by)], [r]) -> (abs (x - r) < 1e-12, near by (V2 (-1) 0)) `shouldBe` (True, True)
      other -> expectationFailure ("expected one loop and one figure, got " <> show other)

  -- A17: seen from the front, the left-right axis points at the reader, so
  -- its projection has no direction; the loop is drawn as if the axis ran
  -- up the page, at the middle of figure 3's bottom edge, which seen edge on
  -- is the figure itself, from (1/2, 0) to (1, 0) on the page.
  -- An end-on axis through a point off the figure's middle, at x = 0.6,
  -- tells this apart from the fallback, which would put the loop at 0.75.
  it "draws an axis seen end on as if it ran up the page (A17)" $ \runs -> do
    loopOn (View (Just frontOn) 0) (quarterFigure3 runs) (quarterAxis runs) `shouldBe` Right [loopAt (V2 0 18) (V2 0.75 0) (V2 0 1)]
    loopOn (View (Just frontOn) 0) (quarterFigure3 runs) (V3 0.6 0.25 0, V3 0 1 0) `shouldBe` Right [loopAt (V2 0 18) (V2 0.6 0) (V2 0 1)]

  -- S27's eye counts a stated kind only where it is drawn, and a turned
  -- figure draws no inferred arrow. Red if the turned figure's stated kind
  -- still put eyes on the page.
  it "puts no eye on an edge-on page whose only stated kind is a turned figure's inferred arrows" $ \runs ->
    case quarterStates runs of
      [a, b, c, d] ->
        fmap (map (\(fig, _) -> length [() | Offset _ (Symbol _ _ _ EdgeOnMark) <- diagramShapes fig])) (stepFigures defaultTheme defaultBudget (View (Just frontOn) 0) [(a, silentNote), (b, silentNote), (c, silentNote {noteArrows = InferArrowsAs MountainArrow, notePresentation = Just (uncurry PageTurnedOver (quarterAxis runs))}), (d, silentNote)])
          `shouldBe` Right [0, 0, 0, 0]
      states -> expectationFailure ("expected four states, got " <> show (length states))

  -- On a page fitted as a run's page is, a loop below a figure that fills
  -- its cell, the flat sheet turned over about x = 1/2, hangs below the
  -- cell, and the captions of its row start below the loop: the loop's
  -- lowest point, read from its path, lies above the ink of each caption of
  -- the row, which rises 10.8 above its baseline. Red if the layout left no
  -- room below the row ('markDrop'), when the first caption line would sit
  -- 18 under the cell, over the loop.
  it "starts the captions of the loop's row below the loop" $ \runs ->
    case quarterStates runs of
      a : b : _ -> do
        let notes =
              [ silentNote {noteCaption = Just "Turn the sheet over.", notePresentation = Just (PageTurnedOver (V3 0.5 0.5 0) (V3 0 1 0))},
                silentNote {noteCaption = Just "Folded in half."}
              ]
        figures <- right (stepFigures defaultTheme defaultBudget top (zip [a, b] notes))
        fitted <- right (fitPage defaultTheme (defaultGrid defaultTheme) HeightToFit defaultPage {pageWidth = 400} figures) >>= maybe (fail "nothing to lay out") pure
        let svg = renderSvg (fittedPage fitted) (fittedDiagram fitted)
            loopLines = loopPaths svg
            lowest = maximum (0 : [y | l <- loopLines, V2 _ y <- pathPoints l])
            captions = [y | l <- T.lines svg, "<text" `T.isInfixOf` l, not (any (`T.isInfixOf` l) [">1<", ">2<"]), Just y <- [attribute "y" l]]
        length loopLines `shouldBe` 2
        length captions `shouldBe` 2
        [y | y <- captions, y - 10.8 < lowest] `shouldBe` []
      states -> expectationFailure ("expected four states, got " <> show (length states))

  -- A top-bottom turn's axis runs across the page, so its loop stands past
  -- the figure's right end, and the page leaves room beside that column for
  -- it: with the turned sheet in the first column the loop stays clear of
  -- the second figure's paper, and in the last column it stays on the page.
  -- Red if the layout left no room beside the column ('markRight'). On a
  -- page too narrow for the loop beside its figures, the fit is refused.
  it "leaves room beside a column for a loop past its figure's right end" $ \runs ->
    case quarterStates runs of
      flatSheet' : _ -> do
        let turned = silentNote {noteCaption = Just "Turn the sheet over, top to bottom.", notePresentation = Just (PageTurnedOver (V3 0.5 0.5 0) (V3 1 0 0))}
            plain = silentNote {noteCaption = Just "Turned."}
            fitted width notes = do
              figures <- right (stepFigures defaultTheme defaultBudget top (zip [flatSheet', flatSheet'] notes))
              pure (fitPage defaultTheme (defaultGrid defaultTheme) HeightToFit defaultPage {pageWidth = width} figures)
            draw = \case
              Right (Just f) -> pure (renderSvg (fittedPage f) (fittedDiagram f))
              other -> fail ("expected a page, got " <> show (void <$> other))
            loopRight svg = maximum (0 : [x | l <- loopPaths svg, V2 x _ <- pathPoints l])
            paperLefts svg = [minimum [x | V2 x _ <- pathPoints l] | l <- T.lines svg, "fill=\"#faf8f3\"" `T.isInfixOf` l]
        first <- fitted 400 [turned, plain] >>= draw
        last' <- fitted 400 [plain, turned] >>= draw
        case paperLefts first of
          [_, second] -> loopRight first `shouldSatisfy` (< second)
          lefts -> expectationFailure ("expected two sheets, got " <> show lefts)
        (loopRight last' > 0, loopRight last' <= 400 - 16) `shouldBe` (True, True)
        narrow <- fitted 60 [turned, plain]
        case narrow of
          Left (TooNarrowForMarks 60 16 _) -> pure ()
          other -> expectationFailure ("expected the page refused as too narrow, got " <> show (void <$> other))
      [] -> expectationFailure "no states"

  -- 06's turn-over golden: the run's four states, each figure with the arrows
  -- inferred to the next and its state's title as its caption, and figure 3
  -- with the loop of the turn that follows it, fitted to a page 400 wide as
  -- a run's page is. Red if the loop lies along the axis, on the edge, or at
  -- a size that follows the model. Figure 3 is followed by a pure turn, which
  -- infers no arrow anyway, so A9's test, not this, pins the suppression.
  it "renders the quarter run turned over, with its loop" $
    fittedTurnOver >=> goldenText "test/golden/quarter-fold-turn-over-steps.svg"
  where
    loopsOf d = length [() | Offset _ (Symbol _ _ _ (TurnOverLoop _)) <- diagramShapes d]

-- | The rotate and repeat marks (R-06-13, A15 of
-- PRDs/06-prd-step-diagrams.md): a note's 'PageRotated' puts the rotate mark
-- above its figure's top-right corner, its sense as the page sees it, and a
-- note's 'noteRepeat' puts the box holding the range there too, to the
-- rotate mark's left when the figure has one.
rotatingAndRepeating :: Spec
rotatingAndRepeating = describe "rotate and repeat marks" $ do
  -- A15, restated with the page's constructor: on the quarter fold's three
  -- figures, a rotate of 3/8 clockwise on figure 1 and a repeat of figures 1
  -- and 2 on figure 3 give one RotateMark (-3) and one RepeatMark 1 2, each
  -- on its own figure, at that figure's top-right corner. Red if the sign
  -- were dropped, the range shifted, or a mark put on another figure.
  it "puts one rotate mark and one repeat mark on their own figures (A15)" $ do
    (a, b, c) <- quarterThree
    let notes = [silentNote {notePresentation = Just (PageRotated (-3) (V3 0.5 0.5 0))}, silentNote, silentNote {noteRepeat = Just (1, 2)}]
    figures <- right (stepFigures defaultTheme defaultBudget top (zip [a, b, c] notes))
    [[(g, p == corner d) | shape <- diagramShapes d, Just (p, g) <- [markOf shape]] | (d, _) <- figures]
      `shouldBe` [[(RotateMark (-3), True)], [], [(RepeatMark 1 2, True)]]

  -- From the paper's other side a clockwise turn looks anticlockwise, so
  -- the mark's sign flips; seen edge on it is drawn as stated. Red if the
  -- sign followed the side wrongly or not at all.
  it "draws a rotate's sense as the page sees it" $ do
    (a, _, _) <- quarterThree
    let glyphs view k = [g | Right ((d, _) : _) <- [stepFigures defaultTheme defaultBudget view [(a, silentNote {notePresentation = Just (PageRotated k (V3 0.5 0.5 0))})]], shape <- diagramShapes d, Just (_, g@(RotateMark _)) <- [markOf shape]]
    [glyphs view 3 | view <- [top, View (Just bottomUp) 0, View (Just frontOn) 0]] `shouldBe` [[RotateMark 3], [RotateMark (-3)], [RotateMark 3]]

  -- A turn of no eighths, or of eight or more either way, is none a run
  -- makes: no mark, and no eye on an edge-on page for it. minBound would
  -- survive a negation and an abs.
  it "draws no rotate mark for a turn of no eighths or of eight or more" $ do
    (a, b, c) <- quarterThree
    forM_ [0, 8, -8, minBound] $ \k -> do
      let note = silentNote {notePresentation = Just (PageRotated k (V3 0.5 0.5 0))}
          -- Every mark, the edge-on eye among them: a turn that draws no
          -- mark must not put eyes on the page either.
          marks view = [length [() | Offset _ (Symbol {}) <- diagramShapes d] | Right figures <- [stepFigures defaultTheme defaultBudget view [(a, note), (b, silentNote), (c, silentNote)]], (d, _) <- figures]
      (k, marks top, marks (View (Just frontOn) 0)) `shouldBe` (k, [0, 0, 0], [0, 0, 0])

  -- R-06-4 for a rotate: a pair that folds and turns round infers the
  -- arrows of every face to where the turn left it; the note suppresses
  -- them, while a given arrow is still drawn.
  it "infers no arrow across a turn on the table, and still draws a given one" $ do
    (a, b, _) <- quarterThree
    turnedB <- case frameVertices b of
      Right points -> pure b {verticesCoords = [[x, y, z] | V3 x y z <- map (applyRigid (rotationAboutDegrees (V3 0.75 0.5 0) (V3 0 0 1) (-135))) points]}
      Left err -> fail (show err)
    let arrowsWith note = [arrowsOf d | Right ((d, _) : _) <- [stepFigures defaultTheme defaultBudget top [(a, note), (turnedB, silentNote)]]]
        rotated note = note {notePresentation = Just (PageRotated (-3) (V3 0.75 0.5 0))}
    (arrowsWith inferNote, arrowsWith (rotated inferNote), arrowsWith (rotated silentNote {noteArrows = GivenArrows [(ValleyArrow, V3 0.25 0.5 0, V3 0.75 0.5 0)]}))
      `shouldBe` ([1], [0], [1])

  -- A rotate's sense depends on the side, so seen edge on it puts the eye
  -- on every figure, as a stated valley or mountain does (the owner's
  -- choice of 2026-11-08). A repeat alone does not.
  it "puts the edge-on eye on every figure for a rotate, not for a repeat" $ do
    (a, b, c) <- quarterThree
    let eyes notes = [length [() | Offset _ (Symbol _ _ _ EdgeOnMark) <- diagramShapes d] | Right figures <- [stepFigures defaultTheme defaultBudget (View (Just frontOn) 0) (zip [a, b, c] notes)], (d, _) <- figures]
    eyes [silentNote, silentNote {notePresentation = Just (PageRotated 2 (V3 0.5 0.5 0))}, silentNote] `shouldBe` [1, 1, 1]
    eyes [silentNote {noteRepeat = Just (1, 2)}, silentNote, silentNote] `shouldBe` [0, 0, 0]

  -- The marks above the corner: the rotate mark centred half its size in
  -- from the right end and half its size above a line 1 page unit over the
  -- step number's ink, 10.8 above the figure's top at the number's 14; the
  -- repeat box with its bottom on that line, at the right end alone, or a
  -- rotate's width and a quarter of the glyph size to its left beside one.
  -- On a figure with the edge-on eye the line is above the eye, 2.2 of the
  -- number's size over the top. Red if a mark were on the paper, or beside
  -- a rotate the box overlapped it.
  it "places the marks above the figure's top-right corner, clear of the number, and above the eye seen edge on" $ do
    (a, _, _) <- quarterThree
    let both = silentNote {notePresentation = Just (PageRotated (-3) (V3 0.5 0.5 0)), noteRepeat = Just (1, 2)}
        alone = silentNote {noteRepeat = Just (1, 2)}
        nudges view note = [(g, n) | Right ((d, _) : _) <- [stepFigures defaultTheme defaultBudget view [(a, note)]], Offset n (Symbol _ _ _ g) <- diagramShapes d, isCornerMark g]
        V2 boxAcross boxUp = glyphReach 24 (RepeatMark 1 2)
        near (g, V2 x y) (h, V2 u v) = g == h && abs (x - u) < 1e-9 && abs (y - v) < 1e-9
        line = 10.8 + 1
        eyeLine = 2.2 * 14 + 1
        expect l = [(RotateMark (-3), V2 (-12) (negate (l + 12))), (RepeatMark 1 2, V2 (negate (24 + 6 + boxAcross)) (negate (l + boxUp)))]
    and (zipWith near (nudges top both) (expect line)) `shouldBe` True
    length (nudges top both) `shouldBe` 2
    and (zipWith near (nudges top alone) [(RepeatMark 1 2, V2 (negate boxAcross) (negate (line + boxUp)))]) `shouldBe` True
    and (zipWith near (nudges (View (Just frontOn) 0) both) (expect eyeLine)) `shouldBe` True
    (length (nudges top alone), length (nudges (View (Just frontOn) 0) both)) `shouldBe` (1, 2)

  -- On a page fitted as a run's page is, the marks lie on the page, clear
  -- of the step numbers and, seen edge on, of the eyes: no two of their
  -- boxes, read from the SVG, overlap. Red if the layout left no room above
  -- the row, or the marks met the number or the eye.
  it "keeps the marks on a fitted page, clear of the numbers and the eyes" $ do
    (a, b, c) <- quarterThree
    let cap t = silentNote {noteCaption = Just t}
        notes = [(cap "Turn it round.") {notePresentation = Just (PageRotated (-3) (V3 0.5 0.5 0))}, (cap "Turn and repeat.") {notePresentation = Just (PageRotated 2 (V3 0.75 0.5 0)), noteRepeat = Just (1, 2)}, (cap "Repeat.") {noteRepeat = Just (1, 12)}]
    forM_ [top, View (Just frontOn) 0] $ \view -> do
      figures <- right (stepFigures defaultTheme defaultBudget view (zip [a, b, c] notes))
      fitted <- right (fitPage defaultTheme (defaultGrid defaultTheme) HeightToFit defaultPage {pageWidth = 400} figures) >>= maybe (fail "nothing to lay out") pure
      let svg = renderSvg (fittedPage fitted) (fittedDiagram fitted)
          boxes = markBoxes svg
          overlap (Box (V2 a0 b0) (V2 a1 b1)) (Box (V2 c0 d0) (V2 c1 d1)) = a0 < c1 && c0 < a1 && b0 < d1 && d0 < b1
          inside (Box (V2 x0 y0) (V2 x1 y1)) = x0 >= 0 && y0 >= 0 && x1 <= 400 && y1 <= pageHeight (fittedPage fitted)
          pairs = [(m, o) | (i, m) <- zip [0 :: Int ..] boxes, (j, o) <- zip [0 ..] boxes, i < j]
      -- Three numbers, two rotate marks and two repeat boxes, and from the
      -- front three eyes too.
      (length boxes, all (inside . snd) boxes) `shouldBe` (if view == top then 7 else 10, True)
      [(fst m, fst o) | (m, o) <- pairs, overlap (snd m) (snd o)] `shouldBe` []
  where
    corner d = let Box _ (V2 r t) = diagramExtent d in V2 r t
    markOf = \case
      Offset _ (Symbol _ _ p g) | isCornerMark g -> Just (p, g)
      _ -> Nothing
    isCornerMark = \case
      RotateMark _ -> True
      RepeatMark _ _ -> True
      _ -> False

-- | Mark labels where the paper shows (R-06-22, A16 of
-- PRDs/06-prd-step-diagrams.md), on the quarter run's written state 1: the
-- sheet folded in half behind, so its right half shows from above and its
-- left half lies under it, face to face. Two pairs of points lie together
-- there: (3/4, 3/4) on the right half and (1/4, 3/4) on the left, both at
-- (3/4, 3/4); and the corners (1, 1) and (0, 1), both at (1, 1). A mark is a
-- point of the paper, so each pair gets one label, on the layer the viewer
-- sees: the right half's from above, the left half's from below.
labellingMarks :: Spec
labellingMarks = beforeAll turnRuns . describe "mark labels" $ do
  -- A16, restated. Red if labels followed the mark's point as a place on
  -- the page, which labels the right half's from either side; if any face's
  -- region were taken as seen, which labels all four; if a face held only
  -- points inside its outline, which drops the corner; or if the side were
  -- ignored.
  it "labels the layer the viewer sees of two lying together, a corner's included (A16)" $ \runs ->
    case quarterStates runs of
      _ : folded : _ -> do
        let marks = [("A", V2 0.75 0.75), ("B", V2 0.25 0.75), ("C", V2 1 1), ("D", V2 0 1)]
        [labelled view folded marks | view <- [top, View (Just bottomUp) 0]] `shouldBe` [Right ["A", "C"], Right ["B", "D"]]
      states -> expectationFailure ("expected the quarter run's states, got " <> show (length states))

  -- Each label: a dot of 3.6 page units at the place, and the name at 11
  -- beside it, toward the middle of the piece of paper the place shows on,
  -- far enough along that the name's estimated box, 0.55 of its size a
  -- character wide and 10.8/14 of it tall, clears the dot by 2: the dot's
  -- radius, the gap, and the box's half extent along the direction.
  -- (3/4, 3/4) is the middle of state 1's upper right quarter, so its name
  -- goes straight down. From below, (1/4, 3/4) shows at the same place, which
  -- the bottom view draws at x = -3/4, so the dot there tests the carry from
  -- sheet to place. (7/8, 7/8) leans down and to the left, toward the
  -- quarter's middle. Red if the place were not carried, the name pushed a
  -- fixed distance, or the direction not toward the piece's middle.
  it "draws a dot at the place and the name beside it, clear of the dot, toward its piece's middle" $ \runs ->
    case quarterStates runs of
      _ : folded : _ -> do
        let shapesOf view marks = [shape | Right ((d, _) : _) <- [stepFigures defaultTheme defaultBudget view [(folded, silentNote {noteMarks = marks})]], shape <- diagramShapes d, isLabelShape shape]
            dot at = Symbol (solid (themeInk defaultTheme) (themeCreaseWidth defaultTheme)) 3.6 at PointDot
            nameAt (V2 ux uy) at name =
              let size = 11
                  wide = 0.55 * size * fromIntegral (T.length name)
                  tall = 10.8 / 14 * size
                  nudge = 1.8 + 2 + abs ux * 0.5 * wide + abs uy * 0.5 * tall
               in Offset (V2 (nudge * ux - 0.5 * wide) (nudge * uy + 0.35 * size)) (Label (themeInk defaultTheme) size at name)
            close a b = show a == show b || nearShapes a b
            nearShapes (Offset (V2 a b) l) (Offset (V2 c d) m) = abs (a - c) < 1e-9 && abs (b - d) < 1e-9 && l == m
            nearShapes a b = a == b
            matches got want = length got == length want && and (zipWith close got want)
            diagonal = sqrt 0.5
        shapesOf top [("A", V2 0.75 0.75)] `shouldSatisfy` (`matches` [dot (V2 0.75 0.75), nameAt (V2 0 1) (V2 0.75 0.75) "A"])
        shapesOf (View (Just bottomUp) 0) [("B", V2 0.25 0.75)] `shouldSatisfy` (`matches` [dot (V2 (-0.75) 0.75), nameAt (V2 0 1) (V2 (-0.75) 0.75) "B"])
        shapesOf top [("peak", V2 0.875 0.875)] `shouldSatisfy` (`matches` [dot (V2 0.875 0.875), nameAt (V2 (-diagonal) diagonal) (V2 0.875 0.875) "peak"])
      states -> expectationFailure ("expected the quarter run's states, got " <> show (length states))

  -- A point on the edge between two faces is held by both, which carry it
  -- to one place: it is labelled once there. On state 1, (1, 1/2) is the
  -- right edge's middle, shared by the two faces of the right half.
  it "labels a point two faces share once" $ \runs ->
    case quarterStates runs of
      _ : folded : _ -> labelled top folded [("E", V2 1 0.5)] `shouldBe` Right ["E"]
      states -> expectationFailure ("expected the quarter run's states, got " <> show (length states))

  -- A file that records no faces has them rebuilt from its creases, as
  -- anything needing paper does: the spec's flat sheet, its border alone,
  -- labels a mark at its middle. Red if the labels read the recorded faces
  -- only.
  it "labels a mark on a flat sheet whose file records no faces" $ \_ ->
    labelled top flatSheet [("M", V2 0.5 0.5)] `shouldBe` Right ["M"]

  -- No label, and never a refusal: seen edge on; on a frame without
  -- material coordinates, as 06's fixture's second frame is, though its
  -- layers can be ordered; and for a point off the paper. Red if any of
  -- these labelled, or if a figure refused for a mark.
  it "labels nothing seen edge on, without material coordinates, or off the paper, and refuses nothing" $ \runs -> do
    (_, halfFixture, _) <- quarterThree
    case quarterStates runs of
      _ : folded : _ -> do
        let marks = [("A", V2 0.75 0.75), ("C", V2 1 1)]
        labelled (View (Just frontOn) 0) folded marks `shouldBe` Right []
        labelled top halfFixture marks `shouldBe` Right []
        labelled top folded [("Z", V2 5 5)] `shouldBe` Right []
      states -> expectationFailure ("expected the quarter run's states, got " <> show (length states))
  where
    isLabelShape = \case
      Symbol _ _ _ PointDot -> True
      Offset _ (Label {}) -> True
      _ -> False
    labelled view frame marks = case stepFigures defaultTheme defaultBudget view [(frame, silentNote {noteMarks = marks})] of
      Right figures -> Right [name | (d, _) <- figures, Offset _ (Label _ _ _ name) <- diagramShapes d]
      Left err -> Left err

-- | The boxes of a page's step numbers, rotate marks, repeat boxes and eyes,
-- in page units, each with what it is: a number by its baseline, 10.8 above
-- it to 3 below and 7.7 a digit across; a rotate mark by its path's points;
-- a repeat box by its rectangle; an eye by its path.
markBoxes :: T.Text -> [(String, Box)]
markBoxes svg =
  [ ("number", Box (V2 x (y - 10.8)) (V2 (x + 7.7 * fromIntegral (T.length t)) (y + 3))) | l <- ls, "<text" `T.isInfixOf` l, "font-size=\"14\"" `T.isInfixOf` l, not ("text-anchor" `T.isInfixOf` l), let t = T.takeWhile (/= '<') (T.drop 1 (T.dropWhile (/= '>') l)), T.all (`elem` ("0123456789" :: String)) t, not (T.null t), Just x <- [attribute "x" l], Just y <- [attribute "y" l]
  ]
    <> [("rotate", boxOf (pathPoints l)) | l <- ls, " C " `T.isInfixOf` l, "stroke-width=\"1.8\"" `T.isInfixOf` l]
    <> [("repeat", Box (V2 x y) (V2 (x + w) (y + h))) | l <- ls, "<rect" `T.isInfixOf` l, "stroke=" `T.isInfixOf` l, Just x <- [attribute "x" l], Just y <- [attribute "y" l], Just w <- [attribute "width" l], Just h <- [attribute "height" l]]
    <> [("eye", boxOf (pathPoints l)) | l <- ls, " Q " `T.isInfixOf` l, "stroke-width=\"1\"" `T.isInfixOf` l, not (" C " `T.isInfixOf` l)]
  where
    ls = T.lines svg
    boxOf ps = case ([x | V2 x _ <- ps], [y | V2 _ y <- ps]) of
      (xs@(_ : _), ys@(_ : _)) -> Box (V2 (minimum xs) (minimum ys)) (V2 (maximum xs) (maximum ys))
      _ -> Box (V2 0 0) (V2 0 0)

-- | The loops a note turning over about this axis puts on this frame, drawn
-- alone through this view.
loopOn :: View -> Frame -> (V3, V3) -> Either StepError [Shape]
loopOn view frame axis =
  case stepFigures defaultTheme defaultBudget view [(frame, silentNote {notePresentation = Just (uncurry PageTurnedOver axis)})] of
    Right ((d, _) : _) -> Right [shape | shape@(Offset _ (Symbol _ _ _ (TurnOverLoop _))) <- diagramShapes d]
    Right [] -> Right []
    Left err -> Left err

-- | The turn-over loop as drawn: moved by this nudge in page units, at this
-- point, rising along this vector, the theme's glyph size at an arrow's
-- weight.
loopAt :: V2 -> V2 -> V2 -> Shape
loopAt nudge anchor vector =
  Offset nudge (Symbol (solid (themeInk defaultTheme) (themeArrowWidth defaultTheme)) (themeGlyphSize defaultTheme) anchor (TurnOverLoop vector))

-- | The quarter run turned over, fitted with its captions to a page 400 wide.
fittedTurnOver :: TurnRuns -> IO T.Text
fittedTurnOver runs = do
  let notes =
        [ inferNote {noteCaption = frameTitle frame, notePresentation = if i == (2 :: Int) then Just (uncurry PageTurnedOver (quarterAxis runs)) else Nothing}
          | (i, frame) <- zip [0 ..] (quarterStates runs)
        ]
  figures <- right (stepFigures defaultTheme defaultBudget top (zip (quarterStates runs) notes))
  fitted <- right (fitPage defaultTheme (defaultGrid defaultTheme) HeightToFit defaultPage {pageWidth = 400, pageTitle = Just "fixture"} figures) >>= maybe (fail "nothing to lay out") pure
  pure (renderSvg (fittedPage fitted) (fittedDiagram fitted))

-- | An attribute of an SVG element's line, by its name, which must follow a
-- space: so @y@ is not found inside @font-family@.
attribute :: T.Text -> T.Text -> Maybe Double
attribute key line = case T.splitOn (" " <> key <> "=\"") line of
  [_, rest] -> Just (read (T.unpack (T.takeWhile (/= '"') rest)))
  _ -> Nothing

-- | The turn-over loop's two paths in a page: its stem, the one path drawn
-- with curves, and its head, the path after it.
loopPaths :: T.Text -> [T.Text]
loopPaths svg = case break (" C " `T.isInfixOf`) (T.lines svg) of
  (_, stem : headLine : _) -> [stem, headLine]
  _ -> []

-- | The points of a path's @d@ attribute, its letters dropped.
pathPoints :: T.Text -> [V2]
pathPoints line = case T.splitOn " d=\"" line of
  [_, rest] -> pairs [read (T.unpack w) :: Double | w <- T.words (T.takeWhile (/= '"') rest), T.all (`elem` ("-.0123456789" :: String)) w]
  _ -> []
  where
    pairs (x : y : more) = V2 x y : pairs more
    pairs _ = []

-- | The two runs 'turningOver' draws from.
data TurnRuns = TurnRuns
  { -- | The quarter fold's three states, then the model turned over.
    quarterStates :: [Frame],
    quarterAxis :: (V3, V3),
    -- | The paper folded in half, then the same paper folded down and
    -- turned over in one step.
    foldTurnFrom :: Frame,
    foldTurnTo :: Frame,
    foldTurnAxis :: (V3, V3)
  }

quarterFigure3 :: TurnRuns -> Frame
quarterFigure3 runs = case drop 2 (quarterStates runs) of
  frame : _ -> frame
  [] -> emptyFrame

turnRuns :: IO TurnRuns
turnRuns = do
  quarterPaper <- loadFoldFile quarterSheet >>= right
  let ran kept moves = do
        let sequence' = quarterFold {seqSteps = take kept (seqSteps quarterFold) <> seqSteps (sequenceOf (seqHeader quarterFold) (step_ "Turn the model over, left to right." moves))}
        run <- right (checkSequence sequence' >>= runSequence defaultRunSettings (M.singleton quarterSheet quarterPaper) . elaborate)
        states <- right (writtenStates run)
        axis <- case mapMaybe presentationAxis (runRecords run) of
          [a] -> pure a
          axes -> fail ("expected one turn, got " <> show (length axes))
        pure (map stateFrame states, axis)
  (quarter, quarterAxis') <- ran 2 (turnOver LeftRight)
  (foldTurn, foldAxis) <- ran 1 (fold inFront (LineOnto (edge North) (edge South) Nothing) >> turnOver LeftRight)
  case foldTurn of
    [_, from, to] -> pure (TurnRuns quarter quarterAxis' from to foldAxis)
    states -> fail ("expected three states of the fold and turn, got " <> show (length states))
  where
    quarterSheet = "examples/quarter-fold-steps.fold"

-- | The eye that marks a figure seen edge on, at a figure whose top-left
-- corner is this point: the step number's size, 14, half of it to the right
-- and 1.7 of it up the page, at a crease's weight.
eyeAt :: V2 -> Shape
eyeAt corner =
  Offset (V2 (0.5 * 14) (-1.7 * 14)) (Symbol (solid (themeInk defaultTheme) (themeCreaseWidth defaultTheme)) 14 corner EdgeOnMark)

-- | A flat sheet with a diagonal crease lettered @F@, drawn alone with these
-- fold-here lines: the shapes the lines add after the figure drawn without
-- them, which has to come first unchanged, and the points of the figure's
-- crease, which the default theme draws as its one faint line.
drawnLines :: View -> [(ArrowKind, V3, V3)] -> IO ([Shape], [V2])
drawnLines view foldLines = do
  without <- figureWith silentNote
  with <- figureWith silentNote {noteFoldLines = GivenFoldLines foldLines}
  take (length without) with `shouldBe` without
  pure (drop (length without) with, concat [ps | Polyline stroke ps <- without, strokeWidth stroke == themeGhostWidth defaultTheme])
  where
    creased =
      flatSheet
        { edgesVertices = edgesVertices flatSheet <> [(VertexId 0, VertexId 2)],
          edgesAssignment = edgesAssignment flatSheet <> [Flat]
        }
    figureWith note =
      right (stepFigures defaultTheme defaultBudget view [(creased, note)]) >>= \case
        [(d, _)] -> pure (diagramShapes d)
        figures -> fail ("expected one figure, got " <> show (length figures))

-- | Every label's text, a caption's lines among them, which are 'Label's
-- moved by an 'Offset'.
labelsOf :: Diagram -> [String]
labelsOf d = mapMaybe text (diagramShapes d)
  where
    text = \case
      Label _ _ _ t -> Just (filter (/= '"') (show t))
      Offset _ shape -> text shape
      -- A mark's words, a rotate's amount or a repeat's range, are its
      -- glyph's, drawn by the backend, never a Label (06 R-06-7, R-06-13);
      -- and a line or an area has none, fanned or not.
      Symbol {} -> Nothing
      Fanned {} -> Nothing
      _ -> Nothing

arrowsOf :: Diagram -> Int
arrowsOf d = length [() | Arrow _ <- diagramShapes d]

-- | A page of notes, drawn as 'page' draws its frames: their figures laid
-- out by 'gridOf', as 'stepPage' lays its out.
pageWith :: View -> [(Frame, StepNote)] -> Either StepError (Maybe Diagram)
pageWith view notes = gridOf grid . map fst <$> stepFigures defaultTheme defaultBudget view notes

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
-- "Senbazuru.Sequence.Record"). Seen from straight above or below, a left-right
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
