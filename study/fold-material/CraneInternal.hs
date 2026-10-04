-- | Isolate the mountain folds inside the released crane body patch.
-- A mountain crease bends the paper's front side outward; here every such
-- fold starts fully closed. They are found by rule, not named (owner decision
-- 37): every mountain crease with both panels in the patch. With the wing
-- hinged at y = 1/4 that is two, 26 and 51, joining panels 8/27 and 7/43;
-- hinged at its root, four, 28, 30, 55 and 57.
-- Each subdivided crease has nine shared vertices at 1/4, but the old boundary
-- holds only its far end. Holding the remaining line vertices is a diagnostic
-- of crease-line bending, not a new material law. See docs/glossary.md.
--
-- Independently restrict solver contact forces to those creases' panel pairs.
-- All source orders still survive in the fixture and independent endpoint
-- check. A reduced-force solve is always a diagnostic: passing geometric
-- checks would not establish equilibrium with the omitted contacts present.
module CraneInternal
  ( InternalControl (..),
    InternalStudy (..),
    internalStudy,
    internalStudyAt,
    internalLineVertices,
    internalRequirements,
    fullInternalForces,
    internalAccepted,
    internalAcceptable,
    solveInternal,
    continueInternal,
  )
where

import Control.Monad (unless, when)
import CraneRoot
import CraneSpread
import CraneWing (studyHinge)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (sortOn)
import Data.Set qualified as S
import FoldRelaxation
import Senbazuru.Explain (explain, tshow)
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
    -- | The mountain creases inside the released patch, in id order.
    internalCreases :: ![EdgeId],
    -- | The one contact order between each crease's two panels, in the same
    -- order as the creases.
    internalPairs :: ![(FaceId, FaceId)]
  }
  deriving stock (Show)

-- | The study with the wing hinged at y = 1/4.
internalStudy :: Frame -> InternalControl -> Either SpreadError InternalStudy
internalStudy = internalStudyAt studyHinge

-- | The study with the wing hinged at @hingeY@. A crease with no contact
-- order between its panels, or more than one, is refused rather than guessed.
internalStudyAt :: Double -> Frame -> InternalControl -> Either SpreadError InternalStudy
internalStudyAt hingeY source control = do
  root <- craneRootAt hingeY source 3 (if control == FixedPatch then FlatRoot else FreeBody)
  features <- first (SpreadError . explain) (surfaceFeatures (spreadSource (rootSpread root)))
  let interior = sortOn fst [(creaseId edge, owners) | (edge, owners) <- features, creaseAssignment edge == Mountain, all (`S.member` rootNeighbours root) owners]
      wanted = S.fromList (map fst interior)
      fixture = rootSpread root
      between owners (a, b) = S.fromList owners == S.fromList [a, b]
  -- A fixed-body reference has no force rows between these held panels.
  -- Obtain their orientation from the same fixture with its body released.
  free <- if control == FixedPatch then craneRootAt hingeY source 3 FreeBody else pure root
  let orders = spreadContactOrders (rootSpread free)
      vertices = S.fromList [v | (eid, (a, b)) <- refinedEdges (spreadRefined fixture), S.member eid wanted, v <- [a, b]]
      holds = IM.fromList [(i, position p) | (i, p) <- zip [0 ..] (samples (refinedMesh (spreadRefined fixture))), S.member i vertices]
      pins = if control `elem` [HeldLines, HeldLinesInternalForces] then IM.union (spreadPins fixture) holds else spreadPins fixture
      pairFor (eid, owners) = case filter (between owners) orders of
        [pair] -> Right pair
        found -> Left (SpreadError ("crease " <> tshow (unEdgeId eid) <> " inside the released patch has " <> tshow (length found) <> " contact orders between its panels, not one"))
  when (null interior) (Left (SpreadError "no mountain crease lies inside the released patch"))
  pairs <- traverse pairFor interior
  -- Force selection is applied after holds: the full control may drop newly
  -- constant pairs, but never discard a required order involving free paper.
  let changed = root {rootSpread = fixture {spreadPins = pins}}
  pure (InternalStudy changed control (map fst interior) pairs)

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
  pure (internalAcceptable study && valid)

-- | Whether 'internalAccepted' could accept this control at all, whatever its
-- solve: one that leaves out contact forces never is. A control it never
-- accepts skips the base angle's 1° check (owner decision 36).
internalAcceptable :: InternalStudy -> Bool
internalAcceptable = fullInternalForces

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
