-- |
-- Module      : Senbazuru.Cli
-- Description : Command-line interface for senbazuru.
--
-- Lives in the executable rather than the library on purpose: the library
-- should stay usable from GHCi and from other programs without dragging in an
-- argument parser. The rule of thumb is that this module contains no logic
-- worth testing — it parses flags, calls into the library, and prints.
module Senbazuru.Cli
  ( runCli,
    Command (..),
    RenderOptions (..),
    CheckOptions (..),
    commandParser,
  )
where

import Control.Monad (unless, when)
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Version (makeVersion, showVersion)
import Numeric (showFFloat)
import Options.Applicative
import Senbazuru.Diagram (Colour (..), Diagram)
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid)
import Senbazuru.Diagram.Style (Theme (..), defaultTheme)
import Senbazuru.Fold.Load (loadFoldFile, renderLoadError)
import Senbazuru.Fold.Query (FoldError, FrameKind (..), frameKind, frameVertices, renderFoldError)
import Senbazuru.Fold.Types
  ( Assignment,
    FoldFile (..),
    Frame (..),
    allFrames,
    assignmentCode,
  )
import Senbazuru.Origami.FlatFold
  ( Report,
    Tolerance (..),
    checkFrame,
    defaultTolerance,
    renderCheckError,
    renderReport,
    reportViolations,
  )
import Senbazuru.Origami.Folding (FoldingError (..), foldFrame, renderFoldingError)
import Senbazuru.Origami.Stacking
  ( Budget (..),
    Choice (..),
    Stackings (..),
    componentCount,
    defaultBudget,
    renderStackingError,
    solveStackingAs,
    stackingSpace,
    stateCount,
  )
import Senbazuru.Origami.Step (Motion, motionsBetween)
import Senbazuru.Render.Camera (Basis, View (..), namedView, viewNames)
import Senbazuru.Render.CreasePattern (basisFor, creasePatternAuto, withArrows)
import Senbazuru.Render.Steps (StepError (..), stepPage)
import Senbazuru.Render.Svg (Page (..), defaultPage, renderSvg)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

-- | What the user asked for.
data Command
  = Render RenderOptions
  | Info InfoOptions
  | Check CheckOptions
  deriving stock (Eq, Show)

-- | Options for the @info@ subcommand.
data InfoOptions = InfoOptions
  { ioInput :: FilePath,
    -- | Summarise the layers of each frame /folded/, as @render --fold@ draws
    -- it, rather than of the frame as the file stores it.
    ioFold :: Bool,
    ioBudget :: Budget
  }
  deriving stock (Eq, Show)

-- | Options for the @check@ subcommand.
data CheckOptions = CheckOptions
  { coInput :: FilePath,
    coFrame :: Int,
    -- | Kawasaki's alternating sum counts as zero within this many degrees.
    -- Degrees rather than radians because that is the unit the rest of the
    -- origami world states angles in, and the unit the message prints.
    coTolerance :: Double
  }
  deriving stock (Eq, Show)

-- | Options for the @render@ subcommand.
data RenderOptions = RenderOptions
  { roInput :: FilePath,
    -- | 'Nothing' writes to stdout, so the tool composes in a pipeline.
    roOutput :: Maybe FilePath,
    -- | 'Nothing' means frame 0. Kept optional so that asking for a frame and
    -- asking for every frame can be told apart.
    roFrame :: Maybe Int,
    roWidth :: Double,
    roHeight :: Double,
    roMargin :: Double,
    roTransparent :: Bool,
    roHideFlat :: Bool,
    roNoFill :: Bool,
    -- | Fold the crease pattern before drawing it, instead of drawing the
    -- pattern itself.
    roFold :: Bool,
    -- | Draw the fold this step performs, worked out from the next frame.
    roArrows :: Bool,
    -- | Lay every frame out as a numbered grid instead of drawing one.
    roSteps :: Bool,
    roColumns :: Int,
    -- | Where to look from and which way up. The basis is resolved during
    -- argument parsing, so an unknown view name never reaches this record.
    roView :: View,
    -- | Which layer order to draw, one index per component that has a choice.
    -- Empty means the first of each, which is what every version so far drew.
    roStacking :: [Int],
    roBudget :: Budget,
    -- | Page units between one layer of a folded model and the next. Zero, the
    -- default, draws them where the paper is.
    roOffset :: Double
  }
  deriving stock (Eq, Show)

runCli :: IO ()
runCli = execParser opts >>= run
  where
    opts =
      info
        (commandParser <**> helper <**> versionOption)
        ( fullDesc
            <> progDesc "Render FOLD origami files to SVG diagrams"
            <> header "senbazuru - origami diagrams from FOLD files"
        )
    versionOption =
      infoOption
        ("senbazuru " <> showVersion version)
        (long "version" <> help "Show version and exit")
    -- Hard-coded rather than pulled from the Cabal-generated Paths_senbazuru,
    -- which would stop this module loading under a bare ghci.
    version = makeVersion [0, 1, 0, 0]

commandParser :: Parser Command
commandParser =
  hsubparser
    ( command
        "render"
        (info (Render <$> renderOptions) (progDesc "Render a frame to SVG"))
        <> command
          "info"
          (info (Info <$> infoOptions) (progDesc "Summarise a FOLD file"))
        <> command
          "check"
          ( info
              (Check <$> checkOptions)
              ( progDesc
                  "Check every interior vertex against Maekawa's and Kawasaki's theorems"
              )
          )
    )

checkOptions :: Parser CheckOptions
checkOptions =
  CheckOptions
    <$> inputArg
    <*> option
      auto
      ( long "frame"
          <> metavar "N"
          <> value 0
          <> showDefault
          <> help "Which frame to check (0 is the key frame)"
      )
    <*> option
      -- Rejected during parsing rather than checked later: a negative tolerance
      -- makes `abs sum > tolerance` true for every vertex, so the tool would
      -- confidently report that an alternating sum of 0.0000 degrees is not 0.
      (nonNegative =<< auto)
      ( long "tolerance"
          <> metavar "DEG"
          <> value (degreesOf defaultTolerance)
          -- Spelled out rather than shown, because the default is a round
          -- number of radians and Haskell's Show would print its value in
          -- degrees as 5.729577951308233e-4.
          <> showDefaultWith (\d -> showFFloat (Just 6) d "")
          <> help
            ( "How far Kawasaki's alternating sum may sit from zero and still"
                <> " pass. Raise it for files whose coordinates are heavily rounded"
            )
      )
  where
    degreesOf t = toleranceRadians t * 180 / pi

    nonNegative :: Double -> ReadM Double
    nonNegative d
      | d >= 0 && not (isNaN d) && not (isInfinite d) = pure d
      | otherwise = readerError "tolerance must be a non-negative number of degrees"

infoOptions :: Parser InfoOptions
infoOptions =
  InfoOptions
    <$> inputArg
    <*> switch
      ( long "fold"
          <> help
            ( "Report the layers of each frame folded along its own angles, as"
                <> " render --fold draws it. A crease pattern has no layers"
                <> " until it is folded, so this is the only way to see what"
                <> " --stacking can choose between"
            )
      )
    <*> budgetOption

-- | How hard the layer solver may look before giving up, in guesses.
--
-- Offered on both verbs that run the solver, because a model it gives up on is
-- one @info@ has to explain and @render@ has to refuse, and a reader who raises
-- it for one wants it raised for the other.
budgetOption :: Parser Budget
budgetOption =
  Budget
    <$> option
      -- Through Integer for the reason --stacking is: `auto` at type Int wraps
      -- rather than refusing, so a budget too large to be one silently became a
      -- small one.
      (positive =<< auto)
      ( long "layer-budget"
          <> metavar "N"
          <> value (budgetGuesses defaultBudget)
          <> showDefault
          <> help
            ( "How many guesses the layer solver may make in one part of a model"
                <> " before giving up. Raise it for a model it cannot settle"
            )
      )
  where
    positive :: Integer -> ReadM Int
    positive n
      | n > 0 && n <= toInteger (maxBound :: Int) = pure (fromInteger n)
      | otherwise = readerError "the layer budget must be a positive number of guesses"

-- | Degrees in, radians out.
--
-- Every angle this module reads is in degrees, because that is the unit the
-- origami world states angles in and the unit the help text prints; everything
-- inside the library is in radians. One conversion rather than one per flag.
toRadians :: Double -> Double
toRadians d = d * pi / 180

-- | Refuse an angle that is not a number.
--
-- `read` for a Double happily returns NaN, Infinity, and 1e400 — and every one
-- of those propagates through the arithmetic until it reaches 'formatNumber',
-- which prints it as 0. A file drawn with one is not wrong-looking, it is
-- blank, which is the worst way for a flag to fail.
finite :: Double -> ReadM Double
finite d
  | isNaN d || isInfinite d = readerError "the rotation must be a number of degrees"
  | otherwise = pure d

-- | A column count below one describes no page, and quietly rounding it up to
-- one would answer a question nobody asked.
atLeastOne :: Int -> ReadM Int
atLeastOne n
  | n >= 1 = pure n
  | otherwise = readerError "columns must be at least 1"

inputArg :: Parser FilePath
inputArg = argument str (metavar "FILE.fold" <> help "Input FOLD file")

renderOptions :: Parser RenderOptions
renderOptions =
  RenderOptions
    <$> inputArg
    <*> optional
      ( strOption
          ( long "output"
              <> short 'o'
              <> metavar "FILE.svg"
              <> help "Output file (default: stdout)"
          )
      )
    <*> optional
      ( option
          auto
          ( long "frame"
              <> metavar "N"
              <> help "Which frame to render (default: 0, the key frame)"
          )
      )
    <*> option
      auto
      (long "width" <> metavar "PT" <> value 400 <> showDefault <> help "Page width")
    <*> option
      auto
      (long "height" <> metavar "PT" <> value 400 <> showDefault <> help "Page height")
    <*> option
      auto
      (long "margin" <> metavar "PT" <> value 16 <> showDefault <> help "Page margin")
    <*> switch
      (long "transparent" <> help "Omit the white background rectangle")
    <*> switch
      (long "hide-flat" <> help "Do not draw flat (F) or unassigned (U) creases")
    <*> switch
      ( long "no-fill"
          <> help
            ( "Draw every crease and fill nothing: a wireframe. Also the way to"
                <> " render a file whose layers cannot be stacked, since nothing"
                <> " then needs to know which is on top"
            )
      )
    <*> switch
      ( long "fold"
          <> help
            ( "Fold the crease pattern along its fold angles and draw the result"
                <> " instead of the pattern"
            )
      )
    <*> switch
      ( long "arrows"
          <> help
            ( "Draw the fold that takes this frame to the next one, as a book"
                <> " does: the arrow goes on the picture of the paper before the"
                <> " fold. The last frame has no next one, and so no arrows"
            )
      )
    <*> switch
      ( long "steps"
          <> help
            ( "Lay every frame of the file out as one numbered page of figures,"
                <> " all at the same scale, instead of drawing a single frame"
            )
      )
    <*> option
      -- Rejected during parsing, as --tolerance is: a column count below one
      -- describes no page, and quietly rounding it up to one would answer a
      -- question nobody asked.
      (atLeastOne =<< auto)
      ( long "columns"
          <> metavar "N"
          <> value 3
          <> showDefault
          <> help "Figures across the page, with --steps"
      )
    <*> ( View
            <$> optional
              ( option
                  -- Resolved during parsing, so a bad name is rejected with
                  -- optparse's own usage text before any file is opened, and
                  -- roView carries a Basis rather than an unvalidated string.
                  (maybeReader (namedView . T.pack))
                  ( long "view"
                      <> metavar "NAME"
                      <> help
                        ( "Viewing angle: "
                            <> T.unpack (T.intercalate ", " viewNames)
                            <> " (default: chosen from the geometry -- flat models are"
                            <> " viewed from above, solid ones isometrically)"
                        )
                  )
              )
            -- Degrees at the boundary and radians inside, as --tolerance is:
            -- degrees are what anyone turning a drawing thinks in.
            <*> option
              -- Refused during parsing, as --tolerance is: `read` for a Double
              -- accepts NaN, Infinity and 1e400, and a basis turned by one of
              -- those is all NaN. NaN coordinates format as 0, so what came out
              -- was a page with the whole model stacked on one point, and no
              -- error anywhere.
              (fmap toRadians . finite =<< auto)
              ( long "rotate"
                  <> metavar "DEG"
                  <> value 0
                  <> showDefault
                  <> help
                    ( "Turn the drawing anticlockwise on the page. A folded"
                        <> " model lands whichever way up its crease pattern was"
                        <> " drawn, and nothing in the file says which way up it"
                        <> " should be read"
                    )
              )
        )
    <*> option
      (indices . T.pack =<< str)
      ( long "stacking"
          <> metavar "N[,N...]"
          <> value []
          <> help
            ( "Which layer order to draw, when a model has several: one index"
                <> " per part of it that has a choice, in the order info lists"
                <> " them. Default: the first of each"
            )
      )
    <*> budgetOption
    <*> option
      -- Refused during parsing like every other malformed number here, and for
      -- both reasons at once. NaN and Infinity reach 'formatNumber', which
      -- writes them as 0, so a model drawn with one arrives stacked on the page
      -- origin with nothing reporting a fault. And a negative step is not an
      -- error the arithmetic would notice -- the stack would simply open out
      -- down and to the left -- but "how far apart" is a distance, and reading
      -- a minus sign as a direction is a guess about what someone meant.
      (points =<< auto)
      ( long "offset"
          <> metavar "PT"
          <> value 0
          <> showDefault
          <> help
            ( "Draw a folded model's layers this far apart on the page, so that"
                <> " a stack that lands on one spot can be read as a stack."
                <> " Needs the layers, so it goes with --fold and not with"
                <> " --no-fill"
            )
      )
  where
    points :: Double -> ReadM Double
    points d
      | d >= 0 && not (isNaN d) && not (isInfinite d) = pure d
      | otherwise = readerError "the layer offset must be a non-negative number of points"

    -- A comma-separated list of non-negative indices, refused during parsing
    -- like every other malformed option. "1," is a typo rather than a request
    -- for a default, so an empty field is rejected rather than filled in.
    indices :: Text -> ReadM [Int]
    indices raw = traverse (one . T.unpack) (T.splitOn "," raw)
      where
        one field = case reads field of
          -- Read as an Integer and narrowed afterwards. Reading straight into
          -- an Int wraps modulo 2^64 before any check can run, so a number too
          -- large to be an index came out as a perfectly good smaller one and
          -- drew a picture nobody asked for.
          [(n, "")] | n >= 0 && n <= toInteger (maxBound :: Int) -> pure (fromInteger n)
          _ ->
            readerError
              ( "--stacking wants comma-separated whole numbers from 0, not "
                  <> show (T.unpack raw)
              )

-- | Write the layer order the reader asked for into the frame.
--
-- Rather than threading the choice down through the renderer: a frame that
-- carries @faceOrders@ is drawn by them already, so choosing one and writing it
-- in is the whole of @--stacking@. It also means the choice is made once, here,
-- where a bad index can be reported against the file the reader named.
pickStacking :: RenderOptions -> Frame -> IO Frame
pickStacking o frame
  | null (roStacking o) = pure frame
  | otherwise = case solveStackingAs (roBudget o) (roStacking o) frame of
      Left err ->
        die
          ( "cannot draw that layer order for "
              <> T.pack (roInput o)
              <> ": "
              <> renderStackingError err
          )
      Right os -> pure frame {faceOrders = os}

run :: Command -> IO ()
run = \case
  Info o -> withFoldFile (ioInput o) (TIO.putStr . summarise o)
  Render o -> withFoldFile (roInput o) (renderFile o)
  Check o -> withFoldFile (coInput o) (checkFile o)

-- | Load a file or abort with a message on stderr.
withFoldFile :: FilePath -> (FoldFile -> IO ()) -> IO ()
withFoldFile path k =
  loadFoldFile path >>= \case
    Left err -> die (renderLoadError err)
    Right f -> k f

-- | The nth frame, or abort saying how many the file actually has.
--
-- The lower bound is not decoration: @drop@ on a negative index returns the
-- whole list, so without it @--frame -5@ quietly works on frame 0 while every
-- message says @-5@.
frameAt :: Int -> FoldFile -> IO Frame
frameAt i f = case drop i frames of
  (fr : _) | i >= 0 -> pure fr
  _ ->
    die $
      "no frame "
        <> tshow i
        <> "; this file has "
        <> tshow (length frames)
  where
    frames = allFrames f

renderFile :: RenderOptions -> FoldFile -> IO ()
renderFile o f
  | roSteps o = renderStepPage o f
  | otherwise = renderOneFrame o f

-- | Every frame of the file as one numbered page of figures.
--
-- The work is 'stepPage', in the library, where it can be tested and where
-- there is one copy of it. What is left here is refusing flag combinations and
-- turning an error into a message.
renderStepPage :: RenderOptions -> FoldFile -> IO ()
renderStepPage o f = do
  -- Refused rather than silently ignored: --steps uses every frame, so a
  -- request for one particular frame cannot also be honoured.
  when (isJust (roFrame o)) (die "--steps lays out every frame; --frame selects one")
  when (roFold o) (die "--steps draws the frames a file already has; --fold computes a new one")
  -- Every frame has its own layer order and its own components, so one list of
  -- indices cannot mean anything across a page of them. --layer-budget does
  -- apply, and is passed through below: it says how hard to look, which is the
  -- same question for every frame.
  unless
    (null (roStacking o))
    (die "--steps lays out every frame, and --stacking chooses an order for one")
  let theme = themeFor o
      grid = (defaultGrid theme) {gridColumns = roColumns o}
  case stepPage theme (roBudget o) grid (roView o) (roArrows o) (allFrames f) of
    Left (StepError i err) ->
      die
        ( "cannot render frame "
            <> tshow i
            <> " of "
            <> T.pack (roInput o)
            <> ": "
            <> renderFoldError err
        )
    Right Nothing ->
      die (T.pack (roInput o) <> " has no frame with any geometry in it")
    Right (Just d) -> emitWith o (pageFor o (fileTitle f)) d

renderOneFrame :: RenderOptions -> FoldFile -> IO ()
renderOneFrame o f = do
  chosen <- frameAt (fromMaybe 0 (roFrame o)) f
  -- Refused rather than resolved. --arrows describes the step from this frame
  -- to the next one in the file, and --fold replaces this frame with one
  -- computed from it, so together they would draw a motion whose start point is
  -- not where the paper is any more.
  when (roFold o && roArrows o) $
    die "--fold and --arrows describe different frames; use one or the other"
  frame <-
    if roFold o
      then case foldFrame chosen of
        Left err ->
          die ("cannot fold " <> T.pack (roInput o) <> ": " <> renderFoldingError err)
        Right folded -> pure folded
      else pure chosen
  drawn <- pickStacking o frame
  motions <- stepMotions o drawn (drop (fromMaybe 0 (roFrame o) + 1) (allFrames f))
  let theme = themeFor o
      pg = pageFor o (frameTitle drawn <|> fileTitle f)
  case creasePatternAuto theme (roBudget o) (roView o) drawn of
    Left err -> die (cannotRender o err)
    Right d
      | null motions -> emitWith o pg d
      | otherwise -> do
          basis <- basisOf o frame
          emitWith o pg (withArrows theme basis motions d)

-- | Each flag turns one thing off or one thing on. Written as guards rather
-- than as assignments so that a flag left off defers to whatever defaultTheme
-- says, instead of asserting today's value of it.
themeFor :: RenderOptions -> Theme
themeFor o = hideFlat (noFill (offset defaultTheme))
  where
    hideFlat t
      | roHideFlat o = t {themeShowFlat = False, themeShowUnassigned = False}
      | otherwise = t

    noFill t
      | roNoFill o = t {themePaper = Nothing}
      | otherwise = t

    -- The one flag that adds rather than subtracts, and still a guard: left
    -- off, --offset means "whatever the theme says" rather than "zero". The two
    -- are the same number today and need not stay so.
    offset t
      | roOffset o /= 0 = t {themeLayerOffset = roOffset o}
      | otherwise = t

pageFor :: RenderOptions -> Maybe Text -> Page
pageFor o title =
  defaultPage
    { pageWidth = roWidth o,
      pageHeight = roHeight o,
      pageMargin = roMargin o,
      pageBackground = if roTransparent o then Nothing else Just (Colour "#ffffff"),
      pageTitle = title
    }

-- | The motions to draw on this frame, given the frames that come after it.
--
-- The final picture of a sequence shows the finished model, and a book draws no
-- arrow on it. Neither do we.
stepMotions :: RenderOptions -> Frame -> [Frame] -> IO [Motion]
stepMotions o frame later
  | not (roArrows o) = pure []
  | otherwise = case later of
      [] -> pure []
      (next : _) -> case motionsBetween frame next of
        Left err ->
          die ("cannot work out the step in " <> T.pack (roInput o) <> ": " <> renderFoldError err)
        Right ms -> pure ms

-- | The arrows have to be projected the same way the drawing was. 'basisFor' is
-- the decision creasePatternAuto makes, asked again rather than reimplemented,
-- so the two cannot drift apart.
basisOf :: RenderOptions -> Frame -> IO Basis
basisOf o frame = case frameVertices frame of
  Left err -> die (cannotRender o err)
  Right verts -> pure (basisFor (roView o) verts)

cannotRender :: RenderOptions -> FoldError -> Text
cannotRender o err = "cannot render " <> T.pack (roInput o) <> ": " <> renderFoldError err

emitWith :: RenderOptions -> Page -> Diagram -> IO ()
emitWith o pg d = maybe TIO.putStr TIO.writeFile (roOutput o) (renderSvg pg d)

checkFile :: CheckOptions -> FoldFile -> IO ()
checkFile o f = do
  frame <- frameAt (coFrame o) f
  case checkFrame (Tolerance (coTolerance o * pi / 180)) frame of
    Left err ->
      die ("cannot check " <> T.pack (coInput o) <> ": " <> renderCheckError err)
    Right report -> do
      TIO.putStr (formatReport (coInput o) (coFrame o) report)
      -- A non-zero exit so `senbazuru check` composes into a build or a
      -- pre-commit hook without anyone having to grep the output.
      unless (null (reportViolations report)) exitFailure

-- | The report, with a heading saying which file and frame it is about.
--
-- The body comes from 'renderReport'. The wording there is load-bearing and is
-- tested; what is left here is the heading and two spaces of indent.
formatReport :: FilePath -> Int -> Report -> Text
formatReport path frameIx report =
  T.unlines $
    (T.pack path <> ", frame " <> tshow frameIx)
      : map ("  " <>) (renderReport report)

-- | A short human summary of a file, for poking at unfamiliar FOLD data.
summarise :: InfoOptions -> FoldFile -> Text
summarise o f =
  T.unlines $
    [ T.pack (ioInput o),
      "  title:   " <> fromMaybe "(none)" (fileTitle f),
      "  creator: " <> fromMaybe "(none)" (fileCreator f),
      "  classes: " <> commas (fileClasses f),
      "  frames:  " <> tshow (length (allFrames f))
    ]
      <> concatMap frameLines (zip [0 :: Int ..] (allFrames f))
  where
    frameLines (i, fr) =
      [ "  frame " <> tshow i <> ": " <> fromMaybe "(untitled)" (frameTitle fr),
        "    classes:  " <> commas (frameClasses fr),
        "    vertices: " <> tshow (length (verticesCoords fr)),
        "    edges:    " <> tshow (length (edgesVertices fr)),
        "    faces:    " <> tshow (length (facesVertices fr)),
        "    creases:  " <> histogram (edgesAssignment fr),
        -- Reported because it is the difference between a folded form drawn as
        -- paper and one drawn as a wireframe, and there is otherwise no way to
        -- find that out short of opening the JSON.
        "    layers:   " <> layers
      ]
        -- The one line that says what --stacking may be given, and the reason
        -- info grew a --fold: without it the indices are not discoverable
        -- anywhere. Shown only when there is something to choose, since most
        -- models have exactly one layer order and a line saying so every time
        -- would be noise.
        --
        -- Counted differently from the layers line above, on purpose. That one
        -- counts components the way Flat-Folder does, with the settled pairs
        -- among them, so that its published figures can be compared with ours.
        -- This one counts what a reader can act on, which is only the
        -- components with more than one answer in them.
        <> [ "    stacking: "
               <> plural (length choices) "component"
               <> " with a choice; --stacking takes "
               <> T.intercalate ", " (map range choices)
             | not (null choices)
           ]
      where
        (layers, choices) = layersOf fr
        range c =
          "0-"
            <> tshow (length (choiceStates c) - 1)
            -- The budget stopped the count, so there may be more than this.
            <> (if choiceCapped c then "+" else "")

    histogram as
      | null as = "(none recorded)"
      | otherwise = T.unwords [entry a n | a <- [minBound .. maxBound], let n = count a as, n > 0]
      where
        entry a n = assignmentCode a <> "=" <> tshow n
        count :: Assignment -> [Assignment] -> Int
        count a = length . filter (== a)

    -- With --fold the layers line describes the folded form, since that is
    -- where layers exist at all. Only that line: everything above it counts
    -- what the file stores, and folding does not change any of it.
    layersOf fr
      | not (ioFold o) = stackingOf fr
      | otherwise = case foldFrame fr of
          -- A frame that is already a folded form is the thing --fold asks to
          -- see, so it is described rather than refused. A multi-frame sequence
          -- is a crease pattern followed by folded steps, and the flag would
          -- otherwise break exactly the frames it is meant to be about.
          Left (AlreadyFolded _) -> stackingOf fr
          Left err -> ("(cannot be folded: " <> renderFoldingError err <> ")", [])
          Right folded -> stackingOf folded

    -- A folded form with no faceOrders has its layers worked out at render
    -- time, and this is the one place to find out whether that will succeed
    -- and, if not, why -- the renderer falls back to a wireframe without a word
    -- when the solver does not cover a model.
    --
    -- Returns the components alongside the line, so that the two lines above
    -- come from one solve rather than two: they are two readings of the same
    -- answer.
    stackingOf :: Frame -> (Text, [Choice])
    stackingOf fr = case faceOrders fr of
      os@(_ : _) -> (tshow (length os) <> " faceOrders", [])
      [] -> case frameVertices fr of
        -- Said as such, rather than falling through to the crease-pattern
        -- line: a frame whose vertices cannot be read is not a crease pattern,
        -- and this would be the one line of the summary to hide that.
        Left err -> ("(none; the vertices cannot be read: " <> renderFoldError err <> ")", [])
        Right verts
          | frameKind (frameClasses fr) verts == FoldedForm -> case stackingSpace (ioBudget o) fr of
              Right space -> ("(none in the file; " <> worked space <> ")", stackingsChoices space)
              Left err ->
                ("(none in the file, and none worked out: " <> renderStackingError err <> ")", [])
          | otherwise -> ("(none, and a crease pattern needs none)", [])

    -- What the solver made of a frame that carries no faceOrders: how many
    -- pairs of faces overlap, how few of them are actually open questions, and
    -- how many different models that leaves.
    worked space =
      plural pairs "overlapping pair"
        <> " in "
        <> plural (componentCount space) "component"
        <> ", "
        <> (if capped then "at least " else "")
        <> plural states "valid order"
      where
        pairs = length (stackingsForced space) + sum [length (choicePairs c) | c <- stackingsChoices space]
        (states, capped) = stateCount space

    -- Over any number type, because one of these counts pairs and components as
    -- Int and the other counts orders as Integer -- there being models with
    -- more orders than an Int can hold.
    plural :: (Show a, Num a, Eq a) => a -> Text -> Text
    plural n what = tshow n <> " " <> what <> (if n == 1 then "" else "s")

    commas [] = "(none)"
    commas xs = T.intercalate ", " xs

die :: Text -> IO a
die msg = hPutStrLn stderr ("senbazuru: " <> T.unpack msg) >> exitFailure

tshow :: (Show a) => a -> Text
tshow = T.pack . show
