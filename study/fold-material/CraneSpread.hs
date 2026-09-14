-- | Bend an existing crane wing while retaining the rest of the same sheet.
-- CraneWing supplies the connected material, the wing selection and the tail
-- tucked between body layers. Only those four wing panels are refined densely;
-- neighbouring triangles split along shared edges so no seam is opened.
-- See docs/glossary.md for panels, material coordinates and layer order.
--
-- The body stays fixed. A short root strip is held at 30 degrees; a tip grip
-- is turned a further 20 degrees. Integrating those directions gives the
-- grip's position without shortening its material length. The curved initial
-- guess is then relaxed with length, crease, panel-bending and contact terms.
-- This is a static boundary-value experiment, not a motion between grips:
-- intermediate numerical iterates are allowed to stretch and cross paper.
module CraneSpread
  ( CraneSpread (..),
    SpreadError (..),
    SpreadRefinement (..),
    craneSpread,
    craneSpreadWith,
    solveSpread,
    spreadContactOrders,
    crossedGrip,
    spreadCheck,
    spreadAccepted,
    spreadAngleError,
    spreadHeldError,
    spreadSurface,
  )
where

import Control.Monad (unless)
import CraneWing
import Data.Aeson (toJSON)
import Data.Aeson.KeyMap qualified as KM
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Text (Text)
import FoldBending
import FoldRelaxation
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Query (Crease (..), Face (..), frameFaces)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.V3 (V3 (..), polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Flap (flapAt, flapMovingFaces)
import Senbazuru.Origami.Surface
import SurfaceContact qualified as Contact

data CraneSpread = CraneSpread
  { spreadSource :: !(Surface V2),
    spreadRefined :: !RefinedSurface,
    spreadMesh :: !MaterialMesh,
    spreadPins :: !(IM.IntMap V3),
    spreadBody :: !(S.Set Int),
    spreadMoving :: !(S.Set FaceId),
    spreadHinges :: ![Hinge],
    spreadOrders :: ![(FaceId, FaceId)],
    spreadGrip :: !(S.Set Int)
  }
  deriving stock (Show)

-- | Refinement changes resolution, not which vertices are held. The root
-- study needs triangles on both sides of the root before releasing body pins.
data SpreadRefinement = WingOnly | WingAndRootNeighbours
  deriving stock (Eq, Show)

newtype SpreadError = SpreadError Text deriving stock (Eq, Show)

instance Explain SpreadError where explain (SpreadError message) = message

-- | The study controls are deliberately small: root 30 degrees, extra grip
-- rotation 0..20 degrees, refinement 3 or 4 (eight or sixteen spans per wing).
-- These levels represent the same 1/8-span root and tip strips exactly.
craneSpread :: Frame -> Int -> Double -> Either SpreadError CraneSpread
craneSpread = craneSpreadWith WingOnly

craneSpreadWith :: SpreadRefinement -> Frame -> Int -> Double -> Either SpreadError CraneSpread
craneSpreadWith selection source level degrees = do
  unless (level `elem` [3, 4] && finite degrees && degrees >= 0 && degrees <= 20) $
    Left (SpreadError "crane spreading requires refinement 3 or 4 and a finite extra grip angle from 0 to 20 degrees")
  wing <- first SpreadError (buildCraneWing source)
  sheet <- checked (surfaceFromFolded (craneStart wing))
  reference <- checked (flapAt (craneOpening wing) (30 / 90))
  features <- checked (surfaceFeatures sheet)
  let moving = S.fromList (flapMovingFaces (craneOpening wing))
      rootAngles = IM.fromList (zip [0 ..] (edgesFoldAngle (surfaceFrame reference)))
      rest edge
        | creaseId edge `elem` craneHinge wing = IM.findWithDefault 0 (unEdgeId (creaseId edge)) rootAngles * pi / 180
        | creaseAssignment edge == Mountain = -pi
        | otherwise = pi
      targets = M.fromList [(creaseId edge, rest edge) | (edge, _) <- features, creaseAssignment edge `notElem` [Border, Cut]]
      selectedPanels = case selection of
        WingOnly -> moving
        WingAndRootNeighbours -> S.union moving (S.fromList [owner | (edge, owners) <- features, creaseId edge `elem` craneHinge wing, owner <- owners])
  (refined, hinges) <- checked (buildSelectedSurfaceHinges (Bending 1 0.2) level selectedPanels sheet targets)
  let base = refinedMesh refined
      tagged = zip (triangles base) (refinedPanels refined)
      body = S.fromList [v | (tri, owner) <- tagged, S.notMember owner moving, v <- vertices tri]
      selected = S.fromList [v | (tri, owner) <- tagged, S.member owner moving, v <- vertices tri]
      fraction p = let V3 _ y _ = position p in (0.25 - y) / 0.25
      grip = S.fromList [i | (i, p) <- zip [0 ..] (samples base), S.member i selected, fraction p >= 0.875 - 1e-8]
      moved = [if S.member i selected && S.notMember i body then p {position = bentPoint degrees (position p)} else p | (i, p) <- zip [0 ..] (samples base)]
      held i p = S.member i body || (S.member i selected && fraction p <= 0.125 + 1e-8) || S.member i grip
      pins = IM.fromList [(i, position q) | (i, (p, q)) <- zip [0 ..] (zip (samples base) moved), held i p]
  faces <- checked (frameFaces (surfaceFrame sheet))
  let normals = M.fromList [(faceId face, polygonNormal (faceCorners face)) | face <- faces]
      order pair = do
        V3 _ _ z <- maybe (Left (SpreadError "missing source panel normal")) Right (M.lookup (orderRelativeTo pair) normals)
        let above = (orderStacking pair == Above) == (z > 0)
        pure (if above then (orderRelativeTo pair, orderFace pair) else (orderFace pair, orderRelativeTo pair))
  orders <- mapM order (faceOrders (surfaceFrame sheet))
  pure (CraneSpread sheet refined base {samples = moved} pins body moving hinges orders grip)

-- The root is y=1/4 in this fixture's folded coordinates. x follows the wing
-- width; length runs towards decreasing y. Integrate unit tangents through a
-- circular arc between the two held strips. Zero curvature is the rigid limit.
bentPoint :: Double -> V3 -> V3
bentPoint degrees (V3 x y _) =
  let len = 0.25 - y
      start = 0.25 * 0.125
      stop = 0.25 * 0.875
      root = 30 * pi / 180
      turn = degrees * pi / 180
      arc = stop - start
      middle = max 0 (min arc (len - start))
      curvature = turn / arc
      before = min start len
      after = max 0 (len - stop)
      dy = if degrees == 0 then middle * cos root else (sin (root + curvature * middle) - sin root) / curvature
      dz = if degrees == 0 then middle * sin root else (cos root - cos (root + curvature * middle)) / curvature
   in V3 x (0.25 - before * cos root - dy - after * cos (root + turn)) (-(before * sin root) - dz - after * sin (root + turn))

solveSpread :: Settings -> CraneSpread -> Either SpreadError Relaxation
solveSpread settings fixture = do
  contact <- checked (Contact.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) (spreadMesh fixture))
  checked (relaxPinnedContact settings (spreadPins fixture) (spreadHinges fixture) contact (spreadMesh fixture))

-- | An order needs force rows whenever either panel has a free vertex. In the
-- original experiment this is just the wing; releasing body pins must also
-- activate body/body contacts. The independent check still examines ALL
-- triangles and source orders, including those between entirely held panels.
-- Expand transitive orders BEFORE dropping constant pairs: A below held B,
-- and B below held C, still requires moving A below C when they overlap.
spreadContactOrders :: CraneSpread -> [(FaceId, FaceId)]
spreadContactOrders fixture = [(a, b) | (a, b) <- S.toAscList (closure (S.fromList (spreadOrders fixture))), S.member a moving || S.member b moving]
  where
    moving = S.fromList [owner | (tri, owner) <- zip (triangles (spreadMesh fixture)) (refinedPanels (spreadRefined fixture)), any (`IM.notMember` spreadPins fixture) (vertices tri)]

-- | Deliberately push an upper grip through its lower partner. Shared material
-- vertices remain shared; only independent upper-layer grip vertices move.
-- Exact, incompatible pins cannot be repaired by a successful linear solve.
crossedGrip :: CraneSpread -> CraneSpread
crossedGrip fixture = fixture {spreadPins = pins, spreadMesh = mesh {samples = moved}}
  where
    mesh = spreadMesh fixture
    groups = M.fromListWith S.union [(owner, S.fromList (vertices tri)) | (tri, owner) <- zip (triangles mesh) (refinedPanels (spreadRefined fixture))]
    group owner = M.findWithDefault S.empty owner groups
    upperGrip = S.unions [S.intersection (spreadGrip fixture) (S.difference (group upper) (group lower)) | (lower, upper) <- spreadOrders fixture, S.member lower (spreadMoving fixture), S.member upper (spreadMoving fixture)]
    pins = IM.mapWithKey (\i p -> if S.member i upperGrip then p ^-^ V3 0 0 0.005 else p) (spreadPins fixture)
    moved = [p {position = IM.findWithDefault (position p) i pins} | (i, p) <- zip [0 ..] (samples mesh)]

spreadCheck :: CraneSpread -> MaterialMesh -> Either SpreadError ContactCheck
spreadCheck fixture mesh = do
  preserveMaterial fixture mesh
  checked (checkTriangleContact (V3 0 0 1) (spreadOrders fixture) (refinedPanels (spreadRefined fixture)) mesh)

spreadHeldError :: CraneSpread -> MaterialMesh -> Double
spreadHeldError fixture mesh = maximum (0 : [norm (position p ^-^ target) | (i, p) <- zip [0 ..] (samples mesh), Just target <- [IM.lookup i (spreadPins fixture)]])

spreadAngleError :: CraneSpread -> MaterialMesh -> Either SpreadError Double
spreadAngleError fixture mesh = do
  let points = IM.fromList (zip [0 ..] (samples mesh))
  errors <- mapM (\h -> abs . (`angleError` hingeRest h) . fst <$> checked (hingeAngle h points)) [h | h <- spreadHinges fixture, SurfaceCrease _ <- [hingeRole h]]
  pure (maximum (0 : errors))

spreadAccepted :: CraneSpread -> Relaxation -> MaterialMesh -> Either SpreadError Bool
spreadAccepted fixture result mesh = do
  report <- spreadCheck fixture mesh
  angles <- spreadAngleError fixture mesh
  pure (converged result && maxLengthError mesh <= 1e-5 && spreadHeldError fixture mesh == 0 && angles < 1e-5 && contactPassed report)

-- | The exported faces are planar mesh triangles, not the original curved
-- panels. Retain source ids as metadata; generated internal edges are J joins.
-- Expand only known source orders at overlapping triangle shadows. Signs must
-- follow the upper triangle's normal, which reverses on the other paper side.
spreadSurface :: CraneSpread -> MaterialMesh -> Either SpreadError (Surface V2)
spreadSurface fixture mesh = do
  preserveMaterial fixture mesh
  overlaps <- checked (Contact.overlapCandidates (V3 0 0 1) owners mesh)
  let reachable = closure (S.fromList (spreadOrders fixture))
      points = IM.fromList (zip [0 ..] (map position (samples mesh)))
      normals = IM.fromList [(i, polygonNormal [p | v <- vertices tri, Just p <- [IM.lookup v points]]) | (i, tri) <- zip [0 ..] (triangles mesh)]
      makeOrder candidate =
        let (a, b) = Contact.candidatePanels candidate
            (i, j) = Contact.candidateTriangles candidate
            pair
              | S.member (a, b) reachable = Just (i, j)
              | S.member (b, a) reachable = Just (j, i)
              | otherwise = Nothing
         in case pair of
              Nothing -> []
              Just (lower, upper) -> case IM.lookup upper normals of
                Just (V3 _ _ z) -> [FaceOrder (FaceId lower) (FaceId upper) (if z > 0 then Below else Above)]
                Nothing -> []
      incidence = M.fromListWith (+) [(key a b, 1 :: Int) | (i, j, k) <- triangles mesh, (a, b) <- [(i, j), (j, k), (k, i)]]
      edges = M.toAscList incidence
      sourceEdges = M.fromList [(key a b, eid) | (eid, (a, b)) <- refinedEdges (spreadRefined fixture)]
      assignments = M.fromList (zip (map EdgeId [0 ..]) (edgesAssignment (surfaceFrame (spreadSource fixture))))
      assignment (edge, n) = case M.lookup edge sourceEdges >>= (`M.lookup` assignments) of
        Just value -> value
        Nothing -> if n == 1 then Border else Join
      coords (V3 x y z) = [x, y, z]
      frame =
        emptyFrame
          { frameClasses = ["foldedForm"],
            frameAttributes = ["3D"],
            verticesCoords = map (coords . position) (samples mesh),
            facesVertices = [map VertexId (vertices tri) | tri <- triangles mesh],
            edgesVertices = [(VertexId a, VertexId b) | ((a, b), _) <- edges],
            edgesAssignment = map assignment edges,
            faceOrders = concatMap makeOrder overlaps,
            frameExtras =
              KM.fromList
                [ ("senbazuru:material_coords", toJSON [[materialU p, materialV p] | p <- samples mesh]),
                  ("senbazuru:source_panels", toJSON (map unFaceId owners)),
                  ("senbazuru:source_edges", toJSON [fmap unEdgeId (M.lookup edge sourceEdges) | (edge, _) <- edges])
                ]
          }
  checked (surfaceFromFrame frame >>= requireMaterialCoordinates)
  where
    owners = refinedPanels (spreadRefined fixture)

preserveMaterial :: CraneSpread -> MaterialMesh -> Either SpreadError ()
preserveMaterial fixture mesh = unless (triangles mesh == triangles original && map sampleMaterial (samples mesh) == map sampleMaterial (samples original)) (Left (SpreadError "crane spreading must retain the full sheet's material and triangle identities"))
  where
    original = refinedMesh (spreadRefined fixture)

vertices :: Triangle -> [Int]
vertices (a, b, c) = [a, b, c]

key :: Int -> Int -> (Int, Int)
key a b = (min a b, max a b)

closure :: (Ord a) => S.Set (a, a) -> S.Set (a, a)
closure pairs = let more = S.union pairs (S.fromList [(a, c) | (a, b) <- S.toList pairs, (b', c) <- S.toList pairs, b == b']) in if more == pairs then pairs else closure more

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)

checked :: (Explain e) => Either e a -> Either SpreadError a
checked = first (SpreadError . explain)
