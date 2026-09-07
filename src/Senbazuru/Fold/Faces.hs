-- |
-- Module      : Senbazuru.Fold.Faces
-- Description : The faces a file does not record, traced from the creases.
--
-- @faces_vertices@ is optional in FOLD and absent from most real files —
-- @examples\/unit-square.fold@ omits it, and no @.cp@ or @.opx@ can express it
-- at all. Yet the faces are not extra information: a crease pattern is a
-- planar graph, and its faces are exactly the regions the creases cut the
-- sheet into. This module works them out.
--
-- Everything that needs paper rather than lines needs them. Folding has to
-- know which pieces move together; filling has to know what to fill; the layer
-- solver has to know what can be on top of what. So this is also the first
-- authoring primitive: adding a crease invalidates the faces, and whatever
-- adds one has to come back through here.
--
-- == How a face is traced
--
-- Split every edge into two /half-edges/ pointing opposite ways, and give each
-- one the face on its __left__. Then walking that face is following one rule:
--
-- > from the half-edge u→v, turn at v onto the next crease clockwise from v→u
--
-- and repeating until you arrive back where you started. Each half-edge belongs
-- to exactly one face, so tracing every one of them and stopping when a loop
-- closes enumerates every face exactly once.
--
-- The clockwise turn is the line that looks like a typo. Faces come out
-- /counter/clockwise, so the instinct is to turn counterclockwise too — and
-- that traces the same rings backwards. Turning the sharpest possible way
-- against the direction of travel is what keeps the walk hugging one region
-- instead of wandering off round the outside of the sheet. Take the unit square
-- @A(0,0) B(1,0) C(1,1) D(0,1)@ and start along @A→B@: at @B@ the creases are
-- @B→A@ at 180° and @B→C@ at 90°, and the first one clockwise from 180° is 90°,
-- so the walk goes @A→B→C→D→A@ — the interior, anticlockwise, which is what
-- FOLD asks for.
--
-- One of the rings that comes out is the outside of the sheet, traced the other
-- way round. It is told apart by its signed area, which is negative, and
-- dropped. That is the whole of the algorithm.
--
-- __The winding is ours, and can be trusted.__ Every ring returned here is
-- anticlockwise because the sign is what selected it. Elsewhere in senbazuru
-- the file's winding is taken as given and never recomputed — see
-- "Senbazuru.Fold.Query" — but that rule is about not contradicting the
-- @faceOrders@ a file wrote against its own windings. A frame that recorded no
-- faces recorded no orders either, so there is nothing here to contradict.
--
-- == What it refuses, and why loudly
--
-- The walk above is only correct on a graph that really is planar as drawn, and
-- nothing in a FOLD file promises that. Two creases can cross with no vertex
-- where they meet; a vertex can sit in the middle of an edge that was never
-- split at it. Both produce rings — plausible ones, that fill and fold and look
-- like paper — describing regions that are not the regions on the page.
--
-- So each is checked for and named, rather than traced through. The rule this
-- follows is the one the rest of the codebase follows: a picture that is
-- confidently wrong is worse than a refusal, because nothing downstream can
-- tell it from a right one. @examples\/unit-square.fold@ is the case in hand —
-- its three interior creases all pass through the middle of the sheet and none
-- of them stops there — and it is refused, naming a pair.
--
-- Splitting those crossings, rather than complaining about them, is the next
-- primitive along and not this one.
module Senbazuru.Fold.Faces
  ( traceFaces,
    withTracedFaces,
  )
where

import Control.Monad (when)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.List (sortOn, tails)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as M
import Data.Maybe (fromMaybe)
import Data.Set qualified as S
import Senbazuru.Fold.Query (FoldError (..), frameVertices, ringEdges)
import Senbazuru.Fold.Types (EdgeId (..), Frame (..), VertexId (..))
import Senbazuru.Geometry (V2 (..), boxFromPoints, boxSize, norm, (^-^))
import Senbazuru.Geometry.Polygon (distanceToSegment, segmentsCross, signedArea)
import Senbazuru.Geometry.V3 (V3 (..), hasRelief, zSpan)

-- | The regions the creases cut the sheet into, as rings of corners.
--
-- Anticlockwise, one ring per face, in the order the walk met them, and
-- without the outside of the sheet. Refuses anything that would make those
-- rings a description of some other drawing — see the module header.
--
-- A frame with no edges has no faces, which is not an error: it is a sheet
-- nobody has creased.
traceFaces :: Frame -> Either FoldError [[VertexId]]
traceFaces fr = do
  verts <- frameVertices fr
  when (hasRelief verts) (Left (SheetNotFlat (zSpan verts)))
  let points = map flatten verts
      sheet = Sheet {sheetPoints = IM.fromList (zip [0 ..] points), sheetEdges = numbered}
  if null numbered
    then pure []
    else do
      checkDrawing sheet
      pure (facesOf sheet)
  where
    numbered =
      [ (EdgeId i, (a, b))
        | (i, (VertexId a, VertexId b)) <- zip [0 ..] (edgesVertices fr)
      ]

    -- A crease pattern lies in z = 0, which hasRelief has just confirmed, so
    -- dropping z loses nothing rather than projecting anything.
    flatten (V3 x y _) = V2 x y

-- | The frame, with its faces filled in if it did not have any.
--
-- Idempotent, and deliberately does not second-guess a file that /did/ record
-- faces: those came with a winding, and a @faceOrders@ read against it may
-- have come with them. Recomputing there would turn a model inside out, for
-- the reason "Senbazuru.Origami.Layers" gives.
withTracedFaces :: Frame -> Either FoldError Frame
withTracedFaces fr
  | not (null (facesVertices fr)) = Right fr
  | otherwise = do
      traced <- traceFaces fr
      pure fr {facesVertices = traced}

-- | A flat drawing of creases: where the vertices are, and which pairs are
-- joined.
--
-- Vertices are 'Int' here rather than 'VertexId' because almost everything
-- below indexes, counts or searches with them, and the wrapper earns its keep
-- at the edges of the module rather than in the middle of a graph walk.
data Sheet = Sheet
  { sheetPoints :: !(IntMap V2),
    sheetEdges :: ![(EdgeId, (Int, Int))]
  }

-- | Where a vertex is. Every id in 'sheetEdges' came through 'frameVertices',
-- which already refused the ones with no coordinates, so the fallback is
-- unreachable and is a value rather than an error only to keep this total.
pointAt :: Sheet -> Int -> V2
pointAt sheet v = fromMaybe (V2 0 0) (IM.lookup v (sheetPoints sheet))

-- | The two ends of an edge, as points.
endsOf :: Sheet -> (Int, Int) -> (V2, V2)
endsOf sheet (a, b) = (pointAt sheet a, pointAt sheet b)

-- | How far apart two things have to be to be apart, as a distance and as an
-- area.
--
-- Relative to the sheet's own diagonal, a billionth of it, for the reason
-- "Senbazuru.Import.Segments" gives about its own tolerance: the same reader
-- has to cope with a pattern on the unit square and one on the 400-unit square
-- the desktop editors draw on, and an absolute number cannot serve both. The
-- area is that distance times the same diagonal, because
-- 'Senbazuru.Geometry.Polygon.cross2' returns twice a triangle's area and the
-- triangles in question are a hair high and a sheet wide.
tolerances :: Sheet -> (Double, Double)
tolerances sheet = (nearness, nearness * diagonal)
  where
    diagonal = maybe 0 (norm . boxSize) (boxFromPoints (IM.elems (sheetPoints sheet)))
    nearness = 1e-9 * diagonal

-- | Refuse every drawing whose regions are not what tracing would report.
--
-- In order of how cheap they are to test, which is also roughly the order of
-- how likely they are: a malformed edge, then a vertex with nothing to bound,
-- then the sheet coming apart, then the two geometric ones.
checkDrawing :: Sheet -> Either FoldError ()
checkDrawing sheet = do
  mapM_ hasLength (sheetEdges sheet)
  noRepeatedEdge
  mapM_ enoughCreases (IM.toList degrees)
  allOneSheet
  mapM_ noVertexInside (sheetEdges sheet)
  noCrossing (sheetEdges sheet)
  where
    (near, area) = tolerances sheet

    hasLength (eid, ends) = do
      let (a, b) = endsOf sheet ends
      when (norm (b ^-^ a) <= near) (Left (EdgeWithoutLength eid))

    -- Two edges between one pair of vertices sit at the same angle around both
    -- of them, so the sort below cannot say which the walk should turn onto.
    noRepeatedEdge = go M.empty (sheetEdges sheet)
      where
        go _ [] = Right ()
        go seen ((eid, (a, b)) : rest) = case M.lookup key seen of
          Just first -> Left (EdgeRepeated first eid)
          Nothing -> go (M.insert key eid seen) rest
          where
            key = (min a b, max a b)

    degrees =
      IM.fromListWith
        (+)
        ( [(v, 0 :: Int) | v <- IM.keys (sheetPoints sheet)]
            <> [(v, 1) | (_, (a, b)) <- sheetEdges sheet, v <- [a, b]]
        )

    enoughCreases (v, n) =
      when (n < 2) (Left (VertexTooFewCreases (VertexId v) n))

    allOneSheet = case IM.keys (sheetPoints sheet) of
      [] -> Right ()
      (start : _) ->
        let reached = reachableFrom sheet start
         in case [v | v <- IM.keys (sheetPoints sheet), not (IS.member v reached)] of
              (stranded : _) -> Left (SheetInPieces (VertexId start) (VertexId stranded))
              [] -> Right ()

    noVertexInside (eid, ends@(a, b)) =
      case [ v
             | (v, p) <- IM.toList (sheetPoints sheet),
               v /= a,
               v /= b,
               distanceToSegment (endsOf sheet ends) p <= near
           ] of
        (v : _) -> Left (VertexInsideEdge (VertexId v) eid)
        [] -> Right ()

    -- Quadratic in the edges, with a cheap rejection first. The crane is 129
    -- edges, so this is 8256 pairs of which a handful survive the boxes; a
    -- sweep line is the answer if a tessellation ever makes it matter, and is
    -- a great deal of machinery to write before it does.
    noCrossing es =
      sequence_
        [ Left (EdgesCross e f)
          | (e, ep) : rest <- tails es,
            (f, fp) <- rest,
            not (share ep fp),
            boxesOverlap ep fp,
            segmentsCross area (endsOf sheet ep) (endsOf sheet fp)
        ]

    share (a, b) (c, d) = a == c || a == d || b == c || b == d

    boxesOverlap ep fp =
      let (V2 ax ay, V2 bx by) = endsOf sheet ep
          (V2 cx cy, V2 dx dy) = endsOf sheet fp
       in min ax bx - near <= max cx dx
            && min cx dx - near <= max ax bx
            && min ay by - near <= max cy dy
            && min cy dy - near <= max ay by

-- | Every vertex a chain of creases joins to this one.
reachableFrom :: Sheet -> Int -> IS.IntSet
reachableFrom sheet start = go (IS.singleton start) [start]
  where
    neighbours =
      IM.fromListWith
        (<>)
        (concat [[(a, [b]), (b, [a])] | (_, (a, b)) <- sheetEdges sheet])

    go seen [] = seen
    go seen (v : queue) =
      let next = [w | w <- IM.findWithDefault [] v neighbours, not (IS.member w seen)]
       in go (foldr IS.insert seen next) (next <> queue)

-- | Trace every face, and drop the one that is the outside of the sheet.
--
-- The outside is the ring whose signed area is negative — it runs clockwise,
-- because it is the same boundary the sheet's own outer face runs the other way
-- along. A drawing in one connected piece has exactly one such ring, which is
-- why 'checkDrawing' insists on one piece before this is reached.
facesOf :: Sheet -> [[VertexId]]
facesOf sheet =
  [ map VertexId ring
    | ring <- rings,
      signedArea (map (pointAt sheet) ring) > 0
  ]
  where
    rings = walk S.empty (concat [[(a, b), (b, a)] | (_, (a, b)) <- sheetEdges sheet])

    next = nextAround sheet

    walk _ [] = []
    walk done (h : rest)
      | S.member h done = walk done rest
      | otherwise =
          let ring = follow h h []
           in ring : walk (foldr S.insert done (ringEdges ring)) rest

    -- Follow `next` from a half-edge until it comes back to the one it began
    -- at, collecting the vertex each step leaves. Terminates because every
    -- half-edge has exactly one successor and exactly one predecessor, so the
    -- walk is a permutation and its orbits are cycles.
    follow start h acc =
      let h' = M.findWithDefault start h next
       in if h' == start
            then reverse (fst h : acc)
            else follow start h' (fst h : acc)

-- | For each half-edge, the half-edge a face traversal turns onto next.
--
-- From @u→v@, the answer is @v→w@ where @v→w@ is the first crease clockwise
-- from @v→u@ around @v@. With the creases at each vertex sorted anticlockwise
-- by angle, \"the first one clockwise from\" is simply the one before it in
-- that list, wrapping round.
nextAround :: Sheet -> Map (Int, Int) (Int, Int)
nextAround sheet =
  M.fromList
    [ ((neighbour, v), (v, previous))
      | (v, ordered) <- IM.toList byVertex,
        let count = length ordered,
        (i, neighbour) <- zip [0 ..] ordered,
        let previous = ordered !! ((i - 1 + count) `mod` count)
    ]
  where
    byVertex =
      IM.map
        (map snd . sortOn fst)
        ( IM.fromListWith
            (<>)
            ( concat
                [ [(a, [(angle a b, b)]), (b, [(angle b a, a)])]
                  | (_, (a, b)) <- sheetEdges sheet
                ]
            )
        )

    angle from to =
      let V2 dx dy = pointAt sheet to ^-^ pointAt sheet from
       in atan2 dy dx
