-- | Present the helmet base, run as a sequence from @helmet.foldseq@, through
-- the ordinary SVG/FOLD/glTF boundaries. A /base/ is a standard shape many
-- models start from (see docs/glossary.md, "Origami"); the helmet base is a
-- square folded diagonally in half, with both corners of the doubled triangle
-- then brought to its tip. The runner owns motion and state handoff; this
-- module only chooses illustrations and a camera, looking at the moving flaps
-- from above.
--
-- The page is seven poses: the open square and each step's end, which are
-- the states a run writes, and each turn part-way, which a run does not
-- write, drawn from the turn each record carries ('helmetStates'). The
-- study's hand-written recipe drew this page until #534 deleted it; #529 had
-- shown the run draws it byte for byte, and @test/golden/checked-helmet.svg@
-- is the guard that comparison was.
module HelmetGallery (writeHelmetGallery, helmetStates, helmetFile, helmetSvg, turnOf) where

import Control.Monad (forM)
import Data.Aeson (Value, encode, object, (.=))
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
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
import System.FilePath ((</>))

-- | Seven illustrations: the open square, then an intermediate and flat pose
-- of each turn. At this camera's 45-degree elevation the first 90-degree pose
-- has the open sheet's silhouette, so show 120 degrees instead. The corner
-- turns use 90 degrees. Every turn is a half turn, so a pose d degrees along
-- one is d/180 of the way. The interval check covers all the motion between
-- them.
helmetStates :: Run -> Either Text [(Text, Surface V2)]
helmetStates run = do
  turns <- traverse turnOf (runRecords run)
  case zip3 [1 :: Int ..] (runRecords run) turns of
    [] -> Left "the helmet run made no turns"
    moves@((_, opening, _) : _) -> do
      states <- traverse statesFor moves
      pure (("Start with the open square", recordBefore opening) : concat states)
  where
    statesFor (i, record, turn) = do
      let degrees = if i == 1 then 120 else 90 :: Double
      midway <- first explain (flapAt turn (degrees / 180))
      pure [("Move " <> tshow i <> " · " <> tshow (round degrees :: Int) <> "°", midway), (fromMaybe ("Move " <> tshow i) (recordCaption record), recordAfter record)]

-- | Each record's turn, which the page draws part-way through. Every kind of
-- evidence is named, so that one added to 'RouteEvidence' is a warning here
-- rather than a turn this page silently cannot draw.
turnOf :: MoveRecord -> Either Text CheckedFlap
turnOf record = case recordEvidence record of
  SweptHinge turn -> Right turn
  Presented -> Left "a helmet move that turns the model over or round, which this page does not draw"
  NoMotion -> Left "a helmet move that names an anchor, which this page does not draw"

helmetFile :: [(Text, Surface V2)] -> FoldFile
helmetFile states =
  FoldFile
    (Just 1.2)
    (Just "senbazuru checked helmet sequence")
    Nothing
    (Just "Three turns to the helmet base")
    Nothing
    ["diagrams"]
    emptyFrame
    [(materialFrame surface) {frameTitle = Just title} | (title, surface) <- states]

helmetSvg :: FoldFile -> Either Text Text
helmetSvg file = do
  basis <- maybe (Left "invalid helmet camera") Right (basisFrom (V3 (-1) 1 (negate (sqrt 2))) (V3 0 0 1))
  drawing <- first explain (stepPage defaultTheme defaultBudget (defaultGrid defaultTheme) {gridColumns = 4} (View (Just basis) 0) True (otherFrames file))
  diagram <- maybe (Left "helmet sequence has no geometry") Right drawing
  pure (renderSvg defaultPage {pageWidth = 1120, pageHeight = 620, pageMargin = 30, pageBackground = Nothing, pageTitle = fileTitle file} diagram)

writeHelmetGallery :: FilePath -> IO ()
writeHelmetGallery destination = do
  let output = destination </> "checked-helmet"
  createDirectoryIfMissing True output
  source <- readSequenceText "helmet.foldseq" >>= checked . first explain
  sequence' <- checked (first explain (parseSequence "helmet.foldseq" source >>= checkSequence))
  -- The sheet the source names, read from where the source says and keyed as
  -- it is written there, as the run command reads it, so that the path is
  -- written once.
  sheets <- forM (sourceFiles "helmet.foldseq" (checkedSequence sequence')) $ \named -> do
    sheet <- loadFoldFile (sourceToOpen named) >>= checked . first explain
    pure (sourceWritten named, sheet)
  run <- checked (first explain (runSequence defaultRunSettings (M.fromList sheets) (elaborate sequence')))
  states <- checked (helmetStates run)
  moves <- checked (traverse (\record -> (,) record <$> turnOf record) (runRecords run))
  let file = helmetFile states
  BL.writeFile (output </> "sequence.fold") (encode file)
  svg <- checked (helmetSvg file)
  TIO.writeFile (output </> "sequence.svg") svg
  models <- forM (zip [0 :: Int ..] states) $ \(i, (title, surface)) -> do
    let path = "state-" ++ show i ++ ".glb"
    bytes <- checked (first explain (renderSurfaceGlb defaultBudget VisiblePaper (Just title) surface))
    BS.writeFile (output </> path) bytes
    pure (object ["title" .= (tshow (i + 1) <> " · " <> title), "path" .= path])
  reports <- traverse stateReport states
  BL.writeFile (output </> "models.json") (encode models)
  BL.writeFile (output </> "checks.json") (encode (object ["moves" .= map moveReport moves, "states" .= reports]))
  -- Reuse the existing viewer's locally installed Three.js dependency. This
  -- keeps --flap and --helmet usable together without a second npm install.
  copyFile "study/gltf/viewer.html" (output </> "index.html")
  viewer <- TIO.readFile (output </> "index.html")
  TIO.writeFile (output </> "index.html") (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer)
  template <- TIO.readFile "study/fold-material/helmet.html"
  let captions = T.concat ["<li>" <> escapeXml title <> "</li>" | (title, _) <- states]
  TIO.writeFile (destination </> "helmet.html") (T.replace "<!--STATES-->" captions template)
  putStrLn ("Wrote checked helmet SVG, FOLD, seven GLBs and helmet.html to " ++ destination)

moveReport :: (MoveRecord, CheckedFlap) -> Value
moveReport (record, turn) = object ["title" .= recordCaption record, "intervals" .= sweepIntervals (flapCheck turn), "movingFaces" .= map unFaceId (flapMovingFaces turn)]

stateReport :: (Text, Surface V2) -> IO Value
stateReport (title, surface) = do
  (mesh, _) <- checked (first explain (refineSurface 0 surface))
  let frame = surfaceFrame surface
  pure (object ["title" .= title, "maxRelativeEdgeError" .= maxLengthError mesh, "angles" .= edgesFoldAngle frame, "faceOrders" .= faceOrders frame])

checked :: Either Text a -> IO a
checked = either (die . T.unpack) pure
