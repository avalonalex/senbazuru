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
-- Each end has to __meet something the drawing already has__: an edge, which it
-- cuts, or a corner, which it joins. An end that meets neither leaves a crease
-- stopping there and dividing nothing, and there is no face to trace round it.
--
-- Note what that is not. It is not \"on the paper\" — senbazuru has no
-- \"is this point on the sheet\" question, and building one would mean deciding
-- what a sheet is before deciding what a move is. It is a question about the
-- drawing, and the drawing is right here.
--
-- The distinction is not academic, because the two answers differ. A crease
-- from the middle of a face to the middle of a face has both ends on the paper
-- and still divides nothing; a crease to a point off the paper divides nothing
-- either. Both are refused, by one test, with one true sentence — where saying
-- \"that end is off the paper\" would be wrong for the first, and where a
-- previous version said neither and reported a vertex the caller never chose.
--
-- What it does /not/ refuse is an end that lands part-way along a crease that
-- is already there. That end does meet something, the drawing is sound, and
-- whether the result can be folded is
-- <https://github.com/avalonalex/senbazuru/issues/76 somebody else's question>.
module Senbazuru.Fold.Creasing
  ( creaseAlong,
  )
where

import Control.Monad (when)
import Data.IntMap.Strict qualified as IM
import Senbazuru.Fold.Crossings (withPlanarFaces)
import Senbazuru.Fold.Faces (Sheet (..), coordsFor, endsOf, sheetOf, tolerance)
import Senbazuru.Fold.Query (CreaseEnd (..), FoldError (..))
import Senbazuru.Fold.Types (Assignment (..), Frame (..), VertexId (..))
import Senbazuru.Geometry (V2 (..), norm, (^-^))
import Senbazuru.Geometry.Polygon (distanceToSegment)

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
  arraysLineUp
  if norm (to ^-^ from) <= tolerance sheet
    then Left CreaseWithoutLength
    else do
      meetsSomething sheet FromEnd from
      meetsSomething sheet ToEnd to
      withPlanarFaces (creased (endpointsOf sheet (tolerance sheet)))
  where
    edges = length (edgesVertices fr)

    -- Refused before anything is appended, so that appending lands on the end
    -- of an array that really is edge-indexed. A file whose arrays do not line
    -- up is one "Senbazuru.Fold.Query" refuses wherever they are read; without
    -- this it would be silently transformed into a still-mismatched file with
    -- the new assignment written onto somebody else's crease.
    arraysLineUp = do
      matches "edges_assignment" (length (edgesAssignment fr))
      matches "edges_foldAngle" (length (edgesFoldAngle fr))

    matches what n =
      when (n /= 0 && n /= edges) $
        Left (ArrayLengthMismatch "edges_vertices" edges what n)

    -- Each end has to land on something the drawing already has, or the crease
    -- stops there and divides nothing -- and the face tracing then refuses it a
    -- step later, naming a vertex the caller never chose and a consequence
    -- rather than a cause.
    --
    -- Asked of the /edges/ and not of the sheet. An end off the paper, an end
    -- in the middle of a face, and an end nowhere near the model all fail this
    -- one test and all fail it for the same reason, which is exactly as much as
    -- can be said without deciding what a sheet is. Telling them apart would
    -- need that; pointing at the end that has to move does not.
    --
    -- An end on an isolated vertex, if a frame has one, meets nothing by this
    -- test, and that is right: a point with no edges at it divides no paper
    -- either.
    meetsSomething sheet which p
      | any (onIt . snd) (sheetEdges sheet) = Right ()
      | otherwise = Left (CreaseEndMeetsNothing which p)
      where
        onIt e = distanceToSegment (endsOf sheet e) p <= tolerance sheet

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
    --
    -- The two are resolved in order, because the second's id depends on
    -- whether the first added a vertex or joined one. Numbering them 0 and 1
    -- up front is wrong exactly when one end lands on a corner and the other
    -- does not, which is the commonest crease there is.
    endpointsOf sheet near = ((a, addedA), (b, addedB))
      where
        next = length (verticesCoords fr)
        (a, addedA) = case existingAt sheet near from of
          Just v -> (v, [])
          Nothing -> (next, [coordsFor fr from])
        (b, addedB) = case existingAt sheet near to of
          Just v -> (v, [])
          Nothing -> (next + length addedA, [coordsFor fr to])

    creased ((a, addedA), (b, addedB)) =
      fr
        { verticesCoords = verticesCoords fr <> addedA <> addedB,
          edgesVertices = edgesVertices fr <> [(VertexId a, VertexId b)],
          edgesAssignment = assignments,
          edgesFoldAngle = angles,
          -- The line cuts at least one face in two, so every face the file
          -- recorded is now wrong -- and so is every faceOrders entry, which
          -- names those faces and is read against their winding. Dropping the
          -- faces is also what lets "Senbazuru.Fold.Crossings" do its half of
          -- the work: it leaves a frame that records faces alone, on the
          -- grounds that such a frame has already answered the question
          -- cutting asks. This one has not, any more.
          facesVertices = [],
          faceOrders = [],
          frameExtras = mempty
        }

    -- The assignment is the one thing the caller actually asked for, so it is
    -- written whether or not the file kept an array to write it in. An absent
    -- @edges_assignment@ means "nothing is known about any crease", which is
    -- what @U@ means -- so the array it becomes says exactly what the absence
    -- said, plus the one crease somebody has now decided about.
    assignments
      | null (edgesAssignment fr) = replicate edges Unassigned <> [assignment]
      | otherwise = edgesAssignment fr <> [assignment]

    -- The angle follows the assignment rather than being nought. A valley with
    -- an angle of nought is not a valley: FOLD puts a valley's angle in
    -- (0, 180], and "Senbazuru.Origami.Folding" reads exactly this off the
    -- assignment when the array is absent. Writing nought here made the same
    -- command mean two different things depending on whether the file happened
    -- to record angles at all.
    --
    -- Absent stays absent, because there the file made no claim about any
    -- crease's angle and folding will derive them all the same way.
    angles
      | null (edgesFoldAngle fr) = []
      | otherwise = edgesFoldAngle fr <> [flatAngleFor assignment]

-- | The angle a crease of this kind takes when the paper is folded flat.
--
-- Mountain and valley are the two that fold; everything else is a line on the
-- paper that the paper is not folded along.
flatAngleFor :: Assignment -> Double
flatAngleFor = \case
  Mountain -> -180
  Valley -> 180
  _ -> 0

-- | The id of a corner the paper already has at this point, if there is one.
existingAt :: Sheet -> Double -> V2 -> Maybe Int
existingAt sheet near p =
  case [v | (v, q) <- IM.toList (sheetPoints sheet), norm (q ^-^ p) <= near] of
    (v : _) -> Just v
    [] -> Nothing
