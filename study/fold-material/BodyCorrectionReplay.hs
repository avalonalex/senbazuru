-- | Numerical line-search candidates from one saved correction direction.
-- Interpolating vertex positions here reproduces a solver trial, NOT an
-- intermediate fold: it can stretch or cross paper. Every trial therefore
-- receives the unchanged endpoint checks before it can be selected.
--
-- A small accepted fraction cannot establish equilibrium. That test belongs
-- to the original full correction, not to the distance after backtracking.
module BodyCorrectionReplay (ReplayCandidate (..), replayFractions, scaledProposal, replayCorrection, firstPassing) where

import BodyPatch
import BodyPatchCheckpoints
import BodyPatchSubdivision (seedPassed)
import Control.Monad (unless)
import CraneSpread
import Data.List (find)
import FoldMaterial (componentCount)
import FoldRelaxation (maxLengthError)
import Senbazuru.Geometry.V3 (V3)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (contactPassed)
import Senbazuru.Origami.Surface

-- | Same finite search budget as FoldRelaxation: full step plus 30 halvings.
replayFractions :: [Double]
replayFractions = [2 ** negate (fromIntegral k) | k <- [0 :: Int .. 30]]

data ReplayCandidate = ReplayCandidate
  { replayScale :: !Double,
    replayMeasure :: !PatchMeasure,
    replayMovement :: !Double,
    replayGeometryPassed :: !Bool,
    replayCostDecreased :: !Bool
  }
  deriving stock (Eq, Show)

-- | Keep material ids and connectivity; reject malformed proposals instead
-- of silently truncating a zip or moving an exact hold back into place.
scaledProposal :: Double -> MaterialMesh -> [V3] -> Either SpreadError MaterialMesh
scaledProposal scale start proposal = do
  unless (finite scale && scale >= 0 && scale <= 1 && length proposal == length (samples start) && all (finite . norm) proposal) (Left (SpreadError "replay needs a finite fraction and one finite proposal per vertex"))
  let positions = zipWith (\p q -> position p ^+^ scale *^ (q ^-^ position p)) (samples start) proposal
  unless (all (finite . norm) positions) (Left (SpreadError "replayed positions are not finite"))
  pure start {samples = zipWith (\p q -> p {position = q}) (samples start) positions}
  where
    finite x = not (isNaN x || isInfinite x)

replayCorrection :: BodyPatch -> MaterialMesh -> [V3] -> Either SpreadError [ReplayCandidate]
replayCorrection study start proposal = do
  full <- scaledProposal 1 start proposal
  unless (spreadHeldError fixture full == 0) (Left (SpreadError "full replay proposal moves an exact hold"))
  validStart <- seedPassed study start
  unless validStart (Left (SpreadError "replay must start from geometry passing the unchanged checks"))
  before <- measurePatch study (SavedPoint 1 start)
  traverse (measure before) replayFractions
  where
    fixture = patchSpread study
    measure before scale = do
      mesh <- scaledProposal scale start proposal
      -- Surface validation includes the source material, shared vertex ids,
      -- triangle validity and metadata; the contact check examines ALL pairs.
      _ <- spreadSurface fixture mesh
      result <- measurePatch study (SavedPoint 2 mesh)
      movement <- savedMovement (measuredPoint before) (measuredPoint result)
      let geometry = componentCount mesh == 1 && spreadHeldError fixture mesh == 0 && maxLengthError mesh <= 1e-5 && contactPassed (measuredContact result)
      pure (ReplayCandidate scale result movement geometry (patchCost 1e8 result < patchCost 1e8 before))

firstPassing :: [ReplayCandidate] -> Maybe ReplayCandidate
firstPassing = find (\candidate -> replayGeometryPassed candidate && replayCostDecreased candidate)
