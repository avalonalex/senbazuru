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
-- the more robust of the two: a frame may record no angles, or angles that
-- disagree with its coordinates. The coordinates are what the reader is
-- looking at, with one exception. When some vertex moves and one proper rigid
-- motion ('Senbazuru.Geometry.Rigid.fitRigid') maps every vertex onto the
-- next frame, nothing was folded: the reader turned the model over or round.
-- A turn-over leaves the vertices on its axis where they were, so the test
-- cannot ask that every vertex move. That pair is a presentation change, and
-- has no motion to draw an arrow for ('wholeModelMotion' says which). An
-- identical pair is not one: nothing moved.
--
-- A fold cannot pass for one. Its paper held still keeps at least three
-- corners that are not in a line where they were, so the only motion that
-- fits them is no motion at all, and the vertices that did move refuse it.
--
-- == Why several motions, and not one
--
-- The moved faces are split into connected groups, and each group gets its own
-- motion. A step that folds both wings of a bird base at once moves two pieces
-- of paper in two directions, and one arrow between the two averaged together
-- would point somewhere no paper goes. Two flaps that move together are
-- connected through the paper between them and stay one group.
--
-- == When the crease pattern grows between the frames
--
-- Subtracting two frames needs one vertex of the first to be one vertex of the
-- second, and a move that makes a crease adds vertices, so the two frames no
-- longer line up index by index. They still describe one piece of paper, and
-- what pairs them is which piece of paper each vertex /is/: its /material
-- point/, where it lay on the unfolded sheet, which folding never changes.
-- Cutting and creasing never renumber a vertex, so the later frame begins
-- with the earlier frame's vertices, at the same material points, and adds the
-- new ones after them: the /prefix rule/ (PRDs\/decisions.md, D6).
--
-- 'placeOn' puts each of the later frame's vertices where the earlier frame
-- has its paper. The vertices the two share stay where the earlier frame has
-- them. An added vertex on an earlier edge, as the sheet has it, lies that
-- far along the edge as the earlier frame shows it; one inside an earlier
-- face goes where that face's own rigid motion takes its material point,
-- found from three of the face's corners that are not in a line. A crease
-- pattern that kept its vertices but renumbered them, as another tool might
-- write it, is refused rather than drawn wrong: the prefix is compared
-- exactly, number for number.
--
-- The edge is tried before the face, and not as a shortcut. A vertex creasing
-- adds on an earlier crease lies on the boundary of the faces either side,
-- and 'insideRing' calls a point within a hair of a ring's boundary outside
-- it, so such a vertex is in no face at all.
--
-- The face that holds a material point is found by 'insideRing', which a face
-- that is not convex needs: an L-shaped face, which a crease that stops at
-- another leaves, holds points beyond the line of the edge that turns in, and
-- a half-plane test would call them outside it.
module Senbazuru.Origami.Step
  ( Motion (..),
    motionsBetween,
    wholeModelMotion,
    placeOn,
  )
where

import Control.Applicative ((<|>))
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (foldl', maximumBy, sortOn)
import Data.Map.Strict qualified as M
import Data.Ord (comparing)
import Data.Set qualified as S
import Senbazuru.Fold.Crossings (withPlanarFaces)
import Senbazuru.Fold.Faces (toleranceOf)
import Senbazuru.Fold.Query
  ( EdgeKey,
    Face (..),
    FoldError (..),
    edgeKey,
    frameFaces,
    frameVertices,
    ringEdges,
  )
import Senbazuru.Fold.Types (EdgeId (..), FaceId (..), Frame (..), VertexId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (cross2, distanceToSegment, insideRing)
import Senbazuru.Geometry.Rigid (Rigid, fitRigid)
import Senbazuru.Geometry.V3 (V3 (..), modelHair)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (Sample (..), SurfaceError (..), surfaceFromFrame, surfaceSamples)

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
--
-- A pair that differs only by a turn of the whole model, a presentation
-- change, has no motion: the paper did not fold ('wholeModelMotion').
motionsBetween :: Frame -> Frame -> Either FoldError [Motion]
motionsBetween before after = do
  sameModel before after
  from <- frameVertices before
  to <- frameVertices after
  case wholeTurn from to of
    Just _ -> pure []
    Nothing -> foldedBetween before after from to

-- | The turn of the whole model between two frames of one paper, when that is
-- all that happened: some vertex moved, and one proper rigid motion carries
-- every vertex onto its place in the second frame. That is a turn-over or a
-- turn of the page, a change of presentation, which gets no arrow; a page
-- will mark it with a symbol of its own (#36). 'Nothing' when paper folded,
-- and when nothing moved.
wholeModelMotion :: Frame -> Frame -> Either FoldError (Maybe Rigid)
wholeModelMotion before after = do
  sameModel before after
  from <- frameVertices before
  to <- frameVertices after
  pure (wholeTurn from to)

-- | The two frames describe the same paper: the same vertices, edges and
-- faces.
--
-- Compared for equality and not merely for length. Two frames with the same
-- number of faces joined up differently are two models, and matching face i to
-- face i across them would take the centre of one flap and the centre of an
-- unrelated one as the two ends of a motion.
sameModel :: Frame -> Frame -> Either FoldError ()
sameModel before after = do
  sameLength "vertices_coords" (length (verticesCoords before)) (length (verticesCoords after))
  sameContent "edges_vertices" (edgesVertices before) (edgesVertices after)
  sameContent "faces_vertices" (facesVertices before) (facesVertices after)
  where
    sameLength what a b
      | a == b = Right ()
      | otherwise = Left (FramesDiffer what a b)

    sameContent what a b
      | length a /= length b = Left (FramesDiffer what (length a) (length b))
      | otherwise = case [i | (i, x, y) <- zip3 [0 ..] a b, x /= y] of
          (i : _) -> Left (FramesDisagree what i)
          [] -> Right ()

-- | The vertices that moved between two placements of one paper: further from
-- where they were than rounding can explain, judged against the size of the
-- model. A millimetre is a fold in something a centimetre across and noise in
-- something the size of a room. 'modelHair' is the one measure of that, so
-- 'fitRigid' judges its fit by the same hair this judges a move by.
movedBetween :: [V3] -> [V3] -> S.Set Int
movedBetween from to =
  S.fromList
    [ v
      | (v, a, b) <- zip3 [0 ..] from to,
        norm (a ^-^ b) > modelHair from
    ]

-- | A turn of the whole model, if that is what moved some vertices.
wholeTurn :: [V3] -> [V3] -> Maybe Rigid
wholeTurn from to
  | S.null (movedBetween from to) = Nothing
  | otherwise = fitRigid (zip from to)

-- | The motions of a pair in which paper folded.
foldedBetween :: Frame -> Frame -> [V3] -> [V3] -> Either FoldError [Motion]
foldedBetween before after from to = do
  facesBefore <- frameFaces before
  facesAfter <- frameFaces after
  let moved = movedBetween from to
      cornersAfter = M.fromList [(faceId f, faceCorners f) | f <- facesAfter]
      movedFaces =
        [ (f, ringKeys (faceVertexIds f))
          | f <- facesBefore,
            any ((`S.member` moved) . unVertexId) (faceVertexIds f)
        ]
  pure
    [ Motion
        { motionFaces = map (faceId . fst) group,
          motionCreases = creasesIn (S.unions (map snd group)),
          motionFrom = centre (concatMap (faceCorners . fst) group),
          motionTo = centre (concatMap (laterCorners cornersAfter . fst) group)
        }
      | group <- connectedGroups movedFaces
    ]
  where
    -- Guaranteed present by the faces_vertices check above; the fallback keeps
    -- the function total rather than standing for a case that can happen.
    laterCorners byId f = M.findWithDefault (faceCorners f) (faceId f) byId

    centre [] = V3 0 0 0
    centre ps = (1 / fromIntegral (length ps)) *^ foldl' (^+^) (V3 0 0 0) ps

    -- The creases whose recorded angle changed, indexed by the pair of vertices
    -- they join, so that asking whether a group turned about one is a set
    -- lookup rather than a walk down edges_vertices per edge.
    changed =
      [ (eid, edgeKey a b)
        | (eid, (a, b), angleBefore, angleAfter) <-
            zip4
              (map EdgeId [0 ..])
              (edgesVertices before)
              (edgesFoldAngle before)
              (edgesFoldAngle after),
          angleBefore /= angleAfter
      ]

    -- Against the group's ring edges, not against the vertices it happens to
    -- contain: a crease recorded across the diagonal of a face joins two of its
    -- corners without being one of its sides, and is not a crease that face
    -- turned about.
    creasesIn ringsOf = [eid | (eid, key) <- changed, key `S.member` ringsOf]

zip4 :: [a] -> [b] -> [c] -> [d] -> [(a, b, c, d)]
zip4 (a : as) (b : bs) (c : cs) (d : ds) = (a, b, c, d) : zip4 as bs cs ds
zip4 _ _ _ _ = []

-- | The edges around a face's boundary, as unordered vertex pairs.
ringKeys :: [VertexId] -> S.Set EdgeKey
ringKeys vs = S.fromList [edgeKey a b | (a, b) <- ringEdges vs]

-- | Split faces into groups that are joined to each other through shared edges.
--
-- Restricted to the faces given, so two flaps that move together but touch only
-- through paper that stayed still come out as two groups — which is right, and
-- is the whole reason this is not one arrow per step.
connectedGroups :: [(Face, S.Set EdgeKey)] -> [[(Face, S.Set EdgeKey)]]
connectedGroups = go
  where
    go [] = []
    go (f : rest) =
      let (group, others) = grow [f] (snd f) rest
       in group : go others

    grow acc reach candidates =
      case span (S.disjoint reach . snd) candidates of
        (_, []) -> (sortOn (faceId . fst) acc, candidates)
        (skipped, next : more) ->
          grow (next : acc) (S.union reach (snd next)) (skipped <> more)

-- | Where the earlier of two frames has each of the later frame's vertices: a
-- position for every vertex of the later frame, in order, in the earlier
-- frame's coordinates. The module header has how.
--
-- Refused when either frame's material points cannot be read, the second
-- frame's refusals wrapped in 'InNextFrame'; when the later frame does not
-- begin with the earlier frame's vertices at the same material points
-- ('VerticesNotAPrefix'); and when it adds a vertex on no edge and in no face
-- of the earlier one ('AddedVertexOffPaper').
placeOn :: Frame -> Frame -> Either FoldError [V3]
placeOn earlier later = do
  (positions, materials) <- materialOf earlier
  (_, laterMaterials) <- first InNextFrame (materialOf later)
  prefixOf materials laterMaterials
  let hair = toleranceOf materials
      edges = edgesOn earlier materials positions
  faces <- facesOn earlier materials positions edges hair
  added <-
    traverse
      (\(i, m) -> maybe (Left (AddedVertexOffPaper (VertexId i))) Right (onEdge hair edges m <|> inFace hair faces m))
      (zip [length materials ..] (drop (length materials) laterMaterials))
  pure (positions <> added)

-- | A frame's vertices, where they are and where they lay on the sheet.
materialOf :: Frame -> Either FoldError ([V3], [V2])
materialOf fr = do
  surface <- first fromSurface (surfaceFromFrame fr)
  let samples = surfaceSamples surface
  materials <- maybe (Left MaterialCoordinatesMissing) Right (traverse sampleMaterial samples)
  pure (map position samples, materials)

-- | The prefix rule, number for number.
prefixOf :: [V2] -> [V2] -> Either FoldError ()
prefixOf earlier later = case [i | (i, m) <- zip [0 ..] earlier, IM.lookup i byIndex /= Just m] of
  i : _ -> Left (VerticesNotAPrefix (VertexId i))
  [] -> Right ()
  where
    byIndex = IM.fromList (zip [0 ..] later)

-- | The earlier frame's edges, each as it lies on the sheet and where the
-- frame has its two ends.
edgesOn :: Frame -> [V2] -> [V3] -> [(V2, V2, V3, V3)]
edgesOn earlier materials positions =
  [ (a, b, pa, pb)
    | (VertexId u, VertexId v) <- edgesVertices earlier,
      Just (a, pa) <- [IM.lookup u corners],
      Just (b, pb) <- [IM.lookup v corners]
  ]
  where
    corners = IM.fromList (zip [0 ..] (zip materials positions))

-- | The earlier frame's faces as rings on the sheet, each corner with where
-- the earlier frame has it. The faces the frame records, or, for a frame that
-- records none, the faces tracing its creases on the sheet gives. Tracing may
-- cut creases where they cross, adding corners the frame does not have, and
-- each of those lies on an edge of it, so it is placed along that edge.
facesOn :: Frame -> [V2] -> [V3] -> [(V2, V2, V3, V3)] -> Double -> Either FoldError [[(V2, V3)]]
facesOn earlier materials positions edges hair = do
  let onSheet = earlier {verticesCoords = [[u, v] | V2 u v <- materials]}
  traced <- if null (facesVertices earlier) then withPlanarFaces onSheet else pure onSheet
  tracedPoints <- frameVertices traced
  let sheetAt = IM.fromList (zip [0 ..] [V2 x y | V3 x y _ <- tracedPoints])
      placedAt = IM.fromList (zip [0 ..] positions)
      corner (VertexId i) = do
        p <- IM.lookup i sheetAt
        placed <- IM.lookup i placedAt <|> onEdge hair edges p
        pure (p, placed)
  pure [ring | f <- facesVertices traced, Just ring <- [traverse corner f]]

-- | A material point on an earlier edge, as the sheet has it: placed that far
-- along the edge as the earlier frame shows it.
onEdge :: Double -> [(V2, V2, V3, V3)] -> V2 -> Maybe V3
onEdge hair edges m = case [(a, b, pa, pb) | (a, b, pa, pb) <- edges, norm (b ^-^ a) > hair, distanceToSegment (a, b) m <= hair] of
  (a, b, pa, pb) : _ ->
    let t = dot (m ^-^ a) (b ^-^ a) / dot (b ^-^ a) (b ^-^ a)
     in Just (pa ^+^ (t *^ (pb ^-^ pa)))
  [] -> Nothing

-- | A material point inside an earlier face: placed where the face's own
-- motion takes it, read from the three corners of the face that span the
-- largest triangle on the sheet, the three furthest from lying in a line.
inFace :: Double -> [[(V2, V3)]] -> V2 -> Maybe V3
inFace hair faces m = case [ring | ring <- faces, insideRing hair (map fst ring) m] of
  ring : _ -> largestTriangle ring >>= through
  [] -> Nothing
  where
    through ((a, pa), (b, pb), (c, pc))
      | abs d <= hair * hair = Nothing
      | otherwise = Just (((1 - lb - lc) *^ pa) ^+^ (lb *^ pb) ^+^ (lc *^ pc))
      where
        d = cross2 (b ^-^ a) (c ^-^ a)
        lb = cross2 (m ^-^ a) (c ^-^ a) / d
        lc = cross2 (b ^-^ a) (m ^-^ a) / d
    largestTriangle ring = case [(x, y, z) | (i, x) <- zip [0 :: Int ..] ring, (j, y) <- zip [0 ..] ring, j > i, (k, z) <- zip [0 ..] ring, k > j] of
      [] -> Nothing
      triangles -> Just (maximumBy (comparing area) triangles)
    area ((a, _), (b, _), (c, _)) = abs (cross2 (b ^-^ a) (c ^-^ a))

-- | A frame's surface could not be read, as a 'FoldError'. Reading a frame
-- ('surfaceFromFrame') gives only the first five; the rest come from
-- building or refining a surface, which reading never does, and are mapped to
-- the nearest reading error so that the function is total. Each is named
-- rather than caught by a wildcard, so a constructor added to 'SurfaceError'
-- is a warning here.
fromSurface :: SurfaceError -> FoldError
fromSurface = \case
  SurfaceFrameError err -> err
  SurfaceNonFinite v -> VertexNotFinite v
  SurfaceInvalidMaterialCoordinates -> MaterialCoordinatesUnreadable
  SurfaceMaterialCount vertices points -> MaterialCoordinatesCount vertices points
  SurfaceInvalidMaterialPoint v -> MaterialPointInvalid v
  -- Reading leaves a point it does not know as Nothing, which 'materialOf'
  -- refuses; only requiring the points refuses it as this.
  SurfaceMissingMaterial _ -> MaterialCoordinatesMissing
  -- Reading checks the counts before building, so the two never disagree.
  SurfaceMaterialMismatch -> MaterialCoordinatesUnreadable
  SurfaceMaterialNotFlat v -> MaterialPointInvalid v
  SurfaceBadThickness _ -> MaterialCoordinatesUnreadable
  SurfaceBadDirection _ -> MaterialCoordinatesUnreadable
  SurfaceBadLayerPair _ _ -> MaterialCoordinatesUnreadable
  SurfaceBadRefinement _ -> MaterialCoordinatesUnreadable
  SurfaceUnknownRefinementPanel _ -> MaterialCoordinatesUnreadable
  SurfaceNonConvex _ -> MaterialCoordinatesUnreadable
  SurfaceNonPlanar _ -> MaterialCoordinatesUnreadable
  SurfaceDegenerateFan _ -> MaterialCoordinatesUnreadable
  SurfaceJoinedCut _ -> MaterialCoordinatesUnreadable
  SurfaceMissingVertex v -> VertexNotFinite v
