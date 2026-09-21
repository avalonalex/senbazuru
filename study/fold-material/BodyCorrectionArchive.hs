-- | Bind the recovered body correction to its saved material and solver trace.
-- Diagnosis and numerical replay must read the same checked archive: otherwise
-- a changed material identity or a trace from another run could look plausible.
-- Read and validate everything before the caller writes any gallery assets.
module BodyCorrectionArchive (CorrectionArchive (..), readCorrectionArchive, separateOutput, field, checked, xyz) where

import BodyPatch
import BodyPatchCheckpoints
import BodyPatchSubdivision (seedPassed)
import Control.Monad (forM, forM_, unless, when)
import CranePocket (buildCranePocket)
import CraneSpread
import Data.Aeson (FromJSON, Value, eitherDecode, toJSON, withObject, (.:))
import Data.Aeson.Key (Key)
import Data.Aeson.Types (parseEither)
import Data.ByteString.Lazy qualified as BL
import Data.List (isPrefixOf)
import Data.Text (Text)
import Data.Text qualified as T
import FoldRelaxation (maxLengthError)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (panelTolerance)
import Senbazuru.Origami.Surface
import System.Directory (canonicalizePath)
import System.Exit (die)
import System.FilePath (splitDirectories, (</>))

data CorrectionArchive = CorrectionArchive
  { archiveStudy :: !BodyPatch,
    archiveStates :: ![(String, BL.ByteString, MaterialMesh, PatchMeasure)],
    archiveTrace :: ![Value],
    archiveFiles :: ![(FilePath, BL.ByteString)]
  }

separateOutput :: FilePath -> FilePath -> IO ()
separateOutput source output = do
  src <- splitDirectories <$> canonicalizePath source
  dst <- splitDirectories <$> canonicalizePath output
  when (src `isPrefixOf` dst || dst `isPrefixOf` src) (die "correction source and output directories must not overlap")

readCorrectionArchive :: FilePath -> IO CorrectionArchive
readCorrectionArchive source = do
  (rawReport, report) <- readJson (source </> "checks.json")
  (rawTrace, trace) <- readJson (source </> "trace.json")
  expect "gallery" ("body-subdivision" :: Text) report
  expect "lengthWeight" (1e8 :: Double) report
  expect "contactMultiplier" (100 :: Int) report
  expect "lengthTolerance" (1e-5 :: Double) report
  expect "contactTolerance" panelTolerance report
  expect "seedPassed" True report
  continuation <- field "continuation" report
  expect "trace" (trace :: [Value]) continuation
  crane <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= checked)
  atlas <- checked (buildCranePocket crane)
  study <- checked (bodyPatch atlas 1 5)
  let fixture = patchSpread study; base = spreadMesh fixture
  states <- field "states" report :: IO [Value]
  inputs <- forM ["seed", "step-1", "step-2"] $ \name -> do
    (raw, file) <- readJson (source </> name ++ ".fold")
    let frame = keyFrame file
    ps <- traverse vector (verticesCoords frame)
    unless (length ps == length (samples base)) (die "saved vertex count changed")
    let mesh = base {samples = zipWith (\p q -> p {position = q}) (samples base) ps}
    expected <- materialFrame <$> checked (spreadSurface fixture mesh)
    unless (frame == expected && spreadHeldError fixture mesh == 0) (die "saved material, topology, metadata or exact holds changed")
    entry <- case [s | s <- states, parseEither (withObject "state" (.: "id")) s == Right (T.pack name)] of
      [s] -> pure s
      _ -> die "missing or duplicated saved state"
    measured <- checked (measurePatch study (SavedPoint 0 mesh))
    expect "contact" (toJSON (measuredContact measured)) entry
    forM_ [("maxRelativeEdgeError", maxLengthError mesh), ("creaseEnergy", measuredCrease measured), ("panelEnergy", measuredPanel measured), ("totalCost", patchCost 1e8 measured)] $ \(key, value) -> do
      original <- field key entry
      unless (abs (original - value) <= 1e-12 * max 1 (abs value)) (die "saved measurements disagree with geometry")
    pure (name, raw, mesh, measured)
  case (inputs, trace) of
    ([(_, _, seed, _), (_, _, a, _), (_, _, b, _)], s1 : s2 : _) -> do
      valid <- checked (seedPassed study seed)
      unless valid (die "saved seed no longer passes")
      verifyStep study 1 seed a s1
      verifyStep study 2 a b s2
      expect "scale" (0.25 :: Double) s2
    _ -> die "expected seed, two checkpoints and two trace entries"
  pure (CorrectionArchive study inputs trace (("checks.json", rawReport) : ("trace.json", rawTrace) : [(name ++ ".fold", raw) | (name, raw, _, _) <- inputs]))

verifyStep :: BodyPatch -> Int -> MaterialMesh -> MaterialMesh -> Value -> IO ()
verifyStep study number before after record = do
  forM_ [("beforeEnergy", before), ("candidateEnergy", after)] $ \(key, mesh) -> do
    measured <- checked (measurePatch study (SavedPoint 0 mesh))
    recorded <- field key record
    unless (abs (recorded - 2 * patchCost 1e8 measured) < 1e-12) (die "saved trace energy disagrees with positions")
  expect "iteration" number record
  expect "start" (map (xyz . position) (samples before)) record
  expect "candidate" (map (xyz . position) (samples after)) record
  proposal <- field "fullProposal" record >>= traverse vector
  scale <- field "scale" record
  unless (length proposal == length (samples before) && scale > 0 && scale <= (1 :: Double)) (die "invalid saved proposal")
  let proposedMesh = before {samples = zipWith (\p q -> p {position = q}) (samples before) proposal}
  equilibrium <- field "equilibrium" record
  expect "movementThreshold" (1e-7 :: Double) equilibrium
  recordedMovement <- field "fullMovement" equilibrium
  movement <- checked (savedMovement (SavedPoint 0 before) (SavedPoint 0 proposedMesh))
  unless (abs (movement - recordedMovement) < 1e-12) (die "saved full movement disagrees with proposal")
  unless (spreadHeldError (patchSpread study) proposedMesh == 0) (die "saved full proposal moves an exact hold")
  let expected = zipWith (\p q -> position p ^+^ scale *^ (q ^-^ position p)) (samples before) proposal
  unless (and (zipWith (\p q -> norm (p ^-^ position q) < 1e-12) expected (samples after))) (die "saved candidate differs from scaled full proposal")

xyz :: V3 -> [Double]
xyz (V3 x y z) = [x, y, z]

vector :: [Double] -> IO V3
vector [x, y, z] | all (\q -> not (isNaN q || isInfinite q)) [x, y, z] = pure (V3 x y z)
vector _ = die "saved positions need three finite coordinates"

readJson :: (FromJSON a) => FilePath -> IO (BL.ByteString, a)
readJson path = do bytes <- BL.readFile path; value <- either die pure (eitherDecode bytes); pure (bytes, value)

field :: (FromJSON a) => Key -> Value -> IO a
field key = either die pure . parseEither (withObject "saved archive" (.: key))

expect :: (Eq a, FromJSON a) => Key -> a -> Value -> IO ()
expect key expected record = do actual <- field key record; unless (actual == expected) (die ("changed archive field: " ++ show key))

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
