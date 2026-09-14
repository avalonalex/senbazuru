-- | Publish held two-layer shapes and failed controls without confusing them.
-- Only converged, independently checked endpoints enter the image/model list.
-- Unaccepted runs retain their full FOLD geometry and measurements for diagnosis.
-- This is a static material experiment, not a certified motion between grips.
module WingLayersGallery (writeWingLayers) where

import Control.Exception (evaluate)
import Control.Monad (forM, unless, when)
import Data.Aeson (encode, object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldContact (ContactRow (..))
import FoldMaterial (areaRatio, componentCount, resolvedTriangles)
import FoldRelaxation
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types (FaceId (..), FoldFile (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import SurfaceContact qualified as Contact
import System.CPUTime (getCPUTime)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import WingBending (finalMesh)
import WingBendingGallery (wingSvg)
import WingLayers

writeWingLayers :: FilePath -> IO ()
writeWingLayers destination = do
  let output = destination </> "wing-layers"
      controls =
        [ ("flat", "Two layers · flat", 8, 0, id, defaultSettings),
          ("bend-20", "Two layers · grip at 20°", 8, 20, id, defaultSettings),
          ("bend-40", "Two layers · grip at 40°", 8, 40, id, defaultSettings),
          ("perturbed", "Upper layer starts inside lower", 8, 40, perturbUpper (-0.002), defaultSettings),
          ("lifted", "Upper grip lifted · layers can separate", 8, 40, offsetUpperGrip 0.01, defaultSettings),
          ("fine-flat", "Finer mesh · flat", 16, 0, id, defaultSettings),
          -- Bounded diagnostics make generation reproducible even when the
          -- stiff linear solve cannot settle. They are not convergence tests.
          ("fine-bend", "Finer mesh · 12 iterations per stage", 16, 40, id, Settings 12 1e-5),
          ("bad-grip", "Upper grip held below lower · incompatible", 8, 40, offsetUpperGrip (-0.01), Settings 8 1e-5)
        ]
  createDirectoryIfMissing True output
  runs <- forM controls $ \(stem, title, n, degrees, modify, settings) -> do
    initial <- checked (wingLayers n degrees)
    let fixture = modify initial
    start <- getCPUTime
    result <- checked (solveLayers settings fixture)
    mesh <- checked (finalMesh result)
    _ <- evaluate (maxLengthError mesh + if converged result then 1 else 0)
    settled <- getCPUTime
    contact <- checked (checkTriangleContact (V3 0 0 1) [(FaceId 0, FaceId 1)] (layersOwners fixture) mesh)
    _ <- evaluate (contactPassed contact)
    inspected <- getCPUTime
    sheet <- checked (layersSurface fixture mesh)
    (crease, panel) <- checked (bendingEnergy (layersHinges fixture) mesh)
    let vertices = IM.fromList (zip [0 ..] (samples mesh))
        heldError = maximum (0 : [norm (position actual ^-^ target) | (i, target) <- IM.toList (layersPins fixture), Just actual <- [IM.lookup i vertices]])
    angles <- mapM (\h -> abs . (`angleError` hingeRest h) . fst <$> checked (hingeAngle h vertices)) [h | h <- layersHinges fixture, SurfaceCrease _ <- [hingeRole h]]
    ordered <- checked (Contact.prepareContact 0 (V3 0 0 1) [(FaceId 0, FaceId 1)] (layersOwners fixture) mesh)
    rows <- checked (Contact.orderedContacts ordered mesh)
    let accepted = converged result && contactPassed contact && heldError == 0 && maximum (0 : angles) < 1e-7
        strains = [strain | triangle <- resolvedTriangles mesh, Just strain <- [principalStrains triangle]]
        pairedDistances = [norm (position a ^-^ position b) | (i, j) <- layersPairs fixture, Just a <- [IM.lookup i vertices], Just b <- [IM.lookup j vertices]]
        report =
          object
            [ "id" .= stem,
              "title" .= title,
              "divisions" .= n,
              "gripDegrees" .= degrees,
              "accepted" .= accepted,
              "converged" .= converged result,
              "iterationsPerStageLimit" .= iterationLimit settings,
              "iterations" .= maximum (0 : map completedIterations (checkpoints result)),
              "vertices" .= length (samples mesh),
              "triangles" .= length (triangles mesh),
              "components" .= componentCount mesh,
              "sourcePanels" .= (2 :: Int),
              "materialCreases" .= (1 :: Int),
              "areaRatio" .= areaRatio mesh,
              "minPrincipalStrain" .= minimum (0 : map fst strains),
              "maxPrincipalStrain" .= maximum (0 : map snd strains),
              "maxRelativeEdgeError" .= maxLengthError mesh,
              "heldPositionError" .= heldError,
              "maxRootAngleErrorRadians" .= maximum (0 : angles),
              "minOrderedGap" .= minimum (0 : map contactGap rows),
              "maxPairedVertexDistance" .= maximum (0 : pairedDistances),
              "creaseEnergy" .= crease,
              "panelEnergy" .= panel,
              "solveCpuSeconds" .= seconds (settled - start),
              "checkCpuSeconds" .= seconds (inspected - settled),
              "contact" .= contact,
              "continuousMotionChecked" .= False
            ]
        file = FoldFile (Just 1.2) (Just "senbazuru touching layer study") Nothing (Just title) Nothing [] (materialFrame sheet) []
    BL.writeFile (output </> stem ++ ".fold") (encode file)
    when accepted $ do
      bytes <- checked (renderSurfaceGlb defaultBudget VisiblePaper (Just title) sheet)
      BS.writeFile (output </> stem ++ ".glb") bytes
      drawing <- either (die . T.unpack) pure (wingSvg [sheet])
      TIO.writeFile (output </> stem ++ ".svg") drawing
    putStrLn (stem ++ ": " ++ if accepted then "accepted" else "unaccepted diagnostic; see checks.json")
    pure (stem, title, accepted, sheet, report)
  let document = object ["runs" .= [report | (_, _, _, _, report) <- runs]]
      mainShapes = [sheet | (stem, _, True, sheet, _) <- runs, stem `elem` ["flat", "bend-20", "bend-40"]]
  BL.writeFile (output </> "checks.json") (encode document)
  unless (any (\(stem, _, accepted, _, _) -> stem == "lifted" && accepted) runs) (die "Lifted-grip control did not pass; refusing to publish its illustration")
  when (length mainShapes /= 3) (die "Two-layer comparison did not pass; refusing to publish a complete gallery")
  comparison <- either (die . T.unpack) pure (wingSvg mainShapes)
  TIO.writeFile (output </> "sequence.svg") comparison
  BL.writeFile (output </> "models.json") (encode [object ["title" .= title, "path" .= (stem ++ ".glb")] | (stem, title, True, _, _) <- runs])
  viewer <- TIO.readFile "study/gltf/viewer.html"
  TIO.writeFile (output </> "index.html") (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer)
  template <- TIO.readFile "study/fold-material/wing-layers.html"
  TIO.writeFile (destination </> "wing-layers.html") (T.replace "/*LAYER_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn ("Wrote wing-layers.html, accepted surfaces and diagnostic FOLDs to " ++ destination)

seconds :: Integer -> Double
seconds n = fromIntegral n / 1e12

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
