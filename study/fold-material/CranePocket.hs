-- | A material map for opening the traditional crane's body.
-- The eight panels incident to the original sheet's centre are the candidate
-- body core. The remaining four original-sheet quadrants lead to the wings,
-- tail, and neck/head. These are connected material regions, not independently
-- movable flaps: their collars also share edges around the body core.
-- See docs/glossary.md for panels, material coordinates and crease assignments.
--
-- This fixture-specific map is deliberately made before a new solve. It keeps
-- the tail-tucked surface unchanged and names candidate angle freedoms without
-- certifying that they are sufficient. In particular, the core's perimeter is
-- an INTERNAL material interface, not the rim of a hole. Four distinct sheet
-- edge midpoints coincide at the underside in this flat state; they provide
-- landmarks for a later opening measurement, not a closed pressure cavity.
module CranePocket
  ( Region (..),
    EdgeRole (..),
    PocketEdge (..),
    PocketMap (..),
    PocketError (..),
    buildCranePocket,
    mapCranePocket,
    regions,
    regionName,
    regionKey,
    roleName,
    regionFaces,
    regionArea,
    materialError,
  )
where

import Control.Monad (unless)
import CraneWing (CraneWing (..), buildCraneWing)
import Data.Bifunctor (first)
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Text (Text)
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Query (Crease (..), Face (..), edgeKey, frameCreases, frameFaces, ringEdges)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (signedArea)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface

data Region = BodyCore | WingA | WingB | Tail | NeckHead
  deriving stock (Eq, Ord, Show)

data EdgeRole = SheetBoundary | UncreasedConnection | AuthoredRoot | CandidateOpening | RetainedPreference
  deriving stock (Eq, Ord, Show)

data PocketEdge = PocketEdge
  { pocketCrease :: !Crease,
    pocketOwners :: ![FaceId],
    pocketRole :: !EdgeRole
  }
  deriving stock (Eq, Show)

data PocketMap = PocketMap
  { pocketSurface :: !(Surface V2),
    pocketRegions :: !(M.Map FaceId Region),
    pocketEdges :: ![PocketEdge],
    pocketCentre :: !VertexId,
    pocketTips :: ![(Region, VertexId)],
    pocketLips :: ![VertexId],
    pocketCoreBoundary :: ![EdgeId]
  }
  deriving stock (Show)

newtype PocketError = PocketError Text deriving stock (Eq, Show)

instance Explain PocketError where explain (PocketError message) = message

regions :: [Region]
regions = [BodyCore, WingA, WingB, Tail, NeckHead]

regionName :: Region -> Text
regionName = \case
  BodyCore -> "Body core"
  WingA -> "Wing A sector"
  WingB -> "Wing B sector"
  Tail -> "Tail sector"
  NeckHead -> "Neck and head sector"

regionKey :: Region -> Text
regionKey = \case
  BodyCore -> "body"
  WingA -> "wing-a"
  WingB -> "wing-b"
  Tail -> "tail"
  NeckHead -> "neck-head"

roleName :: EdgeRole -> Text
roleName = \case
  SheetBoundary -> "Paper edge"
  UncreasedConnection -> "Uncreased connection"
  AuthoredRoot -> "Authored root control"
  CandidateOpening -> "Candidate opening crease"
  RetainedPreference -> "Retain fold preference"

buildCranePocket :: Frame -> Either PocketError PocketMap
buildCranePocket source = do
  crane <- first PocketError (buildCraneWing source)
  sheet <- checked (surfaceFromFolded (craneStart crane))
  mapCranePocket sheet

-- | Resolve landmarks from original-sheet coordinates, never folded proximity
-- or the current numbering of faces. Refuse a changed recipe rather than
-- quietly classifying a face that crosses a sector boundary by its centroid.
mapCranePocket :: Surface V2 -> Either PocketError PocketMap
mapCranePocket sheet = do
  faces <- checked (frameFaces (surfaceFrame sheet))
  creases <- checked (frameCreases (surfaceFrame sheet))
  -- surfaceFeatures omits flat guides. This map needs those edges too: some
  -- region boundaries cross uncreased paper, which must stay connected.
  let incidence = M.fromListWith (++) [(edgeKey a b, [faceId f]) | f <- faces, (a, b) <- ringEdges (faceVertexIds f)]
      features = [(edge, M.findWithDefault [] (edgeKey (creaseFrom edge) (creaseTo edge)) incidence) | edge <- creases]
  unless (length faces == 76 && length features == 138 && length points == 63) $
    Left (PocketError "expected the 76-panel, 138-edge, 63-vertex crane wing fixture")
  unless (M.size incidence == 138 && S.size (S.fromList [edgeKey (creaseFrom e) (creaseTo e) | e <- creases]) == 138 && all ((/= Cut) . creaseAssignment) creases) $
    Left (PocketError "the crane map needs every distinct material edge and no cuts")
  centre <- landmark (V2 0.5 0.5)
  tips <- traverse (\(r, p) -> (r,) <$> landmark p) [(WingA, V2 0 1), (WingB, V2 1 0), (Tail, V2 0 0), (NeckHead, V2 1 1)]
  lips <- traverse landmark [V2 0 0.5, V2 0.5 0, V2 1 0.5, V2 0.5 1]
  named <- traverse (classify centre) faces
  let membership = M.fromList named
      group r = S.fromList [fid | (fid, owner) <- named, r == owner]
      role edge owners
        | length owners == 1 = SheetBoundary
        | creaseAssignment edge `elem` [Flat, Join] = UncreasedConnection
        | creaseAssignment edge == Unassigned = AuthoredRoot
        | any (`S.member` group BodyCore) owners || length (S.fromList [r | fid <- owners, Just r <- [M.lookup fid membership]]) > 1 = CandidateOpening
        | otherwise = RetainedPreference
      edges = [PocketEdge edge owners (role edge owners) | (edge, owners) <- features]
      coreBoundary = [creaseId edge | (edge, owners) <- features, length (filter (`S.member` group BodyCore) owners) == 1]
  unless (all (\(edge, owners) -> length owners `elem` [1, 2] && (length owners == 1) == (creaseAssignment edge == Border)) features) $
    Left (PocketError "the crane needs one owner per paper edge and two per interior material edge")
  unless (length [() | e <- edges, pocketRole e == AuthoredRoot] == 4 && S.size (group BodyCore) == 8) $
    Left (PocketError "expected four authored root controls and eight central body panels")
  mapM_ (\r -> unless (connected (group r) features) (Left (PocketError (regionName r <> " is not one edge-connected material region")))) regions
  mapM_ (\(r, v) -> unless (all (\f -> v `notElem` faceVertexIds f || S.member (faceId f) (group r)) faces) (Left (PocketError ("corner landmark leaves " <> regionName r)))) tips
  let result = PocketMap sheet membership edges centre tips lips coreBoundary
  unless (length coreBoundary == 16 && all (\e -> creaseId (pocketCrease e) `notElem` coreBoundary || length (pocketOwners e) == 2) edges) $
    Left (PocketError "the body core must have sixteen internal interface edges, not an exposed rim")
  unless (abs (sum (map (regionArea result) regions) - 1) < 1e-9 && materialError result < 1e-9) $
    Left (PocketError "the crane map needs the unchanged unit sheet and length-preserving folded panels")
  pure result
  where
    points = surfaceSamples sheet
    indexed = zip (map VertexId [0 ..]) points
    material = M.fromList [(v, sampleMaterial p) | (v, p) <- indexed]
    landmark target = case [v | (v, p) <- indexed, norm (sampleMaterial p ^-^ target) < 1e-9] of
      [v] -> Right v
      _ -> Left (PocketError ("expected one material landmark at " <> tshow target))
    classify centre face
      | centre `elem` faceVertexIds face = Right (faceId face, BodyCore)
      | otherwise = do
          ps <- traverse (\v -> maybe (Left (PocketError ("missing material vertex " <> tshow v))) Right (M.lookup v material)) (faceVertexIds face)
          let left = all (\(V2 x _) -> x <= 0.5 + 1e-9) ps
              right = all (\(V2 x _) -> x >= 0.5 - 1e-9) ps
              bottom = all (\(V2 _ y) -> y <= 0.5 + 1e-9) ps
              top = all (\(V2 _ y) -> y >= 0.5 - 1e-9) ps
          case [r | (r, yes) <- [(WingA, left && top), (WingB, right && bottom), (Tail, left && bottom), (NeckHead, right && top)], yes] of
            [r] -> Right (faceId face, r)
            _ -> Left (PocketError ("panel " <> tshow (faceId face) <> " crosses the material sector boundaries"))

regionFaces :: PocketMap -> Region -> [FaceId]
regionFaces study r = M.keys (M.filter (== r) (pocketRegions study))

regionArea :: PocketMap -> Region -> Double
regionArea study r = sum [abs (signedArea [sampleMaterial p | v <- ring, Just p <- [M.lookup v points]]) | (fid, ring) <- zip (map FaceId [0 ..]) (facesVertices (surfaceFrame (pocketSurface study))), fid `elem` regionFaces study r]
  where
    points = M.fromList (zip (map VertexId [0 ..]) (surfaceSamples (pocketSurface study)))

-- All pairs of corners within each face check the panel, not only its sides.
materialError :: PocketMap -> Double
materialError study = maximum (0 : errors)
  where
    points = M.fromList (zip (map VertexId [0 ..]) (surfaceSamples (pocketSurface study)))
    errors = [abs (norm (position p ^-^ position q) / norm (sampleMaterial p ^-^ sampleMaterial q) - 1) | ring <- facesVertices (surfaceFrame (pocketSurface study)), a <- ring, b <- ring, a < b, Just p <- [M.lookup a points], Just q <- [M.lookup b points]]

connected :: S.Set FaceId -> [(Crease, [FaceId])] -> Bool
connected selected features = case S.lookupMin selected of
  Nothing -> False
  Just seed -> visit (S.singleton seed) == selected
  where
    visit seen =
      let next = S.union seen (S.fromList [b | (_, owners) <- features, any (`S.member` seen) owners, b <- owners, S.member b selected])
       in if next == seen then seen else visit next

checked :: (Explain e) => Either e a -> Either PocketError a
checked = first (PocketError . explain)
