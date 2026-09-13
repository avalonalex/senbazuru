-- | Show the checked crane wing through the ordinary SVG/FOLD/glTF
-- boundaries. CraneWing owns the recipe; this module chooses illustrations
-- and a shared camera on the moving wing’s side at 45 degrees.
module CraneGallery (writeCraneGallery, craneSvg) where

import Control.Monad (forM)
import CraneWing
import Data.Aeson (Value, encode, object, (.=))
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import FoldRelaxation (maxLengthError)
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

craneSvg :: FoldFile -> Either Text Text
craneSvg file = do
  basis <- maybe (Left "invalid crane camera") Right (basisFrom (V3 (-1) 1 (sqrt 2)) (V3 0 0 1))
  drawing <- first explain (stepPage defaultTheme defaultBudget (defaultGrid defaultTheme) {gridColumns = 4} (View (Just basis) 0) True (otherFrames file))
  diagram <- maybe (Left "crane sequence has no geometry") Right drawing
  pure (renderSvg defaultPage {pageWidth = 1120, pageHeight = 390, pageMargin = 30, pageBackground = Nothing, pageTitle = fileTitle file} diagram)

writeCraneGallery :: FilePath -> IO ()
writeCraneGallery destination = do
  let output = destination </> "checked-crane"
  createDirectoryIfMissing True output
  source <- loadFoldFile "examples/crane.fold" >>= checked . first explain
  wing <- checked (buildCraneWing (keyFrame source))
  states <- checked (craneStates wing)
  let file = craneFile states
  BL.writeFile (output </> "sequence.fold") (encode file)
  svg <- checked (craneSvg file)
  TIO.writeFile (output </> "sequence.svg") svg
  models <- forM (zip [0 :: Int ..] states) $ \(i, (title, surface)) -> do
    let path = "state-" ++ show i ++ ".glb"
    bytes <- checked (first explain (renderSurfaceGlb defaultBudget VisiblePaper (Just title) surface))
    BS.writeFile (output </> path) bytes
    pure (object ["title" .= (tshow (i + 1) <> " · " <> title), "path" .= path])
  reports <- traverse stateReport states
  BL.writeFile (output </> "models.json") (encode models)
  BL.writeFile (output </> "checks.json") (encode (object ["moves" .= [moveReport wing], "wrongDirectionRefusal" .= craneRefusal wing, "states" .= reports]))
  -- Reuse the existing viewer's locally installed Three.js dependency. This
  -- keeps --flap and --crane usable together without a second npm install.
  copyFile "study/gltf/viewer.html" (output </> "index.html")
  viewer <- TIO.readFile (output </> "index.html")
  TIO.writeFile (output </> "index.html") (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer)
  template <- TIO.readFile "study/fold-material/crane.html"
  let captions = T.concat ["<li>" <> escapeXml title <> "</li>" | (title, _) <- states]
  TIO.writeFile (destination </> "crane.html") (T.replace "<!--STATES-->" captions template)
  putStrLn ("Wrote checked crane SVG, FOLD, four GLBs and crane.html to " ++ destination)

moveReport :: CraneWing -> Value
moveReport wing = object ["title" .= ("Lower one wing" :: Text), "intervals" .= sweepIntervals (flapCheck (craneOpening wing)), "movingFaces" .= map unFaceId (flapMovingFaces (craneOpening wing))]

stateReport :: (Text, Surface V2) -> IO Value
stateReport (title, surface) = do
  (mesh, _) <- checked (first explain (refineSurface 0 surface))
  let frame = surfaceFrame surface
  pure (object ["title" .= title, "maxRelativeEdgeError" .= maxLengthError mesh, "angles" .= edgesFoldAngle frame, "faceOrders" .= faceOrders frame])

checked :: Either Text a -> IO a
checked = either (die . T.unpack) pure
