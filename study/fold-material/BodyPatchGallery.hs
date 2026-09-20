-- | A bounded four-run experiment with explicit free boundaries and failures.
-- The raw FOLDs and reports are always saved. Rejected numerical iterates get
-- labelled wire diagrams, never an accepted-paper preview. Every diagram uses
-- the same camera and 600 page units per original sheet unit; SVG and GLB use
-- the identical endpoint, with no visual displacement of touching layers.
module BodyPatchGallery (writeBodyPatch) where

import BodyPatch
import Control.Exception (evaluate)
import Control.Monad (forM)
import CranePocket
import CraneSpread
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldMaterial (areaRatio, componentCount, meshEdges, resolvedTriangles)
import FoldRelaxation
import Senbazuru.Diagram
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Camera (Basis, View (..), bottomUp, frontOn, project, topDown)
import Senbazuru.Render.CreasePattern (surfaceDiagram)
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import Senbazuru.Render.Svg
import SparseSolve (LinearReport (..))
import SurfaceContact qualified as Contact
import System.CPUTime (getCPUTime)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)
import WingBending (finalMesh)

writeBodyPatch :: FilePath -> IO ()
writeBodyPatch destination = do
  let output = destination </> "body-patch"
  createDirectoryIfMissing True output
  source <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= checked)
  atlas <- checked (buildCranePocket source)
  runs <- forM [("closed", 0, 0), ("opening-5", 0, 5), ("opening-10", 0, 10), ("opening-5-fine", 1, 5)] $ \(stem, level, degrees) -> do
    study <- checked (bodyPatch atlas level degrees)
    let fixture = patchSpread study
        initial = spreadMesh fixture
        owners = refinedPanels (spreadRefined fixture)
    putStrLn ("Solving " ++ stem ++ " (" ++ show (length (triangles initial)) ++ " triangles)")
    hFlush stdout
    initialSheet <- checked (spreadSurface fixture initial)
    writeFold (output </> stem ++ "-initial.fold") initialSheet
    contactModel <- checked (Contact.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) owners initial)
    start <- getCPUTime
    (result, diagnostics) <- checked (diagnosePinnedContact (Settings 40 1e-5) (spreadPins fixture) (spreadHinges fixture) contactModel initial)
    mesh <- checked (finalMesh result)
    _ <- evaluate (maxLengthError mesh + if converged result then 1 else 0)
    stop <- getCPUTime
    accepted <- checked (patchAccepted study result mesh)
    contact <- checked (spreadCheck fixture mesh)
    angles <- checked (patchAngles study mesh)
    marks <- checked (patchLandmarks study mesh)
    (crease, panel) <- checked (bendingEnergy (spreadHinges fixture) mesh)
    sheet <- checked (spreadSurface fixture mesh)
    writeFold (output </> stem ++ ".fold") sheet
    let history = [object ["iteration" .= completedIterations point, "maxRelativeEdgeError" .= checkpointError point, "positions" .= map (xyz . position) (samples (checkpointMesh point))] | point <- checkpoints result]
    BL.writeFile (output </> stem ++ "-history.json") (encode history)
    let report =
          object
            [ "id" .= stem,
              "degrees" .= degrees,
              "level" .= level,
              "accepted" .= accepted,
              "converged" .= converged result,
              "vertices" .= length (samples mesh),
              "triangles" .= length (triangles mesh),
              "sourceFaces" .= map unFaceId (patchFaces study),
              "corePanels" .= map unFaceId (patchCore study),
              "sourceEdges" .= map unEdgeId (patchEdges study),
              "sourceVertices" .= map unVertexId (patchVertices study),
              "sourceOrders" .= [[unFaceId a, unFaceId b] | (a, b) <- spreadOrders fixture],
              "pins" .= [object ["vertex" .= i, "position" .= xyz p] | (i, p) <- IM.toList (spreadPins fixture)],
              "components" .= componentCount mesh,
              "materialArea" .= materialArea mesh,
              "areaRatio" .= (areaRatio mesh / materialArea mesh),
              "maxRelativeEdgeError" .= maxLengthError mesh,
              "holdError" .= spreadHeldError fixture mesh,
              "angles" .= [object ["sourceCrease" .= unEdgeId eid, "achieved" .= achieved, "preferred" .= preferred] | (eid, achieved, preferred) <- angles],
              "landmarks" .= [object ["name" .= name, "initial" .= xyz p, "final" .= xyz q, "movement" .= norm (q ^-^ p)] | (name, p, q) <- marks],
              "bodyExtent" .= bodyExtent study mesh,
              "creaseEnergy" .= crease,
              "panelEnergy" .= panel,
              "contact" .= contact,
              "iterations" .= maximum (0 : map completedIterations (checkpoints result)),
              "equilibrium" .= fmap equilibrium (equilibriumCheck result),
              "blockedStages" .= [object ["iteration" .= blockedIteration b, "lengthWeight" .= blockedLengthWeight b] | b <- blockedStages diagnostics],
              "rejectedTrials" .= [object ["kind" .= show (rejectionKind r), "count" .= rejectionCount r] | r <- rejectionSummaries diagnostics],
              "solveCpuSeconds" .= (fromIntegral (stop - start) / 1e12 :: Double),
              "wholeCraneChecked" .= False,
              "continuousMotionChecked" .= False
            ]
    BL.writeFile (output </> stem ++ "-check.json") (encode report)
    views <- forM cameras $ \(key, basis) -> do
      let view = View (Just basis) 0
      TIO.writeFile (output </> stem ++ "-" ++ key ++ "-wire.svg") (wireSvg study mesh basis)
      case if accepted then Just (surfaceDiagram defaultTheme defaultBudget view sheet) else Nothing of
        Just (Right drawing) -> do
          TIO.writeFile (output </> stem ++ "-" ++ key ++ ".svg") (renderSvg page (withExtent basis drawing))
          pure (object ["view" .= key, "paper" .= True, "error" .= (Nothing :: Maybe Text)])
        Just (Left err) -> pure (object ["view" .= key, "paper" .= False, "error" .= Just (explain err)])
        Nothing -> pure (object ["view" .= key, "paper" .= False, "error" .= (Nothing :: Maybe Text)])
    glb <-
      if accepted
        then case renderSurfaceGlb defaultBudget VisiblePaper (Just "Free-boundary body specimen") sheet of
          Right bytes -> BS.writeFile (output </> stem ++ ".glb") bytes >> pure Nothing
          Left err -> pure (Just (explain err))
        else pure (Just "Endpoint is diagnostic; no accepted 3D preview")
    putStrLn (stem ++ ": accepted=" ++ show accepted ++ ", converged=" ++ show (converged result) ++ ", length=" ++ show (maxLengthError mesh) ++ ", CPU seconds=" ++ show (fromIntegral (stop - start) / 1e12 :: Double))
    hFlush stdout
    pure (stem, report, views, glb, mesh, accepted)
  comparison <- case [(a, b, okA && okB) | ("opening-5", _, _, _, a, okA) <- runs, ("opening-5-fine", _, _, _, b, okB) <- runs] of
    [(coarse, fine, accepted)] -> do
      let finePoints = M.fromList [((materialU p, materialV p), position p) | p <- samples fine]
      distances <- forM (samples coarse) $ \p -> case M.lookup (materialU p, materialV p) finePoints of
        Nothing -> die "refinement comparison lost an original material vertex"
        Just q -> pure (norm (q ^-^ position p))
      pure (object ["bothAccepted" .= accepted, "sharedVertices" .= length distances, "maxSharedVertexMovement" .= maximum (0 : distances), "wholeSurfaceDistanceMeasured" .= False])
    _ -> die "missing the two declared 5-degree refinement controls"
  let document = object ["runs" .= [report | (_, report, _, _, _, _) <- runs], "exports" .= [object ["id" .= stem, "views" .= views, "glbError" .= glb] | (stem, _, views, glb, _, _) <- runs], "refinementComparison" .= comparison, "iterationLimitPerStage" .= (40 :: Int), "lengthWeights" .= ([1e2, 1e4, 1e6, 1e8] :: [Double]), "lengthTolerance" .= (1e-5 :: Double), "pixelsPerSheetUnit" .= (600 :: Int)]
  BL.writeFile (output </> "checks.json") (encode document)
  BL.writeFile (output </> "models.json") (encode [object ["title" .= stem, "path" .= (stem ++ ".glb")] | (stem, _, _, Nothing, _, _) <- runs])
  viewer <- TIO.readFile "study/gltf/viewer.html"
  TIO.writeFile (output </> "index.html") (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer)
  template <- TIO.readFile "study/fold-material/body-patch.html"
  TIO.writeFile (destination </> "body-patch.html") (T.replace "/*PATCH_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn ("Wrote body-patch.html and measurements to " ++ destination)

bodyExtent :: BodyPatch -> MaterialMesh -> Value
bodyExtent study mesh = object ["x" .= width x, "y" .= width y, "z" .= width z]
  where
    core = patchCore study
    fixture = patchSpread study
    selected = [v | ((a, b, c), owner) <- zip (triangles mesh) (refinedPanels (spreadRefined fixture)), owner `elem` core, v <- [a, b, c]]
    points = IM.fromList (zip [0 ..] (map position (samples mesh)))
    ps = [p | v <- selected, Just p <- [IM.lookup v points]]
    width f = case map f ps of [] -> 0; v : vs -> foldr max v vs - foldr min v vs
    x (V3 a _ _) = a
    y (V3 _ b _) = b
    z (V3 _ _ c) = c

cameras :: [(String, Basis)]
cameras = [("side", frontOn), ("top", topDown), ("underside", bottomUp)]

page :: Page
page = defaultPage {pageWidth = 560, pageHeight = 440, pageMargin = 28, pageBackground = Nothing}

withExtent :: Basis -> Diagram -> Diagram
withExtent basis drawing = diagramWithExtent (viewBox basis) (diagramShapes drawing)

viewBox :: Basis -> Box
viewBox basis = let V2 x y = project basis (V3 1 0.32 0) in Box (V2 (x - 0.42) (y - 0.32)) (V2 (x + 0.42) (y + 0.32))

wireSvg :: BodyPatch -> MaterialMesh -> Basis -> Text
wireSvg study mesh basis = renderSvg page {pageTitle = Just "Numerical wire diagnostic: includes hidden material"} (diagramWithExtent (viewBox basis) shapes)
  where
    ps = IM.fromList [(i, project basis (position p)) | (i, p) <- zip [0 ..] (samples mesh)]
    edge a b = [p | i <- [a, b], Just p <- [IM.lookup i ps]]
    shapes =
      [Polyline (solid (Colour "#b5b3a9") 0.55) (edge a b) | (a, b) <- meshEdges mesh]
        ++ [Polyline (solid (Colour "#a04c30") 1) (edge a b) | h <- spreadHinges (patchSpread study), let (a, b, _, _) = hingeVertices h, SurfaceCrease _ <- [hingeRole h]]
        ++ [Offset (labelOffset name) (Label (Colour "#274c57") 11 p name) | (name, i) <- patchMarks study, Just p <- [IM.lookup i ps]]

writeFold :: FilePath -> Surface V2 -> IO ()
writeFold path sheet = BL.writeFile path (encode (FoldFile (Just 1.2) (Just "senbazuru body patch study") Nothing (Just "Isolated free-boundary body specimen") Nothing [] (materialFrame sheet) []))

equilibrium :: EquilibriumCheck -> Value
equilibrium check = let linear = equilibriumLinear check in object ["linearConverged" .= linearConverged linear, "linearResidual" .= linearResidual linear, "linearThreshold" .= linearThreshold linear, "fullMovement" .= equilibriumMovement check, "movementThreshold" .= (1e-7 :: Double)]

xyz :: V3 -> [Double]
xyz (V3 x y z) = [x, y, z]

-- FoldMaterial.areaRatio assumes a whole unit square and actually measures
-- current area. An extracted specimen needs its own material-area denominator.
materialArea :: MaterialMesh -> Double
materialArea mesh = sum [abs ((materialU b - materialU a) * (materialV c - materialV a) - (materialV b - materialV a) * (materialU c - materialU a)) / 2 | (a, b, c) <- resolvedTriangles mesh]

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure

-- Page-unit offsets keep nearly coincident attachment labels legible without
-- changing their material positions or the diagram scale.
labelOffset :: Text -> V2
labelOffset name = case name of
  "centre" -> V2 6 20
  "wing-a" -> V2 (-65) 24
  "wing-b" -> V2 10 (-30)
  "tail" -> V2 30 (-8)
  _ -> V2 (-65) (-8)
