-- | Draw the actual nearest surface of a static triangle mesh, even if it
-- intersects itself. A depth crossing splits the projected overlap: one face
-- is in front on one side of the line and behind on the other. Sorting whole
-- faces cannot draw that. Subtracting only the nearer part can, but a plausible
-- picture is NOT a contact certificate. The gallery retains strict checks and
-- the existing illustration audit separately.
--
-- Coincident planes use inherited layer order, or an explicitly counted face-id
-- tie if none exists. The 1e-9 arithmetic tolerance is not paper thickness.
-- Real crease/boundary edges are clipped to their incident visible regions;
-- triangle joins are not ink. Geometry and source winding stay unchanged.
module WholeCraneDrawing (DepthDrawing (..), depthDrawing, nearerPart) where

import BodyIntersectionContext (planeDepth)
import Control.Monad (unless, when)
import Data.Bifunctor (first)
import Data.List (foldl', nubBy, sort)
import Data.Map.Strict qualified as M
import Data.Maybe (catMaybes, fromMaybe, isNothing, mapMaybe)
import Data.Text (Text)
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Query (Crease (..), Face (..), frameCreases, frameFaces, ringEdges)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (clipConvex, cross2, signedArea, subtractConvex)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Visible
import Senbazuru.Render.Camera

data DepthDrawing = DepthDrawing
  { depthForm :: !VisibleForm,
    depthMissing :: ![[V2]],
    depthIdTies :: !Int
  }

data Shadow = Shadow !Face ![V2] !Bool !(V2 -> Double)

depthDrawing :: Basis -> Frame -> [FaceOrder] -> Either Text DepthDrawing
depthDrawing basis frame orders = do
  faces <- first explain (frameFaces frame)
  creases <- first explain (frameCreases frame)
  shadows <- fmap catMaybes (traverse shadow faces)
  when (null shadows) (Left "no triangles face this camera")
  let fronts = M.fromList [(faceId f, front) | Shadow f _ front _ <- shadows]
      inherited = M.fromList (concat [let near = (orderStacking o == Above) == front in [((orderFace o, orderRelativeTo o), near), ((orderRelativeTo o, orderFace o), not near)] | o <- orders, orderStacking o /= Unordered, Just front <- [M.lookup (orderRelativeTo o) fronts]])
      hide (Shadow a ar _ ad) (Shadow b br _ bd)
        | faceId a == faceId b = ([], False)
        | abs (signedArea overlap) < 1e-14 = ([], False)
        | all ((<= 1e-9) . abs) gaps =
            let known = M.lookup (faceId a, faceId b) inherited
                aNear = fromMaybe (faceId a < faceId b) known
             in (if aNear then [] else overlap, isNothing known)
        | otherwise = (nearerPart (\p -> ad p - bd p) overlap, False)
        where
          overlap = cleanRing (clipConvex ar br)
          gaps = map (\p -> ad p - bd p) overlap
      occluders a = map (hide a) shadows
      cut pieces cover = concatMap (\piece -> if abs (signedArea (clipConvex cover piece)) < 1e-14 then [piece] else filter ((> 1e-14) . abs . signedArea) (map cleanRing (subtractConvex 1e-14 cover piece))) pieces
      shown = [(f, front, foldl' cut [ring] [cover | (cover, _) <- occluders s, abs (signedArea cover) > 1e-14]) | s@(Shadow f ring front _) <- shadows]
      shownRings = concat [rings | (_, _, rings) <- shown]
      missing = [piece | Shadow _ ring _ _ <- shadows, piece <- foldl' cut [ring] shownRings, abs (signedArea piece) > 1e-12]
      liftPoint (V2 x y) = x *^ basisRight basis ^+^ y *^ basisUp basis
      stretches c =
        let p = project basis (creaseStart c)
            q = project basis (creaseEnd c)
            visible = [ring | (f, _, rings) <- shown, creaseFrom c `elem` faceVertexIds f, creaseTo c `elem` faceVertexIds f, ring <- rings]
            at t = liftPoint (p ^+^ t *^ (q ^-^ p))
         in [VisibleEdge (creaseAssignment c) (at lo) (at hi) | (lo, hi) <- unionIntervals (mapMaybe (edgeInterval (p, q)) visible)]
      drawnEdges = concatMap stretches [c | c <- creases, creaseAssignment c `notElem` [Join, Cut]]
      form = VisibleForm [Region (faceId f) front (map (map liftPoint) rings) | (f, front, rings) <- shown, not (null rings)] drawnEdges []
  pure (DepthDrawing form missing (length [() | a <- shadows, (_, True) <- occluders a] `div` 2))
  where
    shadow f = do
      unless (length (faceCorners f) == 3) (Left "depth preview requires triangle faces")
      let ring = map (project basis) (faceCorners f)
          area = signedArea ring
      if abs area <= 1e-12
        then pure Nothing
        else do
          z0 <- maybe (Left "triangle has no camera-depth plane") Right (planeDepth basis (faceCorners f) (V2 0 0))
          zx <- maybe (Left "triangle has no camera-depth plane") Right (planeDepth basis (faceCorners f) (V2 1 0))
          zy <- maybe (Left "triangle has no camera-depth plane") Right (planeDepth basis (faceCorners f) (V2 0 1))
          let at (V2 x y) = z0 + x * (zx - z0) + y * (zy - z0)
          pure (Just (Shadow f (if area > 0 then ring else reverse ring) (area > 0) at))

-- | Keep the convex part where the first plane is farther from the camera.
-- Plane-depth difference is linear in page coordinates; interpolation gives
-- its zero exactly up to floating-point arithmetic. No 3D point is moved.
nearerPart :: (V2 -> Double) -> [V2] -> [V2]
nearerPart gap ring = cleanRing (concatMap clip (ringEdges ring))
  where
    clip (a, b)
      | ga >= 0 && gb >= 0 = [b]
      | ga < 0 && gb < 0 = []
      | ga >= 0 = [crossing]
      | otherwise = [crossing, b]
      where
        ga = gap a
        gb = gap b
        crossing = a ^+^ (ga / (ga - gb)) *^ (b ^-^ a)

-- Repeated clipping can produce consecutive corners a rounding unit apart.
-- Their tiny connecting edge then names an arbitrary cutting half-plane.
-- Remove only corners within 1e-12 model units of the neighbouring segment;
-- otherwise a later subtraction can leave a visibly wrong foreground sliver.
cleanRing :: [V2] -> [V2]
cleanRing ring
  | length unique < 3 = []
  | otherwise = case redundantIndices of
      [] -> unique
      i : _ -> cleanRing (take i unique ++ drop (i + 1) unique)
  where
    unique = nubBy (\a b -> norm (a ^-^ b) < 1e-12) ring
    previous = drop (length unique - 1) unique ++ take (length unique - 1) unique
    next = drop 1 unique ++ take 1 unique
    redundant a b c =
      let edge = c ^-^ a
          len = norm edge
          within = dot (b ^-^ a) edge >= 0 && dot (b ^-^ c) edge <= 0
       in len > 0 && within && abs (cross2 edge (b ^-^ a)) / len < 1e-12
    -- Two almost coincident corners can each look redundant while the other
    -- exists. Removing both at once erases their real corner, sometimes the
    -- entire triangle. Remove one, then reconsider its neighbours.
    redundantIndices = [i | (i, (a, b, c)) <- zip [0 ..] (zip3 previous unique next), redundant a b c]

unionIntervals :: [(Double, Double)] -> [(Double, Double)]
unionIntervals = reverse . foldl' add [] . sort
  where
    add ((lo, hi) : rest) (a, b) | a <= hi + 1e-12 = (lo, max hi b) : rest
    add previous interval = interval : previous

-- The feature often lies exactly on a visible polygon boundary. Exact-sign
-- clipping can erase it after subtraction rounded that boundary outward.
-- A 1e-10 model-distance allowance keeps this numerical edge without exposing
-- another layer at a visible drawing distance (600 px per model unit).
edgeInterval :: (V2, V2) -> [V2] -> Maybe (Double, Double)
edgeInterval (p, q) ring = foldl' step (Just (0, 1)) (ringEdges ring)
  where
    step Nothing _ = Nothing
    step interval@(Just (lo, hi)) (a, b)
      | norm edge <= 1e-14 = interval
      | gp >= 0 && gq >= 0 = interval
      | gp < 0 && gq < 0 = Nothing
      | otherwise = let t = gp / (gp - gq); result = if gp < 0 then (max lo t, hi) else (lo, min hi t) in if uncurry (<) result then Just result else Nothing
      where
        edge = b ^-^ a
        gap v = cross2 edge (v ^-^ a) / norm edge + 1e-10
        gp = gap p
        gq = gap q
