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
-- == What @run@ writes
--
-- @run SOURCE --check@ reads a source, parses it and checks it, and prints
-- one line, folding no paper. Without @--check@ it runs the sequence and
-- writes what @-o@ names, by its extension: a sequence file, @.fold@, or to
-- standard output with no @-o@; or one state as a 3D model, @.glb@. A page of
-- steps, @.svg@, waits for the step notes it is drawn from (milestone M3), and
-- is refused by saying so. Each flag goes only with the output it shapes,
-- and is refused with any other, so that a flag never silently does nothing.
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
    GlbScenes (..),
    RunOptionError (..),
    planRun,
    chooseState,

    -- * What to print
    checkSummary,
    refusalLines,
  )
where

import Data.Char (toLower)
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Origami.Stacking (Budget (..), defaultBudget)
import Senbazuru.Sequence.Check (Checked, checkedSequence)
import Senbazuru.Sequence.Error (Hint (..), ParseProblem (..), SequenceError (..), excerpt, sourceLocation)
import Senbazuru.Sequence.Syntax (Located (..), Sequence (..), Step (..))
import Senbazuru.Sequence.Write (FileHeader (..))
import System.FilePath (takeExtension)

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

-- | What @run@ will do.
data Plan
  = -- | Parse and check the source, and print 'checkSummary'.
    PlanCheck
  | -- | Run the sequence and write its sequence file, to the path or to
    -- standard output, with the layer budget and what the file says about
    -- itself.
    PlanFold (Maybe FilePath) Budget FileHeader
  | -- | Run the sequence and write one state as a 3D model: the path, the
    -- layer budget, the @--frame@ given, if any, and which scenes.
    PlanGlb FilePath Budget (Maybe Int) GlbScenes
  deriving stock (Eq, Show)

-- | Which scenes a @.glb@ holds, as @export@ chooses them: the paper as seen
-- and the whole sheet, or, with @--all-layers@, the whole sheet alone. The
-- command line maps it to "Senbazuru.Render.Gltf"'s mode, which this module,
-- a level below rendering, cannot name.
data GlbScenes = GlbVisibleAndComplete | GlbCompleteOnly
  deriving stock (Eq, Show)

-- | Why @run@ will not do what its flags ask.
data RunOptionError
  = -- | Flags given with @--check@, which writes nothing for them to shape.
    -- Named as typed, in the order @run --help@ lists them.
    NotWithCheck [Text]
  | -- | An @-o@ whose extension names nothing @run@ writes: the path.
    UnknownOutput FilePath
  | -- | @-o@ a page of steps, which waits for step notes.
    PageNotYet
  | -- | Flags that shape another output than the one @-o@ names: the
    -- output, then the flags, in the order @run --help@ lists them.
    NotWithOutput Text [Text]
  | -- | A @--frame@ the file has no state for: the number given, and how
    -- many states there are.
    NoSuchFrame Int Int
  deriving stock (Eq, Show)

instance Explain RunOptionError where
  explain = \case
    NotWithCheck flags ->
      "--check writes nothing, so it takes no " <> T.intercalate ", " flags
    UnknownOutput path ->
      "-o " <> T.pack path <> ": run writes .fold, a sequence file, or .glb, one state as a model"
    PageNotYet ->
      "-o .svg, a page of steps, cannot be written by run yet; write .fold and draw it with render --steps"
    NotWithOutput output flags ->
      output <> " takes no " <> T.intercalate ", " flags
    NoSuchFrame n count ->
      "--frame " <> tshow n <> ": the file has " <> tshow count <> " states, frames 1 to " <> tshow count <> " (frame 0 is the key frame, which holds none)"

-- | Decide what to do before any file is opened, so that a refused flag costs
-- nothing and is refused whatever the source holds.
--
-- The output is chosen by @-o@'s extension, compared in lower case so that
-- @OUT.FOLD@ is a FOLD file too. Then each flag that shapes some other
-- output is refused by name: @--frame@ and @--all-layers@ go only with
-- @.glb@, @--author@ and @--description@ only with @.fold@, and the page's
-- flags only with the page, which no output takes yet.
planRun :: RunOptions -> Either RunOptionError Plan
planRun options
  | runCheck options = case flagsGiven allFlags of
      [] -> Right PlanCheck
      flags -> Left (NotWithCheck flags)
  | otherwise = case map toLower . takeExtension <$> runOutput options of
      Nothing -> fold Nothing
      Just ".fold" -> fold (runOutput options)
      Just ".glb" -> case flagsGiven (pageFlags ++ foldFlags) of
        [] -> Right (PlanGlb (fromMaybe "" (runOutput options)) budget (runFrame options) (if runAllLayers options then GlbCompleteOnly else GlbVisibleAndComplete))
        flags -> Left (NotWithOutput "-o .glb" flags)
      Just ".svg" -> Left PageNotYet
      Just _ -> Left (UnknownOutput (fromMaybe "" (runOutput options)))
  where
    budget = maybe defaultBudget Budget (runLayerBudget options)
    fold output = case flagsGiven (glbFlags ++ pageFlags) of
      [] -> Right (PlanFold output budget (FileHeader (runAuthor options) (runDescription options)))
      flags -> Left (NotWithOutput (maybe "a sequence file" (const "-o .fold") output) flags)
    -- Every flag, in the order @run --help@ lists them, with whether it was
    -- given.
    allFlags =
      [ (isJust (runOutput options), "-o"),
        (runReport options, "--report"),
        (isJust (runLayerBudget options), "--layer-budget")
      ]
        ++ glbFlags
        ++ pageFlags
        ++ foldFlags
    glbFlags = [(isJust (runFrame options), "--frame"), (runAllLayers options, "--all-layers")]
    pageFlags =
      [ (isJust (runColumns options), "--columns"),
        (isJust (runView options), "--view"),
        (isJust (runWidth options), "--width"),
        (isJust (runHeight options), "--height")
      ]
    foldFlags = [(isJust (runAuthor options), "--author"), (isJust (runDescription options), "--description")]
    flagsGiven flags = [flag | (True, flag) <- flags]

-- | Which state @--frame N@ names in a file of this many states: state N − 1,
-- because every verb counts the key frame as frame 0 and a sequence file's
-- key frame holds no state. With no @--frame@, the last state, the model the
-- sequence ends at. Frame 0 and frames past the last are refused, naming the
-- count.
chooseState :: Maybe Int -> Int -> Either RunOptionError Int
chooseState frame count = case frame of
  Nothing -> Right (count - 1)
  Just n
    | n >= 1 && n <= count -> Right (n - 1)
    | otherwise -> Left (NoSuchFrame n count)

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
