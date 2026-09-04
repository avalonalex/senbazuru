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
    commandParser,
  )
where

import Control.Applicative ((<|>))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Version (makeVersion, showVersion)
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
import Senbazuru.Render.Camera
  ( Basis,
    isometric,
    namedView,
    topDown,
    viewNames,
  )
import Senbazuru.Render.CreasePattern (creasePatternFrom)
import Senbazuru.Render.Svg (Page (..), defaultPage, renderSvg)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

-- | What the user asked for.
data Command
  = Render RenderOptions
  | Info FilePath
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
    -- | 'Nothing' means choose from the frame's own declared class.
    roView :: Maybe Text
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
    )

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
      ( strOption
          ( long "view"
              <> metavar "NAME"
              <> help
                ( "Viewing angle: "
                    <> T.unpack (T.intercalate ", " viewNames)
                    <> " (default: top for crease patterns, iso for folded forms)"
                )
          )
      )

run :: Command -> IO ()
run = \case
  Info path -> withFoldFile path (TIO.putStr . summarise path)
  Render o -> withFoldFile (roInput o) (renderFile o)

-- | Load a file or abort with a message on stderr.
withFoldFile :: FilePath -> (FoldFile -> IO ()) -> IO ()
withFoldFile path k =
  loadFoldFile path >>= \case
    Left err -> die (renderLoadError err)
    Right f -> k f

renderFile :: RenderOptions -> FoldFile -> IO ()
renderFile o f = do
  frame <- case drop (roFrame o) (allFrames f) of
    (fr : _) -> pure fr
    [] ->
      die $
        "no frame "
          <> tshow (roFrame o)
          <> "; this file has "
          <> tshow (length (allFrames f))
  basis <- resolveView frame
  case creasePatternFrom theme basis frame of
    Left err -> die ("cannot render " <> T.pack (roInput o) <> ": " <> renderFoldError err)
    Right d -> emit (renderSvg (page frame) d)
  where
    -- With no --view, take the frame at its word. A foldedForm sits in space and
    -- looks like nothing much from directly above; anything else is flat, where
    -- a three-quarter view would only skew it. Files declaring no class fall
    -- back to top, so their output never changes.
    resolveView :: Frame -> IO Basis
    resolveView frame = case roView o of
      Nothing
        | "foldedForm" `elem` frameClasses frame -> pure isometric
        | otherwise -> pure topDown
      Just name -> case namedView name of
        Just b -> pure b
        Nothing ->
          die $
            "unknown view "
              <> tshow name
              <> "; expected one of "
              <> T.intercalate ", " viewNames

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
