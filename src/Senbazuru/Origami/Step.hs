-- |
-- Module      : Senbazuru.Origami.Step
-- Description : Working out what one step of a diagram does, by subtracting two frames.
--
-- A crease pattern is not instructions. What makes a diagram teachable is the
-- arrow: the mark that says /this/ piece of paper moves /there/. FOLD has no
-- key for one — no arrow, no operation, not even a caption — so an arrow cannot
-- be read out of a file. It has to be worked out.
--
-- What a file does have is consecutive frames, and between two of them the
-- answer is a subtraction rather than a search. Both ends of the motion are
-- given; the question is only which paper moved and where it went. That is what
-- makes this tractable when turning a crease pattern into a whole folding
-- sequence is not — see @docs\/notes\/no-sequence-solver.md@ for why nobody can
-- do the latter.
--
-- == Which way round the frames go
--
-- A book draws the arrow on the picture of the paper /before/ the fold: step 2
-- shows the model as it is now, with an arrow saying what to do to reach step 3.
-- So @motionsBetween before after@ describes a motion to be drawn on @before@.
--
-- == What counts as moving
--
-- A face moved if any of its vertices did. In a rigid fold that is the whole
-- answer: paper does not stretch, so a face either goes somewhere or stays
-- exactly where it was, and the only vertices it keeps are the ones on the
-- crease it turns about.
--
-- Comparing positions rather than reading fold angles is deliberate, and it is
-- the more robust of the two. A frame may record no angles at all; it may
-- record angles that disagree with its own coordinates; and a step may move
-- paper without changing any angle, by turning the whole model over. The
-- coordinates are what the reader is looking at.
--
-- == Why several motions, and not one
--
-- The moved faces are split into connected groups, and each group gets its own
-- motion. A step that folds both wings of a bird base at once moves two pieces
-- of paper in two directions, and one arrow between the two averaged together
-- would point somewhere no paper goes. Two flaps that move together are
-- connected through the paper between them and stay one group.
module Senbazuru.Origami.Step
  ( Motion (..),
    motionsBetween,
  )
where

import Data.List (sortOn)
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Senbazuru.Fold.Query (Face (..), FoldError (..), frameFaces, frameVertices)
import Senbazuru.Fold.Types (EdgeId (..), FaceId (..), Frame (..), VertexId (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace

-- | One connected piece of paper moving, and where it ends up.
--
-- 'motionFrom' and 'motionTo' are the centre of that paper before and after.
-- The centre is a blunt choice — a book starts its arrow at the edge of the
-- flap being moved, not its middle — but it is the one point that certainly
-- lies on the moving paper and certainly moves with it.
data Motion = Motion
  { -- | The faces that moved, in id order.
    motionFaces :: ![FaceId],
    -- | The creases whose fold angle changed, in id order. Empty when a frame
    -- records no angles, which does not stop the motion being real.
    motionCreases :: ![EdgeId],
    motionFrom :: !V3,
    motionTo :: !V3
  }
  deriving stock (Eq, Show)

-- | What moves between one frame and the next.
--
-- The two frames must describe the same paper: the same vertices, edges and
-- faces, differing only in where they are. That is what consecutive frames of a
-- diagram are, and a pair that disagrees about the graph is not a step but two
-- different models.
motionsBetween :: Frame -> Frame -> Either FoldError [Motion]
motionsBetween before after = do
  sameLength "vertices_coords" (length (verticesCoords before)) (length (verticesCoords after))
  sameLength "edges_vertices" (length (edgesVertices before)) (length (edgesVertices after))
  sameLength "faces_vertices" (length (facesVertices before)) (length (facesVertices after))
  from <- frameVertices before
  to <- frameVertices after
  facesBefore <- frameFaces before
  facesAfter <- frameFaces after
  let moved = movedVertices from to
      movedFaces = [f | f <- facesBefore, any ((`S.member` moved) . unVertexId) (faceVertexIds f)]
      -- Faces are matched by id, which is what "the same paper" means here:
      -- these are two states of one model, not two models that look alike.
      laterCorners f = maybe (faceCorners f) faceCorners (M.lookup (faceId f) byId)
      byId = M.fromList [(faceId f, f) | f <- facesAfter]
  pure
    [ Motion
        { motionFaces = map faceId group,
          motionCreases = creasesIn group,
          motionFrom = centre (concatMap faceCorners group),
          motionTo = centre (concatMap laterCorners group)
        }
      | group <- connectedGroups movedFaces
    ]
  where
    sameLength what a b
      | a == b = Right ()
      | otherwise = Left (FramesDiffer what a b)

    -- A vertex counts as having moved when it is further from where it was than
    -- rounding can explain, judged against the size of the sheet: a millimetre
    -- is a fold in a model a centimetre across and noise in one the size of a
    -- room.
    movedVertices from to =
      S.fromList
        [ v
          | (v, a, b) <- zip3 [0 ..] from to,
            norm (a ^-^ b) > 1e-9 * max 1 (spanOf from)
        ]

    spanOf vs = maximum (0 : [reach v3x vs, reach v3y vs, reach v3z vs])
    reach f vs = case map f vs of
      [] -> 0
      cs -> maximum cs - minimum cs

    centre [] = V3 0 0 0
    centre ps = (1 / fromIntegral (length ps)) *^ foldr (^+^) (V3 0 0 0) ps

    -- The creases this group turned about: those whose recorded angle changed
    -- and whose two endpoints both belong to a face of the group.
    creasesIn group =
      [ eid
        | (eid, angleBefore, angleAfter) <-
            zip3 (map EdgeId [0 ..]) (edgesFoldAngle before) (edgesFoldAngle after),
          angleBefore /= angleAfter,
          touches group eid
      ]

    touches group eid = case drop (unEdgeId eid) (edgesVertices before) of
      ((a, b) : _) -> any (\f -> a `elem` faceVertexIds f && b `elem` faceVertexIds f) group
      [] -> False

-- | Split faces into groups that are joined to each other through shared edges.
--
-- Restricted to the faces given, so two flaps that move together but touch only
-- through paper that stayed still come out as two groups — which is right, and
-- is the whole reason this is not one arrow per step.
connectedGroups :: [Face] -> [[Face]]
connectedGroups = go
  where
    edgesOf f = S.fromList [key a b | (a, b) <- ringEdges (faceVertexIds f)]
    key (VertexId a) (VertexId b) = (min a b, max a b)
    ringEdges vs = zip vs (drop 1 vs <> take 1 vs)

    go [] = []
    go (f : rest) =
      let (group, others) = grow [f] (edgesOf f) rest
       in group : go others

    grow acc reach candidates =
      case span (S.disjoint reach . edgesOf) candidates of
        (_, []) -> (sortOn faceId acc, candidates)
        (skipped, next : more) ->
          grow (next : acc) (S.union reach (edgesOf next)) (skipped <> more)
