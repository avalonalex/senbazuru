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
-- (@PRDs\/09-testing-and-acceptance.md@, section 5), and the comment on each
-- says what would turn it red. Where that section's table spells a step out,
-- the step is compared with it exactly.
--
-- None of this says the crane /folds/. The source's senses, seeds, @keeping@
-- pair, @model@ coordinates and the turns its repeats use are reasoned, not
-- run, and its header says so. Where a test below pins one of them, it pins
-- what the source says, for the milestone that runs it to change both.
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
spec = beforeAll readCrane . describe "the traditional crane" $ do
  -- Red when a keyword the file uses leaves the grammar, or when a step is
  -- added: a diamond start written as `rotate 1/8 turn` would be a step of its
  -- own, since no move may stand outside a step, and make 29.
  it "parses into the book's 28 steps" $ \crane ->
    fmap (length . seqSteps) crane `shouldBe` Right 28

  -- Red when any step's moves change kind.
  it "writes each step with the kinds of move the design lays out for it" $ \crane ->
    fmap (map (fmap (map constructorOf)) . numbered) crane `shouldBe` Right writtenWith

  -- Red when a step the table spells out is written otherwise: the other
  -- macro-move at step 4 or 8, a repeat without its half turn, a different
  -- word for a move the language cannot make, another checkpoint.
  it "writes the steps the design spells out exactly as it spells them" $ \crane ->
    fmap (filter ((`elem` map fst spelledOut) . fst) . numbered) crane `shouldBe` Right spelledOut

  -- Red when a kite fold, a page turned or a point lifted stops choosing the
  -- top flap, or a narrowing fold stops being placed by model coordinates.
  it "folds only the top flap where the design says, and narrows by model coordinates" $ \crane ->
    fmap (\s -> (layersIn [5, 10, 15, 18, 21] s, map isModelFold (movesOf [12, 14] s))) crane
      `shouldBe` Right (replicate 7 TopFlap, replicate 4 True)

  -- Red when checking needs examples/crane.fold. It cannot: 'checkSequence'
  -- takes a value and returns one, with no IO in its type. Also red if the
  -- checkpoint's path stops meaning that file, which a run will open.
  it "checks, loading no file, although it names one a run would need" $ \crane -> do
    void (crane >>= checkSequence) `shouldBe` Right ()
    fmap (map sourceToOpen . sourceFiles cranePath) crane `shouldBe` Right ["examples/crane.fold"]
    doesFileExist "examples/crane.fold" `shouldReturn` True

  -- Red when either constructor leaves the parser, or a `not modelled` text is
  -- read as a caption.
  it "has exactly five moves the language cannot express, and one checkpoint" $ \crane ->
    fmap (\s -> (count isNotModelled s, count isCheckpoint s)) crane `shouldBe` Right (5, 1)

  -- Red when the printer drops or misspells anything the crane uses, a
  -- checkpoint's block among them.
  it "prints as text that parses back to it" $ \crane ->
    fmap stripSpans (crane >>= parseSequence "reprinted" . prettySequence) `shouldBe` fmap stripSpans crane

  -- 35 moves as written, and one core move each: the six pre-creases are
  -- one move each too (owner decision 14). Red when elaboration drops a move
  -- or splits one.
  it "expands into 35 core moves, one per move written" $ \crane -> do
    fmap (sum . map (length . elaboratedMoves) . elaboratedSteps . elaborate) (crane >>= checkSequence) `shouldBe` Right 35
    fmap (length . allMoves . checkedSequence) (crane >>= checkSequence) `shouldBe` Right 35

  -- A page draws each step with its caption. Red when a step loses one.
  it "gives every step a caption" $ \crane ->
    fmap (all (maybe False (not . T.null) . stepCaption . locValue) . seqSteps) crane `shouldBe` Right True

cranePath :: FilePath
cranePath = "examples/traditional-crane.foldseq"

readCrane :: IO (Either SequenceError Sequence)
readCrane = parseSequence cranePath <$> TIO.readFile cranePath

-- | Each step's moves, numbered from 1.
numbered :: Sequence -> [(Int, [Move])]
numbered s = zip [1 ..] [map locValue (stepMoves (locValue step)) | step <- seqSteps s]

movesOf :: [Int] -> Sequence -> [Move]
movesOf steps s = concat [moves | (n, moves) <- numbered s, n `elem` steps]

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

-- | The steps section 5's table spells out word for word, as the source
-- writes them. The `keeping` pair at step 4 and the half turns are the
-- source's reasoned choices, not the table's.
spelledOut :: [(Int, [Move])]
spelledOut =
  [ (2, [TurnOver LeftRight]),
    (4, [Macro (Collapse Centre (Just (CornerOf SouthEast, CornerOf NorthWest)) 180) []]),
    (7, [Unfold ["kite", "lid"]]),
    (8, [Macro (Petal TopFlapTip 180) []]),
    (9, [TurnOver LeftRight]),
    (11, [Repeat "front-petal" Nothing halfTurn]),
    (13, [TurnOver LeftRight]),
    (16, [TurnOver LeftRight]),
    (17, [Repeat "page-turn" Nothing halfTurn]),
    (19, [TurnOver LeftRight]),
    (20, [Repeat "leg-up" Nothing halfTurn]),
    (22, [TurnOver LeftRight]),
    (23, [Repeat "second-page-turn" Nothing halfTurn]),
    (24, [NotModelled "swivel fold"]),
    (25, [NotModelled "swivel fold"]),
    (26, [NotModelled "fold the head"]),
    (27, [NotModelled "inside reverse fold"]),
    (28, [Checkpoint "crane.fold" StackingFirst, NotModelled "open the wings and shape the body"])
  ]
  where
    halfTurn = Just (TurnedQuarters 2 Centre)

-- | The layers each fold of these steps chooses.
layersIn :: [Int] -> Sequence -> [Layers]
layersIn steps s = concatMap layersOf (movesOf steps s)
  where
    layersOf = \case
      Fold _ _ _ layers _ -> [layers]
      FoldAndUnfold _ _ layers _ -> [layers]
      _ -> []

isModelFold :: Move -> Bool
isModelFold = \case
  Fold _ _ (ModelSegment _ _) _ _ -> True
  _ -> False

-- | A move's constructor, as its 'show' begins.
constructorOf :: Move -> String
constructorOf = takeWhile (/= ' ') . show

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
