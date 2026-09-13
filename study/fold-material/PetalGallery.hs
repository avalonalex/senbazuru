-- | Illustrations of the continuously checked first bird petal. Motion and
-- certification live in CheckedPetal; this module selects eight views through
-- the existing SVG and glTF backends, looking down at 45 degrees from the side.
module PetalGallery (writePetalGallery, petalSvg) where

import CheckedPetal
import Control.Monad (forM)
import Data.Aeson (eitherDecode, encode, object, (.=))
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (find)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import FoldRelaxation (maxLengthError)
import PetalCertificate
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid)
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Explain (explain, tshow)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types (FoldFile (..), Frame (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Render.Camera (View (..), basisFrom)
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import Senbazuru.Render.Steps (stepPage)
import Senbazuru.Render.Svg (Page (..), defaultPage, escapeXml, renderSvg)
import StudyCase
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))

petalSvg :: FoldFile -> Either Text Text
petalSvg file = do
  basis <- maybe (Left "invalid petal camera") Right (basisFrom (V3 (-1) 0 (-1)) (V3 0 0 1))
  drawing <- first explain (stepPage defaultTheme defaultBudget (defaultGrid defaultTheme) {gridColumns = 4} (View (Just basis) 0) True (otherFrames file))
  diagram <- maybe (Left "petal sequence has no geometry") Right drawing
  pure (renderSvg defaultPage {pageWidth = 1120, pageHeight = 700, pageMargin = 30, pageBackground = Nothing, pageTitle = fileTitle file} diagram)

writePetalGallery :: FilePath -> IO ()
writePetalGallery destination = do
  let output = destination </> "checked-petal"
  createDirectoryIfMissing True output
  cases <- BL.readFile "study/fold-material/cases.json" >>= either die pure . eitherDecode
  entry <- checked (maybe (Left "missing bird petal case") Right (find ((== "bird-petal") . caseId) (cases :: [CaseSpec])))
  source <- loadFoldFile (caseSource entry) >>= checked . first explain
  motion <- checked (preparePetal entry (keyFrame source))
  file <- checked (petalFile motion)
  BL.writeFile (output </> "sequence.fold") (encode file)
  checked (petalSvg file) >>= TIO.writeFile (output </> "sequence.svg")
  models <- forM (zip [0 :: Int ..] petalStates) $ \(i, t) -> do
    pose <- checked (checkedPetalAt motion t)
    let path = "state-" ++ show i ++ ".glb"
        label = fromMaybe "Petal" (frameTitle (poseFrame pose))
    surface <- checked (checkedPetalSurface motion t)
    bytes <- checked (first explain (renderSurfaceGlb defaultBudget VisiblePaper (Just label) surface))
    BS.writeFile (output </> path) bytes
    pure (object ["title" .= (tshow (i + 1) <> " · " <> label), "path" .= path])
  reports <- forM petalStates $ \t -> do
    pose <- checked (checkedPetalAt motion t)
    frame <- checked (checkedPetalFrame motion t)
    pure (object ["hingeDegrees" .= t, "maxRelativeEdgeError" .= maxLengthError (poseMesh pose), "angles" .= edgesFoldAngle frame, "faceOrders" .= faceOrders frame])
  let report = petalCheck motion
  BL.writeFile (output </> "models.json") (encode models)
  BL.writeFile (output </> "checks.json") (encode (object ["intervals" .= petalIntervals report, "panelPairs" .= petalPairs report, "endpointOrders" .= petalEndpointOrders report, "materialEdges" .= petalEdges report, "certificate" .= ("Exact ideal path; exported angle poses agree within 1e-12 model units" :: Text), "states" .= reports]))
  viewer <- TIO.readFile "study/gltf/viewer.html"
  TIO.writeFile (output </> "index.html") (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer)
  template <- TIO.readFile "study/fold-material/petal.html"
  let captions = T.concat ["<li>" <> escapeXml (fromMaybe "Petal" (frameTitle fr)) <> "</li>" | fr <- otherFrames file]
  TIO.writeFile (destination </> "petal.html") (T.replace "<!--STATES-->" captions template)
  putStrLn ("Wrote continuously checked petal SVG, FOLD, eight GLBs and petal.html to " ++ destination)

checked :: Either Text a -> IO a
checked = either (die . T.unpack) pure
