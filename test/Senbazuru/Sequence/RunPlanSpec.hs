-- |
-- Tests for what @senbazuru run@ accepts and prints, which the command line
-- only calls.
--
-- __The flag rules__ are tested one flag at a time, by name: each flag that
-- @--check@ has nothing to do with is refused alone, and several together are
-- all named, in the order @run --help@ lists them. Without @--check@ the verb
-- refuses to pretend it can run a sequence.
--
-- __What it prints__ for a refusal is compared with goldens: a parse error and
-- a static refusal, each with its location, message and excerpt, exactly as a
-- person sees them after @senbazuru: @. The command line adds that prefix and
-- the exit code, and nothing else.
module Senbazuru.Sequence.RunPlanSpec (spec) where

import Data.Foldable (for_)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Senbazuru.Sequence.Build
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Parse (parseSequence)
import Senbazuru.Sequence.RunPlan
import Senbazuru.Sequence.Syntax (Corner (..), Sequence)
import Test.Golden (goldenText)
import Test.Hspec
import Test.SequenceExamples (blintz)

spec :: Spec
spec = do
  describe "planRun" $ do
    it "checks when asked to check and nothing else" $
      planRun checking `shouldBe` Right PlanCheck

    describe "refuses, with --check, a flag that shapes an output it does not write" $
      for_ eachFlag $ \(flag, given) ->
        it flag $ planRun (given checking) `shouldBe` Left (NotWithCheck [T.pack flag])

    it "names every such flag at once, in the order the help lists them" $
      planRun (foldr snd checking eachFlag) `shouldBe` Left (NotWithCheck (map (T.pack . fst) eachFlag))

    -- Running needs the runner; until there is one, run says so rather than
    -- doing something else in its name.
    it "refuses to run a sequence, with or without flags, until the runner exists" $ do
      planRun (noRunOptions "blintz.foldseq") `shouldBe` Left NoRunnerYet
      planRun ((noRunOptions "blintz.foldseq") {runOutput = Just "out.fold"}) `shouldBe` Left NoRunnerYet

  describe "checkSummary" $ do
    it "counts the blintz's steps and moves" $
      fmap (checkSummary "blintz.foldseq") (checkSequence blintz)
        `shouldBe` Right "blintz.foldseq: 5 steps, 5 moves, checked without geometry"

    it "says one step and one move without a plural" $
      fmap (checkSummary "one.foldseq") (parseSequence "one.foldseq" "foldseq 1\nsheet square\nstep { turn over left-right }\n" >>= checkSequence)
        `shouldBe` Right "one.foldseq: 1 step, 1 move, checked without geometry"

  describe "refusalLines" $ do
    it "shows a parse error with its place, its message and the line it is on" $ do
      source <- blintzWith "fold behind corner south-east" "fold behind corner bottom-right"
      goldenText "test/golden/run-refused-parse.txt" (T.unlines (refused source))

    it "shows a static refusal the same way" $ do
      source <- blintzWith "{ unfold c1 }" "{ unfold c9 }"
      goldenText "test/golden/run-refused-check.txt" (T.unlines (refused source))

    -- A FOLD file handed to run: the library's message says it looks like
    -- FOLD, and only this line, for the one verb, says which verbs read it.
    it "adds, for a FOLD file, the verbs that read one" $
      refused "{\"file_spec\": 1.1}\n"
        `shouldBe` [ "blintz.foldseq:1:1: this looks like a FOLD file, not a sequence source",
                     "  |",
                     "1 | {\"file_spec\": 1.1}",
                     "  | ^",
                     "render, info, check, export, crease and fold read FOLD files"
                   ]

    -- A built sequence has no place to point at, so the message stands alone.
    it "prints a refusal with no place as its message alone" $
      either (refusalLines "") (const []) (checkSequence builtTwice)
        `shouldBe` ["step 2 (c1): \"c1\" is already defined, and a name can be given only once"]

-- | Only @--check@ given.
checking :: RunOptions
checking = (noRunOptions "blintz.foldseq") {runCheck = True}

-- | Each flag, as the help names it, and a way to give it.
eachFlag :: [(String, RunOptions -> RunOptions)]
eachFlag =
  [ ("-o", \o -> o {runOutput = Just "out.fold"}),
    ("--report", \o -> o {runReport = True}),
    ("--layer-budget", \o -> o {runLayerBudget = Just 100}),
    ("--frame", \o -> o {runFrame = Just 1}),
    ("--all-layers", \o -> o {runAllLayers = True}),
    ("--columns", \o -> o {runColumns = Just 3}),
    ("--view", \o -> o {runView = Just "top"}),
    ("--width", \o -> o {runWidth = Just 400}),
    ("--height", \o -> o {runHeight = Just 400}),
    ("--author", \o -> o {runAuthor = Just "A. Folder"}),
    ("--description", \o -> o {runDescription = Just "A blintz"})
  ]

-- | The blintz at the repository root with one piece of text replaced.
blintzWith :: Text -> Text -> IO Text
blintzWith old new = T.replace old new <$> TIO.readFile "blintz.foldseq"

-- | The lines run prints for a source it refuses, read as blintz.foldseq.
refused :: Text -> [Text]
refused source = either (refusalLines source) (const ["accepted"]) (parseSequence "blintz.foldseq" source >>= checkSequence)

-- | A sequence built in Haskell that gives one name to two steps.
builtTwice :: Sequence
builtTwice = sequenceOf (header "T" sheetSquare Nothing) $ do
  _ <- step "c1" "Fold." (fold valley (cornerOf SouthEast `onto` centre))
  _ <- step "c1" "Fold again." (fold valley (cornerOf NorthEast `onto` centre))
  pure ()
