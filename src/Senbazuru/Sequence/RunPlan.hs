-- |
-- Module      : Senbazuru.Sequence.RunPlan
-- Description : What the run verb accepts, and the lines it prints, as pure functions.
--
-- The command line is not tested: it parses flags, calls the library and
-- prints. So everything about @senbazuru run@ worth testing lives here
-- instead, as functions of plain values: which combinations of flags it
-- accepts ('planRun'), the one line it prints for a checked source
-- ('checkSummary'), and the lines it prints for a refused one
-- ('refusalLines'). The command line only calls them.
--
-- == Only @--check@ runs yet
--
-- @run SOURCE --check@ reads a source, parses it and checks it, and prints
-- one line. It opens no sheet and folds no paper, which is milestone M1: the
-- language without geometry. Running the sequence, with @-o@ for a FOLD file,
-- a page of steps or a 3D model, needs the runner, and 'planRun' refuses it
-- by saying so rather than pretending. The flags that running will take are
-- parsed already, so that @--check@ can refuse each one by name: none of them
-- has anything to do when nothing is written.
--
-- == Why these messages may name flags
--
-- The library's other messages name no command and no flag, because they are
-- also read in GHCi and by the material study, where a flag is no help. This
-- module exists for the one verb, and its options are flags, so its refusals
-- say which.
module Senbazuru.Sequence.RunPlan
  ( -- * The options, as given
    RunOptions (..),
    noRunOptions,

    -- * What to do
    Plan (..),
    RunOptionError (..),
    planRun,

    -- * What to print
    checkSummary,
    refusalLines,
  )
where

import Data.Maybe (catMaybes, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Sequence.Check (Checked, checkedSequence)
import Senbazuru.Sequence.Error (Hint (..), ParseProblem (..), SequenceError (..), excerpt, sourceLocation)
import Senbazuru.Sequence.Syntax (Located (..), Sequence (..), Step (..))

-- | Every flag of @run@, as given. Each is a 'Maybe' or a 'Bool', so that a
-- flag typed with its default value can be told from one not typed at all:
-- @--check@ refuses @--columns 3@ although 3 is the default.
data RunOptions = RunOptions
  { runSource :: FilePath,
    runCheck :: Bool,
    runOutput :: Maybe FilePath,
    runReport :: Bool,
    runLayerBudget :: Maybe Int,
    runFrame :: Maybe Int,
    runAllLayers :: Bool,
    runColumns :: Maybe Int,
    runView :: Maybe Text,
    runWidth :: Maybe Double,
    runHeight :: Maybe Double,
    runAuthor :: Maybe Text,
    runDescription :: Maybe Text
  }
  deriving stock (Eq, Show)

-- | The source alone, with no flag given; a test sets the flags it needs by
-- record update.
noRunOptions :: FilePath -> RunOptions
noRunOptions source =
  RunOptions
    { runSource = source,
      runCheck = False,
      runOutput = Nothing,
      runReport = False,
      runLayerBudget = Nothing,
      runFrame = Nothing,
      runAllLayers = False,
      runColumns = Nothing,
      runView = Nothing,
      runWidth = Nothing,
      runHeight = Nothing,
      runAuthor = Nothing,
      runDescription = Nothing
    }

-- | What @run@ will do. One plan so far; writing a FOLD file, a page and a
-- 3D model join it with the runner.
data Plan
  = -- | Parse and check the source, and print 'checkSummary'.
    PlanCheck
  deriving stock (Eq, Show)

-- | Why @run@ will not do what its flags ask.
data RunOptionError
  = -- | Flags given with @--check@, which writes nothing for them to shape.
    -- Named as typed, in the order @run --help@ lists them.
    NotWithCheck [Text]
  | -- | Running a sequence, which needs the runner, not yet built.
    NoRunnerYet
  deriving stock (Eq, Show)

instance Explain RunOptionError where
  explain = \case
    NotWithCheck flags ->
      "--check writes nothing, so it takes no " <> T.intercalate ", " flags
    NoRunnerYet ->
      "running a sequence needs the runner, which is not built yet; --check parses and checks one"

-- | Decide what to do before any file is opened, so that a refused flag costs
-- nothing and is refused whatever the source holds.
planRun :: RunOptions -> Either RunOptionError Plan
planRun options
  | runCheck options = case flagsGiven of
      [] -> Right PlanCheck
      flags -> Left (NotWithCheck flags)
  | otherwise = Left NoRunnerYet
  where
    flagsGiven =
      catMaybes
        [ given (isJust (runOutput options)) "-o",
          given (runReport options) "--report",
          given (isJust (runLayerBudget options)) "--layer-budget",
          given (isJust (runFrame options)) "--frame",
          given (runAllLayers options) "--all-layers",
          given (isJust (runColumns options)) "--columns",
          given (isJust (runView options)) "--view",
          given (isJust (runWidth options)) "--width",
          given (isJust (runHeight options)) "--height",
          given (isJust (runAuthor options)) "--author",
          given (isJust (runDescription options)) "--description"
        ]
    given present flag = if present then Just flag else Nothing

-- | The line @run --check@ prints for a source that checks:
-- @blintz.foldseq: 5 steps, 5 moves, checked without geometry@.
--
-- The path is as the command line gave it. Moves are counted as written in
-- the steps, so a @together@ block is one, as it is one move to the reader.
checkSummary :: FilePath -> Checked -> Text
checkSummary path checked =
  T.pack path <> ": " <> counted stepCount "step" <> ", " <> counted moveCount "move" <> ", checked without geometry"
  where
    steps = seqSteps (checkedSequence checked)
    stepCount = length steps
    moveCount = sum [length (stepMoves step) | Located _ step <- steps]
    counted n word = tshow n <> " " <> word <> (if n == 1 then "" else "s")

-- | The lines @run@ prints for a refused source, given its text, without the
-- @senbazuru: @ the command line puts before the first.
--
-- The first line is the message, after @path:line:col: @ where there is a
-- place to point at. The rest are the excerpt with its caret. The message
-- itself never names the path, so no line names it twice.
--
-- A source that begins with @{@ is a FOLD file handed to the wrong verb. The
-- message says it looks like FOLD, and only here, where a verb is no leak,
-- does a line say which verbs read one. They are @app/@'s verbs, listed by
-- hand: the tests cannot see that module, and its command parser points back
-- here.
refusalLines :: Text -> SequenceError -> [Text]
refusalLines source err =
  (maybe "" (<> ": ") (sourceLocation err) <> explain err)
    : maybe [] T.lines (excerpt source err)
      <> [ "render, info, check, export, crease and fold read FOLD files"
           | ParseFailed problem <- [err],
             problemHint problem == Just LooksLikeFold
         ]
