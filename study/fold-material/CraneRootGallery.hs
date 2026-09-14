-- | Publish the controlled root comparisons with their numerical evidence.
-- Renderer failures retain complete-sheet GLBs and their errors separately
-- from physical acceptance. Failed endpoints have diagnostic FOLD files but
-- cannot enter the accepted
-- 3D model selector. Root spring residuals are reported separately from the
-- original folded creases, because a soft preference is not an exact hold.
module CraneRootGallery (writeCraneRoot) where

import Control.Exception (evaluate)
import Control.Monad (forM)
import CraneRoot
import CraneSpread
import CraneSpreadGallery (spreadSvg)
import Data.Aeson (encode, object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Either (isRight)
import Data.IntMap.Strict qualified as IM
import Data.Set qualified as S
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldMaterial (areaRatio, componentCount, resolvedTriangles)
import FoldRelaxation
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types (FoldFile (..), unEdgeId, unFaceId)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import Senbazuru.Render.Svg (formatNumber)
import SparseSolve (LinearReport (..))
import System.CPUTime (getCPUTime)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)
import WingBending (finalMesh)
import WingBendingGallery (refinement)

writeCraneRoot :: FilePath -> IO ()
writeCraneRoot destination = do
  let output = destination </> "crane-root"
      controls =
        [ ("held", "Held root · 30°", 3, HeldRoot, False),
          ("released", "Released strip · 30° preference", 3, ReleasedRoot, False),
          ("weaker", "Released strip · weaker spring", 3, WeakerRoot, False),
          ("flat", "Released strip · flat preference", 3, FlatRoot, False),
          ("fine", "Flat preference · finer mesh", 4, FlatRoot, False),
          ("body", "Flat preference · nearby body free", 3, FreeBody, False),
          ("crossed-grip", "Upper grip below lower · incompatible", 3, FlatRoot, True)
        ]
  createDirectoryIfMissing True output
  source <- loadFoldFile "examples/crane.fold" >>= checked
  runs <- forM controls $ \(stem, title, level, control, invalid) -> do
    original <- checked (craneRoot (keyFrame source) level control)
    let study = if invalid then original {rootSpread = crossedGrip (rootSpread original)} else original
        fixture = rootSpread study
        limit = if invalid then 2 else 40
    putStrLn ("Solving " ++ stem)
    hFlush stdout
    start <- getCPUTime
    result <- checked (solveSpread (Settings limit 1e-5) fixture)
    mesh <- checked (finalMesh result)
    _ <- evaluate (maxLengthError mesh + if converged result then 1 else 0)
    settled <- getCPUTime
    accepted <- checked (rootAccepted study result mesh)
    contact <- checked (spreadCheck fixture mesh)
    angles <- checked (rootAngles study mesh)
    creaseError <- checked (originalCreaseError study mesh)
    (creaseEnergy, panelEnergy) <- checked (bendingEnergy (spreadHinges fixture) mesh)
    sheet <- checked (spreadSurface fixture mesh)
    profile <- checked (rootProfile study mesh)
    let visibleResult = renderSurfaceGlb defaultBudget VisiblePaper (Just title) sheet
        drawing = spreadSvg [sheet]
        visible = accepted && isRight visibleResult
        visibleError = if accepted then either (Just . explain) (const Nothing) visibleResult else Nothing
        svgError = if accepted then either Just (const Nothing) drawing else Nothing
    if accepted
      then do
        case visibleResult of
          Right bytes -> BS.writeFile (output </> stem ++ ".glb") bytes
          Left err -> do
            putStrLn (stem ++ ": stable-view export unavailable: " ++ T.unpack (explain err))
            bytes <- checked (renderSurfaceGlb defaultBudget CompletePaper (Just title) sheet)
            BS.writeFile (output </> stem ++ "-complete.glb") bytes
        case drawing of
          Right svg -> TIO.writeFile (output </> stem ++ ".svg") svg
          Left err -> putStrLn (stem ++ ": SVG unavailable: " ++ T.unpack err)
      else pure ()
    let degrees = map ((180 / pi *) . abs . snd) angles
        strains = [strain | triangle <- resolvedTriangles mesh, Just strain <- [principalStrains triangle]]
        equilibrium check = let linear = equilibriumLinear check in object ["linearConverged" .= linearConverged linear, "linearResidual" .= linearResidual linear, "linearThreshold" .= linearThreshold linear, "fullMovement" .= equilibriumMovement check, "movementThreshold" .= (1e-7 :: Double)]
        report =
          object
            [ "id" .= stem,
              "title" .= title,
              "refinement" .= level,
              "control" .= show control,
              "iterationLimitPerStage" .= limit,
              "accepted" .= accepted,
              "visibleGlbAvailable" .= visible,
              "visibleGlbError" .= visibleError,
              "svgError" .= svgError,
              "converged" .= converged result,
              "equilibrium" .= fmap equilibrium (equilibriumCheck result),
              "vertices" .= length (samples mesh),
              "triangles" .= length (triangles mesh),
              "components" .= componentCount mesh,
              "heldVertices" .= IM.size (spreadPins fixture),
              "neighbourPanels" .= map unFaceId (S.toList (rootNeighbours study)),
              "sourceOrders" .= length (spreadOrders fixture),
              "activeSourceOrders" .= length (spreadContactOrders fixture),
              "rootAnglesRadians" .= [object ["sourceEdge" .= unEdgeId eid, "angle" .= angle] | (eid, angle) <- angles],
              "minRootDegrees" .= minimum (180 : degrees),
              "maxRootDegrees" .= maximum (0 : degrees),
              "maxOriginalCreaseErrorRadians" .= creaseError,
              "maxRelativeEdgeError" .= maxLengthError mesh,
              "areaRatio" .= areaRatio mesh,
              "minPrincipalStrain" .= minimum (0 : map fst strains),
              "maxPrincipalStrain" .= maximum (0 : map snd strains),
              "heldPositionError" .= spreadHeldError fixture mesh,
              "bodyMovement" .= rootBodyMovement study mesh,
              "creaseEnergy" .= creaseEnergy,
              "panelEnergy" .= panelEnergy,
              "contact" .= contact,
              "solveCpuSeconds" .= (fromIntegral (settled - start) / 1e12 :: Double),
              "continuousMotionChecked" .= False
            ]
        file = FoldFile (Just 1.2) (Just "senbazuru crane root material study") Nothing (Just title) Nothing [] (materialFrame sheet) []
    BL.writeFile (output </> stem ++ ".fold") (encode file)
    BL.writeFile (output </> stem ++ "-check.json") (encode report)
    putStrLn (stem ++ ": " ++ if accepted then "accepted" else "unaccepted diagnostic")
    hFlush stdout
    pure (stem, title, accepted, sheet, report, creaseEnergy + panelEnergy, profile, visible)
  let bent = [(sheet, energy) | (stem, _, True, sheet, _, energy, _, _) <- runs, stem `elem` ["flat", "fine"]]
      comparisons = [object ["geometry" .= refinement a b, "relativeTotalEnergyChange" .= (abs (eb - ea) / ea)] | ((a, ea), (b, eb)) <- zip bent (drop 1 bent)]
      document = object ["runs" .= [report | (_, _, _, _, report, _, _, _) <- runs], "refinement" .= comparisons]
  BL.writeFile (output </> "checks.json") (encode document)
  let comparison = [(title, sheet) | (stem, title, True, sheet, _, _, _, True) <- runs, stem `elem` ["held", "flat", "body"]]
  drawing <- either (die . T.unpack) pure (spreadSvg (map snd comparison))
  TIO.writeFile (output </> "comparison.svg") drawing
  TIO.writeFile (output </> "profile.svg") (profileSvg [(stem, points) | (stem, _, True, _, _, _, points, _) <- runs, stem `elem` ["held", "released", "weaker", "flat", "body"]])
  BL.writeFile (output </> "models.json") (encode [object ["title" .= title, "path" .= (stem ++ ".glb")] | (stem, title, True, _, _, _, _, True) <- runs])
  viewer <- TIO.readFile "study/gltf/viewer.html"
  TIO.writeFile (output </> "index.html") (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer)
  template <- TIO.readFile "study/fold-material/crane-root.html"
  TIO.writeFile (destination </> "crane-root.html") (T.replace "/*ROOT_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn ("Wrote crane-root.html and measurements to " ++ destination)

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure

-- One scale for every profile; the original root lies halfway along the plot.
-- y points towards the body and z points up in the model. Negating both draws
-- the wing tip to the right and its downward displacement down the SVG page.
profileSvg :: [(String, [V3])] -> T.Text
profileSvg curves =
  "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1080 430\" role=\"img\"><title>Measured side profiles through the wing root</title>"
    <> "<path d=\"M40 80H1040M540 50V410\" stroke=\"#c2b7a4\" stroke-dasharray=\"4 5\" fill=\"none\"/>"
    <> "<g font-family=\"system-ui,sans-serif\" font-size=\"18\" fill=\"#292d28\"><text x=\"40\" y=\"35\">Body</text><text x=\"470\" y=\"35\">Original root</text><text x=\"930\" y=\"35\">Wing tip</text></g>"
    <> T.concat ["<polyline fill=\"none\" stroke=\"" <> color stem <> "\" stroke-width=\"2.5\" points=\"" <> T.unwords [formatNumber (40 + 2000 * (0.5 - y)) <> "," <> formatNumber (80 - 2000 * z) | V3 _ y z <- points] <> "\"/>" | (stem, points) <- curves]
    <> "</svg>"
  where
    color stem = case stem of "held" -> "#675949"; "released" -> "#a94e32"; "weaker" -> "#bc862b"; "flat" -> "#267364"; _ -> "#5654a0"
