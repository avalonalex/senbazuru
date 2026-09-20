-- | Two opt-in 512-triangle solves, compared with saved confirmed endpoints.
-- Increasing columns changes the discretization of the same paper, not its
-- rest shape or boundary grips. The first solve keeps the historical six-stage
-- schedule; only a converged, paper-valid result gets the tighter confirmation.
-- Failures remain visible, never relabelled as accepted mesh refinement.
--
-- The shared endpoint exporter measures the complete sheet. Comparisons cover
-- all material-triangle overlaps, including vertices absent from the other
-- grid. Cost bins are the previously declared midpoint accounting, not a
-- physical energy density. Numerical iterates do not certify a folding route.
module HeldRefinementGallery (writeHeldRefinement) where

import BendLocations
import BendRefinement (gridColumns)
import ClosedCrease
import ContactQuadratic (ContactMethod (..))
import Control.Exception (evaluate)
import Control.Monad (forM, unless, when)
import CoupledCrease
import CreaseInequality
import CreaseInequalityGallery (resultReport)
import Data.Aeson (Value, eitherDecode, encode, object, withObject, (.:), (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.Types (parseEither)
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.List (isPrefixOf)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldRelaxation
import HeldConfirmationGallery (Endpoint (..), compareEndpoints, writeEndpoint)
import HeldCosts (heldRegion)
import HeldCostsGallery (differenceMap, heldChangeJson)
import HeldEquilibrium
import HeldEquilibriumGallery (HeldState (..), measureHeldState)
import HeldRefinement
import MatchedEnergy
import MatchedEnergyGallery (groupReport)
import OuterContinuation (agreeMeasurements)
import PrescribedBend (HingeMeasure (..))
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types (FoldFile (..))
import Senbazuru.Origami.Surface
import System.CPUTime (getCPUTime)
import System.Directory (canonicalizePath, createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (splitDirectories, (</>))
import System.IO (hFlush, stdout)

data Source = Source
  { sourceKey :: String,
    sourceLayout :: HeldLayout,
    sourceRecord :: Value,
    sourceBytes :: BL.ByteString,
    sourceFixture :: CoupledFixture,
    sourceEndpoint :: Endpoint
  }

writeHeldRefinement :: FilePath -> FilePath -> IO ()
writeHeldRefinement source destination = do
  let output = destination </> "held-refinement"
  sourcePath <- splitDirectories <$> canonicalizePath source
  outputPath <- splitDirectories <$> canonicalizePath output
  when (sourcePath `isPrefixOf` outputPath || outputPath `isPrefixOf` sourcePath) (die "held-refinement source and output directories must not overlap")
  bytes <- BL.readFile (source </> "checks.json")
  document <- either die pure (eitherDecode bytes)
  inputs <- forM refinementCases $ \(key, layout) -> do
    c <- checked (heldCase layout Triangles256)
    let oldKey = key <> "-256"
        fixture = heldFixture c
    record <- checked (confirmedRecord (T.pack oldKey) layout c document)
    single <- BL.readFile (source </> oldKey <> "-checks.json") >>= either die pure . eitherDecode
    checked (agreeMeasurements record single)
    raw <- BL.readFile (source </> oldKey <> "-after.fold")
    file <- either die pure (eitherDecode raw)
    mesh <- checked (savedBendMesh fixture (keyFrame file))
    measured <- measureHeldState fixture mesh
    original <- field "states" record >>= field "after"
    checked (agreeMeasurements original (heldStateReport measured))
    unless (heldStateValid measured) (die "confirmed source failed fresh paper checks")
    pure (Source key layout record raw fixture (Endpoint oldKey mesh measured True))
  createDirectoryIfMissing True output
  BL.writeFile (output </> "source-checks.json") bytes
  sourceModels <- forM inputs $ \i -> do
    let e = sourceEndpoint i
    (_, model, _, _, _) <- writeEndpoint output (sourceFixture i) "Saved confirmed 256-triangle endpoint" e
    BL.writeFile (output </> endpointKey e <> ".fold") (sourceBytes i)
    pure model
  runs <- mapM (solveFine output) inputs
  let get key = case [(i, e) | (i, _, _, Just e) <- runs, sourceKey i == key] of [x] -> Just x; _ -> Nothing
      fine key = fmap snd (get key)
      coarse key = case [sourceEndpoint i | i <- inputs, sourceKey i == key] of [e] -> Just e; _ -> Nothing
      pairs =
        [(key <> "-refinement", coarse key, fine key) | (key, _) <- refinementCases]
          ++ [("placement-256", coarse "uniform", coarse "whole"), ("placement-512", fine "uniform", fine "whole")]
  comparisons <- forM pairs $ \(name, a, b) -> do
    metrics <- case (a, b) of (Just x, Just y) -> Just <$> compareEndpoints x y; _ -> pure Nothing
    pure (object ["id" .= name, "from" .= fmap endpointKey a, "to" .= fmap endpointKey b, "eligible" .= (maybe False endpointPassed a && maybe False endpointPassed b), "metrics" .= metrics])
  costs <- forM [(i, e, upper, panel) | (i, _, _, Just e) <- runs, (upper, panel) <- [(False, "lower" :: Text), (True, "upper")]] $ \(i, e, upper, panel) -> do
    c <- checked (heldCase (sourceLayout i) Triangles512)
    let passive = filter (\h -> measuredUpper (locatedMeasure h) == upper && hingeRole (measuredHinge (locatedMeasure h)) == PanelBend)
        locate f m = passive <$> checked (locateBends (coupledReference f) {closedMesh = m})
    before <- locate (sourceFixture i) (endpointMesh (sourceEndpoint i))
    after <- locate (heldFixture c) (endpointMesh e)
    cs <- checked (compareBends before after)
    pure (sourceKey i, panel, cs)
  let top = maximum (1e-12 : [abs (edgeDelta c) | (_, _, cs) <- costs, c <- cs])
  costReports <- forM costs $ \(key, panel, cs) -> do
    TIO.writeFile (output </> key <> "-" <> T.unpack panel <> "-costs.svg") (differenceMap top cs)
    pure
      ( object
          [ "id" .= key,
            "panel" .= panel,
            "totals" .= groupReport "all" cs,
            "regions" .= [groupReport (T.pack (show r)) [c | c <- cs, heldRegion (locatedDistance (changeLocation c)) == r] | r <- [minBound .. maxBound]],
            "directions" .= [groupReport d [c | c <- cs, edgeDirection (changeLocation c) == d] | d <- ["Transverse", "Lengthwise", "Diagonal"]],
            "edges" .= map heldChangeJson cs
          ]
      )
  let report =
        object
          [ "gallery" .= ("held-refinement" :: Text),
            "sourceMovementTolerance" .= refinementStop,
            "sources" .= [object ["id" .= endpointKey (sourceEndpoint i), "state" .= heldStateReport (endpointState (sourceEndpoint i)), "history" .= sourceRecord i] | i <- inputs],
            "runs" .= [r | (_, r, _, _) <- runs],
            "comparisons" .= comparisons,
            "costs" .= costReports,
            "edgeDeltaScale" .= top
          ]
  BL.writeFile (output </> "checks.json") (encode report)
  BL.writeFile (output </> "models.json") (encode (sourceModels ++ concat [ms | (_, _, ms, _) <- runs]))
  viewer <- TIO.readFile "study/gltf/viewer.html"
  let compact = "header{padding:16px}header small,header h1,header p{display:none}#view{height:450px;min-height:450px}footer{padding:12px 16px}</style>"
  TIO.writeFile (output </> "index.html") (T.replace "</style>" compact (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer))
  template <- TIO.readFile "study/fold-material/held-refinement.html"
  TIO.writeFile (destination </> "held-refinement.html") (T.replace "/*HELD_REFINEMENT*/null" (TE.decodeUtf8 (BL.toStrict (encode report))) template)
  putStrLn "Wrote held-refinement.html: original confirmed meshes are unchanged."

solveFine :: FilePath -> Source -> IO (Source, Value, [Value], Maybe Endpoint)
solveFine output i = do
  c <- checked (heldCase (sourceLayout i) Triangles512)
  let key = sourceKey i <> "-512"
      fixture = heldFixture c
      state stage label valid mesh = do
        measured <- measureHeldState fixture mesh
        let e = Endpoint (key <> "-" <> stage) mesh measured (valid && heldStateValid measured)
        (_, model, _, _, _) <- writeEndpoint output fixture label e
        pure (stage, e, model)
  before <- state "before" "Original sampled 512-triangle guess" False (coupledSeed fixture)
  (attempt, seconds) <- timed ("Solving " <> key <> " with the original six-stage schedule") (solveCoupledMethod ProgressiveContactExchange equilibriumWeights EnforcePairOrder equilibriumSettings fixture)
  let result = either (const Nothing) Just attempt
  primary <- case result of
    Nothing -> pure []
    Just r -> sequence [state "repair" "Numerical starting repair" False (repairedMesh (inequalityInitial r)), state "solved" "Six-stage endpoint" (inequalityConverged r) (inequalityMesh r)]
  let solved = case [e | (stage, e, _) <- primary, stage == "solved"] of [e] -> Just e; _ -> Nothing
  (confirmation, confirmationSeconds, skipped) <- case solved of
    Just e | endpointPassed e -> do
      (r, t) <- timed ("Confirming " <> key <> " at 1e-8") (solveCoupledUntil refinementStop ProgressiveContactExchange [refinementWeight] EnforcePairOrder equilibriumSettings fixture {coupledSeed = endpointMesh e})
      pure (Just r, Just t, Nothing)
    _ -> pure (Nothing, Nothing, Just ("The six-stage solve did not both converge and pass paper checks." :: Text))
  let confirmed = confirmation >>= either (const Nothing) Just
  finalStates <- case confirmed of
    Nothing -> pure []
    Just r -> sequence [state "confirmation-repair" "Confirmation starting repair" False (repairedMesh (inequalityInitial r)), state "after" "Confirmed endpoint" (inequalityConverged r) (inequalityMesh r)]
  let states = before : primary ++ finalStates
      final = case [e | (stage, e, _) <- finalStates, stage == "after"] of [e] -> Just e; _ -> solved
      accepted = maybe False inequalityConverged confirmed && maybe False endpointPassed final
      -- A good primary endpoint whose confirmation refused is still useful to
      -- inspect, but must not enter an accepted 256-to-512 comparison.
      endpoint = fmap (\e -> e {endpointPassed = accepted}) final
  changes <- case (solved, confirmed, endpoint) of (Just a, Just _, Just b) -> Just <$> compareEndpoints a b; _ -> pure Nothing
  let history = object ["movementTolerance" .= (1e-7 :: Double), "solve" .= either (const Nothing) (Just . resultReport) attempt, "refusal" .= either (Just . explain) (const Nothing) attempt, "cpuSeconds" .= seconds]
      confirmationReport = object ["movementTolerance" .= refinementStop, "lengthWeights" .= [refinementWeight], "solve" .= fmap resultReport confirmed, "refusal" .= (confirmation >>= either (Just . explain) (const Nothing)), "skipped" .= skipped, "cpuSeconds" .= confirmationSeconds, "changes" .= changes]
      report =
        object
          [ "id" .= key,
            "layout" .= show (sourceLayout i),
            "vertices" .= length (samples (coupledSeed fixture)),
            "triangles" .= length (triangles (coupledSeed fixture)),
            "columns" .= map (fromRational :: Rational -> Double) (gridColumns (heldGrid c)),
            "heldVertices" .= IM.keys (coupledPins fixture),
            "sharedCreaseVertices" .= closedRoot (coupledReference fixture),
            "lengthWeights" .= equilibriumWeights,
            "iterationLimitPerStage" .= iterationLimit equilibriumSettings,
            "lengthTolerance" .= lengthTolerance equilibriumSettings,
            "contactMethod" .= show ProgressiveContactExchange,
            "contactEnabled" .= True,
            "passed" .= accepted,
            "primary" .= history,
            "confirmation" .= confirmationReport,
            "states" .= object [Key.fromString stage .= heldStateReport (endpointState e) | (stage, e, _) <- states],
            "stages" .= [stage | (stage, _, _) <- states],
            "comparisonState" .= fmap endpointKey endpoint,
            "continuousMotionChecked" .= False
          ]
  BL.writeFile (output </> key <> "-checks.json") (encode report)
  putStrLn (key <> ": accepted " <> show accepted)
  hFlush stdout
  pure (i, report, [m | (_, _, m) <- states], endpoint)

timed :: String -> Either InequalityError InequalityResult -> IO (Either InequalityError InequalityResult, Double)
timed label attempt = do
  putStrLn label
  hFlush stdout
  start <- getCPUTime
  _ <- evaluate (case attempt of Left _ -> 0; Right r -> maxLengthError (inequalityMesh r) + if inequalityConverged r then 1 else 0)
  finish <- getCPUTime
  pure (attempt, fromIntegral (finish - start) / 1e12)

field :: Text -> Value -> IO Value
field key = either die pure . parseEither (withObject "saved field" (.: Key.fromText key))

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
