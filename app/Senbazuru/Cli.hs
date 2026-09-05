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
import Senbazuru.Origami.Folding (foldFrame, renderFoldingError)
import Senbazuru.Origami.Stacking (renderStackingError, solveStacking)
import Senbazuru.Origami.Step (Motion, motionsBetween)
import Senbazuru.Render.Camera (Basis, namedView, viewNames)
import Senbazuru.Render.CreasePattern (basisFor, creasePatternAuto, withArrows)
import Senbazuru.Render.Steps (StepError (..), stepPage)
import Senbazuru.Render.Svg (Page (..), defaultPage, renderSvg)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

-- | What the user asked for.
data Command
  = Render RenderOptions
  | Info FilePath
  | Check CheckOptions
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
    -- | 'Nothing' means let the geometry decide. Resolved to a 'Basis' during
    -- argument parsing, so an unknown name never reaches this record.
    roView :: Maybe Basis
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
          (info (Info <$> inputArg) (progDesc "Summarise a FOLD file"))
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
      (long "no-fill" <> help "Draw the sheet as a wireframe, with faces left unfilled")
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
    <*> optional
      ( option
          -- Resolved during parsing, so a bad name is rejected with optparse's
          -- own usage text before any file is opened, and roView carries a
          -- Basis rather than an unvalidated string.
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

run :: Command -> IO ()
run = \case
  Info path -> withFoldFile path (TIO.putStr . summarise path)
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
  let theme = themeFor o
      grid = (defaultGrid theme) {gridColumns = roColumns o}
  case stepPage theme grid (roView o) (roArrows o) (allFrames f) of
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
  motions <- stepMotions o frame (drop (fromMaybe 0 (roFrame o) + 1) (allFrames f))
  let theme = themeFor o
      pg = pageFor o (frameTitle frame <|> fileTitle f)
  case creasePatternAuto theme (roView o) frame of
    Left err -> die (cannotRender o err)
    Right d
      | null motions -> emitWith o pg d
      | otherwise -> do
          basis <- basisOf o frame
          emitWith o pg (withArrows theme basis motions d)

-- | Each flag only ever subtracts from the default. Written as guards rather
-- than as assignments so that a flag left off defers to whatever defaultTheme
-- says, instead of asserting today's value of it.
themeFor :: RenderOptions -> Theme
themeFor o = hideFlat (noFill defaultTheme)
  where
    hideFlat t
      | roHideFlat o = t {themeShowFlat = False, themeShowUnassigned = False}
      | otherwise = t

    noFill t
      | roNoFill o = t {themePaper = Nothing}
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
summarise :: FilePath -> FoldFile -> Text
summarise path f =
  T.unlines $
    [ T.pack path,
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
        "    layers:   " <> stacking fr
      ]

    histogram as
      | null as = "(none recorded)"
      | otherwise = T.unwords [entry a n | a <- [minBound .. maxBound], let n = count a as, n > 0]
      where
        entry a n = assignmentCode a <> "=" <> tshow n
        count :: Assignment -> [Assignment] -> Int
        count a = length . filter (== a)

    -- A folded form with no faceOrders has its layers worked out at render
    -- time, and this is the one place to find out whether that will succeed
    -- and, if not, why -- the renderer falls back to a wireframe without a
    -- word when the solver does not cover a model.
    stacking fr = case faceOrders fr of
      os@(_ : _) -> tshow (length os) <> " faceOrders"
      [] -> case frameVertices fr of
        -- Said as such, rather than falling through to the crease-pattern
        -- line: a frame whose vertices cannot be read is not a crease pattern,
        -- and this would be the one line of the summary to hide that.
        Left err -> "(none; the vertices cannot be read: " <> renderFoldError err <> ")"
        Right verts
          | frameKind (frameClasses fr) verts == FoldedForm -> case solveStacking fr of
              Right os ->
                "(none in the file; "
                  <> tshow (length os)
                  <> " overlapping pairs worked out from the geometry)"
              Left err ->
                "(none in the file, and none worked out: " <> renderStackingError err <> ")"
          | otherwise -> "(none, and a crease pattern needs none)"

    commas [] = "(none)"
    commas xs = T.intercalate ", " xs

die :: Text -> IO a
die msg = hPutStrLn stderr ("senbazuru: " <> T.unpack msg) >> exitFailure

tshow :: (Show a) => a -> Text
tshow = T.pack . show
