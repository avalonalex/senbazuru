-- | A held root and a moved grip on one uncreased sheet, before adding the
-- crane's touching layers. The triangular outline resembles one wing; it is
-- a separate test piece, not a disconnected part of the crane fixture.
--
-- Material coordinates stay flat. A circular bend supplies only the initial
-- guess and the grip positions; free vertices are solved by FoldRelaxation.
-- The root and grip occupy fixed material regions at every mesh resolution.
-- A grip angle specifies that held region's orientation, not the angles of
-- the paper between it and the root. No subdivision edge becomes a crease.
--
-- The strip benchmark bends about parallel axes across its width: equal turns
-- between equal spans minimize the sum of squared turns for held end angles
-- within that family. Its reference preserves all triangle lengths exactly.
-- Recovering it from a nearby perturbation checks the study model and boundary
-- controls, not global uniqueness or measured paper physics.
module WingBending (BendingPiece (..), WingError (..), wingPiece, stripBenchmark, solvePiece, finalMesh) where

import Control.Monad (unless)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import FoldBending
import FoldRelaxation
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface

data BendingPiece = BendingPiece
  { pieceMesh :: !MaterialMesh,
    piecePins :: !(IM.IntMap V3),
    pieceRoot :: ![Int],
    pieceGrip :: ![Int],
    pieceHinges :: ![Hinge],
    pieceReference :: !(Maybe MaterialMesh)
  }
  deriving stock (Show)

data WingError = InvalidWingResolution !Int | InvalidGripAngle !Double | WingBendingFailure !BendingError | WingSolveFailure !RelaxError | NoWingCheckpoint
  deriving stock (Eq, Show)

instance Explain WingError where
  explain (InvalidWingResolution n) = "wing resolution must be a multiple of eight, from 8 to 32; got " <> tshow n
  explain (InvalidGripAngle a) = "grip angle must be finite and between 0 and 60 degrees; got " <> tshow a
  explain (WingBendingFailure e) = explain e
  explain (WingSolveFailure e) = explain e
  explain NoWingCheckpoint = "wing solve returned no checkpoint"

wingPiece :: Int -> Double -> Either WingError BendingPiece
wingPiece count degrees = do
  checkCount count
  unless (not (isNaN degrees || isInfinite degrees) && degrees >= 0 && degrees <= 60) (Left (InvalidGripAngle degrees))
  let n = fromIntegral count
      keys = [(i, j) | i <- [0 .. count], j <- [0 .. count - i]]
      ids = M.fromList (zip keys [0 ..])
      vertex key = M.findWithDefault 0 key ids
      material (i, j) = V2 (fromIntegral i / n) ((-0.3) + 0.3 * fromIntegral i / n + 0.6 * fromIntegral j / n)
      points = [Sample uv (curved degrees uv) | key <- keys, let uv = material key]
      cells = concat [(vertex (i, j), vertex (i + 1, j), vertex (i, j + 1)) : [(vertex (i + 1, j), vertex (i + 1, j + 1), vertex (i, j + 1)) | i + j < count - 1] | (i, j) <- keys, i + j < count]
      mesh = Mesh points cells
      root = [idx | (idx, sample) <- zip [0 ..] points, materialU sample <= 0.125]
      grip = [idx | (idx, sample) <- zip [0 ..] points, materialU sample >= 0.875]
      pins = IM.fromList [(idx, position sample) | (idx, sample) <- zip [0 ..] points, idx `elem` (root ++ grip)]
  hinges <- first WingBendingFailure (buildPanelHinges (Bending 1 0.2) mesh)
  pure (BendingPiece mesh pins root grip hinges Nothing)

-- The root and grip stay planar. Only the middle 3/4 of the material length
-- receives this initial cylindrical guess. Chords of its sampled arc are
-- shorter than the material edges; the solve must remove that initial strain.
curved :: Double -> V2 -> V3
curved degrees (V2 u v)
  | degrees == 0 || u <= 0.125 = V3 u v 0
  | otherwise =
      let angle = degrees * pi / 180
          k = angle / 0.75
          s = min 0.75 (u - 0.125)
          extra = max 0 (u - 0.875)
       in V3 (0.125 + sin (k * s) / k + extra * cos angle) v ((1 - cos (k * s)) / k + extra * sin angle)

stripBenchmark :: Int -> Either WingError BendingPiece
stripBenchmark count = do
  checkCount count
  let n = fromIntegral count
      turn = (30 * pi / 180) / (n - 1)
      centers = scanl (^+^) (V3 0 0 0) [V3 (cos (fromIntegral i * turn) / n) 0 (sin (fromIntegral i * turn) / n) | i <- [0 .. count - 1]]
      points = [Sample (V2 (fromIntegral i / n) v) (p ^+^ V3 0 v 0) | (i, p) <- zip [0 :: Int ..] centers, v <- [0, 0.3]]
      cells = concat [[(2 * i, 2 * i + 2, 2 * i + 3), (2 * i, 2 * i + 3, 2 * i + 1)] | i <- [0 .. count - 1]]
      reference = Mesh points cells
      root = [0 .. 3]
      grip = [2 * count - 2 .. 2 * count + 1]
      pins = IM.fromList [(i, position p) | (i, p) <- zip [0 ..] points, i `elem` (root ++ grip)]
      disturbed i p = if IM.member i pins then p else p {position = position p ^+^ V3 0 0 (0.002 * sin (pi * materialU p))}
      mesh = reference {samples = zipWith disturbed [0 ..] points}
  hinges <- first WingBendingFailure (buildPanelHinges (Bending 1 0.2) mesh)
  pure (BendingPiece mesh pins root grip hinges (Just reference))

checkCount :: Int -> Either WingError ()
checkCount n = unless (n >= 8 && n <= 32 && n `mod` 8 == 0) (Left (InvalidWingResolution n))

solvePiece :: BendingPiece -> Either WingError Relaxation
solvePiece piece = first WingSolveFailure (relaxPinnedHinges defaultSettings (piecePins piece) (pieceHinges piece) (pieceMesh piece))

finalMesh :: Relaxation -> Either WingError MaterialMesh
finalMesh result = case reverse (checkpoints result) of
  point : _ -> Right (checkpointMesh point)
  [] -> Left NoWingCheckpoint
