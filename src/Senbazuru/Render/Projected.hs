-- | Visible paper in an orthographic view of an open fold. A panel is one
-- planar piece of the sheet; see docs/glossary.md for the fold vocabulary.
--
-- The flat renderer already subtracts nearer faces and removes buried edges.
-- We can reuse that machinery when every pair of projected panels has a
-- consistent front/back order. Compare their depths at every corner of their
-- overlapping shadows: depth on a plane is a linear function, so its extrema
-- occur at those corners. Comparing face centres instead can put a long,
-- sloping flap behind paper it actually covers.
--
-- Only after those comparisons do we flatten the shadows into a temporary
-- frame. Its orders describe this view, not physical layer order, and it must
-- never be exported as folded material. The visible pieces are lifted onto the
-- camera plane so the caller can project them through the same basis as its
-- other geometry. Neither operation changes the input frame.
--
-- Coplanar overlaps still need the file's layer orders. Separated panels use
-- actual depth, even if an obsolete order says otherwise. Intersecting panels,
-- non-planar or concave faces and unresolved depth ties decline this path.
-- Edge-on panels are supported when their edges also belong to non-edge-on
-- neighbours; free edge-on outlines decline. A successful result is visibility
-- for one view, not a contact
-- certificate or a folding simulation.
module Senbazuru.Render.Projected (projectedForm) where

import Control.Monad (foldM)
import Data.List (foldl', tails)
import Data.Map.Strict qualified as M
import Data.Maybe (catMaybes)
import Data.Set qualified as S
import Senbazuru.Fold.Query (Face (..), FoldError (..), edgeKey, frameFaceOrders, frameFaces, frameVertices, ringEdges)
import Senbazuru.Fold.Types (FaceId (..), FaceOrder (..), Frame (..), Stacking (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (clipConvex, isConvex, signedArea, subtractConvex)
import Senbazuru.Geometry.V3 (V3 (..), polygonNormal, spanAlong)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Flat (FlatError (..))
import Senbazuru.Origami.Visible (Region (..), VisibleEdge (..), VisibleForm (..), visibleForm)
import Senbazuru.Render.Camera (Basis, basisForward, basisRight, basisUp, project)

data Shadow = Shadow
  { shadowId :: !FaceId,
    shadowRing :: ![V2],
    shadowFront :: !Bool,
    shadowDepth :: V2 -> Double
  }

-- | 'Nothing' means this view lies outside the convex, separated-panel path.
-- Invalid indices and contradictory supplied pair orders remain errors.
projectedForm :: Basis -> Frame -> [FaceOrder] -> Either FoldError (Maybe VisibleForm)
projectedForm basis fr supplied = do
  vertices <- frameVertices fr
  faces <- frameFaces fr
  orders <- frameFaceOrders fr {faceOrders = supplied}
  let scale = maximum (1 : [spanAlong component vertices | component <- [v3x, v3y, v3z]])
      hair = 1e-9 * scale
      speck = hair * scale
      shadows = traverse (shadowOf basis hair speck) faces
  case shadows of
    Nothing -> pure Nothing
    Just projected | null (catMaybes projected) || not (edgesAccountedFor faces projected) -> pure Nothing
    Just projected -> do
      let panels = catMaybes projected
          surviving = [f | (f, Just _) <- zip faces projected]
          newIds = M.fromList (zip (map faceId surviving) (map FaceId [0 ..]))
          oldIds = M.fromList [(new, old) | (old, new) <- M.toList newIds]
          renamed table fid = M.findWithDefault fid fid table
          renameOrder o = o {orderFace = renamed newIds (orderFace o), orderRelativeTo = renamed newIds (orderRelativeTo o)}
      known <- suppliedNearness panels orders
      case sequence [orderPair hair speck known a b | a : rest <- tails panels, b <- rest] of
        Nothing -> pure Nothing
        Just relations -> do
          let coordinates p = let V2 x y = project basis p in [x, y, 0]
              mappedOrders = map renameOrder (concat relations)
              flat = fr {verticesCoords = map coordinates vertices, facesVertices = map faceVertexIds surviving, faceOrders = mappedOrders, frameExtras = mempty}
          case visibleForm True flat mappedOrders of
            Right seen -> case uncovered speck panels seen of
              Just fid -> Left (ImpossibleStacking fid)
              Nothing -> pure (Just (liftForm basis (renamed oldIds) seen))
            Left (FlatRefused err) -> Left err
            Left _ -> pure Nothing

-- A contradictory cycle can make every face surrender the same patch to
-- another. Pair checks alone do not see that hole. Require the resulting
-- visible regions to cover the original silhouette; cycles with no shared
-- patch (a valid interleaving) still pass.
uncovered :: Double -> [Shadow] -> VisibleForm -> Maybe FaceId
uncovered speck panels seen = case [shadowId panel | panel <- panels, any ((> speck) . abs . signedArea) (foldl' cut [shadowRing panel] regions)] of
  fid : _ -> Just fid
  [] -> Nothing
  where
    regions = [[V2 x y | V3 x y _ <- piece] | region <- formRegions seen, piece <- regionPieces region]
    cut pieces cover = concatMap (cutOne cover) pieces
    cutOne cover piece
      | abs (signedArea (clipConvex cover piece)) <= speck = [piece]
      | otherwise = subtractConvex speck cover piece

-- An edge-on face paints no area. It can be omitted when all its edges also
-- belong to surviving neighbours, which supply their real depth and outline.
-- A free edge seen end-on needs a separate line-depth test, so decline that
-- case rather than accidentally hiding it behind unrelated paper.
edgesAccountedFor :: [Face] -> [Maybe Shadow] -> Bool
edgesAccountedFor faces projected = all (`S.member` retained) omitted
  where
    keys face = [edgeKey a b | (a, b) <- ringEdges (faceVertexIds face)]
    retained = S.fromList (concat [keys f | (f, Just _) <- zip faces projected])
    omitted = concat [keys f | (f, Nothing) <- zip faces projected]

shadowOf :: Basis -> Double -> Double -> Face -> Maybe (Maybe Shadow)
shadowOf basis hair speck face = case faceCorners face of
  [] -> Nothing
  origin : _ -> do
    normal <- normalize (polygonNormal (faceCorners face))
    let ring = map (project basis) (faceCorners face)
        area = signedArea ring
        facing = dot normal (basisForward basis)
        planar = all ((<= hair) . abs . dot normal . (^-^ origin)) (faceCorners face)
        depthAt (V2 x y) =
          (dot normal origin - x * dot normal (basisRight basis) - y * dot normal (basisUp basis)) / facing
    if not planar || not (isConvex speck ring)
      then Nothing
      else
        if abs area <= speck || abs facing <= 1e-9
          then Just Nothing
          else Just (Just (Shadow (faceId face) (if area > 0 then ring else reverse ring) (area > 0) depthAt))

-- | FOLD signs refer to the second face's normal. Camera projection preserves
-- its facing sign, including when looking from underneath. Record both ways
-- round so a reversed entry cannot evade the contradiction check.
suppliedNearness :: [Shadow] -> [FaceOrder] -> Either FoldError (M.Map (FaceId, FaceId) Bool)
suppliedNearness panels orders = foldM record M.empty (concatMap entries orders)
  where
    fronts = M.fromList [(shadowId p, shadowFront p) | p <- panels]
    entries o = case orderStacking o of
      Unordered -> []
      stacking
        | Just front <- M.lookup (orderRelativeTo o) fronts,
          M.member (orderFace o) fronts ->
            let f = orderFace o
                g = orderRelativeTo o
                near = (stacking == Above) == front
             in [((f, g), near), ((g, f), not near)]
      _ -> []
    record known (pair@(f, g), near) = case M.lookup pair known of
      Just previous | previous /= near -> Left (ContradictoryStacking f g)
      _ -> Right (M.insert pair near known)

orderPair :: Double -> Double -> M.Map (FaceId, FaceId) Bool -> Shadow -> Shadow -> Maybe [FaceOrder]
orderPair hair speck known a b
  | abs (signedArea overlap) <= speck = Just []
  | all (>= negate hair) gaps && any (> hair) gaps = Just (relation False)
  | all (<= hair) gaps && any (< negate hair) gaps = Just (relation True)
  | all ((<= hair) . abs) gaps = relation <$> M.lookup (shadowId a, shadowId b) known
  | otherwise = Nothing
  where
    overlap = clipConvex (shadowRing a) (shadowRing b)
    gaps = [shadowDepth a p - shadowDepth b p | p <- overlap]
    -- Depth increases away from the viewer; a smaller depth wins. Convert
    -- that fact back to the temporary frame's second-face-normal convention.
    relation nearer = [FaceOrder (shadowId a) (shadowId b) (if nearer == shadowFront b then Above else Below)]

liftForm :: Basis -> (FaceId -> FaceId) -> VisibleForm -> VisibleForm
liftForm basis originalId seen =
  seen
    { formRegions = [r {regionFace = originalId (regionFace r), regionPieces = map (map liftPoint) (regionPieces r)} | r <- formRegions seen],
      formEdges = map liftEdge (formEdges seen),
      formSheetEdges = [(fmap originalId owner, liftEdge edge) | (owner, edge) <- formSheetEdges seen]
    }
  where
    liftPoint (V3 x y _) = x *^ basisRight basis ^+^ y *^ basisUp basis
    liftEdge edge = edge {visibleFrom = liftPoint (visibleFrom edge), visibleTo = liftPoint (visibleTo edge)}
