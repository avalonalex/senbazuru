-- | Illustrations of the checked route from square base to bird base. Motion
-- and certification live in CheckedPetal and CheckedBird. Both SVG views use
-- one camera and scale across all sixteen figures; looking from underneath
-- reveals the back petal without changing the material or folding sequence.
module PetalGallery (writePetalGallery, petalSvg, birdSvg) where

import CheckedBird
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
petalSvg = sequenceSvg False 700

birdSvg :: Bool -> FoldFile -> Either Text Text
birdSvg underside = sequenceSvg underside 1280

sequenceSvg :: Bool -> Double -> FoldFile -> Either Text Text
sequenceSvg underside height file = do
  basis <- maybe (Left "invalid petal camera") Right (basisFrom (V3 (-1) 0 (if underside then 1 else -1)) (V3 0 0 1))
  drawing <- first explain (stepPage defaultTheme defaultBudget (defaultGrid defaultTheme) {gridColumns = 4} (View (Just basis) 0) True (otherFrames file))
  diagram <- maybe (Left "petal sequence has no geometry") Right drawing
  pure (renderSvg defaultPage {pageWidth = 1120, pageHeight = height, pageMargin = 30, pageBackground = Nothing, pageTitle = fileTitle file} diagram)

writePetalGallery :: FilePath -> IO ()
writePetalGallery destination = do
  let output = destination </> "checked-petal"
  createDirectoryIfMissing True output
  cases <- BL.readFile "study/fold-material/cases.json" >>= either die pure . eitherDecode
  entry <- checked (maybe (Left "missing bird petal case") Right (find ((== "bird-petal") . caseId) (cases :: [CaseSpec])))
  source <- loadFoldFile (caseSource entry) >>= checked . first explain
  motion <- checked (prepareBird entry (keyFrame source))
  file <- checked (birdFile motion)
  BL.writeFile (output </> "sequence.fold") (encode file)
  checked (birdSvg False file) >>= TIO.writeFile (output </> "sequence.svg")
  checked (birdSvg True file) >>= TIO.writeFile (output </> "sequence-below.svg")
  models <- forM (zip [0 :: Int ..] birdStates) $ \(i, (stage, progress)) -> do
    pose <- checked (checkedBirdAt motion stage progress)
    let path = "state-" ++ show i ++ ".glb"
        label = fromMaybe "Petal" (frameTitle (poseFrame pose))
    surface <- checked (checkedBirdSurface motion stage progress)
    bytes <- checked (first explain (renderSurfaceGlb defaultBudget VisiblePaper (Just label) surface))
    BS.writeFile (output </> path) bytes
    pure (object ["title" .= (tshow (i + 1) <> " · " <> label), "path" .= path])
  reports <- forM birdStates $ \(stage, progress) -> do
    pose <- checked (checkedBirdAt motion stage progress)
    frame <- checked (checkedBirdFrame motion stage progress)
    pure (object ["stage" .= show stage, "progress" .= progress, "hingeDegrees" .= birdHinges stage progress, "maxRelativeEdgeError" .= maxLengthError (poseMesh pose), "angles" .= edgesFoldAngle frame, "faceOrders" .= faceOrders frame])
  let certificates = [object ["stage" .= show stage, "intervals" .= petalIntervals report, "panelPairs" .= petalPairs report, "endpointOrders" .= petalEndpointOrders report, "materialEdges" .= petalEdges report] | (stage, report) <- birdChecks motion]
  BL.writeFile (output </> "models.json") (encode models)
  BL.writeFile (output </> "checks.json") (encode (object ["stages" .= certificates, "joins" .= (2 :: Int), "certificate" .= ("Exact ideal paths; exported angle poses agree within 1e-12 model units. Front and back use 0-to-175 prefixes of full turns; pressing uses the 175-to-180 suffix of the equal-hinge path." :: Text), "states" .= reports]))
  viewer <- TIO.readFile "study/gltf/viewer.html"
  TIO.writeFile (output </> "index.html") (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer)
  template <- TIO.readFile "study/fold-material/petal.html"
  let captions = T.concat ["<li>" <> escapeXml (fromMaybe "Petal" (frameTitle fr)) <> "</li>" | fr <- otherFrames file]
  TIO.writeFile (destination </> "petal.html") (T.replace "<!--STATES-->" captions template)
  putStrLn ("Wrote continuously checked bird SVGs, FOLD, sixteen GLBs and petal.html to " ++ destination)

checked :: Either Text a -> IO a
checked = either (die . T.unpack) pure
