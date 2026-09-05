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

import Control.Monad (when)
import Data.Bifunctor (first)
import Data.Foldable (foldl')
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Numeric (showGFloat)
import Senbazuru.Fold.Query
  ( EdgeKey,
    Face (..),
    FoldError (..),
    FrameKind (..),
    edgeKey,
    facesAlongEdges,
    frameFaces,
    frameKind,
    frameVertices,
    renderFoldError,
    ringEdges,
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
  | -- | This frame is a folded form already, so there is nothing to fold.
    -- Carries how far it spans in @z@, which is zero for a flat-folded model
    -- that only its @frame_classes@ gives away.
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
  | -- | A face no chain of creases connects to the rest, so nothing places it
    -- relative to the others.
    DisconnectedFace !FaceId
  | -- | A fold angle that is not a finite number of degrees. Every trig
    -- function of it is @NaN@, and @NaN@ coordinates format as @0@, so this
    -- would otherwise stack half the model on the origin in silence.
    NonFiniteAngle !EdgeId !Double
  | -- | The faces meeting at a vertex disagree about where it ends up: these
    -- angles tear the paper. Carries the vertex and the distance between the
    -- two furthest-apart placements.
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
  NonFiniteAngle (EdgeId e) d ->
    "edge " <> tshow e <> " has a fold angle of " <> num d <> ", which is not a number of degrees"
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
--
-- One thing about the graph does change: every face comes back wound
-- __counterclockwise as it lay in the crease pattern__, whichever way the file
-- listed it. That is the winding FOLD asks for, and it is not cosmetic. A
-- face's winding defines its normal, and the normal is how a folded form says
-- which side of the paper is which: "Senbazuru.Origami.Stacking" reads it to
-- decide which face a mountain fold puts underneath, and @faceOrders@ signs
-- are written against it. This module already measures the true winding
-- because the direction of every fold depends on it, so writing it out costs
-- nothing and makes the result a frame whose winding can be trusted.
foldFrame :: Frame -> Either FoldingError Frame
foldFrame fr = do
  flat <- first FrameGeometry (frameVertices fr)
  -- Shared with the renderer and the flat-foldability checker, so that all
  -- three agree about what a file is. Asking the geometry alone would fold an
  -- already-folded crane a second time and hand back nonsense: it folds flat,
  -- so nothing in its coordinates says it has been folded.
  when (frameKind (frameClasses fr) flat == FoldedForm) $
    Left (AlreadyFolded (zSpan flat))
  faces <- traverse orientCcw =<< first FrameGeometry (frameFaces fr)
  when (null faces) (Left NoFaces)
  creases <- creaseIndex fr
  neighbours <- faceNeighbours faces
  transforms <- spanningWalk faces creases neighbours
  folded <- placeVertices (length flat) flat faces transforms
  pure
    fr
      { verticesCoords = [[x, y, z] | V3 x y z <- folded],
        facesVertices = map faceVertexIds faces,
        frameClasses = foldedClasses (frameClasses fr),
        frameAttributes = foldedAttributes (hasRelief folded) (frameAttributes fr)
      }

-- | @foldedForm@ in place of @creasePattern@, with everything else kept.
--
-- Replacing the whole list would drop classes that are still true —
-- @singleModel@, @graph@ — and those are the file's own words about itself.
foldedClasses :: [Text] -> [Text]
foldedClasses classes =
  "foldedForm" : filter (`notElem` ["creasePattern", "foldedForm"]) classes

-- | @2D@ or @3D@ to match the coordinates we just wrote.
--
-- FOLD's attribute describes exactly what folding changes, so a folded frame
-- that kept its @2D@ while leaving the plane would contradict itself — and this
-- module is the intended input to a FOLD writer, where that lie would be
-- written to disk.
foldedAttributes :: Bool -> [Text] -> [Text]
foldedAttributes solid attrs
  | solid = "3D" : without
  | otherwise = "2D" : without
  where
    without = filter (`notElem` ["2D", "3D"]) attrs

-- | Put a face's corners in counterclockwise order as seen from @+z@.
--
-- Measured from the coordinates with the shoelace formula, rather than trusting
-- the order the file lists them in. That is not caution for its own sake: the
-- direction the ring runs decides the sign of every fold made across it, so a
-- file whose winding disagrees with the specification would fold half its faces
-- the wrong way.
orientCcw :: Face -> Either FoldingError Face
orientCcw f
  | abs area <= negligible = Left (DegenerateFace (faceId f))
  | area > 0 = Right f
  | otherwise =
      Right
        f
          { faceVertexIds = reverse (faceVertexIds f),
            faceCorners = reverse (faceCorners f)
          }
  where
    -- Twice the signed area. Positive is counterclockwise with y upwards, which
    -- is the convention model coordinates use.
    area = sum (zipWith term corners (drop 1 corners <> take 1 corners))
    corners = faceCorners f
    term (V3 x0 y0 _) (V3 x1 y1 _) = x0 * y1 - x1 * y0

    -- Judged against the face's own size, not against zero. The shoelace sum of
    -- a long thin face is a difference of large numbers, so its sign can be
    -- rounding noise -- and that sign decides the direction of every fold made
    -- across this face, and of every face beyond it in the walk. A sliver whose
    -- orientation cannot be read is refused rather than guessed at.
    negligible = 1e-12 * max 1 (extent * extent)
    extent = max (spanOf (\(V3 x _ _) -> x)) (spanOf (\(V3 _ y _) -> y))
    spanOf g = case map g corners of
      [] -> 0
      cs -> maximum cs - minimum cs

-- | Every crease by the pair of vertices it joins, with its fold angle in
-- radians.
--
-- When @edges_foldAngle@ is absent the angle is taken from the assignment: a
-- mountain folds to @-180°@ and a valley to @+180°@. That is what an assignment
-- on its own can say — it names a direction and not an amount — and a flat fold
-- is the only amount consistent with naming no number at all.
creaseIndex :: Frame -> Either FoldingError (M.Map EdgeKey (EdgeId, Double))
creaseIndex fr = do
  angles <- foldAngles
  foldr add (Right M.empty) (zip3 (map EdgeId [0 ..]) (edgesVertices fr) angles)
  where
    nEdges = length (edgesVertices fr)

    -- An array of the wrong length is a corrupt file, not a default to paper
    -- over. "Senbazuru.Fold.Query" says exactly that about edges_assignment and
    -- rejects it; quietly substituting angles derived from the assignments —
    -- which is what an earlier version did — turned a truncated file into a
    -- different model that rendered without a word.
    foldAngles = case (edgesFoldAngle fr, edgesAssignment fr) of
      (as, _)
        | length as == nEdges -> traverse finite (zip (map EdgeId [0 ..]) as)
      ([], asg)
        | length asg == nEdges -> Right (map fromAssignment asg)
        | null asg -> Right (replicate nEdges 0)
        | otherwise -> lengthMismatch "edges_assignment" (length asg)
      (as, _) -> lengthMismatch "edges_foldAngle" (length as)

    lengthMismatch name n =
      Left (FrameGeometry (ArrayLengthMismatch "edges_vertices" nEdges name n))

    -- cos and sin of a non-finite angle are NaN, a NaN rotation matrix produces
    -- NaN coordinates, and formatNumber writes those as 0 -- so the model would
    -- come out with half its vertices stacked on the origin and nothing said.
    finite (eid, d)
      | isNaN d || isInfinite d = Left (NonFiniteAngle eid d)
      | otherwise = Right (d * pi / 180)

    fromAssignment = \case
      Mountain -> -pi
      Valley -> pi
      _ -> 0

    add (eid, (a, b), angle) acc = do
      m <- acc
      let key = edgeKey a b
      case M.lookup key m of
        Just (other, _) -> Left (DuplicateEdge other eid)
        Nothing -> Right (M.insert key (eid, angle) m)

-- | For each crease, the faces that meet along it.
--
-- A crease with one face is on the edge of the sheet and folds nothing; two is
-- an interior crease; more than two is not a surface, and 'facesAlongEdges'
-- refuses it.
faceNeighbours :: [Face] -> Either FoldingError (M.Map EdgeKey [FaceId])
faceNeighbours = first FrameGeometry . facesAlongEdges

-- | Walk the face graph from the first face, composing one turn per crease.
spanningWalk ::
  [Face] ->
  M.Map EdgeKey (EdgeId, Double) ->
  M.Map EdgeKey [FaceId] ->
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

    -- One level of the walk at a time, rather than one face with the newly
    -- reached ones appended. `queue <> new` on every step is a left-nested
    -- append that the next pop re-traverses, which is quadratic in the number
    -- of faces -- and a real crease pattern has thousands.
    go placed [] = Right placed
    go placed frontier = do
      reached <- concat <$> traverse (step placed) frontier
      let placed' = foldl' keepFirst placed reached
      -- The next level is what this one actually placed, taken from the map so
      -- that each face appears exactly once. Reading it off `reached` instead
      -- lists a face once per neighbour that reached it, and since those
      -- duplicates each expand again on the following level the walk stops
      -- being linear and becomes exponential -- a 3600-face grid did not finish.
      go placed' (IM.keys (placed' `IM.difference` placed))

    -- First arrival wins: foldl' inserts in the order the level produced them
    -- and insertWith keeps whatever is already there. Reaching a face twice in
    -- one level means it shares two creases with this one, which is a loop the
    -- tree has to cut somewhere; placeVertices is what notices whether the cut
    -- mattered.
    keepFirst acc (c, m) = IM.insertWith (\_ old -> old) c m acc

    step placed current = case IM.lookup current byId of
      -- A frontier entry with no face is impossible, since the frontier is
      -- built from faces. Dropping the rest of the queue on it -- which an
      -- earlier version did -- would have reported every face still waiting as
      -- disconnected, blaming the file for a walk that gave up.
      Nothing -> Right []
      Just f -> do
        steps <- traverse (crossing f) (ringEdges (faceVertexIds f))
        let parent = fromMaybe identity (IM.lookup current placed)
        pure
          [ (child, parent `after` turn)
            | Just (child, turn) <- steps,
              not (IM.member child placed)
          ]

    -- Crossing one edge of a face: who is on the other side, and what turn puts
    -- them there.
    crossing f (a, b) = case M.lookup (edgeKey a b) creases of
      Nothing -> Left (FaceEdgeMissing (faceId f) a b)
      Just (_, angle) -> case others of
        [] -> Right Nothing
        (child : _) -> Just . (,) child <$> turnAcross f a b angle
      where
        others =
          [ unFaceId other
            | other <- M.findWithDefault [] (edgeKey a b) neighbours,
              other /= faceId f
          ]

    -- The crease runs a -> b in this face's counterclockwise ring, so the
    -- neighbour is on its right, and a valley has to lift it towards +z. That
    -- is a negative turn about a -> b by the right-hand rule; see the module
    -- header.
    --
    -- A corner the face lists but has no coordinate for cannot happen, since
    -- both lists come from the same Face. Saying so with an error rather than
    -- with `identity` means a change that does reach it fails loudly instead of
    -- quietly stacking a face on top of its parent.
    turnAcross f a b angle = case (cornerAt f a, cornerAt f b) of
      (Just pa, Just pb) -> Right (rotationAbout pa (pb ^-^ pa) (negate angle))
      _ -> Left (FaceEdgeMissing (faceId f) a b)

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
      ps@(p : _)
        -- Written as `all (<= tolerance)` and not `maximum ... <= tolerance`
        -- on purpose. A NaN coordinate -- which a NaN rotation matrix would
        -- produce -- makes every comparison False, so this refuses it; a
        -- seeded `maximum` would not, because `max 0 NaN` is 0 in Haskell, and
        -- NaN coordinates go on to format as 0 and stack half the model on the
        -- origin without a word.
        | all ((<= tolerance) . norm . (^-^ p)) ps -> Right p
        | otherwise -> Left (TornAt (VertexId v) (diameter ps))

    -- The furthest apart any two placements are, which is what TornAt says it
    -- carries and what the message quotes to the user. Measuring everything
    -- against the first placement instead can understate the disagreement by
    -- half. There are only ever as many placements as faces at the vertex.
    diameter ps = maximum (0 : [norm (a ^-^ b) | a <- ps, b <- ps])

    -- Set to admit arithmetic noise and nothing else.
    --
    -- It is tempting to make this loose enough to wave through angles that are
    -- merely written imprecisely, and that would be a mistake, because the line
    -- it draws would then depend on which crease the spanning tree happened to
    -- cut. A pattern whose right angles are written as 179.9 rather than 180
    -- reports a disagreement of 1.5e-6 or 1.7e-3 on a unit sheet depending on
    -- where the tree cut the loop -- three orders of magnitude apart for the
    -- same file. A threshold anywhere in that range is a coin toss.
    --
    -- So the only defensible cut is between our arithmetic and the file's
    -- angles. Composing rotations along a chain of faces costs on the order of
    -- 1e-13; anything larger is the angles genuinely failing to close, however
    -- slightly, and 'TornAt' quotes the distance so the reader can see whether
    -- it is a tear or a typo in the fourth decimal place.
    tolerance = 1e-9 * max 1 sheetSize

    -- The bounding box is enough to size the sheet, and it is one pass.
    sheetSize = max (spanOf v3x) (spanOf v3y)
    spanOf f = case map f flat of
      [] -> 0
      cs -> maximum cs - minimum cs

num :: Double -> Text
num x = T.pack (showGFloat (Just 6) x "")

tshow :: (Show a) => a -> Text
tshow = T.pack . show
