-- | Authenticate the saved thirteen-versus-nineteen-guard comparison.
-- An inspection must use the direction that produced its trial, with the same
-- material and acceptance policy. Reuse the loop reader, quadratic force check
-- and shared one-repair routine; never solve another material direction here.
-- Reconstructing a saved algebraic repair checks its provenance only.
--
-- Read every visited shape and refusal before returning publishable assets.
-- Paths come from bounded trial indices, not file names supplied by JSON.
module BodyFourthArchive (FourthArchive (..), FourthState (..), readFourthArchive) where

import BodyContactDiagnosis
import BodyContactDirection
import BodyCorrectionArchive
import BodyCorrectionReplay (replayFractions, scaledProposal)
import BodyDirectionGallery (pairWitnesses, rowValue)
import BodyLoopArchive
import BodyPatch
import BodyPatchCheckpoints
import BodyPlaneGuard
import BodyRestorationLoop
import BodyShortArchive (checkState)
import Control.Monad (forM, forM_, unless, when)
import CraneSpread
import Data.Aeson (FromJSON, Value, eitherDecode, object, (.=))
import Data.Aeson.Key (Key)
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import FoldContact qualified as F
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import SurfaceContact qualified as C
import System.Exit (die)
import System.FilePath ((</>))

data FourthState = FourthState
  { fourthName :: String,
    fourthTitle :: Text,
    fourthSource :: String,
    fourthScale :: Double,
    fourthMesh :: MaterialMesh,
    fourthRecord :: Value
  }

data FourthArchive = FourthArchive
  { fourthStudy :: BodyPatch,
    fourthDirection :: Value,
    fourthStates :: [FourthState],
    fourthFiles :: [(FilePath, BL.ByteString)]
  }

readFourthArchive :: FilePath -> IO FourthArchive
readFourthArchive source = do
  parent <- readLoopArchive (source </> "source")
  start <- case [loopMesh s | s <- loopStates parent, loopName s == "before"] of
    [s] -> pure s
    _ -> die "missing start of the saved guard comparison"
  bytes <- readArchiveBytes (source </> "checks.json")
  report <- either die pure (eitherDecode bytes)
  let study = loopStudy parent
      fixture = patchSpread study
      pins = spreadPins fixture
      free = [i | i <- [0 .. length (samples start) - 1], IM.notMember i pins]
      oldPairs = [(22, 63), (14, 55), (46, 70)]
  expect "gallery" ("body-fourth-pair" :: Text) report
  forM_ [("issue", 363), ("newQuadratics", 1), ("continuationSteps", 0), ("sourceAttempt", 10), ("oldGuardCount", 13), ("addedGuardCount", 6), ("planeGuardIndex", 12), ("maxRepairsPerTrial", 1), ("quadraticBudget", 100 :: Int)] $ \(k, v) -> expect k v report
  forM_ [("contactTolerance", 1e-7), ("lengthTolerance", 1e-5), ("guardResidualTolerance", 1e-12), ("movementTolerance", 1e-7), ("lengthWeight", 1e8), ("contactWeight", 1e10), ("damping", 1e-3), ("drawingScale", 600 :: Double)] $ \(k, v) -> expect k v report
  forM_ ["continuousMotionChecked", "wholeCraneChecked"] $ \k -> expect k False report
  expect "sourceStart" ("step-9.fold" :: Text) report
  expect "startPositions" (positions start) report
  expect "freeVertices" free report
  expect "fractions" replayFractions report
  model <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) start)
  let witnesses pairs mesh = do
        ws <- C.contactWitnesses model mesh
        pure (concatMap (`pairWitnesses` ws) pairs)
  ws <- checked (witnesses oldPairs start)
  added <- checked (witnesses [(55, 93)] start)
  unless (length ws == 12 && length added == 6) (die "comparison changed overlap corners")
  plane <- checked (measurePlane start 27 70)
  let target = min 0 (planeDistance plane)
      oldGuards = map (contactGuard pins . C.witnessRow) ws ++ [planeGuardRow pins plane]
      newGuards = oldGuards ++ map (contactGuard pins . C.witnessRow) added
  expect "planeTarget" target report
  expect "constraints" [object ["guard" .= i, "triangles" .= pair (C.witnessTriangles w), "rawGap" .= F.contactGap (C.witnessRow w), "lower" .= xyz (C.witnessLower w), "upper" .= xyz (C.witnessUpper w)] | (i, w) <- zip ([0 .. 11] ++ [13 .. 18 :: Int]) (ws ++ added)] report
  rows <- checked (directionRows (spreadHinges fixture) pins model start)
  expect "materialRows" (map rowValue rows) report
  measured <- checked (measurePatch study (SavedPoint 0 start))
  let baseCost = patchCost 1e8 measured
      readState name record = do
        s <- field "state" record
        expect "id" name s
        fileBytes <- readArchiveBytes (source </> name ++ ".fold")
        file <- either die pure (eitherDecode fileBytes)
        ps <- traverse vector (verticesCoords (keyFrame file))
        unless (length ps == length (samples start)) (die "comparison changed vertex count")
        let mesh = start {samples = zipWith (\p q -> p {position = q}) (samples start) ps}
        frame <- materialFrame <$> checked (spreadSurface fixture mesh)
        unless (keyFrame file == frame) (die "comparison changed material or metadata")
        checkState study mesh s
        cut <- checked (pairSection mesh (55, 93))
        expect "crosses55_93" (sectionCrosses cut) record
        near "intersectionLength" (intersectionLength cut) record
        expect "firstDistances" (firstDistances cut) record
        expect "secondDistances" (secondDistances cut) record
        forM_ [("plane30", 30, 93), ("plane27", 27, 70)] $ \(k, v, t) -> checked (measurePlane mesh v t) >>= \p -> near k (planeDistance p) record
        pairWs <- checked (witnesses [(55, 93)] mesh)
        expect "minimumPairGap" (case map (F.contactGap . C.witnessRow) pairWs of [] -> Nothing; gs -> Just (minimum gs)) record
        expect "pairWitnesses" [object ["triangles" .= pair (C.witnessTriangles w), "lower" .= xyz (C.witnessLower w), "upper" .= xyz (C.witnessUpper w), "gap" .= F.contactGap (C.witnessRow w), "row" .= rowValue (contactGuard pins (C.witnessRow w))] | w <- pairWs] record
        images <- forM [name ++ "-" ++ view ++ ".svg" | view <- ["side", "top", "underside", "material", "pair", "tip"]] $ \path -> do
          imageBytes <- readArchiveBytes (source </> path)
          pure (path, imageBytes)
        pure (mesh, (name ++ ".fold", fileBytes) : images)
  initial <- field "start" report
  (initialMesh, initialFiles) <- readState "start" initial
  unless (initialMesh == start) (die "comparison starts at another shape")
  directions <- field "directions" report
  unless (length directions == 2) (die "comparison needs both recorded directions")
  results <- forM (zip ["control", "added" :: String] directions) $ \(name, d) -> do
    expect "id" name d
    expect "failure" (Nothing :: Maybe Text) d
    expect "directionVerified" True d
    expect "acceptedEndpoint" False d
    let guards = if name == "control" then oldGuards else newGuards
        pairs = if name == "control" then oldPairs else oldPairs ++ [(55, 93)]
        initialWs = if name == "control" then ws else ws ++ added
        context = TrialContext study start baseCost guards target (witnesses pairs) initialWs
    expect "guards" (map rowValue guards) d
    raw <- field "correction" d >>= traverse vector
    proposal <- field "proposal" d >>= traverse vector
    unless (length raw == length (samples start) && proposal == zipWith (^+^) (map position (samples start)) raw) (die "comparison changed its saved proposal")
    unless (all (\(v, x) -> IM.notMember v pins || x == V3 0 0 0) (zip [0 ..] raw)) (die "comparison moves an exact hold")
    verifyQuadratic free rows guards (IM.fromList (zip [0 ..] raw)) d
    quadratic <- field "quadratic" d
    iterations <- field "iterations" quadratic :: IO Int
    unless (iterations > 0 && iterations <= 100) (die "comparison exceeds the quadratic budget")
    full <- checked (scaledProposal 1 start proposal)
    movement <- checked (savedMovement (SavedPoint 0 start) (SavedPoint 0 full))
    near "fullMovement" movement d
    unless (movement > 1e-7) (die "comparison changed its unsettled stopping result")
    when (name == "control") $
      forM_ ["proposal", "correction", "quadratic", "contacts"] $ \key -> do
        original <- field key (loopAttempt parent) :: IO Value
        expect key original d
    trials <- field "trials" d
    unless (length trials == if name == "control" then 8 else 4) (die "comparison changed visited trial count")
    inspected <- forM (zip3 [0 :: Int ..] replayFractions trials) $ \(k, scale, t) -> do
      expect "scale" scale t
      let label = name ++ "-" ++ show k
      record <- field "record" t
      (mesh, files) <- readState label record
      expected <- checked (scaledProposal scale start proposal)
      unless (mesh == expected) (die "trial differs from its saved fraction")
      candidate <- checked (assess study start baseCost (map (`margin` displacement start mesh) guards) (object []) mesh)
      expect "checks" (candidateDetails candidate) t
      expect "passed" (candidatePasses candidate) t
      restoration <- field "restoration" t :: IO (Maybe Value)
      (passes, extraFiles) <- case (candidatePasses candidate, restoration) of
        (True, Nothing) -> pure (True, [])
        (False, Just saved) -> case repairCandidate context candidate of
          Left err -> expect "failure" (Just (explain err)) saved >> pure (False, [])
          Right fixed -> do
            expect "failure" (Nothing :: Maybe Text) saved
            expect "checks" (candidateDetails fixed) saved
            expect "passed" (candidatePasses fixed) saved
            repairRecord <- field "record" saved
            (repaired, repairFiles) <- readState (label ++ "-repair") repairRecord
            unless (repaired == candidateMesh fixed) (die "saved repair differs from its projection")
            pure (candidatePasses fixed, repairFiles)
        _ -> die "comparison changed its repair decision"
      unless (not passes || candidatePasses candidate) (die "comparison changed its raw selected endpoint")
      pure (k, passes, mesh, record, files ++ extraFiles)
    let finalIndex = if name == "control" then 7 else 3
    unless ([(k, p) | (k, p, _, _, _) <- inspected] == [(k, k == finalIndex) | k <- [0 .. finalIndex]]) (die "comparison did not retain the first passing trial")
    expect "selectedScale" (2 ** negate (fromIntegral finalIndex) :: Double) d
    expect "selectedState" (name ++ "-" ++ show finalIndex) d
    let selected = [FourthState role title (name ++ "-" ++ show k) (2 ** negate (fromIntegral k)) m r | name == "added", (k, _, m, r, _) <- inspected, (wanted, role, title) <- [(2, "refused", "Refused 1/4"), (3, "retained", "Passing 1/8")], k == wanted]
    pure (d, selected, concat [fs | (_, _, _, _, fs) <- inspected])
  newDirection <- case results of [_, (d, _, _)] -> pure d; _ -> die "missing added-guard direction"
  let states = FourthState "start" "Saved start" "start" 0 start initial : concat [ss | (_, ss, _) <- results]
      files = ("checks.json", bytes) : initialFiles ++ concat [fs | (_, _, fs) <- results] ++ [("source" </> n, b) | (n, b) <- loopFiles parent]
  pure (FourthArchive study newDirection states files)

positions :: MaterialMesh -> [[Double]]
positions = map (xyz . position) . samples

pair :: (Int, Int) -> [Int]
pair (a, b) = [a, b]

expect :: (Eq a, FromJSON a) => Key -> a -> Value -> IO ()
expect key wanted value = do actual <- field key value; unless (actual == wanted) (die ("comparison changed " ++ show key))

near :: Key -> Double -> Value -> IO ()
near key wanted value = do actual <- field key value; unless (not (isNaN actual || isInfinite actual) && abs (actual - wanted) <= 1e-12 * max 1 (abs wanted)) (die ("comparison measurement changed " ++ show key))

vector :: [Double] -> IO V3
vector [x, y, z] | all (\v -> not (isNaN v || isInfinite v)) [x, y, z] = pure (V3 x y z)
vector _ = die "comparison needs three finite coordinates"
