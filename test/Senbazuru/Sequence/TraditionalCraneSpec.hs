-- |
-- The whole traditional crane, as a fold sequence: parsed, checked, expanded
-- and printed, and never run.
--
-- @examples\/traditional-crane.foldseq@ writes the book's 28 steps from a
-- plain square. Most of them cannot run yet: the runner that folds some
-- layers arrives at milestone M4, the macro-moves at M5, and five of the
-- steps are moves the language has no word for. That is the point of the
-- test. It shows the language can /say/ a whole model before it can fold one,
-- so that each milestone after this one adds folding to a sequence already
-- written, instead of growing the language to reach it.
--
-- The assertions are the ones the design lays out for it
-- (@PRDs\/09-testing-and-acceptance.md@, section 5), and each says what
-- would turn it red. The table of what each step is written with is that
-- section's table, step by step.
--
-- None of this says the crane /folds/. The source's senses, seeds, @keeping@
-- pair, @model@ coordinates and the turns its repeats use are reasoned, not
-- run, and its header says so.
module Senbazuru.Sequence.TraditionalCraneSpec (spec) where

import Control.Monad (void)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Senbazuru.Sequence.Check (checkSequence, checkedSequence)
import Senbazuru.Sequence.Elaborate (elaborate, elaboratedMoves, elaboratedSteps)
import Senbazuru.Sequence.Error (SequenceError)
import Senbazuru.Sequence.Parse (parseSequence)
import Senbazuru.Sequence.Pretty (prettySequence)
import Senbazuru.Sequence.Syntax
import System.Directory (doesFileExist)
import Test.Hspec
import Test.SequenceHelpers (allMoves)

spec :: Spec
spec = describe "the traditional crane" $ do
  it "parses into the book's 28 steps" $ do
    crane <- readCrane
    fmap (length . seqSteps) crane `shouldBe` Right 28

  -- A diamond start written as `rotate 1/8 turn` would be a step of its own,
  -- since no move may stand outside a step, and make 29.
  it "is written, step by step, with the moves the design lays out for it" $ do
    crane <- readCrane
    fmap (zip [1 :: Int ..] . map (map constructorOf . stepMoves . locValue) . seqSteps) crane
      `shouldBe` Right writtenWith

  -- Red when checking needs examples/crane.fold. It cannot: 'checkSequence'
  -- takes a value and returns one, with no IO in its type.
  it "checks, loading no file, although it names one a run would need" $ do
    crane <- readCrane
    void (crane >>= checkSequence) `shouldBe` Right ()
    fmap (map sourceToOpen . sourceFiles cranePath) crane `shouldBe` Right ["examples/crane.fold"]
    doesFileExist "examples/crane.fold" `shouldReturn` True

  it "has exactly five moves the language cannot express, and one checkpoint" $ do
    crane <- readCrane
    fmap (\s -> (count isNotModelled s, count isCheckpoint s)) crane `shouldBe` Right (5, 1)

  it "prints as text that parses back to it" $ do
    crane <- readCrane
    fmap stripSpans (crane >>= parseSequence "reprinted" . prettySequence) `shouldBe` fmap stripSpans crane

  -- 35 moves as written; each of the six fold-and-unfolds is two core moves.
  it "expands into 41 core moves, a fold and unfold being two" $ do
    crane <- readCrane
    fmap (sum . map (length . elaboratedMoves) . elaboratedSteps . elaborate) (crane >>= checkSequence) `shouldBe` Right 41
    fmap (length . allMoves . checkedSequence) (crane >>= checkSequence) `shouldBe` Right 35

  it "gives every step a caption" $ do
    crane <- readCrane
    fmap (all (maybe False (not . T.null) . stepCaption . locValue) . seqSteps) crane `shouldBe` Right True

cranePath :: FilePath
cranePath = "examples/traditional-crane.foldseq"

readCrane :: IO (Either SequenceError Sequence)
readCrane = parseSequence cranePath <$> TIO.readFile cranePath

-- | Section 5's table of the design's testing plan, one row per step.
writtenWith :: [(Int, [String])]
writtenWith =
  zip
    [1 ..]
    [ ["FoldAndUnfold", "FoldAndUnfold"], -- 1, diagonals
      ["TurnOver"],
      ["FoldAndUnfold", "FoldAndUnfold"], -- 3, midlines
      ["Macro"], -- 4, collapse to a square base
      ["Fold", "Fold"], -- 5, edges to the centre line
      ["Fold"], -- 6, the top triangle down
      ["Unfold"], -- 7
      ["Macro"], -- 8, the front petal
      ["TurnOver"],
      ["FoldAndUnfold", "FoldAndUnfold"], -- 10
      ["Repeat"], -- 11, the back petal
      ["Fold", "Fold"], -- 12, narrowing, by model coordinates
      ["TurnOver"],
      ["Fold", "Fold"], -- 14, the same, since a repeat cannot carry a model line
      ["Fold"], -- 15, a page turned
      ["TurnOver"],
      ["Repeat"], -- 17
      ["Fold"], -- 18, a lower point up
      ["TurnOver"],
      ["Repeat"], -- 20
      ["Fold"], -- 21, a page turned again
      ["TurnOver"],
      ["Repeat"], -- 23
      ["NotModelled"], -- 24, a swivel fold
      ["NotModelled"], -- 25, another
      ["NotModelled"], -- 26, the head
      ["NotModelled"], -- 27, an inside reverse fold
      ["Checkpoint", "NotModelled"] -- 28, the finished crease pattern, then the wings
    ]

-- | A move's constructor, as its 'show' begins.
constructorOf :: Located Move -> String
constructorOf = takeWhile (/= ' ') . show . locValue

count :: (Move -> Bool) -> Sequence -> Int
count wanted = length . filter wanted . allMoves

isNotModelled :: Move -> Bool
isNotModelled = \case
  NotModelled _ -> True
  _ -> False

isCheckpoint :: Move -> Bool
isCheckpoint = \case
  Checkpoint _ _ -> True
  _ -> False
