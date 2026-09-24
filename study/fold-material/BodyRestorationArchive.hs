-- | Authenticate the repaired trial before computing a new material direction.
-- A saved contact repair is useful only with its original material, exact holds
-- and refused control. Recompute its algebraic projection as a checksum of the
-- archive, then remeasure the saved vertices; never substitute a new repair.
-- The preceding proposals and all their trials are checked by BodyPlaneArchive.
module BodyRestorationArchive (RestorationArchive (..), RestorationSource (..), readRestorationArchive, checkRestorationArchive) where

import BodyContactDiagnosis
import BodyContactDirection (contactGuard)
import BodyContactRestoration
import BodyCorrectionArchive
import BodyDirectionGallery (pairWitnesses, rowValue)
import BodyPatch
import BodyPatchCheckpoints
import BodyPatchSubdivision (seedPassed)
import BodyPlaneArchive
import BodyPlaneGuard
import BodyShortArchive (checkState)
import Control.Monad (forM, forM_, unless)
import CraneSpread
import Data.Aeson (FromJSON, Value, eitherDecode, object, (.=))
import Data.Aeson.Key (Key)
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.List (zip7)
import Data.Text (Text)
import FoldContact qualified as F
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import SurfaceContact qualified as C
import System.Exit (die)
import System.FilePath ((</>))

data RestorationArchive = RestorationArchive
  { restorationStudy :: BodyPatch,
    restorationMesh :: MaterialMesh,
    restorationReport :: Value,
    restorationFiles :: [(FilePath, BL.ByteString)]
  }

-- | Inputs already authenticated by the preceding direction's reader. This
-- keeps the repair checker independent of which generation supplied them;
-- importing BodyFreshArchive here would create a cycle through its parent.
data RestorationSource = RestorationSource
  { repairStudy :: BodyPatch,
    repairStart :: MaterialMesh,
    repairHalf :: MaterialMesh,
    repairRefused :: MaterialMesh,
    repairReport :: Value,
    repairFiles :: [(FilePath, BL.ByteString)]
  }

readRestorationArchive :: FilePath -> IO RestorationArchive
readRestorationArchive source = do
  parent <- readPlaneArchive (source </> "source")
  controls <- case [trials | ("plane", _, trials) <- planeDirections parent] of [ts] -> pure ts; _ -> die "missing saved plane direction"
  let control name = case [m | (n, m, _) <- controls, n == name] of [m] -> pure m; _ -> die "missing restoration control"
  half <- control "plane-8"
  refused <- control "plane-7"
  checkRestorationArchive source "body-restoration" (RestorationSource (planeStudy parent) (planeStart parent) half refused (planeReport parent) (planeFiles parent))

checkRestorationArchive :: FilePath -> Text -> RestorationSource -> IO RestorationArchive
checkRestorationArchive source gallery parent = do
  (bytes, report) <- jsonFile (source </> "checks.json")
  expect "gallery" gallery report
  expect "source" (repairReport parent) report
  expect "restorationCount" (1 :: Int) report
  forM_ ["newMaterialSolves", "continuationSteps"] $ \key -> expect key (0 :: Int) report
  forM_ ["acceptedEndpoint", "continuousMotionChecked", "wholeCraneChecked"] $ \key -> expect key False report
  forM_ ["guardsPassed", "geometryPassed", "costDecreased", "candidatePassed"] $ \key -> expect key True report
  forM_ [("contactTolerance", 1e-7), ("lengthTolerance", 1e-5), ("guardResidualTolerance", 1e-12), ("lengthWeight", 1e8), ("contactWeight", 1e10)] $ \(key, value) -> expect key (value :: Double) report
  let study = repairStudy parent
      fixture = patchSpread study
      start = repairStart parent
      pins = spreadPins fixture
      displacement a b = IM.fromList (zip [0 ..] (zipWith (\p q -> position q ^-^ position p) (samples a) (samples b)))
      dotRow row delta = sum [dot g (IM.findWithDefault (V3 0 0 0) i delta) | (i, g) <- IM.toList (fst row)]
      margin row delta = snd row + dotRow row delta
  let half = repairHalf parent; refused = repairRefused parent
  initial <- checked (measurePlane start 27 70)
  before <- checked (measurePlane refused 27 70)
  let target = min 0 (planeDistance initial)
  raw <- checked (restorePlane pins target before)
  expect "rawCorrection" [xyz (IM.findWithDefault (V3 0 0 0) i raw) | i <- [0 .. length (samples start) - 1]] report
  expect "gradient" (rowValue (planeGradient before, planeDistance before)) report
  let projected = refused {samples = [p {position = position p ^+^ IM.findWithDefault (V3 0 0 0) i raw} | (i, p) <- zip [0 ..] (samples refused)]}
      named = [("start", start), ("half", half), ("refused", refused), ("restored", projected)]
  records <- field "states" report
  unless (length records == 4) (die "restoration archive lost its controls")
  states <- forM (zip named records) $ \((name, expectedMesh), record) -> do
    expect "id" name record
    (foldBytes, file) <- jsonFile (source </> name ++ ".fold")
    expected <- materialFrame <$> checked (spreadSurface fixture expectedMesh)
    unless (keyFrame file == expected) (die "restoration archive changed geometry, material or metadata")
    -- Equality above binds every saved coordinate to the expected shape before
    -- measuring it. This does not accept regenerated coordinates over the file.
    state <- field "state" record
    expect "id" name state
    checkState study expectedMesh state
    m <- checked (measurePlane expectedMesh 27 70)
    cut <- checked (pairSection expectedMesh (46, 70))
    near "planeDistance" (planeDistance m) record
    near "planeMargin" (planeDistance m + 1e-7) record
    expect "crosses46_70" (sectionCrosses cut) record
    near "intersectionLength" (intersectionLength cut) record
    pure (name ++ ".fold", foldBytes)
  let repaired = projected; installed = displacement refused repaired
  valid <- checked (seedPassed study repaired)
  unless valid (die "saved repair no longer passes geometry")
  model <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) start)
  let witnesses mesh = do ws <- checked (C.contactWitnesses model mesh); pure (concatMap (`pairWitnesses` ws) [(22, 63), (14, 55), (46, 70)])
  ws0 <- witnesses start
  ws1 <- witnesses refused
  ws2 <- witnesses repaired
  let identity w = (C.witnessTriangles w, map fst (F.contactGradient (C.witnessRow w)))
      gap = F.contactGap . C.witnessRow
  unless (length ws0 == 12 && map identity ws0 == map identity ws1 && map identity ws1 == map identity ws2) (die "restoration witness topology changed")
  let old = map (contactGuard pins . C.witnessRow) ws0
      refreshed = map (contactGuard pins . C.witnessRow) ws1
      oldMargins = map (`margin` displacement start repaired) old
      newMargins = map (`margin` installed) refreshed
      originalPlaneMargin = margin (planeGuardRow pins initial) (displacement start repaired)
      restorationPlaneMargin = planeDistance before - target + dotRow (planeGradient before, 0 :: Double) installed
      constraints = [object ["triangles" .= (let (a, b) = C.witnessTriangles a0 in [a, b]), "originalRow" .= rowValue row0, "refreshedRow" .= rowValue row1, "originalLinearMargin" .= m0, "refreshedLinearMargin" .= m1, "originalGap" .= gap a0, "refusedGap" .= gap a1, "restoredGap" .= gap a2] | (a0, a1, a2, row0, row1, m0, m1) <- zip7 ws0 ws1 ws2 old refreshed oldMargins newMargins]
  expect "constraints" constraints report
  unless (all (>= -1e-12) (oldMargins ++ newMargins ++ [originalPlaneMargin, restorationPlaneMargin])) (die "saved restoration guards fail")
  after <- checked (measurePlane repaired 27 70)
  movement <- checked (savedMovement (SavedPoint 0 refused) (SavedPoint 0 repaired))
  mainMovement <- checked (savedMovement (SavedPoint 0 start) (SavedPoint 0 refused))
  costs <- traverse (fmap (patchCost 1e8) . checked . measurePatch study . SavedPoint 0) [start, refused, repaired]
  case costs of
    [baseCost, oldCost, newCost] -> do
      unless (newCost < baseCost) (die "saved repair no longer decreases cost")
      near "costChangeFromTrial" (newCost - oldCost) report
    _ -> die "missing restoration costs"
  forM_ [("targetDistance", target), ("refusedDistance", planeDistance before), ("restoredDistance", planeDistance after), ("predictedDistance", planeDistance before + dotRow (planeGradient before, 0 :: Double) installed), ("correctionMovement", movement), ("mainMovement", mainMovement), ("originalPlaneMargin", originalPlaneMargin), ("restorationPlaneMargin", restorationPlaneMargin)] $ \(key, value) -> near key value report
  images <- forM [name ++ "-" ++ view ++ ".svg" | (name, _) <- named, view <- ["tip", "pair", "side", "top", "underside", "material"]] $ \name -> do imageBytes <- readArchiveBytes (source </> name); pure (name, imageBytes)
  pure (RestorationArchive study repaired report (("checks.json", bytes) : states ++ images ++ [("source" </> name, b) | (name, b) <- repairFiles parent]))

jsonFile :: (FromJSON a) => FilePath -> IO (BL.ByteString, a)
jsonFile path = do bytes <- readArchiveBytes path; value <- either die pure (eitherDecode bytes); pure (bytes, value)

expect :: (Eq a, FromJSON a) => Key -> a -> Value -> IO ()
expect key expected record = do value <- field key record; unless (value == expected) (die ("changed restoration archive field: " ++ show key))

near :: Key -> Double -> Value -> IO ()
near key expected record = do value <- field key record; unless (not (isNaN value || isInfinite value) && abs (value - expected) < 1e-17) (die ("changed restoration archive measurement: " ++ show key))
