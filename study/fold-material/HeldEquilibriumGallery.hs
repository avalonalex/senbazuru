-- | Four opt-in solves, with convergence and valid paper reported separately.
-- Solver iterates are numerical corrections, not a checked folding route.
-- Every saved state gets the existing whole-sheet contact check and exact
-- two-panel order audit. Comparisons intersect material triangles, so a bend
-- at a vertex present in only one grid cannot disappear from the measurement.
module HeldEquilibriumGallery (writeHeldEquilibrium, HeldState (..), measureHeldState, writeMeasuredHeldState) where

import BendLocations (locateBends)
import BendLocationsGallery (rowJson)
import BendRefinement (gridColumns)
import ClosedCrease
import ContactQuadratic (ContactMethod (..))
import Control.Exception (evaluate)
import Control.Monad (forM)
import CoupledCrease
import CoupledCreaseGallery (measure)
import CreaseInequality
import CreaseInequalityGallery (resultReport)
import CreasePairContact
import Data.Aeson (Value, encode, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldMaterial (componentCount)
import FoldRelaxation
import HeldBend
import HeldEquilibrium
import IllustrationComparison (materialDifferences)
import PrescribedBend
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import System.CPUTime (getCPUTime)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)
import UnequalCreaseGallery (gapSvg, mapSvg, profileSvg, sampleLocations, sampleReport)

data Run = Run
  { runKey :: String,
    runLayout :: HeldLayout,
    runBudget :: HeldBudget,
    runPassed :: Bool,
    runFinal :: Maybe (MaterialMesh, ProbeMeasure, Double),
    runReport :: Value,
    runModels :: [Value]
  }

writeHeldEquilibrium :: FilePath -> IO ()
writeHeldEquilibrium destination = do
  let output = destination </> "held-equilibrium"
  createDirectoryIfMissing True output
  runs <- mapM (solveRun output) heldCases
  comparisons <- forM [(a, b) | a <- runs, b <- runs, (runLayout a == runLayout b && runBudget a == Triangles128 && runBudget b == Triangles256) || (runBudget a == runBudget b && runLayout a == UniformLayout && runLayout b == WholeBendLayout)] $ \(a, b) -> do
    metrics <- case (runFinal a, runFinal b) of
      (Just (ma, ea, ga), Just (mb, eb, gb)) -> do
        ds <- checked (materialDifferences ma mb)
        let displacement = maximum (0 : map norm ds)
        pure $
          Just $
            object
              [ "maxMaterialDisplacement" .= displacement,
                "shapeWithinTarget" .= (displacement < 0.001),
                "opening" .= change 1e-7 ga gb,
                "lowerPassive" .= change 1e-12 (probeLowerEnergy ea) (probeLowerEnergy eb),
                "upperPassive" .= change 1e-12 (probeUpperEnergy ea) (probeUpperEnergy eb),
                "imposed" .= change 1e-12 (probeControlEnergy ea) (probeControlEnergy eb)
              ]
      _ -> pure Nothing
    pure (object ["from" .= runKey a, "to" .= runKey b, "eligible" .= (runPassed a && runPassed b), "metrics" .= metrics])
  let document = object ["gallery" .= ("held-equilibrium" :: Text), "runs" .= map runReport runs, "comparisons" .= comparisons]
  BL.writeFile (output </> "checks.json") (encode document)
  BL.writeFile (output </> "models.json") (encode (concatMap runModels runs))
  viewer <- TIO.readFile "study/gltf/viewer.html"
  let compact = "header{padding:16px}header small,header h1,header p{display:none}#view{height:450px;min-height:450px}footer{padding:12px 16px}</style>"
  TIO.writeFile (output </> "index.html") (T.replace "</style>" compact (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer))
  template <- TIO.readFile "study/fold-material/held-equilibrium.html"
  TIO.writeFile (destination </> "held-equilibrium.html") (T.replace "/*HELD_EQUILIBRIUM*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn "Wrote held-equilibrium.html and four bounded solves."

-- | A near-zero reference has no meaningful percentage. Preserve its absolute
-- change instead of turning two touching layers into a spurious relative fail.
change :: Double -> Double -> Double -> Value
change floorValue a b = object ["from" .= a, "to" .= b, "absolute" .= abs (b - a), "percent" .= percentage, "withinRelativeTarget" .= fmap (< 5) percentage]
  where
    percentage = if abs a <= floorValue then Nothing else Just (100 * abs (b - a) / abs a)

solveRun :: FilePath -> (String, HeldLayout, HeldBudget) -> IO Run
solveRun output (key, layout, budget) = do
  c <- checked (heldCase layout budget)
  let fixture = heldFixture c
      reference = coupledReference fixture
      attempt = solveCoupledMethod ProgressiveContactExchange equilibriumWeights EnforcePairOrder equilibriumSettings fixture
  -- Save the starting mesh before beginning expensive work, including refusals.
  (seedReport, seedModel, _, _, _) <- writeHeldState output fixture (key ++ "-before") "Original sampled guess" (coupledSeed fixture)
  putStrLn ("Solving " ++ key)
  hFlush stdout
  start <- getCPUTime
  _ <- evaluate (case attempt of Left _ -> 0; Right r -> maxLengthError (inequalityMesh r) + if inequalityConverged r then 1 else 0)
  finish <- getCPUTime
  let result = either (const Nothing) Just attempt
      refusal = either (Just . explain) (const Nothing) attempt
  states <- case result of
    Nothing -> pure []
    Just r -> forM [("repair", "Numerical starting repair", repairedMesh (inequalityInitial r)), ("after", "Solver endpoint", inequalityMesh r)] $ \(stage, label, mesh) -> do
      (report, model, valid, cost, gap) <- writeHeldState output fixture (key ++ "-" ++ stage) label mesh
      pure (stage, report, model, valid, mesh, cost, gap)
  let accepted = maybe False inequalityConverged result && or [valid | (stage, _, _, valid, _, _, _) <- states, stage == "after"]
      endpoint = case [(mesh, cost, gap) | (stage, _, _, _, mesh, cost, gap) <- states, stage == "after"] of [x] -> Just x; _ -> Nothing
      report =
        object
          [ "id" .= key,
            "layout" .= show layout,
            "triangles" .= length (triangles (coupledSeed fixture)),
            "vertices" .= length (samples (coupledSeed fixture)),
            "components" .= componentCount (coupledSeed fixture),
            "columns" .= map (fromRational :: Rational -> Double) (gridColumns (heldGrid c)),
            "curveCurvature" .= curveCurvature (caseCurve c),
            "curveArcLength" .= curveArcLength (caseCurve c),
            "seedGripRoundoff" .= heldGripRoundoff c,
            "heldVertices" .= IM.keys (coupledPins fixture),
            "sharedCreaseVertices" .= closedRoot reference,
            "contactMethod" .= show ProgressiveContactExchange,
            "lengthWeights" .= equilibriumWeights,
            "iterationLimitPerStage" .= iterationLimit equilibriumSettings,
            "lengthTolerance" .= lengthTolerance equilibriumSettings,
            "contactEnabled" .= True,
            "passed" .= accepted,
            "refusal" .= refusal,
            "solve" .= fmap resultReport result,
            "solveCpuSeconds" .= (fromIntegral (finish - start) / 1e12 :: Double),
            "states" .= object (("before" .= seedReport) : [Key.fromString stage .= value | (stage, value, _, _, _, _, _) <- states]),
            "stages" .= ("before" : [stage | (stage, _, _, _, _, _, _) <- states]),
            "continuousMotionChecked" .= False
          ]
      models = seedModel : [model | (_, _, model, _, _, _, _) <- states]
  BL.writeFile (output </> key ++ "-checks.json") (encode report)
  putStrLn (key ++ ": accepted " ++ show accepted ++ "; CPU seconds " ++ show (fromIntegral (finish - start) / 1e12 :: Double) ++ maybe "" (\r -> "; " ++ T.unpack r) refusal)
  hFlush stdout
  pure (Run key layout budget accepted endpoint report models)

-- | Measurements can be checked against an archive before publishing any
-- files. Holding this value also avoids repeating the exact contact audit.
data HeldState = HeldState
  { heldStateReport :: Value,
    heldStateValid :: Bool,
    heldStateCost :: ProbeMeasure,
    heldStateAudit :: PairAudit,
    heldStateGaps :: [Maybe Rational]
  }

writeHeldState :: FilePath -> CoupledFixture -> String -> Text -> MaterialMesh -> IO (Value, Value, Bool, ProbeMeasure, Double)
writeHeldState output fixture name caption mesh = do
  measured <- measureHeldState fixture mesh
  writeMeasuredHeldState output fixture name caption mesh measured

measureHeldState :: CoupledFixture -> MaterialMesh -> IO HeldState
measureHeldState fixture mesh = do
  (measurement, valid) <- measure fixture mesh
  let reference = (coupledReference fixture) {closedMesh = mesh}
  cost <- checked (measureProbe reference)
  audit <- checked (auditPairContact (closedOwners reference) mesh)
  gaps <- checked (samplePairGaps (closedOwners reference) mesh sampleLocations)
  springs <- checked (locateBends reference)
  let report =
        object
          [ "measurement" .= measurement,
            "geometryPassed" .= valid,
            "lowerPassive" .= probeLowerEnergy cost,
            "upperPassive" .= probeUpperEnergy cost,
            "imposed" .= probeControlEnergy cost,
            "crease" .= probeCreaseEnergy cost,
            "lengthSquares" .= probeLengthSquares cost,
            "lengthEnergyAtFinalWeight" .= (1e10 * probeLengthSquares cost / 2),
            "gapSamples" .= sampleReport gaps,
            "springs" .= map rowJson springs,
            "edges" .= [object ["vertices" .= [a, b], "rest" .= edgeRest e, "actual" .= edgeActual e] | e <- probeEdges cost, let (a, b) = edgeIds e]
          ]
  pure (HeldState report valid cost audit gaps)

writeMeasuredHeldState :: FilePath -> CoupledFixture -> String -> Text -> MaterialMesh -> HeldState -> IO (Value, Value, Bool, ProbeMeasure, Double)
writeMeasuredHeldState output fixture name caption mesh measured = do
  sheet <- checked (coupledSurface fixture mesh)
  let report = heldStateReport measured
      valid = heldStateValid measured
      cost = heldStateCost measured
      audit = heldStateAudit measured
      gaps = heldStateGaps measured
      opening = fromRational (pairMaximum audit)
  TIO.writeFile (output </> name ++ "-profile.svg") (profileSvg mesh)
  TIO.writeFile (output </> name ++ "-gaps.svg") (gapSvg (max 1e-5 opening) audit)
  TIO.writeFile (output </> name ++ "-map.svg") (mapSvg gaps)
  BL.writeFile (output </> name ++ ".fold") (encode (FoldFile (Just 1.2) (Just "senbazuru held equilibrium") Nothing (Just caption) Nothing [] (materialFrame sheet) []))
  checked (renderSurfaceGlb defaultBudget CompletePaper (Just caption) sheet) >>= BS.writeFile (output </> name ++ ".glb")
  BL.writeFile (output </> name ++ ".json") (encode report)
  pure (report, object ["title" .= (T.pack name <> " · " <> caption), "path" .= (name ++ ".glb")], valid, cost, opening)

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
