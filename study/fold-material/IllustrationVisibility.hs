-- | Experimental visible-layer policy for saved illustrations. A depth tie
-- allows a declared layer order to override geometry only where the depth
-- contradicting that order is within the camera-distance allowance. It chooses the
-- visible side without moving either piece. This is a drawing approximation,
-- not a collision certificate or physical thickness.
--
-- This bounded study mirrors Render.Projected's projection. It decides each
-- pair of panels its own way and takes everything else from Render.Shadows,
-- which production imports too: the shadows, both yardsticks, the supplied
-- orders, the coverage check and the lifting. Its copies of those fell behind
-- production twice. With no allowance it therefore draws what production
-- draws and reports uncovered paper exactly where production refuses; it
-- reports every uncovered part, where production stops at the first face. It
-- reuses Origami.Visible's polygon subtraction and hidden-edge handling.
-- Keeping the experiment here leaves production tolerances unchanged. Its
-- extra record explains every overlapping pair, including unresolved regions;
-- callers must not grade a whole-face fallback as successful visibility.
-- A returned form may still be partial: inspect auditUncovered before claiming
-- complete coverage. Those patches remain explicit comparison uncertainty.
module IllustrationVisibility (VisibilityAudit (..), PairAudit (..), illustrationVisibility) where

import Data.List (tails)
import Data.Map.Strict qualified as M
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Senbazuru.Fold.Query (Face (..), FoldError (..), frameFaceOrders, frameFaces, frameVertices)
import Senbazuru.Fold.Types (FaceId (..), FaceOrder (..), Frame (..), Stacking (..))
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.Polygon (clipConvex, signedArea)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Flat (FlatError (..))
import Senbazuru.Origami.Visible (VisibleForm, visibleForm)
import Senbazuru.Render.Camera (Basis)
import Senbazuru.Render.Shadows (Shadow (..), edgesAccountedFor, liftForm, modelHair, picture, shadowOf, suppliedNearness, uncoveredParts)

data VisibilityAudit = VisibilityAudit
  { auditPairs :: ![PairAudit],
    auditForm :: !(Maybe VisibleForm),
    auditUncovered :: ![[V2]],
    auditStatus :: !Text
  }
  deriving stock (Show)

data PairAudit = PairAudit
  { pairFaces :: !(FaceId, FaceId),
    pairOverlap :: ![V2],
    pairDepthRange :: !(Double, Double),
    pairOverriddenDepth :: !Double,
    pairDecision :: !Text,
    pairRelation :: !(Maybe FaceOrder)
  }
  deriving stock (Show)

-- | Allowance is in model depth units, not polygon area or screen width.
-- The caller keeps strict production rendering as a separate baseline.
illustrationVisibility :: Double -> Basis -> Frame -> [FaceOrder] -> Either FoldError VisibilityAudit
illustrationVisibility allowance basis fr supplied = do
  vertices <- frameVertices fr
  faces <- frameFaces fr
  orders <- frameFaceOrders fr {faceOrders = supplied}
  let hair = modelHair vertices
      (pictured, speck) = picture basis vertices
      declined = VisibilityAudit [] Nothing []
  if allowance < 0 || isNaN allowance || isInfinite allowance
    then pure (declined "invalid allowance")
    else case traverse (shadowOf basis hair speck) faces of
      Nothing -> pure (declined "non-planar, concave or degenerate face")
      Just projected | null (catMaybes projected) || not (edgesAccountedFor faces projected) -> pure (declined "unsupported edge-on outlines")
      Just projected -> do
        let panels = catMaybes projected
            surviving = [f | (f, Just _) <- zip faces projected]
            newIds = M.fromList (zip (map faceId surviving) (map FaceId [0 ..]))
            oldIds = M.fromList [(new, old) | (old, new) <- M.toList newIds]
            renamed table fid = M.findWithDefault fid fid table
            renameOrder o = o {orderFace = renamed newIds (orderFace o), orderRelativeTo = renamed newIds (orderRelativeTo o)}
        known <- suppliedNearness panels orders
        let pairs = catMaybes [auditPair allowance hair speck known a b | a : rest <- tails panels, b <- rest]
            report result = VisibilityAudit pairs result []
        case traverse pairRelation pairs of
          Nothing -> pure (report Nothing "unresolved overlapping pairs")
          Just relations -> do
            let mappedOrders = map renameOrder relations
                flat = fr {verticesCoords = [[x, y, z] | V3 x y z <- pictured], facesVertices = map faceVertexIds surviving, faceOrders = mappedOrders, frameExtras = mempty}
            case visibleForm True flat mappedOrders of
              Right seen ->
                let missing = concat (uncoveredParts speck seen (map shadowRing panels))
                    result = Just (liftForm basis (renamed oldIds) seen)
                 in pure (VisibilityAudit pairs result missing (if null missing then "visible regions cover the sheet" else "partial visibility: uncovered paper"))
              Left (FlatRefused err) -> Left err
              Left _ -> pure (report Nothing "flat visibility refused")

-- Each overlap is convex and depth difference is linear. Its corner
-- extrema bound the WHOLE overlap, not just sampled interior points. Only the
-- depth contradicting an inherited order is overridden; a wide separation
-- consistent with that order needs no allowance. Crossings deeper on both
-- sides stay unresolved. Clearly separated paper outside the allowance uses
-- actual depth, even when an obsolete inherited order disagrees.
auditPair :: Double -> Double -> Double -> M.Map (FaceId, FaceId) Bool -> Shadow -> Shadow -> Maybe PairAudit
auditPair allowance hair speck known a b
  | abs (signedArea overlap) <= speck = Nothing
  | otherwise = Just (PairAudit (shadowId a, shadowId b) overlap (minimum gaps, maximum gaps) overridden decision (relation <$> nearer))
  where
    overlap = clipConvex (shadowRing a) (shadowRing b)
    gaps = [shadowDepth a p - shadowDepth b p | p <- overlap]
    inherited = M.lookup (shadowId a, shadowId b) known
    violation near = maximum (0 : if near then gaps else map negate gaps)
    overridden = if decision == "inherited tie" then maybe 0 violation nearer else 0
    (decision, nearer)
      | Just near <- inherited, violation near <= max hair allowance, violation near > hair || all ((<= hair) . abs) gaps = ("inherited tie", Just near)
      | all (>= negate hair) gaps && any (> hair) gaps = ("depth", Just False)
      | all (<= hair) gaps && any (< negate hair) gaps = ("depth", Just True)
      | all ((<= max hair allowance) . abs) gaps = ("missing order", Nothing)
      | otherwise = ("crossing outside allowance", Nothing)
    relation near = FaceOrder (shadowId a) (shadowId b) (if near == shadowFront b then Above else Below)
