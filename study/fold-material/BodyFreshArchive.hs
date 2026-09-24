-- | Read the saved fresh material direction without solving it again.
-- A follow-up repair must use that direction's start and fractions, not the
-- visually indistinguishable states from the preceding experiment. Rebuild
-- material and contact rows, verify the saved force balance, replay all 31
-- fractions and bind each FOLD file to its material and actual measurements.
-- Force balance means material gradients, damping and recorded contact forces
-- cancel within the original numerical limit; it does not settle the paper.
-- The source restoration and older controls are checked by their own reader.
-- Only a verified archive returns bytes for a later gallery to publish.
module BodyFreshArchive (FreshArchive (..), readFreshArchive) where

import BodyContactDiagnosis
import BodyContactDirection
import BodyCorrectionArchive
import BodyCorrectionReplay
import BodyDirectionGallery (pairWitnesses, rowValue)
import BodyPatch
import BodyPatchCheckpoints
import BodyPlaneGuard
import BodyRestorationArchive
import BodyShortArchive (checkState)
import Control.Monad (forM, forM_, unless)
import CraneSpread
import Data.Aeson (FromJSON, Value, eitherDecode, object, (.=))
import Data.Aeson.Key (Key)
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import FoldContact qualified as F
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import SurfaceContact qualified as C
import System.Exit (die)
import System.FilePath ((</>))

data FreshArchive = FreshArchive
  { freshStudy :: BodyPatch,
    freshStart :: MaterialMesh,
    freshReport :: Value,
    freshDirections :: [(String, Value, [(String, MaterialMesh, Value)])],
    freshFiles :: [(FilePath, BL.ByteString)]
  }

readFreshArchive :: FilePath -> IO FreshArchive
readFreshArchive source = do
  archive <- readRestorationArchive (source </> "source")
  (reportBytes, report) <- jsonFile (source </> "checks.json")
  expect "gallery" ("body-fresh" :: Text) report
  expect "newRestorations" (0 :: Int) report
  expect "newQuadratics" (1 :: Int) report
  expect "continuationSteps" (0 :: Int) report
  forM_ ["continuousMotionChecked", "wholeCraneChecked"] $ \key -> expect key False report
  forM_ [("contactTolerance", 1e-7), ("lengthTolerance", 1e-5), ("movementTolerance", 1e-7), ("lengthWeight", 1e8), ("contactWeight", 1e10), ("damping", 1e-3)] $ \(key, x) -> expect key (x :: Double) report
  expect "quadraticBudget" (100 :: Int) report
  expect "drawingScale" (600 :: Double) report
  expect "source" (restorationReport archive) report
  let start = restorationMesh archive
      study = restorationStudy archive
      fixture = patchSpread study
      pins = spreadPins fixture
      free = [i | i <- [0 .. length (samples start) - 1], IM.notMember i pins]
  expect "freeVertices" free report
  model <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) start)
  allWitnesses <- checked (C.contactWitnesses model start)
  let ws = concatMap (`pairWitnesses` allWitnesses) [(22, 63), (14, 55), (46, 70)]
      guards = map (contactGuard pins . C.witnessRow) ws
      constraints = [object ["triangles" .= (let (a, b) = C.witnessTriangles w in [a, b]), "rawGap" .= F.contactGap (C.witnessRow w), "floor" .= min 0 (F.contactGap (C.witnessRow w)), "lower" .= xyz (C.witnessLower w), "upper" .= xyz (C.witnessUpper w), "row" .= rowValue row] | (w, row) <- zip ws guards]
  unless (length guards == 12) (die "fresh archive lost overlap guards")
  rows <- checked (directionRows (spreadHinges fixture) pins model start)
  expect "materialRows" (map rowValue rows) report
  expect "constraints" constraints report
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
        unless (length ps == length (samples start)) (die "fresh archive vertex count changed")
        let mesh = start {samples = zipWith (\p q -> p {position = q}) (samples start) ps}
        expected <- materialFrame <$> checked (spreadSurface fixture mesh)
        unless (keyFrame file == expected) (die "fresh archive material, topology or metadata changed")
        expect "id" name state
        checkState study mesh state
        pure (mesh, (name ++ ".fold", bytes))
  startRecord <- field "start" report
  (startMesh, startFile) <- readMesh "start" startRecord
  unless (startMesh == start) (die "fresh archive started from another shape")
  directionRecords <- field "directions" report
  unless (length directionRecords == 1) (die "expected one saved fresh direction")
  directions <- forM (zip ["fresh"] directionRecords) $ \(name, direction) -> do
    expect "id" name direction
    expect "usesPlaneGuard" True direction
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
    let delta = IM.fromList (zip [0 ..] raw)
        zero = V3 0 0 0
        at i = IM.findWithDefault zero i delta
        residual (gradient, r) = r + sum [dot g (at i) | (i, g) <- IM.toList gradient]
        inequalities = guards ++ [planeGuardRow pins measure]
        materialForce = IM.unionsWith (^+^) (IM.map (1e-3 *^) delta : [IM.map (residual row *^) g | row@(g, _) <- rows])
    unless (all (\i -> at i == zero) (IM.keys pins)) (die "fresh raw direction moves a hold")
    savedContacts <- field "contacts" direction
    unless (length savedContacts == length inequalities) (die "fresh archive lost contact details")
    forces <- forM (zip3 [0 :: Int ..] inequalities savedContacts) $ \(i, row, contact) -> do
      expect "sources" [i] contact
      multiplier <- field "multiplier" contact
      scale <- field "responseScale" contact
      active <- field "selected" contact
      let gap = residual row
      unless (finite multiplier && multiplier >= 0 && finite scale && scale > 0 && finite gap && gap >= -1e-12 && (if active then abs gap <= 1e-12 else multiplier == 0)) (die "fresh archive contact forces fail their guards")
      nearField 1e-12 "gap" gap contact
      pure (active, IM.map ((multiplier / scale) *^) (fst row))
    expect "active" (length (filter fst forces)) quadratic
    let force = IM.unionWith (^+^) materialForce (IM.map ((-1) *^) (IM.unionsWith (^+^) (map snd forces)))
        balance = sqrt (sum [dot v v | i <- free, Just v <- [IM.lookup i force]])
    unless (finite balance && balance <= 1e-6) (die "fresh archive force balance fails")
    nearField 1e-7 "balance" balance quadratic
    full <- checked (scaledProposal 1 start proposal)
    movement <- checked (savedMovement (SavedPoint 0 start) (SavedPoint 0 full))
    nearField 1e-14 "fullMovement" movement direction
    unless (movement > 1e-7) (die "archived full movement already meets equilibrium")
    replayed <- checked (replayCorrection study start proposal)
    selected <- maybe (die "saved direction has no passing trial") pure (firstPassing replayed)
    expect "selectedScale" (replayScale selected) direction
    records <- field "trials" direction
    unless (length records == 31) (die "fresh archive lost trial fractions")
    entries <- forM (zip3 [0 :: Int ..] replayed records) $ \(k, trial, record) -> do
      let nameOfTrial = name ++ "-" ++ show k
      expect "scale" (replayScale trial) record
      expect "geometryPassed" (replayGeometryPassed trial) record
      expect "costDecreased" (replayCostDecreased trial) record
      nearField 1e-14 "movement" (replayMovement trial) record
      state <- field "state" record
      (mesh, bytes) <- readMesh nameOfTrial state
      unless (mesh == savedMesh (measuredPoint (replayMeasure trial))) (die "saved fresh trial differs from its fraction of the proposal")
      let proposalDelta = zipWith (\p q -> q ^-^ position p) (samples start) proposal
          change = sum [dot g d | (i, d) <- zip [0 ..] proposalDelta, Just g <- [IM.lookup i (planeGradient measure)]]
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
    pure ((name, direction, map fst entries), map snd entries)
  -- Return the validated source assets verbatim; the caller decides what to
  -- publish only after this boundary has checked all states.
  let files = ("checks.json", reportBytes) : startFile : concatMap snd directions ++ [("source" </> name, bytes) | (name, bytes) <- restorationFiles archive]
      stateNames = "start" : [name | ((_, _, trials), _) <- directions, (name, _, _) <- trials]
  images <- forM [name ++ "-" ++ view ++ ".svg" | name <- stateNames, view <- ["tip", "pair", "side", "top", "underside", "material"]] $ \name -> do bytes <- readArchiveBytes (source </> name); pure (name, bytes)
  pure (FreshArchive study start report (map fst directions) (files ++ images))

jsonFile :: (FromJSON a) => FilePath -> IO (BL.ByteString, a)
jsonFile path = do bytes <- readArchiveBytes path; value <- either die pure (eitherDecode bytes); pure (bytes, value)

expect :: (Eq a, FromJSON a) => Key -> a -> Value -> IO ()
expect key expected record = do value <- field key record; unless (value == expected) (die ("changed fresh archive field: " ++ show key))

nearField :: Double -> Key -> Double -> Value -> IO ()
nearField tolerance key expected record = do value <- field key record; unless (finite value && abs (value - expected) < tolerance) (die ("changed fresh archive measurement: " ++ show key))

vector :: [Double] -> IO V3
vector [x, y, z] | all finite [x, y, z] = pure (V3 x y z)
vector _ = die "fresh archive needs finite 3D coordinates"

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)
