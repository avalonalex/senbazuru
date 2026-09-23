-- | Read the ten-correction body experiment without solving it again. A saved
-- outcome is useful evidence only when its material, parent shape and trial
-- fraction agree. This reader checks the whole returned chain and remeasures
-- all 310 trials, including the refused fractions before each selected one.
-- The saved quadratic reports are retained, not recomputed as new solutions.
--
-- Keeping this at the archive boundary lets later inspections share one rule
-- for what the final attempt means. File names are derived from fixed indices,
-- never accepted as arbitrary paths from JSON. No correction solver is called.
module BodyShortArchive (ShortArchive (..), ShortState (..), readShortArchive, checkState) where

import BodyCorrectionArchive
import BodyCorrectionReplay
import BodyPatch
import BodyPatchCheckpoints
import BodyPatchSubdivision (seedPassed)
import Control.Monad (forM, forM_, unless, when)
import CraneSpread
import Data.Aeson (FromJSON, Value, eitherDecode, toJSON)
import Data.Aeson.Key (Key)
import Data.ByteString.Lazy qualified as BL
import Data.List (findIndex)
import Data.Text (Text)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface
import System.Exit (die)
import System.FilePath ((</>))

-- | The start of attempt ten, its retained fraction, then the next larger
-- refused fraction. The labels describe archival roles, not new acceptance.
data ShortState = ShortState
  { shortName :: String,
    shortTitle :: Text,
    shortSource :: FilePath,
    shortScale :: Double,
    shortMesh :: MaterialMesh,
    shortRecord :: Value
  }

data ShortArchive = ShortArchive
  { shortStudy :: BodyPatch,
    shortAttempt :: Value,
    shortStates :: [ShortState],
    shortFiles :: [(FilePath, BL.ByteString)]
  }

readShortArchive :: FilePath -> IO ShortArchive
readShortArchive source = do
  original <- readBlockedArchive (source </> "source")
  (rawReport, report) <- jsonFile (source </> "checks.json")
  (rawTrace, attempts) <- jsonFile (source </> "trace.json")
  expect "gallery" ("body-short" :: Text) report
  forM_ ["iterationLimit", "completedCorrections"] $ \key -> expect key (10 :: Int) report
  expect "sourceIteration" (8 :: Int) report
  expect "stopReason" ("correction-budget" :: Text) report
  forM_ ["acceptedEndpoint", "continuousMotionChecked", "wholeCraneChecked"] $ \key -> expect key False report
  forM_ [("lengthWeight", 1e8), ("contactWeight", 1e10), ("damping", 1e-3), ("lengthTolerance", 1e-5), ("contactTolerance", 1e-7), ("movementTolerance", 1e-7)] $ \(key, value) -> expect key (value :: Double) report
  expect "quadraticBudget" (100 :: Int) report
  expect "pairs" ([[22, 63], [14, 55], [46, 70]] :: [[Int]]) report
  expect "attempts" (attempts :: [Value]) report
  states <- field "states" report
  unless (length attempts == 10 && length states == 11) (die "expected the ten-correction archive")
  let study = blockedStudy original
      fixture = patchSpread study
      base = blockedMesh original
      names = "start" : ["step-" ++ show i | i <- [1 :: Int .. 10]]
      positions = map (xyz . position) . samples
      readMesh name = do
        (bytes, file) <- jsonFile (source </> name ++ ".fold")
        ps <- traverse vector (verticesCoords (keyFrame file))
        unless (length ps == length (samples base)) (die "short-correction archive vertex count changed")
        let mesh = base {samples = zipWith (\p q -> p {position = q}) (samples base) ps}
        expected <- materialFrame <$> checked (spreadSurface fixture mesh)
        unless (keyFrame file == expected) (die "short-correction archive changed material or metadata")
        pure (mesh, (name ++ ".fold", bytes))
  retained <- forM (zip3 [0 :: Int ..] names states) $ \(i, name, record) -> do
    expect "id" name record
    (mesh, bytes) <- readMesh name
    valid <- checked (seedPassed study mesh)
    unless valid (die "a retained short-correction shape fails geometry")
    checkState study mesh record
    when (i == 0) (unless (mesh == base) (die "short continuation starts from another archive"))
    pure (mesh, bytes, record)
  inspected <- forM (zip3 [1 :: Int ..] attempts (zip retained (drop 1 retained))) $ \(number, attempt, ((before, _, record), (after, _, _))) -> do
    expect "number" number attempt
    expect "before" record attempt
    expect "startPositions" (positions before) attempt
    expect "directionVerified" True attempt
    expect "failure" (Nothing :: Maybe Text) attempt
    quadratic <- field "quadratic" attempt
    expect "converged" True quadratic
    forM_ [("violation", 1e-12), ("complementarity", 1e-12), ("balance", 1e-6)] $ \(key, cap) -> do
      x <- field key quadratic
      unless (finite x && x >= 0 && x <= cap) (die "saved quadratic report does not pass its original limits")
    proposal <- field "proposal" attempt >>= traverse vector
    full <- checked (scaledProposal 1 before proposal)
    movement <- checked (savedMovement (SavedPoint 0 before) (SavedPoint 0 full))
    nearField "fullMovement" movement attempt
    unless (movement > 1e-7) (die "archived run continued after its declared equilibrium limit")
    trials <- checked (replayCorrection study before proposal)
    chosen <- maybe (die "saved attempt has no independently passing trial") pure (firstPassing trials)
    index <- maybe (die "selected fraction is absent") pure (findIndex ((== replayScale chosen) . replayScale) trials)
    let stem k = "attempt-" ++ show number ++ "-trial-" ++ show k
    expect "selectedScale" (replayScale chosen) attempt
    expect "selectedState" [stem index] attempt
    unless (savedMesh (measuredPoint (replayMeasure chosen)) == after) (die "retained shape differs from its selected trial")
    records <- field "trials" attempt
    unless (length records == 31) (die "saved attempt lost trial evidence")
    files <- forM (zip3 [0 :: Int ..] trials records) $ \(k, trial, entry) -> do
      expect "scale" (replayScale trial) entry
      expect "costDecreased" (replayCostDecreased trial) entry
      expect "geometryPassed" (replayGeometryPassed trial) entry
      nearField "movement" (replayMovement trial) entry
      state <- field "state" entry
      expect "id" (stem k) state
      (mesh, bytes) <- readMesh (stem k)
      unless (mesh == savedMesh (measuredPoint (replayMeasure trial))) (die "archived trial is not the stated fraction of its saved proposal")
      checkState study mesh state
      pure (k, mesh, state, bytes)
    let finalStates =
          [ShortState "before" "Start of attempt ten" "step-9.fold" 0 before record | number == 10]
            ++ [ShortState name title (stem k ++ ".fold") scale mesh state | number == 10, (k, mesh, state, _) <- files, (j, name, title, scale) <- [(index, "retained", "Retained · 1/32768", replayScale chosen), (index - 1, "refused", "Refused · 1/16384", 2 * replayScale chosen)], k == j]
    pure (attempt, finalStates, [bytes | (_, _, _, bytes) <- files])
  case (retained, reverse retained, reverse inspected) of
    ((firstMesh, _, _) : _, (lastMesh, _, _) : _, (attempt, final, _) : _) -> do
      movement <- checked (savedMovement (SavedPoint 0 firstMesh) (SavedPoint 0 lastMesh))
      nearField "maxMovementFromStart" movement report
      expect "selectedScale" (1 / 32768 :: Double) attempt
      unless (length final == 3) (die "final inspection needs the start, retained and next-larger refused trial")
      pure (ShortArchive study attempt final (("checks.json", rawReport) : ("trace.json", rawTrace) : [bytes | (_, bytes, _) <- retained] ++ concat [bytes | (_, _, bytes) <- inspected] ++ [("source" </> name, bytes) | (name, bytes) <- blockedFiles original]))
    _ -> die "incomplete short-correction archive"

checkState :: BodyPatch -> MaterialMesh -> Value -> IO ()
checkState study mesh record = do
  measured <- checked (measurePatch study (SavedPoint 0 mesh))
  valid <- checked (seedPassed study mesh)
  expect "geometryPassed" valid record
  expect "contact" (toJSON (measuredContact measured)) record
  expect "holdError" (spreadHeldError (patchSpread study) mesh) record
  forM_ [("maxRelativeEdgeError", maximum (0 : map edgeRelativeError (measuredEdges measured))), ("creaseEnergy", measuredCrease measured), ("panelEnergy", measuredPanel measured), ("lengthCost", 5e7 * measuredLengthSquares measured), ("contactCost", 5e9 * measuredContactSquares measured), ("totalCost", patchCost 1e8 measured), ("bodyDepth", measuredBodyDepth measured)] $ \(key, x) -> nearField key x record

jsonFile :: (FromJSON a) => FilePath -> IO (BL.ByteString, a)
jsonFile path = do bytes <- BL.readFile path; value <- either die pure (eitherDecode bytes); pure (bytes, value)

expect :: (Eq a, FromJSON a) => Key -> a -> Value -> IO ()
expect key expected record = do actual <- field key record; unless (actual == expected) (die ("changed short archive field: " ++ show key))

nearField :: Key -> Double -> Value -> IO ()
nearField key expected record = do actual <- field key record; unless (finite actual && abs (actual - expected) < 1e-12) (die ("saved measurement disagrees: " ++ show key))

vector :: [Double] -> IO V3
vector [x, y, z] | all finite [x, y, z] = pure (V3 x y z)
vector _ = die "saved trial needs three finite coordinates per vertex"

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)
