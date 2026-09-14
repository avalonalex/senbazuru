-- | Static crane spreading controls, measured before any picture is published.
-- The coarse/fine comparison shares grips and a camera. Only independently
-- accepted endpoints enter the SVG and glTF gallery; failed controls retain
-- complete material FOLD files for diagnosis.
module CraneSpreadGallery (writeCraneSpread, spreadSvg) where

import Control.Exception (evaluate)
import Control.Monad (forM, unless, when)
import CraneSpread
import Data.Aeson (encode, object, (.=))
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Set qualified as S
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldMaterial (areaRatio, componentCount, resolvedTriangles)
import FoldRelaxation
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid)
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types (FoldFile (..))
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Camera (View (..), basisFrom)
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import Senbazuru.Render.Steps (stepPage)
import Senbazuru.Render.Svg (Page (..), defaultPage, renderSvg)
import SparseSolve (LinearReport (..))
import System.CPUTime (getCPUTime)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import WingBending (finalMesh)
import WingBendingGallery (refinement)

writeCraneSpread :: FilePath -> IO ()
writeCraneSpread destination = do
  let output = destination </> "crane-spreading"
      controls = [("rigid", "Rigid wing · 30° root", 3, 0, False), ("curved", "Curved wing · 50° grip", 3, 20, False), ("fine", "Curved wing · finer mesh", 4, 20, False), ("crossed-grip", "Upper grip below lower · incompatible", 3, 20, True)]
  createDirectoryIfMissing True output
  source <- loadFoldFile "examples/crane.fold" >>= checked
  runs <- forM controls $ \(stem, title, level, degrees, invalid) -> do
    original <- checked (craneSpread (keyFrame source) level degrees)
    let fixture = if invalid then crossedGrip original else original
    start <- getCPUTime
    result <- checked (solveSpread (Settings (if invalid then 2 else 20) 1e-5) fixture)
    mesh <- checked (finalMesh result)
    _ <- evaluate (maxLengthError mesh + if converged result then 1 else 0)
    settled <- getCPUTime
    contact <- checked (spreadCheck fixture mesh)
    accepted <- checked (spreadAccepted fixture result mesh)
    _ <- evaluate accepted
    inspected <- getCPUTime
    sheet <- checked (spreadSurface fixture mesh)
    angles <- checked (spreadAngleError fixture mesh)
    (crease, panel) <- checked (bendingEnergy (spreadHinges fixture) mesh)
    let initial = IM.fromList (zip [0 ..] (samples (refinedMesh (spreadRefined fixture))))
        bodyError = maximum (0 : [norm (position p ^-^ position q) | (i, p) <- zip [0 ..] (samples mesh), S.member i (spreadBody fixture), Just q <- [IM.lookup i initial]])
        strains = [strain | triangle <- resolvedTriangles mesh, Just strain <- [principalStrains triangle]]
        equilibrium check = let linear = equilibriumLinear check in object ["linearConverged" .= linearConverged linear, "linearResidual" .= linearResidual linear, "linearThreshold" .= linearThreshold linear, "fullMovement" .= equilibriumMovement check, "movementThreshold" .= (1e-7 :: Double)]
        report =
          object
            [ "id" .= stem,
              "title" .= title,
              "refinement" .= level,
              "rootDegrees" .= (30 :: Int),
              "gripDegrees" .= (30 + degrees),
              "accepted" .= accepted,
              "converged" .= converged result,
              "equilibrium" .= fmap equilibrium (equilibriumCheck result),
              "iterations" .= maximum (0 : map completedIterations (checkpoints result)),
              "vertices" .= length (samples mesh),
              "triangles" .= length (triangles mesh),
              "components" .= componentCount mesh,
              "sourcePanels" .= S.size (S.fromList (refinedPanels (spreadRefined fixture))),
              "sourceEdges" .= S.size (S.fromList (map fst (refinedEdges (spreadRefined fixture)))),
              "sourceOrders" .= length (spreadOrders fixture),
              "heldBodyVertices" .= S.size (spreadBody fixture),
              "maxRelativeEdgeError" .= maxLengthError mesh,
              "areaRatio" .= areaRatio mesh,
              "minPrincipalStrain" .= minimum (0 : map fst strains),
              "maxPrincipalStrain" .= maximum (0 : map snd strains),
              "heldPositionError" .= spreadHeldError fixture mesh,
              "bodyPositionError" .= bodyError,
              "maxCreaseAngleErrorRadians" .= angles,
              "creaseEnergy" .= crease,
              "panelEnergy" .= panel,
              "contact" .= contact,
              "solveCpuSeconds" .= seconds (settled - start),
              "checkCpuSeconds" .= seconds (inspected - settled),
              "continuousMotionChecked" .= False
            ]
        file = FoldFile (Just 1.2) (Just "senbazuru connected crane spreading study") Nothing (Just title) Nothing [] (materialFrame sheet) []
    BL.writeFile (output </> stem ++ ".fold") (encode file)
    when accepted $ do
      bytes <- checked (renderSurfaceGlb defaultBudget VisiblePaper (Just title) sheet)
      BS.writeFile (output </> stem ++ ".glb") bytes
    putStrLn (stem ++ ": " ++ if accepted then "accepted" else "unaccepted diagnostic")
    pure (stem, title, accepted, sheet, report, panel)
  unless ([accepted | (_, _, accepted, _, _, _) <- runs] == [True, True, True, False]) (die "Unexpected crane control result; refusing to publish the gallery")
  let baseline = [sheet | (stem, _, True, sheet, _, _) <- runs, stem `elem` ["rigid", "curved"]]
      bent = [(sheet, energy) | (stem, _, True, sheet, _, energy) <- runs, stem `elem` ["curved", "fine"]]
      comparisons = [object ["geometry" .= refinement a b, "relativeEnergyChange" .= (abs (eb - ea) / ea)] | ((a, ea), (b, eb)) <- zip bent (drop 1 bent)]
      document = object ["runs" .= [report | (_, _, _, _, report, _) <- runs], "refinement" .= comparisons]
  BL.writeFile (output </> "checks.json") (encode document)
  drawing <- either (die . T.unpack) pure (spreadSvg baseline)
  TIO.writeFile (output </> "comparison.svg") drawing
  finer <- either (die . T.unpack) pure (spreadSvg (map fst bent))
  TIO.writeFile (output </> "refinement.svg") finer
  BL.writeFile (output </> "models.json") (encode [object ["title" .= title, "path" .= (stem ++ ".glb")] | (stem, title, True, _, _, _) <- runs])
  viewer <- TIO.readFile "study/gltf/viewer.html"
  TIO.writeFile (output </> "index.html") (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer)
  template <- TIO.readFile "study/fold-material/crane-spreading.html"
  TIO.writeFile (destination </> "crane-spreading.html") (T.replace "/*SPREAD_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn ("Wrote crane-spreading.html and checked endpoints to " ++ destination)

spreadSvg :: [Surface V2] -> Either T.Text T.Text
spreadSvg sheets = do
  camera <- maybe (Left "invalid crane camera") Right (basisFrom (V3 (-1) 1 (sqrt 2)) (V3 0 0 1))
  drawing <- first explain (stepPage defaultTheme defaultBudget (defaultGrid defaultTheme) {gridColumns = length sheets} (View (Just camera) 0) False (map surfaceFrame sheets))
  diagram <- maybe (Left "crane comparison has no geometry") Right drawing
  pure (renderSvg defaultPage {pageWidth = 1080, pageHeight = 380, pageMargin = 28, pageBackground = Nothing, pageTitle = Just "Spreading the connected crane wing"} diagram)

seconds :: Integer -> Double
seconds n = fromIntegral n / 1e12

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
