-- | A run as a page of steps (PRDs\/06-prd-step-diagrams.md, §2): the notes a
-- run's states are drawn with, against the file the run writes (A11); the
-- page those notes draw, against @render --steps@ of that file; the caption
-- under each figure, against its state's title (R-06-21, §9); which steps
-- have a figure; how a figure the page cannot draw is refused; and the
-- arrows each figure carries, read from the records of the step that starts
-- from it, against the arrows the written states infer (R-06-16, A10), and a
-- pre-crease's one arc there and back, read from its folded pose (R-06-17);
-- and the fold-here lines it carries, along each fold's and pre-crease's
-- hinge (owner decision 74).
module Senbazuru.Render.SequenceSpec (spec) where

import Control.Monad (forM, forM_)
import Data.List (sort)
import Data.Map.Strict qualified as M
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Diagram (ArrowHead (..), ArrowPath (..), Diagram (..), Glyph (..), Shape (..), Stroke (..))
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid, gridOf)
import Senbazuru.Diagram.Page (FittedPage (..), Height (..), Page (..), PageFitError (..), defaultPage, fitPage)
import Senbazuru.Diagram.Style (ArrowKind (..), Theme (..), defaultTheme)
import Senbazuru.Fold.Load (loadFoldFile, readSequenceText)
import Senbazuru.Fold.Query (FoldError (..), frameVertices)
import Senbazuru.Fold.Types (FoldFile (..), Frame (..))
import Senbazuru.Geometry.Rigid (identity)
import Senbazuru.Geometry.V3 (V3 (..), modelSpan)
import Senbazuru.Origami.Folding (foldFrameWith)
import Senbazuru.Origami.Stacking (Budget (..), defaultBudget)
import Senbazuru.Origami.Step (Motion (..), motionsAcross)
import Senbazuru.Origami.Surface (surfaceFromFolded)
import Senbazuru.Render.Camera (View (..), bottomUp, defaultView, frontOn, topDown)
import Senbazuru.Render.Sequence
import Senbazuru.Render.Steps (Arrows (..), FoldLines (..), StepNote, noteArrows, noteCaption, noteFoldLines, silentNote, stepFigures, stepPage)
import Senbazuru.Render.Svg (renderSvg)
import Senbazuru.Sequence.Build
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Error (SequenceError (..))
import Senbazuru.Sequence.Parse (parseSequence)
import Senbazuru.Sequence.Record (MoveKind (..), Run (..), StepOutcome (..), WrittenState (..), displayAfter, displayBefore, recordKind, recordMoveIndex, recordStep, writtenStates)
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence, sheetState, workingPattern)
import Senbazuru.Sequence.Syntax (Amount (..), Compass (..), Corner (..), Layers (..), Line (..), Move (..), Name (..), PageAxis (..), Point (..), RefusalKind (..), Sense (..), Sequence (..), Turning (..))
import Senbazuru.Sequence.Write (noFileHeader, writeSequence)
import Test.Golden (goldenText)
import Test.Hspec
import Test.SequenceExamples (blintz, creasedTwice, quarterFold)

-- | The runs these items draw. Built in 'beforeAll', as 09 §6.3 asks of a new
-- run, so a run that is refused fails these items and no others.
data Runs = Runs
  { quarterRun :: Run,
    blintzRun :: Run,
    -- | The quarter fold with its second step's one move @expect refused@.
    refusedRun :: Run,
    -- | The quarter fold with @anchor P@ as a step between its two folds.
    holdingRun :: Run,
    -- | The quarter fold with a step of only @expect refused@ between its
    -- two folds.
    skippingRun :: Run,
    -- | The quarter fold's first fold, then a step that stops at
    -- @not modelled@.
    stoppedRun :: Run,
    -- | The quarter fold anchored at (3/4, 3/4), paper its second fold
    -- turns, so the run re-anchors and shows the model by a half turn from
    -- then on; then one step that unfolds both folds, one move of two
    -- records, whose second re-anchors again.
    anchoredRun :: Run,
    -- | The quarter fold after a step that turns the sheet a quarter turn
    -- clockwise on the page, so every fold is shown turned.
    rotatedRun :: Run,
    -- | The quarter fold with a turn-over, top to bottom, between its two
    -- folds: about a line across the second fold's, so that fold's arrow
    -- is not the same shown turned and as folded, as it would be after a
    -- turn-over left to right, about the line the arrow lies along.
    turnedRun :: Run,
    -- | The blintz's four corners folded behind in one step of four moves,
    -- then all four opened by one @unfold@: one move that turns four
    -- separate pieces of paper.
    cornersRun :: Run,
    -- | The quarter fold's first step, then a step that folds the top half
    -- down and stops at @not modelled@: its fold leaves a record and the
    -- step writes no state.
    stoppedAfterFoldRun :: Run,
    -- | A plain square pre-creased along a diagonal, then folded in half:
    -- each step adds creases ('creasedTwice').
    creasedRun :: Run,
    -- | The helmet base, as @helmet.foldseq@ writes it: a diagonal fold,
    -- then each corner of the doubled triangle brought to its tip, each
    -- through two layers whose creases lie apart on the sheet.
    helmetRun :: Run,
    -- | A plain square pre-creased along a slant and along x = 1/2, then
    -- folded top down and folded left over along x = 1/2: the last fold
    -- goes through two layers, of which the slant cut one's hinge in two
    -- and left the other's whole (the code review of #695).
    overlapRun :: Run,
    -- | A plain square whose one step pre-creases the diagonal in front and
    -- then folds along it in front: two moves, two hinges in one place.
    sameLineRun :: Run,
    -- | The same, the fold written behind: two kinds of line in one place.
    bothKindsRun :: Run,
    -- | The quarter fold on a copy of its sheet with edge 11 written the
    -- other way round, so its second fold's two hinge edges, one on each
    -- layer, lie in one place running opposite ways.
    reversedRun :: Run,
    -- | PRDs\/06 §7's pre-crease on a plain square, as
    -- @test\/fixtures\/diagonal-precrease.foldseq@ writes it: the diagonal
    -- folded in front, moving the south-east corner, and laid flat again.
    diagonalRun :: Run,
    -- | The same pre-crease written behind.
    behindRun :: Run,
    -- | The traditional crane's first three steps, which its own source
    -- cannot run on its own, since a run refuses the whole file at step 4:
    -- both diagonals pre-creased in one step, the paper turned over left to
    -- right, and both midlines pre-creased in one step.
    diagonalsRun :: Run,
    -- | Built by hand: the blintz's sheet laid flat, as a run starts it, as
    -- state 0, a step that writes it again, two steps that write no state,
    -- and a step that writes the crane folded, with no layer order, so
    -- drawing it has to work one out. One guess is not enough (StackingSpec,
    -- "the budget").
    craneRun :: Run
  }

runs :: IO Runs
runs = do
  quarterSheet <- loadFoldFile "examples/quarter-fold-steps.fold" >>= right
  blintzSheet <- loadFoldFile "examples/blintz-base.fold" >>= right
  helmetSheet <- loadFoldFile "examples/helmet-base.fold" >>= right
  helmetText <- readSequenceText "helmet.foldseq" >>= right
  helmet <- right (parseSequence "helmet.foldseq" helmetText)
  diagonalText <- readSequenceText "test/fixtures/diagonal-precrease.foldseq" >>= right
  diagonalSource <- right (parseSequence "test/fixtures/diagonal-precrease.foldseq" diagonalText)
  crane <- loadFoldFile "test/fixtures/crane.fold" >>= right
  let reversedSheet = quarterSheet {keyFrame = (keyFrame quarterSheet) {edgesVertices = [if i == (11 :: Int) then (b, a) else (a, b) | (i, (a, b)) <- zip [0 ..] (edgesVertices (keyFrame quarterSheet))]}}
      sheets = M.fromList [("examples/quarter-fold-steps.fold", quarterSheet), ("examples/blintz-base.fold", blintzSheet), ("examples/helmet-base.fold", helmetSheet), ("reversed.fold", reversedSheet)]
      ran sequence' = right (checkSequence sequence' >>= runSequence defaultRunSettings sheets . elaborate)
  laid <- right (sheetState blintzSheet) >>= right . foldFrameWith . workingPattern >>= right . surfaceFromFolded
  folded <- right (foldFrameWith (keyFrame crane)) >>= right . surfaceFromFolded
  let outcome n name end = StepOutcome n (Just (Name name)) Nothing end identity identity
      craneSteps = [outcome 1 "open" (Just laid), outcome 2 "refused" Nothing, outcome 3 "refused again" Nothing, outcome 4 "crane" (Just folded)]
  Runs
    <$> ran quarterFold
    <*> ran blintz
    <*> ran (quarterWith (expectRefused (RefusalKind "SeedMissing") (Fold ValleyFold ToFlat (Segment (MidpointOfEdge South) (MidpointOfEdge North)) FlapOfFirstArgument Nothing)))
    <*> ran holding
    <*> ran skipping
    <*> ran stopped
    <*> ran anchored
    <*> ran rotated
    <*> ran turned
    <*> ran corners
    <*> ran stoppedAfterFold
    <*> ran creasedTwice
    <*> ran helmet
    <*> ran overlap
    <*> ran sameLine
    <*> ran bothKinds
    <*> ran reversed
    <*> ran diagonalSource
    <*> ran behindDiagonal
    <*> ran diagonals
    <*> pure (Run Nothing laid identity craneSteps [] [] Nothing Nothing)
  where
    quarterWith second = sequenceOf (seqHeader quarterFold) $ do
      _ <- step "half" "Fold the left half behind, onto the right." (fold behind (LineOnto (edge West) (edge East) Nothing))
      _ <- step "quarter" "Fold the top half down in front, onto the bottom." second
      pure ()
    holding = sequenceOf (seqHeader quarterFold) $ do
      step_ "Fold the left half behind, onto the right." (fold behind (LineOnto (edge West) (edge East) Nothing))
      step_ "Hold that paper still from now on." (anchor (at (1 / 4) (1 / 4)))
      step_ "Fold the top half down in front, onto the bottom." (fold inFront (LineOnto (edge North) (edge South) Nothing))
    skipping = sequenceOf (seqHeader quarterFold) $ do
      step_ "Fold the left half behind, onto the right." (fold behind (LineOnto (edge West) (edge East) Nothing))
      step_ "Try a fold the paper refuses." (expectRefused (RefusalKind "SeedMissing") (Fold ValleyFold ToFlat (Segment (MidpointOfEdge South) (MidpointOfEdge North)) FlapOfFirstArgument Nothing))
      step_ "Fold the top half down in front, onto the bottom." (fold inFront (LineOnto (edge North) (edge South) Nothing))
    stopped = sequenceOf (seqHeader quarterFold) $ do
      step_ "Fold the left half behind, onto the right." (fold behind (LineOnto (edge West) (edge East) Nothing))
      step_ "Squash the corner flat." (notModelled "a squash fold")
    west = fold behind (LineOnto (edge West) (edge East) Nothing)
    north = fold inFront (LineOnto (edge North) (edge South) Nothing)
    anchored = sequenceOf (header "A quarter fold, opened in one step" (sheetFile "examples/quarter-fold-steps.fold") (Just (at (3 / 4) (3 / 4)))) $ do
      half <- step "half" "Fold the left half behind." west
      quarter <- step "quarter" "Fold the top half down in front." north
      step_ "Unfold both folds." (unfold [half, quarter])
    rotated = sequenceOf (seqHeader quarterFold) $ do
      step_ "Turn the sheet a quarter turn." (rotate 2 Clockwise)
      step_ "Fold the left half behind, onto the right." west
      step_ "Fold the top half down in front, onto the bottom." north
    turned = sequenceOf (seqHeader quarterFold) $ do
      step_ "Fold the left half behind, onto the right." west
      step_ "Turn the model over." (turnOver TopBottom)
      step_ "Fold the top half down in front, onto the bottom." north
    corners = sequenceOf (seqHeader blintz) $ do
      folded <- step "corners" "Fold all four corners behind, to the centre." (forM_ [SouthEast, NorthEast, NorthWest, SouthWest] (\c -> fold mountain (cornerOf c `onto` centre)))
      step_ "Open all four." (unfold [folded])
    square = header "A square" sheetSquare (Just (at (3 / 4) (1 / 4)))
    diagonal = Segment (CornerOf SouthWest) (CornerOf NorthEast)
    overlap = sequenceOf square $ do
      step_ "Crease a slant, and the middle." $ do
        move (FoldAndUnfold ValleyFold (Segment (CornerOf SouthWest) (at 1 (1 / 2))) FlapOfFirstArgument (Just (CornerOf SouthEast)))
        preCrease inFront (LineOnto (edge West) (edge East) Nothing)
      step_ "Fold the top down." (fold inFront (LineOnto (edge North) (edge South) Nothing))
      step_ "Fold the left over." (fold inFront (LineOnto (edge West) (edge East) Nothing))
    sameLine = sequenceOf square . step_ "Crease the diagonal, then fold along it." $ do
      move (FoldAndUnfold ValleyFold diagonal FlapOfFirstArgument (Just (CornerOf NorthWest)))
      move (Fold ValleyFold ToFlat diagonal FlapOfFirstArgument (Just (CornerOf NorthWest)))
    bothKinds = sequenceOf square . step_ "Crease the diagonal in front, then fold it behind." $ do
      move (FoldAndUnfold ValleyFold diagonal FlapOfFirstArgument (Just (CornerOf NorthWest)))
      move (Fold MountainFold ToFlat diagonal FlapOfFirstArgument (Just (CornerOf NorthWest)))
    reversed = sequenceOf (header "A square folded into quarters" (sheetFile "reversed.fold") (Just (at (3 / 4) (1 / 4)))) $ do
      step_ "Fold the left half behind." west
      step_ "Fold the top half down in front." north
    plain = header "A square" sheetSquare Nothing
    behindDiagonal =
      sequenceOf plain . step_ "Fold the diagonal behind and unfold it." $
        move (FoldAndUnfold MountainFold diagonal FlapOfFirstArgument (Just (CornerOf SouthEast)))
    diagonals = sequenceOf plain $ do
      step_ "Crease both diagonals." $ do
        move (FoldAndUnfold ValleyFold diagonal FlapOfFirstArgument (Just (CornerOf SouthEast)))
        move (FoldAndUnfold ValleyFold (Segment (CornerOf SouthEast) (CornerOf NorthWest)) FlapOfFirstArgument (Just (CornerOf SouthWest)))
      step_ "Turn the paper over." (turnOver LeftRight)
      step_ "Crease both midlines." $ do
        preCrease inFront (LineOnto (edge South) (edge North) Nothing)
        preCrease inFront (LineOnto (edge West) (edge East) Nothing)
    stoppedAfterFold = sequenceOf (seqHeader quarterFold) $ do
      step_ "Fold the left half behind, onto the right." west
      step_ "Fold the top half down, then squash the corner." (north >> notModelled "a squash fold")

spec :: Spec
spec = describe "a run's page" . beforeAll runs $ do
  -- A11. Turns red if stepNotes dropped, added or reordered a state, or
  -- built its frames some other way than writtenStates, which the writer
  -- uses.
  it "gives each state the run writes, as its file holds it, a note (A11)" $ \r ->
    forM_ [quarterRun r, blintzRun r] $ \run -> do
      fmap (map fst) (stepNotes run) `shouldBe` fmap otherFrames (writeSequence noFileHeader run)
      fmap length (stepNotes run) `shouldSatisfy` either (const False) (> 0)

  -- Owner decision 76's structural test, kept for the rest of M3 while notes
  -- gain fields: with every note made silent, a run's page is what
  -- render --steps draws of its file. Both sides are stepFigures laid out by
  -- gridOf, so it does not hold the page's layout; it turns red if
  -- stepNotes' frames are not the file's, as A11 does, or if render --steps
  -- stops drawing a frame with a silent note (noteFor False), which A11
  -- cannot see.
  it "draws, with every note made silent, what render --steps draws of its file" $ \r ->
    forM_ [("quarter" :: String, quarterRun r), ("blintz", blintzRun r)] $ \(name, run) -> do
      notes <- right (stepNotes run)
      file <- right (writeSequence noFileHeader run)
      let silenced = gridOf grid . map fst <$> stepFigures defaultTheme defaultBudget defaultView [(fr, silentNote) | (fr, _) <- notes]
          plain = stepPage defaultTheme defaultBudget grid defaultView False (otherFrames file)
      (name, silenced) `shouldBe` (name, plain)
      (name, fmap isJust plain) `shouldBe` (name, Right True)

  -- The composition run -o x.svg calls, and S37's golden is to, at
  -- the defaults and with each of the theme, the grid, the view, the height
  -- and the page changed. Turns red if runPage drew notes of its own rather
  -- than stepNotes', or dropped any of the five for a default; the last line
  -- is what makes dropping one show, since each changes both runs' pages.
  it "is fitPage over stepFigures over stepNotes, with the theme, grid, view, height and page it is given" $ \r ->
    forM_ [quarterRun r, blintzRun r] $ \run -> do
      notes <- right (stepNotes run)
      pages <- forM settings $ \(theme, grid', view, height, page) -> do
        figures <- right (stepFigures theme defaultBudget view notes)
        fitted <- right (runPage theme defaultBudget grid' view height page run)
        Right fitted `shouldBe` fitPage theme grid' height page figures
        pure fitted
      case pages of
        atDefaults : changed -> filter (== atDefaults) changed `shouldBe` []
        [] -> expectationFailure "no settings"

  -- D24: a step of nothing but expect refused moved no paper and writes no
  -- state, so it has no figure. The run has two steps and two figures, the
  -- sheet and the paper folded in half, whose paper is drawn as the quarter
  -- fold's first two states are; the sheet carries step 1's arrow, as the
  -- quarter fold's does, and the last figure none. Turns red if stepNotes
  -- gave such a step a figure, such as the state before it again. (Restated
  -- when notes gained arrows: it compared whole figures with silent ones.)
  it "draws no figure for a step whose moves were all expect refused" $ \r -> do
    notes <- right (stepNotes (refusedRun r))
    quarter <- right (writeSequence noFileHeader (quarterRun r))
    quarterNotes <- right (stepNotes (quarterRun r))
    length notes `shouldBe` 2
    figures <- right (stepFigures defaultTheme defaultBudget defaultView [(fr, silentNote) | (fr, _) <- notes])
    firstTwo <- right (stepFigures defaultTheme defaultBudget defaultView [(fr, silentNote) | fr <- take 2 (otherFrames quarter)])
    (map fst figures, length figures) `shouldBe` (map fst firstTwo, 2)
    map (noteArrows . snd) notes `shouldBe` [noteArrows note | (_, note) <- take 1 quarterNotes] <> [NoArrows]

  -- 06 §2: anchor P moves no paper, so the figure it starts from carries no
  -- arrows, and the model stays where it stood. That figure is state 1, the
  -- one step 1 ended at; state 2, which the anchor step ends at, starts step
  -- 3's fold. Green by construction while every note is silent; turns red if
  -- notes inferred arrows everywhere, and is meant to stay green when notes
  -- are filled from records.
  it "gives the figure an anchor P step starts from no arrows" $ \r -> do
    states <- right (writtenStates (holdingRun r))
    map stateStep states `shouldBe` [Nothing, Just 1, Just 2, Just 3]
    notes <- right (stepNotes (holdingRun r))
    case notes of
      [_, (_, startsTheAnchor), _, _] -> noteArrows startsTheAnchor `shouldBe` NoArrows
      _ -> expectationFailure ("expected four figures, got " <> show (length notes))

  describe "arrows read from move records (R-06-16)" $ do
    -- A10, restated to what can turn red. A figure whose step holds one move
    -- carries that move's arrows, and their ends are where the written
    -- states put them: what motionsAcross finds between the figure's state
    -- and the next, which is what InferArrowsAs draws, within 1e-12 of the
    -- model's span, in order. Checked on six runs because no one of them
    -- shows every fault. The blintz and the quarter fold are the two runs
    -- S37 pins as pages, and every record of either is shown as folded, so a
    -- page that skipped the records' displays would pass on them; the
    -- anchored quarter is shown by a half turn after its second fold, the
    -- rotated one by a quarter turn throughout, and the turned one over;
    -- and the creased square's fold makes a crease, so its record's paper
    -- before has vertices its figure's state lacks. Red if the ends came
    -- from the surfaces as folded and not as shown, or a step's records went
    -- to the wrong figure.
    --
    -- A pre-crease's arc is left out (restated by S34): its figure's state
    -- and the next are one flat state, which infer nothing, and the arc runs
    -- to its folded pose, which the next item holds it to.
    it "puts each single-move figure's arrows where the written states infer them (A10)" $ \r ->
      forM_ [("blintz" :: String, blintzRun r), ("quarter", quarterRun r), ("anchored", anchoredRun r), ("rotated", rotatedRun r), ("turned", turnedRun r), ("creased", creasedRun r)] $ \(name, run) -> do
        notes <- right (stepNotes run)
        inferred <- right (inferredEnds (map fst notes))
        scale <- modelSpan . concat <$> right (traverse (frameVertices . fst) notes)
        let given = map (map (\(_, a, b) -> (a, b)) . filter (not . isArc) . givenArrows . snd) notes
        (name, map length given) `shouldBe` (name, map length inferred <> [0])
        (name, maximum (0 : zipWith apart (concat given) (concat inferred))) `shouldSatisfy` ((<= 1e-12 * scale) . snd)

    -- The runs above are worth checking only if some record is shown other
    -- than as folded: these three are, the blintz and the quarter fold are
    -- not.
    it "holds runs whose records are shown turned, so the displays are tested" $ \r -> do
      let shownTurned run = [() | record <- runRecords run, recordKind record == Turn, displayBefore record /= identity || displayAfter record /= identity]
      map (null . shownTurned) [blintzRun r, quarterRun r, anchoredRun r, rotatedRun r, turnedRun r] `shouldBe` [True, True, False, False, False]

    -- The kind is the move's as written: the blintz's corners are folded
    -- behind, mountains, and its last step unfolds; the quarter fold is one
    -- fold behind and one in front. Red if the kind were read from the
    -- creases, which the quarter's second fold letters both ways, or an
    -- unfold drew a fold's head.
    it "gives each arrow the kind its move was written as, and an unfold the unfold's" $ \r -> do
      blintzNotes <- right (stepNotes (blintzRun r))
      quarterNotes <- right (stepNotes (quarterRun r))
      map (map kindOf . givenArrows . snd) blintzNotes `shouldBe` [[MountainArrow], [MountainArrow], [MountainArrow], [MountainArrow], [UnfoldArrow], []]
      map (map kindOf . givenArrows . snd) quarterNotes `shouldBe` [[MountainArrow], [ValleyArrow], []]

    -- A figure with nothing to say keeps NoArrows, never an empty list of
    -- given arrows: the last figure, the figure a turn-over starts from and
    -- the one a rotate starts from. The creased square's first figure, which
    -- its pre-crease starts from, carries the pre-crease's arc (S34). Red if
    -- a presentation drew an arrow, or an empty list were given.
    it "gives NoArrows to a figure whose step turns no paper, and to the last" $ \r -> do
      turnedNotes <- right (stepNotes (turnedRun r))
      rotatedNotes <- right (stepNotes (rotatedRun r))
      creasedNotes <- right (stepNotes (creasedRun r))
      map (isGiven . snd) turnedNotes `shouldBe` [True, False, True, False]
      map (isGiven . snd) rotatedNotes `shouldBe` [False, True, True, False]
      map (isGiven . snd) creasedNotes `shouldBe` [True, True, False]
      [noteArrows note | (_, note) <- turnedNotes <> rotatedNotes <> creasedNotes, not (isGiven note)] `shouldSatisfy` all (== NoArrows)

    -- An unfold of two folds is one move that leaves two records, and its
    -- figure carries one arrow, the one the two figures either side of it
    -- show: from the middle of the folded quarter. An arrow for each record
    -- would be two, the second starting where the figure draws no such
    -- paper; and the pair cannot be compared by face numbers, since the
    -- second record re-anchors and numbers its faces afresh. Red if the
    -- arrows were drawn for each record, or the records of one move were
    -- compared by numbering.
    it "draws one arrow for an unfold of two folds, not one for each record" $ \r -> do
      let run = anchoredRun r
      [(recordStep record, recordMoveIndex record) | record <- runRecords run, recordStep record == 3] `shouldBe` [(3, 1), (3, 1)]
      notes <- right (stepNotes run)
      inferred <- right (inferredEnds (map fst notes))
      case (drop 2 notes, drop 2 inferred) of
        ((_, opening) : _, [[(from, to)]]) -> case givenArrows opening of
          [(kind, a, b)] -> do
            kind `shouldBe` UnfoldArrow
            max (apart (a, b) (from, to)) (apart (a, b) (V3 0.75 0.25 0, V3 (5 / 12) (7 / 12) 0)) `shouldSatisfy` (<= 1e-12)
          arrows -> expectationFailure ("expected one arrow, got " <> show (length arrows))
        _ -> expectationFailure "expected the unfold's figure and one inferred motion"

    -- A step of several moves draws each move's arrows on its one figure:
    -- the blintz's four corners in one step are four arrows on the sheet,
    -- in the order the moves were written, each where the written states
    -- put one, compared as a set since the states list motions by face.
    -- Red if only a step's first move were drawn.
    --
    -- And one move draws an arrow for each piece of paper it turns: the
    -- next step opens all four corners with one unfold, one move of four
    -- records, and its figure carries four unfold arrows, one from each
    -- corner's triangle as it lies folded onto the centre. Red if only a
    -- move's first piece were drawn.
    it "draws an arrow for each move of a step, and for each piece of paper a move turns" $ \r -> do
      [(recordStep record, recordMoveIndex record) | record <- runRecords (cornersRun r), recordStep record == 2] `shouldBe` replicate 4 (2, 1)
      notes <- right (stepNotes (cornersRun r))
      inferred <- right (inferredEnds (map fst notes))
      case (notes, inferred) of
        ([(_, sheet), (_, folded), (_, opened)], [folding, opening]) -> do
          let given = givenArrows sheet
          map kindOf given `shouldBe` replicate 4 MountainArrow
          -- Each tail is the middle of its corner's triangle, in the order
          -- written: south-east, north-east, north-west, south-west.
          let corners' = [V3 x y 0 | (x, y) <- [(5 / 6, 1 / 6), (5 / 6, 5 / 6), (1 / 6, 5 / 6), (1 / 6, 1 / 6)]]
          maximum (0 : zipWith (\(_, a, _) c -> apart (a, a) (c, c)) given corners') `shouldSatisfy` (<= 1e-12)
          length folding `shouldBe` 4
          paired [(a, b) | (_, a, b) <- given] folding `shouldSatisfy` (<= 1e-12)
          map kindOf (givenArrows folded) `shouldBe` replicate 4 UnfoldArrow
          length opening `shouldBe` 4
          paired [(a, b) | (_, a, b) <- givenArrows folded] opening `shouldSatisfy` (<= 1e-12)
          noteArrows opened `shouldBe` NoArrows
        _ -> expectationFailure "expected three figures and two pairs of states"

    -- The other place where steps and states disagree: a step of only
    -- expect refused writes no state, so the fold after it starts from the
    -- state before it, and that figure carries the fold's arrow. Red if a
    -- figure took the records of the step numbered one more than the step
    -- that ended at its state.
    it "draws the arrow of the step after one that wrote no state, on the state before it" $ \r -> do
      notes <- right (stepNotes (skippingRun r))
      map (map kindOf . givenArrows . snd) notes `shouldBe` [[MountainArrow], [ValleyArrow], []]

    -- 06 §2's not modelled row, and D21: a step that folds and then stops
    -- at not modelled leaves its fold's record in the run and writes no
    -- state. The last figure carries the stopped step's caption and none of
    -- its arrows, which would show a fold the page never draws the result
    -- of. Red if a figure took the records of every step after its state,
    -- or of the step its caption names.
    it "draws no arrow for the moves of a step stopped at not modelled" $ \r -> do
      let run = stoppedAfterFoldRun r
      map recordStep (runRecords run) `shouldBe` [1, 2]
      notes <- right (stepNotes run)
      map (noteCaption . snd) notes `shouldBe` [Just "Fold the left half behind, onto the right.", Just "Fold the top half down, then squash the corner."]
      map (isGiven . snd) notes `shouldBe` [True, False]
      map (noteArrows . snd) (drop 1 notes) `shouldBe` [NoArrows]

    -- What the page then draws: the head of each kind as the page sees it.
    -- From above the quarter fold's mountain is the hollow half head and
    -- its valley the solid one; from below they swap, since the reader's
    -- valley is a mountain from behind the paper. Seen edge on from the
    -- front, where the page cannot show which, the first is drawn as written
    -- and every figure carries the edge-on mark; the second fold moves its
    -- paper straight towards the viewer, an arrow of no length on the page,
    -- which is not drawn. Red if runPage dropped the notes' arrows or the
    -- view never reached them.
    it "draws each arrow's head as the page sees its kind, and marks an edge-on page" $ \r -> do
      let headsFrom view = do
            fitted <- runPage defaultTheme defaultBudget grid view HeightToFit defaultPage {pageWidth = 600} (quarterRun r)
            pure (fmap (\page -> ([arrowHead path | Arrow path <- shapesOf (fittedDiagram page)], length [() | Symbol _ _ _ EdgeOnMark <- shapesOf (fittedDiagram page)])) fitted)
      headsFrom (View (Just topDown) 0) `shouldBe` Right (Just ([HollowHalfHead, SolidHead], 0))
      headsFrom (View (Just bottomUp) 0) `shouldBe` Right (Just ([SolidHead, HollowHalfHead], 0))
      headsFrom (View (Just frontOn) 0) `shouldBe` Right (Just ([HollowHalfHead], 3))

  describe "a pre-crease's arc, there and back (R-06-17)" $ do
    -- 06 §7 and #643's done-when, as the owner chose on 2026-11-13: one arc
    -- from the middle of the triangle the fold moves, (0, 0), (1, 0), (1, 1),
    -- whose corners' mean is (2/3, 1/3), to where it lands folded flat
    -- across y = x, (1/3, 2/3), with the fold's head at the far end and the
    -- unfold's at the near one. Compared in order, tail with tail and head
    -- with head. Red if the arc ran from the folded pose back, had no length
    -- (read from the record's paper after the move, which a pre-crease lays
    -- flat again where it began), or took any kind but the fold-and-unfold
    -- of its written sense.
    it "draws one arc from the paper a pre-crease moves to where its fold takes it" $ \r -> do
      forM_ [("in front" :: String, diagonalRun r, ValleyAndUnfoldArrow), ("behind", behindRun r, MountainAndUnfoldArrow)] $ \(name, run, kind) -> do
        notes <- right (stepNotes run)
        case map (givenArrows . snd) notes of
          [[(drawn, a, b)], []] -> do
            (name, drawn) `shouldBe` (name, kind)
            (name, apart (a, b) (V3 (2 / 3) (1 / 3) 0, V3 (1 / 3) (2 / 3) 0)) `shouldSatisfy` ((<= 1e-12) . snd)
          other -> expectationFailure (name <> ": expected one arc on the first of two figures, got " <> show other)

    -- Two pre-creases in one step draw two arcs on one figure, in the order
    -- written: the second diagonal's moving half is two triangles, whose
    -- centres (1/2, 1/6) and (1/6, 1/2) have the mean (1/3, 1/3), folded
    -- across x + y = 1 to (2/3, 2/3). After the turn-over left to right
    -- every state is shown mirrored, x going to 1 − x: the south half's three
    -- faces have the mean y 5/18 and fold to 13/18, and the west half's
    -- four, at x 1/4 on the sheet, are shown at 3/4 and fold to 1/4. Red if
    -- only a step's first pre-crease drew, or the folded pose were not shown
    -- as the figure shows the paper ('displayBefore'), which draws the last
    -- arc from 1/4 to 3/4.
    it "draws an arc for each pre-crease of a step, where its figure shows the paper" $ \r -> do
      notes <- right (stepNotes (diagonalsRun r))
      let arc a b c d = (ValleyAndUnfoldArrow, V3 a b 0, V3 c d 0)
          expected =
            [ [arc (2 / 3) (1 / 3) (1 / 3) (2 / 3), arc (1 / 3) (1 / 3) (2 / 3) (2 / 3)],
              [],
              [arc 0.5 (5 / 18) 0.5 (13 / 18), arc 0.75 0.5 0.25 0.5],
              []
            ]
          given = map (givenArrows . snd) notes
      map (map kindOf) given `shouldBe` map (map kindOf) expected
      maximum (0 : zipWith (\(_, a, b) (_, c, d) -> apart (a, b) (c, d)) (concat given) (concat expected)) `shouldSatisfy` (<= 1e-12)

    -- The owner's choice of 2026-11-13: a pre-crease and a fold along the
    -- same line in one step each draw their arrow, on one curve, in the
    -- order written, so no instruction is dropped; with a valley pre-crease
    -- and a mountain fold the mountain's head does not read over the
    -- valley's, which docs/usage.md records. Red if coincident arrows were
    -- merged, or a step's arrows reordered.
    it "draws a pre-crease's arc and a fold's arrow along one line both, in order" $ \r ->
      forM_ [("same kind" :: String, sameLineRun r, ValleyArrow), ("both kinds", bothKindsRun r, MountainArrow)] $ \(name, run, foldKind) -> do
        notes <- right (stepNotes run)
        case map (givenArrows . snd) notes of
          ([(first', a, b), (second', c, d)] : _) -> do
            (name, first', second') `shouldBe` (name, ValleyAndUnfoldArrow, foldKind)
            (name, apart (a, b) (c, d)) `shouldSatisfy` ((<= 1e-12) . snd)
          other -> expectationFailure (name <> ": expected two arrows on the first figure, got " <> show other)

    -- What the page draws: one arrow with a head at each end, the fold's
    -- head as the page sees it and the unfold's double head at its tail.
    -- From below the valley's solid head is the mountain's half head, and
    -- the mountain's the valley's, and the unfold's is the same from either
    -- side. Seen edge on from the front, where the page cannot show which
    -- side it sees, each is drawn as written (the code review of #696). Red
    -- if the page drew the arc without its tail, or two arrows, swapped the
    -- tail with the side, or swapped either kind's head edge on.
    it "draws a pre-crease as one arrow with a head at each end" $ \r -> do
      let ends run view = do
            fitted <- runPage defaultTheme defaultBudget grid view HeightToFit defaultPage run
            pure (fmap (\page -> [(arrowHead path, arrowTail path) | Arrow path <- shapesOf (fittedDiagram page)]) fitted)
      ends (diagonalRun r) (View (Just topDown) 0) `shouldBe` Right (Just [(SolidHead, Just HollowDoubleHead)])
      ends (diagonalRun r) (View (Just bottomUp) 0) `shouldBe` Right (Just [(HollowHalfHead, Just HollowDoubleHead)])
      ends (diagonalRun r) (View (Just frontOn) 0) `shouldBe` Right (Just [(SolidHead, Just HollowDoubleHead)])
      ends (behindRun r) (View (Just topDown) 0) `shouldBe` Right (Just [(HollowHalfHead, Just HollowDoubleHead)])
      ends (behindRun r) (View (Just bottomUp) 0) `shouldBe` Right (Just [(SolidHead, Just HollowDoubleHead)])
      ends (behindRun r) (View (Just frontOn) 0) `shouldBe` Right (Just [(HollowHalfHead, Just HollowDoubleHead)])

    -- 06's New goldens row: the page run -o x.svg writes of 06 §7's run, at
    -- run's defaults, so the bytes are the CLI's. Read rasterised: on figure
    -- 1 one arc with a solid head at the top left and a hollow double head
    -- at its tail, one valley-dashed line along the diagonal and no crease;
    -- on figure 2 the sheet with the faint crease the pre-crease left. Red
    -- if no arrow were drawn, the unfold's head were solid, or the line were
    -- missing.
    it "draws diagonal-precrease-steps.svg" $ \r -> do
      let run = diagonalRun r
      fitted <- right (runPage defaultTheme defaultBudget grid defaultView HeightToFit defaultPage {pageTitle = runTitle run} run) >>= maybe (fail "no page") pure
      goldenText "test/golden/diagonal-precrease-steps.svg" (renderSvg (fittedPage fitted) (fittedDiagram fitted))

  describe "fold-here lines along each hinge (owner decision 74)" $ do
    -- The done-when's lines, read off each note and not off the drawn page,
    -- which drops a line of no length and any line of an unfold: so a line
    -- for each stretch of a hinge carried over to the figure by its two ends
    -- on the sheet, which folding doubles over, would draw nothing on figure
    -- 2 and still pass a test of the page. Figure 1 has the first fold's
    -- hinge, the sheet's line x = 1/2 in its two pieces, as a mountain, the
    -- fold being written behind; figure 2 the second fold's, y = 1/2 from
    -- the middle to the right edge, as a valley: two edges, one on each
    -- layer, in one place, drawn once. Red if a stretch's ends were carried
    -- over, coincident edges were each drawn, or the kind were not the
    -- written sense.
    it "draws the quarter fold's hinges, an edge each, coincident edges once" $ \r -> do
      notes <- right (stepNotes (quarterRun r))
      map (sort . map unordered . givenLines . snd) notes
        `shouldBe` map
          (sort . map unordered)
          [ [(MountainArrow, V3 0.5 0.5 0, V3 0.5 0 0), (MountainArrow, V3 0.5 0.5 0, V3 0.5 1 0)],
            [(ValleyArrow, V3 0.5 0.5 0, V3 1 0.5 0)],
            []
          ]
      map (noteFoldLines . snd) (drop 2 notes) `shouldBe` [NoFoldLines]

    -- An unfold draws no line, as the owner confirmed on 2026-11-12, though
    -- its record carries the hinge it opens along: the blintz's figure 5,
    -- its unfold, has NoFoldLines, and each corner fold before it one
    -- mountain line along its diagonal. Red if every record of a turn drew
    -- its hinge, whatever its kind; the page alone would not show it, since
    -- an unfold's line is not drawn.
    it "draws no line for an unfold, and the blintz's corner folds one each" $ \r -> do
      notes <- right (stepNotes (blintzRun r))
      map (map kindOf . givenLines . snd) notes `shouldBe` replicate 4 [MountainArrow] <> [[], []]
      map (noteFoldLines . snd) (drop 4 notes) `shouldBe` [NoFoldLines, NoFoldLines]
      -- Each corner's line runs between the midpoints of the two sides that
      -- meet at it, where the figure has its paper: south-east first.
      case notes of
        (_, first') : _ -> map unordered (givenLines first') `shouldMatchList` [unordered (MountainArrow, V3 0.5 0 0, V3 1 0.5 0)]
        [] -> expectationFailure "no figures"

    -- A pre-crease draws its line, in the sense it was written: the creased
    -- square's first step creases the diagonal as a valley, and its figure,
    -- the plain sheet, has no crease there at all. Red if lines were drawn
    -- only for turns.
    it "draws a pre-crease's line, where the figure has no crease yet" $ \r -> do
      notes <- right (stepNotes (creasedRun r))
      case notes of
        (sheet, creasing) : _ -> do
          map unordered (givenLines creasing) `shouldMatchList` [unordered (ValleyArrow, V3 0 0 0, V3 1 1 0)]
          length (edgesVertices sheet) `shouldBe` 4
        [] -> expectationFailure "no figures"

    -- Lines are where the figure shows the paper: on the rotated quarter
    -- every state is shown a quarter turn clockwise, so the first fold's
    -- hinge, the sheet's x = 1/2, lies along y = 1/2 on the page, and on the
    -- anchored quarter the second fold is shown by a half turn. Each line's
    -- ends are vertices of the figure's own state. Red if the lines were
    -- read from the paper as folded and not as shown.
    it "puts each line where its figure shows the paper" $ \r ->
      forM_ [("rotated" :: String, rotatedRun r), ("anchored", anchoredRun r), ("turned", turnedRun r)] $ \(name, run) -> do
        notes <- right (stepNotes run)
        forM_ notes $ \(fr, note) -> do
          points <- right (frameVertices fr)
          let onFigure p = any (\q -> apart (p, p) (q, q) <= 1e-12) points
          (name, [(a, b) | (_, a, b) <- givenLines note, not (onFigure a && onFigure b)]) `shouldBe` (name, [])
        rotated <- right (stepNotes (rotatedRun r))
        case drop 1 rotated of
          (_, folding) : _ -> map (\(_, V3 _ y0 _, V3 _ y1 _) -> (y0, y1)) (givenLines folding) `shouldSatisfy` all (\(y0, y1) -> abs (y0 - 0.5) <= 1e-12 && abs (y1 - 0.5) <= 1e-12)
          [] -> expectationFailure "no figures"

    -- The same line on two layers is drawn once even where folding put its
    -- two edges a few bits apart: each of the helmet's corner folds turns
    -- two layers whose creases lie apart on the sheet, two stretches, and
    -- on the figure their edges agree only to about 1e-16. Red if lines
    -- were merged only when exactly equal.
    it "draws the helmet's doubled hinges once, though folding put their edges bits apart" $ \r -> do
      notes <- right (stepNotes (helmetRun r))
      map (sort . map unordered . givenLines . snd) notes
        `shouldBe` map
          (sort . map unordered)
          [ [(ValleyArrow, V3 0 0 0, V3 0.5 0.5 0), (ValleyArrow, V3 0.5 0.5 0, V3 1 1 0)],
            [(ValleyArrow, V3 0.5 0 0, V3 0.5 0.5 0)],
            [(ValleyArrow, V3 0.5 0.5 0, V3 1 0.5 0)],
            []
          ]

    -- A layer's whole edge and the pieces another layer's creases cut the
    -- same line into are drawn as one line, the span they cover: the last
    -- fold of the overlap run goes through two layers, the slant having cut
    -- one's hinge at (1/2, 1/4) and not the other's. Three lines over each
    -- other would start their dashes at different points and read solid.
    -- Red if lines were merged only when both their ends coincide.
    it "draws a whole hinge and another layer's pieces of it as one line" $ \r -> do
      notes <- right (stepNotes (overlapRun r))
      case drop 2 notes of
        (_, leftOver) : _ -> map unordered (givenLines leftOver) `shouldMatchList` [unordered (ValleyArrow, V3 0.5 0 0, V3 0.5 0.5 0)]
        [] -> expectationFailure "expected the third figure"

    -- The merge is across the step, not within a record: a pre-crease and
    -- then a fold along the same diagonal, both in front, are two records
    -- whose lines lie in one place, and are drawn once. Written behind, the
    -- fold's line is a mountain, and both lines are kept, so neither
    -- instruction is dropped. Red if lines were merged only within a
    -- record, or whatever their kind.
    it "draws two moves' lines in one place once, unless their kinds differ" $ \r -> do
      same <- right (stepNotes (sameLineRun r))
      both <- right (stepNotes (bothKindsRun r))
      case (same, both) of
        ((_, once) : _, (_, twice) : _) -> do
          map unordered (givenLines once) `shouldMatchList` [unordered (ValleyArrow, V3 0 0 0, V3 1 1 0)]
          map unordered (givenLines twice) `shouldMatchList` [unordered (ValleyArrow, V3 0 0 0, V3 1 1 0), unordered (MountainArrow, V3 0 0 0, V3 1 1 0)]
        _ -> expectationFailure "expected figures"

    -- Two edges in one place running opposite ways are the same line: the
    -- reversed quarter's second fold draws one valley line, as the quarter
    -- does. Red if lines were joined only when they ran the same way.
    it "draws one line for two edges in one place running opposite ways" $ \r -> do
      notes <- right (stepNotes (reversedRun r))
      case drop 1 notes of
        (_, folding) : _ -> map unordered (givenLines folding) `shouldMatchList` [unordered (ValleyArrow, V3 0.5 0.5 0, V3 1 0.5 0)]
        [] -> expectationFailure "expected the second figure"

    -- A fold that creases fresh paper names its hinge by edges of that
    -- newly cut paper, which the figure's state does not have: the creased
    -- square's fold behind, along x = 1/2, which the diagonal crosses at
    -- the middle, draws its two mountain halves. Red if the hinge's edges
    -- were looked up in the figure's state, where they name other edges or
    -- none.
    it "draws a creasing fold's line from the paper it creased" $ \r -> do
      notes <- right (stepNotes (creasedRun r))
      case drop 1 notes of
        (_, folding) : _ -> map unordered (givenLines folding) `shouldMatchList` map unordered [(MountainArrow, V3 0.5 1 0, V3 0.5 0.5 0), (MountainArrow, V3 0.5 0.5 0, V3 0.5 0 0)]
        [] -> expectationFailure "expected the second figure"

    -- A step of several folds draws each fold's line on its one figure:
    -- the blintz's four corners folded in one step draw four mountain lines
    -- on the sheet, each along its corner's diagonal, read from the paper
    -- each fold starts from. Red if only a step's first move drew a line.
    it "draws a line for each fold of a step that holds several" $ \r -> do
      notes <- right (stepNotes (cornersRun r))
      case notes of
        (_, sheet) : _ ->
          map unordered (givenLines sheet)
            `shouldMatchList` [ unordered (MountainArrow, a, b)
                                | (a, b) <- [(V3 0.5 0 0, V3 1 0.5 0), (V3 1 0.5 0, V3 0.5 1 0), (V3 0.5 1 0, V3 0 0.5 0), (V3 0 0.5 0, V3 0.5 0 0)]
                              ]
        [] -> expectationFailure "no figures"

    -- The page draws them as it draws a given line: from above, figure 1's
    -- mountain lines with the mountain dash and figure 2's valley with the
    -- valley dash; from below, swapped. Red if runPage dropped the notes'
    -- lines.
    it "draws each line's dash as the page sees its kind" $ \r -> do
      let dashesFrom view = do
            fitted <- runPage defaultTheme defaultBudget grid view HeightToFit defaultPage {pageWidth = 600} (quarterRun r)
            pure (fmap (\page -> [dash | Polyline (Stroke _ _ dash) _ <- shapesOf (fittedDiagram page), dash `elem` [mountainDash, valleyDash]]) fitted)
          mountainDash = themeMountainDash defaultTheme
          valleyDash = themeValleyDash defaultTheme
      dashesFrom (View (Just topDown) 0) `shouldBe` Right (Just [mountainDash, mountainDash, valleyDash])
      dashesFrom (View (Just bottomUp) 0) `shouldBe` Right (Just [valleyDash, valleyDash, mountainDash])

  -- A figure the page cannot draw is named by the step that ended at its
  -- state. In the crane run that is state 2, the third figure, which step 4
  -- ended at, because steps 2 and 3 wrote no state: the three numbers
  -- differ, so a refusal naming the step by the state's number or the
  -- figure's, or naming the state before or after, would each be red. With
  -- one step writing no state, the figure's number and the step's would
  -- agree and the second would pass. With the default budget the same run
  -- draws, so the refusal is the budget's.
  describe "a figure the page cannot draw" $ do
    it "is refused as the step that ended at its state" $ \r -> do
      runPage defaultTheme (Budget 1) grid defaultView HeightToFit defaultPage (craneRun r)
        `shouldBe` Left (RunRefused (PageRefused 2 (Just (4, Just (Name "crane"))) (GaveUpStacking 1)))
      fmap isJust (runPage defaultTheme defaultBudget grid defaultView HeightToFit defaultPage (craneRun r)) `shouldBe` Right True

    it "is refused as state 0 when it is the sheet, which no step made" $ \r -> do
      let folded = [end | StepOutcome {outcomeEnd = Just end, outcomeStep = 4} <- runSteps (craneRun r)]
      case folded of
        [end] ->
          runPage defaultTheme (Budget 1) grid defaultView HeightToFit defaultPage (craneRun r) {runStart = end, runSteps = []}
            `shouldBe` Left (RunRefused (PageRefused 0 Nothing (GaveUpStacking 1)))
        _ -> expectationFailure "expected the crane run's step 4 to write the folded crane"

  -- R-06-21 and 06 §9: the caption under a figure is its state's title, the
  -- instruction of the next step that writes a state, so the words the page
  -- prints are the ones the file holds. Red if stepNotes took captions from
  -- anywhere but the written frames, or shifted them a state.
  describe "captions" $ do
    it "captions each figure with its state's title" $ \r ->
      forM_ [quarterRun r, blintzRun r] $ \run -> do
        notes <- right (stepNotes run)
        file <- right (writeSequence noFileHeader run)
        map (noteCaption . snd) notes `shouldBe` map frameTitle (otherFrames file)
        map (noteCaption . snd) notes `shouldSatisfy` any isJust

    -- The sheet carries step 1's instruction, and the last figure the closing
    -- line: an off-by-one that is not (06 §9).
    it "puts each step's instruction under the figure it starts from, and the closing line last" $ \r -> do
      notes <- right (stepNotes (quarterRun r))
      map (noteCaption . snd) notes
        `shouldBe` [ Just "Fold the left half behind, onto the right.",
                     Just "Fold the top half down in front, onto the bottom.",
                     Just "Folded into quarters."
                   ]

    -- D24: a step of only expect refused writes no state, so its caption is
    -- on no figure, and the state before it carries the next step that
    -- writes one. Red if captions were taken from steps by number rather
    -- than from the states written.
    it "puts no figure under a step that writes no state, and passes its place to the next" $ \r -> do
      notes <- right (stepNotes (skippingRun r))
      map (noteCaption . snd) notes
        `shouldBe` [ Just "Fold the left half behind, onto the right.",
                     Just "Fold the top half down in front, onto the bottom.",
                     Just "Folded into quarters."
                   ]

    -- A run stopped at not modelled keeps the states before the gap, and its
    -- last figure carries the stopped step's caption, not the closing line:
    -- that is the step the reader would fold from it.
    it "captions the last figure of a stopped run with the step it stopped at" $ \r -> do
      notes <- right (stepNotes (stoppedRun r))
      map (noteCaption . snd) notes
        `shouldBe` [Just "Fold the left half behind, onto the right.", Just "Squash the corner flat."]

    -- The page prints them: every word of every caption, in order, as the
    -- lines of the figure it belongs to. Red if runPage laid the figures out
    -- without their captions.
    it "prints each caption under its figure" $ \r -> do
      fitted <- right (runPage defaultTheme defaultBudget grid defaultView HeightToFit defaultPage (quarterRun r)) >>= maybe (fail "no page") pure
      notes <- right (stepNotes (quarterRun r))
      wordsOf (captionLines (fittedDiagram fitted)) `shouldBe` concatMap (maybe [] wordsOfOne . noteCaption . snd) notes

    -- A page too short for its captions is the page's refusal, not the
    -- run's: a taller page draws the same run, so it is never told as a
    -- refusal of the source. 28 page units inside a page 60 tall cannot
    -- hold even a one-line band of 32.
    it "refuses a page too short for its captions as the page's, not the run's" $ \r ->
      runPage defaultTheme defaultBudget grid defaultView HeightAsGiven defaultPage {pageHeight = 60} (quarterRun r)
        `shouldSatisfy` \case
          Left (PageDoesNotFit (TooShortForCaptions 60 16 _)) -> True
          _ -> False
  where
    grid = defaultGrid defaultTheme
    -- The defaults, then each of the five changed alone: the theme twice,
    -- once in what draws the figures, the paper, and once in what sets the
    -- captions, the type size, which only fitPage reads.
    settings =
      [ (defaultTheme, grid, defaultView, HeightToFit, defaultPage),
        (defaultTheme {themePaper = Nothing}, grid, defaultView, HeightToFit, defaultPage),
        (defaultTheme {themeLabelSize = 10}, grid, defaultView, HeightToFit, defaultPage),
        (defaultTheme, grid {gridColumns = 2}, defaultView, HeightToFit, defaultPage),
        (defaultTheme, grid, View (Just bottomUp) 0, HeightToFit, defaultPage),
        (defaultTheme, grid, defaultView, HeightAsGiven, defaultPage),
        (defaultTheme, grid, defaultView, HeightToFit, defaultPage {pageWidth = 600})
      ]
    captionLines d = [t | Offset _ (Label _ _ _ t) <- diagramShapes d]
    wordsOf = concatMap wordsOfOne
    wordsOfOne :: Text -> [Text]
    wordsOfOne = T.words
    kindOf (kind, _, _) = kind
    -- How far the worst-matched arrow of either list is from its nearest in
    -- the other: each given arrow has an inferred one at its place, and each
    -- inferred one a given. Paired by nearness, since sorting would order
    -- two lists differently where they differ in a last digit.
    paired :: [(V3, V3)] -> [(V3, V3)] -> Double
    paired as bs = maximum (0 : map (`nearest` bs) as <> map (`nearest` as) bs)
    nearest arrow others = minimum (map (apart arrow) others)
    isGiven note = not (null (givenArrows note))
    -- A pre-crease's arc, there and back.
    isArc (kind, _, _) = kind `elem` [ValleyAndUnfoldArrow, MountainAndUnfoldArrow]

-- | The fold-here lines a note gives, or none for a note that gives none.
givenLines :: StepNote -> [(ArrowKind, V3, V3)]
givenLines note = case noteFoldLines note of
  GivenFoldLines foldLines -> foldLines
  _ -> []

-- | A line with its two ends in a fixed order, so lines can be compared
-- whichever way round each was drawn, and its kind by name, so a list of
-- them can be sorted. Rounded to a billionth, since a
-- line's ends are where folding put them, and the same point folded two
-- ways can differ in the last bits.
unordered :: (ArrowKind, V3, V3) -> (String, (Double, Double, Double), (Double, Double, Double))
unordered (kind, a, b) = (show kind, min (key a) (key b), max (key a) (key b))
  where
    key (V3 x y z) = (snap x, snap y, snap z)
    snap v = fromIntegral (round (v * 1e9) :: Integer) / 1e9

-- | The arrows a note gives, or none for a note that gives none.
givenArrows :: StepNote -> [(ArrowKind, V3, V3)]
givenArrows note = case noteArrows note of
  GivenArrows arrows -> arrows
  _ -> []

-- | What the written states infer between each frame and the next: the two
-- ends of each motion 'motionsAcross' finds, which is what a page drawn from
-- the file with @InferArrowsAs@ draws its arrows between.
inferredEnds :: [Frame] -> Either FoldError [[(V3, V3)]]
inferredEnds frames = traverse (\(a, b) -> map (\m -> (motionFrom m, motionTo m)) <$> motionsAcross a b) (zip frames (drop 1 frames))

-- | How far apart two arrows are: the larger of the distances between their
-- tails and between their heads, along any one axis.
apart :: (V3, V3) -> (V3, V3) -> Double
apart (a, b) (c, d) = max (gap a c) (gap b d)
  where
    gap (V3 x y z) (V3 u v w) = maximum (map abs [x - u, y - v, z - w])

-- | Every shape of a diagram, with the ones a page moved into place
-- unwrapped.
shapesOf :: Diagram -> [Shape]
shapesOf d = [unwrapped shape | shape <- diagramShapes d]
  where
    unwrapped = \case
      Offset _ inner -> unwrapped inner
      other -> other

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
