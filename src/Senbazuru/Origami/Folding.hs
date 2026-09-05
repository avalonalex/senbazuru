-- |
-- Module      : Senbazuru.Origami.Folding
-- Description : Turning a crease pattern and its fold angles into a folded form.
--
-- Given a flat sheet with a crease pattern on it and an angle for every crease,
-- where does the paper end up? This module answers that, and hands back another
-- 'Frame' — a folded form, which the existing renderer draws with no idea that
-- it was computed rather than read from a file.
--
-- == The algorithm, in one line
--
-- Paper does not stretch, so every face moves __rigidly__: it turns and slides,
-- never bends or scales. The whole folded state is therefore one 'Rigid' per
-- face. Hold one face still, walk a spanning tree of the face-adjacency graph,
-- and at each step across a crease compose one more turn:
--
-- > M[child] = M[parent] `after` rotationAbout p axis angle
--
-- Then every vertex is a lookup: apply the transform of any face it belongs to.
-- The long version, with references, is in
-- @docs\/notes\/folding-by-transforms.md@.
--
-- == The line that looks like a mistake
--
-- @p@ and @axis@ above come from the crease __as it lies in the flat pattern__,
-- not from where that crease has ended up after the parent moved. It reads like
-- a bug. It is not: sandwiching a rotation between a motion and its inverse
-- turns it into the same rotation about the moved axis, so
-- @R_folded · M[parent]@ is @M[parent] · R_flat · M[parent]⁻¹ · M[parent]@, and
-- the inverse cancels. Nothing is ever inverted and no axis is re-derived from
-- an accumulated result, which is why a long chain of faces does not drift.
--
-- == Which way does it turn?
--
-- This is the part that silently folds half a model backwards, and it takes
-- three facts to pin down.
--
-- 1. A crease pattern lies in the plane @z = 0@ and is looked at from @+z@.
--    Mountain and valley are named from that side.
-- 2. Faces are oriented counterclockwise __as measured here__, from the
--    coordinates, not as the file lists them. FOLD specifies counterclockwise
--    and real files disagree; a winding taken on trust would flip the sign for
--    every face that disagreed. Walking a counterclockwise ring keeps the face
--    on your left, so the neighbour across each edge is on your right.
-- 3. A valley opens towards the viewer. Pin the parent face flat and the child
--    can only rise, so a valley — positive, in FOLD — lifts the child towards
--    @+z@.
--
-- Put together: with the shared crease directed the way the __parent's__
-- counterclockwise ring runs, the child is on the right of it, and lifting the
-- child towards @+z@ is a __negative__ turn by the right-hand rule. So the
-- rotation applied is @negate angle@, and that minus sign is the whole of the
-- convention.
--
-- == What a spanning tree cannot notice
--
-- Around an interior vertex the faces form a ring, and a tree has no rings — it
-- reaches the last face by one path and never closes the loop. So every angle
-- assignment produces /some/ answer, including assignments no sheet of paper
-- can adopt, and the wrong ones do not announce themselves: the model simply
-- tears, and the tear is invisible in a picture.
--
-- So 'foldFrame' closes the loops itself. A vertex on several faces is placed
-- once per face, and if those placements disagree the fold is rejected with
-- 'TornAt' naming the vertex and how far apart they are. That check is the
-- difference between this module and a plausible-looking one.
module Senbazuru.Origami.Folding
  ( foldFrame,
    FoldingError (..),
    renderFoldingError,
  )
where

import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Numeric (showGFloat)
import Senbazuru.Fold.Query
  ( Face (..),
    FoldError,
    frameFaces,
    frameVertices,
    renderFoldError,
  )
import Senbazuru.Fold.Types
  ( Assignment (..),
    EdgeId (..),
    FaceId (..),
    Frame (..),
    VertexId (..),
  )
import Senbazuru.Geometry.Rigid (Rigid, after, applyRigid, identity, rotationAbout)
import Senbazuru.Geometry.V3 (V3 (..), hasRelief, zSpan)
import Senbazuru.Geometry.VectorSpace

-- | Everything that stops a pattern being folded.
data FoldingError
  = -- | The frame is not structurally sound enough to get this far.
    FrameGeometry !FoldError
  | -- | The vertices already leave the plane, so this is a folded form and
    -- there is nothing to fold. Carries how far it spans in @z@.
    AlreadyFolded !Double
  | -- | No @faces_vertices@. Creases alone do not say which pieces of paper
    -- move together, so there is nothing to apply a transform to.
    NoFaces
  | -- | A face whose corners are collinear, so it has no area and no
    -- orientation to read.
    DegenerateFace !FaceId
  | -- | A face has an edge that @edges_vertices@ does not list, so there is no
    -- fold angle for it. Carries the face and the two corners.
    FaceEdgeMissing !FaceId !VertexId !VertexId
  | -- | Two entries of @edges_vertices@ join the same pair of vertices. Which
    -- fold angle applies is then a coin toss, so neither is used.
    DuplicateEdge !EdgeId !EdgeId
  | -- | More than two faces meet along one crease, so the sheet is not a
    -- surface and \"the face on the other side\" has no answer.
    NonManifoldEdge !VertexId !VertexId !Int
  | -- | A face no chain of creases connects to the rest, so nothing places it
    -- relative to the others.
    DisconnectedFace !FaceId
  | -- | The faces meeting at a vertex disagree about where it ends up: these
    -- angles tear the paper. Carries the vertex and the distance between the
    -- furthest-apart placements.
    TornAt !VertexId !Double
  deriving stock (Eq, Show)

-- | A human-readable rendering of a 'FoldingError'.
renderFoldingError :: FoldingError -> Text
renderFoldingError = \case
  FrameGeometry err -> renderFoldError err
  AlreadyFolded dz ->
    "the vertices span " <> num dz <> " in z, so this frame is already folded"
  NoFaces ->
    "no faces_vertices, so there is no way to know which pieces of paper move"
      <> " together; folding needs faces, not just creases"
  DegenerateFace (FaceId f) ->
    "face " <> tshow f <> " has no area, so it has no orientation to fold about"
  FaceEdgeMissing (FaceId f) (VertexId a) (VertexId b) ->
    "face "
      <> tshow f
      <> " has an edge from vertex "
      <> tshow a
      <> " to "
      <> tshow b
      <> " that edges_vertices does not list, so it has no fold angle"
  DuplicateEdge (EdgeId a) (EdgeId b) ->
    "edges " <> tshow a <> " and " <> tshow b <> " join the same two vertices"
  NonManifoldEdge (VertexId a) (VertexId b) n ->
    "the crease from vertex "
      <> tshow a
      <> " to "
      <> tshow b
      <> " has "
      <> tshow n
      <> " faces along it; folding needs at most two"
  DisconnectedFace (FaceId f) ->
    "face "
      <> tshow f
      <> " is not joined to the rest of the sheet by any crease, so nothing"
      <> " says where it goes"
  TornAt (VertexId v) d ->
    "vertex "
      <> tshow v
      <> " is placed "
      <> num d
      <> " apart by the faces meeting at it, so these fold angles tear the"
      <> " paper rather than folding it"

-- | Fold a crease pattern into the form its fold angles describe.
--
-- The result is a new 'Frame' with the same graph and the same angles, moved
-- vertices, and @frame_classes@ set to @foldedForm@ so that whatever draws it
-- picks the right line convention. The angles are kept because they, not the
-- coordinates, are the state — see @docs\/notes\/fold-angles-are-the-state.md@.
--
-- The root face is held still, which places the model somewhere particular in
-- space without changing its shape.
foldFrame :: Frame -> Either FoldingError Frame
foldFrame fr = do
  flat <- first FrameGeometry (frameVertices fr)
  case () of
    _ | hasRelief flat -> Left (AlreadyFolded (zSpan flat))
    _ -> Right ()
  faces <- traverse orientCcw =<< first FrameGeometry (frameFaces fr)
  case faces of
    [] -> Left NoFaces
    _ -> Right ()
  creases <- creaseIndex fr
  neighbours <- faceNeighbours faces
  transforms <- spanningWalk faces creases neighbours
  folded <- placeVertices (length flat) flat faces transforms
  pure
    fr
      { verticesCoords = [[x, y, z] | V3 x y z <- folded],
        frameClasses = ["foldedForm"]
      }

-- | An identifier for a crease, independent of which way round it is written.
type CreaseKey = (Int, Int)

creaseKey :: VertexId -> VertexId -> CreaseKey
creaseKey (VertexId a) (VertexId b) = (min a b, max a b)

-- | Put a face's corners in counterclockwise order as seen from @+z@.
--
-- Measured from the coordinates with the shoelace formula, rather than trusting
-- the order the file lists them in. That is not caution for its own sake: the
-- direction the ring runs decides the sign of every fold made across it, so a
-- file whose winding disagrees with the specification would fold half its faces
-- the wrong way.
orientCcw :: Face -> Either FoldingError Face
orientCcw f
  | area > 0 = Right f
  | area < 0 =
      Right
        f
          { faceVertexIds = reverse (faceVertexIds f),
            faceCorners = reverse (faceCorners f)
          }
  | otherwise = Left (DegenerateFace (faceId f))
  where
    -- Twice the signed area. Positive is counterclockwise with y upwards, which
    -- is the convention model coordinates use.
    area = sum (zipWith term corners (drop 1 corners <> take 1 corners))
    corners = faceCorners f
    term (V3 x0 y0 _) (V3 x1 y1 _) = x0 * y1 - x1 * y0

-- | Every crease by the pair of vertices it joins, with its fold angle in
-- radians.
--
-- When @edges_foldAngle@ is absent the angle is taken from the assignment: a
-- mountain folds to @-180°@ and a valley to @+180°@. That is what an assignment
-- on its own can say — it names a direction and not an amount — and a flat fold
-- is the only amount consistent with naming no number at all.
creaseIndex :: Frame -> Either FoldingError (M.Map CreaseKey (EdgeId, Double))
creaseIndex fr = foldr add (Right M.empty) (zip3 (map EdgeId [0 ..]) (edgesVertices fr) angles)
  where
    angles = case edgesFoldAngle fr of
      as | length as == length (edgesVertices fr) -> map radians as
      _ -> map fromAssignment (edgesAssignment fr <> repeat Unassigned)

    radians d = d * pi / 180
    fromAssignment = \case
      Mountain -> -pi
      Valley -> pi
      _ -> 0

    add (eid, (a, b), angle) acc = do
      m <- acc
      let key = creaseKey a b
      case M.lookup key m of
        Just (other, _) -> Left (DuplicateEdge other eid)
        Nothing -> Right (M.insert key (eid, angle) m)

-- | For each crease, the faces that meet along it.
--
-- A crease with one face is on the edge of the sheet and folds nothing; two is
-- an interior crease; more than two is not a surface.
faceNeighbours :: [Face] -> Either FoldingError (M.Map CreaseKey [FaceId])
faceNeighbours faces = M.traverseWithKey atMostTwo byCrease
  where
    byCrease =
      M.fromListWith
        (<>)
        [ (creaseKey a b, [faceId f])
          | f <- faces,
            (a, b) <- ringEdges (faceVertexIds f)
        ]

    atMostTwo (a, b) fs
      | length fs <= 2 = Right fs
      | otherwise = Left (NonManifoldEdge (VertexId a) (VertexId b) (length fs))

-- | The consecutive pairs around a closed ring.
ringEdges :: [a] -> [(a, a)]
ringEdges vs = zip vs (drop 1 vs <> take 1 vs)

-- | Walk the face graph from the first face, composing one turn per crease.
spanningWalk ::
  [Face] ->
  M.Map CreaseKey (EdgeId, Double) ->
  M.Map CreaseKey [FaceId] ->
  Either FoldingError (IM.IntMap Rigid)
spanningWalk faces creases neighbours = do
  placed <- go (IM.singleton root identity) [root]
  case [faceId f | f <- faces, not (IM.member (unFaceId (faceId f)) placed)] of
    (missing : _) -> Left (DisconnectedFace missing)
    [] -> Right placed
  where
    root = case faces of
      (f : _) -> unFaceId (faceId f)
      [] -> 0

    byId = IM.fromList [(unFaceId (faceId f), f) | f <- faces]

    go placed [] = Right placed
    go placed (current : queue) = case IM.lookup current byId of
      Nothing -> Right placed
      Just f -> do
        steps <- traverse (crossing f) (ringEdges (faceVertexIds f))
        let parent = fromMaybe identity (IM.lookup current placed)
            fresh =
              [ (child, parent `after` turn)
                | Just (child, turn) <- steps,
                  not (IM.member child placed)
              ]
            -- A face can be reached twice within one ring only if it shares two
            -- creases with this one, in which case the first arrival wins and
            -- the second is a loop the tree cuts. placeVertices is what notices
            -- if that mattered.
            placed' = foldr (\(c, m) acc -> IM.insertWith (\_ old -> old) c m acc) placed fresh
        go placed' (queue <> map fst fresh)
      where
        -- Crossing one edge of the current face: who is on the other side, and
        -- what turn puts them there.
        crossing f (a, b) = case M.lookup (creaseKey a b) creases of
          Nothing -> Left (FaceEdgeMissing (faceId f) a b)
          Just (_, angle) ->
            let others =
                  [ unFaceId other
                    | other <- M.findWithDefault [] (creaseKey a b) neighbours,
                      other /= faceId f
                  ]
             in case others of
                  [] -> Right Nothing
                  (child : _) -> Right (Just (child, turnAcross f a b angle))

    -- The crease runs a -> b in this face's counterclockwise ring, so the
    -- neighbour is on its right, and a valley has to lift it towards +z. That
    -- is a negative turn about a -> b by the right-hand rule; see the module
    -- header.
    turnAcross f a b angle = case cornerAt f a of
      Nothing -> identity
      Just pa -> case cornerAt f b of
        Nothing -> identity
        Just pb -> rotationAbout pa (pb ^-^ pa) (negate angle)

    cornerAt f v = lookup v (zip (faceVertexIds f) (faceCorners f))

-- | Move every vertex, and refuse to hand back a torn model.
--
-- Each face places the vertices it owns. A vertex on several faces is therefore
-- placed several times, and the placements agree only if the fold angles round
-- that vertex compose to nothing — the loop-closure condition, which the
-- spanning tree cut and never tested. Comparing them here is the test.
--
-- The tolerance is relative to the size of the sheet, because \"far apart\" only
-- means something next to something else: a millimetre is a tear in a model a
-- centimetre across and rounding noise in one the size of a room.
placeVertices ::
  Int ->
  [V3] ->
  [Face] ->
  IM.IntMap Rigid ->
  Either FoldingError [V3]
placeVertices n flat faces transforms =
  traverse settle [0 .. n - 1]
  where
    placements :: IM.IntMap [V3]
    placements =
      IM.fromListWith
        (<>)
        [ (v, [applyRigid m corner])
          | f <- faces,
            let m = fromMaybe identity (IM.lookup (unFaceId (faceId f)) transforms),
            (VertexId v, corner) <- zip (faceVertexIds f) (faceCorners f)
        ]

    original = IM.fromList (zip [0 ..] flat)

    settle v = case IM.findWithDefault [] v placements of
      -- A vertex no face mentions cannot be folded, and leaving it where it was
      -- is the only answer that does not invent one. It is also invisible: the
      -- renderer draws edges, and an edge to such a vertex has no face either.
      [] -> Right (IM.findWithDefault (V3 0 0 0) v original)
      (p : ps)
        | spread <= tolerance -> Right p
        | otherwise -> Left (TornAt (VertexId v) spread)
        where
          spread = maximum (0 : map (norm . (^-^ p)) ps)

    tolerance = 1e-6 * max 1 sheetSize

    -- The bounding box is enough to size the sheet, and it is one pass.
    sheetSize = max (spanOf v3x) (spanOf v3y)
    spanOf f = case map f flat of
      [] -> 0
      cs -> maximum cs - minimum cs

num :: Double -> Text
num x = T.pack (showGFloat (Just 6) x "")

tshow :: (Show a) => a -> Text
tshow = T.pack . show
