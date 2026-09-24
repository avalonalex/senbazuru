-- | Validate the saved moving-plane comparison before another study reads it.
-- Both directions and all 62 trials must reproduce the original material,
-- exact holds, geometry and cost decisions. The preceding 310-trial chain is
-- also checked. This shared reader never solves or accepts new paper, and
-- returns source bytes only after validation so callers cannot publish a
-- partially checked archive. Paths are fixed by direction and fraction ids.
module BodyPlaneArchive (PlaneArchive (..), readPlaneArchive) where

import BodyContactDiagnosis
import BodyCorrectionArchive
import BodyCorrectionReplay
import BodyDirectionGallery (rowValue)
import BodyPatch
import BodyPatchCheckpoints
import BodyPlaneGuard
import BodyShortArchive
import Control.Monad (forM, forM_, unless, when)
import CraneSpread
import Data.Aeson (FromJSON, Value, eitherDecode)
import Data.Aeson.Key (Key)
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import System.Exit (die)
import System.FilePath ((</>))

data PlaneArchive = PlaneArchive
  { planeStudy :: BodyPatch,
    planeStart :: MaterialMesh,
    planeReport :: Value,
    planeDirections :: [(String, Value, [(String, MaterialMesh, Value)])],
    planeFiles :: [(FilePath, BL.ByteString)]
  }

readPlaneArchive :: FilePath -> IO PlaneArchive
readPlaneArchive source = do
  archive <- readShortArchive (source </> "source")
  (reportBytes, report) <- jsonFile (source </> "checks.json")
  expect "gallery" ("body-plane" :: Text) report
  expect "sourceAttempt" (10 :: Int) report
  expect "newQuadratics" (1 :: Int) report
  expect "continuationSteps" (0 :: Int) report
  forM_ ["continuousMotionChecked", "wholeCraneChecked"] $ \key -> expect key False report
  forM_ [("contactTolerance", 1e-7), ("lengthTolerance", 1e-5), ("movementTolerance", 1e-7), ("lengthWeight", 1e8), ("contactWeight", 1e10), ("damping", 1e-3)] $ \(key, x) -> expect key (x :: Double) report
  expect "quadraticBudget" (100 :: Int) report
  expect "drawingScale" (600 :: Double) report
  expect "sourceControl" (shortAttempt archive) report
  forM_ ["materialRows", "constraints"] $ \key -> do value <- field key (shortAttempt archive) :: IO Value; expect key value report
  start <- case [shortMesh s | s <- shortStates archive, shortName s == "before"] of [m] -> pure m; _ -> die "missing saved start of attempt ten"
  let study = shortStudy archive; fixture = patchSpread study
  expect "startPositions" (map (xyz . position) (samples start)) report
  measure <- checked (measurePlane start 27 70)
  plane <- field "planeGuard" report
  expect "vertex" (27 :: Int) plane
  expect "triangle" (70 :: Int) plane
  expect "gradient" (rowValue (planeGradient measure, planeDistance measure)) plane
  expect "row" (rowValue (planeGuardRow (spreadPins fixture) measure)) plane
  nearField 1e-17 "distance" (planeDistance measure) plane
  nearField 1e-17 "floor" (min 0 (planeDistance measure)) plane
  let readMesh name state = do
        (bytes, file) <- jsonFile (source </> name ++ ".fold")
        ps <- traverse vector (verticesCoords (keyFrame file))
        unless (length ps == length (samples start)) (die "plane archive vertex count changed")
        let mesh = start {samples = zipWith (\p q -> p {position = q}) (samples start) ps}
        expected <- materialFrame <$> checked (spreadSurface fixture mesh)
        unless (keyFrame file == expected) (die "plane archive material, topology or metadata changed")
        expect "id" name state
        checkState study mesh state
        pure (mesh, (name ++ ".fold", bytes))
  startRecord <- field "start" report
  (startMesh, startFile) <- readMesh "start" startRecord
  unless (startMesh == start) (die "plane archive started from another shape")
  directionRecords <- field "directions" report
  unless (length directionRecords == 2) (die "expected two saved plane directions")
  directions <- forM (zip ["control", "plane"] directionRecords) $ \(name, direction) -> do
    expect "id" name direction
    expect "usesPlaneGuard" (name == "plane") direction
    expect "failure" (Nothing :: Maybe Text) direction
    expect "directionVerified" True direction
    expect "acceptedEndpoint" False direction
    quadratic <- field "quadratic" direction
    expect "converged" True quadratic
    forM_ [("balance", 1e-6), ("complementarity", 1e-12), ("violation", 1e-12)] $ \(key, cap) -> do
      x <- field key quadratic; unless (finite x && x >= 0 && x <= cap) (die "archived quadratic report fails its numerical limits")
    proposal <- field "proposal" direction >>= traverse vector
    raw <- field "correction" direction >>= traverse vector
    unless (length raw == length (samples start) && length proposal == length raw && and (zipWith3 (\p d q -> position p ^+^ d == q) (samples start) raw proposal)) (die "archived raw correction does not produce its proposal")
    full <- checked (scaledProposal 1 start proposal)
    movement <- checked (savedMovement (SavedPoint 0 start) (SavedPoint 0 full))
    nearField 1e-14 "fullMovement" movement direction
    unless (movement > 1e-7) (die "archived full movement already meets equilibrium")
    replayed <- checked (replayCorrection study start proposal)
    selected <- maybe (die "saved direction has no passing trial") pure (firstPassing replayed)
    expect "selectedScale" (replayScale selected) direction
    records <- field "trials" direction
    unless (length records == 31) (die "plane archive lost trial fractions")
    entries <- forM (zip3 [0 :: Int ..] replayed records) $ \(k, trial, record) -> do
      let nameOfTrial = name ++ "-" ++ show k
      expect "scale" (replayScale trial) record
      expect "geometryPassed" (replayGeometryPassed trial) record
      expect "costDecreased" (replayCostDecreased trial) record
      nearField 1e-14 "movement" (replayMovement trial) record
      state <- field "state" record
      (mesh, bytes) <- readMesh nameOfTrial state
      unless (mesh == savedMesh (measuredPoint (replayMeasure trial))) (die "saved plane trial differs from its fraction of the proposal")
      let delta = zipWith (\p q -> q ^-^ position p) (samples start) proposal
          change = sum [dot g d | (i, d) <- zip [0 ..] delta, Just g <- [IM.lookup i (planeGradient measure)]]
      nearField 1e-16 "predictedDistance" (planeDistance measure + replayScale trial * change) record
      pair <- field "pair" record
      measured <- checked (measurePlane mesh 27 70)
      nearField 1e-17 "distance" (planeDistance measured) pair
      nearField 1e-17 "margin" (planeDistance measured + 1e-7) pair
      section <- checked (pairSection mesh (46, 70))
      expect "crosses" (sectionCrosses section) pair
      nearField 1e-12 "intersectionLength" (intersectionLength section) pair
      pure ((nameOfTrial, mesh, record), bytes)
    let selectedNames = [name ++ "-" ++ show k | (k, trial) <- zip [0 :: Int ..] replayed, replayScale trial == replayScale selected]
    expect "selectedState" selectedNames direction
    when (name == "control") $ forM_ ["proposal", "correction", "quadratic", "contacts", "selectedScale"] $ \key -> do expected <- field key (shortAttempt archive) :: IO Value; expect key expected direction
    pure ((name, direction, map fst entries), map snd entries)
  -- Return the validated source assets verbatim; the caller decides what to
  -- publish only after this boundary has checked all states.
  let files = ("checks.json", reportBytes) : startFile : concatMap snd directions ++ [("source" </> name, bytes) | (name, bytes) <- shortFiles archive]
      stateNames = "start" : [name | ((_, _, trials), _) <- directions, (name, _, _) <- trials]
  images <- forM [name ++ "-" ++ view ++ ".svg" | name <- stateNames, view <- ["tip", "pair", "side", "top", "underside", "material"]] $ \name -> do bytes <- readArchiveBytes (source </> name); pure (name, bytes)
  pure (PlaneArchive study start report (map fst directions) (files ++ images))

jsonFile :: (FromJSON a) => FilePath -> IO (BL.ByteString, a)
jsonFile path = do bytes <- readArchiveBytes path; value <- either die pure (eitherDecode bytes); pure (bytes, value)

expect :: (Eq a, FromJSON a) => Key -> a -> Value -> IO ()
expect key expected record = do value <- field key record; unless (value == expected) (die ("changed plane archive field: " ++ show key))

nearField :: Double -> Key -> Double -> Value -> IO ()
nearField tolerance key expected record = do value <- field key record; unless (finite value && abs (value - expected) < tolerance) (die ("changed plane archive measurement: " ++ show key))

vector :: [Double] -> IO V3
vector [x, y, z] | all finite [x, y, z] = pure (V3 x y z)
vector _ = die "plane archive needs finite 3D coordinates"

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)
