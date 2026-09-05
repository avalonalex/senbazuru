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

import Control.Monad (unless)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Version (makeVersion, showVersion)
import Numeric (showFFloat)
import Options.Applicative
import Senbazuru.Diagram (Colour (..))
import Senbazuru.Diagram.Style (Theme (..), defaultTheme)
import Senbazuru.Fold.Load (loadFoldFile, renderLoadError)
import Senbazuru.Fold.Query (renderFoldError)
import Senbazuru.Fold.Types
  ( Assignment,
    FoldFile (..),
    Frame (..),
    allFrames,
    assignmentCode,
  )
import Senbazuru.Origami.FlatFold
  ( Report (..),
    Skip (..),
    Tolerance (..),
    checkFrame,
    defaultTolerance,
    renderCheckError,
    renderViolation,
    reportViolations,
  )
import Senbazuru.Render.Camera (Basis, namedView, viewNames)
import Senbazuru.Render.CreasePattern (creasePatternAuto)
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
    roFrame :: Int,
    roWidth :: Double,
    roHeight :: Double,
    roMargin :: Double,
    roTransparent :: Bool,
    roHideFlat :: Bool,
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
              (progDesc "Test every interior vertex for flat-foldability")
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
      auto
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
    <*> option
      auto
      ( long "frame"
          <> metavar "N"
          <> value 0
          <> showDefault
          <> help "Which frame to render (0 is the key frame)"
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
frameAt :: Int -> FoldFile -> IO Frame
frameAt i f = case drop i (allFrames f) of
  (fr : _) -> pure fr
  [] ->
    die $
      "no frame "
        <> tshow i
        <> "; this file has "
        <> tshow (length (allFrames f))

renderFile :: RenderOptions -> FoldFile -> IO ()
renderFile o f = do
  frame <- frameAt (roFrame o) f
  let rendered = creasePatternAuto theme (roView o) frame
  case rendered of
    Left err -> die ("cannot render " <> T.pack (roInput o) <> ": " <> renderFoldError err)
    Right d -> emit (renderSvg (page frame) d)
  where
    theme
      | roHideFlat o = defaultTheme {themeShowFlat = False, themeShowUnassigned = False}
      | otherwise = defaultTheme

    page frame =
      defaultPage
        { pageWidth = roWidth o,
          pageHeight = roHeight o,
          pageMargin = roMargin o,
          pageBackground = if roTransparent o then Nothing else Just (Colour "#ffffff"),
          -- Prefer the frame's own title; fall back to the file's.
          pageTitle = frameTitle frame <|> fileTitle f
        }

    emit = maybe TIO.putStr TIO.writeFile (roOutput o)

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

-- | The report as text.
--
-- Deliberately says \"no violations found\" rather than \"flat-foldable\". The
-- checks are local and necessary rather than sufficient, and a tool that
-- overstates them teaches the wrong thing.
formatReport :: FilePath -> Int -> Report -> Text
formatReport path frameIx report =
  T.unlines $
    (T.pack path <> ", frame " <> tshow frameIx)
      : map ("  " <>) (violationLines <> summaryLines)
  where
    violations = reportViolations report
    violationLines = [renderViolation v x | (v, x) <- violations]

    summaryLines =
      [ "checked "
          <> plural (length (reportChecked report)) "interior vertex" "interior vertices"
          <> skippedNote,
        if null violations
          then "no violations found"
          else plural (length violations) "violation" "violations"
      ]

    skippedNote = case (countSkips OnBorder, countSkips NoCreases) of
      (0, 0) -> ""
      (border, 0) -> "; skipped " <> tshow border <> " on the border"
      (0, bare) -> "; skipped " <> tshow bare <> " with no creases"
      (border, bare) ->
        "; skipped "
          <> tshow border
          <> " on the border and "
          <> tshow bare
          <> " with no creases"

    countSkips s = length [() | (_, s') <- reportSkipped report, s' == s]

    plural n one several = tshow n <> " " <> (if n == 1 then one else several)

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
        "    creases:  " <> histogram (edgesAssignment fr)
      ]

    histogram as
      | null as = "(none recorded)"
      | otherwise = T.unwords [entry a n | a <- [minBound .. maxBound], let n = count a as, n > 0]
      where
        entry a n = assignmentCode a <> "=" <> tshow n
        count :: Assignment -> [Assignment] -> Int
        count a = length . filter (== a)

    commas [] = "(none)"
    commas xs = T.intercalate ", " xs

die :: Text -> IO a
die msg = hPutStrLn stderr ("senbazuru: " <> T.unpack msg) >> exitFailure

tshow :: (Show a) => a -> Text
tshow = T.pack . show
