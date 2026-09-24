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
-- See @docs\/notes\/aligned-crease-hinges.md@ for the helmet-base example.
--
-- 'prepareFlapToward' takes a direction, +z or -z, in place of a sign and
-- signs the travel itself. A 'Toward' names where the moving paper beside the
-- hinge goes: 'TowardPlusZ' is the turn that sets it off towards +z, whether
-- it lies flat beyond the hinge or is already folded over. A positive change
-- in a crease's angle moves the face beside it towards that face's own top,
-- so the sign depends on which way up the moving face beside each crease
-- lies, which is its placement applied to +z and not its winding. In the
-- blintz, which folds the four corners of a square to its centre, a corner
-- folded flat under the centre comes back out by a 'TowardMinusZ' turn, since
-- it sets off downwards; turned 'TowardPlusZ' it would swing up through the
-- centre, and checking refuses that turn.
--
-- Every moving face beside the hinge is read, and two things refuse a turn
-- rather than guess it. Those faces must all lie on one side of the hinge
-- line, since a turn lifts the paper on one side of its line and lowers it on
-- the other. And each must lie flat, by the same 'hasRelief' the rest of the
-- library judges flatness with: one standing on edge shows neither its top nor
-- its back towards +z, and one tilted past vertical would read the turn that
-- finishes its own fold as the opposite way. This module first read the face
-- held still beside the first crease. That agrees on an open hinge, whose two
-- faces are one flat sheet, but gives the opposite answer on a hinge folded
-- shut, and it made a page turn depend on which crease was listed first. See
-- @docs\/notes\/turning-towards-a-side.md@, and the glossary for a page turn.
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
-- see @docs\/notes\/free-edges-on-a-hinge.md@. Material vertices stay distinct.
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
-- with the supplied order. See @docs\/notes\/a-wing-resting-on-paper.md@.
module Senbazuru.Origami.Flap
  ( FlapMotion,
    CheckedFlap,
    FlapError (..),
    Toward (..),
    prepareFlap,
    prepareFlapAlong,
    prepareFlapToward,
    checkFlap,
    flapAt,
    flapCheck,
    flapMovingFaces,
    flapStationaryFace,
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
import Senbazuru.Geometry.V3 (V3 (..), cross, hasRelief, modelSpan, polygonNormal, zSpan)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding (Folded (..), FoldingError, facesUp, foldFrameWith)
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
  deriving stock (Eq, Show)

data CheckedFlap = CheckedFlap !FlapMotion !SweepCheck
  deriving stock (Eq, Show)

-- | Which way the moving paper beside the hinge sets off, for
-- 'prepareFlapToward': towards +z or towards -z. The +z is the given
-- 'Folded'\'s own, the only coordinates this module measures in, which is why
-- the names carry no other frame: a caller that shows the model turned over
-- converts its direction before asking.
data Toward = TowardPlusZ | TowardMinusZ
  deriving stock (Eq, Show)

data FlapError
  = FlapFolding !FoldingError
  | FlapGeometry !FoldError
  | FlapSurface !SurfaceError
  | FlapSweep !SweepError
  | FlapMissingCrease !EdgeId
  | FlapNotHinge !EdgeId
  | FlapWrongSide !EdgeId !FaceId
  | FlapCoupled !EdgeId ![VertexId]
  | FlapMovingNotFlat !FaceId !Double
  | FlapMovesBothWays !FaceId !FaceId
  | FlapEmptyHinge
  | FlapDuplicateCrease !EdgeId
  | FlapNotBoundary !EdgeId
  | FlapUnalignedCrease !EdgeId
  | FlapMissingFace !FaceId
  | FlapMissingOwner !Int
  | FlapMissingVertex !VertexId
  | FlapStartMismatch
  | FlapInvalidTravel !Double
  | FlapInvalidTurn !Double
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
    FlapMovingNotFlat fid spread -> "(internal face " <> tshow (unFaceId fid) <> "), which moves beside the hinge, does not lie flat, and a turn towards +z or -z is read only from moving faces that do: its corners span " <> num spread <> " in z"
    FlapMovesBothWays a b -> "(internal faces " <> tshow (unFaceId a) <> " and " <> tshow (unFaceId b) <> ") both move beside the hinge but lie on opposite sides of its line, so one turn would set one off towards +z and the other towards -z, and which way to turn cannot be read"
    FlapEmptyHinge -> "a flap hinge needs at least one crease"
    FlapDuplicateCrease eid -> "flap hinge repeats crease " <> tshow (unEdgeId eid)
    FlapNotBoundary eid -> "selected crease " <> tshow (unEdgeId eid) <> " must separate moving from stationary paper"
    FlapUnalignedCrease eid -> "selected crease " <> tshow (unEdgeId eid) <> " is not on the common hinge line in the folded paper"
    FlapMissingFace fid -> "flap is missing face or placement " <> tshow (unFaceId fid)
    FlapMissingOwner i -> "flap contact triangle " <> tshow i <> " is missing its source face"
    FlapMissingVertex vid -> "flap is missing material vertex " <> tshow (unVertexId vid)
    FlapStartMismatch -> "flap start must be the unmodified result of foldFrameWith, including its cut pattern and explicit angles"
    FlapInvalidTravel value -> "flap travel must be finite and between -360 and 360 degrees; got " <> tshow value
    FlapInvalidTurn value -> "a turn towards +z or -z must be finite and from 0 to 360 degrees; got " <> tshow value
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
prepareFlapAlong eids side travel = prepareHinge eids side (Signed travel)

-- | 'prepareFlapAlong' with a size of turn in degrees and a 'Toward' in place
-- of a signed travel. The sign is read from the moving face beside each
-- crease: a positive change in a crease's angle moves that face towards its
-- own top, so turning a face that lies top up towards +z is positive and one
-- lying upside down negative. So one turn towards +z can be either sign. On
-- the quarter fold after its first step, the hinge along y = 1/2 has two
-- segments, edges 9 and 11; face 1 beside edge 9 lies top up and face 2
-- beside edge 11 upside down, so that turn is travel 180 with edge 9 listed
-- first and -180 with edge 11 first.
--
-- Its refusals are 'prepareFlapAlong'\'s, with one in place and two more. A
-- size has no sign, so one that is negative, above 360 or not finite is
-- 'FlapInvalidTurn', where a travel's bound is 'FlapInvalidTravel'. A moving
-- face beside the hinge that does not lie flat is 'FlapMovingNotFlat', and
-- moving faces beside it on both sides of its line are 'FlapMovesBothWays',
-- whatever the size of the turn. Both are asked once the paper that moves is
-- known to be a flap on one hinge, after every check of the selection and
-- before its surface, sweep and layer orders are checked, so that a wrong
-- selection is refused as one and not as a question of which way to turn it.
prepareFlapToward :: [EdgeId] -> FaceId -> Double -> Toward -> Folded -> Either FlapError FlapMotion
prepareFlapToward eids side magnitude toward = prepareHinge eids side (Towards magnitude toward)

-- | How far to turn, as the two entries above are given it. A 'Towards' is
-- signed only once the flap has been checked and its moving faces are known.
data Travel = Signed !Double | Towards !Double !Toward

prepareHinge :: [EdgeId] -> FaceId -> Travel -> Folded -> Either FlapError FlapMotion
prepareHinge [] _ _ _ = Left FlapEmptyHinge
prepareHinge eids@(eid : _) side request supplied = do
  case request of
    Signed travel -> unless (finite travel && abs travel <= 360) (Left (FlapInvalidTravel travel))
    Towards magnitude _ -> unless (finite magnitude && magnitude >= 0 && magnitude <= 360) (Left (FlapInvalidTurn magnitude))
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
  fixedPanel <- faceNamed faces fixed
  (from, to) <- maybe (Left (FlapNotHinge eid)) Right (find (\(x, y) -> edgeKey x y == key) (ringEdges (faceVertexIds fixedPanel)))
  let vertices = IM.fromList (zip [0 ..] expected)
      point vid = maybe (Left (FlapMissingVertex vid)) Right (IM.lookup (unVertexId vid) vertices)
  origin <- point from
  finish <- point to
  let axis = (1 / norm (finish ^-^ origin)) *^ (finish ^-^ origin)
      onLine p = norm (cross axis ((1 / scale) *^ (p ^-^ origin))) < 1e-12
      -- Whether a segment's stationary face runs along the hinge the same way
      -- as the first one's, and which face beside it moves. One running the
      -- other way turns by -travel.
      segmentAlong (e, x, y, left, right) = do
        unless (S.member left selected /= S.member right selected) (Left (FlapNotBoundary e))
        let (movingFace, stationary) = if S.member left selected then (left, right) else (right, left)
        panel <- faceNamed faces stationary
        mover <- faceNamed faces movingFace
        (u, v) <- maybe (Left (FlapNotHinge e)) Right (find (\(p, q) -> edgeKey p q == edgeKey x y) (ringEdges (faceVertexIds panel)))
        p <- point u
        q <- point v
        unless (onLine p && onLine q) (Left (FlapUnalignedCrease e))
        pure (e, dot axis (q ^-^ p) > 0, mover)
  directions <- traverse segmentAlong segments
  travel <- case request of
    Signed travel -> Right travel
    Towards magnitude toward -> travelTowards start magnitude toward [(along, m) | (_, along, m) <- directions]
  let travels = [(e, if along then travel else negate travel) | (e, along, _) <- directions]
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

-- | The travel of a turn towards +z or -z, read from the moving face beside
-- each hinge crease, in the refolded start. Each face says which way its own
-- crease must change, positive when the turn sets it off towards its top;
-- turned into the way the first crease changes, which is the travel's sign,
-- those readings agree unless the faces lie on both sides of the hinge line.
-- The directions are compared, not signed sizes, so that a turn of 0 is
-- refused as any other is. Placements come from that refold, as every pose's
-- do, never from the 'Folded' a caller supplied, whose constructor is public.
travelTowards :: Folded -> Double -> Toward -> [(Bool, Face)] -> Either FlapError Double
travelTowards start magnitude toward beside = do
  readings <- traverse reading beside
  case readings of
    (lead, direction) : rest -> case find ((/= direction) . snd) rest of
      Just (other, _) -> Left (FlapMovesBothWays lead other)
      Nothing -> Right (direction * magnitude)
    -- Unreachable: an empty hinge is refused before any face is read.
    [] -> Left FlapEmptyHinge
  where
    reading (along, face) = do
      let moving = faceId face
          corners = faceCorners face
      when (hasRelief corners) (Left (FlapMovingNotFlat moving (zSpan corners)))
      placed <- placement moving start
      let topSide = if facesUp placed then TowardPlusZ else TowardMinusZ
          direction = if toward == topSide then 1 else negate 1
      pure (moving, if along then direction else negate direction)

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

-- | The face the turn is measured against: the one beside the first hinge
-- crease, on the side that does not move, numbered like 'flapMovingFaces'.
-- Every pose 'flapAt' gives is moved back so that this face lies where it lay
-- at the start, which is what holding the paper still means here.
flapStationaryFace :: CheckedFlap -> FaceId
flapStationaryFace (CheckedFlap motion _) = stationaryFace motion

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

faceNamed :: [Face] -> FaceId -> Either FlapError Face
faceNamed faces fid = maybe (Left (FlapMissingFace fid)) Right (find ((== fid) . faceId) faces)

comparePoint :: FlapMotion -> (Int, MaterialSample, MaterialSample) -> Either FlapError ()
comparePoint motion (i, actual, expected) =
  let normalized = (1 / checkScale motion) *^ (position actual ^-^ checkOrigin motion)
   in unless (norm (normalized ^-^ position expected) < 1e-9) (Left (FlapPathMismatch (VertexId i)))

finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)
