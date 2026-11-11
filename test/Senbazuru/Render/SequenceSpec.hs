-- | A run as a page of steps (PRDs\/06-prd-step-diagrams.md, §2): the notes a
-- run's states are drawn with, against the file the run writes (A11); the
-- page those notes draw, against @render --steps@ of that file; the caption
-- under each figure, against its state's title (R-06-21, §9); which steps
-- have a figure; how a figure the page cannot draw is refused; and the
-- arrows each figure carries, read from the records of the step that starts
-- from it, against the arrows the written states infer (R-06-16, A10).
module Senbazuru.Render.SequenceSpec (spec) where

import Control.Monad (forM, forM_)
import Data.Map.Strict qualified as M
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Diagram (ArrowHead (..), ArrowPath (..), Diagram (..), Glyph (..), Shape (..))
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid, gridOf)
import Senbazuru.Diagram.Page (FittedPage (..), Height (..), Page (..), PageFitError (..), defaultPage, fitPage)
import Senbazuru.Diagram.Style (ArrowKind (..), Theme (..), defaultTheme)
import Senbazuru.Fold.Load (loadFoldFile)
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
import Senbazuru.Render.Steps (Arrows (..), StepNote, noteArrows, noteCaption, silentNote, stepFigures, stepPage)
import Senbazuru.Sequence.Build
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Error (SequenceError (..))
import Senbazuru.Sequence.Record (MoveKind (..), Run (..), StepOutcome (..), WrittenState (..), displayAfter, displayBefore, recordKind, recordMoveIndex, recordStep, writtenStates)
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence, sheetState, workingPattern)
import Senbazuru.Sequence.Syntax (Amount (..), Compass (..), Corner (..), Layers (..), Line (..), Move (..), Name (..), PageAxis (..), Point (..), RefusalKind (..), Sense (..), Sequence (..), Turning (..))
import Senbazuru.Sequence.Write (noFileHeader, writeSequence)
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
  crane <- loadFoldFile "test/fixtures/crane.fold" >>= right
  let sheets = M.fromList [("examples/quarter-fold-steps.fold", quarterSheet), ("examples/blintz-base.fold", blintzSheet)]
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
    it "puts each single-move figure's arrows where the written states infer them (A10)" $ \r ->
      forM_ [("blintz" :: String, blintzRun r), ("quarter", quarterRun r), ("anchored", anchoredRun r), ("rotated", rotatedRun r), ("turned", turnedRun r), ("creased", creasedRun r)] $ \(name, run) -> do
        notes <- right (stepNotes run)
        inferred <- right (inferredEnds (map fst notes))
        scale <- modelSpan . concat <$> right (traverse (frameVertices . fst) notes)
        let given = map (map (\(_, a, b) -> (a, b)) . givenArrows . snd) notes
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
    -- given arrows: the last figure, the figure a turn-over starts from, the
    -- one a rotate starts from, and the one a pre-crease starts from, whose
    -- arrows are S34's. Red if a presentation or a pre-crease drew an arrow,
    -- or an empty list were given.
    it "gives NoArrows to a figure whose step turns no paper, and to the last" $ \r -> do
      turnedNotes <- right (stepNotes (turnedRun r))
      rotatedNotes <- right (stepNotes (rotatedRun r))
      creasedNotes <- right (stepNotes (creasedRun r))
      map (isGiven . snd) turnedNotes `shouldBe` [True, False, True, False]
      map (isGiven . snd) rotatedNotes `shouldBe` [False, True, True, False]
      map (isGiven . snd) creasedNotes `shouldBe` [False, True, False]
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
