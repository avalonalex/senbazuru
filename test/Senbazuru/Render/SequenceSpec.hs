-- | A run as a page of steps (PRDs\/06-prd-step-diagrams.md, §2): the notes a
-- run's states are drawn with, against the file the run writes (A11); the
-- page those notes draw, against @render --steps@ of that file; the caption
-- under each figure, against its state's title (R-06-21, §9); which steps
-- have a figure; and how a figure the page cannot draw is refused.
module Senbazuru.Render.SequenceSpec (spec) where

import Control.Monad (forM, forM_)
import Data.Map.Strict qualified as M
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Diagram (Diagram (..), Shape (..))
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid, gridOf)
import Senbazuru.Diagram.Page (FittedPage (..), Height (..), Page (..), PageFitError (..), defaultPage, fitPage)
import Senbazuru.Diagram.Style (Theme (..), defaultTheme)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (FoldError (..))
import Senbazuru.Fold.Types (FoldFile (..), Frame (..))
import Senbazuru.Geometry.Rigid (identity)
import Senbazuru.Origami.Folding (foldFrameWith)
import Senbazuru.Origami.Stacking (Budget (..), defaultBudget)
import Senbazuru.Origami.Surface (surfaceFromFolded)
import Senbazuru.Render.Camera (View (..), bottomUp, defaultView)
import Senbazuru.Render.Sequence
import Senbazuru.Render.Steps (Arrows (..), noteArrows, noteCaption, silentNote, stepFigures, stepPage)
import Senbazuru.Sequence.Build
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Error (SequenceError (..))
import Senbazuru.Sequence.Record (Run (..), StepOutcome (..), WrittenState (..), writtenStates)
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence, sheetState, workingPattern)
import Senbazuru.Sequence.Syntax (Amount (..), Compass (..), Layers (..), Line (..), Move (..), Name (..), Point (..), RefusalKind (..), Sense (..), Sequence (..))
import Senbazuru.Sequence.Write (noFileHeader, writeSequence)
import Test.Hspec
import Test.SequenceExamples (blintz, quarterFold)

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
  -- sheet and the paper folded in half, drawn as the quarter fold's first
  -- two states are. Turns red if stepNotes gave such a step a figure, such as
  -- the state before it again.
  it "draws no figure for a step whose moves were all expect refused" $ \r -> do
    notes <- right (stepNotes (refusedRun r))
    quarter <- right (writeSequence noFileHeader (quarterRun r))
    length notes `shouldBe` 2
    figures <- right (stepFigures defaultTheme defaultBudget defaultView notes)
    firstTwo <- right (stepFigures defaultTheme defaultBudget defaultView [(fr, silentNote) | fr <- take 2 (otherFrames quarter)])
    (map fst figures, length figures) `shouldBe` (map fst firstTwo, 2)

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
    -- The defaults, then each of the five changed alone.
    settings =
      [ (defaultTheme, grid, defaultView, HeightToFit, defaultPage),
        (defaultTheme {themePaper = Nothing}, grid, defaultView, HeightToFit, defaultPage),
        (defaultTheme, grid {gridColumns = 2}, defaultView, HeightToFit, defaultPage),
        (defaultTheme, grid, View (Just bottomUp) 0, HeightToFit, defaultPage),
        (defaultTheme, grid, defaultView, HeightAsGiven, defaultPage),
        (defaultTheme, grid, defaultView, HeightToFit, defaultPage {pageWidth = 600})
      ]
    captionLines d = [t | Offset _ (Label _ _ _ t) <- diagramShapes d]
    wordsOf = concatMap wordsOfOne
    wordsOfOne :: Text -> [Text]
    wordsOfOne = T.words

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
