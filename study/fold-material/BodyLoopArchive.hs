-- | Authenticate the saved ten-correction repair loop without another solve.
-- A final refusal belongs to a particular retained chain, material and contact
-- policy. Rebuild rows, verify recorded forces, bind every FOLD file to its
-- stated fraction or one saved repair, and remeasure all acceptance decisions.
-- Comparing the saved algebraic repair with its projection formula is a
-- checksum; it never installs new coordinates or calls a correction solver.
--
-- File names come from bounded indices, not paths supplied by JSON. The whole
-- archive is checked before any bytes are returned for a gallery to publish.
-- The reader intentionally accepts this ten-step, non-equilibrium experiment;
-- other stopping policies need their own interpretation, not a silent guess.
module BodyLoopArchive (LoopArchive (..), LoopState (..), readLoopArchive, verifyQuadratic) where

import BodyContactDiagnosis
import BodyContactDirection
import BodyCorrectionArchive
import BodyCorrectionReplay (replayFractions, scaledProposal)
import BodyDirectionGallery (pairWitnesses, rowValue)
import BodyFreshArchive
import BodyPatch
import BodyPatchCheckpoints
import BodyPlaneGuard
import BodyRestorationArchive
import BodyRestorationLoop qualified as Loop
import BodyShortArchive (checkState)
import ContactQuadratic (QuadraticRow)
import Control.Monad (forM, forM_, unless)
import CraneSpread
import Data.Aeson (FromJSON, Value, eitherDecode, object, (.=))
import Data.Aeson.Key (Key)
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.List (isSuffixOf)
import Data.Maybe (isJust)
import Data.Text (Text)
import FoldContact qualified as F
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import SurfaceContact qualified as C
import System.Exit (die)
import System.FilePath (takeDirectory, takeExtension, (</>))

data LoopState = LoopState
  { loopName :: String,
    loopTitle :: Text,
    loopSource :: String,
    loopScale :: Double,
    loopMesh :: MaterialMesh,
    loopRecord :: Value
  }

data LoopArchive = LoopArchive
  { loopStudy :: BodyPatch,
    loopAttempt :: Value,
    loopStates :: [LoopState],
    loopReport :: Value,
    loopFiles :: [(FilePath, BL.ByteString)]
  }

readLoopArchive :: FilePath -> IO LoopArchive
readLoopArchive source = do
  let repairDirectory = source </> "source"
  parent <- readFreshArchive (repairDirectory </> "source")
  controls <- case [ts | ("fresh", _, ts) <- freshDirections parent] of
    [ts] -> pure ts
    _ -> die "missing fresh direction"
  let control name = case [m | (n, m, _) <- controls, n == name] of
        [m] -> pure m
        _ -> die "missing fresh repair control"
  half <- control "fresh-8"
  refused <- control "fresh-7"
  original <- checkRestorationArchive repairDirectory "body-fresh-restoration" (RestorationSource (freshStudy parent) (freshStart parent) half refused (freshReport parent) (freshFiles parent))
  (reportBytes, report) <- jsonFile (source </> "checks.json")
  (traceBytes, attempts) <- jsonFile (source </> "trace.json")
  expect "gallery" ("body-restoration-loop" :: Text) report
  expect "source" (restorationReport original) report
  expect "attempts" (attempts :: [Value]) report
  forM_ ["iterationLimit", "completedCorrections"] $ \key -> expect key (10 :: Int) report
  expect "stopReason" ("correction-budget" :: Text) report
  expect "maxRepairsPerTrial" (1 :: Int) report
  expect "fractions" replayFractions report
  forM_ ["acceptedEndpoint", "continuousMotionChecked", "wholeCraneChecked"] $ \key -> expect key False report
  forM_ [("lengthWeight", 1e8), ("contactWeight", 1e10), ("damping", 1e-3), ("lengthTolerance", 1e-5), ("contactTolerance", 1e-7), ("movementTolerance", 1e-7), ("guardResidualTolerance", 1e-12), ("drawingScale", 600)] $ \(key, x) -> expect key (x :: Double) report
  expect "quadraticBudget" (100 :: Int) report
  records <- field "states" report
  unless (length attempts == 10 && length records == 11) (die "expected the complete ten-correction repair loop")
  let study = restorationStudy original
      fixture = patchSpread study
      base = restorationMesh original
      pins = spreadPins fixture
      free = [i | i <- [0 .. length (samples base) - 1], IM.notMember i pins]
  expect "freeVertices" free report
  model <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) base)
  let witnesses mesh = do
        ws <- checked (C.contactWitnesses model mesh)
        pure (concatMap (`pairWitnesses` ws) [(22, 63), (14, 55), (46, 70)])
      identity w = (C.witnessTriangles w, map fst (F.contactGradient (C.witnessRow w)))
      readState name record = do
        state <- field "state" record
        expect "id" name state
        (bytes, file) <- jsonFile (source </> name ++ ".fold")
        ps <- traverse vector (verticesCoords (keyFrame file))
        unless (length ps == length (samples base)) (die "loop archive changed vertex count")
        let mesh = base {samples = zipWith (\p q -> p {position = q}) (samples base) ps}
        expected <- materialFrame <$> checked (spreadSurface fixture mesh)
        unless (keyFrame file == expected) (die "loop archive changed material or metadata")
        checkState study mesh state
        m <- checked (measurePlane mesh 27 70)
        cut <- checked (pairSection mesh (46, 70))
        near "planeDistance" (planeDistance m) record
        near "planeMargin" (planeDistance m + 1e-7) record
        near "intersectionLength" (intersectionLength cut) record
        expect "crosses46_70" (sectionCrosses cut) record
        images <- forM [name ++ "-" ++ view ++ ".svg" | view <- ["side", "top", "underside", "material", "pair", "tip"]] $ \path -> do
          b <- readArchiveBytes (source </> path)
          pure (path, b)
        pure (mesh, (name ++ ".fold", bytes) : images)
      checkCandidate start cost guardMargins record checks = do
        state <- field "state" record
        geometry <- field "geometryPassed" state
        actualCost <- field "totalCost" state
        meshName <- field "id" state
        (mesh, files) <- readState meshName record
        let guards = all (>= -1e-12) guardMargins
            cheaper = actualCost < cost
        expect "guardsPassed" guards checks
        expect "geometryPassed" (geometry :: Bool) checks
        expect "costDecreased" cheaper checks
        values <- field "guardMargins" checks
        unless (length values == length guardMargins && and (zipWith close values guardMargins)) (die "loop guard margins disagree")
        movement <- checked (savedMovement (SavedPoint 0 start) (SavedPoint 0 mesh))
        near "movement" movement checks
        pure (mesh, files, guards && geometry && cheaper)
  retained <- forM (zip ("start" : ["step-" ++ show i | i <- [1 :: Int .. 10]]) records) $ \(name, record) -> do
    (mesh, files) <- readState name record
    state <- field "state" record
    expect "geometryPassed" True state
    pure (mesh, files, record)
  case retained of
    (initial, _, _) : _ -> unless (initial == base) (die "loop starts from another repaired shape")
    _ -> die "missing initial shape"
  inspected <- forM (zip3 [1 :: Int ..] attempts (zip retained (drop 1 retained))) $ \(number, attempt, ((start, _, before), (after, _, _))) -> do
    expect "number" number attempt
    expect "before" before attempt
    expect "startPositions" (positions start) attempt
    expect "failure" (Nothing :: Maybe Text) attempt
    expect "directionVerified" True attempt
    ws <- witnesses start
    unless (length ws == 12) (die "loop lost a named overlap guard")
    plane <- checked (measurePlane start 27 70)
    let target = min 0 (planeDistance plane)
        guards = map (contactGuard pins . C.witnessRow) ws ++ [planeGuardRow pins plane]
        constraints = [object ["triangles" .= (let (a, b) = C.witnessTriangles w in [a, b]), "vertices" .= map fst (F.contactGradient (C.witnessRow w)), "rawGap" .= F.contactGap (C.witnessRow w)] | w <- ws]
    unless (planeDistance plane >= -1e-7 && planeDistance plane < 0) (die "loop left its plane regime")
    expect "targetDistance" target attempt
    expect "constraints" constraints attempt
    expect "guards" (map rowValue guards) attempt
    rows <- checked (directionRows (spreadHinges fixture) pins model start)
    expect "materialRows" (map rowValue rows) attempt
    raw <- field "correction" attempt >>= traverse vector
    proposal <- field "proposal" attempt >>= traverse vector
    unless (length raw == length (samples start) && length proposal == length raw && proposal == zipWith (^+^) (map position (samples start)) raw) (die "saved correction disagrees with proposal")
    unless (all (\(i, d) -> IM.notMember i pins || d == V3 0 0 0) (zip [0 ..] raw)) (die "raw direction moves an exact hold")
    verifyQuadratic free rows guards (IM.fromList (zip [0 ..] raw)) attempt
    full <- checked (scaledProposal 1 start proposal)
    movement <- checked (savedMovement (SavedPoint 0 start) (SavedPoint 0 full))
    near "fullMovement" movement attempt
    unless (movement > 1e-7) (die "loop continued past its equilibrium limit")
    measured <- checked (measurePatch study (SavedPoint 0 start))
    let cost = patchCost 1e8 measured
        stem :: Int -> String
        stem k = "attempt-" ++ show number ++ "-trial-" ++ show k
    trials <- field "trials" attempt
    unless (not (null trials) && length trials <= 31) (die "invalid loop trial budget")
    entries <- forM (zip3 [0 :: Int ..] replayFractions trials) $ \(k, scale, trial) -> do
      expect "scale" scale trial
      record <- field "record" trial
      state <- field "state" record
      expect "id" (stem k) state
      expected <- checked (scaledProposal scale start proposal)
      checks <- field "checks" trial
      expect "extra" (object []) checks
      (mesh, files, passed) <- checkCandidate start cost (map (`margin` displacement start expected) guards) record checks
      unless (mesh == expected) (die "raw trial differs from its saved fraction")
      expect "passed" passed trial
      repair <- field "restoration" trial :: IO (Maybe Value)
      case (passed, repair) of
        (True, Nothing) -> pure (stem k, mesh, record, files, True)
        (True, Just _) -> die "a passing raw trial was repaired"
        (False, Nothing) -> die "a refused raw trial lost its repair decision"
        (False, Just restored) -> do
          failure <- field "failure" restored :: IO (Maybe Text)
          m <- checked (measurePlane mesh 27 70)
          ws1 <- witnesses mesh
          let refusal
                | planeDistance m >= target = Just "No plane-distance loss to restore"
                | map identity ws /= map identity ws1 = Just "Refused trial changed overlap witness topology"
                | otherwise = Nothing
          if isJust refusal
            then do
              unless (failure == refusal) (die "repair refusal reason changed")
              pure (stem k, mesh, record, files, False)
            else do
              expect "failure" (Nothing :: Maybe Text) restored
              details <- field "checks" restored
              extra <- field "extra" details
              expect "gradient" (rowValue (planeGradient m, planeDistance m)) extra
              expect "refreshedGuards" (map (rowValue . contactGuard pins . C.witnessRow) ws1) extra
              correction <- field "rawCorrection" extra >>= traverse vector
              let gradient = IM.difference (planeGradient m) pins
                  squared = sum [dot g g | g <- IM.elems gradient]
                  rawExpected = [((target - planeDistance m) / squared) *^ IM.findWithDefault (V3 0 0 0) i gradient | i <- [0 .. length (samples mesh) - 1]]
                  projected = mesh {samples = zipWith (\p d -> p {position = position p ^+^ d}) (samples mesh) correction}
              unless (squared > 0 && length correction == length rawExpected && and (zipWith (\a b -> norm (a ^-^ b) < 1e-20) correction rawExpected)) (die "saved repair differs from its one projection")
              ws2 <- witnesses projected
              unless (map identity ws1 == map identity ws2) (die "saved repair changed overlap topology")
              let installed = displacement mesh projected
                  gaps = map (`margin` displacement start projected) guards ++ map ((`margin` installed) . contactGuard pins . C.witnessRow) ws1 ++ [margin (planeGradient m, planeDistance m - target) installed]
              fixed <- field "record" restored
              fixedState <- field "state" fixed
              expect "id" (stem k ++ "-repair") fixedState
              (repaired, repairedFiles, usable) <- checkCandidate start cost gaps fixed details
              unless (repaired == projected) (die "saved repair coordinates changed")
              expect "passed" usable restored
              -- A second check exercises the shared routine used by the next
              -- comparison. Reconstructing these saved algebraic repairs is
              -- a regression checksum, not another material direction.
              let sharedWitnesses current = do
                    found <- C.contactWitnesses model current
                    pure (concatMap (`pairWitnesses` found) [(22, 63), (14, 55), (46, 70)])
                  context = Loop.TrialContext study start cost guards target sharedWitnesses ws
              shared <- checked (Loop.repairCandidate context (Loop.Candidate mesh passed checks))
              unless (Loop.candidateMesh shared == repaired && Loop.candidatePasses shared == usable && Loop.candidateDetails shared == details) (die "shared repair changed a saved repair")
              afterPlane <- checked (measurePlane repaired 27 70)
              repairMovement <- checked (savedMovement (SavedPoint 0 mesh) (SavedPoint 0 repaired))
              originalCost <- field "totalCost" state
              finalCost <- field "totalCost" fixedState
              forM_ [("targetDistance", target), ("refusedDistance", planeDistance m), ("restoredDistance", planeDistance afterPlane), ("repairMovement", repairMovement), ("costChangeFromTrial", finalCost - originalCost)] $ \(key, x) -> near key x extra
              pure (stem k ++ "-repair", repaired, fixed, files ++ repairedFiles, usable)
    case reverse entries of
      (name, mesh, record, _, True) : rest -> do
        unless (all (\(_, _, _, _, passed) -> not passed) rest && mesh == after) (die "loop did not retain its first passing candidate")
        expect "selectedState" name attempt
        expect "selectedScale" (2 ** negate (fromIntegral (length trials - 1)) :: Double) attempt
        let states =
              [LoopState "before" "Start of final correction" "step-9" 0 start before | number == 10]
                ++ [LoopState "retained" "Passing 1/128" name (1 / 128) mesh record | number == 10]
                ++ [LoopState "refused" "Refused 1/64" n (1 / 64) m r | number == 10, (n, m, r, _, _) <- entries, n == stem 6]
        pure (states, concat [fs | (_, _, _, fs, _) <- entries])
      _ -> die "loop has no retained passing candidate"
  let selected = concatMap fst inspected
  unless (length selected == 3) (die "missing final start and two controls")
  finalAttempt <- case reverse attempts of
    a : _ -> pure a
    _ -> die "missing final attempt"
  expect "selectedState" ("attempt-10-trial-7" :: String) finalAttempt
  expect "selectedScale" (1 / 128 :: Double) finalAttempt
  finalMesh <- case reverse retained of
    (m, _, _) : _ -> pure m
    _ -> die "missing final retained shape"
  movement <- checked (savedMovement (SavedPoint 0 base) (SavedPoint 0 finalMesh))
  near "maxMovementFromStart" movement report
  let files = ("checks.json", reportBytes) : ("trace.json", traceBytes) : concat [fs | (_, fs, _) <- retained] ++ concatMap snd inspected ++ [("source" </> n, b) | (n, b) <- restorationFiles original]
  -- The gallery names this particular saved experiment and reports these
  -- counts. Refuse a different ten-step archive instead of reusing its labels.
  let directFolds = [n | (n, _) <- files, takeDirectory n == ".", takeExtension n == ".fold"]
      repairs = length (filter ("-repair.fold" `isSuffixOf`) directFolds)
  unless (length directFolds == 137 && repairs == 30) (die "loop archive changed its trial or repair count")
  pure (LoopArchive study finalAttempt selected report files)

verifyQuadratic :: [Int] -> [QuadraticRow] -> [QuadraticRow] -> IM.IntMap V3 -> Value -> IO ()
verifyQuadratic free rows guards delta attempt = do
  report <- field "quadratic" attempt
  expect "converged" True report
  forM_ [("balance", 1e-6), ("violation", 1e-12), ("complementarity", 1e-12)] $ \(key, cap) -> do
    x <- field key report
    unless (finite x && x >= 0 && x <= cap) (die "unverified saved quadratic report")
  contacts <- field "contacts" attempt
  unless (length contacts == length guards) (die "missing saved contact forces")
  forces <- forM (zip3 [0 :: Int ..] guards contacts) $ \(i, row, c) -> do
    expect "sources" [i] c
    multiplier <- field "multiplier" c
    scale <- field "responseScale" c
    active <- field "selected" c
    let gap = margin row delta
    unless (finite multiplier && multiplier >= 0 && finite scale && scale > 0 && gap >= -1e-12 && if active then abs gap <= 1e-12 else multiplier == 0) (die "saved contact force violates its guard")
    near "gap" gap c
    pure (active, IM.map ((multiplier / scale) *^) (fst row))
  expect "active" (length (filter fst forces)) report
  let material = IM.unionsWith (^+^) (IM.map (1e-3 *^) delta : [IM.map (margin row delta *^) g | row@(g, _) <- rows])
      total = IM.unionWith (^+^) material (IM.map ((-1) *^) (IM.unionsWith (^+^) (map snd forces)))
      balance = sqrt (sum [dot v v | i <- free, Just v <- [IM.lookup i total]])
  unless (finite balance && balance <= 1e-6) (die "saved quadratic force balance fails")

positions :: MaterialMesh -> [[Double]]
positions = map (xyz . position) . samples

displacement :: MaterialMesh -> MaterialMesh -> IM.IntMap V3
displacement a b = IM.fromList (zip [0 ..] (zipWith (\p q -> position q ^-^ position p) (samples a) (samples b)))

margin :: QuadraticRow -> IM.IntMap V3 -> Double
margin (g, r) d = r + sum [dot v (IM.findWithDefault (V3 0 0 0) i d) | (i, v) <- IM.toList g]

jsonFile :: (FromJSON a) => FilePath -> IO (BL.ByteString, a)
jsonFile path = do
  bytes <- readArchiveBytes path
  value <- either die pure (eitherDecode bytes)
  pure (bytes, value)

expect :: (Eq a, FromJSON a) => Key -> a -> Value -> IO ()
expect key wanted record = do
  actual <- field key record
  unless (actual == wanted) (die ("changed loop archive field: " ++ show key))

near :: Key -> Double -> Value -> IO ()
near key expected record = do
  actual <- field key record
  unless (close actual expected) (die ("changed loop measurement: " ++ show key))

close :: Double -> Double -> Bool
close a b = finite a && finite b && abs (a - b) < 1e-15

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)

vector :: [Double] -> IO V3
vector [x, y, z] | all finite [x, y, z] = pure (V3 x y z)
vector _ = die "loop position must have three finite coordinates"
