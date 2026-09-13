-- | Check the straight vertex paths of one numerical correction.
-- A solver proposes a displacement for every shared material vertex. Those
-- straight paths specify its line search, not a physical folding instruction:
-- triangles can stretch between the endpoints. HingeSweep separately handles
-- length-preserving rotations defined by crease angles.
--
-- A plane separating two triangles throughout an interval proves they cannot
-- cross there. We bound its signed projections in the Bernstein polynomial
-- basis: each value is a weighted average of the coefficients, so their signs
-- bound the entire interval. Rational arithmetic represents the input Doubles
-- exactly and preserves structural zeros at shared vertices. No tolerance turns
-- a small negative bound into a pass. This is a sufficient test, not a complete
-- root solver: uncertain intervals are split, and exhausted work is Unresolved.
--
-- A shared corner or edge is lawful contact. A separating plane may contain it,
-- but at least one triangle's NONSHARED vertices must lie strictly on its side.
-- Thus the intersection can contain only shared material. We also bound each
-- triangle's squared normal length, so collapsing a triangle cannot evade the
-- pair check. Static PanelContact diagnostics supply approximate witnesses;
-- only the exact interval bounds can return Clear. These are zero-thickness
-- checks on the specified numerical path, without contact clearance or forces.
module CorrectionSweep
  ( CorrectionSweep,
    CorrectionSettings (..),
    defaultCorrectionSettings,
    CorrectionOutcome (..),
    CorrectionCheck (..),
    CorrectionError (..),
    prepareCorrection,
    correctionMeshAt,
    checkCorrection,
  )
where

import Control.Monad (unless, when)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (foldl', tails)
import PanelContact qualified as Panel
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..), Triangle)

-- Polynomials use increasing powers of local interval progress. Three scalar
-- polynomials describe a moving point or a moving plane's normal vector.
type Polynomial = [Rational]

type Path = (Polynomial, Polynomial, Polynomial)

data CorrectionSweep = CorrectionSweep !MaterialMesh !MaterialMesh !(IM.IntMap Path)
  deriving stock (Eq, Show)

data CorrectionSettings = CorrectionSettings {correctionDepth :: !Int, correctionBudget :: !Int}
  deriving stock (Eq, Show)

defaultCorrectionSettings :: CorrectionSettings
defaultCorrectionSettings = CorrectionSettings 16 1024

data CorrectionOutcome
  = CorrectionClear
  | CorrectionCollision !Double ![(Int, Int)]
  | CorrectionDegenerate !Double ![Int]
  | CorrectionUnresolved !Double !Double ![(Int, Int)] ![Int]
  deriving stock (Eq, Show)

data CorrectionCheck = CorrectionCheck {correctionOutcome :: !CorrectionOutcome, correctionIntervals :: !Int}
  deriving stock (Eq, Show)

data CorrectionError
  = ChangedCorrectionMaterial
  | EmptyCorrectionMesh
  | InvalidCorrectionVertex !Int
  | MissingCorrectionVertex !Int
  | InvalidCorrectionTriangle !Int
  | InvalidCorrectionSettings
  | InvalidCorrectionProgress
  | CorrectionGeometry !Panel.ContactError
  deriving stock (Eq, Show)

instance Explain CorrectionError where
  explain ChangedCorrectionMaterial = "a numerical correction must keep the same material coordinates, vertex ids and triangles"
  explain EmptyCorrectionMesh = "a numerical correction needs at least one triangle"
  explain (InvalidCorrectionVertex i) = "numerical correction vertex " <> tshow i <> " has a non-finite coordinate"
  explain (MissingCorrectionVertex i) = "numerical correction refers to missing vertex " <> tshow i
  explain (InvalidCorrectionTriangle i) = "numerical correction triangle " <> tshow i <> " has zero material or endpoint area"
  explain InvalidCorrectionSettings = "correction sweep needs a depth from 0 to 30 and a positive interval budget"
  explain InvalidCorrectionProgress = "correction progress must be finite and between zero and one"
  explain (CorrectionGeometry err) = explain err

prepareCorrection :: MaterialMesh -> MaterialMesh -> Either CorrectionError CorrectionSweep
prepareCorrection start finish = do
  unless (triangles start == triangles finish && map sampleMaterial (samples start) == map sampleMaterial (samples finish)) (Left ChangedCorrectionMaterial)
  when (null (triangles start)) (Left EmptyCorrectionMesh)
  let finiteSample (i, s) = let V2 u v = sampleMaterial s; V3 x y z = position s in unless (all finite [u, v, x, y, z]) (Left (InvalidCorrectionVertex i))
  mapM_ finiteSample (zip [0 ..] (samples start))
  mapM_ finiteSample (zip [0 ..] (samples finish))
  let paths = IM.fromList (zip [0 ..] (zipWith (linearPath . position) (samples start) (map position (samples finish))))
      material = IM.fromList [(i, constant (V3 u v 0)) | (i, s) <- zip [0 ..] (samples start), let V2 u v = sampleMaterial s]
      validate (i, ids) = do
        ps <- mapM (\v -> maybe (Left (MissingCorrectionVertex v)) Right (IM.lookup v paths)) (corners ids)
        ms <- mapM (\v -> maybe (Left (MissingCorrectionVertex v)) Right (IM.lookup v material)) (corners ids)
        let area t = value t (dotPath (normal ps) (normal ps))
        unless (area 0 > 0 && area 1 > 0 && value 0 (dotPath (normal ms) (normal ms)) > 0) (Left (InvalidCorrectionTriangle i))
  mapM_ validate (zip [0 ..] (triangles start))
  pure (CorrectionSweep start finish paths)

-- | Inspect the specified optimizer displacement, not an angle-defined fold.
-- Endpoints are returned verbatim; only positions vary in interior witnesses.
correctionMeshAt :: CorrectionSweep -> Double -> Either CorrectionError MaterialMesh
correctionMeshAt (CorrectionSweep start finish _) t = do
  unless (finite t && t >= 0 && t <= 1) (Left InvalidCorrectionProgress)
  pure $ if t == 0 then start else if t == 1 then finish else start {samples = zipWith move (samples start) (samples finish)}
  where
    move a b = a {position = ((1 - t) *^ position a) ^+^ (t *^ position b)}

checkCorrection :: CorrectionSettings -> CorrectionSweep -> Either CorrectionError CorrectionCheck
checkCorrection settings sweep@(CorrectionSweep start _ paths) = do
  unless (correctionDepth settings >= 0 && correctionDepth settings <= 30 && correctionBudget settings > 0) (Left InvalidCorrectionSettings)
  initial <- witness 0 pairs triangleIds
  case initial of
    Just outcome -> pure (CorrectionCheck outcome 0)
    Nothing -> do
      final <- witness 1 pairs triangleIds
      case final of
        Just outcome -> pure (CorrectionCheck outcome 0)
        Nothing -> walk 0 (correctionDepth settings) 0 1 pairs triangleIds
  where
    topology = IM.fromList (zip [0 ..] (triangles start))
    triangleIds = IM.keys topology
    pairs = [(i, j) | i : rest <- tails triangleIds, j <- rest]
    ids i = maybe [] corners (IM.lookup i topology)
    path i = IM.findWithDefault ([], [], []) i paths
    point t i = atPath t (path i)
    -- Restrict the ORIGINAL exact linear paths to this rational interval.
    -- Repeated subdivision never rounds an intermediate mesh into new input.
    local lo hi i = lineBetween (point lo i) (point hi i)
    witness t candidates faces = do
      let collapsed = [i | i <- faces, let n = normal (map (constantPath . point t) (ids i)), value 0 (dotPath n n) == 0]
      if not (null collapsed)
        then pure (Just (CorrectionDegenerate (fromRational t) collapsed))
        else do
          current <- correctionMeshAt sweep (fromRational t)
          let vertices = IM.fromList (zip [0 ..] (samples current))
              panel i = Panel.Panel (tshow i) [position s | v <- ids i, Just s <- [IM.lookup v vertices]]
              inspect pair@(i, j) = do
                report <- first CorrectionGeometry (Panel.checkPanelContact (V3 0 0 1) [] [panel i, panel j])
                pure [pair | not (Panel.contactPassed report)]
          bad <- concat <$> mapM inspect candidates
          pure $ if null bad then Nothing else Just (CorrectionCollision (fromRational t) bad)
    walk used depth lo hi candidates faces
      | used >= correctionBudget settings = pure (unresolved used lo hi candidates faces)
      | otherwise = do
          let vertexPaths = IM.mapWithKey (\i _ -> local lo hi i) paths
              geometry = IM.map (map (\i -> IM.findWithDefault ([], [], []) i vertexPaths) . corners) topology
              ps i = IM.findWithDefault [] i geometry
              uncertainFaces = [i | i <- faces, let n = normal (ps i), not (positive (dotPath n n))]
              remaining = [(i, j) | (i, j) <- candidates, not (separated (ids i) (ps i) (ids j) (ps j))]
              count = used + 1
              mid = (lo + hi) / 2
          if null remaining && null uncertainFaces
            then pure (CorrectionCheck CorrectionClear count)
            else do
              middle <- witness mid remaining uncertainFaces
              case middle of
                Just outcome -> pure (CorrectionCheck outcome count)
                Nothing | depth == 0 -> pure (unresolved count lo hi remaining uncertainFaces)
                Nothing -> do
                  left <- walk count (depth - 1) lo mid remaining uncertainFaces
                  case correctionOutcome left of
                    CorrectionClear -> walk (correctionIntervals left) (depth - 1) mid hi remaining uncertainFaces
                    _ -> pure left
    unresolved count lo hi pairs' faces = CorrectionCheck (CorrectionUnresolved (fromRational lo) (fromRational hi) pairs' faces) count

-- First try fixed directions over the whole interval, then planes attached to
-- either moving triangle. A failed certificate means subdivide, not collision.
separated :: [Int] -> [Path] -> [Int] -> [Path] -> Bool
separated ai as bi bs = any along axes || any plane planes
  where
    common = filter (`elem` bi) ai
    mid = map (constantPath . atPath (1 / 2))
    am = mid as
    bm = mid bs
    an = normal am
    bn = normal bm
    ae = edges am
    be = edges bm
    axes = map constant [V3 1 0 0, V3 0 1 0, V3 0 0 1] ++ [an, bn] ++ [crossPath a b | a <- ae, b <- be] ++ map (crossPath an) ae ++ map (crossPath bn) be
    -- Subtract paired vertices before bounding: common translation cancels.
    along axis = let differences = [dotPath axis (subPath b a) | a <- as, b <- bs] in all positive differences || all (positive . negatePoly) differences
    movingPlanes ps = case ps of
      origin : _ -> (normal ps, origin) : [(crossPath (normal ps) edge, a) | (a, edge) <- zip ps (edges ps)]
      [] -> []
    -- Edge planes can contain a nonshared vertex on EACH triangle when two
    -- flat triangles meet only at a corner. A direction between their vertex
    -- sums supplies another candidate through that corner (the centroid
    -- difference, without dividing by three). The same exact side proof is
    -- still required; selecting this direction alone establishes nothing.
    vertexSum = foldl' addPath ([], [], [])
    cornerPlanes = [(subPath (vertexSum as) (vertexSum bs), p) | (i, p) <- zip ai as, i `elem` common]
    planes = movingPlanes as ++ movingPlanes bs ++ cornerPlanes
    plane (axis, origin) = side axis origin || side (negatePath axis) origin
    side axis origin =
      let av = [(i, dotPath axis (subPath a origin)) | (i, a) <- zip ai as]
          bv = [(i, negatePoly (dotPath axis (subPath b origin))) | (i, b) <- zip bi bs]
          interior values = [p | (i, p) <- values, i `notElem` common]
          strict values = not (null values) && all positive values
       in length common < 3 && all (nonnegative . snd) av && all (nonnegative . snd) bv && (strict (interior av) || strict (interior bv))

-- Power t^j has Bernstein coefficient choose(k,j)/choose(n,j) at index k.
-- The Bernstein basis is nonnegative and sums to one on [0,1].
bernstein :: Polynomial -> [Rational]
bernstein [] = [0]
bernstein coefficients = [sum [a * fromInteger (choose k j) / fromInteger (choose degree j) | (j, a) <- zip [0 .. k] coefficients] | k <- [0 .. degree]]
  where
    degree = length coefficients - 1
    choose n k = product [toInteger (n - k + 1) .. toInteger n] `div` product [1 .. toInteger k]

positive :: Polynomial -> Bool
positive = all (> 0) . bernstein

nonnegative :: Polynomial -> Bool
nonnegative = all (>= 0) . bernstein

add :: Polynomial -> Polynomial -> Polynomial
add [] ys = ys
add xs [] = xs
add (x : xs) (y : ys) = (x + y) : add xs ys

negatePoly :: Polynomial -> Polynomial
negatePoly = map negate

multiply :: Polynomial -> Polynomial -> Polynomial
multiply xs ys = foldl' add [] [replicate i 0 ++ map (x *) ys | (i, x) <- zip [0 ..] xs]

value :: Rational -> Polynomial -> Rational
value t = foldr (\coefficient rest -> coefficient + t * rest) 0

subPath :: Path -> Path -> Path
subPath (ax, ay, az) (bx, by, bz) = (add ax (negatePoly bx), add ay (negatePoly by), add az (negatePoly bz))

addPath :: Path -> Path -> Path
addPath (ax, ay, az) (bx, by, bz) = (add ax bx, add ay by, add az bz)

negatePath :: Path -> Path
negatePath (x, y, z) = (negatePoly x, negatePoly y, negatePoly z)

dotPath :: Path -> Path -> Polynomial
dotPath (ax, ay, az) (bx, by, bz) = add (multiply ax bx) (add (multiply ay by) (multiply az bz))

crossPath :: Path -> Path -> Path
crossPath (ax, ay, az) (bx, by, bz) = (minus ay bz az by, minus az bx ax bz, minus ax by ay bx)
  where
    minus a b c d = add (multiply a b) (negatePoly (multiply c d))

atPath :: Rational -> Path -> (Rational, Rational, Rational)
atPath t (x, y, z) = (value t x, value t y, value t z)

constantPath :: (Rational, Rational, Rational) -> Path
constantPath (x, y, z) = ([x], [y], [z])

constant :: V3 -> Path
constant (V3 x y z) = constantPath (toRational x, toRational y, toRational z)

lineBetween :: (Rational, Rational, Rational) -> (Rational, Rational, Rational) -> Path
lineBetween (ax, ay, az) (bx, by, bz) = ([ax, bx - ax], [ay, by - ay], [az, bz - az])

linearPath :: V3 -> V3 -> Path
linearPath a b = lineBetween (atPath 0 (constant a)) (atPath 0 (constant b))

normal :: [Path] -> Path
normal [a, b, c] = crossPath (subPath b a) (subPath c a)
normal _ = ([], [], [])

edges :: [Path] -> [Path]
edges ps = zipWith subPath (drop 1 ps ++ take 1 ps) ps

corners :: Triangle -> [Int]
corners (a, b, c) = [a, b, c]

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)
