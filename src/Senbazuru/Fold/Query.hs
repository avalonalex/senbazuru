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
-- 'Crease' holds two actual points, not two integers that we hope are valid
-- indices, so no code downstream needs an error path for a dangling reference.
module Senbazuru.Fold.Query
  ( -- * Errors
    FoldError (..),
    renderFoldError,

    -- * Refined views of a frame
    Crease (..),
    Face (..),
    frameVertices,
    frameCreases,
    frameFaces,
  )
where

import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Fold.Types
  ( Assignment (..),
    EdgeId (..),
    FaceId (..),
    Frame (..),
    VertexId (..),
  )
import Senbazuru.Geometry.V3 (V3 (..))

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
  | -- | A face refers to a vertex id that has no entry in @vertices_coords@.
    -- Carries the face, the bad vertex id, and how many vertices exist.
    FaceVertexOutOfRange FaceId VertexId Int
  | -- | A face with fewer than three corners, which bounds no area and so is
    -- not a face. Carries the face and how many corners it has.
    FaceTooFewCorners FaceId Int
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
  FaceVertexOutOfRange (FaceId f) (VertexId v) n ->
    "face "
      <> tshow f
      <> " refers to vertex "
      <> tshow v
      <> ", but vertices_coords only has "
      <> tshow n
      <> " entries (valid ids are 0.."
      <> tshow (n - 1)
      <> ")"
  FaceTooFewCorners (FaceId f) n ->
    "face "
      <> tshow f
      <> " has "
      <> tshow n
      <> " corner(s); a face needs at least 3 to enclose any paper"
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
--
-- Endpoints are 'V3' because that is what the file holds. Flattening them onto
-- a page is the camera's job, not this module's — see
-- "Senbazuru.Render.Camera".
data Crease = Crease
  { creaseId :: !EdgeId,
    -- | The endpoint ids, kept alongside the positions because a consumer that
    -- has to reason about the /graph/ — which creases meet at which vertex —
    -- cannot recover them from coordinates without comparing floating-point
    -- numbers for equality. "Senbazuru.Origami.FlatFold" is the first such
    -- consumer.
    creaseFrom :: !VertexId,
    creaseTo :: !VertexId,
    creaseStart :: !V3,
    creaseEnd :: !V3,
    creaseAssignment :: !Assignment
  }
  deriving stock (Eq, Show)

-- | Vertex positions, as points in space.
--
-- FOLD coordinates may have two or three components. Two-component vertices
-- get @z = 0@, which is not a fudge: a @creasePattern@ frame really is flat,
-- and the plane it lies in is @z = 0@. Anything beyond the third component is
-- ignored, since nothing here can draw a fourth dimension.
--
-- No projection happens at this stage. This module answers \"where is the paper
-- in space?\"; deciding how to look at it belongs to
-- "Senbazuru.Render.Camera".
frameVertices :: Frame -> Either FoldError [V3]
frameVertices fr = traverse toV3 (zip (map VertexId [0 ..]) (verticesCoords fr))
  where
    toV3 (vid, coords) = case coords of
      (x : y : z : _) -> Right (V3 x y z)
      [x, y] -> Right (V3 x y 0)
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
        pure (Crease eid a b pa pb asg)

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

-- | One face of the sheet, resolved to the points that bound it.
--
-- The vertex ids are kept beside the coordinates for the same reason 'Crease'
-- keeps its endpoints: a consumer reasoning about the /graph/ — which faces
-- share an edge, which is what folding a pattern needs — cannot recover them
-- from coordinates without comparing floating-point numbers for equality.
data Face = Face
  { faceId :: !FaceId,
    -- | @faces_vertices[i]@, in the order the file gives them.
    faceVertexIds :: ![VertexId],
    -- | The same corners as points, in the same order.
    faceCorners :: ![V3]
  }
  deriving stock (Eq, Show)

-- | Every face of the frame as a closed ring of corners.
--
-- A frame with no @faces_vertices@ has no faces, which is not an error: the key
-- is optional, plenty of real crease patterns omit it, and \"there are no
-- faces\" is a perfectly good answer to give a renderer.
--
-- What /is/ an error is a face that cannot be a face. Two vertices enclose no
-- paper, and a corner pointing at a vertex that does not exist is a corrupt
-- file. Both are rejected here rather than skipped, on the same grounds
-- 'frameCreases' rejects a mismatched @edges_assignment@: while the project is
-- young a loud failure teaches us what real files look like, where a quiet skip
-- would draw a sheet with a hole in it and say nothing.
--
-- __Winding is not consulted, and does not need to be.__ FOLD specifies
-- counterclockwise, real files disagree, and it makes no difference to the one
-- thing this feeds: filling a simple closed polygon covers the same region
-- whichever way round its corners are listed. Anything that needs a face's
-- /normal/ — which side is up, which is what a folded form will care about —
-- must work the orientation out for itself rather than trusting the file.
frameFaces :: Frame -> Either FoldError [Face]
frameFaces fr = do
  verts <- frameVertices fr
  let byId = IM.fromList (zip [0 ..] verts)
      nVerts = length verts

      resolve fid vid@(VertexId i) = case IM.lookup i byId of
        Just p -> Right p
        Nothing -> Left (FaceVertexOutOfRange fid vid nVerts)

      toFace (fid, corners)
        | length corners < 3 = Left (FaceTooFewCorners fid (length corners))
        | otherwise = Face fid corners <$> traverse (resolve fid) corners

  traverse toFace (zip (map FaceId [0 ..]) (facesVertices fr))
