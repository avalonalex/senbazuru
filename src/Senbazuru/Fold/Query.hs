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
    FrameKind (..),
    frameKind,
    frameVertices,
    frameCreases,
    frameFaces,
    frameFaceOrders,
  )
where

import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Fold.Types
  ( Assignment (..),
    EdgeId (..),
    FaceId (..),
    FaceOrder (..),
    Frame (..),
    VertexId (..),
  )
import Senbazuru.Geometry.V3 (V3 (..), hasRelief)

-- | Everything that can be structurally wrong with an otherwise well-formed
-- FOLD frame, or with a pair of frames that are meant to be two states of one
-- model.
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
  | -- | A face whose corner list repeats its first vertex at the end. The ring
    -- is closed implicitly, so this is one corner listed twice, and it makes a
    -- face look as though it has an edge from a vertex to itself.
    FaceRingClosed FaceId
  | -- | A @faceOrders@ entry names a face that does not exist. Carries the bad
    -- face id and how many faces there are.
    FaceOrderOutOfRange FaceId Int
  | -- | A @faceOrders@ entry stacks a face against itself, which says nothing
    -- and is more likely a typo than a claim.
    FaceOrderSelf FaceId
  | -- | A @faceOrders@ entry is measured against a face with no area, which
    -- therefore has no normal for the sign to mean anything against.
    FaceWithoutNormal FaceId
  | -- | The @faceOrders@ contradict each other: following them round returns to
    -- where it started, so the file describes a stack of paper in front of
    -- itself. Raised by "Senbazuru.Origami.Layers" and carried here so that
    -- everything a frame can be wrong about reaches a caller as one type.
    ImpossibleStacking FaceId
  | -- | Two frames that should describe the same paper disagree about how much
    -- of it there is. Carries the key and the two lengths.
    FramesDiffer Text Int Int
  | -- | They have the same amount of paper and have joined it up differently,
    -- so matching element @i@ of one to element @i@ of the other would compare
    -- unrelated pieces. Carries the key and the first index that differs.
    FramesDisagree Text Int
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
    "edge " <> tshow e <> " refers to vertex " <> tshow v <> ", but " <> validIds n
  FaceVertexOutOfRange (FaceId f) (VertexId v) n ->
    "face " <> tshow f <> " refers to vertex " <> tshow v <> ", but " <> validIds n
  FaceTooFewCorners (FaceId f) n ->
    "face "
      <> tshow f
      <> " has "
      <> tshow n
      <> " corner(s); a face needs at least 3 to enclose any paper"
  FaceRingClosed (FaceId f) ->
    "face "
      <> tshow f
      <> " ends on the corner it starts with; faces_vertices lists each corner"
      <> " once and the ring closes on its own"
  FaceOrderOutOfRange (FaceId f) n ->
    "faceOrders refers to face "
      <> tshow f
      <> ", but there "
      <> (if n == 1 then "is 1 face" else "are " <> tshow n <> " faces")
  FaceOrderSelf (FaceId f) ->
    "faceOrders stacks face " <> tshow f <> " against itself"
  FaceWithoutNormal (FaceId f) ->
    "faceOrders stacks against face "
      <> tshow f
      <> ", which has no area and so no normal for above and below to mean"
      <> " anything against"
  ImpossibleStacking (FaceId f) ->
    "the faceOrders run in a circle through face "
      <> tshow f
      <> "; no stack of paper is in front of itself"
  FramesDisagree what i ->
    "these two frames are not two states of one model: their "
      <> what
      <> " first differ at index "
      <> tshow i
  FramesDiffer what a b ->
    "these two frames are not two states of one model: one has "
      <> tshow a
      <> " "
      <> what
      <> " and the other has "
      <> tshow b
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
    -- Spelled out for the empty case, which would otherwise read "valid ids are
    -- 0..-1" -- a backwards interval, which is not a range and not a hint.
    validIds 0 = "vertices_coords is empty"
    validIds n =
      "vertices_coords only has "
        <> tshow n
        <> " entries (valid ids are 0.."
        <> tshow (n - 1)
        <> ")"

    tshow :: (Show a) => a -> Text
    tshow = T.pack . show

-- | What a frame's coordinates are a picture of.
data FrameKind
  = -- | A flat sheet with the folds still to be made marked on it.
    CreasePattern
  | -- | The paper as it is after folding, flat or not.
    FoldedForm
  deriving stock (Eq, Show)

-- | Decide which kind of picture a frame is, from its geometry and then, only
-- if it has to, from its classes.
--
-- Relief settles it: a frame that leaves the plane has been folded, whatever it
-- calls itself, and 'hasRelief' is the one place that judgement is made.
--
-- A flat frame is the hard case, and the reason this function exists rather
-- than each caller writing two lines. A flat-folded model — the traditional
-- crane — has coordinates a crease pattern's cannot be told from, so the only
-- thing left to ask is @frame_classes@, and a frame that declares nothing is
-- taken as a pattern, which is what senbazuru has always done. Three callers
-- need this answer: what line convention to draw with, whether the
-- flat-folding theorems apply, and whether there is anything left to fold.
-- They must not be able to disagree, and they did: the folding module tested
-- the geometry alone and would fold an already-folded crane a second time.
--
-- Takes @frame_classes@ and the vertices rather than the whole frame: the
-- caller has already validated the vertices, so a frame with a bad coordinate
-- fails once and in one place, and nobody has to build a frame to ask.
frameKind :: [Text] -> [V3] -> FrameKind
frameKind classes verts
  | hasRelief verts = FoldedForm
  | "foldedForm" `elem` classes = FoldedForm
  | otherwise = CreasePattern

-- | Look vertices up by id.
--
-- An 'IM.IntMap' gives @O(log n)@ lookup. Indexing the list with @(!!)@ instead
-- would make every caller quadratic, which starts to matter on real crease
-- patterns with thousands of vertices — so this is a shared function rather
-- than a line each caller is free to write the slow way.
vertexIndex :: [V3] -> (VertexId -> Maybe V3)
vertexIndex verts = \(VertexId i) -> IM.lookup i byId
  where
    byId = IM.fromList (zip [0 ..] verts)

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
  let lookupVertex = vertexIndex verts

      resolve eid vid = case lookupVertex vid of
        Just p -> Right p
        Nothing -> Left (VertexIndexOutOfRange eid vid (length verts))

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
-- __Winding is not consulted here, and the corners come back in the order the
-- file gave them.__ FOLD specifies counterclockwise and real files disagree,
-- and for filling it makes no difference: a simple closed polygon covers the
-- same region whichever way round its corners are listed.
--
-- What a consumer should do about that depends on what it wants the winding
-- /for/, and the two answers point opposite ways.
-- "Senbazuru.Origami.Folding" needs a consistent orientation and nothing else,
-- so it measures one from the coordinates and ignores the file. But
-- "Senbazuru.Origami.Layers" reads @faceOrders@, whose signs were written
-- against the normals the file's own winding defines — so it must take that
-- winding exactly as given, and recomputing it there turns models inside out.
frameFaces :: Frame -> Either FoldError [Face]
frameFaces fr = do
  verts <- frameVertices fr
  let lookupVertex = vertexIndex verts

      resolve fid vid = case lookupVertex vid of
        Just p -> Right p
        Nothing -> Left (FaceVertexOutOfRange fid vid (length verts))

      toFace (fid, corners)
        | closedRing corners = Left (FaceRingClosed fid)
        | length corners < 3 = Left (FaceTooFewCorners fid (length corners))
        | otherwise = Face fid corners <$> traverse (resolve fid) corners

      -- The ring is implicitly closed, so a file that also closes it explicitly
      -- has said the first corner twice. Checked before the length, because
      -- @[0, 1, 0]@ would otherwise pass as a three-corner face enclosing no
      -- area at all.
      closedRing corners = case (corners, reverse corners) of
        (first : _ : _, final : _) -> first == final
        _ -> False

  traverse toFace (zip (map FaceId [0 ..]) (facesVertices fr))

-- | The frame's @faceOrders@, checked against the faces that exist.
--
-- Nothing here interprets the stacking; that needs a direction to look from and
-- lives in "Senbazuru.Origami.Layers". This only refuses entries that cannot
-- mean anything: a face id with no face, and a face stacked against itself.
frameFaceOrders :: Frame -> Either FoldError [FaceOrder]
frameFaceOrders fr = traverse check (faceOrders fr)
  where
    nFaces = length (facesVertices fr)

    check o = do
      inRange (orderFace o)
      inRange (orderRelativeTo o)
      if orderFace o == orderRelativeTo o
        then Left (FaceOrderSelf (orderFace o))
        else Right o

    inRange fid@(FaceId i)
      | i >= 0 && i < nFaces = Right ()
      | otherwise = Left (FaceOrderOutOfRange fid nFaces)
