-- | Bind the recovered body correction to its saved material and solver trace.
-- Diagnosis and numerical replay must read the same checked archive: otherwise
-- a changed material identity or a trace from another run could look plausible.
-- Read and validate everything before the caller writes any gallery assets.
module BodyCorrectionArchive (CorrectionArchive (..), BlockedArchive (..), readCorrectionArchive, readBlockedArchive, separateOutput, field, checked, xyz) where

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

data BlockedArchive = BlockedArchive
  { blockedStudy :: !BodyPatch,
    blockedMesh :: !MaterialMesh,
    blockedProposal :: ![V3],
    blockedRecord :: !Value,
    blockedFiles :: ![(FilePath, BL.ByteString)]
  }

-- | Bind the new direction comparison to the last refused search in #328.
-- Validate the whole returned chain, including the unchanged final shape;
-- a plausible endpoint alone would not identify the proposal that stalled.
readBlockedArchive :: FilePath -> IO BlockedArchive
readBlockedArchive source = do
  archive <- readCorrectionArchive (source </> "source")
  (rawReport, report) <- readJson (source </> "checks.json")
  (rawTrace, trace) <- readJson (source </> "trace.json")
  expect "gallery" ("body-geometry" :: Text) report
  forM_ [("lengthWeight", 1e8), ("contactWeight", 1e10), ("lengthTolerance", 1e-5), ("contactTolerance", 1e-7), ("movementTolerance", 1e-7)] $ \(key, value) -> expect key (value :: Double) report
  expect "iterationLimit" (40 :: Int) report
  expect "sourceIteration" (1 :: Int) report
  expect "blockedIterations" [8 :: Int] report
  expect "converged" False report
  expect "acceptedEndpoint" False report
  unless (length trace == 8) (die "expected eight saved body corrections")
  let study = archiveStudy archive; fixture = patchSpread study; base = spreadMesh fixture
  inputs <- forM [0 .. 8 :: Int] $ \i -> do
    let name = "step-" ++ show i ++ ".fold"
    (raw, file) <- readJson (source </> name)
    ps <- traverse vector (verticesCoords (keyFrame file))
    unless (length ps == length (samples base)) (die "blocked archive vertex count changed")
    let mesh = base {samples = zipWith (\p q -> p {position = q}) (samples base) ps}
    expected <- materialFrame <$> checked (spreadSurface fixture mesh)
    valid <- checked (seedPassed study mesh)
    unless (valid && keyFrame file == expected) (die "blocked archive material or geometry changed")
    pure (name, raw, mesh)
  forM_ (zip3 [1 ..] (zip inputs (drop 1 inputs)) trace) $ \(i, ((_, _, before), (_, _, after)), record) ->
    if i < (8 :: Int)
      then verifyStep study i before after record
      else do
        unless (before == after) (die "blocked search installed a correction")
        expect "iteration" i record
        expect "start" (map (xyz . position) (samples before)) record
        expect "scale" (Nothing :: Maybe Double) record
        refused <- field "refusals" record :: IO [Value]
        unless (length refused == 31) (die "blocked search must retain all 31 refusals")
        forM_ (zip [0 :: Int ..] refused) $ \(k, trial) -> expect "scale" (2 ** negate (fromIntegral k) :: Double) trial
        beforeCost <- checked (measurePatch study (SavedPoint i before))
        recorded <- field "beforeEnergy" record
        unless (abs (recorded - 2 * patchCost 1e8 beforeCost) < 1e-12) (die "blocked starting cost changed")
  case (inputs, reverse inputs, reverse trace, archiveStates archive) of
    ((_, _, firstMesh) : _, (_, _, lastMesh) : _, record : _, [_, (_, _, originalStart, _), _]) -> do
      unless (firstMesh == originalStart) (die "body geometry continuation started from another archive")
      proposal <- field "fullProposal" record >>= traverse vector
      unless (length proposal == length (samples base)) (die "blocked proposal vertex count changed")
      let full = lastMesh {samples = zipWith (\p q -> p {position = q}) (samples lastMesh) proposal}
      unless (spreadHeldError fixture full == 0) (die "blocked proposal moves a hold")
      movement <- checked (savedMovement (SavedPoint 0 lastMesh) (SavedPoint 0 full))
      equilibrium <- field "equilibrium" record
      expect "movementThreshold" (1e-7 :: Double) equilibrium
      expect "linearConverged" True equilibrium
      recorded <- field "fullMovement" equilibrium
      unless (movement > 1e-7 && abs (movement - recorded) < 1e-12) (die "blocked full movement changed")
      pure (BlockedArchive study lastMesh proposal record (("checks.json", rawReport) : ("trace.json", rawTrace) : [(name, raw) | (name, raw, _) <- inputs] ++ [("source" </> name, bytes) | (name, bytes) <- archiveFiles archive]))
    _ -> die "incomplete blocked body archive"

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
