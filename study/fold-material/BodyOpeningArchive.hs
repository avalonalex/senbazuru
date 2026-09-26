-- | Read the saved larger-opening experiment without running or drawing it.
-- The raw checkpoints are authoritative: reconstruct the authored material and
-- controls, then require saved positions to preserve those identities and exact
-- holds. Sharing this reader keeps a visual inspection from accidentally
-- rebuilding a different body or running another optimizer.
module BodyOpeningArchive (OpeningArchive (..), openingInputs, readOpeningArchive) where

import BodyCorrectionArchive
import BodyLargerOpening (openingGuess)
import BodyPatch
import BodyPatchCheckpoints (SavedPoint (..))
import Control.Monad (forM, forM_, unless)
import CranePocket (buildCranePocket)
import CraneSpread
import Data.Aeson (Value, eitherDecode)
import Data.IntMap.Strict qualified as IM
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types (keyFrame)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface
import System.Exit (die)
import System.FilePath ((</>))

data OpeningArchive = OpeningArchive
  { openingOld :: !BodyPatch,
    openingTarget :: !BodyPatch,
    openingSeed :: !MaterialMesh,
    openingInitial :: !MaterialMesh,
    openingRun :: !Value,
    openingPoints :: ![SavedPoint]
  }

openingInputs :: CorrectionArchive -> IO (BodyPatch, BodyPatch, MaterialMesh, MaterialMesh)
openingInputs archive = do
  seed <- case archiveStates archive of
    ("seed", _, mesh, _) : _ -> pure mesh
    _ -> die "missing recovered seed"
  crane <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= checked)
  atlas <- checked (buildCranePocket crane)
  target <- checked (bodyPatch atlas 1 10)
  let old = archiveStudy archive
  guess <- checked (openingGuess old target seed)
  -- The reference for contact measurements is the same guess used by the
  -- solver. The material reference remains spreadRefined, unchanged.
  pure (old, target {patchSpread = (patchSpread target) {spreadMesh = guess}}, seed, guess)

readOpeningArchive :: FilePath -> IO OpeningArchive
readOpeningArchive output = do
  archive <- readCorrectionArchive (output </> "source")
  (old, target, seed, guess) <- openingInputs archive
  raw <- readArchiveBytes (output </> "run.json")
  run <- either die pure (eitherDecode raw :: Either String Value)
  forM_ [("issue", 393), ("targetDegrees", 10), ("iterationLimit", 40), ("lengthWeight", 1e8), ("contactWeight", 1e10)] $ \(key, expected) -> do
    actual <- field key run
    unless (actual == (expected :: Double)) (die "opening archive settings changed")
  initialBytes <- readArchiveBytes (output </> "initial.json")
  initial <- either die pure (eitherDecode initialBytes :: Either String Value)
  forM_ [("seed", seed), ("guess", guess)] $ \(key, mesh) -> do
    positions <- field key initial
    unless (positions == map (xyz . position) (samples mesh)) (die "opening archive initial material construction changed")
  pins <- field "pins" initial
  unless (pins == [(i, xyz p) | (i, p) <- IM.toList (spreadPins (patchSpread target))]) (die "opening archive controls changed")
  result <- field "result" run
  records <- field "points" result :: IO [Value]
  points <- forM records $ \r -> do
    i <- field "iteration" r
    coords <- field "positions" r
    ps <- traverse vector coords
    unless (length ps == length (samples guess)) (die "saved checkpoint vertex count changed")
    let mesh = guess {samples = zipWith (\p q -> p {position = q}) (samples guess) ps}
    _ <- checked (spreadSurface (patchSpread target) mesh)
    unless (spreadHeldError (patchSpread target) mesh == 0) (die "saved checkpoint moved a declared hold")
    pure (SavedPoint i mesh)
  pure (OpeningArchive old target seed guess run points)

vector :: [Double] -> IO V3
vector [x, y, z] | all (\q -> not (isNaN q || isInfinite q)) [x, y, z] = pure (V3 x y z)
vector _ = die "expected three finite coordinates"
