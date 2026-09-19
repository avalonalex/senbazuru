-- | Two opt-in restarts, with the old endpoints kept alongside them. The
-- shared outer-strip writer gives both studies identical geometry checks,
-- spring records and projections. Historical convergence is never inferred
-- from a pretty endpoint: a new pass requires a new converged solve and all
-- the unchanged material/contact checks. See OuterContinuation for the
-- distinction between saved positions and the paper's rest geometry.
module OuterContinuationGallery (writeOuterContinuation) where

import ClosedCrease
import ContactQuadratic (ContactMethod (..))
import Control.Exception (evaluate)
import Control.Monad (forM, unless)
import CoupledCrease
import CoupledCreaseGallery (matching)
import CreaseInequality
import CreaseInequalityGallery (resultReport)
import CreasePairContact
import Data.Aeson (Value, eitherDecode, encode, object, withObject, (.:), (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.Types (parseEither)
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldRelaxation
import OuterContinuation
import OuterStripGallery (writeOuterState)
import PrescribedBend
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types (FoldFile (..))
import Senbazuru.Origami.Surface
import System.CPUTime (getCPUTime)
import System.Directory (canonicalizePath, createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)
import UnequalCrease

writeOuterContinuation :: FilePath -> FilePath -> IO ()
writeOuterContinuation source destination = do
  let output = destination </> "outer-continuation"
  sourcePath <- canonicalizePath source
  outputPath <- canonicalizePath output
  unless (sourcePath /= outputPath) (die "continuation output must differ from its source")
  bytes <- BL.readFile (source </> "checks.json")
  document <- either die pure (eitherDecode bytes)
  -- Load and validate both identities before either solver runs. Keep the
  -- bytes read here, so an archived source never gets regenerated or repaired.
  inputs <- forM [RestBand, OuterWithoutContact] $ \c -> do
    record <- checked (sourceRecord c document)
    fixture <- checked (continuationFixture c)
    foldBytes <- BL.readFile (source </> T.unpack (continuationId c) <> "-after.fold")
    file <- either die pure (eitherDecode foldBytes)
    restart <- checked (restartFixture fixture (keyFrame file))
    audit <- checked (auditPairContact (closedOwners (coupledReference fixture)) (coupledSeed restart))
    pure (c, record, fixture, restart, foldBytes, audit)
  createDirectoryIfMissing True output
  BL.writeFile (output </> "source-checks.json") bytes
  prepared <- forM inputs $ \(c, record, fixture, restart, foldBytes, audit) -> do
    let stem = T.unpack (continuationId c)
        caption = continuationId c <> " · Original endpoint"
        mesh = coupledSeed restart
        scale = maximum [1e-8, fromRational (abs (pairMinimum audit)), fromRational (abs (pairMaximum audit))]
    -- This first projection is regenerated later at a shared gap scale.
    (_, _, report, _) <- writeOuterState output (continuationChoice c) (continuationControl c) fixture scale (stem <> "-source") caption mesh audit
    old <- field "states" record >>= field "after"
    checked (agreeMeasurements old report)
    pure (c, record, fixture, restart, foldBytes)
  runs <- forM prepared $ \(c, record, fixture, restart, foldBytes) -> do
    let stem = T.unpack (continuationId c)
        mode = unequalContactMode (continuationControl c)
        attempt = solveCoupledMethod ProgressiveContactExchange [continuationWeight] mode continuationSettings restart
    putStrLn ("Continuing " <> stem)
    hFlush stdout
    start <- getCPUTime
    _ <- evaluate (case attempt of Left _ -> 0; Right r -> maxLengthError (inequalityMesh r) + if inequalityConverged r then 1 else 0)
    finish <- getCPUTime
    let result = either (const Nothing) Just attempt
        refusal = either (Just . explain) (const Nothing) attempt
        original = coupledSeed restart
        candidates = ("source", "Original endpoint", original) : maybe [] (\r -> [("repair", "Restart after feasibility check", repairedMesh (inequalityInitial r)), ("after", "Continued endpoint", inequalityMesh r)]) result
    audits <- mapM (\(_, _, mesh) -> checked (auditPairContact (closedOwners (coupledReference fixture)) mesh)) candidates
    let scale = maximum (1e-8 : [fromRational (max (abs (pairMinimum a)) (abs (pairMaximum a))) | a <- audits])
    stages <- forM (zip candidates audits) $ \((stage, label, mesh), audit) -> do
      (valid, _, state, model) <- writeOuterState output (continuationChoice c) (continuationControl c) fixture scale (stem <> "-" <> stage) (continuationId c <> " · " <> label) mesh audit
      energy <- energyReport fixture mesh
      pure (stage, label, valid, state, energy, model)
    -- Keep the original bytes, including metadata, even though all reported
    -- geometry was rechecked against the authored fixture above.
    BL.writeFile (output </> stem <> "-source.fold") foldBytes
    displacement <- checked (traverse (matching original . inequalityMesh) result)
    repairMovement <- checked (traverse (matching original . repairedMesh . inequalityInitial) result)
    changes <- checked (traverse (panelChanges original . inequalityMesh) result)
    let passed = c == RestBand && maybe False inequalityConverged result && any (\(stage, _, valid, _, _, _) -> stage == "after" && valid) stages
        report =
          object
            [ "id" .= continuationId c,
              "title" .= (if c == RestBand then "Rest-only · fractional band" else "Outer-only · original band · contact off" :: Text),
              "contactEnabled" .= (c == RestBand),
              "source" .= record,
              "lengthWeights" .= [continuationWeight],
              "iterationLimitPerStage" .= iterationLimit continuationSettings,
              "lengthTolerance" .= lengthTolerance continuationSettings,
              "movementTolerance" .= (1e-7 :: Double),
              "contactMethod" .= show ProgressiveContactExchange,
              "solve" .= fmap resultReport result,
              "refusal" .= refusal,
              "passed" .= passed,
              "maxPositionChange" .= displacement,
              "maxRestartRepairMovement" .= repairMovement,
              "panelChanges" .= changes,
              "solveCpuSeconds" .= (fromIntegral (finish - start) / 1e12 :: Double),
              "states" .= object [Key.fromString stage .= state | (stage, _, _, state, _, _) <- stages],
              "energies" .= object [Key.fromString stage .= energy | (stage, _, _, _, energy, _) <- stages],
              "stages" .= [object ["id" .= stage, "label" .= label] | (stage, label, _, _, _, _) <- stages],
              "continuousMotionChecked" .= False
            ]
    BL.writeFile (output </> stem <> "-checks.json") (encode report)
    putStrLn (stem <> ": endpoint passed " <> show passed <> maybe "" (\reason -> "; " <> T.unpack reason) refusal)
    pure (report, [model | (_, _, _, _, _, model) <- stages])
  let report = object ["gallery" .= ("outer-continuation" :: Text), "runs" .= map fst runs]
  BL.writeFile (output </> "checks.json") (encode report)
  BL.writeFile (output </> "models.json") (encode (concatMap snd runs))
  viewer <- TIO.readFile "study/gltf/viewer.html"
  let compact = "header{padding:16px}header small,header h1,header p{display:none}#view{height:450px;min-height:450px}footer{padding:12px 16px}</style>"
  TIO.writeFile (output </> "index.html") (T.replace "</style>" compact (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer))
  template <- TIO.readFile "study/fold-material/outer-continuation.html"
  TIO.writeFile (destination </> "outer-continuation.html") (T.replace "/*OUTER_CONTINUATION*/null" (TE.decodeUtf8 (BL.toStrict (encode report))) template)
  putStrLn "Wrote outer-continuation.html; the original outer-strip study is unchanged."

energyReport :: CoupledFixture -> MaterialMesh -> IO Value
energyReport fixture mesh = do
  p <- checked (measureProbe (coupledReference fixture) {closedMesh = mesh})
  let lengths = continuationWeight * probeLengthSquares p / 2
      total = lengths + probeLowerEnergy p + probeUpperEnergy p + probeControlEnergy p + probeCreaseEnergy p
  pure (object ["length" .= lengths, "lowerPassive" .= probeLowerEnergy p, "upperPassive" .= probeUpperEnergy p, "imposed" .= probeControlEnergy p, "crease" .= probeCreaseEnergy p, "total" .= total, "lineSearchObjective" .= (2 * total)])

field :: Text -> Value -> IO Value
field key = either die pure . parseEither (withObject "source state" (.: Key.fromText key))

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
