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
-- 'observeContactPose' can extend that knowledge at a separately supplied
-- approach pose. It checks old orders before learning new ones, and records
-- additions only after the whole observation passes. Numerical trial steps
-- still use 'discoveredContacts', which cannot change history. Callers generate
-- approach poses from crease angles, never by interpolating mesh positions.
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
    ContactObservation (..),
    referenceObservations,
    observeContactPose,
    discoveredContacts,
  )
where

import Control.Monad (unless)
import Data.Bifunctor (first)
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Text (Text)
import FoldContact (ContactRow (..), contactTolerance)
import PanelContact qualified as Panel
import Senbazuru.Explain (Explain (..), num, tshow)
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
    referenceModel :: !OrderedContact,
    referenceClearance :: !Double,
    savedObservations :: ![ContactObservation]
  }
  deriving stock (Eq, Show)

-- Ordinary accessor functions, not exported record fields: exporting a field
-- would also permit record updates that bypass the private constructor.
referenceOrders :: ReferenceContact -> [(FaceId, FaceId)]
referenceOrders = savedOrders

referenceCandidates :: ReferenceContact -> [ContactCandidate]
referenceCandidates = savedCandidates

-- | An audit entry for an accepted pose, starting at zero for the reference.
-- New orders are (lower, upper) along the model's direction. The candidates
-- retain measured gaps so the first encounter can be inspected afterwards.
data ContactObservation = ContactObservation
  { observationNumber :: !Int,
    observationNewOrders :: ![(FaceId, FaceId)],
    observationCandidates :: ![ContactCandidate]
  }
  deriving stock (Eq, Show)

referenceObservations :: ReferenceContact -> [ContactObservation]
referenceObservations = savedObservations

data DiscoveryError
  = DiscoveryGeometry !ContactError
  | AmbiguousReferenceOrder !FaceId !FaceId
  | CrossedReferencePanels !FaceId !FaceId
  | UncheckableReferenceOrder !FaceId !FaceId
  | NewContactPair !FaceId !FaceId
  | HistoryOrderViolation !Double
  | ObservationGeometry !Panel.ContactError
  | UnsafeContactObservation !Panel.ContactCheck
  deriving stock (Eq, Show)

instance Explain DiscoveryError where
  explain (DiscoveryGeometry err) = explain err
  explain (AmbiguousReferenceOrder a b) = pairName a b <> " overlap without a resolvable above/below order in the observed pose; supply a separated pose"
  explain (CrossedReferencePanels a b) = pairName a b <> " cross or have inconsistent directional order in the observed pose; correction cannot infer their history"
  explain (UncheckableReferenceOrder a b) = pairName a b <> " have an observed overlap that cannot be measured along the supplied direction"
  explain (NewContactPair a b) = pairName a b <> " now overlap, but the reference pose established no order between them; record a separated approach pose before correction, or supply an explicit order"
  explain (HistoryOrderViolation gap) = "contact observation violates an already learned order or its numerical clearance by " <> num (negate gap) <> " model units; history was not changed"
  explain (ObservationGeometry err) = explain err
  explain (UnsafeContactObservation report) = "contact observation failed the independent triangle check: " <> tshow (length (Panel.crossingPanels report)) <> " crossing pairs, " <> tshow (length (Panel.unorderedContacts report)) <> " unresolved overlaps, " <> tshow (length (Panel.reversedOrders report)) <> " reversed orders and " <> tshow (length (Panel.uncheckedOrders report)) <> " uncheckable orders; history was not changed"

pairName :: FaceId -> FaceId -> Text
pairName a b = "panels " <> tshow a <> " and " <> tshow b

-- | Inputs are numerical clearance, model direction, source-panel ownership
-- and a separated reference mesh. No authored lower/upper pairs are consumed.
discoverReference :: Double -> V3 -> [FaceId] -> MaterialMesh -> Either DiscoveryError ReferenceContact
discoverReference clearance axis owners mesh = do
  -- Validate clearance/material even when the scan finds no overlapping pair.
  _ <- first DiscoveryGeometry (prepareContact clearance axis [] owners mesh)
  candidates <- first DiscoveryGeometry (overlapCandidates axis owners mesh)
  orders <- inferOrders candidates
  model <- first DiscoveryGeometry (prepareContact clearance axis orders owners mesh)
  pure (ReferenceContact orders candidates axis owners model clearance [ContactObservation 0 orders candidates])

-- | Accept one sampled approach pose, preserving every earlier relationship
-- even after the panels separate. A new projected overlap must still be
-- separated enough to determine its side; an already crossed first encounter
-- is refused. The independent triangle check also covers contact inside panels.
-- No positions or constraints are changed on failure. This validates sampled
-- poses ONLY: a crossing and separation between samples can go undetected.
observeContactPose :: ReferenceContact -> MaterialMesh -> Either DiscoveryError ReferenceContact
observeContactPose reference mesh = do
  -- This also validates unchanged material ids before looking for new pairs.
  oldRows <- first DiscoveryGeometry (orderedContacts (referenceModel reference) mesh)
  checkGaps oldRows
  candidates <- first DiscoveryGeometry (overlapCandidates axis owners mesh)
  let unknown candidate = let (a, b) = candidatePanels candidate in not (knownPair (referenceOrders reference) a b)
  additions <- inferOrders (filter unknown candidates)
  let orders = referenceOrders reference ++ additions
  model <- first DiscoveryGeometry (prepareContact (referenceClearance reference) axis orders owners mesh)
  first DiscoveryGeometry (orderedContacts model mesh) >>= checkGaps
  report <- first ObservationGeometry (Panel.checkTriangleContact axis orders owners mesh)
  unless (Panel.contactPassed report) (Left (UnsafeContactObservation report))
  let observation = ContactObservation (length (savedObservations reference)) additions candidates
  pure reference {savedOrders = orders, referenceModel = model, savedObservations = savedObservations reference ++ [observation]}
  where
    axis = referenceAxis reference
    owners = referenceOwners reference
    checkGaps rows =
      let gap = minimum (0 : map contactGap rows)
       in unless (gap >= negate contactTolerance) (Left (HistoryOrderViolation gap))

inferOrders :: [ContactCandidate] -> Either DiscoveryError [(FaceId, FaceId)]
inferOrders candidates = mapM infer (M.toAscList grouped)
  where
    grouped = M.fromListWith (++) [(candidatePanels candidate, [candidateGapRange candidate]) | candidate <- candidates]
    infer ((a, b), ranges)
      | Nothing `elem` ranges = Left (UncheckableReferenceOrder a b)
      | lo < negate contactTolerance && hi > contactTolerance = Left (CrossedReferencePanels a b)
      | lo >= negate contactTolerance && hi > contactTolerance = Right (a, b)
      | hi <= contactTolerance && lo < negate contactTolerance = Right (b, a)
      | otherwise = Left (AmbiguousReferenceOrder a b)
      where
        lo = minimum (0 : [low | Just (low, _) <- ranges])
        hi = maximum (0 : [high | Just (_, high) <- ranges])

knownPair :: [(FaceId, FaceId)] -> FaceId -> FaceId -> Bool
knownPair orders a b = reaches S.empty a b || reaches S.empty b a
  where
    reaches seen from to
      | from == to = True
      | S.member from seen = False
      | otherwise = any (\next -> reaches (S.insert from seen) next to) [next | (lower, next) <- orders, lower == from]

-- | Rescan each queried mesh, but keep reference order fixed. The existing
-- line search rejects unsupported candidates; a stalled full correction must
-- remain unconverged. Direct queries report the newly discovered pair by id.
discoveredContacts :: ReferenceContact -> MaterialMesh -> Either DiscoveryError [ContactRow]
discoveredContacts reference mesh = do
  rows <- first DiscoveryGeometry (orderedContacts (referenceModel reference) mesh)
  candidates <- first DiscoveryGeometry (overlapCandidates (referenceAxis reference) (referenceOwners reference) mesh)
  mapM_ (\candidate -> let (a, b) = candidatePanels candidate in unless (knownPair (referenceOrders reference) a b) (Left (NewContactPair a b))) candidates
  pure rows
