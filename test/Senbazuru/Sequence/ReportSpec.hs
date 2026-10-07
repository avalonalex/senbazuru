-- | A run's report, 'renderRunReport' (PRDs\/04-prd-sequence-source-and-cli.md,
-- R-04-24 and A19): what each move did, one fact to a line, for a person to
-- read beside the file a run writes.
module Senbazuru.Sequence.ReportSpec (spec) where

import Control.Monad (forM_)
import Data.Map.Strict qualified as M
import Data.Text qualified as T
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Sequence.Build
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Error (SequenceError)
import Senbazuru.Sequence.Record (Run, renderRunReport)
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence)
import Senbazuru.Sequence.Syntax (Amount (..), Compass (..), Corner (..), Layers (..), Line (..), Move (..), Point (..), RefusalKind (..), Sense (..), Sequence)
import Test.Golden (goldenText)
import Test.Hspec
import Test.SequenceExamples (blintz, quarterFold)

spec :: Spec
spec = describe "a run's report" $ do
  quarterSheet <- runIO (loadFoldFile "examples/quarter-fold-steps.fold" >>= right)
  blintzSheet <- runIO (loadFoldFile "examples/blintz-base.fold" >>= right)
  let sheets = M.fromList [("examples/quarter-fold-steps.fold", quarterSheet), ("examples/blintz-base.fold", blintzSheet)]
      runOn :: Sequence -> Either SequenceError Run
      runOn sequence' = checkSequence sequence' >>= runSequence defaultRunSettings sheets . elaborate
  quarter <- runIO (right (renderRunReport <$> runOn quarterFold))

  -- A19: the quarter fold, with every row the record has a field for so far:
  -- what checked the move, the line and the point its references named, the
  -- paper it moved, its hinge and the face it held still.
  it "reports the quarter fold, one fact to a line (A19)" $
    goldenText "test/golden/quarter-fold-report.txt" (T.unlines quarter)

  it "has every row the record has a field for, under each move" $
    forM_ ["checked: ", "line ", "named by ", "moving: ", "hinge: ", "held still: "] $ \row ->
      length (filter (T.isPrefixOf ("  " <> row)) quarter) `shouldBe` 2

  -- A19's second golden: the blintz's four corners, then E10's move, which
  -- carries the first corner on through the centre, wrapped in
  -- expect refused. It has no record, and the report is the only place its
  -- outcome shows.
  it "reports an expected refusal, which nothing else records (A19)" $ do
    report <- right (renderRunReport <$> runOn carriedOn)
    goldenText "test/golden/blintz-expected-report.txt" (T.unlines report)
    filter (T.isPrefixOf "step 5") report `shouldBe` ["step 5, move 1: expect refused FlapEndpointOrder"]

  -- The blintz's own last step reopens c1: an unfold, whose record names the
  -- step it turns back, since one unfold of several steps makes a record for
  -- each under the same heading.
  it "names the step an unfold turns back" $ do
    report <- right (renderRunReport <$> runOn blintz)
    filter (T.isPrefixOf "  turns back: ") report `shouldBe` ["  turns back: step 1 (c1)"]

  -- An expected refusal in a step the run then stops in: the step finished
  -- no outcome, and its name comes from the stop.
  it "names the step of an expected refusal the run stopped in" $ do
    report <- right (renderRunReport <$> runOn (stoppedQuarterWith (expectRefused (RefusalKind "SeedMissing") (Fold ValleyFold ToFlat (Segment (MidpointOfEdge South) (MidpointOfEdge North)) FlapOfFirstArgument Nothing) >> notModelled "fold in quarters")))
    filter (T.isPrefixOf "step 2") report `shouldBe` ["step 2 (quarter), move 1: expect refused SeedMissing"]

  it "ends with where a run stopped, if it did" $ do
    report <- right (renderRunReport <$> runOn stoppedQuarter)
    last report `shouldBe` "stopped: step 2 (quarter): \"fold in quarters\" is not modelled, so the run stops here and keeps the moves before it"
  where
    carriedOn = sequenceOf (header "Blintz, then carry a corner on" (sheetFile "examples/blintz-base.fold") (Just centre)) $ do
      c1 <- step "c1" "Fold the south-east corner behind, to the centre." (fold mountain (cornerOf SouthEast `onto` centre))
      forM_ [NorthEast, NorthWest, SouthWest] $ \c -> step_ "Fold the next corner behind, to the centre." (fold mountain (cornerOf c `onto` centre))
      step_ "Carry the first corner on, in front." (expectRefused (RefusalKind "FlapEndpointOrder") (Fold ValleyFold (Degrees 180) (hingeOf c1) FlapOfFirstArgument (Just (cornerOf SouthEast))))
    stoppedQuarter = stoppedQuarterWith (notModelled "fold in quarters")
    stoppedQuarterWith second = sequenceOf (header "A square folded into quarters" (sheetFile "examples/quarter-fold-steps.fold") (Just (at (3 / 4) (1 / 4)))) $ do
      _ <- step "half" "Fold the left half behind, onto the right." (fold behind (LineOnto (edge West) (edge East) Nothing))
      _ <- step "quarter" "Fold the top half down in front, onto the bottom." second
      pure ()

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
