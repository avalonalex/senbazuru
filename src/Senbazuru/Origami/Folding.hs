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
-- So 'foldFrame' closes the loops itself, and it takes two checks rather than
-- the one it looks like it should.
--
-- A vertex on several faces is placed once per face, and if those placements
-- disagree the fold is rejected with 'TornAt' naming the vertex and how far
-- apart they are. That catches most of it and is the difference between this
-- module and a plausible-looking one.
--
-- What it cannot catch is a loop the walk closed by /doing nothing/. Two faces
-- meeting along a crease share only that crease's own endpoints, which lie on
-- its rotation axis and are fixed by any turn about it — so if the walk gives
-- both faces the same transform, every vertex they share agrees and the
-- dropped angle leaves no trace. 'loopsClose' asks the other question
-- afterwards: is each crease's own angle actually achieved by the transforms?
module Senbazuru.Origami.Folding
  ( foldFrame,
    Folded (..),
    foldFrameWith,
    FoldingError (..),
    renderFoldingError,
  )
where

import Control.Monad (when)
import Data.Bifunctor (first)
import Data.Foldable (foldl', traverse_)
import Data.IntMap.Strict qualified as IM
import Data.IntSet qualified as IS
import Data.Map.Strict qualified as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Senbazuru.Explain (Explain (..), num, tshow)
import Senbazuru.Fold.Crossings (withPlanarFaces)
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
    ringEdges,
  )
import Senbazuru.Fold.Types
  ( Assignment (..),
    EdgeId (..),
    FaceId (..),
    FaceOrder (..),
    Frame (..),
    VertexId (..),
    otherSide,
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
  | -- | No @faces_vertices@, and none could be traced from the creases either
    -- — so the sheet has no creases at all. Anything worse than that about the
    -- drawing is refused by "Senbazuru.Fold.Faces" with the offending element
    -- named, and arrives as a 'FrameGeometry'.
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
  | -- | A crease with paper on one side only records a fold angle. Nothing can
    -- turn about such a crease — there is no second face for it to move — so
    -- the angle describes a fold that cannot happen. Carries the crease and the
    -- angle, in degrees.
    --
    -- Silent until now, and in the same way the loop-closing creases were: the
    -- walk simply never looks at it.
    AngleWithoutPaper !EdgeId !Double
  | -- | A crease's two faces are not at the angle it records. Carries the
    -- crease and how far the paper is from where that angle would put it.
    --
    -- The same fault as 'TornAt' seen from the other side. That one notices a
    -- vertex two faces disagree about; this one notices a crease whose angle
    -- the walk never applied, which can happen with no vertex disagreeing at
    -- all — see 'loopsClose'.
    AngleNotAchieved !EdgeId !Double
  deriving stock (Eq, Show)

instance Explain FoldingError where
  explain = \case
    FrameGeometry err -> explain err
    AlreadyFolded dz ->
      "the vertices span " <> num dz <> " in z, so this frame is already folded"
    NoFaces ->
      "there are no creases here, so there is no paper to fold"
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
    AngleWithoutPaper (EdgeId e) d ->
      "crease "
        <> tshow e
        <> " has paper on one side only and records a fold angle of "
        <> num d
        <> " degrees, so there is no second face for it to move"
    AngleNotAchieved (EdgeId e) d ->
      "crease "
        <> tshow e
        <> " is not folded to the angle it records: its two faces are "
        <> num d
        <> " from where that angle puts them, so these angles cannot all be"
        <> " achieved at once"
    TornAt (VertexId v) d ->
      "vertex "
        <> tshow v
        <> " is placed "
        <> num d
        <> " apart by the faces meeting at it, so these fold angles tear the"
        <> " paper rather than folding it"

-- | 'explain' for a 'FoldingError', under the name it had before the class.
--
-- Kept when the class arrived so that nothing had to move at once. Nothing
-- calls it now: the CLI says 'explain' and no test names this one, so it is
-- exported for a caller that does not exist yet.
renderFoldingError :: FoldingError -> Text
renderFoldingError = explain

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
-- Two things about the graph change, and the second is the price of the first.
--
-- Every face comes back wound __counterclockwise as it lay in the crease
-- pattern__, whichever way the file listed it. That is the winding FOLD asks
-- for, and it is not cosmetic. A
-- face's winding defines its normal, and the normal is how a folded form says
-- which side of the paper is which: "Senbazuru.Origami.Stacking" reads it to
-- decide which face a mountain fold puts underneath, and @faceOrders@ signs
-- are written against it. This module already measures the true winding
-- because the direction of every fold depends on it, so writing it out costs
-- nothing and makes the result a frame whose winding can be trusted.
--
-- And every @faceOrders@ entry whose /second/ face was turned round comes back
-- with its sign flipped, because a winding is not private to its face. FOLD
-- reads a sign against that face's normal and a normal is defined by its
-- winding, so the two were written against each other: a file that wound its
-- faces backwards has signs that are backwards too, and the pair cancels.
-- Re-winding uncancels it. Moving the sign as well puts the cancellation back,
-- and leaving it would turn such a file's model inside out with nothing in the
-- geometry to give it away. See 'reorient'.
--
-- __The angles it folded by are written back.__ A file that gives only an
-- assignment says nothing about how far each crease turns, and folding reads
-- @±180°@ from it. The folded frame records those, so the shape carries its own
-- state instead of leaving the next reader to derive it again. The crane is the
-- case that matters: it carries 129 assignments and no angles, so until this
-- its folded form said nothing whatever about how it had been folded.
--
-- One thing is thrown away: 'frameExtras', the keys of the input file that
-- senbazuru does not understand. They are kept everywhere else precisely so
-- that a file can be read and written back without losing them — but folding
-- rewrites every coordinate and reverses the winding of any face that ends up
-- turned over, and we cannot say which of a file's remaining keys survive
-- that. @faces_edges@ lists a face's edges in the same order as its corners,
-- so it does not; @cpedit:page@ is the bounds of a crease pattern's page, and
-- this is no longer a crease pattern. Writing them out again would be stating
-- something we have reason to think is false, which is worse than losing them.
foldFrame :: Frame -> Either FoldingError Frame
foldFrame = fmap foldedFrame . foldFrameWith

-- | A folded model, the pattern it was folded from, and the motion that placed
-- each face.
--
-- 'foldFrame' answers the question this module was written for and throws the
-- rest away. What it throws away is the interesting part for anything that has
-- to run the fold /backwards/: each 'Rigid' says where a face of the flat sheet
-- ended up, so 'Senbazuru.Geometry.Rigid.inverse' of it takes a point on the
-- folded model back to the point of the sheet it came from.
data Folded = Folded
  { -- | The folded form, exactly what 'foldFrame' returns.
    foldedFrame :: !Frame,
    -- | __The pattern the transforms are against__, which is not necessarily the
    -- frame that went in. Folding first hands the input to
    -- 'Senbazuru.Fold.Crossings.withPlanarFaces', and cutting the crossings
    -- adds vertices and re-traces the faces. So a face's transform is keyed by
    -- its index into /this/ frame's faces, and it is this frame that a caller
    -- wanting to write something back onto the sheet has to write onto.
    --
    -- Most frames come back from that untouched — a frame that records its own
    -- faces and has nothing crossing is returned as it was — so checking the
    -- claim against the nearest example will usually show the two are equal.
    -- The one that matters is @examples\/unit-square.fold@, whose creases cross
    -- with no vertex where they meet: eight vertices go in and nine come out.
    --
    -- Handing it back states the invariant. The alternative is every caller
    -- calling @withPlanarFaces@ again itself and trusting that it lands on the
    -- same frame, which is true today and is not a thing to build on.
    --
    -- Two things it does /not/ promise. Its @faceOrders@ are the file's, read
    -- against the file's winding, where 'foldedFrame'\'s have been re-signed to
    -- match the counterclockwise rings it writes — so the two frames can carry
    -- opposite signs for the same relation, and each is right about its own
    -- faces. Reading faces from one and orders from the other is the mistake to
    -- avoid; take both from 'foldedFrame'.
    --
    -- Nor does it promise that face @i@'s corners are listed in the same order
    -- here as in 'foldedFrame'. Folding writes its faces
    -- counterclockwise as measured on the pattern, so a face the file listed
    -- clockwise has its ring reversed on the way out. The two frames agree about
    -- which vertices a face has and about their ids, not about where the ring
    -- starts or which way it runs.
    foldedPattern :: !Frame,
    -- | One motion per face, keyed by the @Int@ inside its
    -- 'Senbazuru.Fold.Types.FaceId' — @IM.lookup (unFaceId f)@, as
    -- "Senbazuru.Origami.ThroughLayers" does. Every face of 'foldedPattern' has
    -- one: a face the walk could not reach is 'DisconnectedFace' rather than a
    -- gap here.
    foldedPlacements :: !(IM.IntMap Rigid)
  }
  deriving stock (Eq, Show)

-- | 'foldFrame', keeping the working.
--
-- The same computation; 'foldFrame' is this with two thirds of the answer
-- dropped. Written this way round rather than as two functions so that there is
-- one spanning walk and not two implementations of it that can drift.
foldFrameWith :: Frame -> Either FoldingError Folded
foldFrameWith fr0 = do
  asGiven <- first FrameGeometry (frameVertices fr0)
  -- Shared with the renderer and the flat-foldability checker, so that all
  -- three agree about what a file is. Asking the geometry alone would fold an
  -- already-folded crane a second time and hand back nonsense: it folds flat,
  -- so nothing in its coordinates says it has been folded.
  when (frameKind (frameClasses fr0) asGiven == FoldedForm) $
    Left (AlreadyFolded (zSpan asGiven))
  -- Two ways in which a file leaves out what its own creases determine, and
  -- both are recovered rather than refused. A drawing whose creases cross has
  -- left out the vertex where they meet, so cut them at it; and most files
  -- record no faces at all -- no .cp or .opx can -- so trace those. Neither
  -- invents anything: the crossing is on the paper already, and creases alone
  -- do say which pieces of paper move together, just not in so many words.
  --
  -- Both happen here, before anything else reads the frame, so that nothing
  -- below can disagree about which frame it is working on. That includes the
  -- vertices: splitting adds some, so they have to be read from the frame that
  -- comes out and not from the one that went in.
  fr <- first FrameGeometry (withPlanarFaces fr0)
  flat <- first FrameGeometry (frameVertices fr)
  turned <- traverse orientCcw =<< first FrameGeometry (frameFaces fr)
  let faces = map fst turned
      -- The faces whose rings this just reversed, by id. Every @faceOrders@
      -- sign written against one of them now reads backwards.
      rewound = IS.fromList [unFaceId (faceId f) | (f, Rewound) <- turned]
  when (null faces) (Left NoFaces)
  creases <- creaseIndex fr
  -- The angles this fold used, so that the folded frame can record them. Read
  -- after 'creaseIndex' rather than before it, so a file with a bad angle or a
  -- mismatched array still fails in the same place with the same message.
  angles <- foldAnglesOf fr
  neighbours <- faceNeighbours faces
  -- Built once and handed to both checks below, so they cannot come to
  -- different conclusions about one file by measuring it differently.
  let byId = IM.fromList [(unFaceId (faceId f), f) | f <- faces]
      tolerance = sheetTolerance flat
  transforms <- spanningWalk faces creases neighbours
  -- Vertices first, creases second, and that order is the whole of which
  -- message a torn model gets. 'TornAt' names the vertex the faces disagree
  -- about, which is where the origami problem is; 'loopsClose' names whichever
  -- crease the spanning tree happened to drop, which is an accident of the
  -- walk. So the vertex check speaks first and this is the backstop for what it
  -- cannot see.
  folded <- placeVertices tolerance (length flat) flat faces transforms
  loopsClose tolerance byId faces creases neighbours transforms
  pure
    Folded
      { foldedFrame =
          fr
            { verticesCoords = [[x, y, z] | V3 x y z <- folded],
              edgesFoldAngle = angles,
              facesVertices = map faceVertexIds faces,
              faceOrders = map (reorient rewound) (faceOrders fr),
              frameClasses = foldedClasses (frameClasses fr),
              frameAttributes = foldedAttributes (hasRelief folded) (frameAttributes fr),
              frameExtras = mempty
            },
        foldedPattern = fr,
        foldedPlacements = transforms
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

-- | Whether a face's corners had to be turned round to run counterclockwise.
--
-- A 'Bool' would do and would be worse. Which way round it reads decides which
-- @faceOrders@ signs get flipped, so a caller that took @True@ for "was already
-- counterclockwise" would invert exactly the wrong faces — quietly, and in the
-- same way the bug this exists to fix did.
data Winding = AsGiven | Rewound
  deriving stock (Eq, Show)

-- | Put a face's corners in counterclockwise order as seen from @+z@, and say
-- whether that meant turning them round.
--
-- Measured from the coordinates with the shoelace formula, rather than trusting
-- the order the file lists them in. That is not caution for its own sake: the
-- direction the ring runs decides the sign of every fold made across it, so a
-- file whose winding disagrees with the specification would fold half its faces
-- the wrong way.
--
-- The 'Winding' is what 'reorient' needs. A winding is not private to its
-- face: @faceOrders@ signs are written against it, so moving one without the
-- other changes what the file says.
orientCcw :: Face -> Either FoldingError (Face, Winding)
orientCcw f
  | abs area <= negligible = Left (DegenerateFace (faceId f))
  | area > 0 = Right (f, AsGiven)
  | otherwise =
      Right
        ( f
            { faceVertexIds = reverse (faceVertexIds f),
              faceCorners = reverse (faceCorners f)
            },
          Rewound
        )
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

-- | A face order as it reads once the faces have been re-wound.
--
-- FOLD's triple @[f, g, s]@ puts @s@ against __@g@__'s normal, and a normal is
-- defined by the counterclockwise ordering of that face's own corners. So the
-- winding and the sign were written against each other: a file that wound its
-- faces backwards has signs that are backwards too, and the two wrongs cancel.
--
-- 'orientCcw' rewrites the winding, which uncancels them. Flipping the sign of
-- every order whose @g@ was turned round puts the cancellation back, and the
-- result is a frame that says the same thing about its layers in the winding
-- FOLD asks for. Doing neither would turn a model inside out silently, since
-- nothing downstream can tell a deliberate order from an inverted one.
--
-- Only @g@. Reversing @f@ changes which face is being placed and not the
-- direction the relation is read in, so an order whose first face was turned
-- round is left exactly as it was.
reorient :: IS.IntSet -> FaceOrder -> FaceOrder
reorient rewound o
  | unFaceId (orderRelativeTo o) `IS.member` rewound =
      o {orderStacking = otherSide (orderStacking o)}
  | otherwise = o

-- | The fold angle of every crease, in degrees, in @edges_vertices@ order.
--
-- Degrees rather than radians, because degrees are what the file holds and what
-- a folded frame has to write back: 'foldFrameWith' records the angles it
-- folded by, so the shape it produces carries its own state. Radians are one
-- multiplication away and only 'creaseIndex' wants them. Going the other way,
-- from radians back to degrees, would be a second rounding on a number that is
-- about to be written to a file, and files are compared byte for byte here.
--
-- When @edges_foldAngle@ is absent the angle comes from the assignment: a
-- mountain folds to @-180°@ and a valley to @+180°@. That is what an assignment
-- on its own can say — it names a direction and not an amount — and a flat fold
-- is the only amount consistent with naming no number at all.
--
-- An array of the wrong length is a corrupt file, not a default to paper over.
-- "Senbazuru.Fold.Query" says exactly that about @edges_assignment@ and rejects
-- it; quietly substituting angles derived from the assignments — which is what
-- an earlier version did — turned a truncated file into a different model that
-- rendered without a word.
foldAnglesOf :: Frame -> Either FoldingError [Double]
foldAnglesOf fr = case (edgesFoldAngle fr, edgesAssignment fr) of
  (as, _)
    | length as == nEdges -> traverse finite (zip (map EdgeId [0 ..]) as)
  ([], asg)
    | length asg == nEdges -> Right (map fromAssignment asg)
    | null asg -> Right (replicate nEdges 0)
    | otherwise -> lengthMismatch "edges_assignment" (length asg)
  (as, _) -> lengthMismatch "edges_foldAngle" (length as)
  where
    nEdges = length (edgesVertices fr)

    lengthMismatch name n =
      Left (FrameGeometry (ArrayLengthMismatch "edges_vertices" nEdges name n))

    -- cos and sin of a non-finite angle are NaN, a NaN rotation matrix produces
    -- NaN coordinates, and formatNumber writes those as 0 -- so the model would
    -- come out with half its vertices stacked on the origin and nothing said.
    finite (eid, d)
      | isNaN d || isInfinite d = Left (NonFiniteAngle eid d)
      | otherwise = Right d

    fromAssignment = \case
      Mountain -> -180
      Valley -> 180
      _ -> 0

-- | Every crease by the pair of vertices it joins, with its fold angle in
-- radians.
--
-- The angles are 'foldAnglesOf' in the unit the rotations want. The conversion
-- is exact where it has to be: @180 * pi / 180@ is @pi@ and @-180 * pi / 180@
-- is @-pi@, both measured, so keeping the angles in degrees did not move a
-- flat fold by a bit and no golden file changed.
--
-- At @±180°@ the two are the same rigid motion: turning half a turn either way
-- about a line lands in the same place. So folding cannot tell a flat mountain
-- from a flat valley, and the assignment survives only as layer ordering, which
-- is "Senbazuru.Origami.Stacking"\'s question rather than this module's.
creaseIndex :: Frame -> Either FoldingError (M.Map EdgeKey (EdgeId, Double))
creaseIndex fr = do
  angles <- foldAnglesOf fr
  foldr
    add
    (Right M.empty)
    (zip3 (map EdgeId [0 ..]) (edgesVertices fr) (map toRadians angles))
  where
    toRadians d = d * pi / 180

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

-- | The turn that takes the face across one of @f@'s ring edges into place.
--
-- The crease runs @a -> b@ in this face's counterclockwise ring, so the
-- neighbour is on its right, and a valley has to lift it towards @+z@. That is
-- a negative turn about @a -> b@ by the right-hand rule; see the module header.
--
-- A corner the face lists but has no coordinate for cannot happen, since both
-- lists come from the same 'Face'. Saying so with an error rather than with
-- 'identity' means a change that does reach it fails loudly instead of quietly
-- stacking a face on top of its parent.
turnAcross :: Face -> VertexId -> VertexId -> Double -> Either FoldingError Rigid
turnAcross f a b angle = case (cornerAt f a, cornerAt f b) of
  (Just pa, Just pb) -> Right (rotationAbout pa (pb ^-^ pa) (negate angle))
  _ -> Left (FaceEdgeMissing (faceId f) a b)

cornerAt :: Face -> VertexId -> Maybe V3
cornerAt f v = lookup v (zip (faceVertexIds f) (faceCorners f))

-- | Every crease's two faces are where that crease's own angle says, and not
-- merely where the walk left them.
--
-- The spanning tree uses one crease per pair of faces it joins and ignores the
-- rest, so a crease that closes a loop never has its turn composed. 'TornAt'
-- catches most of the damage, by noticing that faces disagree about where a
-- shared vertex goes — but not all of it, because two faces meeting along a
-- crease share only that crease's own endpoints, which lie __on its rotation
-- axis__. Any rotation about that axis fixes them. So when the walk happens to
-- give both faces the /same/ transform, they agree about every vertex they
-- share and the ignored angle vanishes without trace.
--
-- The case that found it: a square with a flat line across it and one valley
-- running from the middle of that line to the edge is three faces in a ring,
-- two of the three joins at zero degrees. The tree reaches all three without
-- turning anything, the valley closes the loop, and the model comes back
-- unfolded and unremarked. It was <https://github.com/avalonalex/senbazuru/issues/84 #84>.
--
-- So every crease is checked against the transforms afterwards. For a tree edge
-- that holds by construction and costs a comparison; for a crease that closes a
-- loop it is the closure condition, stated about the crease that was dropped
-- rather than about a vertex somewhere near it; and for a crease with paper on
-- one side only it is the observation that nothing can turn about it at all, so
-- the only angle it can honestly carry is zero.
--
-- It runs __after__ 'placeVertices' and is deliberately the second opinion. A
-- model whose angles genuinely tear has a vertex its faces disagree about, and
-- that vertex is where the origami problem is; the crease this names is
-- whichever one the tree happened to drop, which is an accident of the walk.
-- Where 'TornAt' can speak it should, and this catches only what it cannot see.
loopsClose ::
  Double ->
  IM.IntMap Face ->
  [Face] ->
  M.Map EdgeKey (EdgeId, Double) ->
  M.Map EdgeKey [FaceId] ->
  IM.IntMap Rigid ->
  Either FoldingError ()
loopsClose tolerance byId faces creases neighbours transforms =
  traverse_ checkFace faces
  where
    checkFace f = traverse_ (checkEdge f) (ringEdges (faceVertexIds f))

    checkEdge f (a, b) = case M.lookup (edgeKey a b) creases of
      -- Unreachable: 'spanningWalk' looks up the same key for the same ring
      -- edge of the same face and refuses this before the walk finishes. Kept
      -- because the alternative is a partial pattern match, and stated as
      -- unreachable so nobody goes looking for the case that produces it.
      Nothing -> Left (FaceEdgeMissing (faceId f) a b)
      Just (eid, angle) -> case across f a b of
        -- A crease the paper only has on one side. Nothing can turn about it,
        -- so an angle there is a fold that cannot happen -- and it would
        -- otherwise be ignored in exactly the silence this function exists to
        -- break. Zero is the only angle such a crease can honestly carry.
        [] | angle /= 0 -> Left (AngleWithoutPaper eid (degrees angle))
        [] -> Right ()
        os -> traverse_ (against f a b eid angle) (onceOnly f os)

    -- Who is on the other side of this crease, which is a different question
    -- from which pairs are this face's turn to check. Asking one and using the
    -- answer for the other says every interior crease has paper on one side,
    -- for whichever of its two faces is numbered higher.
    across f a b =
      [ other
        | other <- M.findWithDefault [] (edgeKey a b) neighbours,
          other /= faceId f
      ]

    -- Each unordered pair once. The relation is symmetric -- crossing back the
    -- other way turns by the same angle about the reversed axis -- so checking
    -- both directions would only cost time.
    onceOnly f os = [o | o <- os, unFaceId o > unFaceId (faceId f)]

    -- Both lookups are total over the faces this was handed, and both fail
    -- loudly rather than falling back, for the reason 'turnAcross' gives: a
    -- default here does not report a smaller problem, it reports no problem.
    -- An `identity` for a missing transform compares as though the face had
    -- not moved, and an empty corner list makes the crease pass unconditionally.
    against f a b eid angle other = do
      turn <- turnAcross f a b angle
      here <- placementOf (faceId f)
      there <- placementOf other
      corners <- cornersOf other
      let expected = here `after` turn
          off c = norm (applyRigid expected c ^-^ applyRigid there c)
      -- Filtered rather than compared against a maximum. `maximum (0 : xs)` is
      -- 0 when xs holds a NaN, because `max 0 NaN` is 0 in Haskell -- so a NaN
      -- transform would pass this check silently, which is the trap
      -- 'placeVertices' documents and which an earlier version of this function
      -- fell into while claiming in a comment not to.
      case filter (not . within) (map off corners) of
        [] -> Right ()
        (bad : _) -> Left (AngleNotAchieved eid bad)

    -- Named so the negation below reads as "not within" and not as "greater
    -- than". They are different for a NaN, which is neither -- and hlint
    -- suggests rewriting `not . (<= tolerance)` to `(> tolerance)` while its
    -- own note says that is wrong in exactly this case.
    within d = d <= tolerance

    placementOf f = case IM.lookup (unFaceId f) transforms of
      Just m -> Right m
      Nothing -> Left (DisconnectedFace f)

    cornersOf f = case IM.lookup (unFaceId f) byId of
      Just g -> Right (faceCorners g)
      Nothing -> Left (DisconnectedFace f)

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
  Double ->
  Int ->
  [V3] ->
  [Face] ->
  IM.IntMap Rigid ->
  Either FoldingError [V3]
placeVertices tolerance n flat faces transforms =
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

-- | Radians as the degrees a file would have written.
degrees :: Double -> Double
degrees r = r * 180 / pi

-- | How far apart two answers about this sheet may be and still be one answer.
--
-- Set to admit arithmetic noise and nothing else, and shared by the two checks
-- that need it so they cannot come to different conclusions about one file.
--
-- It is tempting to make it loose enough to wave through angles that are merely
-- written imprecisely, and that would be a mistake, because the line it draws
-- would then depend on which crease the spanning tree happened to cut. A
-- pattern whose right angles are written as 179.9 rather than 180 reports a
-- disagreement of 1.5e-6 or 1.7e-3 on a unit sheet depending on where the tree
-- cut the loop — three orders of magnitude apart for the same file. A threshold
-- anywhere in that range is a coin toss.
--
-- So the only defensible cut is between our arithmetic and the file's angles.
-- Composing rotations along a chain of faces costs on the order of 1e-13;
-- anything larger is the angles genuinely failing to close, however slightly,
-- and the refusals quote the distance so the reader can see whether it is a
-- tear or a typo in the fourth decimal place.
--
-- The @max 1@ is a floor and not a scale, so on a sheet smaller than one model
-- unit — a file written in metres for a pleat a millimetre across — this stops
-- tracking the paper and becomes an absolute 1e-9. That is inherited from where
-- this used to live rather than chosen here, and it is a real gap for very
-- small coordinates.
sheetTolerance :: [V3] -> Double
sheetTolerance flat = 1e-9 * max 1 sheetSize
  where
    -- The bounding box is enough to size the sheet, and it is one pass.
    sheetSize = max (spanOf v3x) (spanOf v3y)
    spanOf f = case map f flat of
      [] -> 0
      cs -> maximum cs - minimum cs
