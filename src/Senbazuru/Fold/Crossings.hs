-- |
-- Module      : Senbazuru.Fold.Crossings
-- Description : Cutting creases at the points where they meet.
--
-- "Senbazuru.Fold.Faces" refuses a drawing whose creases cross with no vertex
-- where they meet, and it is right to: the regions between crossing creases
-- are not the faces of anything. But the file is not really wrong — it has
-- simply left out a vertex that the drawing already implies — and putting it
-- in is mechanical. That is what this does.
--
-- Two shapes of the same problem, and the errors 'Senbazuru.Fold.Faces' raises
-- name them exactly:
--
-- * @EdgesCross@ — two creases pass through each other. The crossing point has
--   to be worked out, added as a vertex, and both creases cut at it.
-- * @VertexInsideEdge@ — a vertex is already there, sitting on a crease that
--   was never cut at it. Only the cutting is missing, and it is exact rather
--   than computed.
--
-- == Which files need it, measured
--
-- Two, out of the thirty in the reference corpora and this repository, and
-- they need it for the two different reasons above:
--
-- * @examples\/unit-square.fold@ — hand-written, and the only file anywhere
--   here with two creases genuinely /passing through/ each other. Eight
--   vertices become nine and eleven creases become fourteen.
-- * ORIPA's @turkey2015.opx@ — a real design, and the surprise. Not one new
--   vertex: all 231 were already there. But 71 of its creases end /on/ another
--   crease that ORIPA never cut, so 429 creases become 500. The easy assumption
--   is that an editor splits as you draw and only hand-written files are
--   untidy; that file is the counterexample, and it was unfoldable here until
--   this module existed.
--
-- The larger reason is still /authoring/, though. A new crease drawn across a
-- pattern crosses whatever is already there, and every crease it cuts has to
-- be cut back before the faces can be re-traced. This is a primitive the fold
-- vocabulary is built on; fixing two files is what it does on the way past.
--
-- == The case that decides the design
--
-- Three creases through one point — exactly what @unit-square.fold@ has at the
-- middle of the sheet. Taken pair by pair that is three crossings, and
-- computing each one separately gives three points a rounding error apart. Add
-- all three as vertices and the sheet has a knot in it: three vertices where
-- there should be one, joined by two creases far shorter than anything a
-- person drew.
--
-- So the crossing points are all found first and then /merged/ — with each
-- other and with the vertices already there — before anything is cut. The
-- tolerance is "Senbazuru.Fold.Faces"'s, which is the same question asked
-- about the same sheet, and the merging is a plain scan rather than the grid
-- "Senbazuru.Import.Segments" uses: reading a file makes every endpoint a
-- candidate, where here there is one candidate per crossing, and a crease
-- pattern that crosses itself hundreds of times is not a thing anyone has.
--
-- == What it leaves alone, and what it destroys
--
-- __A frame that records its own faces is never cut.__ It has already answered
-- the question cutting asks. A crease stopping part-way along another is no
-- defect there — the face on that side simply has a corner in the middle of
-- one of its sides, which is legal and which real patterns are full of — so
-- cutting would throw away an answer the file gave in favour of one worked out
-- here, re-wound to this project\'s convention. @faceOrders@ are read against
-- the winding of the faces a file recorded, so replacing those faces
-- underneath them turns a model inside out.
--
-- __A frame with nothing to cut comes back the frame it arrived as__, keys and
-- all. More than an optimisation: it is what lets this sit in front of every
-- fold and every export without stripping keys off files that never needed it,
-- and without adding refusals to paths that never asked a question it answers.
--
-- __When it does cut, @faces_vertices@ and @frameExtras@ go.__ Note the reason,
-- because the obvious one is wrong: the vertices are /not/ renumbered — every
-- one the file had keeps the id it had, and crossings are appended after them.
-- What makes a stale @faces_vertices@ untrue is that its rings have gained
-- corners in the middle of their sides. Anything in @frameExtras@ indexing a
-- face or an edge is in the same position, and the decoder cannot judge a key
-- it does not understand, so whatever /changes/ the document has to:
-- __preserve at the boundary, discard at the transform__.
--
-- One thing it does not catch: two creases drawn exactly on top of each other,
-- end for end. Neither cuts the other, so nothing is rebuilt and the frame
-- passes through — and "Senbazuru.Fold.Faces" refuses it as a repeated edge,
-- naming the two creases the file really has. Only a /partial/ overlap is
-- reported from here, because that is the case where the pieces would
-- otherwise come out doubled.
module Senbazuru.Fold.Crossings
  ( splitCrossings,
    withPlanarFaces,
  )
where

import Control.Monad (when)
import Data.IntMap.Strict qualified as IM
import Data.List (foldl', partition, sortOn, tails)
import Data.Maybe (mapMaybe)
import Senbazuru.Fold.Faces (Sheet (..), coordsFor, endsOf, pointAt, sheetOf, tolerance, withTracedFaces)
import Senbazuru.Fold.Query (FoldError (..))
import Senbazuru.Fold.Types (EdgeId (..), Frame (..), VertexId (..))
import Senbazuru.Geometry (V2 (..), dot, norm, (*^), (^+^), (^-^))
import Senbazuru.Geometry.Polygon (cross2, distanceToSegment, segmentsCross)

-- | Cut every crease at every point another crease or vertex meets it.
--
-- The frame comes back unchanged when there was nothing to cut. When there
-- was, its vertices have gained the crossing points, its creases have been
-- replaced by the pieces they were cut into — each piece keeping its parent's
-- assignment and fold angle — and its faces and unrecognised keys have been
-- dropped, for the reason in the module header.
--
-- Idempotent: splitting a split drawing finds nothing left to cut.
splitCrossings :: Frame -> Either FoldError Frame
splitCrossings fr
  -- A frame that records its own faces is left exactly as it is. Cutting
  -- exists to answer "where do these creases divide the paper?", and such a
  -- frame has already answered it: a crease stopping part-way along another is
  -- no defect there, because the face on that side simply has a corner in the
  -- middle of one of its sides, which is legal and which real patterns are
  -- full of. Cutting anyway would throw away an answer the file gave for one
  -- we worked out, re-wound to our own convention and possibly failing on a
  -- drawing its faces described perfectly well.
  --
  -- The same rule "Senbazuru.Fold.Faces" follows, for the same reason, and it
  -- is what keeps @faceOrders@ meaningful: those are read against the winding
  -- of the faces the file recorded, so a frame whose faces are replaced
  -- underneath them is a frame turned inside out.
  | not (null (facesVertices fr)) = Right fr
  | otherwise = do
      sheet <- sheetOf fr
      if null (sheetEdges sheet)
        then pure fr
        else do
          let points = IM.elems (sheetPoints sheet) <> mergedCrossings sheet
              indexed = IM.fromList (zip [0 ..] points)
              cuts = cutsAlong indexed sheet
          if all (null . snd) cuts
            then pure fr
            else do
              arraysLineUp fr
              rebuilt fr points cuts

-- | Cut the creases and then work out the faces, which is the pair every
-- caller wants and neither half of which is any use alone.
--
-- One function rather than two calls, because a policy spelled out at each
-- backend is a policy the next backend forgets — which is exactly what
-- happened to @--layer-budget@, and is written down in CLAUDE.md so that it
-- does not happen twice.
withPlanarFaces :: Frame -> Either FoldError Frame
withPlanarFaces fr = withTracedFaces =<< splitCrossings fr

-- | Refuse an assignment or angle array that does not line up with the creases.
--
-- Checked immediately before the rebuild and not a step earlier. It exists
-- only to keep 'rebuilt' total — each piece looks its parent's assignment up
-- by edge id — so a frame with nothing to cut must not be refused by it. That
-- frame was acceptable to @export --thickness 0@, which consults no
-- assignments at all, and adding a refusal it has no use for on the way past
-- is how a transform that was supposed to be invisible stops being invisible.
-- "Senbazuru.Fold.Query" still refuses the same file wherever the arrays are
-- actually read.
arraysLineUp :: Frame -> Either FoldError ()
arraysLineUp fr = do
  matches "edges_assignment" (length (edgesAssignment fr))
  matches "edges_foldAngle" (length (edgesFoldAngle fr))
  where
    edges = length (edgesVertices fr)
    matches what n =
      when (n /= 0 && n /= edges) $
        Left (ArrayLengthMismatch "edges_vertices" edges what n)

-- | Where every pair of creases crosses, with points closer together than the
-- tolerance taken to be one point.
--
-- The merging is what stops three creases through one place becoming three
-- vertices a rounding error apart. A crossing already within a tolerance of a
-- vertex the file has is dropped rather than added: the file put it there, and
-- the cut below will use it.
mergedCrossings :: Sheet -> [V2]
mergedCrossings sheet =
  [ centre group
    | group <- foldl absorb [] found,
      not (any (near `apart` centre group) existing)
  ]
  where
    near = tolerance sheet
    existing = IM.elems (sheetPoints sheet)

    -- The box rejects most pairs before any of the crossing geometry runs, for
    -- the reason "Senbazuru.Fold.Faces" gives about the identical test: this
    -- is every crease against every other, on the way into every fold.
    found =
      mapMaybe
        (uncurry (crossingOf sheet near))
        [ (ep, fp)
          | (_, ep) : rest <- tails (sheetEdges sheet),
            (_, fp) <- rest,
            boxesMeet sheet near ep fp
        ]

    -- Grouping has to be transitive, and \"is this within a tolerance of one I
    -- already kept\" is not. Three crossings in a row, each within a tolerance
    -- of the next but the ends further apart than that, would keep the first
    -- and the last: two vertices at one place on the paper, joined by a crease
    -- a hair long that nothing downstream is short enough to refuse. So a new
    -- point absorbs every group it is near to, rather than being dropped
    -- against the first one it meets.
    absorb groups p = untouched <> [p : concat touching]
      where
        (touching, untouched) = partition (any (near `apart` p)) groups

    centre group = (1 / fromIntegral (length group)) *^ foldl' (^+^) (V2 0 0) group

-- | Are the two points within a tolerance of each other?
apart :: Double -> V2 -> V2 -> Bool
apart near p q = norm (q ^-^ p) <= near

-- | Do the two creases\' bounding boxes come within a tolerance of touching?
--
-- The cheap rejection in front of every pairwise geometric test here, and the
-- same one "Senbazuru.Fold.Faces" documents as load-bearing for the identical
-- questions.
boxesMeet :: Sheet -> Double -> (Int, Int) -> (Int, Int) -> Bool
boxesMeet sheet near ep fp =
  overlaps (ax, bx) (cx, dx) && overlaps (ay, by) (cy, dy)
  where
    (V2 ax ay, V2 bx by) = endsOf sheet ep
    (V2 cx cy, V2 dx dy) = endsOf sheet fp
    overlaps (p, q) (r, s) = min p q - near <= max r s && min r s - near <= max p q

-- | Where two creases cross, if they do.
--
-- The crossing is asked for by 'segmentsCross' first and only then computed,
-- so the one place a division by a near-zero cross product could happen is
-- behind a test that the two are not nearly parallel.
crossingOf :: Sheet -> Double -> (Int, Int) -> (Int, Int) -> Maybe V2
crossingOf sheet near ep fp
  | shareEnd = Nothing
  | not (segmentsCross near (a, b) (c, d)) = Nothing
  | otherwise = Just (a ^+^ (along *^ ab))
  where
    (a, b) = endsOf sheet ep
    (c, d) = endsOf sheet fp
    shareEnd = case (ep, fp) of
      ((p, q), (r, s)) -> p == r || p == s || q == r || q == s
    ab = b ^-^ a
    cd = d ^-^ c
    -- The standard parametric solve: a + t(b-a) meets c + u(d-c) where the
    -- cross products say so. segmentsCross has already established that the
    -- denominator is not a rounding error.
    along = cross2 (c ^-^ a) cd / cross2 ab cd

-- | For each crease, the points that fall strictly inside it, in the order
-- they are met walking from its first end to its second.
--
-- \"Strictly\" is what keeps a crease's own ends out of its cut list, and it
-- is a distance rather than an identity: a crossing point that landed on an
-- end was already merged into that vertex, but a /different/ vertex sitting a
-- hair from the end would otherwise be cut in as a piece too short to be a
-- crease.
--
-- The order is by how far along the crease each point projects, which is what
-- makes the pieces come out end to end rather than shuffled. Sorting by
-- distance from the first end would do as well and only because the points are
-- known to be on the segment; projecting says what is meant.
cutsAlong :: IM.IntMap V2 -> Sheet -> [((EdgeId, (Int, Int)), [Int])]
cutsAlong points sheet =
  [ (edge, map snd (sortOn fst (inside ends)))
    | edge@(_, ends) <- sheetEdges sheet
  ]
  where
    near = tolerance sheet

    listed = IM.toList points

    inside (u, v) =
      [ (dot (p ^-^ from) direction, i)
        | (i, p) <- listed,
          i /= u,
          i /= v,
          withinBox p,
          distanceToSegment (from, to) p <= near,
          not (apart near p from),
          not (apart near p to)
      ]
      where
        (from@(V2 fx fy), to@(V2 tx ty)) = (pointAt sheet u, pointAt sheet v)
        direction = to ^-^ from
        -- Read once per crease rather than once per crease and vertex, and
        -- rejected on the box before any distance is computed. This is the
        -- only O(creases x vertices) loop in the module.
        withinBox (V2 x y) =
          x >= min fx tx - near
            && x <= max fx tx + near
            && y >= min fy ty - near
            && y <= max fy ty + near

-- | The frame with its creases cut into the pieces the cuts make.
--
-- Every piece keeps its parent's assignment and fold angle, which is the only
-- answer that can be right: cutting a valley in two does not make either half
-- something other than a valley.
rebuilt :: Frame -> [V2] -> [((EdgeId, (Int, Int)), [Int])] -> Either FoldError Frame
rebuilt fr points cuts = do
  noDoubledPiece
  pure
    fr
      { verticesCoords = kept <> map added (drop (length kept) points),
        edgesVertices = [(VertexId a, VertexId b) | (a, b) <- concatMap snd chains],
        edgesAssignment = inherited (edgesAssignment fr),
        edgesFoldAngle = inherited (edgesFoldAngle fr),
        facesVertices = [],
        frameExtras = mempty
      }
  where
    -- Two creases lying along one line with a stretch in common do not cross,
    -- so nothing above cuts them at a point -- but cutting them where each
    -- other\'s ends fall leaves two pieces joining the same pair of vertices,
    -- one from each. Caught by looking at what came out, which needs no
    -- tolerance of its own and can name the two creases the file really has
    -- rather than two pieces it has never seen.
    noDoubledPiece =
      case [ (e, f)
             | ((e, ps), rest) <- zip chains (drop 1 (tails chains)),
               (f, qs) <- rest,
               any ((`elem` map unordered qs) . unordered) ps
           ] of
        ((e, f) : _) -> Left (EdgesOverlap e f)
        [] -> Right ()

    unordered (a, b) = (min a b, max a b)

    -- Every vertex the file had keeps the row the file wrote, untouched.
    -- Rebuilding them from the flattened points would drop the z column that
    -- reading the sheet threw away -- and a crease pattern is flat, not
    -- necessarily flat at z = 0, so a sheet recorded at a constant height
    -- would quietly move to the origin.
    kept = verticesCoords fr

    added = coordsFor fr

    chains =
      [ (eid, zip chain (drop 1 chain))
        | ((eid, (u, v)), between) <- cuts,
          let chain = (u : between) <> [v]
      ]

    -- One entry per piece, taken from the crease the piece came out of. An
    -- absent array stays absent: an assignment invented for a crease the file
    -- said nothing about would be a claim it did not make.
    inherited [] = []
    inherited xs =
      concat
        [ replicate (length ps) x
          | (EdgeId i, ps) <- chains,
            x <- take 1 (drop i xs)
        ]
