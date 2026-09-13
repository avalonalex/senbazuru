-- | Directional contact correction for declared source-panel relationships.
-- Original panels are regions between crease lines; their ids survive
-- triangle subdivision. A lower panel must stay below an upper panel wherever their shadows overlap,
-- along a fixed direction attached to the model, never the camera. This extends
-- the original packet check to open panels; it does not infer contact partners.
--
-- Clip the MOVING 3D triangle by the vertical sides of its partner's shadow.
-- A vertical flap can have coincident projected corners at different heights;
-- collapsing it to a 2D polygon would lose the penetrating end. At least one
-- triangle must have a height function along the direction. Otherwise return
-- an error, even if another diagnostic could decide that particular pair.
--
-- Overlap corners move when either triangle moves. A small forward derivative
-- carries each scalar's value and its derivatives with respect to mesh vertices
-- through clipping and height evaluation. This differentiates the moving
-- intersection, rather than treating a contact point as fixed in space.
-- Shared vertex contributions add by id, so a crease remains one joined sheet.
--
-- A supplied numerical clearance separates panels that share no material
-- vertex. Joined panels use zero, since opening their common crease would
-- tear the sheet. This small solver margin is not physical paper thickness;
-- it keeps a tolerated negative residual from becoming a strict intersection.
-- 'prepareTriangleContact' instead names separated material triangles directly,
-- so two regions of ONE bending panel can meet without inventing new panels.
-- Its requirements stay attached to those triangle ids; adjacent triangles
-- sharing a vertex are refused because separating them would open the sheet.
--
-- FoldRelaxation penalises only negative separation after subtracting the
-- clearance: separated flaps do not attract. These are zero-thickness inequalities at numerical iterates,
-- not continuous collision detection, friction or general self-contact. The
-- distances and small-area tolerances here are for the study's unit sheets.
--
-- 'orderedBarrierContacts' supplies a separate energy for disjoint triangles.
-- DirectionalDistance measures approach to violating a retained order even
-- before shadows overlap; this module subtracts clearance and turns that
-- distance into a barrier residual, a penalty growing without bound at zero.
-- Raw height rows still serve endpoint measurements. The barrier range is
-- numerical, and these forces do not replace the independent motion check.
module SurfaceContact
  ( OrderedContact,
    ContactError (..),
    ContactCandidate (..),
    overlapCandidates,
    TriangleCandidate (..),
    localOverlapCandidates,
    prepareContact,
    prepareTriangleContact,
    orderedContacts,
    orderedBarrierContacts,
  )
where

import Control.Monad (unless, when)
import Data.IntMap.Strict qualified as IM
import Data.List (foldl')
import Data.Set qualified as S
import DirectionalDistance (DistanceSample (..), orderDistance)
import FoldContact (ContactRow (..))
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Types (FaceId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..), cross, polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..), Triangle)

-- Prepared triangle requirements and material are immutable; only positions
-- may change. Whole-panel preparation expands its owners into these same ids.
data OrderedContact = OrderedContact !(V3, V3, V3) ![Triangle] ![V2] ![(Int, Int, Double)]
  deriving stock (Eq, Show)

-- | A geometric overlap between triangles from distinct source panels. Panel
-- ids are in ascending order; the gap is SECOND minus FIRST along the axis.
-- Nothing means both triangles are upright, so this direction cannot resolve
-- their order. These candidates do not say which side ought to remain on top.
data ContactCandidate = ContactCandidate
  { candidateTriangles :: !(Int, Int),
    candidatePanels :: !(FaceId, FaceId),
    candidateGapRange :: !(Maybe (Double, Double))
  }
  deriving stock (Eq, Show)

-- | Local overlap without source-panel grouping. The local scan orders ids
-- ascending (the panel adapter keeps its panel order instead);
-- the gap is SECOND minus FIRST along the model direction. No gap means that
-- both triangles stand parallel to that direction and cannot supply heights.
data TriangleCandidate = TriangleCandidate
  { localTriangles :: !(Int, Int),
    localGapRange :: !(Maybe (Double, Double))
  }
  deriving stock (Eq, Show)

data ContactError
  = InvalidContactClearance
  | InvalidContactDirection
  | InvalidContactOwners
  | UnknownContactPanel !FaceId
  | CyclicContactOrder
  | ChangedContactMaterial
  | InvalidContactTriangle !Int
  | MissingContactVertex !Int
  | UncheckableContactPair !Int !Int
  | NonFiniteContact !Int !Int
  | UnknownContactTriangle !Int
  | AdjacentContactTriangles !Int !Int
  | InvalidBarrierDistance
  | OutsideBarrierDomain !Int !Int
  | EmptyContactMesh
  | InvalidContactMaterial !Int
  deriving stock (Eq, Show)

instance Explain ContactError where
  explain InvalidBarrierDistance = "contact activation distance must be finite and positive"
  explain (OutsideBarrierDomain a b) = "triangles " <> tshow a <> " and " <> tshow b <> " have no positive ordered-distance clearance"
  explain InvalidContactClearance = "surface contact needs a finite nonnegative numerical clearance"
  explain InvalidContactDirection = "surface contact needs a finite nonzero material direction"
  explain InvalidContactOwners = "surface contact needs a nonempty mesh and one source-panel owner per triangle"
  explain (UnknownContactPanel fid) = "surface contact order names an absent panel " <> tshow fid
  explain CyclicContactOrder = "surface contact lower/upper requirements contain a cycle"
  explain ChangedContactMaterial = "surface contact correction must preserve its prepared triangle ids and original-sheet coordinates"
  explain (InvalidContactTriangle i) = "surface contact triangle " <> tshow i <> " needs finite positions and nonzero area"
  explain (MissingContactVertex i) = "surface contact refers to missing vertex " <> tshow i
  explain (UncheckableContactPair a b) = "triangles " <> tshow a <> " and " <> tshow b <> " both stand parallel to the contact direction; this order cannot be corrected as a height inequality"
  explain (NonFiniteContact a b) = "contact between triangles " <> tshow a <> " and " <> tshow b <> " produced a non-finite gap or derivative"
  explain (UnknownContactTriangle i) = "local contact refers to absent triangle " <> tshow i
  explain (AdjacentContactTriangles a b) = "local contact triangles " <> tshow a <> " and " <> tshow b <> " share material vertices; their connection must remain joined"
  explain EmptyContactMesh = "local triangle contact needs a nonempty mesh"
  explain (InvalidContactMaterial i) = "local contact vertex " <> tshow i <> " needs finite original-sheet coordinates"

-- | Prepare numerical clearance, direction, lower/upper panel pairs and one
-- owner per triangle. Only position changes are allowed after preparation.
prepareContact :: Double -> V3 -> [(FaceId, FaceId)] -> [FaceId] -> MaterialMesh -> Either ContactError OrderedContact
prepareContact clearance direction requirements owners mesh = do
  unless (finite clearance && clearance >= 0) (Left InvalidContactClearance)
  basis <- projectionBasis direction
  validateOwners owners mesh
  mapM_ (\fid -> unless (fid `elem` owners) (Left (UnknownContactPanel fid))) [fid | (a, b) <- requirements, fid <- [a, b]]
  let reachable = closure (S.fromList requirements)
  unless (all (uncurry (/=)) (S.toList reachable)) (Left CyclicContactOrder)
  let panelVertices = IM.fromListWith S.union [(unFaceId owner, S.fromList [a, b, c]) | (owner, (a, b, c)) <- zip owners (triangles mesh)]
      joined a b = not (S.null (S.intersection (IM.findWithDefault S.empty (unFaceId a) panelVertices) (IM.findWithDefault S.empty (unFaceId b) panelVertices)))
      pairs = [(i, j, if joined a b then 0 else clearance) | (i, a) <- zip [0 ..] owners, (j, b) <- zip [0 ..] owners, S.member (a, b) reachable]
      model = OrderedContact basis (triangles mesh) (map sampleMaterial (samples mesh)) pairs
  _ <- orderedContacts model mesh
  pure model

-- | Numerical clearance, model direction and (lower, upper) triangle ids.
-- This is an explicit local requirement, not automatic contact discovery.
-- Requirements include their transitive consequences, just as panel orders do;
-- every resulting pair must have disjoint material vertices. Source-panel ids
-- are neither consumed nor changed, so a panel need not be above itself.
prepareTriangleContact :: Double -> V3 -> [(Int, Int)] -> MaterialMesh -> Either ContactError OrderedContact
prepareTriangleContact clearance direction requirements mesh = do
  unless (finite clearance && clearance >= 0) (Left InvalidContactClearance)
  basis <- projectionBasis direction
  when (null (triangles mesh)) (Left EmptyContactMesh)
  mapM_ (\(i, sample) -> let V2 u v = sampleMaterial sample in unless (all finite [u, v]) (Left (InvalidContactMaterial i))) (zip [0 ..] (samples mesh))
  let topology = IM.fromList (zip [0 ..] (triangles mesh))
      vertices i = case IM.lookup i topology of
        Nothing -> Left (UnknownContactTriangle i)
        Just (a, b, c) -> Right [a, b, c]
      reachable = closure (S.fromList requirements)
  mapM_ vertices [i | (a, b) <- requirements, i <- [a, b]]
  unless (all (uncurry (/=)) (S.toList reachable)) (Left CyclicContactOrder)
  let pair (a, b) = do
        av <- vertices a
        bv <- vertices b
        unless (all (`notElem` bv) av) (Left (AdjacentContactTriangles a b))
        pure (a, b, clearance)
  pairs <- mapM pair (S.toList reachable)
  let model = OrderedContact basis (triangles mesh) (map sampleMaterial (samples mesh)) pairs
  _ <- orderedContacts model mesh
  pure model

closure :: (Ord a) => S.Set (a, a) -> S.Set (a, a)
closure pairs =
  let more = S.union pairs (S.fromList [(a, c) | (a, b) <- S.toList pairs, (b', c) <- S.toList pairs, b == b'])
   in if more == pairs then pairs else closure more

-- | Return separation MINUS numerical clearance, with positional gradients.
-- A negative residual asks the solver to separate the panels further.
orderedContacts :: OrderedContact -> MaterialMesh -> Either ContactError [ContactRow]
orderedContacts (OrderedContact basis topology material pairs) mesh = do
  unless (triangles mesh == topology && map sampleMaterial (samples mesh) == material) (Left ChangedContactMaterial)
  projected <- projectMesh basis mesh
  let triangle i = maybe (Left (InvalidContactTriangle i)) Right (IM.lookup i projected)
      pair (i, j, clearance) = do
        (lower, lowerAlignment) <- triangle i
        (upper, upperAlignment) <- triangle j
        gaps <-
          if max lowerAlignment upperAlignment <= 1e-8
            then Left (UncheckableContactPair i j)
            else
              if lowerAlignment >= upperAlignment
                then separation i lower upper
                else map negate <$> separation j upper lower
        unless (all validD gaps) (Left (NonFiniteContact i j))
        pure [ContactRow (value gap - clearance) (IM.toList (derivative gap)) | gap <- gaps]
  concat <$> mapM pair pairs

-- | Smoothly activate a distance barrier before a directional order fails.
-- Activation is an extra numerical range beyond clearance, not paper thickness.
-- The squared residual is -(h-d)^2 log(d/h) for 0 < d < h, zero outside.
-- Its value and first derivative vanish at h; a distance at or below clearance
-- is outside its domain. Use disjoint triangle pairs from
-- 'prepareTriangleContact': connected neighbors cannot open a positive gap.
-- Existing height and motion checks still decide accepted validity.
orderedBarrierContacts :: Double -> OrderedContact -> MaterialMesh -> Either ContactError [ContactRow]
orderedBarrierContacts activation (OrderedContact basis@(_, _, axis) topology material pairs) mesh = do
  unless (finite activation && activation > 0) (Left InvalidBarrierDistance)
  unless (triangles mesh == topology && map sampleMaterial (samples mesh) == material) (Left ChangedContactMaterial)
  _ <- projectMesh basis mesh
  let vertices = IM.fromList (zip [0 ..] (samples mesh))
      faces = IM.fromList (zip [0 ..] topology)
      point i = maybe (Left (MissingContactVertex i)) (Right . (i,) . position) (IM.lookup i vertices)
      triangle i = case IM.lookup i faces of
        Nothing -> Left (InvalidContactTriangle i)
        Just (a, b, c) -> (,,) <$> point a <*> point b <*> point c
      pair (i, j, clearance) = do
        lower <- triangle i
        upper <- triangle j
        let DistanceSample distance gradient = orderDistance axis lower upper
            gap = distance - clearance
        unless (finite gap && all (finitePoint . snd) gradient) (Left (NonFiniteContact i j))
        unless (gap > 0) (Left (OutsideBarrierDomain i j))
        if gap >= activation
          then pure (ContactRow 0 [])
          else do
            let root = sqrt (-log (gap / activation))
                residual = -((activation - gap) * root)
                slope = root + (activation - gap) / (2 * gap * root)
                row = ContactRow residual [(v, slope *^ g) | (v, g) <- gradient]
            if root == 0
              then pure (ContactRow 0 [])
              else if finite residual && finite slope then pure row else Left (NonFiniteContact i j)
  mapM pair pairs

-- | Find overlaps from CURRENT geometry, without an authored pair list.
-- A positive-area piece of a 3D triangle must lie in the other's projected
-- footprint. Mere shared edges/vertices do not discover an order. Upright
-- triangles retain their actual 3D area; two upright triangles whose projected
-- boxes meet are conservatively reported as uncheckable candidates.
overlapCandidates :: V3 -> [FaceId] -> MaterialMesh -> Either ContactError [ContactCandidate]
overlapCandidates direction owners mesh = do
  validateOwners owners mesh
  let pairs = [(i, j) | (i, a) <- zip [0 ..] owners, (j, b) <- zip [0 ..] owners, a < b]
      ownership = IM.fromList (zip [0 ..] owners)
      attach candidate = do
        let (i, j) = localTriangles candidate
        a <- maybe (Left InvalidContactOwners) Right (IM.lookup i ownership)
        b <- maybe (Left InvalidContactOwners) Right (IM.lookup j ownership)
        pure (ContactCandidate (i, j) (a, b) (localGapRange candidate))
  candidates <- scanOverlaps direction pairs mesh
  mapM attach candidates

-- | Discover local partners anywhere in the mesh, including within one panel.
-- Shared material vertices exclude a separating constraint, regardless of
-- current positions. This exclusion is NOT a collision verdict: the independent
-- triangle check must still inspect neighbors for overlap beyond their join.
localOverlapCandidates :: V3 -> MaterialMesh -> Either ContactError [TriangleCandidate]
localOverlapCandidates direction mesh = do
  when (null (triangles mesh)) (Left EmptyContactMesh)
  let indexed = zip [0 ..] (triangles mesh)
      separate (a, b, c) (d, e, f) = all (`notElem` [d, e, f]) [a, b, c]
      pairs = [(i, j) | (i, a) <- indexed, (j, b) <- indexed, i < j, separate a b]
  scanOverlaps direction pairs mesh

-- Both discovery policies use the same geometric test. Neither source-panel
-- ids nor adjacency alter clipping or the sign of the measured separation.
scanOverlaps :: V3 -> [(Int, Int)] -> MaterialMesh -> Either ContactError [TriangleCandidate]
scanOverlaps direction pairs mesh = do
  basis <- projectionBasis direction
  projected <- projectMesh basis mesh
  let pair (i, j) = do
        (firstTriangle, firstAlignment) <- maybe (Left (InvalidContactTriangle i)) Right (IM.lookup i projected)
        (secondTriangle, secondAlignment) <- maybe (Left (InvalidContactTriangle j)) Right (IM.lookup j projected)
        if not (boxesMeet firstTriangle secondTriangle)
          then pure []
          else
            if max firstAlignment secondAlignment <= 1e-8
              then pure [TriangleCandidate (i, j) Nothing]
              else do
                (clipped, gaps) <-
                  if firstAlignment >= secondAlignment
                    then clippedSeparation i firstTriangle secondTriangle
                    else do
                      (ps, ds) <- clippedSeparation j secondTriangle firstTriangle
                      pure (ps, map negate ds)
                unless (all validD gaps) (Left (NonFiniteContact i j))
                let area = norm (polygonNormal [V3 (value x) (value y) (value z) | (x, y, z) <- clipped]) / 2
                pure $ case map value gaps of
                  [] -> []
                  ds | area > 1e-14 -> [TriangleCandidate (i, j) (Just (minimum ds, maximum ds))]
                  _ -> []
  concat <$> mapM pair pairs

projectionBasis :: V3 -> Either ContactError (V3, V3, V3)
projectionBasis direction = do
  unless (finitePoint direction && finite (norm direction) && norm direction > 1e-12) (Left InvalidContactDirection)
  let axis = (1 / norm direction) *^ direction
      side = cross axis (if abs (v3x axis) < 0.9 then V3 1 0 0 else V3 0 1 0)
      u = (1 / norm side) *^ side
  pure (u, cross axis u, axis)

validateOwners :: [FaceId] -> MaterialMesh -> Either ContactError ()
validateOwners owners mesh = unless (not (null (triangles mesh)) && length owners == length (triangles mesh)) (Left InvalidContactOwners)

projectMesh :: (V3, V3, V3) -> MaterialMesh -> Either ContactError (IM.IntMap ([Point], Double))
projectMesh basis mesh = do
  let vertices = IM.fromList (zip [0 ..] (samples mesh))
      point i = maybe (Left (MissingContactVertex i)) (Right . position) (IM.lookup i vertices)
      prepare (i, (a, b, c)) = do
        pa <- point a
        pb <- point b
        pc <- point c
        let normal = cross (pb ^-^ pa) (pc ^-^ pa)
            area = norm normal
            (_, _, axis) = basis
        unless (all finitePoint [pa, pb, pc] && finite area && area > 1e-14) (Left (InvalidContactTriangle i))
        pure (i, ([project basis a pa, project basis b pb, project basis c pc], abs (dot normal axis) / area))
  IM.fromList <$> mapM prepare (zip [0 ..] (triangles mesh))

-- Projected boxes are only a cheap rejection test. The clipping above decides
-- actual overlap; touching boxes must not discard a possible upright flap.
boxesMeet :: [Point] -> [Point] -> Bool
boxesMeet as bs = all overlap [\(x, _, _) -> value x, \(_, y, _) -> value y]
  where
    overlap coordinate = case (map coordinate as, map coordinate bs) of
      ([], _) -> False
      (_, []) -> False
      (xs, ys) -> maximum xs >= minimum ys - 1e-12 && maximum ys >= minimum xs - 1e-12

-- A triangle's height varies linearly, so the smallest/largest gaps occur at
-- the clipped 3D polygon's corners. Both corners of an upright edge are retained.
separation :: Int -> [Point] -> [Point] -> Either ContactError [D]
separation i base moving = snd <$> clippedSeparation i base moving

clippedSeparation :: Int -> [Point] -> [Point] -> Either ContactError ([Point], [D])
clippedSeparation i base moving = case base of
  [a, b, c] ->
    let determinant = crossXY (sub b a) (sub c a)
        outline = if value determinant > 0 then base else reverse base
        clipped = foldl' clip moving (ring outline)
        gap p = zOf p - zOf a - crossXY (sub p a) (sub c a) / determinant * (zOf b - zOf a) - crossXY (sub b a) (sub p a) / determinant * (zOf c - zOf a)
     in Right (clipped, map gap clipped)
  _ -> Left (InvalidContactTriangle i)
  where
    clip ps (a, b) =
      let distance p = crossXY (sub b a) (sub p a)
          snap d = if abs (value d) < 1e-14 then d {value = 0} else d
          edge (p, q)
            | value dp >= 0 && value dq >= 0 = [q]
            | value dp < 0 && value dq < 0 = []
            | otherwise = let hit = add p (scale (dp / (dp - dq)) (sub q p)) in if value dq >= 0 then [hit, q] else [hit]
            where
              dp = snap (distance p); dq = snap (distance q)
       in concatMap edge (ring ps)

ring :: [a] -> [(a, a)]
ring xs = zip xs (drop 1 xs ++ take 1 xs)

type Point = (D, D, D)

project :: (V3, V3, V3) -> Int -> V3 -> Point
project (u, v, w) i p = (coordinate u, coordinate v, coordinate w)
  where
    coordinate axis = D (dot axis p) (IM.singleton i axis)

sub, add :: Point -> Point -> Point
sub (x, y, z) (a, b, c) = (x - a, y - b, z - c)
add (x, y, z) (a, b, c) = (x + a, y + b, z + c)

scale :: D -> Point -> Point
scale t (x, y, z) = (t * x, t * y, t * z)

crossXY :: Point -> Point -> D
crossXY (x, y, _) (a, b, _) = x * b - y * a

zOf :: Point -> D
zOf (_, _, z) = z

-- The ordinary product and quotient rules, carrying sparse derivatives for
-- at most the six vertices of a contact pair. Branch predicates inspect only
-- the value; derivatives describe the currently selected clipping features.
data D = D {value :: !Double, derivative :: !(IM.IntMap V3)}

instance Num D where
  D a da + D b db = D (a + b) (IM.unionWith (^+^) da db)
  D a da - D b db = D (a - b) (IM.unionWith (^+^) da (IM.map ((-1) *^) db))
  D a da * D b db = D (a * b) (IM.unionWith (^+^) (IM.map (b *^) da) (IM.map (a *^) db))
  negate (D a da) = D (-a) (IM.map ((-1) *^) da)
  abs (D a da) = D (abs a) (IM.map (signum a *^) da)
  signum (D a _) = D (signum a) IM.empty
  fromInteger n = D (fromInteger n) IM.empty

instance Fractional D where
  recip (D a da) = D (1 / a) (IM.map ((-(1 / (a * a))) *^) da)
  fromRational n = D (fromRational n) IM.empty

validD :: D -> Bool
validD (D a da) = finite a && all finitePoint (IM.elems da)

finite :: Double -> Bool
finite a = not (isNaN a || isInfinite a)

finitePoint :: V3 -> Bool
finitePoint (V3 x y z) = all finite [x, y, z]
