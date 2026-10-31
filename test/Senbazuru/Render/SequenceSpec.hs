-- | A run as a page of steps (PRDs\/06-prd-step-diagrams.md, §2): the notes a
-- run's states are drawn with, against the file the run writes (A11); the
-- page those notes draw, against @render --steps@ of that file; which steps
-- have a figure; and how a figure the page cannot draw is refused.
module Senbazuru.Render.SequenceSpec (spec) where

import Control.Monad (forM, forM_)
import Data.Map.Strict qualified as M
import Data.Maybe (isJust)
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid)
import Senbazuru.Diagram.Style (Theme (..), defaultTheme)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (FoldError (..))
import Senbazuru.Fold.Types (FoldFile (..))
import Senbazuru.Geometry.Rigid (identity)
import Senbazuru.Origami.Folding (foldFrameWith)
import Senbazuru.Origami.Stacking (Budget (..), defaultBudget)
import Senbazuru.Origami.Surface (surfaceFromFolded)
import Senbazuru.Render.Camera (View (..), bottomUp, defaultView)
import Senbazuru.Render.Sequence
import Senbazuru.Render.Steps (Arrows (..), noteArrows, silentNote, stepPage, stepPageWith)
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
    -- | Built by hand: the blintz's sheet laid flat, as a run starts it, as
    -- state 0, a step that writes it again, a step that writes no state, and
    -- a step that writes the crane folded, with no layer order, so drawing it
    -- has to work one out. One guess is not enough (StackingSpec, "the
    -- budget").
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
      craneSteps = [outcome 1 "open" (Just laid), outcome 2 "refused" Nothing, outcome 3 "crane" (Just folded)]
  Runs
    <$> ran quarterFold
    <*> ran blintz
    <*> ran (quarterWith (expectRefused (RefusalKind "SeedMissing") (Fold ValleyFold ToFlat (Segment (MidpointOfEdge South) (MidpointOfEdge North)) FlapOfFirstArgument Nothing)))
    <*> ran holding
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

spec :: Spec
spec = describe "a run's page" . beforeAll runs $ do
  -- A11. Turns red if stepNotes dropped, added or reordered a state, or
  -- built its frames some other way than writtenStates, which the writer
  -- uses.
  it "gives each state the run writes, as its file holds it, a note (A11)" $ \r ->
    forM_ [quarterRun r, blintzRun r] $ \run -> do
      fmap (map fst) (stepNotes run) `shouldBe` fmap otherFrames (writeSequence noFileHeader run)
      fmap length (stepNotes run) `shouldSatisfy` either (const False) (> 0)

  -- Kept for the rest of M3, while notes gain fields: with every note made
  -- silent, a run's page is what render --steps draws of its file, so the
  -- paper and the layout hold whatever the notes add. Turns red if a figure
  -- were drawn from anything but its state, or laid out another way.
  it "draws, with every note made silent, what render --steps draws of its file" $ \r ->
    forM_ [("quarter" :: String, quarterRun r), ("blintz", blintzRun r)] $ \(name, run) -> do
      notes <- right (stepNotes run)
      file <- right (writeSequence noFileHeader run)
      let silenced = stepPageWith defaultTheme defaultBudget grid defaultView [(fr, silentNote) | (fr, _) <- notes]
          plain = stepPage defaultTheme defaultBudget grid defaultView False (otherFrames file)
      (name, silenced) `shouldBe` (name, plain)
      (name, fmap isJust plain) `shouldBe` (name, Right True)

  -- The composition the command line and S37's golden both call, at the
  -- defaults and with each of the theme, the grid and the view changed.
  -- Turns red if runPage drew notes of its own rather than stepNotes', or
  -- dropped any of the three for a default; the last line is what makes
  -- dropping one show, since each changes the quarter fold's page.
  it "is stepPageWith over stepNotes, with the theme, grid and view it is given" $ \r ->
    forM_ [quarterRun r, blintzRun r] $ \run -> do
      notes <- right (stepNotes run)
      pages <- forM settings $ \(theme, grid', view) -> do
        page <- right (runPage theme defaultBudget grid' view run)
        Right page `shouldBe` stepPageWith theme defaultBudget grid' view notes
        pure page
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
    page <- right (runPage defaultTheme defaultBudget grid defaultView (refusedRun r))
    firstTwo <- right (stepPage defaultTheme defaultBudget grid defaultView False (take 2 (otherFrames quarter)))
    (page, isJust page) `shouldBe` (firstTwo, True)

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
  -- state. In the crane run that is state 2, the third figure, which step 3
  -- ended at, because step 2 wrote no state: so a refusal naming the state's
  -- number, the figure's, or the step before or after would each be red.
  -- With the default budget the same run draws, so the refusal is the
  -- budget's.
  describe "a figure the page cannot draw" $ do
    it "is refused as the step that ended at its state" $ \r -> do
      runPage defaultTheme (Budget 1) grid defaultView (craneRun r)
        `shouldBe` Left (PageRefused 2 (Just (3, Just (Name "crane"))) (GaveUpStacking 1))
      fmap isJust (runPage defaultTheme defaultBudget grid defaultView (craneRun r)) `shouldBe` Right True

    it "is refused as state 0 when it is the sheet, which no step made" $ \r -> do
      let folded = [end | StepOutcome {outcomeEnd = Just end, outcomeStep = 3} <- runSteps (craneRun r)]
      case folded of
        [end] ->
          runPage defaultTheme (Budget 1) grid defaultView (craneRun r) {runStart = end, runSteps = []}
            `shouldBe` Left (PageRefused 0 Nothing (GaveUpStacking 1))
        _ -> expectationFailure "expected the crane run's step 3 to write the folded crane"
  where
    grid = defaultGrid defaultTheme
    -- The defaults, then each of the three changed alone.
    settings =
      [ (defaultTheme, grid, defaultView),
        (defaultTheme {themePaper = Nothing}, grid, defaultView),
        (defaultTheme, grid {gridColumns = 2}, defaultView),
        (defaultTheme, grid, View (Just bottomUp) 0)
      ]

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
