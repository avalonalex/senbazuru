-- |
-- Tests for laying a whole folding sequence out as one page.
--
-- The property worth stating loudest is that every figure is drawn through one
-- camera. It is easy to get wrong by asking each frame what /it/ would like,
-- and the result is subtle rather than obviously broken: the reader is moved
-- around the model between figures, and the shared extent that holds the scale
-- steady becomes a union of boxes measured in different projections.
module Senbazuru.Render.StepsSpec (spec) where

import Control.Monad (forM, forM_)
import Data.Map.Strict qualified as M
import Data.Maybe (mapMaybe)
import Data.Text qualified as T
import Senbazuru.Diagram (ArrowHead (..), ArrowPath (..), Diagram (..), Glyph (..), Shape (..), Stroke (..), solid)
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid, gridOf)
import Senbazuru.Diagram.Page (FittedPage (..), Height (..), Page (..), fitPage)
import Senbazuru.Diagram.Style (ArrowKind (..), Theme (..), defaultTheme)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (FoldError (..), frameVertices)
import Senbazuru.Fold.Types (Assignment (..), FoldFile (..), Frame (..), VertexId (..), allFrames, emptyFrame)
import Senbazuru.Geometry (Box (..), Transform (..), V2 (..), boxSize)
import Senbazuru.Geometry.Rigid (applyRigid)
import Senbazuru.Geometry.V3 (V3 (..), modelSpan)
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Step (Motion (..), motionsBetween)
import Senbazuru.Render.Camera (Basis, SeenFrom (..), View (..), bottomUp, defaultView, frontOn, isometric, topDown)
import Senbazuru.Render.Steps
import Senbazuru.Render.Svg (defaultPage, pageTransform, renderSvg)
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
      -- A mark has no words (06 R-06-7), and nor has a line or an area,
      -- fanned or not.
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
