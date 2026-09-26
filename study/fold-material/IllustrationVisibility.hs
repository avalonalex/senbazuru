-- | Experimental visible-layer policy for saved illustrations. A depth tie
-- allows a declared layer order to override geometry only where the depth
-- contradicting that order is within the camera-distance allowance. It chooses the
-- visible side without moving either piece. This is a drawing approximation,
-- not a collision certificate or physical thickness.
--
-- This bounded study mirrors Render.Projected's projection and coverage checks
-- and reuses Origami.Visible's polygon subtraction and hidden-edge handling.
-- Keeping the experiment here leaves production tolerances unchanged. Its
-- extra record explains every overlapping pair, including unresolved regions;
-- callers must not grade a whole-face fallback as successful visibility.
-- A returned form may still be partial: inspect auditUncovered before claiming
-- complete coverage. Those patches remain explicit comparison uncertainty.
module IllustrationVisibility (VisibilityAudit (..), PairAudit (..), illustrationVisibility) where

import Control.Monad (foldM)
import Data.List (foldl', tails)
import Data.Map.Strict qualified as M
import Data.Maybe (catMaybes)
import Data.Set qualified as S
import Data.Text (Text)
import Senbazuru.Fold.Query (Face (..), FoldError (..), edgeKey, frameFaceOrders, frameFaces, frameVertices, ringEdges)
import Senbazuru.Fold.Types (FaceId (..), FaceOrder (..), Frame (..), Stacking (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (clipConvex, isConvex, signedArea, subtractConvex)
import Senbazuru.Geometry.V3 (V3 (..), polygonNormal, spanAlong)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Flat (FlatError (..))
import Senbazuru.Origami.Visible (Region (..), VisibleEdge (..), VisibleForm (..), visibleForm)
import Senbazuru.Render.Camera (Basis, basisForward, basisRight, basisUp, project)

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

data Shadow = Shadow
  { shadowId :: !FaceId,
    shadowRing :: ![V2],
    shadowFront :: !Bool,
    shadowDepth :: V2 -> Double
  }

-- | Allowance is in model depth units, not polygon area or screen width.
-- The caller keeps strict production rendering as a separate baseline.
illustrationVisibility :: Double -> Basis -> Frame -> [FaceOrder] -> Either FoldError VisibilityAudit
illustrationVisibility allowance basis fr supplied = do
  vertices <- frameVertices fr
  faces <- frameFaces fr
  orders <- frameFaceOrders fr {faceOrders = supplied}
  let scale = maximum (1 : [spanAlong component vertices | component <- [v3x, v3y, v3z]])
      hair = 1e-9 * scale
      speck = hair * scale
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
            let coordinates p = let V2 x y = project basis p in [x, y, 0]
                mappedOrders = map renameOrder relations
                flat = fr {verticesCoords = map coordinates vertices, facesVertices = map faceVertexIds surviving, faceOrders = mappedOrders, frameExtras = mempty}
            case visibleForm True flat mappedOrders of
              Right seen ->
                let missing = uncovered speck panels seen
                    result = Just (liftForm basis (renamed oldIds) seen)
                 in pure (VisibilityAudit pairs result missing (if null missing then "visible regions cover the sheet" else "partial visibility: uncovered paper"))
              Left (FlatRefused err) -> Left err
              Left _ -> pure (report Nothing "flat visibility refused")

-- A contradictory cycle can make every face surrender the same patch to
-- another. Pair checks alone do not see that hole. Require the resulting
-- visible regions to cover the original silhouette; cycles with no shared
-- patch (a valid interleaving) still pass.
uncovered :: Double -> [Shadow] -> VisibleForm -> [[V2]]
uncovered speck panels seen = [piece | panel <- panels, piece <- foldl' cut [shadowRing panel] regions, abs (signedArea piece) > speck]
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
