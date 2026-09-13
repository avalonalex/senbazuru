-- | Learn which material triangles of bending paper lie above each other.
-- A source panel is the region between deliberate crease lines. It can bend
-- until two of its own parts meet, so a whole-panel order cannot describe this
-- contact. Here the keys are triangle ids in one unchanged material mesh.
-- The scan consumes no partner list and does not split or rename source panels.
--
-- Nearby overlapping shadows in a separated reference pose supply a lower/upper
-- relationship along a caller's model direction. We keep that relationship
-- fixed during correction: learning it again after penetration would accept
-- the reversed order. A newly contacting pair needs an earlier order;
-- otherwise the solver must refuse that trial. 'extendLocalReference' can learn
-- additional partners while they are still separated. Its result is a proposed
-- history: the solver retains it only if the step is accepted. A rejected trial
-- cannot leave behind either an order or an audit event. These numerical poses
-- do not certify collision-free motion between them.
--
-- The reference search distance is measured along the model direction over overlapping
-- shadows, not as closest distance in 3D. It must exceed numerical clearance;
-- neither is physical thickness. A trial needs an order when it reaches
-- clearance (plus contact tolerance), not merely the wider search distance.
-- Separated, unknown pairs have no force or promised order, but
-- learned orders remain active even after separation. Flat connected reference
-- triangles share their discovered partners so a sliding contact does not lose
-- its order at a triangulation diagonal. Each extension finds flat patches in
-- its own pose; an initially flat sheet cannot exempt all its future internal
-- contact. This does not merge material ids.
--
-- Triangles sharing material vertices cannot be pulled apart. Discovery skips
-- them, but independent reference checks still inspect every pair, so a shared
-- corner cannot excuse a crossing. Acyclic directional orders are intentionally
-- narrower than general self-contact. SurfaceContact owns clipping and forces;
-- this module owns discovery and the history of retained relationships.
module LocalContactDiscovery
  ( LocalReference,
    LocalDiscoveryError (..),
    discoverLocalReference,
    extendLocalReference,
    LocalEncounter (..),
    localReferenceEncounters,
    localReferenceOrders,
    localReferenceCandidates,
    localDiscoveredContacts,
  )
where

import Control.Monad (unless)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Set qualified as S
import Data.Text (Text)
import FoldContact (ContactRow (..), contactTolerance)
import PanelContact qualified as Panel
import Senbazuru.Explain (Explain (..), num, tshow)
import Senbazuru.Geometry.V3 (V3, cross)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..))
import SurfaceContact

-- Ordinary accessors preserve the private constructor's guarantee: callers
-- cannot replace learned orders while retaining different prepared forces.
data LocalReference = LocalReference
  { referenceClearance :: !Double,
    referenceSearchDistance :: !Double,
    referenceAxis :: !V3,
    referenceOrders :: ![(Int, Int)],
    referenceCandidates :: ![TriangleCandidate],
    referenceModel :: !OrderedContact,
    referenceEncounters :: ![LocalEncounter]
  }
  deriving stock (Eq, Show)

localReferenceOrders :: LocalReference -> [(Int, Int)]
localReferenceOrders = referenceOrders

localReferenceCandidates :: LocalReference -> [TriangleCandidate]
localReferenceCandidates = referenceCandidates

-- | A successful extension records its separated witnesses and unchanged mesh.
-- The iteration is an audit label supplied by the solver, not physical time.
-- Orders include patch partners; candidates contain the direct encounters.
data LocalEncounter = LocalEncounter
  { encounterIteration :: !Int,
    encounterOrders :: ![(Int, Int)],
    encounterCandidates :: ![TriangleCandidate],
    encounterMesh :: !MaterialMesh
  }
  deriving stock (Eq, Show)

localReferenceEncounters :: LocalReference -> [LocalEncounter]
localReferenceEncounters = referenceEncounters

data LocalDiscoveryError
  = InvalidLocalSearchDistance
  | LocalDiscoveryGeometry !ContactError
  | AmbiguousLocalOrder !Int !Int
  | CrossedLocalReference !Int !Int
  | UncheckableLocalOrder !Int !Int
  | NewLocalContactPair !Int !Int
  | LocalReferenceClearance !Double
  | LocalReferenceGeometry !Panel.ContactError
  | UnsafeLocalReference !Panel.ContactCheck
  deriving stock (Eq, Show)

instance Explain LocalDiscoveryError where
  explain InvalidLocalSearchDistance = "local contact discovery needs a finite search distance greater than numerical clearance"
  explain (LocalDiscoveryGeometry err) = explain err
  explain (AmbiguousLocalOrder a b) = pairName a b <> " overlap without a resolvable above/below order; supply a separated reference pose"
  explain (CrossedLocalReference a b) = pairName a b <> " cross in the reference; their earlier order cannot be inferred"
  explain (UncheckableLocalOrder a b) = pairName a b <> " cannot supply reference heights along the contact direction"
  explain (NewLocalContactPair a b) = pairName a b <> " now reach contact without a reference order; supply a reference that establishes their side before correction"
  explain (LocalReferenceClearance gap) = "local reference violates numerical clearance by " <> num (negate gap) <> " model units"
  explain (LocalReferenceGeometry err) = explain err
  explain (UnsafeLocalReference report) = "local reference failed the independent triangle check: " <> tshow (length (Panel.crossingPanels report)) <> " crossings, " <> tshow (length (Panel.unorderedContacts report)) <> " unresolved overlaps, " <> tshow (length (Panel.reversedOrders report)) <> " reversed orders and " <> tshow (length (Panel.uncheckedOrders report)) <> " uncheckable orders"

pairName :: Int -> Int -> Text
pairName a b = "material triangles " <> tshow a <> " and " <> tshow b

-- | Numerical clearance, search distance, model direction and a separated mesh.
-- Refuse unsafe references, including collisions excluded from force discovery
-- because the triangles share a vertex. No authored pairs or panel ids are read.
discoverLocalReference :: Double -> Double -> V3 -> MaterialMesh -> Either LocalDiscoveryError LocalReference
discoverLocalReference clearance searchDistance axis mesh = do
  _ <- first LocalDiscoveryGeometry (prepareTriangleContact clearance axis [] mesh)
  unless (not (isNaN searchDistance || isInfinite searchDistance) && searchDistance > clearance) (Left InvalidLocalSearchDistance)
  patches <- referencePatches mesh
  candidates <- filter (nearby searchDistance) <$> first LocalDiscoveryGeometry (localOverlapCandidates axis mesh)
  detected <- mapM infer candidates
  let patch i = IM.findWithDefault [i] i patches
      topology = IM.fromList (zip [0 ..] (triangles mesh))
      vertices i = case IM.lookup i topology of Nothing -> []; Just (a, b, c) -> [a, b, c]
      orders = S.toAscList (S.fromList [(a, b) | (lower, upper) <- detected, a <- patch lower, b <- patch upper, all (`notElem` vertices b) (vertices a)])
  model <- first LocalDiscoveryGeometry (prepareTriangleContact clearance axis orders mesh)
  rows <- first LocalDiscoveryGeometry (orderedContacts model mesh)
  let gap = minimum (0 : map contactGap rows)
  unless (gap >= negate contactTolerance) (Left (LocalReferenceClearance gap))
  report <- first LocalReferenceGeometry (Panel.checkLocalTriangleContact axis orders mesh)
  unless (Panel.contactPassed report) (Left (UnsafeLocalReference report))
  pure (LocalReference clearance searchDistance axis orders candidates model [])
  where
    infer candidate = case localGapRange candidate of
      Nothing -> Left (UncheckableLocalOrder a b)
      Just (lo, hi)
        | lo < negate contactTolerance && hi > contactTolerance -> Left (CrossedLocalReference a b)
        | lo > contactTolerance -> Right (a, b)
        | hi < negate contactTolerance -> Right (b, a)
        | otherwise -> Left (AmbiguousLocalOrder a b)
      where
        (a, b) = localTriangles candidate

-- | Rescan trial geometry while preserving the reference order. Returned gaps
-- may be negative (the solver must correct them); an unknown pair reaching
-- numerical clearance or crossing is an error,
-- never a new order inferred from a possibly crossed numerical trial.
localDiscoveredContacts :: LocalReference -> MaterialMesh -> Either LocalDiscoveryError [ContactRow]
localDiscoveredContacts reference mesh = do
  rows <- first LocalDiscoveryGeometry (orderedContacts model mesh)
  candidates <- first LocalDiscoveryGeometry (localOverlapCandidates axis mesh)
  mapM_ known (filter (nearby (clearance + contactTolerance)) candidates)
  pure rows
  where
    clearance = referenceClearance reference
    axis = referenceAxis reference
    orders = referenceOrders reference
    model = referenceModel reference
    known candidate = let (a, b) = localTriangles candidate in unless (related orders a b) (Left (NewLocalContactPair a b))

-- | Propose a monotone extension: callers keep it only if they accept this pose.
-- First enforce the OLD guard, so a newly crossed/touching pair cannot explain
-- itself by supplying a new order. Previously known negative gaps remain solver
-- residuals; their direction is never relearned. Every newly implied relation
-- must have positive clearance wherever its shadows overlap, including partners
-- added by flat patches or by transitivity (A below B below C means A below C).
extendLocalReference :: Int -> LocalReference -> MaterialMesh -> Either LocalDiscoveryError LocalReference
extendLocalReference iteration reference mesh = do
  _ <- localDiscoveredContacts reference mesh
  candidates <- first LocalDiscoveryGeometry (localOverlapCandidates axis mesh)
  let fresh candidate = let (a, b) = localTriangles candidate in not (related oldOrders a b)
      encounters = filter (\candidate -> fresh candidate && nearby (referenceSearchDistance reference) candidate) candidates
  if null encounters
    then pure reference
    else do
      detected <- mapM infer encounters
      patches <- referencePatches mesh
      let patch i = IM.findWithDefault [i] i patches
          topology = IM.fromList (zip [0 ..] (triangles mesh))
          vertices i = case IM.lookup i topology of Nothing -> []; Just (a, b, c) -> [a, b, c]
          additions = [(a, b) | (lower, upper) <- detected, a <- patch lower, b <- patch upper, all (`notElem` vertices b) (vertices a), not (reaches oldOrders a b)]
          orders = S.toAscList (S.fromList (oldOrders ++ additions))
      model <- first LocalDiscoveryGeometry (prepareTriangleContact clearance axis orders mesh)
      mapM_ (checkNew orders) (filter fresh candidates)
      let learned = S.toAscList (S.fromList additions)
          event = LocalEncounter iteration learned encounters mesh
      pure reference {referenceOrders = orders, referenceModel = model, referenceEncounters = referenceEncounters reference ++ [event]}
  where
    clearance = referenceClearance reference
    axis = referenceAxis reference
    oldOrders = referenceOrders reference
    infer candidate = case localGapRange candidate of
      Just (lo, _) | lo > clearance + contactTolerance -> Right (localTriangles candidate)
      Just (_, hi) | hi < negate (clearance + contactTolerance) -> let (a, b) = localTriangles candidate in Right (b, a)
      _ -> let (a, b) = localTriangles candidate in Left (NewLocalContactPair a b)
    checkNew orders candidate =
      let (a, b) = localTriangles candidate
       in if not (related orders a b)
            then pure ()
            else case localGapRange candidate of
              Nothing -> Left (UncheckableLocalOrder a b)
              Just (lo, hi) ->
                let gap = (if reaches orders a b then lo else negate hi) - clearance
                 in unless (gap > contactTolerance) (Left (LocalReferenceClearance gap))

related :: [(Int, Int)] -> Int -> Int -> Bool
related orders a b = reaches orders a b || reaches orders b a

reaches :: [(Int, Int)] -> Int -> Int -> Bool
reaches orders = go S.empty
  where
    go seen from to
      | from == to = True
      | S.member from seen = False
      | otherwise = any (\next -> go (S.insert from seen) next to) [next | (lower, next) <- orders, lower == from]

-- Only nearby projected overlaps need a contact relationship. Distant parts of
-- a curved sheet can exchange height order while their shadows are separate;
-- freezing every distant relationship would constrain unrelated bending.
-- Crossing ranges and unsupported directions always remain candidates.
nearby :: Double -> TriangleCandidate -> Bool
nearby distance candidate = case localGapRange candidate of
  Nothing -> True
  Just (lo, hi) -> lo <= distance && hi >= negate distance

-- A flat patch is a connected set of coplanar reference triangles, not a source
-- panel: one bent panel can contain many patches. Expand an encountered pair to
-- its two patches so a contact sliding across a triangulation diagonal keeps
-- the same order. The resulting relationships survive later bending, but new
-- encounters use that later pose's patches. No material identity changes.
referencePatches :: MaterialMesh -> Either LocalDiscoveryError (IM.IntMap [Int])
referencePatches mesh = do
  let vertices = IM.fromList (zip [0 ..] (samples mesh))
      point i = maybe (Left (LocalDiscoveryGeometry (MissingContactVertex i))) (Right . position) (IM.lookup i vertices)
      normal (i, (a, b, c)) = do
        pa <- point a
        pb <- point b
        pc <- point c
        let n = cross (pb ^-^ pa) (pc ^-^ pa)
        pure (i, [a, b, c], (1 / norm n) *^ n)
  rows <- mapM normal (zip [0 ..] (triangles mesh))
  let adjacent = [(i, j) | (i, av, an) <- rows, (j, bv, bn) <- rows, i /= j, length (filter (`elem` bv) av) == 2, norm (cross an bn) <= 1e-10]
      connected seen [] = S.toAscList seen
      connected seen (i : rest)
        | S.member i seen = connected seen rest
        | otherwise = connected (S.insert i seen) ([b | (a, b) <- adjacent, a == i] ++ rest)
  pure (IM.fromList [(i, connected S.empty [i]) | (i, _, _) <- rows])
