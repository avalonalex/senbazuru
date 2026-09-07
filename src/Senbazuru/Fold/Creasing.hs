-- |
-- Module      : Senbazuru.Fold.Creasing
-- Description : Drawing a new crease on a sheet of paper.
--
-- The first operation senbazuru has that /changes/ a crease pattern rather
-- than reading one. Everything before it took a file and produced a picture, a
-- folded form or a refusal; this takes a file and produces another file, which
-- is what an authoring tool is.
--
-- It is deliberately one operation and not a vocabulary. The
-- <https://github.com/avalonalex/senbazuru/issues/60 vocabulary> is a list of
-- named moves — fold along a line, turn the model over, reverse fold — and the
-- shape of that list is worth settling against a real model rather than
-- guessing at. Creasing is the move every other one is built from, so it is
-- the one worth having first and alone.
--
-- == What drawing a crease actually involves
--
-- Almost none of it is the crease. Adding the segment is two vertices and an
-- edge; what makes this more than that is everything the new line invalidates:
--
-- 1. The new crease __crosses__ whatever is already drawn there, and a crossing
--    with no vertex is not a planar graph. "Senbazuru.Fold.Crossings" cuts
--    both the new crease and everything it meets.
-- 2. The __faces are wrong__ the moment the line is drawn — it cuts at least
--    one of them in two. They are dropped and re-derived by
--    "Senbazuru.Fold.Faces".
-- 3. Anything in @frameExtras@ that indexes a face or an edge is wrong for the
--    same reason, and the decoder cannot judge a key it does not understand,
--    so the transform has to: __preserve at the boundary, discard at the
--    transform__.
--
-- All three are somebody else's code, which is the point. The crease is added
-- and the frame is handed straight to
-- 'Senbazuru.Fold.Crossings.withPlanarFaces', so a pattern that has been
-- creased is validated by exactly what validates a pattern that was read.
--
-- == Where the crease has to be
--
-- On the paper. That is not checked directly — senbazuru has no
-- \"is this point on the sheet\" question, and building one would mean deciding
-- what a sheet is before deciding what a move is — but it does not need to be.
-- A crease drawn off the edge of the paper ends at a vertex with one crease at
-- it, and re-deriving the faces refuses exactly that, naming the vertex. A
-- crease drawn entirely outside leaves the sheet in two pieces, which is
-- refused too.
--
-- So the check is real and the message is about the drawing rather than about
-- the intent. Saying \"that crease runs off the paper\" would be nicer and
-- would mean answering a harder question than the one being asked.
module Senbazuru.Fold.Creasing
  ( creaseAlong,
  )
where

import Data.IntMap.Strict qualified as IM
import Senbazuru.Fold.Crossings (withPlanarFaces)
import Senbazuru.Fold.Faces (Sheet (..), sheetOf, tolerance)
import Senbazuru.Fold.Query (FoldError (..))
import Senbazuru.Fold.Types (Assignment, EdgeId (..), Frame (..), VertexId (..))
import Senbazuru.Geometry (V2 (..), norm, (^-^))

-- | Draw a crease between two points, and put the pattern back in order.
--
-- The endpoints join whatever is already at them: a corner they land on, or a
-- crease they land in the middle of, which gets cut there. Anything the new
-- crease crosses on its way is cut too, and the faces are worked out again
-- from the creases that result.
--
-- Refuses a folded form — creasing one means creasing through its layers,
-- which is a different and much harder move — and refuses a crease with no
-- length, which names no line to fold about.
creaseAlong :: V2 -> V2 -> Assignment -> Frame -> Either FoldError Frame
creaseAlong from to assignment fr = do
  -- Read the sheet only to refuse the frames that are not one to draw on: a
  -- folded form, and an edge naming a vertex that is not there. Its tolerance
  -- is the sheet's own, so a crease counts as having length by the same
  -- measure everything else on this paper is judged by.
  sheet <- sheetOf fr
  let near = tolerance sheet
  if norm (to ^-^ from) <= near
    then Left (EdgeWithoutLength (EdgeId (length (edgesVertices fr))))
    else withPlanarFaces (creased (endpointsOf sheet near))
  where
    -- An end that lands on a corner the paper already has /is/ that corner.
    -- Appending a second vertex at the same place instead would leave the
    -- crease attached to a vertex of its own, joined to nothing, and the face
    -- tracing would refuse it -- correctly, since a crease hanging off a point
    -- that happens to coincide with a corner really does divide nothing.
    --
    -- Only corners, and only these two points, so a plain scan is the whole of
    -- it. An end that lands in the /middle/ of a crease needs no special case:
    -- it becomes a vertex, and cutting that crease at it is exactly what
    -- "Senbazuru.Fold.Crossings" is for.
    -- The two ends are resolved in order, because the second's id depends on
    -- whether the first added a vertex or joined one. Numbering them 0 and 1
    -- up front is wrong exactly when one end lands on a corner and the other
    -- does not, which is the commonest crease there is.
    endpointsOf sheet near = ((a, addedA), (b, addedB))
      where
        next = length (verticesCoords fr)
        (a, addedA) = case existingAt sheet near from of
          Just v -> (v, [])
          Nothing -> (next, [coordsOf from])
        (b, addedB) = case existingAt sheet near to of
          Just v -> (v, [])
          Nothing -> (next + length addedA, [coordsOf to])

    creased ((a, addedA), (b, addedB)) =
      fr
        { verticesCoords = verticesCoords fr <> addedA <> addedB,
          edgesVertices = edgesVertices fr <> [(VertexId a, VertexId b)],
          edgesAssignment = appended (edgesAssignment fr) assignment,
          edgesFoldAngle = appended (edgesFoldAngle fr) 0,
          -- The line cuts at least one face in two, so every face the file
          -- recorded is now wrong. Dropping them is also what lets
          -- "Senbazuru.Fold.Crossings" do its half of the work: it leaves a
          -- frame that records faces alone, on the grounds that such a frame
          -- has already answered the question cutting asks. This one has not,
          -- any more.
          facesVertices = [],
          frameExtras = mempty
        }

    -- The endpoints are written with as many components as the file uses. A
    -- crease pattern is flat but not necessarily at z = 0, and a point drawn
    -- on the sheet is at the sheet's own height.
    coordsOf (V2 x y) = case verticesCoords fr of
      ((_ : _ : z : _) : _) -> [x, y, z]
      _ -> [x, y]

    -- An array the file did not have stays absent. An angle invented for a
    -- crease nobody asked about would be a claim the file never made -- and
    -- leaving edges_foldAngle absent is what lets foldFrame read +/-180 off
    -- the assignment, so "crease it" and "crease it and fold it" stay one
    -- decision made by the file rather than two made here.
    appended [] _ = []
    appended xs x = xs <> [x]

-- | The id of a corner the paper already has at this point, if there is one.
existingAt :: Sheet -> Double -> V2 -> Maybe Int
existingAt sheet near p =
  case [v | (v, q) <- IM.toList (sheetPoints sheet), norm (q ^-^ p) <= near] of
    (v : _) -> Just v
    [] -> Nothing
