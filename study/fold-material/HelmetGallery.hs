-- | Present the checked helmet recipe through the ordinary SVG/FOLD/glTF
-- boundaries. The recipe owns motion and state handoff; this module only
-- chooses illustrations and a camera, looking at the moving flaps from above.
module HelmetGallery (writeHelmetGallery, helmetSvg) where

import Control.Monad (forM)
import Data.Aeson (Value, encode, object, (.=))
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import FoldRelaxation (maxLengthError)
import HelmetSequence
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid)
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Explain (explain, tshow)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types (FaceId (..), FoldFile (..), Frame (..))
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Flap (flapCheck, flapMovingFaces)
import Senbazuru.Origami.HingeSweep (sweepIntervals)
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Camera (View (..), basisFrom)
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import Senbazuru.Render.Steps (stepPage)
import Senbazuru.Render.Svg (Page (..), defaultPage, escapeXml, renderSvg)
import System.Directory (copyFile, createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))

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
  source <- loadFoldFile "examples/helmet-base.fold" >>= checked . first explain
  moves <- checked (buildHelmetSequence (keyFrame source))
  states <- checked (helmetStates moves)
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

moveReport :: HelmetMove -> Value
moveReport move = object ["title" .= helmetTitle move, "intervals" .= sweepIntervals (flapCheck (helmetMotion move)), "movingFaces" .= map unFaceId (flapMovingFaces (helmetMotion move))]

stateReport :: (Text, Surface V2) -> IO Value
stateReport (title, surface) = do
  (mesh, _) <- checked (first explain (refineSurface 0 surface))
  let frame = surfaceFrame surface
  pure (object ["title" .= title, "maxRelativeEdgeError" .= maxLengthError mesh, "angles" .= edgesFoldAngle frame, "faceOrders" .= faceOrders frame])

checked :: Either Text a -> IO a
checked = either (die . T.unpack) pure
