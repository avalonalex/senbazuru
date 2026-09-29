-- | A paper screen: how far a pose is from paper, written beside it.
--
-- PRD 11 (R-11-1 and R-11-3) asks that nothing be shown as paper that paper
-- could not be. The screen is a handful of measures read from a pose alone,
-- with no solver:
--
-- * principal strain, stretch and squash apart, since stretching is what
--   tears paper, while squashed paper can take up the slack in wrinkles too
--   small for the mesh to show;
-- * the no-stretch floor, how far some point must move before the pose could
--   be paper at all;
-- * crossings, counted by the study's strict test, with the largest
--   reach-through among them;
-- * false-crease turning: how much the pose bends paper along joins, the
--   edges a panel was cut into for the mesh, where the crease pattern has no
--   crease;
-- * the body core's head-to-tail length and its centre creases, which tell a
--   pod, a body swung open about its spine, from a pillow, one lengthened and
--   filled out.
--
-- The line that looks like a slip is the halving in the floor. Paper cannot
-- stretch, so no two of its points end up further apart than they are on the
-- flat sheet. A pair too far apart by @e@ can share the correction, each
-- moving @e/2@ towards the other, so the floor promises only that one of them
-- moves @e/2@. That promise is a proof, not an estimate, but only while the
-- straight line between the two points lies in the sheet. On a sheet with a
-- notch, or a slit that stores one material point twice, two points can be
-- further apart than a straight line allows without any stretch. So such a
-- sheet is refused rather than measured.
--
-- A count of crossings on touching paper measures rounding, not paper
-- (@docs/notes/crossing-counts-on-touching-paper.md@). Owner decision 16
-- reports crossings with no pass or fail for now. The reach-through of a pair,
-- the smaller of how far each triangle reaches past the other's plane on its
-- shorter side, bounds how far the pair passes through; it is not the depth
-- itself, and the pair with the largest bound need not be the deepest.
module PaperScreen
  ( FloorPair (..),
    ScreenError (..),
    Turning (..),
    sheetIsConvex,
    noStretchFloor,
    strainExtremes,
    reachThrough,
    deepestReach,
    falseCreaseTurning,
    coreLength,
    centreFolds,
  )
where

import Data.IntMap.Strict qualified as IM
import Data.List (foldl', sort, sortOn, tails)
import Data.Maybe (isJust, mapMaybe)
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import FoldMaterial (resolvedTriangles)
import FoldRelaxation (principalStrains)
import Senbazuru.Explain (Explain (..), num, tshow)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (cross2, signedArea)
import Senbazuru.Geometry.V3 (V3 (..), cross, spanAlong)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..))
import Text.Read (readMaybe)

-- | The pair of material vertices that sets a floor, and the floor itself in
-- sheet sides, the flat square's side being 1. It can be negative: then every
-- pair is already closer than the strain screen allows, and no point need
-- move.
data FloorPair = FloorPair
  { floorDistance :: !Double,
    floorVertices :: !(Int, Int)
  }
  deriving stock (Eq, Show)

-- | Why a pose could not be screened.
data ScreenError
  = -- | The sheet's convex hull is larger than the sheet by this area.
    NonConvexSheet !Double
  | -- | Two vertices share a material point: the sheet is cut there.
    RepeatedMaterialPoint !Int !Int
  | -- | A flagged pair named a triangle the mesh does not have.
    UnknownTriangle !Text
  | -- | A triangle has no plane to measure a reach from.
    DegenerateTriangle !Int
  deriving stock (Eq, Show)

instance Explain ScreenError where
  explain (NonConvexSheet excess) = "the sheet is not convex (its convex hull's area is larger by " <> num excess <> "), so a straight line between two of its points can leave the paper and the no-stretch floor would not be a bound"
  explain (RepeatedMaterialPoint i j) = "vertices " <> tshow i <> " and " <> tshow j <> " are the same point of the flat sheet, so the sheet is cut there and the no-stretch floor would not be a bound"
  explain (UnknownTriangle name) = "the crossing check named " <> name <> ", which is not a triangle of this mesh"
  explain (DegenerateTriangle i) = "triangle " <> tshow i <> " has no area, so no plane to measure a reach from"

-- | Refuse a sheet on which a straight line between two of its points can
-- leave the paper: the floor's promise needs every chord of the sheet to lie
-- in it. A notch shows as a convex hull larger than the sheet. A slit does
-- not, since it removes no area, so it is found where it is stored: as two
-- vertices at one material point.
sheetIsConvex :: MaterialMesh -> Either ScreenError ()
sheetIsConvex mesh = do
  case [(i, j) | (i, u) : rest <- tails indexed, (j, v) <- rest, norm (u ^-^ v) < 1e-12] of
    (i, j) : _ -> Left (RepeatedMaterialPoint i j)
    [] -> Right ()
  if excess > 1e-9 * max 1 hullArea then Left (NonConvexSheet excess) else Right ()
  where
    indexed = zip [0 ..] (map sampleMaterial (samples mesh))
    sheetArea = sum [abs (signedArea [sampleMaterial a, sampleMaterial b, sampleMaterial c]) | (a, b, c) <- resolvedTriangles mesh]
    hullArea = abs (signedArea (hull (map sampleMaterial (samples mesh))))
    excess = hullArea - sheetArea

-- | Andrew's monotone chain: the lower hull left to right, then the upper
-- hull back, each dropping a point that does not turn anticlockwise.
hull :: [V2] -> [V2]
hull points = case sortOn (\(V2 x y) -> (x, y)) points of
  sorted@(_ : _ : _) -> dropLast (chain sorted) ++ dropLast (chain (reverse sorted))
  few -> few
  where
    -- Each chain ends where the other begins; keep that point once.
    dropLast xs = take (length xs - 1) xs
    chain = reverse . foldl' keep []
    keep (b : a : rest) p | cross2 (b ^-^ a) (p ^-^ b) <= 0 = keep (a : rest) p
    keep stack p = p : stack

-- | The no-stretch floor at strain screen @epsilon@: over every pair of
-- material vertices, the largest @(|x_i - x_j| - (1 + epsilon) |u_i - u_j|) / 2@,
-- where @u@ is the flat-sheet position and @x@ the placed one. Placed points
-- in 3D give the floor in space; points projected onto a page give the floor
-- in that picture, which is a floor too, since projecting never lengthens.
-- The distance is always straight-line length: another measure would not
-- make the floor a bound.
noStretchFloor :: (VectorSpace a) => Double -> [(V2, a)] -> Maybe FloorPair
noStretchFloor epsilon placed = maximumOn floorDistance pairs
  where
    indexed = zip [0 ..] placed
    pairs =
      [ FloorPair ((norm (x ^-^ y) - (1 + epsilon) * norm (u ^-^ v)) / 2) (i, j)
        | (i, (u, x)) : rest <- tails indexed,
          (j, (v, y)) <- rest
      ]

-- | The largest squash and the largest stretch over the mesh's triangles, as
-- non-negative fractions: squash 0.2 is a side shortened by a fifth.
strainExtremes :: MaterialMesh -> (Double, Double)
strainExtremes mesh = (abs (minimum (0 : map fst strains)), maximum (0 : map snd strains))
  where
    strains = mapMaybe principalStrains (resolvedTriangles mesh)

-- | How far two triangles pass through each other, at most: for each, how far
-- its corners reach past the other's plane on its shorter side, and the
-- smaller of the two. Moving the triangle with the smaller reach that far
-- along the other's normal, towards the side it reaches further on, leaves it
-- on one side of the other's plane. The larger reach measures how big the
-- other triangle is, not how deep they meet, so it is not taken. The true
-- depth can be smaller still, when a move in another direction separates
-- the pair sooner.
reachThrough :: (V3, V3, V3) -> (V3, V3, V3) -> Maybe Double
reachThrough a b = min <$> reach a b <*> reach b a
  where
    reach (p, q, r) (o, s, t) = do
      n <- normalize (cross (s ^-^ o) (t ^-^ o))
      let heights = [dot n (c ^-^ o) | c <- [p, q, r]]
      pure (max 0 (min (negate (minimum heights)) (maximum heights)))

-- | The largest reach-through among the pairs a crossing check flagged, with
-- the pair, named as that check names triangles: @triangle-i@ is the i-th of
-- the mesh's own triangles.
deepestReach :: MaterialMesh -> [(Text, Text)] -> Either ScreenError (Maybe (Double, (Int, Int)))
deepestReach mesh flagged = do
  reaches <- mapM measure flagged
  pure (maximumOn fst reaches)
  where
    points = IM.fromList (zip [0 ..] (map position (samples mesh)))
    faces = IM.fromList (zip [0 ..] (triangles mesh))
    -- Each triangle's plane is checked on its own, so a pair with one flat
    -- triangle blames that one rather than the first of the pair.
    triangle name = case T.stripPrefix "triangle-" name >>= readMaybe . T.unpack of
      Just i
        | Just (a, b, c) <- IM.lookup i faces,
          Just corners@(p, q, r) <- (,,) <$> IM.lookup a points <*> IM.lookup b points <*> IM.lookup c points ->
            if isJust (normalize (cross (q ^-^ p) (r ^-^ p))) then Right (i, corners) else Left (DegenerateTriangle i)
      _ -> Left (UnknownTriangle name)
    measure (one, other) = do
      (i, a) <- triangle one
      (j, b) <- triangle other
      -- Both planes were found above, so this is never Nothing.
      depth <- maybe (Left (DegenerateTriangle i)) Right (reachThrough a b)
      pure (depth, (i, j))

-- | Turning along false creases: joins bent past the threshold, in degrees.
data Turning = Turning
  { turningJoins :: !Int,
    -- | Sheet sides times degrees, summed over those joins.
    turningTotal :: !Double
  }
  deriving stock (Eq, Show)

-- | Sum length times angle over the joins bent past @threshold@ degrees,
-- given each join's material length and its bend in degrees. The threshold
-- is what separates a fold, whose total survives refinement, from a curve
-- sampled by the mesh, whose joins each bend less as the mesh gets finer
-- (Y3 in PRD 11's research). Counting joins instead of summing would call a
-- fold cut across more triangles a worse fold.
falseCreaseTurning :: Double -> [(Double, Double)] -> Turning
falseCreaseTurning threshold joins = Turning (length bent) (sum [len * angle | (len, angle) <- bent])
  where
    bent = [(len, abs angle) | (len, angle) <- joins, abs angle > threshold]

-- | The core's head-to-tail length: its extent along x, the crane's long
-- axis in the study's coordinates, in sheet sides.
coreLength :: S.Set Int -> MaterialMesh -> Maybe Double
coreLength core mesh = case [position s | (i, s) <- zip [0 ..] (samples mesh), S.member i core] of
  [] -> Nothing
  corePoints -> Just (spanAlong v3x corePoints)

-- | The median fold, in degrees, of the core's crease segments through the
-- sheet's centre, split into those along the square's midlines and those
-- along its diagonals. Each segment is given as its two material endpoints
-- and its fold in degrees.
centreFolds :: V2 -> [(V2, V2, Double)] -> (Maybe Double, Maybe Double)
centreFolds centre segments = (median midline, median diagonal)
  where
    through = [(a, b, abs angle) | (a, b, angle) <- segments, abs (cross2 (b ^-^ a) (centre ^-^ a)) < 1e-9 * max 1 (norm (b ^-^ a))]
    isDiagonal (a, b, _) = let V2 dx dy = b ^-^ a in abs (abs dx - abs dy) < 1e-9 * max 1 (abs dx + abs dy)
    diagonal = [angle | s@(_, _, angle) <- through, isDiagonal s]
    midline = [angle | s@(_, _, angle) <- through, not (isDiagonal s)]

-- | The middle value, or the mean of the two middle values; nothing of none.
median :: [Double] -> Maybe Double
median xs = case drop (half - 1) sorted of
  lower : upper : _ | even (length xs) -> Just ((lower + upper) / 2)
  _ -> case drop half sorted of
    middle : _ -> Just middle
    [] -> Nothing
  where
    sorted = sort xs
    half = length xs `div` 2

-- | The element with the largest key, the first of equals; nothing of none.
-- A strict left fold, so each comparison is made as the list is walked
-- rather than left as a chain to run at the end.
maximumOn :: (Ord b) => (a -> b) -> [a] -> Maybe a
maximumOn key = foldl' pick Nothing
  where
    pick Nothing x = Just x
    pick (Just best) x = if key x > key best then Just x else Just best
