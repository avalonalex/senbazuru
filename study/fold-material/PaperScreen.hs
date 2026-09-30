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
-- moves @e/2@. That promise is a proof, not an estimate, but only for a pair
-- whose straight line on the flat sheet, its chord, stays on the paper: then
-- the distance along the paper is the chord's length. On a sheet that is not
-- convex, a chord can cross a notch, and its two ends can then move further
-- apart than the chord without any stretch. So the floor is taken over the
-- pairs whose chord stays on the sheet ('sheetChords', owner decision 28). A
-- floor over fewer pairs is still a floor, since each pair's excess is a
-- proof on its own; it can only be smaller. A cut sheet is refused instead,
-- since a line from a point on a cut cannot tell which side of the cut it
-- leaves by, and so is a mesh the screen cannot read: one with no triangle,
-- a triangle with no area, or a point that is not finite.
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
    Chords (..),
    sheetChords,
    keptPairs,
    finitePoints,
    noStretchFloor,
    pictureFloor,
    strainExtremes,
    reachThrough,
    deepestReach,
    falseCreaseTurning,
    coreLength,
    centreFolds,
  )
where

import Control.Monad (when)
import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.List (foldl', sort, sortOn, tails)
import Data.Map.Strict qualified as M
import Data.Maybe (isJust, mapMaybe)
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import FoldMaterial (resolvedTriangles)
import FoldRelaxation (principalStrains)
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Geometry (V2 (..), boxFromPoints, boxSize)
import Senbazuru.Geometry.Polygon (cross2, distanceToSegment, segmentsCross, signedArea)
import Senbazuru.Geometry.V3 (V3 (..), cross, spanAlong)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..))
import Senbazuru.Render.Camera (Basis, project)
import Text.Read (readMaybe)

-- | The pair of material vertices that sets a floor, and the floor itself in
-- sheet units, units of the flat sheet's coordinates (docs/glossary.md). It
-- can be negative: then every pair is already closer than the strain screen
-- allows, and no point need move.
data FloorPair = FloorPair
  { floorDistance :: !Double,
    floorVertices :: !(Int, Int)
  }
  deriving stock (Eq, Show)

-- | Why a pose could not be screened.
data ScreenError
  = -- | The mesh has no triangle, so there is no sheet to screen.
    EmptySheet
  | -- | Triangle @i@ names vertex @v@, which the mesh does not have.
    UnknownVertex !Int !Int
  | -- | A triangle has no area on the flat sheet.
    DegenerateSheetTriangle !Int
  | -- | Two vertices share a material point: the sheet is cut there.
    RepeatedMaterialPoint !Int !Int
  | -- | The sheet is cut along this edge of its boundary: there is paper on
    -- both sides of it.
    CutAlong !Int !Int
  | -- | A vertex is not at a finite place, on the flat sheet or in the pose.
    NonFinitePoint !Int
  | -- | A flagged pair named a triangle the mesh does not have.
    UnknownTriangle !Text
  | -- | A triangle has no plane to measure a reach from.
    DegenerateTriangle !Int
  | -- | The surface whose joins were to be read was written for another
    -- mesh: its faces are not this mesh's triangles.
    SurfaceOfAnotherMesh
  deriving stock (Eq, Show)

instance Explain ScreenError where
  explain EmptySheet = "the mesh has no triangles, so there is no sheet to screen"
  explain (UnknownVertex i v) = "triangle " <> tshow i <> " names vertex " <> tshow v <> ", which the mesh does not have"
  explain (DegenerateSheetTriangle i) = "triangle " <> tshow i <> " has no area on the flat sheet, so the sheet's outline cannot be read from it"
  explain (CutAlong a b) = "the sheet is cut along the edge from vertex " <> tshow a <> " to vertex " <> tshow b <> ": there is paper on both sides of it, so the no-stretch floor cannot tell which side of the cut a straight line leaves by"
  explain (NonFinitePoint i) = "vertex " <> tshow i <> " is not at a finite place, on the flat sheet or in the pose, so the screen cannot measure it"
  explain (RepeatedMaterialPoint i j) = "vertices " <> tshow i <> " and " <> tshow j <> " are the same point of the flat sheet, so the sheet is cut there, and the no-stretch floor cannot tell which side of the cut a straight line from it leaves by"
  explain (UnknownTriangle name) = "the crossing check named " <> name <> ", which is not a triangle of this mesh"
  explain (DegenerateTriangle i) = "triangle " <> tshow i <> " has no area, so no plane to measure a reach from"
  explain SurfaceOfAnotherMesh = "the surface given was written for another mesh: its faces are not this mesh's triangles, so its joins cannot be matched to this mesh's hinges"

-- | The pairs of a sheet's vertices the no-stretch floor may use: those whose
-- chord, the straight line between them on the flat sheet, stays on the
-- paper.
data Chords
  = -- | A convex sheet, on which every chord stays.
    EveryChord
  | -- | A sheet that is not convex: the pairs, smaller vertex first, whose
    -- chord stays on it.
    ChordsOnSheet !(S.Set (Int, Int))
  deriving stock (Eq, Show)

-- | The chords of a mesh's flat sheet that the floor may use, or a refusal.
-- A sheet is refused when the screen cannot read it (no triangle, a triangle
-- naming a vertex the mesh lacks or having no area, a point that is not
-- finite) and when it is cut. A cut is found where it is stored, as two
-- vertices at one material point, and wherever it is stored, as a boundary
-- edge with paper on the far side of it too. A notch shows as a convex hull
-- larger than the sheet.
--
-- On a sheet with a notch, a chord stays on the paper when it crosses no
-- edge of the boundary and each of its pieces, split at the boundary's
-- corners it passes through, has its midpoint on the paper. A piece then
-- meets the boundary only at its ends, so it is on the paper throughout or
-- off it throughout. A point is on the paper when it lies within a hair of
-- the boundary, or inside it by the even-odd rule: a ray from it crosses the
-- boundary an odd number of times.
sheetChords :: MaterialMesh -> Either ScreenError Chords
sheetChords mesh = do
  case [i | (i, u) <- indexed, not (finite2 u)] of
    i : _ -> Left (NonFinitePoint i)
    [] -> Right ()
  when (null (triangles mesh)) (Left EmptySheet)
  faces <- mapM corners (zip [0 ..] (triangles mesh))
  case [i | (i, face) <- zip [0 :: Int ..] faces, noArea face] of
    i : _ -> Left (DegenerateSheetTriangle i)
    [] -> Right ()
  case [(i, j) | (i, u) : rest <- tails indexed, (j, v) <- rest, norm (u ^-^ v) <= hair] of
    (i, j) : _ -> Left (RepeatedMaterialPoint i j)
    [] -> Right ()
  case [(a, b) | (a, b, u, v, w) <- boundary, cutAlong u v w] of
    (a, b) : _ -> Left (CutAlong a b)
    [] -> Right ()
  let sheetArea = sum (map (abs . signedArea) faces)
      hullArea = abs (signedArea (hull (map snd indexed)))
  pure $
    if hullArea - sheetArea <= 1e-9 * max 1 hullArea
      then EveryChord
      else ChordsOnSheet (S.fromList [(i, j) | (i, u) : rest <- tails indexed, (j, v) <- rest, onPaper u v])
  where
    indexed = zip [0 ..] (map sampleMaterial (samples mesh))
    material = IM.fromList indexed
    corners (i, (a, b, c)) = mapM (\v -> maybe (Left (UnknownVertex i v)) Right (IM.lookup v material)) [a, b, c]
    -- A triangle is flat when its height over its longest side is a hair.
    noArea face = case face of
      [a, b, c] -> 2 * abs (signedArea face) <= hair * maximum [norm (b ^-^ a), norm (c ^-^ b), norm (a ^-^ c)]
      _ -> True
    -- Distances are judged to a hair, and a cut is looked for a step off
    -- each boundary edge, both scaled to the sheet as the library's
    -- tolerances are.
    scale = maybe 1 (max 1 . norm . boxSize) (boxFromPoints (map snd indexed))
    hair = 1e-9 * scale
    step = 1e-6 * scale
    -- The boundary: each edge that only one triangle has, with its ends and
    -- that triangle's third corner, which says which side the paper is on.
    owners = M.fromListWith (++) [((min a b, max a b), [c]) | (i, j, k) <- triangles mesh, (a, b, c) <- [(i, j, k), (j, k, i), (k, i, j)]]
    boundary = [(a, b, u, v, w) | ((a, b), [c]) <- M.toList owners, Just u <- [IM.lookup a material], Just v <- [IM.lookup b material], Just w <- [IM.lookup c material]]
    edges = [(u, v) | (_, _, u, v, _) <- boundary]
    cornerPoints = [p | i <- IS.toList (IS.fromList (concat [[a, b] | (a, b, _, _, _) <- boundary])), Just p <- [IM.lookup i material]]
    -- A step off the middle of a boundary edge, away from its triangle,
    -- lands off the paper unless there is paper beyond the edge as well.
    cutAlong u v w = insideBoundary (middle ^+^ (step / norm across) *^ away)
      where
        middle = 0.5 *^ (u ^+^ v)
        across = let V2 x y = v ^-^ u in V2 (negate y) x
        away = if dot across (w ^-^ middle) > 0 then (-1) *^ across else across
    insideBoundary (V2 x y) = odd (length [() | (V2 ax ay, V2 bx by) <- edges, (ay > y) /= (by > y), x < ax + (y - ay) * (bx - ax) / (by - ay)])
    paperAt p = any (\e -> distanceToSegment e p <= hair) edges || insideBoundary p
    onPaper u v =
      not (any (segmentsCross hair (u, v)) edges)
        && all paperAt [0.5 *^ (p ^+^ q) | (p, q) <- zip stops (drop 1 stops)]
      where
        touched = [c | c <- cornerPoints, distanceToSegment (u, v) c <= hair, norm (c ^-^ u) > hair, norm (c ^-^ v) > hair]
        stops = u : sortOn (\c -> dot (c ^-^ u) (v ^-^ u)) touched ++ [v]
    finite2 (V2 x y) = all finiteNumber [x, y]

-- | How many pairs a sheet's chords keep, of how many there are among this
-- many vertices; nothing on a convex sheet, where every pair counts.
keptPairs :: Chords -> Int -> Maybe (Int, Int)
keptPairs EveryChord _ = Nothing
keptPairs (ChordsOnSheet kept) vertices = Just (S.size kept, vertices * (vertices - 1) `div` 2)

-- | Refuse a pose with a point that is not finite, on the flat sheet or in
-- the pose. Every measure would carry a NaN through, and a comparison with
-- NaN is false whichever way it is asked, so a verdict could pass it.
finitePoints :: MaterialMesh -> Either ScreenError ()
finitePoints mesh = case [i | (i, s) <- zip [0 ..] (samples mesh), not (all finiteNumber (coordinates s))] of
  i : _ -> Left (NonFinitePoint i)
  [] -> Right ()
  where
    coordinates s = let V2 u v = sampleMaterial s; V3 x y z = position s in [u, v, x, y, z]

finiteNumber :: Double -> Bool
finiteNumber x = not (isNaN x || isInfinite x)

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
-- material vertices whose chord the sheet keeps ('sheetChords'), the largest
-- @(|x_i - x_j| - (1 + epsilon) |u_i - u_j|) / 2@, where @u@ is the
-- flat-sheet position and @x@ the placed one. Placed points in 3D give the
-- floor in space; points projected onto a page give the floor in that
-- picture, which is a floor too, since projecting never lengthens. The
-- distance is always straight-line length: another measure would not make
-- the floor a bound. The chords must be those of the mesh the points come
-- from, in its vertex order.
noStretchFloor :: (VectorSpace a) => Chords -> Double -> [(V2, a)] -> Maybe FloorPair
noStretchFloor chords epsilon placed = maximumOn floorDistance pairs
  where
    indexed = zip [0 ..] placed
    pairs =
      [ FloorPair ((norm (x ^-^ y) - (1 + epsilon) * norm (u ^-^ v)) / 2) (i, j)
        | (i, (u, x)) : rest <- tails indexed,
          (j, (v, y)) <- rest,
          kept i j
      ]
    kept i j = case chords of
      EveryChord -> True
      ChordsOnSheet on -> S.member (i, j) on

-- | The no-stretch floor in one picture: distances measured after projecting
-- onto the page, so never larger than the floor in 3D.
pictureFloor :: Chords -> Basis -> Double -> MaterialMesh -> Maybe FloorPair
pictureFloor chords basis epsilon mesh = noStretchFloor chords epsilon [(sampleMaterial s, project basis (position s)) | s <- samples mesh]

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
-- axis in the study's coordinates, in sheet units.
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
