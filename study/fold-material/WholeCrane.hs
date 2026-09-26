-- | One connected, prescribed whole-crane starting shape for visual review.
-- The saved body is a cut-out specimen. Here its material coordinates locate
-- the same paper on the full sheet; original shared vertex ids do the joining,
-- never proximity in the folded stack. The central body is held at its saved
-- shape while neck/head, tail and wings can adjust around it.
--
-- Continue the body's deformation into the missing paper with a smooth graph
-- displacement (neighbouring vertices prefer the same correction). This is an
-- INITIAL GUESS and can strain paper. Both wings then follow a circular bend
-- below y=0.30 in the original folded fixture, clear of the body interface.
-- The bend has zero extra turn at its root and 60 degrees at the tips. It is
-- sampled by triangles, not a rendered curve concealing different geometry.
-- No interpolation here describes a physical folding motion. See the material
-- coordinates and panels in docs/glossary.md.
module WholeCrane (WholeCrane (..), wholeCrane, wholeMeasurements) where

import BodyPatch
import Control.Monad (unless)
import CranePocket
import CraneSpread
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (foldl')
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Text (Text)
import FoldBending
import FoldMaterial (componentCount, meshEdges)
import Senbazuru.Explain (Explain, explain)
import Senbazuru.Fold.Query (Crease (..), Face (..), frameFaces)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (cross2)
import Senbazuru.Geometry.V3 (V3 (..), cross, polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import SparseSolve

data WholeCrane = WholeCrane
  { wholeSpread :: !CraneSpread,
    wholeMap :: !PocketMap,
    wholeCore :: !(S.Set Int),
    wholeMarks :: ![(Text, Int)],
    wholeMappedVertices :: !Int
  }
  deriving stock (Show)

wholeCrane :: PocketMap -> BodyPatch -> MaterialMesh -> Either SpreadError WholeCrane
wholeCrane atlas patch saved = do
  unless (patchDegrees patch == 10 && patchLevel patch == 1) (bad "whole crane requires the saved ten-degree refined body")
  _ <- spreadSurface (patchSpread patch) saved
  let sheet = pocketSurface atlas
  features <- checked (surfaceFeatures sheet)
  let targets = M.fromList [(creaseId c, if creaseAssignment c == Mountain then -pi else if creaseAssignment c == Valley then pi else 0) | (c, _) <- features, creaseAssignment c `notElem` [Border, Cut]]
  (refined, hinges) <- checked (buildSurfaceHinges (Bending 1 0.2) 1 sheet targets)
  let base = refinedMesh refined
      tagged = zip (triangles base) (refinedPanels refined)
      memberships = IM.fromListWith S.union [(i, S.singleton r) | (tri, owner) <- tagged, Just r <- [M.lookup owner (pocketRegions atlas)], i <- vertices tri]
      core = S.fromList [i | (tri, owner) <- tagged, owner `elem` regionFaces atlas BodyCore, i <- vertices tri]
      original = IM.fromList (zip [0 ..] (samples base))
      savedSamples = IM.fromList (zip [0 ..] (samples saved))
      savedTriangles = [[p | i <- vertices tri, Just p <- [IM.lookup i savedSamples]] | tri <- triangles saved]
      mapped p = case [q | ps <- savedTriangles, Just q <- [interpolateMaterial (sampleMaterial p) ps]] of
        [] -> Nothing
        q : rest | all ((< 1e-8) . norm . (^-^ q)) rest -> Just q
        _ -> Nothing
      anchors = IM.fromList [(i, q) | (i, p) <- IM.toList original, Just q <- [mapped p]]
  unless (all (`IM.member` anchors) (S.toList core)) (bad "the saved body does not cover every central vertex")
  unless (IM.size anchors == length (samples saved)) (bad "expected matching uniform midpoint material samples on the saved patch")
  -- The two wing fits use their saved attachment shape, not a guessed sign
  -- based on front/back colour. The opened patch already changes their tilt.
  wingFits <- traverse (fitWing memberships original anchors) [WingA, WingB]
  let fits = M.fromList (zip [WingA, WingB] wingFits)
      baseline i p = case S.toList (IM.findWithDefault S.empty i memberships) of
        [r] | Just fit <- M.lookup r fits -> applyFit fit (position p)
        _ -> analytic p
      initial = IM.mapWithKey baseline original
  continued <- continueDisplacements base initial anchors
  let bend i p = case S.toList (IM.findWithDefault S.empty i memberships) of
        [r]
          | Just (_, _, ex, ey) <- M.lookup r fits,
            let len = max 0 (0.30 - v3y (position p)),
            len > 0 ->
              let turn = (pi / 3) / 0.30
                  side = if r == WingA then 1 else -1
                  normal = cross ex ey
               in (len - sin (turn * len) / turn) *^ ey ^+^ (side * (1 - cos (turn * len)) / turn) *^ normal
        _ -> V3 0 0 0
      moved = base {samples = [p {position = IM.findWithDefault (position p) i continued ^+^ bend i p} | (i, p) <- IM.toList original]}
      landmark (name, v) = (name, unVertexId v)
      marks = ("centre", unVertexId (pocketCentre atlas)) : [landmark (regionKey r, v) | (r, v) <- pocketTips atlas]
      tips = S.fromList [unVertexId v | (r, v) <- pocketTips atlas, r `elem` [WingA, WingB]]
      held = S.union core tips
      pins = IM.fromList [(i, position p) | (i, p) <- zip [0 ..] (samples moved), S.member i held]
  faces <- checked (frameFaces (surfaceFrame sheet))
  let normals = M.fromList [(faceId f, v3z (polygonNormal (faceCorners f))) | f <- faces]
  orders <- traverse (directed normals) (faceOrders (surfaceFrame sheet))
  unless (componentCount moved == 1 && length (triangles moved) == 448 && length (samples moved) == 237) (bad "unexpected whole-crane material mesh")
  let fixture = CraneSpread sheet refined moved pins core (S.fromList (M.keys (pocketRegions atlas))) hinges orders tips
  pure (WholeCrane fixture atlas core marks (IM.size anchors))
  where
    analytic p = let V3 x y z = position p; V2 u v = sampleMaterial p; angle = pi / 18 in V3 x ((1 - sqrt 2 / 2) + (y - (1 - sqrt 2 / 2)) * cos angle) (z - (v - u) / sqrt 2 * sin angle)

-- Material triangles are non-overlapping on the original square, even when
-- their folded positions coincide. Barycentric weights locate the same piece
-- of paper, including a boundary vertex shared by several triangles.
interpolateMaterial :: V2 -> [MaterialSample] -> Maybe V3
interpolateMaterial p [a, b, c]
  | abs denominator < 1e-15 = Nothing
  | minimum [u, v, w] < -1e-9 = Nothing
  | otherwise = Just (u *^ position a ^+^ v *^ position b ^+^ w *^ position c)
  where
    ab = sampleMaterial b ^-^ sampleMaterial a
    ac = sampleMaterial c ^-^ sampleMaterial a
    ap = p ^-^ sampleMaterial a
    denominator = cross2 ab ac
    v = cross2 ap ac / denominator
    w = cross2 ab ap / denominator
    u = 1 - v - w
interpolateMaterial _ _ = Nothing

type Fit = (V3, V3, V3, V3)

-- Least-squares plane tangents, made perpendicular and unit length so the
-- continuation itself is rigid. It cannot satisfy every deformed attachment;
-- the graph correction below carries those residuals into the remaining sheet.
fitWing :: IM.IntMap (S.Set Region) -> IM.IntMap MaterialSample -> IM.IntMap V3 -> Region -> Either SpreadError Fit
fitWing memberships original anchors region = do
  let pairs = [(position p, q) | (i, q) <- IM.toList anchors, S.member region (IM.findWithDefault S.empty i memberships), Just p <- [IM.lookup i original]]
  unless (length pairs >= 3) (bad "wing fit has fewer than three attachment samples")
  let average ps = (1 / fromIntegral (length ps)) *^ foldl' (^+^) (V3 0 0 0) ps
      from = average (map fst pairs)
      to = average (map snd pairs)
      shifted = [(p ^-^ from, q ^-^ to) | (p, q) <- pairs]
      xx = sum [v3x p * v3x p | (p, _) <- shifted]
      yy = sum [v3y p * v3y p | (p, _) <- shifted]
      xy = sum [v3x p * v3y p | (p, _) <- shifted]
      xq = foldl' (^+^) (V3 0 0 0) [v3x p *^ q | (p, q) <- shifted]
      yq = foldl' (^+^) (V3 0 0 0) [v3y p *^ q | (p, q) <- shifted]
      det = xx * yy - xy * xy
  unless (det > 1e-14) (bad "wing attachment samples do not span a plane")
  ex <- maybe (bad "wing fit has no first tangent") Right (normalize ((1 / det) *^ (yy *^ xq ^-^ xy *^ yq)))
  let ey0 = (1 / det) *^ (xx *^ yq ^-^ xy *^ xq)
  ey <- maybe (bad "wing fit has no second tangent") Right (normalize (ey0 ^-^ dot ex ey0 *^ ex))
  pure (from, to, ex, ey)

applyFit :: Fit -> V3 -> V3
applyFit (from, to, ex, ey) p = let V3 x y z = p ^-^ from in to ^+^ x *^ ex ^+^ y *^ ey ^+^ z *^ cross ex ey

continueDisplacements :: MaterialMesh -> IM.IntMap V3 -> IM.IntMap V3 -> Either SpreadError (IM.IntMap V3)
continueDisplacements mesh baseline anchors = do
  let free = IM.keys (IM.difference baseline anchors)
      freeSet = S.fromList free
      edges = meshEdges mesh
      rows = [IM.fromList [(i, s) | (i, s) <- [(a, 1), (b, -1)], S.member i freeSet] | (a, b) <- edges]
      residual i = IM.findWithDefault (V3 0 0 0) i anchors ^-^ IM.findWithDefault (V3 0 0 0) i baseline
      rhs = IM.fromListWith (^+^) [(a, residual b) | (i, j) <- edges, (a, b) <- [(i, j), (j, i)], S.member a freeSet, IM.member b anchors]
  factor <- maybe (bad "cannot continue the body displacement through the full sheet") Right (factorNormal 1e-12 free rows)
  let solve coordinate = applyFactor factor (IM.map coordinate rhs)
      xs = solve v3x
      ys = solve v3y
      zs = solve v3z
      values = IM.mapWithKey (\i p -> p ^+^ V3 (IM.findWithDefault 0 i xs) (IM.findWithDefault 0 i ys) (IM.findWithDefault 0 i zs)) baseline
  pure (IM.union anchors values)

-- | Drawing-scale shape measurements, not volume or air pressure. The body
-- depth is its world-Z range; the paired wing tips report their separation.
wholeMeasurements :: WholeCrane -> MaterialMesh -> Either SpreadError [(Text, Double)]
wholeMeasurements study mesh = do
  _ <- spreadSurface (wholeSpread study) mesh
  let points = IM.fromList (zip [0 ..] (map position (samples mesh)))
      zs = [v3z p | i <- S.toList (wholeCore study), Just p <- [IM.lookup i points]]
      point name = maybe (bad "missing whole-crane landmark") Right (lookup name (wholeMarks study) >>= (`IM.lookup` points))
  a <- point "wing-a"
  b <- point "wing-b"
  neck <- point "neck-head"
  tailTip <- point "tail"
  let restPoints = IM.fromList (zip [0 ..] (map position (samples (refinedMesh (spreadRefined (wholeSpread study))))))
      original name = maybe (bad "missing original landmark") Right (lookup name (wholeMarks study) >>= (`IM.lookup` restPoints))
  originalNeck <- original "neck-head"
  originalTail <- original "tail"
  pure [("bodyDepth", maximum (0 : zs) - minimum (0 : zs)), ("wingTipSeparation", norm (a ^-^ b)), ("neckTipDisplacement", norm (neck ^-^ originalNeck)), ("tailTipDisplacement", norm (tailTip ^-^ originalTail))]

directed :: M.Map FaceId Double -> FaceOrder -> Either SpreadError (FaceId, FaceId)
directed normals o = do
  z <- maybe (bad "missing ordered source normal") Right (M.lookup (orderRelativeTo o) normals)
  pure (if (orderStacking o == Above) == (z > 0) then (orderRelativeTo o, orderFace o) else (orderFace o, orderRelativeTo o))

vertices :: Triangle -> [Int]
vertices (a, b, c) = [a, b, c]

checked :: (Explain e) => Either e a -> Either SpreadError a
checked = first (SpreadError . explain)

bad :: Text -> Either SpreadError a
bad = Left . SpreadError
