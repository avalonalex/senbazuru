-- |
-- Module      : Senbazuru.Sequence.RunPlan
-- Description : What the run verb accepts, and the lines it prints, as pure functions.
--
-- The command line is not tested: it parses flags, calls the library and
-- prints. So everything about @senbazuru run@ worth testing lives here
-- instead, as functions of plain values: which combinations of flags it
-- accepts ('planRun'), the one line it prints for a checked source
-- ('checkSummary'), the lines it prints for a refused one ('refusalLines'),
-- and the warning a page seen from behind gets ('oppositeSideWarning'). The
-- command line only calls them.
--
-- == What @run@ writes
--
-- @run SOURCE --check@ reads a source, parses it and checks it, and prints
-- one line, folding no paper. Without @--check@ it runs the sequence and
-- writes what @-o@ names, by its extension: a sequence file, @.fold@, or to
-- standard output with no @-o@; a page of steps, @.svg@; or one state as a
-- 3D model, @.glb@. Each flag goes only with the output it shapes, and is
-- refused with any other, so that a flag never silently does nothing.
--
-- == Why the page's flags reach the plan unfilled
--
-- 'PageFlags' holds each page flag as given, a 'Maybe', and the command line
-- fills in the defaults. They are "Senbazuru.Render.Svg"'s @defaultPage@ and
-- "Senbazuru.Diagram.Layout"'s @defaultGrid@, which this module, a level
-- below rendering, may not import (PRDs\/decisions.md, §2 row 6), and from
-- which @render@ reads its own. Filling them here would mean writing 400 and 3
-- a second time, where nothing would notice the two copies drift. For the
-- same reason the plan holds @--view@'s name and not a view, which the
-- command line looks up, or leaves to "Senbazuru.Render.Camera"'s
-- @defaultView@ when none is given.
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
    PageFlags (..),
    GlbScenes (..),
    RunOptionError (..),
    planRun,
    chooseState,

    -- * What to print
    checkSummary,
    refusalLines,
    oppositeSideWarning,
  )
where

import Data.Char (toLower)
import Data.Maybe (isJust)
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
  | -- | Run the sequence and write its page of steps: the path, the layer
    -- budget, and the page's flags as given.
    PlanSvg FilePath Budget PageFlags
  | -- | Run the sequence and write one state as a 3D model: the path, the
    -- layer budget, the @--frame@ given, if any, and which scenes.
    PlanGlb FilePath Budget (Maybe Int) GlbScenes
  deriving stock (Eq, Show)

-- | The page's flags, each as given, for the command line to fill in from the
-- page's own defaults (see the module header). Not named @pageWidth@ and
-- @pageHeight@, which are the page's own fields.
data PageFlags = PageFlags
  { -- | @--columns@: figures across the page.
    flagColumns :: Maybe Int,
    -- | @--view@, by name: where to look from.
    flagViewName :: Maybe Text,
    -- | @--width@, in page units.
    flagWidth :: Maybe Double,
    -- | @--height@, in page units.
    flagHeight :: Maybe Double
  }
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
  | -- | Flags that shape another output than the one @-o@ names: the
    -- output, then the flags, in the order @run --help@ lists them.
    NotWithOutput Text [Text]
  | -- | A @--frame@ the file has no state for: the number given, and how
    -- many states there are.
    NoSuchFrame Int Int
  | -- | A run that wrote no state, so has none to export. No run does that
    -- today, since state 0 is the sheet; this is here so that the rule
    -- choosing the last state never has to answer -1.
    NoStates
  deriving stock (Eq, Show)

instance Explain RunOptionError where
  explain = \case
    NotWithCheck flags ->
      "--check writes nothing, so it takes no " <> T.intercalate ", " flags
    UnknownOutput path ->
      "-o " <> T.pack path <> ": run writes .fold, a sequence file, .svg, a page of steps, or .glb, one state as a model"
    NotWithOutput output flags ->
      output <> " takes no " <> T.intercalate ", " flags
    NoSuchFrame n count ->
      "--frame " <> tshow n <> ": the file has " <> tshow count <> " states, frames 1 to " <> tshow count <> " (frame 0 is the key frame, which holds none)"
    NoStates -> "the run wrote no states, so there is none to export"

-- | Decide what to do before any file is opened, so that a refused flag costs
-- nothing and is refused whatever the source holds.
--
-- The output is chosen by @-o@'s extension, compared in lower case so that
-- @OUT.FOLD@ is a FOLD file too. Then each flag that shapes some other
-- output is refused by name: @--frame@ and @--all-layers@ go only with
-- @.glb@, @--author@ and @--description@ only with @.fold@, and the page's
-- flags only with @.svg@.
planRun :: RunOptions -> Either RunOptionError Plan
planRun options
  | runCheck options = case flagsGiven allFlags of
      [] -> Right PlanCheck
      flags -> Left (NotWithCheck flags)
  | otherwise = case runOutput options of
      Nothing -> fold Nothing
      Just path -> case map toLower (takeExtension path) of
        ".fold" -> fold (Just path)
        ".glb" -> case flagsGiven (pageFlags ++ foldFlags) of
          [] -> Right (PlanGlb path budget (runFrame options) (if runAllLayers options then GlbCompleteOnly else GlbVisibleAndComplete))
          flags -> Left (NotWithOutput "-o .glb" flags)
        ".svg" -> case flagsGiven (glbFlags ++ foldFlags) of
          [] -> Right (PlanSvg path budget page)
          flags -> Left (NotWithOutput "-o .svg" flags)
        _ -> Left (UnknownOutput path)
  where
    budget = maybe defaultBudget Budget (runLayerBudget options)
    page = PageFlags (runColumns options) (runView options) (runWidth options) (runHeight options)
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
  Nothing
    | count >= 1 -> Right (count - 1)
    | otherwise -> Left NoStates
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

-- | The line @run -o x.svg@ prints, once, when its page shows the paper from
-- the side opposite the reader's side, without the @senbazuru: @ the command
-- line puts before it. Given the @--view@ named, if any.
--
-- A warning and not a refusal: a page drawn from below is a picture someone
-- may want, and it draws the states the run wrote, as every view does. What
-- the reader is told is that it is not the side the instructions face, since
-- a valley fold seen from there is a mountain fold. Which side a page shows is
-- "Senbazuru.Render.Steps"' @pageSide@, which this module cannot import, so
-- the command line asks it and calls this.
oppositeSideWarning :: Maybe Text -> Text
oppositeSideWarning view =
  "warning: "
    <> maybe "the page" ("--view " <>) view
    <> " shows the paper from the side opposite the reader's side, as if the model had been turned over"
