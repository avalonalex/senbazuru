-- | Publish matched body-angle experiments, keeping diagnostic endpoints out
-- of the accepted 3D selector. Every solve is evaluated under both the old
-- strict-angle policy and the selected-preference policy; those two verdicts
-- describe one mesh, not two different physical solutions.
module CraneBodyGallery (writeCraneBody) where

import Control.Exception (evaluate)
import Control.Monad (forM, when)
import CraneBody
import CraneRoot
import CraneSpread
import CraneSpreadGallery (spreadSvg)
import Data.Aeson (encode, object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Maybe (isNothing)
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldMaterial (areaRatio, componentCount)
import FoldRelaxation
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import SparseSolve (LinearReport (..))
import System.CPUTime (getCPUTime)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)
import WingBending (finalMesh)

writeCraneBody :: FilePath -> IO ()
writeCraneBody destination = do
  let output = destination </> "crane-body"
      controls = [("fixed", "Fixed body reference", OriginalPreferences), ("original", "Free patch · original springs", OriginalPreferences), ("weaker", "Free patch · selected springs × 0.1", WeakerBody), ("open", "Free patch · selected preference 170°", OpenBody), ("crossed", "Incompatible upper grip", WeakerBody)]
  createDirectoryIfMissing True output
  source <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= checked)
  runs <- forM controls $ \(stem, title, control) -> do
    base <- checked (craneBody source 3 control)
    held <- if stem == "fixed" then checked (craneRoot source 3 FlatRoot) else pure (bodyRoot base)
    let study = base {bodyRoot = if stem == "crossed" then held {rootSpread = crossedGrip (rootSpread held)} else held}
        root = bodyRoot study
        fixture = rootSpread root
        limit = if stem == "crossed" then 2 else 40
    putStrLn ("Solving " ++ stem)
    hFlush stdout
    start <- getCPUTime
    result <- checked (solveSpread (Settings limit 1e-5) fixture)
    mesh <- checked (finalMesh result)
    _ <- evaluate (maxLengthError mesh + if converged result then 1 else 0)
    settled <- getCPUTime
    (strict, accepted) <- checked (bodyAccepted study result mesh)
    contact <- checked (spreadCheck fixture mesh)
    (selectedError, retainedError) <- checked (bodyAngleErrors study mesh)
    angles <- checked (bodyAngles study mesh)
    roots <- checked (rootAngles root mesh)
    (creaseEnergy, panelEnergy) <- checked (bendingEnergy (spreadHinges fixture) mesh)
    sheet <- checked (spreadSurface fixture mesh)
    let report =
          object
            [ "id" .= stem,
              "title" .= (title :: Text),
              "control" .= show control,
              "strictAccepted" .= strict,
              "selectedAccepted" .= accepted,
              "converged" .= converged result,
              "equilibrium" .= fmap equilibrium (equilibriumCheck result),
              "iterationLimitPerStage" .= limit,
              "iterations" .= maximum (0 : map completedIterations (checkpoints result)),
              "refinement" .= (3 :: Int),
              "vertices" .= length (samples mesh),
              "triangles" .= length (triangles mesh),
              "components" .= componentCount mesh,
              "heldVertices" .= IM.size (spreadPins fixture),
              "sourceOrders" .= length (spreadOrders fixture),
              "activeSourceOrders" .= length (spreadContactOrders fixture),
              "releasedPanels" .= (if stem == "fixed" then [] else map unFaceId (S.toAscList (rootNeighbours root))),
              "selectedCreases" .= map unEdgeId (S.toAscList (bodySelected study)),
              "angles" .= [object ["sourceEdge" .= unEdgeId (angleSource a), "selected" .= angleSelected a, "achievedRadians" .= angleAchieved a, "originalRadians" .= angleOriginal a, "preferredRadians" .= anglePreferred a] | a <- angles],
              "rootAnglesRadians" .= map snd roots,
              "maxSelectedOriginalErrorRadians" .= selectedError,
              "maxRetainedOriginalErrorRadians" .= retainedError,
              "maxRelativeEdgeError" .= maxLengthError mesh,
              "areaRatio" .= areaRatio mesh,
              "heldPositionError" .= spreadHeldError fixture mesh,
              "bodyMovement" .= rootBodyMovement root mesh,
              "creaseEnergy" .= creaseEnergy,
              "panelEnergy" .= panelEnergy,
              "contact" .= contact,
              "solveCpuSeconds" .= (fromIntegral (settled - start) / 1e12 :: Double),
              "continuousMotionChecked" .= False
            ]
        file = FoldFile (Just 1.2) (Just "senbazuru body crease preferences") Nothing (Just title) Nothing [] (materialFrame sheet) []
    BL.writeFile (output </> stem ++ ".fold") (encode file)
    BL.writeFile (output </> stem ++ "-check.json") (encode report)
    -- Publish measurements before attempting a renderer: export failures must
    -- not discard an expensive experiment or turn physical acceptance false.
    export <-
      if accepted
        then do
          let stable = renderSurfaceGlb defaultBudget VisiblePaper (Just title) sheet
          case stable of
            Right bytes -> do
              BS.writeFile (output </> stem ++ ".glb") bytes
              pure Nothing
            Left err -> do
              bytes <- checked (renderSurfaceGlb defaultBudget CompletePaper (Just title) sheet)
              BS.writeFile (output </> stem ++ "-complete.glb") bytes
              pure (Just (explain err))
        else pure Nothing
    when accepted $ case spreadSvg [sheet] of
      Right svg -> TIO.writeFile (output </> stem ++ ".svg") svg
      Left err -> putStrLn (T.unpack err)
    putStrLn (stem ++ ": strict " ++ show strict ++ ", selected " ++ show accepted ++ "; length " ++ show (maxLengthError mesh) ++ "; selected/retained angle " ++ show (selectedError, retainedError))
    hFlush stdout
    pure (stem, title, accepted, export, report)
  let document = object ["runs" .= [report | (_, _, _, _, report) <- runs], "exports" .= [object ["id" .= stem, "stableAvailable" .= (accepted && isNothing err), "error" .= err] | (stem, _, accepted, err, _) <- runs]]
  BL.writeFile (output </> "checks.json") (encode document)
  BL.writeFile (output </> "models.json") (encode [object ["title" .= title, "path" .= (stem ++ ".glb")] | (stem, title, True, Nothing, _) <- runs])
  viewer <- TIO.readFile "study/gltf/viewer.html"
  TIO.writeFile (output </> "index.html") (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer)
  template <- TIO.readFile "study/fold-material/crane-body.html"
  TIO.writeFile (destination </> "crane-body.html") (T.replace "/*BODY_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn ("Wrote crane-body.html and measurements to " ++ destination)
  where
    equilibrium check = let linear = equilibriumLinear check in object ["linearConverged" .= linearConverged linear, "linearResidual" .= linearResidual linear, "linearThreshold" .= linearThreshold linear, "fullMovement" .= equilibriumMovement check, "movementThreshold" .= (1e-7 :: Double)]

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
