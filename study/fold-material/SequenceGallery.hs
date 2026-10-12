-- | Run a fold sequence and present it as one of the study's galleries: a page
-- of figures through the ordinary SVG, FOLD and glTF writers, a 3D viewer of
-- each figure, and the checks behind them. "BlintzGallery" and
-- "HelmetGallery" are one 'Gallery' each, a handful of choices. Everything
-- from reading the source to writing the page is here, once, so that a fix
-- made for one gallery cannot miss the other.
--
-- The page shows more than a run writes. A run writes one state per step, its
-- end; the page also shows each turn part-way, drawn from the checked turn its
-- record carries ('turnOf', 'flapAt'). How far along is a fraction of that
-- record's own turn, not an angle: 0.5 of a half turn is 90°, and 0.5 of a
-- quarter turn is 45°. A gallery that labels its poses in degrees has to know
-- the size of its turns to do so, and says how it knows.
--
-- No test writes a gallery. The specs build each page from a run with
-- 'pageStates', 'pageFile' and 'pageSvg', and @test/golden/checked-blintz.svg@
-- and @checked-helmet.svg@ pin the two pages byte for byte. Everything else
-- 'writeSequenceGallery' writes is checked only by running it.
module SequenceGallery
  ( Gallery (..),
    PartWay (..),
    writeSequenceGallery,
    pageStates,
    pageFile,
    pageSvg,
    turnOf,
  )
where

import Control.Monad (forM, unless)
import Data.Aeson (Value, encode, object, (.=))
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (zip4)
import Data.Map.Strict qualified as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import FoldRelaxation (maxLengthError)
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid)
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Explain (explain, tshow)
import Senbazuru.Fold.Load (loadFoldFile, readSequenceText)
import Senbazuru.Fold.Types (FaceId (..), FoldFile (..), Frame (..), emptyFrame)
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Flap (CheckedFlap, flapAt, flapCheck, flapMovingFaces)
import Senbazuru.Origami.HingeSweep (sweepIntervals)
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Camera (View (..), basisFrom)
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import Senbazuru.Render.Steps (stepPage)
import Senbazuru.Render.Svg (Page (..), defaultPage, escapeXml, renderSvg)
import Senbazuru.Sequence.Check (checkSequence, checkedSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Parse (parseSequence)
import Senbazuru.Sequence.Record (MoveRecord, RouteEvidence (..), Run (..), recordAfter, recordBefore, recordCaption, recordEvidence)
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence)
import Senbazuru.Sequence.Syntax (SourceFile (..), sourceFiles)
import System.Directory (copyFile, createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (takeFileName, (</>))

-- | What one gallery chooses. Paths are from the repository root, where the
-- study runs.
data Gallery = Gallery
  { -- | The name of what is folded, in messages and in the FOLD file's creator.
    galleryName :: Text,
    -- | The sequence source. The sheet is read from where the source says.
    gallerySource :: FilePath,
    -- | The directory, under the destination, for the page's SVG and FOLD
    -- file, a GLB per figure, the checks and the viewer. The HTML template
    -- links into it by this name.
    galleryDirectory :: FilePath,
    -- | FOLD's @file_title@, which the SVG takes as its @\<title\>@ too.
    galleryTitle :: Text,
    -- | The direction the camera looks along, given to 'basisFrom' with +z as
    -- up. One with a positive z looks up at the paper from below.
    galleryViewDirection :: V3,
    galleryPageWidth :: Double,
    galleryPageHeight :: Double,
    -- | One pose part-way through each move's turn, in the order of the run's
    -- records. A run of more or fewer moves is refused.
    galleryPartWay :: [PartWay],
    -- | The HTML page, written to the destination under its own file name,
    -- with a caption for each figure in place of @\<!--STATES--\>@.
    galleryTemplate :: FilePath
  }

-- | A pose part-way through one move's turn.
data PartWay = PartWay
  { -- | What the figure's title says after \"Move N · \".
    partWayLabel :: Text,
    -- | How far along, as 'flapAt' takes it: 0 at the turn's start, 1 at its
    -- end, a fraction of that record's turn whatever its size.
    partWayFraction :: Double
  }

-- | The page's figures, titled: the open square, then each move's turn
-- part-way and its end. A move's end is the next move's start, so it appears
-- once. The interval check covered each turn whole, so the motion between
-- the figures is checked too.
pageStates :: Gallery -> Run -> Either Text [(Text, Surface V2)]
pageStates gallery run = do
  turns <- first (\problem -> "the " <> galleryName gallery <> " page: " <> problem) (traverse turnOf records)
  unless (length poses == length records) $
    Left ("the " <> galleryName gallery <> " page has " <> tshow (length poses) <> " part-way poses for the run's " <> tshow (length records) <> " moves")
  case zip4 [1 :: Int ..] records turns poses of
    [] -> Left ("the " <> galleryName gallery <> " run made no turns")
    moves@((_, opening, _, _) : _) -> do
      states <- traverse figuresOf moves
      pure (("Start with the open square", recordBefore opening) : concat states)
  where
    records = runRecords run
    poses = galleryPartWay gallery
    figuresOf (i, record, turn, partWay) = do
      midway <- first explain (flapAt turn (partWayFraction partWay))
      pure [("Move " <> tshow i <> " · " <> partWayLabel partWay, midway), (fromMaybe ("Move " <> tshow i) (recordCaption record), recordAfter record)]

-- | Each record's turn, which the page draws part-way through. Every kind of
-- evidence is named, so that one added to 'RouteEvidence' is a warning here
-- rather than a turn the page silently cannot draw.
turnOf :: MoveRecord -> Either Text CheckedFlap
turnOf record = case recordEvidence record of
  SweptHinge turn -> Right turn
  Presented -> Left "a move that turns the model over or round, which a gallery's page does not draw"
  NoMotion -> Left "a move that names an anchor, which a gallery's page does not draw"

-- | The page's figures as one FOLD file, a frame each, titled as on the page.
pageFile :: Gallery -> [(Text, Surface V2)] -> FoldFile
pageFile gallery states =
  FoldFile
    (Just 1.2)
    (Just ("senbazuru checked " <> galleryName gallery <> " sequence"))
    Nothing
    (Just (galleryTitle gallery))
    Nothing
    ["diagrams"]
    emptyFrame
    [(materialFrame surface) {frameTitle = Just title} | (title, surface) <- states]

-- | The page drawn: every figure in four columns, from one camera, each but
-- the last with an arrow for the fold that takes it to the next.
pageSvg :: Gallery -> FoldFile -> Either Text Text
pageSvg gallery file = do
  basis <- maybe (Left ("invalid " <> galleryName gallery <> " camera")) Right (basisFrom (galleryViewDirection gallery) (V3 0 0 1))
  drawing <- first explain (stepPage defaultTheme defaultBudget (defaultGrid defaultTheme) {gridColumns = 4} (View (Just basis) 0) True (otherFrames file))
  diagram <- maybe (Left (galleryName gallery <> " sequence has no geometry")) Right drawing
  pure (renderSvg defaultPage {pageWidth = galleryPageWidth gallery, pageHeight = galleryPageHeight gallery, pageMargin = 30, pageBackground = Nothing, pageTitle = fileTitle file} diagram)

-- | Run the gallery's source and write its page under the destination.
writeSequenceGallery :: Gallery -> FilePath -> IO ()
writeSequenceGallery gallery destination = do
  let output = destination </> galleryDirectory gallery
      sourcePath = gallerySource gallery
  createDirectoryIfMissing True output
  source <- readSequenceText sourcePath >>= checked . first explain
  sequence' <- checked (first explain (parseSequence sourcePath source >>= checkSequence))
  -- The sheet the source names, read from where the source says and keyed as
  -- it is written there, as the run command finds and keys it, so that the
  -- path is written once.
  sheets <- forM (sourceFiles sourcePath (checkedSequence sequence')) $ \named -> do
    sheet <- loadFoldFile (sourceToOpen named) >>= checked . first explain
    pure (sourceWritten named, sheet)
  run <- checked (first explain (runSequence defaultRunSettings (M.fromList sheets) (elaborate sequence')))
  states <- checked (pageStates gallery run)
  moves <- checked (traverse (\record -> (,) record <$> turnOf record) (runRecords run))
  let file = pageFile gallery states
  BL.writeFile (output </> "sequence.fold") (encode file)
  svg <- checked (pageSvg gallery file)
  TIO.writeFile (output </> "sequence.svg") svg
  models <- forM (zip [0 :: Int ..] states) $ \(i, (title, surface)) -> do
    let glb = "state-" ++ show i ++ ".glb"
    bytes <- checked (first explain (renderSurfaceGlb defaultBudget VisiblePaper (Just title) surface))
    BS.writeFile (output </> glb) bytes
    pure (object ["title" .= (tshow (i + 1) <> " · " <> title), "path" .= glb])
  reports <- traverse stateReport states
  BL.writeFile (output </> "models.json") (encode models)
  BL.writeFile (output </> "checks.json") (encode (object ["moves" .= map moveReport moves, "states" .= reports]))
  -- Reuse the existing viewer's locally installed Three.js dependency. This
  -- keeps --flap and each sequence gallery usable together without a second
  -- npm install.
  copyFile "study/gltf/viewer.html" (output </> "index.html")
  viewer <- TIO.readFile (output </> "index.html")
  TIO.writeFile (output </> "index.html") (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer)
  template <- TIO.readFile (galleryTemplate gallery)
  let captions = T.concat ["<li>" <> escapeXml title <> "</li>" | (title, _) <- states]
      html = takeFileName (galleryTemplate gallery)
  TIO.writeFile (destination </> html) (T.replace "<!--STATES-->" captions template)
  putStrLn ("Wrote checked " ++ T.unpack (galleryName gallery) ++ " SVG, FOLD, " ++ show (length states) ++ " GLBs and " ++ html ++ " to " ++ destination)

moveReport :: (MoveRecord, CheckedFlap) -> Value
moveReport (record, turn) = object ["title" .= recordCaption record, "intervals" .= sweepIntervals (flapCheck turn), "movingFaces" .= map unFaceId (flapMovingFaces turn)]

stateReport :: (Text, Surface V2) -> IO Value
stateReport (title, surface) = do
  (mesh, _) <- checked (first explain (refineSurface 0 surface))
  let frame = surfaceFrame surface
  pure (object ["title" .= title, "maxRelativeEdgeError" .= maxLengthError mesh, "angles" .= edgesFoldAngle frame, "faceOrders" .= faceOrders frame])

checked :: Either Text a -> IO a
checked = either (die . T.unpack) pure
