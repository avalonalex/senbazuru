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
import Senbazuru.Fold.Load (LoadError (..))
import Senbazuru.Origami.Stacking (Budget (..), defaultBudget)
import Senbazuru.Sequence.Build
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Error (SequenceError (..), SheetProblem (..))
import Senbazuru.Sequence.Parse (parseSequence)
import Senbazuru.Sequence.RunPlan
import Senbazuru.Sequence.Syntax (Corner (..), Sequence, SourceFile (..), sourceFiles)
import Senbazuru.Sequence.Write (FileHeader (..), noFileHeader)
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

    -- PRD 04's A15: the output is chosen by -o's extension, in any case, and
    -- each flag that shapes another output is refused by name.
    describe "chooses the output by -o's extension" $ do
      it "writes the sequence file to standard output with no -o, and to a .fold" $ do
        planRun running `shouldBe` Right (PlanFold Nothing defaultBudget noFileHeader)
        planRun running {runOutput = Just "out.fold", runAuthor = Just "A. Folder", runDescription = Just "Two folds."}
          `shouldBe` Right (PlanFold (Just "out.fold") defaultBudget (FileHeader (Just "A. Folder") (Just "Two folds.")))

      it "writes one state as a model to a .glb, the complete paper alone with --all-layers" $ do
        planRun running {runOutput = Just "out.glb", runFrame = Just 2} `shouldBe` Right (PlanGlb "out.glb" defaultBudget (Just 2) GlbVisibleAndComplete)
        planRun running {runOutput = Just "out.glb", runAllLayers = True} `shouldBe` Right (PlanGlb "out.glb" defaultBudget Nothing GlbCompleteOnly)

      it "reads the extension in any case" $ do
        planRun running {runOutput = Just "OUT.FOLD"} `shouldBe` Right (PlanFold (Just "OUT.FOLD") defaultBudget noFileHeader)
        planRun running {runOutput = Just "Out.Glb"} `shouldBe` Right (PlanGlb "Out.Glb" defaultBudget Nothing GlbVisibleAndComplete)

      it "refuses an extension it does not write, and a page of steps until step notes exist" $ do
        planRun running {runOutput = Just "out.png"} `shouldBe` Left (UnknownOutput "out.png")
        planRun running {runOutput = Just "out"} `shouldBe` Left (UnknownOutput "out")
        planRun running {runOutput = Just "OUT.SVG"} `shouldBe` Left PageNotYet

      it "holds the --layer-budget given, whichever it writes" $ do
        planRun running {runLayerBudget = Just 7} `shouldBe` Right (PlanFold Nothing (Budget 7) noFileHeader)
        planRun running {runOutput = Just "out.glb", runLayerBudget = Just 7} `shouldBe` Right (PlanGlb "out.glb" (Budget 7) Nothing GlbVisibleAndComplete)

    describe "refuses a flag that shapes another output (A15)" $ do
      it "--frame and --all-layers, except with .glb" $ do
        planRun running {runFrame = Just 2} `shouldBe` Left (NotWithOutput "a sequence file" ["--frame"])
        planRun running {runOutput = Just "out.fold", runFrame = Just 2, runAllLayers = True} `shouldBe` Left (NotWithOutput "-o .fold" ["--frame", "--all-layers"])

      it "--author and --description, except with .fold" $
        planRun running {runOutput = Just "out.glb", runAuthor = Just "A.", runDescription = Just "D."} `shouldBe` Left (NotWithOutput "-o .glb" ["--author", "--description"])

      it "the page's flags, which no output takes until the page" $ do
        planRun running {runColumns = Just 3, runView = Just "iso"} `shouldBe` Left (NotWithOutput "a sequence file" ["--columns", "--view"])
        planRun running {runOutput = Just "out.glb", runWidth = Just 400, runHeight = Just 400} `shouldBe` Left (NotWithOutput "-o .glb" ["--width", "--height"])

  -- PRD 04's A16: --frame N is state N - 1, frame 0 being the key frame.
  describe "chooseState" $ do
    it "takes --frame N as state N - 1, and the last state with no --frame" $ do
      chooseState (Just 1) 3 `shouldBe` Right 0
      chooseState (Just 3) 3 `shouldBe` Right 2
      chooseState Nothing 3 `shouldBe` Right 2

    it "refuses frame 0, the key frame, and a frame past the last, naming the count" $ do
      chooseState (Just 0) 3 `shouldBe` Left (NoSuchFrame 0 3)
      chooseState (Just 4) 3 `shouldBe` Left (NoSuchFrame 4 3)

    -- No run writes no state, since state 0 is the sheet; but the rule
    -- should not lean on that and answer -1.
    it "refuses a run with no states rather than choose state -1" $
      chooseState Nothing 0 `shouldBe` Left NoStates

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

    -- The command line reads each file the source names and, for one that
    -- will not load, prints this: the line that named it, not just the path.
    it "points a sheet that will not load at the line that names it" $ do
      source <- blintzWith "examples/blintz-base.fold" "examples/no-such.fold"
      case parseSequence "blintz.foldseq" source of
        Left err -> expectationFailure (show err)
        Right sq -> case sourceFiles "blintz.foldseq" sq of
          [named] ->
            take 4 (refusalLines source (SheetRefused (sourceSpan named) (sourceWritten named) (SheetUnreadable (ReadFailed (sourceToOpen named) "does not exist"))))
              `shouldBe` [ "blintz.foldseq:3:1: sheet \"examples/no-such.fold\": cannot read examples/no-such.fold: does not exist",
                           "  |",
                           "3 | sheet \"examples/no-such.fold\"",
                           "  | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
                         ]
          other -> expectationFailure ("expected one file, got " <> show other)

    -- A built sequence has no place to point at, so the message stands alone.
    it "prints a refusal with no place as its message alone" $
      either (refusalLines "") (const []) (checkSequence builtTwice)
        `shouldBe` ["step 2 (c1): \"c1\" is already defined, and a name can be given only once"]

-- | Only @--check@ given.
checking :: RunOptions
checking = (noRunOptions "blintz.foldseq") {runCheck = True}

-- | Running the blintz, with no flag given; a test sets the flags it needs.
running :: RunOptions
running = noRunOptions "blintz.foldseq"

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
