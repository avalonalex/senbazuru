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
--
-- FoldRelaxation penalises only negative separation after subtracting the
-- clearance: separated flaps do not attract. These are zero-thickness inequalities at numerical iterates,
-- not continuous collision detection, friction or general self-contact. The
-- distances and small-area tolerances here are for the study's unit sheets.
module SurfaceContact
  ( OrderedContact,
    ContactError (..),
    prepareContact,
    orderedContacts,
  )
where

import Control.Monad (unless)
import Data.IntMap.Strict qualified as IM
import Data.List (foldl')
import Data.Set qualified as S
import FoldContact (ContactRow (..))
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Types (FaceId (..))
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..), Triangle)

-- Prepared ownership and material are immutable; only positions may change.
data OrderedContact = OrderedContact !(V3, V3, V3) ![Triangle] ![V2] ![(Int, Int, Double)]
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
  deriving stock (Eq, Show)

instance Explain ContactError where
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

-- | Prepare numerical clearance, direction, lower/upper panel pairs and one
-- owner per triangle. Only position changes are allowed after preparation.
prepareContact :: Double -> V3 -> [(FaceId, FaceId)] -> [FaceId] -> MaterialMesh -> Either ContactError OrderedContact
prepareContact clearance direction requirements owners mesh = do
  unless (finite clearance && clearance >= 0) (Left InvalidContactClearance)
  unless (finitePoint direction && finite (norm direction) && norm direction > 1e-12) (Left InvalidContactDirection)
  unless (not (null (triangles mesh)) && length owners == length (triangles mesh)) (Left InvalidContactOwners)
  mapM_ (\fid -> unless (fid `elem` owners) (Left (UnknownContactPanel fid))) [fid | (a, b) <- requirements, fid <- [a, b]]
  let reachable = closure (S.fromList requirements)
  unless (all (uncurry (/=)) (S.toList reachable)) (Left CyclicContactOrder)
  let axis = (1 / norm direction) *^ direction
      side = cross axis (if abs (v3x axis) < 0.9 then V3 1 0 0 else V3 0 1 0)
      u = (1 / norm side) *^ side
      v = cross axis u
      panelVertices = IM.fromListWith S.union [(unFaceId owner, S.fromList [a, b, c]) | (owner, (a, b, c)) <- zip owners (triangles mesh)]
      joined a b = not (S.null (S.intersection (IM.findWithDefault S.empty (unFaceId a) panelVertices) (IM.findWithDefault S.empty (unFaceId b) panelVertices)))
      pairs = [(i, j, if joined a b then 0 else clearance) | (i, a) <- zip [0 ..] owners, (j, b) <- zip [0 ..] owners, S.member (a, b) reachable]
      model = OrderedContact (u, v, axis) (triangles mesh) (map sampleMaterial (samples mesh)) pairs
  _ <- orderedContacts model mesh
  pure model
  where
    closure pairs =
      let more = S.union pairs (S.fromList [(a, c) | (a, b) <- S.toList pairs, (b', c) <- S.toList pairs, b == b'])
       in if more == pairs then pairs else closure more

-- | Return separation MINUS numerical clearance, with positional gradients.
-- A negative residual asks the solver to separate the panels further.
orderedContacts :: OrderedContact -> MaterialMesh -> Either ContactError [ContactRow]
orderedContacts (OrderedContact basis topology material pairs) mesh = do
  unless (triangles mesh == topology && map sampleMaterial (samples mesh) == material) (Left ChangedContactMaterial)
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
  projected <- IM.fromList <$> mapM prepare (zip [0 ..] topology)
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

-- A triangle's height varies linearly, so the smallest/largest gaps occur at
-- the clipped 3D polygon's corners. Both corners of an upright edge are retained.
separation :: Int -> [Point] -> [Point] -> Either ContactError [D]
separation i base moving = case base of
  [a, b, c] ->
    let determinant = crossXY (sub b a) (sub c a)
        outline = if value determinant > 0 then base else reverse base
        clipped = foldl' clip moving (ring outline)
        gap p = zOf p - zOf a - crossXY (sub p a) (sub c a) / determinant * (zOf b - zOf a) - crossXY (sub b a) (sub p a) / determinant * (zOf c - zOf a)
     in Right (map gap clipped)
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
