-- | Turn one connected flap and check its entire path before exporting poses.
-- A flap here is the set of faces reached after removing ONE crease from the
-- face graph. If the other side can still be reached, other creases must move
-- too: this operation refuses that coupled motion rather than cutting a loop.
-- See docs/glossary.md for faces, creases, material coordinates and fold angles.
--
-- Start with 'foldFrameWith' and select ids from its 'foldedPattern', since
-- cutting crossings can renumber the input. Travel is a signed CHANGE in the
-- crease's FOLD angle, in degrees. The stationary face's counterclockwise edge
-- direction needs the NEGATIVE of that travel as a right-hand rotation; this
-- is the same convention used by "Senbazuru.Origami.Folding".
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
-- refusals: coplanar touching layers and flat fold endpoints are not yet
-- supported. A refusal can be a contact witness or an unresolved interval,
-- never a claim to have found the earliest impact. Stale face orders are
-- discarded; this first operation accepts separated panels, not a layer stack.
module Senbazuru.Origami.Flap
  ( FlapMotion,
    CheckedFlap,
    FlapError (..),
    prepareFlap,
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
import Data.Set qualified as S
import Senbazuru.Explain (Explain (..), num, tshow)
import Senbazuru.Fold.Query (Crease (..), Face (..), FoldError, edgeKey, facesAlongEdges, frameCreases, frameFaces, frameVertices, ringEdges)
import Senbazuru.Fold.Types (Assignment (..), EdgeId (..), FaceId (..), Frame (..), VertexId (..))
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.Rigid (Rigid, after, inverse)
import Senbazuru.Geometry.V3 (V3 (..), modelSpan)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding (Folded (..), FoldingError, foldFrameWith)
import Senbazuru.Origami.HingeSweep
import Senbazuru.Origami.Surface

data FlapMotion = FlapMotion
  { initialFold :: !Folded,
    movingCrease :: !EdgeId,
    movingFaces :: ![FaceId],
    stationaryFace :: !FaceId,
    angularTravel :: !Double,
    checkOrigin :: !V3,
    checkScale :: !Double,
    checkedPath :: !HingeSweep,
    triangleOwners :: ![FaceId]
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
  | FlapMissingFace !FaceId
  | FlapMissingVertex !VertexId
  | FlapStartMismatch
  | FlapInvalidTravel !Double
  | FlapInvalidProgress !Double
  | FlapPathMismatch !VertexId
  | FlapCollision !Double ![(FaceId, FaceId)]
  | FlapUnresolved !Double !Double ![(FaceId, FaceId)]
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
    FlapMissingFace fid -> "flap is missing face or placement " <> tshow (unFaceId fid)
    FlapMissingVertex vid -> "flap is missing material vertex " <> tshow (unVertexId vid)
    FlapStartMismatch -> "flap start must be the unmodified result of foldFrameWith, including its cut pattern and explicit angles"
    FlapInvalidTravel value -> "flap travel must be finite and at most 360 degrees; got " <> tshow value
    FlapInvalidProgress value -> "flap progress must be between 0 and 1; got " <> tshow value
    FlapPathMismatch vid -> "angle-derived flap pose disagrees with the checked hinge path at vertex " <> tshow (unVertexId vid)
    FlapCollision t pairs -> "flap path refused: contact between faces " <> facePairs pairs <> " at progress " <> num t <> " (a witness, not the first impact time)"
    FlapUnresolved lo hi pairs -> "flap path unresolved between progress " <> num lo <> " and " <> num hi <> " for faces " <> facePairs pairs
    where
      facePairs pairs = tshow [(unFaceId a, unFaceId b) | (a, b) <- pairs]

-- | Crease id, incident face on the moving side, signed travel in degrees,
-- and a folding result. The ids belong to its returned cut pattern.
prepareFlap :: EdgeId -> FaceId -> Double -> Folded -> Either FlapError FlapMotion
prepareFlap eid side travel supplied = do
  unless (finite travel && abs travel <= 360) (Left (FlapInvalidTravel travel))
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
  unless (finite scale && scale > 0 && length actual == length expected && and (zipWith (\a b -> norm (a ^-^ b) / scale < 1e-9) actual expected)) (Left FlapStartMismatch)
  faces <- first FlapGeometry (frameFaces (foldedFrame start))
  neighbours <- first FlapGeometry (facesAlongEdges faces)
  (a, b) <- maybe (Left (FlapMissingCrease eid)) Right (lookup eid (zip (map EdgeId [0 ..]) (edgesVertices flat)))
  creases <- first FlapGeometry (frameCreases (foldedFrame start))
  crease <- maybe (Left (FlapMissingCrease eid)) Right (find ((== eid) . creaseId) creases)
  unless (creaseAssignment crease `elem` [Mountain, Valley, Unassigned]) (Left (FlapNotHinge eid))
  let key = edgeKey a b
  fixed <- case M.findWithDefault [] key neighbours of
    [left, right]
      | side == left -> Right right
      | side == right -> Right left
      | otherwise -> Left (FlapWrongSide eid side)
    _ -> Left (FlapNotHinge eid)
  let links = [(x, y) | (edge, [x, y]) <- M.toList neighbours, edge /= key]
      selected = connected links S.empty [side]
  when (S.member fixed selected) (Left (FlapCoupled eid [a, b]))
  fixedPanel <- maybe (Left (FlapMissingFace fixed)) Right (find ((== fixed) . faceId) faces)
  (from, to) <- maybe (Left (FlapNotHinge eid)) Right (find (\(x, y) -> edgeKey x y == key) (ringEdges (faceVertexIds fixedPanel)))
  let vertices = IM.fromList (zip [0 ..] expected)
      point vid = maybe (Left (FlapMissingVertex vid)) Right (IM.lookup (unVertexId vid) vertices)
  origin <- point from
  finish <- point to
  sheet <- first FlapSurface (surfaceFromFolded start)
  (mesh, owners) <- first FlapSurface (refineSurface 0 sheet)
  let normalized = mesh {samples = [p {position = (1 / scale) *^ (position p ^-^ origin)} | p <- samples mesh]}
      moving = S.toList (S.fromList [unVertexId vid | face <- faces, S.member (faceId face) selected, vid <- faceVertexIds face])
  sweep <- first FlapSweep (prepareSweep (V3 0 0 0) ((1 / scale) *^ (finish ^-^ origin)) (negate travel * pi / 180) moving normalized)
  let motion = FlapMotion start eid (S.toList selected) fixed travel origin scale sweep owners
  -- The same refolding/anchoring path supplies all subsequent public poses.
  _ <- surfaceAt motion 1
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
  result <- first FlapSweep (checkSweep settings (checkedPath motion))
  let owners = IM.fromList (zip [0 ..] (triangleOwners motion))
      sourcePairs pairs = sort (nub [(min a b, max a b) | (i, j) <- pairs, Just a <- [IM.lookup i owners], Just b <- [IM.lookup j owners]])
  case sweepOutcome result of
    SweepClear -> Right (CheckedFlap motion result)
    SweepCollision t pairs -> Left (FlapCollision t (sourcePairs pairs))
    SweepUnresolved lo hi pairs -> Left (FlapUnresolved lo hi (sourcePairs pairs))

flapCheck :: CheckedFlap -> SweepCheck
flapCheck (CheckedFlap _ result) = result

flapMovingFaces :: CheckedFlap -> [FaceId]
flapMovingFaces (CheckedFlap motion _) = movingFaces motion

-- | A checked angle state at a fraction of the accepted motion. The returned
-- surface supplies both renderers and its materialFrame supplies FOLD output.
flapAt :: CheckedFlap -> Double -> Either FlapError (Surface V2)
flapAt (CheckedFlap motion _) = surfaceAt motion

surfaceAt :: FlapMotion -> Double -> Either FlapError (Surface V2)
surfaceAt motion progress = do
  unless (finite progress && progress >= 0 && progress <= 1) (Left (FlapInvalidProgress progress))
  let start = initialFold motion
      frame = foldedFrame start
      angles = [if EdgeId i == movingCrease motion then angle + progress * angularTravel motion else angle | (i, angle) <- zip [0 ..] (edgesFoldAngle frame)]
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
