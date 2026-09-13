-- | Turn one connected flap and check its entire path before exporting poses.
-- A flap here is the set of faces reached after removing the selected creases
-- from the face graph. Those creases must all separate moving from stationary
-- paper and lie on one line in the CURRENT folded shape. A hinge can therefore
-- cross several graph edges, or turn several touching layers together. An
-- incomplete cut is refused; this operation does not discover coupled motions.
-- See docs/glossary.md for faces, creases, material coordinates and fold angles.
--
-- Start with 'foldFrameWith' and select ids from its 'foldedPattern', since
-- cutting crossings can renumber the input. Travel is a signed CHANGE in the
-- crease's FOLD angle, in degrees. The stationary face's counterclockwise edge
-- direction needs the NEGATIVE of that travel as a right-hand rotation; this
-- is the same convention used by "Senbazuru.Origami.Folding".
-- With several segments, the first crease defines the sign. A stationary face
-- on an upside-down layer can orient its segment the other way, so its FOLD
-- angle must change with the OPPOSITE sign for the same physical rotation.
-- See docs/notes/aligned-crease-hinges.md for the helmet-base example.
--
-- Preparation identifies the flap. Checking produces an opaque 'CheckedFlap';
-- only that value supplies public poses. Each pose is independently re-folded
-- from angles, checking both shared vertices and achieved crease angles, then
-- aligned to keep the stationary side still. No vertex interpolation is used.
-- Comparing it with the specified hinge path prevents a camera-like change
-- of anchoring from making the checked motion differ from the exported one.
--
-- The interval checker works on geometry normalized by the original sheet's
-- span. Exported coordinates keep their original units and material ids. This
-- inherits HingeSweep's numerical guard, zero-thickness model and conservative
-- refusals. Flat endpoints need a one-sided half-turn (or shorter) approach
-- in a plane containing the hinge. A touching stack may move together, or stay
-- still, when its supplied face orders are consistent and its panels coplanar.
-- The common rigid motion preserves those orders against panel normals even
-- as the whole stack turns over. Each overlapping pair needs a supplied order;
-- this operation does not infer a stack from coincident positions.
-- An unjoined stack edge may rest on the lifting hinge when its declared
-- partner supplies the shared boundary and the plane separation check passes;
-- see docs/notes/free-edges-on-a-hinge.md. Material vertices stay distinct.
-- Endpoint layers follow that approach. At the start they must agree with any
-- supplied orders; without orders, departure selects the previously unknown
-- touching side. Other poses retain only the validated stack orders. A refusal
-- can be a contact witness, contradictory order or an unresolved interval,
-- never a claim to have found the earliest impact. Stale face orders are
-- not used to exempt untested pairs from contact checks.
-- A hinge may rest on an initially coplanar layer's interior while the moving
-- paper lifts strictly to one side. Coplanar pairs, including pairs meeting
-- only at an edge, are offered to HingeSweep's resting-plane check; this names
-- candidates, not accepted contact. Any resulting departure orders must agree
-- with the supplied order. See docs/notes/a-wing-resting-on-paper.md.
module Senbazuru.Origami.Flap
  ( FlapMotion,
    CheckedFlap,
    FlapError (..),
    prepareFlap,
    prepareFlapAlong,
    checkFlap,
    flapAt,
    flapCheck,
    flapMovingFaces,
  )
where

import Control.Monad (unless, when)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (find, nub, sort)
import Data.Map.Strict qualified as M
import Data.Maybe (fromMaybe)
import Data.Set qualified as S
import Senbazuru.Explain (Explain (..), num, tshow)
import Senbazuru.Fold.Query (Crease (..), Face (..), FoldError, edgeKey, facesAlongEdges, frameCreases, frameFaces, frameVertices, ringEdges)
import Senbazuru.Fold.Types (Assignment (..), EdgeId (..), FaceId (..), FaceOrder (..), Frame (..), Stacking (..), VertexId (..))
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.Rigid (Rigid, after, inverse)
import Senbazuru.Geometry.V3 (V3 (..), cross, modelSpan, polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding (Folded (..), FoldingError, foldFrameWith)
import Senbazuru.Origami.HingeSweep
import Senbazuru.Origami.Layers (layerDepths)
import Senbazuru.Origami.Surface

data FlapMotion = FlapMotion
  { initialFold :: !Folded,
    creaseTravels :: ![(EdgeId, Double)],
    movingFaces :: ![FaceId],
    stationaryFace :: !FaceId,
    checkOrigin :: !V3,
    checkScale :: !Double,
    checkedPath :: !HingeSweep,
    triangleOwners :: ![FaceId],
    startingOrders :: ![FaceOrder],
    rigidOrders :: ![FaceOrder]
  }
  deriving stock (Show)

data CheckedFlap = CheckedFlap !FlapMotion !SweepCheck
  deriving stock (Show)

data FlapError
  = FlapFolding !FoldingError
  | FlapGeometry !FoldError
  | FlapSurface !SurfaceError
  | FlapSweep !SweepError
  | FlapMissingCrease !EdgeId
  | FlapNotHinge !EdgeId
  | FlapWrongSide !EdgeId !FaceId
  | FlapCoupled !EdgeId ![VertexId]
  | FlapEmptyHinge
  | FlapDuplicateCrease !EdgeId
  | FlapNotBoundary !EdgeId
  | FlapUnalignedCrease !EdgeId
  | FlapMissingFace !FaceId
  | FlapMissingOwner !Int
  | FlapMissingVertex !VertexId
  | FlapStartMismatch
  | FlapInvalidTravel !Double
  | FlapInvalidProgress !Double
  | FlapPathMismatch !VertexId
  | FlapCollision !Double ![(FaceId, FaceId)]
  | FlapUnresolved !Double !Double ![(FaceId, FaceId)]
  | FlapEndpointOrder !Double !FoldError
  | FlapStackOrder !FoldError
  deriving stock (Eq, Show)

instance Explain FlapError where
  explain = \case
    FlapFolding err -> explain err
    FlapGeometry err -> explain err
    FlapSurface err -> explain err
    FlapSweep err -> explain err
    FlapMissingCrease eid -> "flap crease " <> tshow (unEdgeId eid) <> " is absent from the cut pattern"
    FlapNotHinge eid -> "edge " <> tshow (unEdgeId eid) <> " must be a crease joining exactly two faces"
    FlapWrongSide eid fid -> "moving face " <> tshow (unFaceId fid) <> " must touch crease " <> tshow (unEdgeId eid)
    FlapCoupled eid vertices -> "crease " <> tshow (unEdgeId eid) <> " does not separate a flap: other creases must move around vertices " <> tshow (map unVertexId vertices)
    FlapEmptyHinge -> "a flap hinge needs at least one crease"
    FlapDuplicateCrease eid -> "flap hinge repeats crease " <> tshow (unEdgeId eid)
    FlapNotBoundary eid -> "selected crease " <> tshow (unEdgeId eid) <> " must separate moving from stationary paper"
    FlapUnalignedCrease eid -> "selected crease " <> tshow (unEdgeId eid) <> " is not on the common hinge line in the folded paper"
    FlapMissingFace fid -> "flap is missing face or placement " <> tshow (unFaceId fid)
    FlapMissingOwner i -> "flap contact triangle " <> tshow i <> " is missing its source face"
    FlapMissingVertex vid -> "flap is missing material vertex " <> tshow (unVertexId vid)
    FlapStartMismatch -> "flap start must be the unmodified result of foldFrameWith, including its cut pattern and explicit angles"
    FlapInvalidTravel value -> "flap travel must be finite and at most 360 degrees; got " <> tshow value
    FlapInvalidProgress value -> "flap progress must be between 0 and 1; got " <> tshow value
    FlapPathMismatch vid -> "angle-derived flap pose disagrees with the checked hinge path at vertex " <> tshow (unVertexId vid)
    FlapCollision t pairs -> "flap path refused: contact between faces " <> facePairs pairs <> " at progress " <> num t <> " (a witness, not the first impact time)"
    FlapUnresolved lo hi pairs -> "flap path unresolved between progress " <> num lo <> " and " <> num hi <> " for faces " <> facePairs pairs
    FlapEndpointOrder t err -> "flap layer order contradicts its approach/departure at progress " <> num t <> ": " <> explain err
    FlapStackOrder err -> "flap stack has contradictory layer orders: " <> explain err
    where
      facePairs pairs = tshow [(unFaceId a, unFaceId b) | (a, b) <- pairs]

-- | Crease id, incident face on the moving side, signed travel in degrees,
-- and a folding result. The ids belong to its returned cut pattern.
prepareFlap :: EdgeId -> FaceId -> Double -> Folded -> Either FlapError FlapMotion
prepareFlap eid = prepareFlapAlong [eid]

-- | Select every segment of one physical hinge. The first crease must touch
-- the supplied moving face, and travel is the change in THAT crease's FOLD
-- angle. Other segments receive the sign required by their stationary face's
-- orientation. Ids need not be consecutive or share material vertices: two
-- layers can have distinct creases on the same line in the folded paper.
prepareFlapAlong :: [EdgeId] -> FaceId -> Double -> Folded -> Either FlapError FlapMotion
prepareFlapAlong [] _ _ _ = Left FlapEmptyHinge
prepareFlapAlong eids@(eid : _) side travel supplied = do
  unless (finite travel && abs travel <= 360) (Left (FlapInvalidTravel travel))
  case [e | (i, e) <- zip [0 :: Int ..] eids, e `elem` take i eids] of
    repeated : _ -> Left (FlapDuplicateCrease repeated)
    [] -> pure ()
  -- Folded's constructor is public. Rebuild its angle state instead of trusting
  -- supplied transforms or using arbitrary coordinates as the starting paper.
  let suppliedFrame = foldedFrame supplied
      flat = (foldedPattern supplied) {edgesFoldAngle = edgesFoldAngle suppliedFrame, faceOrders = [], frameExtras = mempty}
  unless (length (edgesFoldAngle suppliedFrame) == length (edgesVertices flat)) (Left FlapStartMismatch)
  _ <- first FlapSurface (surfaceFromFolded supplied)
  start <- first FlapFolding (foldFrameWith flat)
  material <- first FlapGeometry (frameVertices (foldedPattern start))
  actual <- first FlapGeometry (frameVertices suppliedFrame)
  expected <- first FlapGeometry (frameVertices (foldedFrame start))
  let scale = modelSpan material
  unless (facesVertices suppliedFrame == facesVertices (foldedFrame start)) (Left FlapStartMismatch)
  unless (finite scale && scale > 0 && length actual == length expected && and (zipWith (\a b -> norm (a ^-^ b) / scale < 1e-9) actual expected)) (Left FlapStartMismatch)
  faces <- first FlapGeometry (frameFaces (foldedFrame start))
  neighbours <- first FlapGeometry (facesAlongEdges faces)
  creases <- first FlapGeometry (frameCreases (foldedFrame start))
  let segment e = do
        crease <- maybe (Left (FlapMissingCrease e)) Right (find ((== e) . creaseId) creases)
        unless (creaseAssignment crease `elem` [Mountain, Valley, Unassigned]) (Left (FlapNotHinge e))
        (a, b) <- maybe (Left (FlapMissingCrease e)) Right (lookup e (zip (map EdgeId [0 ..]) (edgesVertices flat)))
        case M.findWithDefault [] (edgeKey a b) neighbours of
          [left, right] -> Right (e, a, b, left, right)
          _ -> Left (FlapNotHinge e)
  segments <- traverse segment eids
  (_, a, b, leftFace, rightFace) <- segment eid
  let key = edgeKey a b
  fixed <- if side == leftFace then Right rightFace else if side == rightFace then Right leftFace else Left (FlapWrongSide eid side)
  let removed = S.fromList [edgeKey x y | (_, x, y, _, _) <- segments]
      links = [(x, y) | (edge, [x, y]) <- M.toList neighbours, S.notMember edge removed]
      selected = connected links S.empty [side]
  when (S.member fixed selected) (Left (FlapCoupled eid [a, b]))
  fixedPanel <- maybe (Left (FlapMissingFace fixed)) Right (find ((== fixed) . faceId) faces)
  (from, to) <- maybe (Left (FlapNotHinge eid)) Right (find (\(x, y) -> edgeKey x y == key) (ringEdges (faceVertexIds fixedPanel)))
  let vertices = IM.fromList (zip [0 ..] expected)
      point vid = maybe (Left (FlapMissingVertex vid)) Right (IM.lookup (unVertexId vid) vertices)
  origin <- point from
  finish <- point to
  let axis = (1 / norm (finish ^-^ origin)) *^ (finish ^-^ origin)
      onLine p = norm (cross axis ((1 / scale) *^ (p ^-^ origin))) < 1e-12
      segmentTravel (e, x, y, left, right) = do
        unless (S.member left selected /= S.member right selected) (Left (FlapNotBoundary e))
        let stationary = if S.member left selected then right else left
        panel <- maybe (Left (FlapMissingFace stationary)) Right (find ((== stationary) . faceId) faces)
        (u, v) <- maybe (Left (FlapNotHinge e)) Right (find (\(p, q) -> edgeKey p q == edgeKey x y) (ringEdges (faceVertexIds panel)))
        p <- point u
        q <- point v
        unless (onLine p && onLine q) (Left (FlapUnalignedCrease e))
        pure (e, if dot axis (q ^-^ p) > 0 then travel else negate travel)
  travels <- traverse segmentTravel segments
  sheet <- first FlapSurface (surfaceFromFolded start)
  (mesh, owners) <- first FlapSurface (refineSurface 0 sheet)
  let normalized = mesh {samples = [p {position = (1 / scale) *^ (position p ^-^ origin)} | p <- samples mesh]}
      moving = S.toList (S.fromList [unVertexId vid | face <- faces, S.member (faceId face) selected, vid <- faceVertexIds face])
  sweep <- first FlapSweep (prepareSweep (V3 0 0 0) ((1 / scale) *^ (finish ^-^ origin)) (negate travel * pi / 180) moving normalized)
  let suppliedOrders = faceOrders suppliedFrame
      sameMotion o = S.member (orderFace o) selected == S.member (orderRelativeTo o) selected
      retained =
        [ o
          | o <- suppliedOrders,
            orderStacking o /= Unordered,
            sameMotion o,
            Just f <- [find ((== orderFace o) . faceId) faces],
            Just g <- [find ((== orderRelativeTo o) . faceId) faces],
            coplanarFaces scale f g
        ]
      motion = FlapMotion start travels (S.toList selected) fixed origin scale sweep owners suppliedOrders retained
  checkOrders FlapStackOrder scale faces retained
  -- The same refolding/anchoring path supplies all subsequent public poses.
  _ <- surfaceAt motion 1
  _ <- surfaceAt motion 0.5
  pure motion

connected :: [(FaceId, FaceId)] -> S.Set FaceId -> [FaceId] -> S.Set FaceId
connected _ visited [] = visited
connected links visited (face : rest)
  | S.member face visited = connected links visited rest
  | otherwise =
      let next = [b | (a, b) <- links, a == face] ++ [a | (a, b) <- links, b == face]
       in connected links (S.insert face visited) (next ++ rest)

checkFlap :: SweepSettings -> FlapMotion -> Either FlapError CheckedFlap
checkFlap settings motion = do
  faces <- first FlapGeometry (frameFaces (foldedFrame (initialFold motion)))
  let ordered a b = any (\o -> (orderFace o == a && orderRelativeTo o == b) || (orderFace o == b && orderRelativeTo o == a)) (rigidOrders motion)
      contacts =
        [ (i, j)
          | (i, a) <- zip [0 ..] (triangleOwners motion),
            (j, b) <- zip [0 ..] (triangleOwners motion),
            i < j,
            ordered a b
        ]
      resting =
        [ (i, j)
          | (i, a) <- zip [0 ..] (triangleOwners motion),
            (j, b) <- zip [0 ..] (triangleOwners motion),
            i < j,
            (a `elem` movingFaces motion) /= (b `elem` movingFaces motion),
            Just f <- [find ((== a) . faceId) faces],
            Just g <- [find ((== b) . faceId) faces],
            coplanarFaces (checkScale motion) f g
        ]
  result <- first FlapSweep (checkSweepWithLayerContacts settings contacts resting (checkedPath motion))
  let owners = IM.fromList (zip [0 ..] (triangleOwners motion))
      sourcePairs pairs = sort (nub [(min a b, max a b) | (i, j) <- pairs, Just a <- [IM.lookup i owners], Just b <- [IM.lookup j owners]])
  case sweepOutcome result of
    SweepClear -> do
      -- Fan triangles retain their source face's winding, so each contact's
      -- side is already a FOLD order against the stationary face's normal.
      mapM_ (checkEndpointOrder motion result) [0, 1]
      Right (CheckedFlap motion result)
    SweepCollision t pairs -> Left (FlapCollision t (sourcePairs pairs))
    SweepUnresolved lo hi pairs -> Left (FlapUnresolved lo hi (sourcePairs pairs))

flapCheck :: CheckedFlap -> SweepCheck
flapCheck (CheckedFlap _ result) = result

flapMovingFaces :: CheckedFlap -> [FaceId]
flapMovingFaces (CheckedFlap motion _) = movingFaces motion

-- | A checked angle state at a fraction of the accepted motion. The returned
-- surface supplies both renderers and its materialFrame supplies FOLD output.
flapAt :: CheckedFlap -> Double -> Either FlapError (Surface V2)
flapAt (CheckedFlap motion result) progress = do
  surface <- surfaceAt motion progress
  orders <- endpointOrders motion result progress
  first FlapSurface (withFaceOrders (nub (rigidOrders motion ++ orders)) surface)

endpointOrders :: FlapMotion -> SweepCheck -> Double -> Either FlapError [FaceOrder]
endpointOrders motion report progress = nub <$> traverse order [c | c <- sweepEndpointContacts report, contactProgress c == progress]
  where
    owners = IM.fromList (zip [0 ..] (triangleOwners motion))
    owner i = maybe (Left (FlapMissingOwner i)) Right (IM.lookup i owners)
    order c = FaceOrder <$> owner (contactMoving c) <*> owner (contactFixed c) <*> pure (if contactSide c > 0 then Above else Below)

checkEndpointOrder :: FlapMotion -> SweepCheck -> Double -> Either FlapError ()
checkEndpointOrder motion report progress = do
  surface <- surfaceAt motion progress
  faces <- first FlapGeometry (frameFaces (surfaceFrame surface))
  orders <- endpointOrders motion report progress
  -- Test each contact plane separately: orders on different planes are not a
  -- global painting order. Include the given initial orders so reopening a
  -- flat flap cannot silently put it through the layer it was resting on.
  let supplied = [o | progress == 0, o <- startingOrders motion]
  checkOrders (FlapEndpointOrder progress) (checkScale motion) faces (supplied ++ rigidOrders motion ++ orders)

-- Check each plane independently. A paper-relative order rotates with its
-- panels, so using world z would miss contradictory orders on an upright stack.
checkOrders :: (FoldError -> FlapError) -> Double -> [Face] -> [FaceOrder] -> Either FlapError ()
checkOrders mapError scale faces orders = mapM_ check orders
  where
    check order = case find ((== orderRelativeTo order) . faceId) faces of
      Nothing -> Left (FlapMissingFace (orderRelativeTo order))
      Just fixed -> case faceCorners fixed of
        [] -> Left (FlapMissingFace (faceId fixed))
        _ : _ -> do
          let n = polygonNormal (faceCorners fixed)
              group = filter (coplanarFaces scale fixed) faces
              members = map faceId group
              relevant = [o | o <- orders, orderFace o `elem` members, orderRelativeTo o `elem` members]
          _ <- first mapError (layerDepths n group relevant)
          pure ()

coplanarFaces :: Double -> Face -> Face -> Bool
coplanarFaces scale a b = inPlane a b && inPlane b a
  where
    inPlane f g = case faceCorners f of
      [] -> False
      origin : _ -> let n = polygonNormal (faceCorners f) in norm n > 0 && all (\p -> abs (dot n (p ^-^ origin)) <= 64 * encodeFloat 1 (-52) * scale * norm n) (faceCorners g)

surfaceAt :: FlapMotion -> Double -> Either FlapError (Surface V2)
surfaceAt motion progress = do
  unless (finite progress && progress >= 0 && progress <= 1) (Left (FlapInvalidProgress progress))
  let start = initialFold motion
      frame = foldedFrame start
      angles = [angle + progress * fromMaybe 0 (lookup (EdgeId i) (creaseTravels motion)) | (i, angle) <- zip [0 ..] (edgesFoldAngle frame)]
      sheet = (foldedPattern start) {edgesFoldAngle = angles, faceOrders = [], frameExtras = mempty}
  placed <- first FlapFolding (foldFrameWith sheet)
  before <- placement (stationaryFace motion) start
  afterPose <- placement (stationaryFace motion) placed
  surface <- first FlapSurface (surfaceFromFolded placed >>= transformSurface (before `after` inverse afterPose))
  path <- first FlapSweep (sweepMeshAt (checkedPath motion) progress)
  unless (length (surfaceSamples surface) == length (samples path)) (Left FlapStartMismatch)
  mapM_ (comparePoint motion) (zip3 [0 ..] (surfaceSamples surface) (samples path))
  pure surface

placement :: FaceId -> Folded -> Either FlapError Rigid
placement fid folded = maybe (Left (FlapMissingFace fid)) Right (IM.lookup (unFaceId fid) (foldedPlacements folded))

comparePoint :: FlapMotion -> (Int, MaterialSample, MaterialSample) -> Either FlapError ()
comparePoint motion (i, actual, expected) =
  let normalized = (1 / checkScale motion) *^ (position actual ^-^ checkOrigin motion)
   in unless (norm (normalized ^-^ position expected) < 1e-9) (Left (FlapPathMismatch (VertexId i)))

finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)
