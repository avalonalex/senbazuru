-- |
-- Module      : Senbazuru.Fold.Query
-- Description : Turning a loosely-typed 'Frame' into geometry a renderer can trust.
--
-- "Senbazuru.Fold.Types" mirrors the file format, which is permissive: arrays
-- are optional, coordinates may be 2D or 3D, and nothing guarantees that
-- @edges_vertices@ only mentions vertices that exist. This module is the gate
-- between that world and the rest of the program.
--
-- The pattern is sometimes called \"parse, don't validate\": rather than
-- scattering @if index < length vs@ checks through the renderer, we do the
-- checks once, here, and hand back a type that no longer /can/ be wrong. A
-- 'Crease' holds two actual 'V2' points, not two integers that we hope are
-- valid indices, so no code downstream needs an error path for a dangling
-- reference.
module Senbazuru.Fold.Query
  ( -- * Errors
    FoldError (..),
    renderFoldError,

    -- * Refined views of a frame
    Crease (..),
    frameVertices,
    frameCreases,
  )
where

import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Fold.Types
  ( Assignment (..),
    EdgeId (..),
    Frame (..),
    VertexId (..),
  )
import Senbazuru.Geometry (V2 (..))

-- | Everything that can be structurally wrong with an otherwise well-formed
-- FOLD frame.
--
-- Each constructor carries enough context to point at the offending element,
-- because \"invalid FOLD file\" is a useless thing to tell someone holding a
-- 4000-line crease pattern.
data FoldError
  = -- | The frame has no vertices at all, so there is nothing to draw and no
    -- region for the page to show.
    NoVertices
  | -- | A vertex has fewer than two coordinates. Carries the vertex and the
    -- number of components actually present.
    VertexCoordTooShort VertexId Int
  | -- | An edge refers to a vertex id that has no entry in @vertices_coords@.
    -- Carries the edge, the bad vertex id, and how many vertices exist.
    VertexIndexOutOfRange EdgeId VertexId Int
  | -- | Two parallel arrays that must agree in length do not. Carries the name
    -- and length of each.
    ArrayLengthMismatch Text Int Text Int
  deriving stock (Eq, Show)

-- | A human-readable rendering of a 'FoldError', suitable for a CLI message.
renderFoldError :: FoldError -> Text
renderFoldError = \case
  NoVertices ->
    "frame has no vertices_coords, so there is nothing to draw"
  VertexCoordTooShort (VertexId v) n ->
    "vertex "
      <> tshow v
      <> " has "
      <> tshow n
      <> " coordinate(s); at least 2 (x, y) are required"
  VertexIndexOutOfRange (EdgeId e) (VertexId v) n ->
    "edge "
      <> tshow e
      <> " refers to vertex "
      <> tshow v
      <> ", but vertices_coords only has "
      <> tshow n
      <> " entries (valid ids are 0.."
      <> tshow (n - 1)
      <> ")"
  ArrayLengthMismatch a na b nb ->
    a
      <> " has "
      <> tshow na
      <> " entries but "
      <> b
      <> " has "
      <> tshow nb
      <> "; FOLD requires parallel arrays to line up"
  where
    tshow :: (Show a) => a -> Text
    tshow = T.pack . show

-- | One edge of the crease pattern, resolved to actual endpoints.
data Crease = Crease
  { creaseId :: !EdgeId,
    creaseStart :: !V2,
    creaseEnd :: !V2,
    creaseAssignment :: !Assignment
  }
  deriving stock (Eq, Show)

-- | Vertex positions, projected onto the xy plane.
--
-- FOLD coordinates may have three components. This function keeps @x@ and @y@
-- and discards @z@, which is exactly right for a @creasePattern@ frame (where
-- @z@ is zero anyway) and is a plain orthographic top-down view for a
-- @foldedForm@ frame. A top-down view of a folded model is /not/ a correct
-- picture of it — that needs a real camera and layer ordering — but it is a
-- well-defined projection, and it is honest about what it does rather than
-- silently refusing 3D input.
frameVertices :: Frame -> Either FoldError [V2]
frameVertices fr = traverse toV2 (zip (map VertexId [0 ..]) (verticesCoords fr))
  where
    toV2 (vid, coords) = case coords of
      (x : y : _) -> Right (V2 x y)
      shorter -> Left (VertexCoordTooShort vid (length shorter))

-- | Every edge of the frame as a line segment with its fold assignment.
--
-- Border edges are included: the outline of the sheet is part of the drawing,
-- and deciding what to do with each assignment is the renderer's job, not this
-- module's.
frameCreases :: Frame -> Either FoldError [Crease]
frameCreases fr = do
  verts <- frameVertices fr
  assignments <- resolveAssignments
  let -- An IntMap gives O(log n) lookup by vertex id. Indexing the list with
      -- (!!) instead would make the whole function quadratic, which starts to
      -- matter on real crease patterns with thousands of vertices.
      byId = IM.fromList (zip [0 ..] verts)
      nVerts = length verts

      resolve eid vid@(VertexId i) = case IM.lookup i byId of
        Just p -> Right p
        Nothing -> Left (VertexIndexOutOfRange eid vid nVerts)

      toCrease (eid, (a, b), asg) = do
        pa <- resolve eid a
        pb <- resolve eid b
        pure (Crease eid pa pb asg)

  traverse toCrease (zip3 (map EdgeId [0 ..]) (edgesVertices fr) assignments)
  where
    nEdges = length (edgesVertices fr)

    -- edges_assignment is optional. Absent means "nothing is known about any
    -- crease", which is precisely what U (Unassigned) means. Present but the
    -- wrong length is a corrupt file, not a default to paper over.
    --
    -- Note that some other FOLD implementations are more lenient here and pad
    -- a short array with U per-edge. That renders more files, at the cost of
    -- silently drawing a truncated pattern as though it were complete. The
    -- strict choice is made here on the grounds that a loud failure while the
    -- project is young teaches us what real files actually look like; it is
    -- worth revisiting once we have seen more of them.
    resolveAssignments
      | null (edgesAssignment fr) = Right (replicate nEdges Unassigned)
      | length (edgesAssignment fr) == nEdges = Right (edgesAssignment fr)
      | otherwise =
          Left $
            ArrayLengthMismatch
              "edges_vertices"
              nEdges
              "edges_assignment"
              (length (edgesAssignment fr))
