-- | A deliberately small geometric experiment for issue #114.
--
-- A crease is a line marked on the original flat sheet. Here the line at
-- u = 1/2 is replaced by a band of that sheet, bent into a half-cylinder.
-- Its width is pi*r: the bend uses existing paper instead of adding a bridge.
-- Coordinates (u,v) continue to identify the original material after folding.
--
-- The second fold turns the already folded packet about a perpendicular axis.
-- The upper layer must travel around a larger radius. Keeping the same band
-- of material for both layers STRETCHES it. This module intentionally retains
-- that failed assumption as a measurable baseline, not a physical solver.
-- See docs/notes/two-bends-need-more-than-radii.md for the derivation.
--
-- A sharp comparison uses an exact rigid single hinge and prescribed curved
-- double-fold panels, with gaps tapering to the crease lines. Its much smaller
-- distortion is still a failure of isometry; see sharp-creases-and-opening-panels.md.
--
-- Kept outside the library: neither a new CLI folding operation nor a general
-- interpretation of FOLD. The two examples are generated from these formulas.
module FoldMaterial
  ( FoldCase (..),
    Sample (..),
    Mesh (..),
    Triangle,
    radius,
    bendStart,
    bendEnd,
    firstProfile,
    paperPoint,
    makeMesh,
    sharpPoint,
    sharpMesh,
    sharpStretch,
    opening,
    resolvedTriangles,
    meshEdges,
    edgeStrains,
    areaRatio,
    componentCount,
    analyticStretch,
  )
where

import Data.IntMap.Strict qualified as IM
import Data.List (foldl')
import Data.Map.Strict qualified as M
import Data.Maybe (mapMaybe)
import Data.Set qualified as S
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace

data FoldCase = Single | Double
  deriving stock (Eq, Show)

data Sample = Sample
  { materialU :: !Double,
    materialV :: !Double,
    position :: !V3
  }
  deriving stock (Eq, Show)

type Triangle = (Int, Int, Int)

data Mesh = Mesh
  { samples :: ![Sample],
    triangles :: ![Triangle]
  }
  deriving stock (Eq, Show)

-- | A visible demonstration scale, not a measured paper parameter.
-- The original square has side 1; adjacent layer mid-surfaces are 0.03 apart.
radius :: Double
radius = 0.015

bendStart, bendEnd :: Double
bendStart = 0.5 - pi * radius / 2
bendEnd = 0.5 + pi * radius / 2

-- | Cross-section (x,z), measured by distance u along the original sheet.
-- The two straight portions are shortened by half the bend's material width.
firstProfile :: Double -> (Double, Double)
firstProfile u
  | u < bendStart = (u, 0)
  | u > bendEnd = (1 - u, 2 * radius)
  | otherwise =
      let theta = (u - bendStart) / radius
       in (bendStart + radius * sin theta, radius * (1 - cos theta))

paperPoint :: FoldCase -> Double -> Double -> V3
paperPoint which u v =
  let (x, z) = firstProfile u
   in case which of
        Single -> V3 x v z
        Double
          | v < bendStart -> V3 x v z
          | v > bendEnd -> V3 x (1 - v) (-2 * radius - z)
          | otherwise ->
              -- The PLUS z is intentional. The second fold turns downwards,
              -- so the upper layer lies outside the lower layer's bend.
              let theta = (v - bendStart) / radius
                  outerRadius = radius + z
               in V3 x (bendStart + outerRadius * sin theta) (-radius + outerRadius * cos theta)

-- | Fractional extension in the v direction, on the smooth surface.
-- Zero means unchanged length; 2 means a strip became three times as long.
analyticStretch :: FoldCase -> Double -> Double -> Double
analyticStretch Single _ _ = 0
analyticStretch Double u v
  | v > bendStart && v < bendEnd = snd (firstProfile u) / radius
  | otherwise = 0

-- | n subdivisions of each bend, with its exact endpoints in the grid.
-- The flat parts need no subdivision: their maps are linear. Clamping n
-- avoids a zero divisor; this experiment has no user-supplied mesh settings.
makeMesh :: Int -> FoldCase -> Mesh
makeMesh requested which =
  let n = max 2 requested
      axis = 0 : [bendStart + pi * radius * fromIntegral i / fromIntegral n | i <- [0 .. n]] ++ [1]
   in meshOn Uniform axis (paperPoint which)

-- | Free-edge opening as a fraction of the original square's side, not
-- thickness. The single fold rotates one rigid half about a sharp hinge.
-- The double fold prescribes heights that vanish at the shared crease:
-- panels separate towards their free edges instead of sitting in parallel
-- planes. Its curved panels stretch; this is a drawing target, not equilibrium.
opening :: Double
opening = 0.025

sharpPoint :: FoldCase -> Double -> Double -> V3
sharpPoint Single u v
  | u <= 0.5 = V3 u v 0
  | otherwise =
      let angle = asin (2 * opening)
          distance = u - 0.5
       in V3 (0.5 - distance * cos angle) v (distance * sin angle)
sharpPoint Double u v =
  let s = 2 * max 0 (u - 0.5)
      t = 2 * abs (v - 0.5)
      z = if v <= 0.5 then opening * s * t else -opening * (1 + s) * t
   in V3 (min u (1 - u)) (min v (1 - v)) z

-- | Largest local extension over ALL material directions. For the double
-- fold, height is a graph over an otherwise reflected flat square. Its
-- largest squared length multiplier is 1 + z_u^2 + z_v^2. Small distortion
-- is still distortion; a nice silhouette is not evidence of valid paper.
sharpStretch :: FoldCase -> Double -> Double -> Double
sharpStretch Single _ _ = 0
sharpStretch Double u v =
  let s = 2 * max 0 (u - 0.5)
      t = 2 * abs (v - 0.5)
      dzdu = if u > 0.5 then 2 * opening * t else 0
      dzdv = 2 * opening * (if v <= 0.5 then s else 1 + s)
   in sqrt (1 + dzdu * dzdu + dzdv * dzdv) - 1

sharpMesh :: Int -> FoldCase -> Mesh
sharpMesh requested which =
  -- An even grid always includes both crease lines exactly. Otherwise a
  -- triangle could bridge the kink and hide the sharp crease in the mesh.
  let n = 2 * max 1 requested
   in meshOn MeetCreases [fromIntegral i / fromIntegral n | i <- [0 .. n]] (sharpPoint which)

data Diagonals = Uniform | MeetCreases
  deriving stock (Eq)

meshOn :: Diagonals -> [Double] -> (Double -> Double -> V3) -> Mesh
meshOn diagonals axis point =
  let count = length axis
      verts = [Sample u v (point u v) | v <- axis, u <- axis]
      cell i j =
        let a = j * count + i
            b = a + 1
            c = a + count
            d = c + 1
            -- The gap closes on two crossing crease lines. Joining points on
            -- those lines cuts off a flat triangle, coincident with the layer
            -- beneath it. Run the diagonal INTO the intersection instead, so
            -- both triangles also contain a vertex away from the creases.
            opposite = diagonals == MeetCreases && ((i < (count - 1) `div` 2) /= (j < (count - 1) `div` 2))
         in if opposite then [(a, b, c), (b, d, c)] else [(a, b, d), (a, d, c)]
   in Mesh verts (concat [cell i j | j <- [0 .. count - 2], i <- [0 .. count - 2]])

resolvedTriangles :: Mesh -> [(Sample, Sample, Sample)]
resolvedTriangles mesh =
  let vertices = IM.fromList (zip [0 ..] (samples mesh))
      resolve (a, b, c) = (,,) <$> IM.lookup a vertices <*> IM.lookup b vertices <*> IM.lookup c vertices
   in mapMaybe resolve (triangles mesh)

-- | Unique material edges, including triangulation diagonals. All faces use
-- shared vertex ids, so adjacency does not depend on coincident coordinates.
meshEdges :: Mesh -> [(Int, Int)]
meshEdges = S.toList . S.fromList . concatMap sides . triangles
  where
    sides (a, b, c) = map ordered [(a, b), (b, c), (c, a)]
    ordered (a, b) = (min a b, max a b)

edgeStrains :: Mesh -> [Double]
edgeStrains mesh = mapMaybe strain (meshEdges mesh)
  where
    vertices = IM.fromList (zip [0 ..] (samples mesh))
    strain (i, j) = do
      a <- IM.lookup i vertices
      b <- IM.lookup j vertices
      let du = materialU a - materialU b
          dv = materialV a - materialV b
          rest = sqrt (du * du + dv * dv)
      if rest > 0
        then Just (norm (position a ^-^ position b) / rest - 1)
        else Nothing

-- | The original square has area one, so the sum is already an area ratio.
areaRatio :: Mesh -> Double
areaRatio = sum . map triangleArea . resolvedTriangles
  where
    triangleArea (a, b, c) = norm (cross (position b ^-^ position a) (position c ^-^ position a)) / 2

componentCount :: Mesh -> Int
componentCount mesh = visit 0 (S.fromList [0 .. length (samples mesh) - 1])
  where
    neighbours = M.fromListWith (++) (concatMap (\(a, b) -> [(a, [b]), (b, [a])]) (meshEdges mesh))
    visit count remaining = case S.minView remaining of
      Nothing -> count
      Just (start, _) -> visit (count + 1) (remaining S.\\ reachable S.empty [start])
    reachable seen [] = seen
    reachable seen (x : pending)
      | S.member x seen = reachable seen pending
      | otherwise = reachable (S.insert x seen) (foldl' (flip (:)) pending (M.findWithDefault [] x neighbours))
