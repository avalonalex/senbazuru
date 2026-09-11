-- | Graphics pieces derived from one material surface. A glTF viewer knows
-- triangle depth, but not origami layer order. Moving each panel to give it a
-- different depth tears shared creases. Instead, the display mesh removes only
-- paper buried by other panels in the SAME plane. Other panels keep their
-- real depth and the viewer handles their occlusion as the camera turns.
--
-- The complete mesh is retained separately. Clipping a display piece can add
-- corners inside an original panel: each corner records a weighted combination
-- of original vertex ids, so it remains attached to material rather than being
-- an unrelated point in space. Original corners have one id with weight one.
-- These weights interpolate within a placed panel, never between fold states.
-- See docs/glossary.md for panels, material coordinates and layer order.
module Senbazuru.Render.PaperMesh
  ( PaperVertex (..),
    PaperPiece (..),
    PaperMeshError (..),
    completePaper,
    visiblePaper,
  )
where

import Control.Monad (unless)
import Data.Bifunctor (first)
import Data.List (find, partition)
import Data.Map.Strict qualified as M
import Data.Maybe (fromMaybe)
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Query (Face (..), FoldError, FrameKind (..), frameKind)
import Senbazuru.Fold.Types (FaceId (..), FaceOrder (..), Frame (..), VertexId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (cross2)
import Senbazuru.Geometry.V3 (V3 (..), cross, modelSpan, polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Stacking (Budget, layerOrderFor)
import Senbazuru.Origami.Surface (Surface, SurfaceError, surfaceFaces, surfaceFrame)
import Senbazuru.Origami.Visible (Region (..), VisibleForm (..))
import Senbazuru.Render.Camera (Basis, basisFrom, project)
import Senbazuru.Render.Projected (projectedForm)

data PaperVertex = PaperVertex
  { paperPosition :: !V3,
    materialWeights :: ![(VertexId, Double)]
  }
  deriving stock (Eq, Show)

-- | Corners follow the source panel's winding. True draws that winding with
-- the paper's top colour; False draws it reversed with the underside colour.
data PaperPiece = PaperPiece
  { piecePanel :: !FaceId,
    pieceCorners :: ![PaperVertex],
    pieceSides :: ![Bool]
  }
  deriving stock (Eq, Show)

data PaperMeshError
  = PaperSurfaceError !SurfaceError
  | PaperOrderError !FoldError
  | PaperNotPlanar !FaceId
  | PaperUnresolved ![FaceId]
  | PaperMissingPoint !FaceId !V2
  deriving stock (Eq, Show)

instance Explain PaperMeshError where
  explain = \case
    PaperSurfaceError err -> explain err
    PaperOrderError err -> explain err
    PaperNotPlanar (FaceId f) -> "panel " <> tshow f <> " needs a planar surface for the visible glTF scene"
    PaperUnresolved fs -> "cannot resolve coplanar visibility for panels " <> tshow (map unFaceId fs) <> "; provide their layer order or export --all-layers to inspect the complete geometry"
    PaperMissingPoint (FaceId f) p -> "a clipped corner " <> tshow p <> " could not be attached to material panel " <> tshow f

completePaper :: Surface material -> Either PaperMeshError [PaperPiece]
completePaper sheet = map whole <$> first PaperSurfaceError (surfaceFaces sheet)
  where
    whole f = PaperPiece (faceId f) [PaperVertex p [(vid, 1)] | (vid, p) <- zip (faceVertexIds f) (faceCorners f)] [True, False]

-- | Remove coplanar overlaps on both sides, independently of a viewing camera.
-- A cycle with no common overlap (a pinwheel) is valid; contradictory orders
-- over a shared patch are refused by the existing projected visibility check.
visiblePaper :: Budget -> Surface material -> Either PaperMeshError [PaperPiece]
visiblePaper budget sheet = do
  faces <- first PaperSurfaceError (surfaceFaces sheet)
  planes <- traverse plane faces
  concat <$> traverse drawGroup (groups planes)
  where
    fr = surfaceFrame sheet
    points = [V3 x y z | [x, y, z] <- verticesCoords fr]
    extent = max 1 (modelSpan points)
    hair = 1e-9 * extent
    plane f = case faceCorners f of
      origin : _ -> case normalize (polygonNormal (faceCorners f)) of
        Just normal -> do
          unless (all ((<= hair) . abs . dot normal . (^-^ origin)) (faceCorners f)) (Left (PaperNotPlanar (faceId f)))
          pure (f, origin, normal)
        Nothing -> Left (PaperNotPlanar (faceId f))
      [] -> Left (PaperNotPlanar (faceId f))
    groups [] = []
    groups (p@(_, origin, normal) : rest) =
      let same (f, _, n) = norm (cross normal n) <= 1e-9 && all ((<= hair) . abs . dot normal . (^-^ origin)) (faceCorners f)
          (joined, others) = partition same rest
       in (p : joined) : groups others
    drawGroup [] = Right []
    drawGroup group@((_, _, normal) : _) = do
      basis <- maybe (Left (PaperUnresolved ids)) Right (basisFrom (negateV normal) (upHint normal))
      reverseBasis <- maybe (Left (PaperUnresolved ids)) Right (basisFrom normal (upHint normal))
      let local = M.fromList (zip ids (map FaceId [0 ..]))
          supplied = [o {orderFace = a, orderRelativeTo = b} | o <- faceOrders fr, Just a <- [M.lookup (orderFace o) local], Just b <- [M.lookup (orderRelativeTo o) local]]
          groupFrame = fr {facesVertices = map faceVertexIds faces, faceOrders = supplied, frameExtras = mempty}
          -- Only a whole flat model can ask the existing folding layer solver.
          -- Open models must supply the coplanar relations they have checked.
          flatPoint p = let V2 x y = project basis p in [x, y, 0]
          flat = groupFrame {verticesCoords = map flatPoint points}
      orders <-
        if not (null supplied) || length faces /= length (facesVertices fr) || frameKind (frameClasses fr) points == CreasePattern
          then Right supplied
          else fromMaybe [] <$> first PaperOrderError (layerOrderFor budget flat)
      let geometry = groupFrame {edgesVertices = [], edgesAssignment = [], edgesFoldAngle = []}
      concat <$> traverse (view geometry orders faces) [basis, reverseBasis]
      where
        faces = [f | (f, _, _) <- group]
        ids = map faceId faces
    view geometry orders faces basis = do
      seen <- first PaperOrderError (projectedForm basis geometry orders)
      case seen of
        Nothing -> Left (PaperUnresolved (map faceId faces))
        Just form -> concat <$> traverse (region faces basis) (formRegions form)
    region faces basis r = case lookup (unFaceId (regionFace r)) (zip [0 ..] faces) of
      Nothing -> Left (PaperUnresolved (map faceId faces))
      Just f -> traverse (piece f basis (regionTopSide r)) (regionPieces r)
    piece f basis top corners = do
      vertices <- traverse (attach hair f basis . project basis) corners
      -- Projected pieces face the viewer. Restore the source winding before
      -- the backend chooses which side's indices to reverse.
      pure (PaperPiece (faceId f) (if top then vertices else reverse vertices) [top])
    negateV = ((-1) *^)
    upHint (V3 x y z)
      | abs x <= min (abs y) (abs z) = V3 1 0 0
      | abs y <= abs z = V3 0 1 0
      | otherwise = V3 0 0 1

attach :: Double -> Face -> Basis -> V2 -> Either PaperMeshError PaperVertex
attach hair face basis target = case find (\(_, p) -> norm (project basis p ^-^ target) <= hair) vertices of
  Just (vid, p) -> Right (PaperVertex p [(vid, 1)])
  Nothing -> case [weights | triangle <- fan vertices, Just weights <- [inTriangle triangle]] of
    weights : _ -> Right (PaperVertex (foldr ((^+^) . contribution) (V3 0 0 0) weights) [(vid, w) | ((vid, _), w) <- weights])
    [] -> Left (PaperMissingPoint (faceId face) target)
  where
    vertices = zip (faceVertexIds face) (faceCorners face)
    contribution ((_, p), w) = w *^ p
    inTriangle (a@(_, pa), b@(_, pb), c@(_, pc)) =
      let origin = project basis pa
          ab = project basis pb ^-^ origin
          ac = project basis pc ^-^ origin
          at = target ^-^ origin
          denominator = cross2 ab ac
          wb = cross2 at ac / denominator
          wc = cross2 ab at / denominator
          wa = 1 - wb - wc
       in if abs denominator > hair * hair && all (>= (-1e-8)) [wa, wb, wc]
            then Just [(a, wa), (b, wb), (c, wc)]
            else Nothing
    fan (a : b : c : rest) = (a, b, c) : fan (a : c : rest)
    fan _ = []
