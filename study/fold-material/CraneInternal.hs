-- | Isolate the two mountain folds inside the released crane body patch.
-- A mountain crease bends the paper's front side outward; here both folds
-- start fully closed. Their material edges join panels 8/27 and 7/43.
-- Each subdivided crease has nine shared vertices, but the old boundary holds
-- only its far end. Holding the remaining line vertices is a diagnostic of
-- crease-line bending, not a new material law. See docs/glossary.md.
--
-- Independently restrict solver contact forces to those two panel pairs.
-- All source orders still survive in the fixture and independent endpoint
-- check. A reduced-force solve is always a diagnostic: passing geometric
-- checks would not establish equilibrium with the omitted contacts present.
module CraneInternal
  ( InternalControl (..),
    InternalStudy (..),
    internalStudy,
    internalCreases,
    internalLineVertices,
    internalRequirements,
    fullInternalForces,
    internalAccepted,
    solveInternal,
    continueInternal,
  )
where

import Control.Monad (unless)
import CraneRoot
import CraneSpread
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Set qualified as S
import FoldRelaxation
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Query (Crease (..))
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface
import SurfaceContact qualified as Contact

data InternalControl = OriginalPatch | HeldLines | InternalForces | HeldLinesInternalForces | FixedPatch | ContinuedPatch
  deriving stock (Eq, Show)

data InternalStudy = InternalStudy
  { internalRoot :: !CraneRoot,
    internalControl :: !InternalControl,
    internalPairs :: ![(FaceId, FaceId)]
  }
  deriving stock (Show)

internalStudy :: Frame -> InternalControl -> Either SpreadError InternalStudy
internalStudy source control = do
  root <- craneRoot source 3 (if control == FixedPatch then FlatRoot else FreeBody)
  features <- first (SpreadError . explain) (surfaceFeatures (spreadSource (rootSpread root)))
  let interior = [(creaseId edge, owners) | (edge, owners) <- features, creaseAssignment edge == Mountain, all (`S.member` rootNeighbours root) owners]
      wanted = S.fromList (map EdgeId [26, 51])
      fixture = rootSpread root
      matches (a, b) = any (\(_, owners) -> S.fromList owners == S.fromList [a, b]) interior
  -- A fixed-body reference has no force rows between these held panels.
  -- Obtain their orientation from the same fixture with its body released.
  free <- if control == FixedPatch then craneRoot source 3 FreeBody else pure root
  let pairs = filter matches (spreadContactOrders (rootSpread free))
      vertices = S.fromList [v | (eid, (a, b)) <- refinedEdges (spreadRefined fixture), S.member eid wanted, v <- [a, b]]
      holds = IM.fromList [(i, position p) | (i, p) <- zip [0 ..] (samples (refinedMesh (spreadRefined fixture))), S.member i vertices]
      pins = if control `elem` [HeldLines, HeldLinesInternalForces] then IM.union (spreadPins fixture) holds else spreadPins fixture
  unless (S.fromList (map fst interior) == wanted && length pairs == 2) (Left (SpreadError "expected internal mountain creases 26 and 51 and their two retained panel orders"))
  -- Force selection is applied after holds: the full control may drop newly
  -- constant pairs, but never discard a required order involving free paper.
  let changed = root {rootSpread = fixture {spreadPins = pins}}
  pure (InternalStudy changed control pairs)

internalCreases :: [EdgeId]
internalCreases = map EdgeId [26, 51]

internalLineVertices :: InternalStudy -> EdgeId -> S.Set Int
internalLineVertices study eid = S.fromList [v | (source, (a, b)) <- refinedEdges (spreadRefined fixture), source == eid, v <- [a, b]]
  where
    fixture = rootSpread (internalRoot study)

internalRequirements :: InternalStudy -> [(FaceId, FaceId)]
internalRequirements study
  | not (fullInternalForces study) = internalPairs study
  | otherwise = spreadContactOrders (rootSpread (internalRoot study))

fullInternalForces :: InternalStudy -> Bool
fullInternalForces study = internalControl study `notElem` [InternalForces, HeldLinesInternalForces]

internalAccepted :: InternalStudy -> Relaxation -> MaterialMesh -> Either SpreadError Bool
internalAccepted study result mesh = do
  valid <- rootAccepted (internalRoot study) result mesh
  pure (fullInternalForces study && valid)

solveInternal :: Settings -> InternalStudy -> Either SpreadError (Relaxation, TrialDiagnostics)
solveInternal settings study = do
  let fixture = rootSpread (internalRoot study)
  contact <- first (SpreadError . explain) (Contact.prepareContact 0 (V3 0 0 1) (internalRequirements study) (refinedPanels (spreadRefined fixture)) (spreadMesh fixture))
  first (SpreadError . explain) (diagnosePinnedContact settings (spreadPins fixture) (spreadHinges fixture) contact (spreadMesh fixture))

-- | An exhausted endpoint may still be improving. Continue only at the final
-- numerical penalty, keeping the same material, holds, springs and orders.
continueInternal :: Settings -> InternalStudy -> MaterialMesh -> Either SpreadError (Relaxation, TrialDiagnostics)
continueInternal settings study mesh = do
  let fixture = rootSpread (internalRoot study)
  _ <- spreadCheck fixture mesh
  unless (spreadHeldError fixture mesh == 0) (Left (SpreadError "a continued crane diagnostic must preserve every held position"))
  contact <- first (SpreadError . explain) (Contact.prepareContact 0 (V3 0 0 1) (internalRequirements study) (refinedPanels (spreadRefined fixture)) mesh)
  first (SpreadError . explain) (continuePinnedContact settings (spreadPins fixture) (spreadHinges fixture) contact mesh)
