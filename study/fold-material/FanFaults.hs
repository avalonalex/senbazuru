-- | What fanning a flat figure gets wrong, measured before the drawing that
-- fans it is designed (S9 of #637).
--
-- == What fanning is
--
-- A flat-folded model has its layers lying exactly on one another, so a
-- figure that draws each layer where it lies shows the stack as one outline.
-- /Fanning/ (06 §10, owner decisions 65 and 66) moves every vertex toward the
-- page's lower left by 1.5 page units for each sheet over it, counting at most
-- 6: its fan count, from 'fanCounts'. The paper on top stays where it lies,
-- folds stay joined, and the edges underneath peek out. Terms are in
-- @docs/glossary.md@.
--
-- Nothing in the library fans a figure yet: #639 builds the shape that carries
-- a move per point and #644 draws with it. This module measures what the rule
-- would get wrong, so that those two are designed knowing it. The pieces of
-- the rule that have no home yet are local copies here: the move itself
-- ('fanMove'); R-06-27's move for a point partway along a face edge, its two
-- ends' moves mixed by where it lies; and the painter's covering, a face
-- painted in a later layer covering what lies under it. The counts and the
-- stretches come from "Senbazuru.Origami.Visible" and the page scale from
-- "Senbazuru.Diagram.Page".
--
-- == Why everything is measured on the page
--
-- A fan move is a fixed length on the page, while the figure is drawn at
-- whatever scale its page gives it. So a fault depends on the scale: a move of
-- 9 page units is nothing beside a face 100 units across and turns a face 5
-- units across inside out. Every position here is a page point: the camera's
-- projection of the model point, times the scale @s@ in page units per model
-- unit, with y negated, because model y grows up the page and page y grows
-- down it. The fan direction, (−1, +1)/√2, is in those page axes: left and
-- down. The offset of a real page is left out, since every fault here compares
-- two points of one figure.
--
-- == The faults
--
-- * A face drawn /inside out/: its fanned ring is simple and winds the other
--   way from its true ring. Every move points the same way, so the fanned
--   area is exactly @s² A₀ + s B@, a quadratic with no constant term, and the
--   ring winds the other way below one scale, @−B / A₀@ ('insideOutBelow'). A
--   face whose fanned ring /crosses itself/ is counted as that instead, since
--   a crossed ring's winding means nothing. \"Inside out\" rather than
--   \"turned over\", which already names a whole-model move.
--
-- * A /line that stops short/. A stretch is a visible piece of an edge; where
--   its edge runs on under a nearer face, the stretch ends at that face's edge.
--   Fanned, the end moves with its own edge and the face with its own corners,
--   so the two can come apart, and the full-weight line stops short of the
--   paper it met. An end that moves /into/ the nearer face is no fault on the
--   painter fanning shares with the offset view (06 R-06-27), which paints a
--   layer's faces after the layers below it and so covers the overrun.
--
-- * /Moved visible paper/: the points of a face's visible boundary that move,
--   and how far. A fold-here line, the line a figure draws to say \"fold
--   here\", drawn on true positions sits that far from the paper it marks. The
--   face /leans/ when those moves differ.
--
-- * A /fold drawn as a border/: a stretch drawn at border weight whose named
--   edge is a fold, because a buried sheet's border lies along it. Fanned, the
--   border moves with its own sheet, which is the mismatch measured.
--
-- * A /hinge move/: how far the paper under a fold's hinge moves on the figure
--   before that fold, where owner decision 74 draws the fold-here line.
--
-- == What this does not do
--
-- Points inside a face are not moved: R-06-27 gives a fanned position only to
-- points on a face's edges. A stretch with no named edge ('sheetEdgeSpan' is
-- 'Nothing') has no fanned position and is left out. Only flat figures: a
-- figure with paper in the air is drawn unfanned (R-06-26).
module FanFaults
  ( -- * The rule fanning follows
    fanStep,
    fanCap,
    fanDirection,
    fanMove,
    noticeable,

    -- * A figure, as one page draws it
    Figure (..),
    figureOf,
    pagePoint,
    fannedPoint,

    -- * Faults that change with the figure's size
    FaceShape (..),
    faceShapeAt,
    insideOutBelow,
    MetEnd (..),
    metEnds,
    gapAt,

    -- * Faults of a fixed size on the page
    MovedPaper (..),
    movedPaper,
    BorderFold (..),
    borderDrawnFolds,
    foldsAlongBorder,
    HingeMove (..),
    hingeMoves,
  )
where

import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (nub, sort)
import Data.Maybe (isJust, mapMaybe)
import Data.Text (Text)
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Query (Face (..), frameFaces, frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (collinearOverlap, cross2, distanceToSegment, insideRing, segmentsCross, signedArea)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Flat (Sheet (..), flatSheet)
import Senbazuru.Origami.Layers (layerDepths, layerOf)
import Senbazuru.Origami.Visible
import Senbazuru.Render.Camera (Basis, SeenFrom (..), basisForward, project, seenFrom)

-- | Page units a vertex moves for each sheet over it (06 R-06-25, a SKETCH
-- value chosen by C121, not the owner).
fanStep :: Double
fanStep = 1.5

-- | The most sheets a move counts (R-06-25, also C121's).
fanCap :: Int
fanCap = 6

-- | Toward the page's lower left, in page axes, where y grows down the page.
fanDirection :: V2
fanDirection = (1 / sqrt 2) *^ V2 (-1) 1

-- | How far a vertex under this many sheets moves on the page.
fanMove :: Int -> V2
fanMove count = (fanStep * fromIntegral (min fanCap count)) *^ fanDirection

-- | A move or a gap under a millionth of a page unit is rounding, not a fault:
-- a point found on an edge a hair from its corner takes a hair of that
-- corner's neighbour's move.
noticeable :: Double
noticeable = 1e-6

-- | A flat figure, seen through one camera, with what every fault reads.
data Figure = Figure
  { figureFrame :: !Frame,
    figureBasis :: !Basis,
    -- | Whether the camera sees the @+z@ side, which is the side the counts,
    -- the visible paper and the stretches are taken from.
    figureFromAbove :: !Bool,
    -- | Each vertex's fan count, by vertex id.
    figureCounts :: !(IM.IntMap Int),
    figurePositions :: !(IM.IntMap V3),
    figureFaces :: ![Face],
    figureForm :: !VisibleForm,
    -- | The layer each face is painted in, nearest the camera last, as the
    -- offset view's painter takes them.
    figureLayers :: ![(FaceId, Int)],
    -- | The flat sheet's length tolerance, in model units.
    figureHair :: !Double
  }

-- | Read a flat frame through a camera, or say why it cannot be fanned.
figureOf :: Basis -> Frame -> Either Text Figure
figureOf basis fr = do
  sheet <- first explain (flatSheet fr)
  counts <- first explain (fanCounts fromAbove fr (faceOrders fr))
  verts <- first explain (frameVertices fr)
  faces <- first explain (frameFaces fr)
  form <- first explain (visibleForm fromAbove fr (faceOrders fr))
  layers <- first explain (layerDepths ((-1) *^ basisForward basis) faces (faceOrders fr))
  pure
    Figure
      { figureFrame = fr,
        figureBasis = basis,
        figureFromAbove = fromAbove,
        figureCounts = IM.fromList [(i, c) | (VertexId i, c) <- counts],
        figurePositions = IM.fromList (zip [0 ..] verts),
        figureFaces = faces,
        figureForm = form,
        figureLayers = layers,
        figureHair = sheetHair sheet
      }
  where
    fromAbove = seenFrom basis /= FromOppositeSide

-- | A model point on a page drawn at @s@ page units per model unit, with y
-- negated, the page's offset left out.
pagePoint :: Figure -> Double -> V3 -> V2
pagePoint fig s p = let V2 x y = project (figureBasis fig) p in V2 (s * x) (negate (s * y))

positionOf :: Figure -> VertexId -> V3
positionOf fig (VertexId v) = IM.findWithDefault (V3 0 0 0) v (figurePositions fig)

countOf :: Figure -> VertexId -> Int
countOf fig (VertexId v) = IM.findWithDefault 0 v (figureCounts fig)

-- | Where a vertex is drawn once fanned.
fannedPoint :: Figure -> Double -> VertexId -> V2
fannedPoint fig s v = pagePoint fig s (positionOf fig v) ^+^ fanMove (countOf fig v)

truePoint :: Figure -> Double -> VertexId -> V2
truePoint fig s v = pagePoint fig s (positionOf fig v)

-- | How far a vertex moves, in page units. Every move is along 'fanDirection',
-- so a point partway along an edge moves by the same fraction of the way
-- between its ends' moves.
moveOf :: Figure -> VertexId -> Double
moveOf fig v = fanStep * fromIntegral (min fanCap (countOf fig v))

-- | What becomes of a face's ring once fanned.
data FaceShape
  = -- | Still winds the way it did.
    Kept
  | -- | Simple, but winds the other way: the paper is drawn from its back.
    InsideOut
  | -- | Two of its sides cross, or one folds back along its neighbour.
    CrossesItself
  | -- | Fewer than three distinct corners are left.
    Collapsed
  deriving stock (Eq, Ord, Show)

-- | The shape of a face's fanned ring at a scale. A crossed ring is reported as
-- crossed whatever its area says, since its winding means nothing.
faceShapeAt :: Figure -> Double -> Face -> FaceShape
faceShapeAt fig s face
  | length fanned < 3 = Collapsed
  | crosses tolerance fanned = CrossesItself
  | signedArea fanned * signedArea true < 0 = InsideOut
  | otherwise = Kept
  where
    tolerance = s * figureHair fig
    true = map (truePoint fig s) (faceVertexIds face)
    fanned = withoutRepeats tolerance (map (fannedPoint fig s) (faceVertexIds face))

-- | Consecutive corners within the tolerance are one corner, the last and the
-- first included.
withoutRepeats :: Double -> [V2] -> [V2]
withoutRepeats tolerance = closeUp . go
  where
    go (a : b : rest)
      | norm (b ^-^ a) <= tolerance = go (a : rest)
      | otherwise = a : go (b : rest)
    go rest = rest
    closeUp ps = case ps of
      a : _ : _ | norm (last ps ^-^ a) <= tolerance -> init ps
      _ -> ps

-- | Two sides cross, or overlap along one line by more than the tolerance,
-- which is how a side folding back along its neighbour shows: 'segmentsCross'
-- cannot see it, since the two never straddle each other.
crosses :: Double -> [V2] -> Bool
crosses tolerance ring =
  or
    [ apart || overlapping
      | (i, e1) <- sides,
        (j, e2) <- sides,
        i < j,
        let adjacent = j == i + 1 || (i == 0 && j == n - 1)
            apart = not adjacent && segmentsCross tolerance e1 e2
            overlapping = isJust (collinearOverlap tolerance e1 e2)
    ]
  where
    sides = zip [0 :: Int ..] (zip ring (drop 1 ring <> take 1 ring))
    n = length sides

-- | The scale below which a face's fanned ring winds the other way from its
-- true one, if there is one. Below it the face is drawn inside out unless its
-- ring also crosses itself there, which 'faceShapeAt' asks at a given scale:
-- the crane's face 20, seen from below, crosses itself on both sides of its
-- scale.
--
-- The fanned area is @s² A₀ + s B@: @A₀@ is the true ring's area at one page
-- unit per model unit, and @B@ is what the moves add, which grows with @s@
-- only once because every move points the same way (the moves alone enclose
-- nothing). So the area changes sign at @s = −B / A₀@, and only where @B@ and
-- @A₀@ have opposite signs.
--
-- @B@ is taken directly, as half the sum over the corners of each corner's
-- move times the cross product of 'fanDirection' with the line from the
-- corner before it to the corner after, rather than as the fanned area less
-- the true one, which would subtract two nearly equal numbers. Where the moves
-- add no area, @B@ is rounding: a face whose corners all move alike only
-- slides, and one whose one moving corner travels along the line through its
-- neighbours is only sheared. Such a face has no scale. @B@ counts as nothing
-- when it is under a billionth, as a hair is, of the most the moves could add,
-- half the sum of each corner's move times that line's length.
insideOutBelow :: Figure -> Face -> Maybe Double
insideOutBelow fig face
  | a0 == 0 = Nothing
  | abs b <= 1e-9 * most = Nothing
  | threshold > 0 = Just threshold
  | otherwise = Nothing
  where
    corners = map (truePoint fig 1) (faceVertexIds face)
    moves = map (moveOf fig) (faceVertexIds face)
    -- The line from the corner before each corner to the corner after it.
    across = zipWith (^-^) (drop 1 corners <> take 1 corners) (take (length corners) (drop (length corners - 1) (corners <> corners)))
    a0 = signedArea corners
    b = 0.5 * sum (zipWith (\m d -> m * cross2 fanDirection d) moves across)
    most = 0.5 * sum (zipWith (\m d -> m * norm d) moves across)
    threshold = negate b / a0

-- | An end of a stretch where the stretch's edge runs on under a nearer face.
data MetEnd = MetEnd
  { -- | The face whose edge the stretch is.
    metSheet :: !FaceId,
    -- | The nearer faces whose edge the stretch ends at, and which cover the
    -- edge's continuation.
    metCovers :: ![FaceId],
    metSpan :: !EdgeSpan,
    -- | The end's fraction along the named edge, from 'spanFrom'.
    metFraction :: !Double,
    -- | Which way along the named edge the line runs on past the end: 1
    -- toward 'spanTo', −1 toward 'spanFrom'.
    metOutward :: !Double
  }
  deriving stock (Eq, Show)

-- | Every end of every stretch where its edge runs on under a nearer face.
--
-- An end counts when it is strictly inside its named edge, so the edge goes
-- on past it, and some face painted in a later layer than the stretch's own
-- face has the end on its boundary and covers the point just past it. Ends at
-- an edge's corner, and ends where only the face beside the stretch changes,
-- have nothing to come apart from.
metEnds :: Figure -> [MetEnd]
metEnds fig =
  [ MetEnd f covers sp t outward
    | e <- formSheetEdges (figureForm fig),
      Just f <- [sheetEdgeFace e],
      Just sp <- [sheetEdgeSpan e],
      (t, outward) <- [(spanStart sp, signum (spanStart sp - spanEnd sp)), (spanEnd sp, signum (spanEnd sp - spanStart sp))],
      t > edgeHair sp,
      t < 1 - edgeHair sp,
      let a = truePoint fig 1 (spanFrom sp)
          b = truePoint fig 1 (spanTo sp)
          at = a ^+^ (t *^ (b ^-^ a))
          beyond = a ^+^ ((t + outward * 1000 * hair / norm (b ^-^ a)) *^ (b ^-^ a))
          covers =
            [ faceId g
              | g <- figureFaces fig,
                faceId g /= f,
                layerOf (figureLayers fig) (faceId g) > layerOf (figureLayers fig) f,
                let ring = map (truePoint fig 1) (faceVertexIds g),
                onBoundary ring at,
                insideRing hair ring beyond
            ],
      not (null covers)
  ]
  where
    hair = figureHair fig
    edgeHair sp = hair / max hair (norm (truePoint fig 1 (spanTo sp) ^-^ truePoint fig 1 (spanFrom sp)))
    onBoundary ring x = any (\side -> distanceToSegment side x <= 10 * hair) (sidesOf ring)

sidesOf :: [a] -> [(a, a)]
sidesOf ps = zip ps (drop 1 ps <> take 1 ps)

-- | How far the full-weight line falls short of the paper it met, on the page
-- at a scale: the length of the named edge, from the fanned end on past it,
-- that no face painted after the stretch's own face covers, up to the next
-- point where one does, or the edge's own end if none ever does. 0 where the
-- fanned end itself is under such paper, which covers the line. Measured
-- along the edge, not as the end's distance from that paper, which is
-- shorter wherever the edge meets the paper's side at a slant.
gapAt :: Figure -> Double -> MetEnd -> Double
gapAt fig s end = case [(lo, hi) | (lo, hi) <- zip cuts (drop 1 cuts), covered (along ((lo + hi) / 2))] of
  (lo, _) : _ -> lo * norm (far ^-^ at)
  [] -> norm (far ^-^ at)
  where
    sp = metSpan end
    a = fannedPoint fig s (spanFrom sp)
    b = fannedPoint fig s (spanTo sp)
    at = a ^+^ (metFraction end *^ (b ^-^ a))
    far = if metOutward end > 0 then b else a
    along u = at ^+^ (u *^ (far ^-^ at))
    later = [map (fannedPoint fig s) (faceVertexIds g) | g <- figureFaces fig, layerOf (figureLayers fig) (faceId g) > layerOf (figureLayers fig) (metSheet end)]
    covered x = any (\ring -> insideRing 0 ring x) later
    -- Where the line from the end to the edge's end crosses a side of any of
    -- that paper: between two such crossings it is covered all the way or
    -- not at all, which the midpoint tells.
    cuts = sort (nub ([0, 1] <> [u | ring <- later, side <- sidesOf ring, Just u <- [crossing side]]))
    crossing (p, q) =
      let d = far ^-^ at
          e = q ^-^ p
          denom = cross2 d e
          u = cross2 (p ^-^ at) e / denom
          v = cross2 (p ^-^ at) d / denom
       in if denom /= 0 && u > 0 && u < 1 && v >= 0 && v <= 1 then Just u else Nothing

-- | How far a face's visible boundary moves.
data MovedPaper = MovedPaper
  { movedFace :: !FaceId,
    -- | The largest move, in page units, of a corner of the face's visible
    -- paper lying on the face's own ring.
    movedMost :: !Double,
    -- | The smallest such move. The face leans where the two differ.
    movedLeast :: !Double
  }
  deriving stock (Eq, Show)

-- | Every face with visible paper that fanning moves, and how far.
--
-- The corners of a face's visible pieces that lie on its own ring are the ends
-- of the uncovered stretches of its boundary, and a move that varies linearly
-- along an edge is largest at one of them. Corners inside the face are left
-- out, since R-06-27 moves only points on a face's edges.
movedPaper :: Figure -> [MovedPaper]
movedPaper fig =
  [ MovedPaper fid (maximum moves) (minimum moves)
    | fid <- nub [regionFace r | r <- formRegions (figureForm fig)],
      Just face <- [lookup fid [(faceId x, x) | x <- figureFaces fig]],
      let corners = [project (figureBasis fig) p | r <- formRegions (figureForm fig), regionFace r == fid, piece <- regionPieces r, p <- piece]
          sides = [((u, w), (planar u, planar w)) | (u, w) <- sidesOf (faceVertexIds face)]
          moves =
            [ (1 - t) * moveOf fig u + t * moveOf fig w
              | x <- corners,
                ((u, w), (p, q)) <- sides,
                norm (q ^-^ p) > hair,
                distanceToSegment (p, q) x <= hair,
                let t = max 0 (min 1 (dot (x ^-^ p) (q ^-^ p) / dot (q ^-^ p) (q ^-^ p)))
            ],
      not (null moves),
      maximum moves > noticeable
  ]
  where
    hair = figureHair fig
    planar = project (figureBasis fig) . positionOf fig

-- | A stretch drawn at border weight whose named edge is a fold.
data BorderFold = BorderFold
  { borderFoldSheet :: !(Maybe FaceId),
    borderFoldSpan :: !EdgeSpan,
    -- | The largest difference, in page units, between the fold's move and the
    -- move of the buried border it lies along, at the stretch's two ends.
    borderFoldMismatch :: !Double
  }
  deriving stock (Eq, Show)

-- | Every stretch drawn 'Border' whose named edge is a mountain or valley fold.
-- A stretch takes the strongest assignment of the creases under it, so a fold
-- lying along a buried sheet's border is drawn as the border; once fanned, the
-- border moves with its own sheet and the fold with its own.
borderDrawnFolds :: Figure -> [BorderFold]
borderDrawnFolds fig =
  [ BorderFold (sheetEdgeFace e) sp (maximum (0 : mismatches sp))
    | e <- formSheetEdges (figureForm fig),
      visibleAssignment (sheetEdgeLine e) == Border,
      Just sp <- [sheetEdgeSpan e],
      Just a <- [assignmentOf (spanFrom sp, spanTo sp)],
      a `elem` [Mountain, Valley]
  ]
  where
    fr = figureFrame fig
    hair = figureHair fig
    planar = project (figureBasis fig) . positionOf fig
    assignmentOf (u, w) = case [a | ((p, q), a) <- zip (edgesVertices fr) (edgesAssignment fr), (p, q) == (u, w) || (p, q) == (w, u)] of
      a : _ -> Just a
      [] -> Nothing
    borders = [(u, w) | ((u, w), Border) <- zip (edgesVertices fr) (edgesAssignment fr)]
    mismatches sp =
      [ abs (alongFold - alongBorder)
        | t <- [spanStart sp, spanEnd sp],
          let p = planar (spanFrom sp)
              q = planar (spanTo sp)
              x = p ^+^ (t *^ (q ^-^ p))
              alongFold = (1 - t) * moveOf fig (spanFrom sp) + t * moveOf fig (spanTo sp),
          (u, w) <- borders,
          let bu = planar u
              bw = planar w,
          norm (bw ^-^ bu) > hair,
          distanceToSegment (bu, bw) x <= hair,
          -- A border that only ends at the stretch's end, at an angle to the
          -- fold, is not the border the fold is drawn as.
          isJust (collinearOverlap hair (p, q) (bu, bw)),
          let s = dot (x ^-^ bu) (bw ^-^ bu) / dot (bw ^-^ bu) (bw ^-^ bu)
              alongBorder = (1 - s) * moveOf fig u + s * moveOf fig w
      ]

-- | The folds that lie wholly along a border edge, whether or not they are
-- visible, and how many folds there are: mountain and valley edges alike.
foldsAlongBorder :: Figure -> ([EdgeId], Int)
foldsAlongBorder fig = (along, length folds)
  where
    fr = figureFrame fig
    hair = figureHair fig
    planar = project (figureBasis fig) . positionOf fig
    folds = [(EdgeId i, (u, w)) | (i, ((u, w), a)) <- zip [0 ..] (zip (edgesVertices fr) (edgesAssignment fr)), a `elem` [Mountain, Valley]]
    borders = [(planar u, planar w) | ((u, w), Border) <- zip (edgesVertices fr) (edgesAssignment fr)]
    along =
      [ i
        | (i, (u, w)) <- folds,
          let p = planar u
              q = planar w,
          norm (q ^-^ p) > hair,
          any (\side -> distanceToSegment side p <= hair && distanceToSegment side q <= hair) borders
      ]

-- | How far the paper under one hinge edge moves on the figure before its fold.
data HingeMove = HingeMove
  { hingeEdge :: !EdgeId,
    -- | Whether a stretch names the edge, so that it is drawn at full weight.
    hingeVisible :: !Bool,
    -- | The larger of its two ends' moves, in page units.
    hingeMost :: !Double,
    -- | The same, square to the hinge: how far a fold-here line drawn on true
    -- positions sits from the moved edge.
    hingeSquare :: !Double
  }
  deriving stock (Eq, Show)

-- | The moves under a fold's hinge edges, on the figure drawn before the fold.
hingeMoves :: Figure -> [EdgeId] -> [HingeMove]
hingeMoves fig = mapMaybe one
  where
    fr = figureFrame fig
    named = [(spanFrom sp, spanTo sp) | e <- formSheetEdges (figureForm fig), Just sp <- [sheetEdgeSpan e]]
    one (EdgeId i) = case drop i (edgesVertices fr) of
      (u, w) : _ ->
        let p = truePoint fig 1 u
            q = truePoint fig 1 w
            sine = if norm (q ^-^ p) > 0 then abs (cross2 ((1 / norm (q ^-^ p)) *^ (q ^-^ p)) fanDirection) else 0
            most = max (moveOf fig u) (moveOf fig w)
         in Just (HingeMove (EdgeId i) ((u, w) `elem` named || (w, u) `elem` named) most (most * sine))
      [] -> Nothing
