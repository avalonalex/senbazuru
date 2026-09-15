-- | Compare a finite contact penalty with explicit nonnegative gaps on exactly
-- the same small sheet. Reuse the baseline's measurements and plots, retain
-- its failed controls, and publish the initial feasibility repair separately.
-- Only checked static endpoints pass; solver iterates are not folding steps.
module CreaseInequalityGallery (writeCreaseInequality, resultReport) where

import ClosedCrease
import ContactQuadratic
import Control.Exception (evaluate)
import Control.Monad (forM)
import CreaseCorrection
import CreaseCorrectionGallery (controls, creaseAngles, heldError, measure, penetrationSvg)
import CreaseInequality
import Data.Aeson (Value, encode, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldMaterial (componentCount)
import FoldRelaxation
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import System.CPUTime (getCPUTime)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)
import WingBending (finalMesh)

writeCreaseInequality :: FilePath -> IO ()
writeCreaseInequality destination = do
  let output = destination </> "crease-inequality"
  createDirectoryIfMissing True output
  runs <- forM [(n, entry) | n <- [1, 2], entry <- controls] $ \(n, (key, title, control)) -> do
    fixture <- checked (creaseCorrection n control)
    let stem = key ++ "-" ++ show n
        seed = correctionSeed fixture
    putStrLn ("Comparing " ++ stem)
    hFlush stdout
    baselineStart <- getCPUTime
    (baseline, _) <- checked (solveCorrection (Settings 40 1e-5) fixture)
    penalty <- checked (finalMesh baseline)
    _ <- evaluate (maxLengthError penalty + if converged baseline then 1 else 0)
    baselineEnd <- getCPUTime
    constraintStart <- getCPUTime
    let attempt = if control == WithoutContact then Nothing else Just (solveInequality (Settings 40 1e-5) fixture)
    _ <- evaluate (case attempt of Just (Right r) -> maxLengthError (inequalityMesh r) + if inequalityConverged r then 1 else 0; _ -> 0)
    constraintEnd <- getCPUTime
    let result = case attempt of Just (Right r) -> Just r; _ -> Nothing
        refusal = case attempt of Just (Left err) -> Just (explain err); _ -> Nothing
        candidates = [("before", "Original guess", seed), ("penalty", "Penalty endpoint", penalty)] ++ maybe [] (\r -> [("repair", "Feasible starting guess", repairedMesh (inequalityInitial r)), ("constrained", "Constrained endpoint", inequalityMesh r)]) result
    stages <- forM candidates $ \(stage, label, mesh) -> do
      (report, gaps) <- measure fixture mesh
      sheet <- checked (correctionSurface fixture mesh)
      let name = stem ++ "-" ++ stage
          caption = title <> " · " <> label <> " · " <> T.pack (show (32 * n)) <> " triangles"
      TIO.writeFile (output </> name ++ "-gap.svg") (penetrationSvg gaps)
      BL.writeFile (output </> name ++ ".fold") (encode (FoldFile (Just 1.2) (Just "senbazuru nonnegative crease contact") Nothing (Just caption) Nothing [] (materialFrame sheet) []))
      -- Complete paper, without layer offsets. The rounded GLB is inspection
      -- only; the exact fractions below refer to the original stored Doubles.
      bytes <- checked (renderSurfaceGlb defaultBudget CompletePaper (Just caption) sheet)
      BS.writeFile (output </> name ++ ".glb") bytes
      pure (stage, label, report, object ["title" .= caption, "path" .= (name ++ ".glb")])
    baselinePass <- passes fixture penalty (converged baseline) False
    newPass <- maybe (pure False) (\r -> passes fixture (inequalityMesh r) (inequalityConverged r) True) result
    let report =
          object
            [ "id" .= stem,
              "control" .= key,
              "title" .= title,
              "subdivision" .= n,
              "triangles" .= length (triangles seed),
              "vertices" .= length (samples seed),
              "components" .= componentCount seed,
              "sharedCreaseVertices" .= closedRoot (correctionReference fixture),
              "heldVertices" .= IM.keys (correctionPins fixture),
              "baselineConverged" .= converged baseline,
              "baselineWithinTolerances" .= baselinePass,
              "baselineIterations" .= maximum (0 : map completedIterations (checkpoints baseline)),
              "baselineCpuSeconds" .= seconds baselineStart baselineEnd,
              "constrainedCpuSeconds" .= (if control == WithoutContact then Nothing else Just (seconds constraintStart constraintEnd)),
              "constrainedPassed" .= newPass,
              "refusal" .= refusal,
              "constrained" .= fmap resultReport result,
              "measurements" .= object [Key.fromString stage .= r | (stage, _, r, _) <- stages],
              "stages" .= [object ["id" .= stage, "label" .= label] | (stage, label, _, _) <- stages],
              "continuousMotionChecked" .= False
            ]
    putStrLn (stem ++ ": constrained endpoint passed " ++ show newPass ++ maybe "" (\reason -> "; refused: " ++ T.unpack reason) refusal)
    hFlush stdout
    pure (report, [m | (_, _, _, m) <- stages])
  let document = object ["runs" .= map fst runs]
  BL.writeFile (output </> "checks.json") (encode document)
  BL.writeFile (output </> "models.json") (encode (concatMap snd runs))
  viewer <- TIO.readFile "study/gltf/viewer.html"
  let compact = "header{padding:16px}header small,header h1,header p{display:none}#view{height:450px;min-height:450px}footer{padding:12px 16px}</style>"
  TIO.writeFile (output </> "index.html") (T.replace "</style>" compact (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer))
  template <- TIO.readFile "study/fold-material/crease-inequality.html"
  TIO.writeFile (destination </> "crease-inequality.html") (T.replace "/*INEQUALITY_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn ("Wrote crease-inequality.html, complete-sheet FOLDs/GLBs and constrained-step diagnostics to " ++ destination)

-- Exact lower/upper order is an ADDITIONAL check, leaving every existing
-- material, authored-angle and whole-mesh contact tolerance unchanged.
passes :: CreaseCorrection -> MaterialMesh -> Bool -> Bool -> IO Bool
passes fixture mesh settled requireExact = do
  (angle, _) <- creaseAngles fixture mesh
  gaps <- checked (auditLowerGap fixture mesh)
  contact <- checked (checkTriangleContact (V3 0 0 1) [(FaceId 0, FaceId 1)] (closedOwners (correctionReference fixture)) mesh)
  pure (settled && maxLengthError mesh <= 1e-5 && heldError fixture mesh == 0 && angle <= 1e-5 && contactPassed contact && (not requireExact || minimumGap gaps >= 0))

resultReport :: InequalityResult -> Value
resultReport result =
  object
    [ "converged" .= inequalityConverged result,
      "iterations" .= length (inequalitySteps result),
      "initialLift" .= (fromRational (commonLift (inequalityInitial result)) :: Double),
      "initialLiftExact" .= show (commonLift (inequalityInitial result)),
      "initialRoundingLift" .= maxRoundingLift (inequalityInitial result),
      "steps" .= map stepReport (inequalitySteps result)
    ]

stepReport :: InequalityStep -> Value
stepReport step =
  let q = stepQuadratic step
   in object
        [ "iteration" .= stepIteration step,
          "lengthWeight" .= stepWeight step,
          "fullRepairedMovement" .= stepMovement step,
          "acceptedScale" .= stepScale step,
          "commonLift" .= stepLift step,
          "maxRoundingLift" .= stepRounding step,
          "energyBefore" .= stepEnergyBefore step,
          "energyAfter" .= stepEnergyAfter step,
          "minGapExact" .= show (stepMinGap step),
          "lengthError" .= stepLengthError step,
          "accepted" .= stepAccepted step,
          "stageSettled" .= stepSettled step,
          "quadratic" .= object ["converged" .= quadraticConverged q, "iterations" .= quadraticIterations q, "maxViolation" .= quadraticViolation q, "complementarity" .= quadraticComplementarity q, "forceBalance" .= quadraticBalance q, "activeConstraints" .= quadraticActive q]
        ]

seconds :: Integer -> Integer -> Double
seconds start finish = fromIntegral (finish - start) / 1e12

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
