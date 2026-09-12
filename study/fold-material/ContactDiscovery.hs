-- | Learn directional panel order from a separated reference pose.
-- Panels are the original regions between crease lines, before triangulation.
-- Where their projected footprints overlap, the reference geometry can say
-- which panel is above the other. That decision is fixed for the whole solve:
-- re-inferring it from an intersecting candidate could legitimise a crossing.
-- The direction belongs to the model, never the camera or paper colour.
--
-- SurfaceContact finds current triangle overlaps and supplies their moving
-- derivatives. This module owns the HISTORY policy: what the reference pose
-- established, and whether that knowledge covers a later overlap. A new pair
-- needs an order already implied by the reference, or it is refused. Coplanar,
-- crossed and uncheckable reference overlaps are errors, not guesses by id.
--
-- This intentionally studies contacts between distinct source panels only.
-- It does not discover general self-contact within a bent panel, infer a route
-- around another flap, or certify the continuous motion between iterates.
module ContactDiscovery
  ( ReferenceContact,
    DiscoveryError (..),
    discoverReference,
    referenceOrders,
    referenceCandidates,
    discoveredContacts,
  )
where

import Control.Monad (unless)
import Data.Bifunctor (first)
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Text (Text)
import FoldContact (ContactRow, contactTolerance)
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Types (FaceId)
import Senbazuru.Geometry.V3 (V3)
import Senbazuru.Origami.Surface (MaterialMesh)
import SurfaceContact

-- The constructor is private: callers cannot replace the reference orders
-- halfway through correction while continuing to claim the same history.
data ReferenceContact = ReferenceContact
  { savedOrders :: ![(FaceId, FaceId)],
    savedCandidates :: ![ContactCandidate],
    referenceAxis :: !V3,
    referenceOwners :: ![FaceId],
    referenceModel :: !OrderedContact
  }
  deriving stock (Eq, Show)

-- Ordinary accessor functions, not exported record fields: exporting a field
-- would also permit record updates that bypass the private constructor.
referenceOrders :: ReferenceContact -> [(FaceId, FaceId)]
referenceOrders = savedOrders

referenceCandidates :: ReferenceContact -> [ContactCandidate]
referenceCandidates = savedCandidates

data DiscoveryError
  = DiscoveryGeometry !ContactError
  | AmbiguousReferenceOrder !FaceId !FaceId
  | CrossedReferencePanels !FaceId !FaceId
  | UncheckableReferenceOrder !FaceId !FaceId
  | NewContactPair !FaceId !FaceId
  deriving stock (Eq, Show)

instance Explain DiscoveryError where
  explain (DiscoveryGeometry err) = explain err
  explain (AmbiguousReferenceOrder a b) = pairName a b <> " overlap without a resolvable above/below order in the reference pose; supply a separated reference"
  explain (CrossedReferencePanels a b) = pairName a b <> " cross or have inconsistent directional order in the reference pose; correction cannot infer their history"
  explain (UncheckableReferenceOrder a b) = pairName a b <> " have a reference overlap that cannot be measured along the supplied direction"
  explain (NewContactPair a b) = pairName a b <> " now overlap, but the reference pose established no order between them; this contact needs another reference or an explicit order"

pairName :: FaceId -> FaceId -> Text
pairName a b = "panels " <> tshow a <> " and " <> tshow b

-- | Inputs are numerical clearance, model direction, source-panel ownership
-- and a separated reference mesh. No authored lower/upper pairs are consumed.
discoverReference :: Double -> V3 -> [FaceId] -> MaterialMesh -> Either DiscoveryError ReferenceContact
discoverReference clearance axis owners mesh = do
  -- Validate clearance/material even when the scan finds no overlapping pair.
  _ <- first DiscoveryGeometry (prepareContact clearance axis [] owners mesh)
  candidates <- first DiscoveryGeometry (overlapCandidates axis owners mesh)
  let grouped = M.fromListWith (++) [(candidatePanels candidate, [candidateGapRange candidate]) | candidate <- candidates]
      infer ((a, b), ranges)
        | Nothing `elem` ranges = Left (UncheckableReferenceOrder a b)
        | lo < negate contactTolerance && hi > contactTolerance = Left (CrossedReferencePanels a b)
        | lo >= negate contactTolerance && hi > contactTolerance = Right (a, b)
        | hi <= contactTolerance && lo < negate contactTolerance = Right (b, a)
        | otherwise = Left (AmbiguousReferenceOrder a b)
        where
          lo = minimum (0 : [low | Just (low, _) <- ranges])
          hi = maximum (0 : [high | Just (_, high) <- ranges])
  orders <- mapM infer (M.toAscList grouped)
  model <- first DiscoveryGeometry (prepareContact clearance axis orders owners mesh)
  pure (ReferenceContact orders candidates axis owners model)

-- | Rescan each queried mesh, but keep reference order fixed. The existing
-- line search rejects unsupported candidates; a stalled full correction must
-- remain unconverged. Direct queries report the newly discovered pair by id.
discoveredContacts :: ReferenceContact -> MaterialMesh -> Either DiscoveryError [ContactRow]
discoveredContacts reference mesh = do
  rows <- first DiscoveryGeometry (orderedContacts (referenceModel reference) mesh)
  candidates <- first DiscoveryGeometry (overlapCandidates (referenceAxis reference) (referenceOwners reference) mesh)
  let known a b = reaches S.empty a b || reaches S.empty b a
      reaches seen a b
        | a == b = True
        | S.member a seen = False
        | otherwise = any (\next -> reaches (S.insert a seen) next b) [next | (lower, next) <- referenceOrders reference, lower == a]
  mapM_ (\candidate -> let (a, b) = candidatePanels candidate in unless (known a b) (Left (NewContactPair a b))) candidates
  pure rows
