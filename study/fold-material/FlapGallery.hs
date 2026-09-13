-- | Export the library's checked flap motions through ordinary renderers.
-- The study executable is only the reproducible driver: flap selection,
-- contact checking and angle-derived surfaces all live in the library.
module FlapGallery (writeFlapGallery) where

import Control.Monad (forM)
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import FlapExample
import FoldRelaxation (maxLengthError)
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid)
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Explain (Explain, explain)
import Senbazuru.Fold.Types (EdgeId (..), FaceId (..), FoldFile (..), Frame (..), emptyFrame)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Flap
import Senbazuru.Origami.Folding (foldFrameWith)
import Senbazuru.Origami.HingeSweep (defaultSweepSettings, sweepIntervals)
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Camera (View (..), basisFrom)
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import Senbazuru.Render.Steps (stepPage)
import Senbazuru.Render.Svg (Page (..), defaultPage, escapeXml, renderSvg)
import System.Directory (copyFile, createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))

writeFlapGallery :: FilePath -> IO ()
writeFlapGallery destination = do
  let output = destination </> "checked-flap"
  createDirectoryIfMissing True output
  closingStart <- checked (foldFrameWith singleFlap {edgesFoldAngle = replicate 7 0})
  closing <- checked (prepareFlap (EdgeId 6) (FaceId 1) 180 closingStart >>= checkFlap defaultSweepSettings)
  closed <- checked (flapAt closing 1)
  let closedFrame = surfaceFrame closed
      reopening = singleFlap {edgesFoldAngle = edgesFoldAngle closedFrame, faceOrders = faceOrders closedFrame}
  firstEntry <- writeMotion output "single" "Fold completely flat" closing
  otherEntries <- forM [("reopen", "Reopen the same fold", reopening, EdgeId 6, FaceId 1, -180), ("opposing", "Between two flaps", opposingFlap, EdgeId 9, FaceId 2, 16)] $ \(key, title, frame, crease, side, travel) -> do
    start <- checked (foldFrameWith frame)
    motion <- checked (prepareFlap crease side travel start >>= checkFlap defaultSweepSettings)
    writeMotion output key title motion
  let entries = firstEntry : otherEntries
  start <- checked (foldFrameWith opposingFlap)
  rejected <- checked (prepareFlap (EdgeId 9) (FaceId 2) 360 start)
  refusal <- case checkFlap defaultSweepSettings rejected of
    Left err@FlapCollision {} -> pure (explain err)
    Left err -> die ("expected a collision witness for the full turn: " ++ T.unpack (explain err))
    Right _ -> die "unsafe full turn unexpectedly accepted"
  BL.writeFile (output </> "models.json") (encode (concatMap (\(_, models, _) -> models) entries))
  BL.writeFile (output </> "checks.json") (encode (object ["motions" .= [report | (_, _, report) <- entries], "rejectedRoute" .= refusal]))
  copyFile "study/gltf/viewer.html" (output </> "index.html")
  template <- TIO.readFile "study/fold-material/flap.html"
  TIO.writeFile (destination </> "flap.html") (T.replace "<!--MOTIONS-->" (T.concat [card | (card, _, _) <- entries]) (T.replace "<!--REFUSAL-->" (escapeXml refusal) template))
  putStrLn ("Wrote checked flap SVGs, FOLD states, GLBs, audit and flap.html to " ++ destination)

writeMotion :: FilePath -> String -> T.Text -> CheckedFlap -> IO (T.Text, [Value], Value)
writeMotion output key title motion = do
  states <- checked (traverse (flapAt motion) [0, 1 / 3, 2 / 3, 1])
  let frames = [(materialFrame surface) {frameTitle = Just (title <> " · state " <> T.pack (show i))} | (i, surface) <- zip [1 :: Int ..] states]
  BL.writeFile (output </> key ++ ".fold") (encode (sequenceFile title frames))
  basis <- maybe (die "invalid side camera") pure (basisFrom (V3 (-1) 1 (negate (sqrt 2))) (V3 0 0 1))
  drawing <- checked (stepPage defaultTheme defaultBudget (defaultGrid defaultTheme) {gridColumns = 4} (View (Just basis) 0) True frames)
  diagram <- maybe (die "flap sequence has no geometry") pure drawing
  TIO.writeFile (output </> key ++ ".svg") (renderSvg defaultPage {pageWidth = 1120, pageHeight = 340, pageMargin = 30, pageBackground = Nothing, pageTitle = Just title} diagram)
  exports <- forM (zip [1 :: Int ..] states) $ \(i, surface) -> do
    let file = key ++ "-" ++ show i ++ ".glb"
        label = title <> " · state " <> T.pack (show i)
    bytes <- checked (renderSurfaceGlb defaultBudget VisiblePaper (Just label) surface)
    BS.writeFile (output </> file) bytes
    (mesh, _) <- checked (refineSurface 0 surface)
    pure (object ["title" .= label, "path" .= file], maxLengthError mesh)
  let intervals = sweepIntervals (flapCheck motion)
      error' = maximum (0 : map snd exports)
      card = "<section><h2>" <> escapeXml title <> "</h2><img src=\"checked-flap/" <> T.pack key <> ".svg\" alt=\"Four checked angle states, viewed from 45 degrees above a corner\"><p>Whole rotation cleared. Interval checks: " <> T.pack (show intervals) <> ". <a href=\"checked-flap/" <> T.pack key <> ".fold\">FOLD sequence</a> · <a href=\"checked-flap/" <> T.pack key <> ".svg\">SVG page</a></p></section>"
      report = object ["name" .= title, "intervals" .= intervals, "movingFaces" .= map unFaceId (flapMovingFaces motion), "maxRelativeEdgeError" .= error', "angles" .= map edgesFoldAngle frames, "faceOrders" .= map faceOrders frames]
  pure (card, map fst exports, report)

sequenceFile :: T.Text -> [Frame] -> FoldFile
sequenceFile title = FoldFile (Just 1.2) (Just "senbazuru checked flap demo") Nothing (Just title) Nothing ["diagrams"] emptyFrame

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
