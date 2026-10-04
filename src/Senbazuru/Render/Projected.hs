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
-- What the material study judges a view by as well is in
-- "Senbazuru.Render.Shadows": the shadows, the two yardsticks, the orders the
-- file supplies, the coverage check and the lifting. Its header says why a
-- view needs two yardsticks. This module keeps what is production's alone:
-- deciding each pair of panels ('orderPair'), and refusing a view at the first
-- face the visible regions leave uncovered.
--
-- Coplanar overlaps still need the file's layer orders. Separated panels use
-- actual depth, even if an obsolete order says otherwise. Intersecting panels,
-- non-planar or concave faces and unresolved depth ties decline this path.
-- Edge-on panels are supported when their edges also belong to non-edge-on
-- neighbours; free edge-on outlines decline. A successful result is visibility
-- for one view, not a contact
-- certificate or a folding simulation.
module Senbazuru.Render.Projected (projectedForm) where

import Data.List (tails)
import Data.Map.Strict qualified as M
import Data.Maybe (catMaybes)
import Senbazuru.Fold.Query (Face (..), FoldError (..), frameFaceOrders, frameFaces, frameVertices)
import Senbazuru.Fold.Types (FaceId (..), FaceOrder (..), Frame (..), Stacking (..))
import Senbazuru.Geometry.Polygon (clipConvex, signedArea)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Flat (FlatError (..))
import Senbazuru.Origami.Visible (VisibleForm, visibleForm)
import Senbazuru.Render.Camera (Basis)
import Senbazuru.Render.Shadows (Shadow (..), edgesAccountedFor, liftForm, modelHair, picture, shadowOf, suppliedNearness, uncoveredParts)

-- | 'Nothing' means this view lies outside the convex, separated-panel path.
-- Invalid indices and contradictory supplied pair orders remain errors.
projectedForm :: Basis -> Frame -> [FaceOrder] -> Either FoldError (Maybe VisibleForm)
projectedForm basis fr supplied = do
  vertices <- frameVertices fr
  faces <- frameFaces fr
  orders <- frameFaceOrders fr {faceOrders = supplied}
  let hair = modelHair vertices
      (pictured, speck) = picture basis vertices
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
          let mappedOrders = map renameOrder (concat relations)
              flat = fr {verticesCoords = [[x, y, z] | V3 x y z <- pictured], facesVertices = map faceVertexIds surviving, faceOrders = mappedOrders, frameExtras = mempty}
          case visibleForm True flat mappedOrders of
            Right seen -> case uncovered speck panels seen of
              Just fid -> Left (ImpossibleStacking fid)
              Nothing -> pure (Just (liftForm basis (renamed oldIds) seen))
            -- Flat refuses a face only by the area test 'shadowOf' has already
            -- made with the same speck, so no error here names a face, and the
            -- temporary frame's face ids need no renaming back.
            Left (FlatRefused err) -> Left err
            Left _ -> pure Nothing

-- A contradictory cycle can make every face surrender the same patch to
-- another. Pair checks alone do not see that hole. Require the resulting
-- visible regions to cover the original silhouette; cycles with no shared
-- patch (a valid interleaving) still pass.
uncovered :: Double -> [Shadow] -> VisibleForm -> Maybe FaceId
uncovered speck panels seen = case [shadowId panel | (panel, left) <- zip panels (uncoveredParts speck seen (map shadowRing panels)), not (null left)] of
  fid : _ -> Just fid
  [] -> Nothing

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
