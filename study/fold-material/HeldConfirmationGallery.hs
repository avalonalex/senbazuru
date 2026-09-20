-- | Check numerical stopping sensitivity before refining the material again.
-- A saved endpoint changes only the starting positions: its unfolded sheet,
-- angular springs and held vertices remain the authored HeldEquilibrium case.
-- All four archives are validated before any output or solve, but only the
-- two 256-triangle endpoints receive another bounded solve.
--
-- The full repaired proposal must now be at most 1e-8 sheet units (formerly
-- 1e-7). Paper acceptance, contact and inner quadratic settings do not change.
-- A smaller last proposal is evidence about this local solver, not a bound
-- on all remaining motion, a global minimum or a continuously checked route.
module HeldConfirmationGallery (writeHeldConfirmation, Endpoint (..), compareEndpoints, writeEndpoint) where

import BendLocations
import ClosedCrease
import ContactQuadratic (ContactMethod (..))
import Control.Exception (evaluate)
import Control.Monad (forM, unless, when)
import CoupledCrease
import CreaseInequality
import CreaseInequalityGallery (resultReport)
import CreasePairContact
import Data.Aeson (Value, eitherDecode, encode, object, withObject, (.:), (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.Types (parseEither)
import Data.ByteString.Lazy qualified as BL
import Data.List (isPrefixOf)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldRelaxation
import HeldCosts
import HeldCostsGallery (differenceMap, heldChangeJson)
import HeldEquilibrium
import HeldEquilibriumGallery (HeldState (..), change, measureHeldState, writeMeasuredHeldState)
import IllustrationComparison (materialDifferences)
import MatchedEnergy
import MatchedEnergyGallery (groupReport)
import OuterContinuation (agreeMeasurements)
import PrescribedBend
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types (FoldFile (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import System.CPUTime (getCPUTime)
import System.Directory (canonicalizePath, createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (splitDirectories, (</>))
import System.IO (hFlush, stdout)

-- A measured endpoint keeps its geometry and convergence evidence together.
-- The caller records which stopping policy an archived endpoint satisfied.
data Endpoint = Endpoint
  { endpointKey :: String,
    endpointMesh :: MaterialMesh,
    endpointState :: HeldState,
    endpointPassed :: Bool
  }

data Input = Input
  { inputKey :: String,
    inputBudget :: HeldBudget,
    inputFixture :: CoupledFixture,
    inputRecord :: Value,
    inputBytes :: BL.ByteString,
    inputEndpoint :: Endpoint
  }

movementStop :: Double
movementStop = 1e-8

finalWeight :: Double
finalWeight = 1e10

writeHeldConfirmation :: FilePath -> FilePath -> IO ()
writeHeldConfirmation source destination = do
  let output = destination </> "held-confirmation"
  sourcePath <- splitDirectories <$> canonicalizePath source
  outputPath <- splitDirectories <$> canonicalizePath output
  when (sourcePath `isPrefixOf` outputPath || outputPath `isPrefixOf` sourcePath) (die "held-confirmation output and source directories must not overlap")
  bytes <- BL.readFile (source </> "checks.json")
  document <- either die pure (eitherDecode bytes)
  inputs <- forM heldCases $ \(key, layout, budget) -> do
    c <- checked (heldCase layout budget)
    record <- checked (heldRecord (T.pack key) layout c document)
    single <- BL.readFile (source </> key <> "-checks.json") >>= either die pure . eitherDecode
    checked (agreeMeasurements record single)
    raw <- BL.readFile (source </> key <> "-after.fold")
    file <- either die pure (eitherDecode raw)
    let fixture = heldFixture c
    mesh <- checked (savedBendMesh fixture (keyFrame file))
    measured <- measureHeldState fixture mesh
    original <- field "states" record >>= field "after"
    checked (agreeMeasurements original (heldStateReport measured))
    unless (heldStateValid measured) (die "saved held-panel endpoint failed fresh paper checks")
    pure (Input key budget fixture record raw (Endpoint (key <> "-source") mesh measured True))
  createDirectoryIfMissing True output
  BL.writeFile (output </> "source-checks.json") bytes
  sourceModels <- forM inputs $ \i -> do
    let e = inputEndpoint i
    (_, model, _, _, _) <- writeEndpoint output (inputFixture i) "Original saved endpoint" e
    BL.writeFile (output </> endpointKey e <> ".fold") (inputBytes i)
    pure model
  runs <- mapM (continueRun output) [i | i <- inputs, inputBudget i == Triangles256]
  let endpoints = map inputEndpoint inputs ++ [e | (_, _, Just e) <- runs]
      findEndpoint key = case [e | e <- endpoints, endpointKey e == key] of [e] -> pure (Just e); [] -> pure Nothing; _ -> die "duplicate confirmation endpoint"
      pairs =
        [(a <> "-source", b <> "-source", "Original mesh comparison") | (a, b) <- heldPairs]
          ++ [(a <> "-source", b <> "-after", "Coarser source unchanged; finer endpoint continued") | (a, b) <- take 2 heldPairs]
          ++ [("uniform-256-after", "whole-256-after", "Both finer endpoints continued")]
  comparisons <- forM pairs $ \(a, b, label) -> do
    ea <- findEndpoint a
    eb <- findEndpoint b
    metrics <- case (ea, eb) of (Just x, Just y) -> Just <$> compareEndpoints x y; _ -> pure Nothing
    pure (object ["from" .= a, "to" .= b, "label" .= (label :: Text), "eligible" .= (maybe False endpointPassed ea && maybe False endpointPassed eb), "metrics" .= metrics])
  -- Both maps use one signed scale. The fixed bins were declared in #306,
  -- rather than selected from the new answer. No source springs are rebased.
  costs <- forM [(i, e, upper, panel) | i <- inputs, (_, _, Just e) <- runs, endpointKey e == inputKey i <> "-after", (upper, panel) <- [(False, "lower" :: Text), (True, "upper")]] $ \(i, e, upper, panel) -> do
    let fixture = inputFixture i
        passive = filter (\h -> measuredUpper (locatedMeasure h) == upper && hingeRole (measuredHinge (locatedMeasure h)) == PanelBend)
        locate mesh = passive <$> checked (locateBends (coupledReference fixture) {closedMesh = mesh})
    before <- locate (endpointMesh (inputEndpoint i))
    after <- locate (endpointMesh e)
    changes <- checked (compareBends before after)
    pure (inputKey i, panel, changes)
  let top = maximum (1e-12 : [abs (edgeDelta c) | (_, _, cs) <- costs, c <- cs])
  costReports <- forM costs $ \(key, panel, cs) -> do
    TIO.writeFile (output </> key <> "-" <> T.unpack panel <> "-costs.svg") (differenceMap top cs)
    pure
      ( object
          [ "id" .= key,
            "panel" .= panel,
            "totals" .= groupReport "all" cs,
            "regions" .= [groupReport (T.pack (show r)) [c | c <- cs, heldRegion (locatedDistance (changeLocation c)) == r] | r <- [minBound .. maxBound]],
            "edges" .= map heldChangeJson cs
          ]
      )
  let report =
        object
          [ "gallery" .= ("held-confirmation" :: Text),
            "sourceMovementTolerance" .= (1e-7 :: Double),
            "movementTolerance" .= movementStop,
            "sourceEndpoints" .= [object ["id" .= endpointKey e, "state" .= heldStateReport (endpointState e)] | e <- map inputEndpoint inputs],
            "runs" .= [r | (r, _, _) <- runs],
            "comparisons" .= comparisons,
            "costs" .= costReports,
            "edgeDeltaScale" .= top
          ]
  BL.writeFile (output </> "checks.json") (encode report)
  BL.writeFile (output </> "models.json") (encode (sourceModels ++ concat [ms | (_, ms, _) <- runs]))
  viewer <- TIO.readFile "study/gltf/viewer.html"
  let compact = "header{padding:16px}header small,header h1,header p{display:none}#view{height:450px;min-height:450px}footer{padding:12px 16px}</style>"
  TIO.writeFile (output </> "index.html") (T.replace "</style>" compact (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer))
  template <- TIO.readFile "study/fold-material/held-confirmation.html"
  TIO.writeFile (destination </> "held-confirmation.html") (T.replace "/*HELD_CONFIRMATION*/null" (TE.decodeUtf8 (BL.toStrict (encode report))) template)
  putStrLn "Wrote held-confirmation.html: two bounded continuations; original archives unchanged."

continueRun :: FilePath -> Input -> IO (Value, [Value], Maybe Endpoint)
continueRun output i = do
  let key = inputKey i
      fixture = inputFixture i
      source = inputEndpoint i
      restart = fixture {coupledSeed = endpointMesh source}
      attempt = solveCoupledUntil movementStop ProgressiveContactExchange [finalWeight] EnforcePairOrder equilibriumSettings restart
  putStrLn ("Confirming " <> key <> " at movement stop 1e-8, at most 40 additional iterations")
  hFlush stdout
  start <- getCPUTime
  _ <- evaluate (case attempt of Left _ -> 0; Right r -> maxLengthError (inequalityMesh r) + if inequalityConverged r then 1 else 0)
  finish <- getCPUTime
  let result = either (const Nothing) Just attempt
      refusal = either (Just . explain) (const Nothing) attempt
  states <- forM (maybe [] (\r -> [("repair", "Numerical restart repair", repairedMesh (inequalityInitial r)), ("after", "Continued endpoint", inequalityMesh r)]) result) $ \(stage, label, mesh) -> do
    measured <- measureHeldState fixture mesh
    let e = Endpoint (key <> "-" <> stage) mesh measured (heldStateValid measured && maybe False inequalityConverged result)
    (_, model, _, _, _) <- writeEndpoint output fixture label e
    pure (stage, e, model)
  let endpoint = case [e | (stage, e, _) <- states, stage == "after"] of [e] -> Just e; _ -> Nothing
  movement <- traverse (compareEndpoints source) endpoint
  repairMovement <- checked (traverse (\r -> maximum . (0 :) . map norm <$> materialDifferences (endpointMesh source) (repairedMesh (inequalityInitial r))) result)
  let report =
        object
          [ "id" .= key,
            "source" .= inputRecord i,
            "lengthWeights" .= [finalWeight],
            "iterationLimitPerStage" .= iterationLimit equilibriumSettings,
            "lengthTolerance" .= lengthTolerance equilibriumSettings,
            "movementTolerance" .= movementStop,
            "contactMethod" .= show ProgressiveContactExchange,
            "contactEnabled" .= True,
            "solve" .= fmap resultReport result,
            "refusal" .= refusal,
            "passed" .= maybe False endpointPassed endpoint,
            "solveCpuSeconds" .= (fromIntegral (finish - start) / 1e12 :: Double),
            "changes" .= movement,
            "maxRestartRepairMovement" .= repairMovement,
            "states" .= object (("source" .= heldStateReport (endpointState source)) : [Key.fromString stage .= heldStateReport (endpointState e) | (stage, e, _) <- states]),
            "stages" .= ("source" : [stage | (stage, _, _) <- states]),
            "continuousMotionChecked" .= False
          ]
  BL.writeFile (output </> key <> "-checks.json") (encode report)
  putStrLn (key <> ": passed " <> show (maybe False endpointPassed endpoint) <> maybe "" (\reason -> "; " <> T.unpack reason) refusal)
  hFlush stdout
  pure (report, [m | (_, _, m) <- states], endpoint)

compareEndpoints :: Endpoint -> Endpoint -> IO Value
compareEndpoints a b = do
  ds <- checked (materialDifferences (endpointMesh a) (endpointMesh b))
  let x = heldStateCost (endpointState a)
      y = heldStateCost (endpointState b)
      displacement = maximum (0 : map norm ds)
      opening = fromRational . pairMaximum . heldStateAudit . endpointState
      total p = probeLowerEnergy p + probeUpperEnergy p + probeControlEnergy p + probeCreaseEnergy p + finalWeight * probeLengthSquares p / 2
  pure
    ( object
        [ "maxMaterialDisplacement" .= displacement,
          "shapeWithinTarget" .= (displacement < 0.001),
          "opening" .= change 1e-7 (opening a) (opening b),
          "lowerPassive" .= change 1e-12 (probeLowerEnergy x) (probeLowerEnergy y),
          "upperPassive" .= change 1e-12 (probeUpperEnergy x) (probeUpperEnergy y),
          "imposed" .= change 1e-12 (probeControlEnergy x) (probeControlEnergy y),
          "crease" .= change 1e-12 (probeCreaseEnergy x) (probeCreaseEnergy y),
          "length" .= change 1e-12 (finalWeight * probeLengthSquares x / 2) (finalWeight * probeLengthSquares y / 2),
          "total" .= change 1e-12 (total x) (total y)
        ]
    )

writeEndpoint :: FilePath -> CoupledFixture -> Text -> Endpoint -> IO (Value, Value, Bool, ProbeMeasure, Double)
writeEndpoint output fixture label e = writeMeasuredHeldState output fixture (endpointKey e) label (endpointMesh e) (endpointState e)

field :: Text -> Value -> IO Value
field key = either die pure . parseEither (withObject "saved field" (.: Key.fromText key))

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
