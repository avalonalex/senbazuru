-- |
-- Module      : Senbazuru.Origami.Visible
-- Description : What of a flat-folded model can actually be seen.
--
-- A folded model is opaque and overlaps itself, so a picture of one shows less
-- than it contains. This module works out how much less: which patch of which
-- face the viewer can see, which side of the paper is looking back, and which
-- stretches of which edges are not buried under a layer.
--
-- It answers a question "Senbazuru.Origami.Layers" cannot. That module sorts
-- whole faces into a back-to-front order and lets a renderer paint them one
-- after another, which is the right thing to do when such an order exists.
-- Twice it does not:
--
-- * __A twist has no such order.__ The flaps of a square twist lie A over B
--   over C over A. That is not a contradiction — no point of the paper is
--   under all three at once, so nothing has to pass through anything — but
--   there is no single order to paint four flaps in, and painting faces whole
--   is the only thing that needs one.
--
-- * __An order does not hide anything.__ Painting every face and then every
--   edge draws the creases of layers buried ten deep, and says nothing about
--   which side of the sheet each patch of paper is showing. Neither is what a
--   book prints.
--
-- Both go away if the drawing is made of what is /visible/ rather than of what
-- is /there/.
--
-- == The regions
--
-- The visible part of a face is what is left of it once everything nearer the
-- viewer has been taken away:
--
-- > visible f = f minus every face nearer the viewer that overlaps it
--
-- That is the whole definition, and it is worth seeing why it is enough. Over
-- any single point of the page, the faces covering that point are totally
-- ordered — this is exactly the situation the layer solver's @Acyclic@ rule
-- covers, three faces with a patch of paper in common — so exactly one of them
-- is on top there. The point therefore belongs to that face's visible part and
-- to no other, and the visible parts of all the faces tile the model's
-- silhouette with no gaps and no overlaps. A cycle among three faces is no
-- obstacle because no point is under the whole cycle.
--
-- The usual way to compute this is to overlay every face, cut the plane into
-- cells at every crossing, find each cell's top face, and glue neighbouring
-- cells back together when they agree — which needs a planar arrangement, a
-- half-edge structure and a rule for matching a hole to the ring around it.
-- The subtraction above lands on the same regions with none of that, and it
-- lands on them already grouped by which face is on top.
--
-- == Why the subtraction stays convex
--
-- A face minus another face is not convex, so a region is kept as a handful of
-- convex pieces rather than one ring, and 'Senbazuru.Geometry.Polygon.subtractConvex'
-- is what produces them: taking away a convex shape is one half-plane clip per
-- edge of it, and nothing else. Everything here therefore stays inside the
-- convex clipping the rest of the project already uses, and the faces have to
-- be convex — which "Senbazuru.Origami.Flat" is where senbazuru insists on.
--
-- A region can genuinely have a hole, when a flap lands in the middle of a
-- larger face, and pieces express that without anyone having to notice: the
-- ring around the hole simply arrives as four pieces rather than one.
--
-- == The edges
--
-- An edge is visible where the paper differs across it, and hidden where it
-- does not. So each edge is cut at every point where a face boundary crosses
-- it, and each of the resulting stretches is kept only if the topmost face
-- along one side of it is not the topmost face along the other. A crease with
-- another layer over the top of it has the same face on both sides and goes;
-- the outline of that layer has paper on one side and nothing on the other and
-- stays.
--
-- The cutting is done a line at a time rather than an edge at a time, and that
-- is not an optimisation. A flat-folded model is full of edges that land
-- exactly on top of one another — fold a square into quarters and all eight of
-- its boundary edges land on four lines — and cutting each edge separately
-- gives coincident stretches that agree geometrically and differ in the last
-- bits of their coordinates. Gathering the collinear edges into one 'Track'
-- first means such stretches are literally the same interval of the same line,
-- and the eight edges of the quarter fold come back as four.
--
-- == What this does not do
--
-- Only models folded flat, for the reason "Senbazuru.Origami.Flat" gives.
-- Nothing here knows about drawing: a region says which face and which side of
-- the paper is showing, which are facts about paper, and what a picture makes
-- of them is somebody else\'s business.
--
-- And 'regionTopSide' is a guess in one case, worth knowing about because it is
-- silent. It is read from the winding the file wrote, and a file that wound
-- every face backwards /and/ negated every @faceOrders@ sign describes the same
-- model: the two wrongs cancel for the layer order, since the signs were
-- written against those windings, and there is nothing for them to cancel
-- against here. Such a file comes out with its two sides of paper the wrong way
-- round, and no test on the geometry can tell. Frames from
-- "Senbazuru.Origami.Folding" are not like that — it writes its faces
-- anticlockwise on purpose.
module Senbazuru.Origami.Visible
  ( -- * What can be seen
    VisibleForm (..),
    Region (..),
    VisibleEdge (..),
    visibleForm,
  )
where

import Control.Monad (foldM)
import Data.List (foldl', sort)
import Data.Map.Strict qualified as M
import Senbazuru.Fold.Query (Crease (..), FoldError (..))
import Senbazuru.Fold.Types
  ( Assignment (..),
    FaceId,
    FaceOrder (..),
    Frame,
    Stacking (..),
    VertexId (..),
  )
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon
  ( centroid,
    clipConvex,
    cross2,
    distanceOutside,
    signedArea,
    subtractConvex,
  )
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Flat (FlatError (..), Panel (..), Sheet (..), flatSheet, vertexAt)

-- | The part of one face the viewer can see.
--
-- Empty regions are not reported: a face buried under others contributes
-- nothing to the picture and does not appear at all.
data Region = Region
  { -- | The face this is the visible part of.
    regionFace :: !FaceId,
    -- | Whether the side of the paper facing the viewer here is the sheet's
    -- __top__ side — the one a crease pattern is drawn on. Origami paper is
    -- usually one thing on the top side and another underneath, and a flap
    -- folded over shows its underside; this is which of the two the viewer is
    -- looking at.
    regionTopSide :: !Bool,
    -- | Convex pieces, anticlockwise, which together are the region and do not
    -- overlap one another. Points in space, at the plane the model lies in, so
    -- that a camera projects them exactly as it projects everything else.
    regionPieces :: ![[V3]]
  }
  deriving stock (Eq, Show)

-- | A stretch of an edge that is not hidden behind a layer.
--
-- Not an edge of the file: one edge may come back as several stretches, or as
-- none, and several edges that landed on the same line come back as one. The
-- assignment is the strongest of those that lie along it, which is why the
-- outline of a folded model reads as the edge of the paper even where a crease
-- landed exactly on it.
data VisibleEdge = VisibleEdge
  { visibleAssignment :: !Assignment,
    visibleFrom :: !V3,
    visibleTo :: !V3
  }
  deriving stock (Eq, Show)

-- | Everything a drawing of a flat-folded model is made of.
data VisibleForm = VisibleForm
  { formRegions :: ![Region],
    formEdges :: ![VisibleEdge],
    -- | The same stretches, cut wherever the sheet behind them changes, and
    -- each labelled with that sheet: the face whose paper lies nearest the
    -- viewer along it, or 'Nothing' where there is paper on neither side.
    --
    -- A second cut of one answer rather than a second answer. A stretch is not
    -- an edge /of/ one face — it is the line between whatever is on its two
    -- sides — so a drawing that keeps every sheet in its place, as an ordinary
    -- picture does, never has to ask which sheet a stretch belongs to, and
    -- 'formEdges' is deliberately joined up across the boundaries where it
    -- changes. A drawing that /moves/ the sheets apart does have to ask, and
    -- gets a stretch per sheet here.
    formSheetEdges :: ![(Maybe FaceId, VisibleEdge)]
  }
  deriving stock (Eq, Show)

-- | What can be seen of a flat-folded frame, from one side of it.
--
-- @visibleForm fromAbove frame orders@. The first argument says which side of
-- the model's plane the viewer is on: 'True' for the @+z@ side, which is where
-- 'Senbazuru.Render.Camera.topDown' looks from. Turning it over is the whole
-- of \"look at the underside\", and it flips both which face wins over which
-- and which side of the paper each shows.
--
-- The @faceOrders@ are the caller's, exactly as "Senbazuru.Origami.Layers"
-- takes them: read from the file when it has some, or worked out by
-- "Senbazuru.Origami.Stacking" when it has none. A pair of faces with no entry
-- is left alone, because that is how FOLD says two faces do not overlap.
visibleForm :: Bool -> Frame -> [FaceOrder] -> Either FlatError VisibleForm
visibleForm fromAbove fr orders = do
  sheet <- flatSheet fr
  nearer <- nearness fromAbove sheet orders
  let shown = shownStretches sheet nearer
  pure
    VisibleForm
      { formRegions = regionsOf fromAbove sheet nearer,
        formEdges = edgesOf shown,
        formSheetEdges = sheetEdgesOf shown
      }

-- | \"Is the first face nearer the viewer than the second?\", from
-- @faceOrders@.
--
-- Two sign conventions meet here and both have to be got right.
--
-- FOLD says @f@ is above @g@ meaning __on the side @g@'s normal points to__,
-- and a face's normal is defined by the order its corners are listed in. So
-- \"above\" is the @+z@ side when @g@ lies top-up and the @-z@ side when it
-- lies top-down: 'panelFaceUp' is exactly that question, read off the winding
-- the file wrote and never recomputed.
--
-- Then \"the @+z@ side\" is nearer the viewer only if the viewer is up there.
-- Miss that and a model looked at from underneath comes out inside out, which
-- is a convincing picture of a different model.
--
-- Every pair is recorded both ways round, so the caller never has to remember
-- which way it asked. An unrecorded pair answers 'False' both ways, which is
-- right: FOLD leaves out exactly the pairs that do not overlap, and neither of
-- those can hide the other.
--
-- A pair recorded twice, disagreeing with itself, is refused
-- ('ContradictoryStacking'). That is as far as checking goes here, and it is
-- worth saying what is /not/ checked: a circle running through three faces that
-- all share a patch of paper is a real contradiction and passes this. Each of
-- the three then loses the shared patch to the other two and the model comes
-- out with a hole in it. Nothing senbazuru produces can be like that —
-- "Senbazuru.Origami.Stacking" rules exactly that out before it answers — so it
-- would take a file that contradicts itself in a way one pair at a time cannot
-- show.
nearness ::
  Bool ->
  Sheet ->
  [FaceOrder] ->
  Either FlatError (FaceId -> FaceId -> Bool)
nearness fromAbove sheet orders = do
  entries <- concat <$> traverse entry orders
  known <- foldM record M.empty entries
  pure (\f g -> M.findWithDefault False (f, g) known)
  where
    record known (fg@(f, g), v) = case M.lookup fg known of
      Just settled | settled /= v -> Left (FlatRefused (ContradictoryStacking f g))
      _ -> Right (M.insert fg v known)

    faceUp = M.fromList [(panelId p, panelFaceUp p) | p <- sheetPanels sheet]

    look fid = case M.lookup fid faceUp of
      Nothing -> Left (FlatRefused (FaceOrderOutOfRange fid (length (sheetPanels sheet))))
      Just up -> Right up

    entry o = case orderStacking o of
      Unordered -> Right []
      stacking -> do
        _ <- look f
        gFaceUp <- look g
        let fOnTop = (stacking == Above) == gFaceUp
            fNearer = fOnTop == fromAbove
        pure [((f, g), fNearer), ((g, f), not fNearer)]
      where
        f = orderFace o
        g = orderRelativeTo o

-- | The visible part of every face that has one.
--
-- Faces that overlap but are not nearer are left out of the subtraction, and
-- so are faces the orders relate without the geometry agreeing that they share
-- any paper. That second guard is not redundant. Taking away a face that does
-- not actually overlap is not a no-op: the piece survives whole, but split
-- into as many parts as the absent face has edges, and every later subtraction
-- then runs on all of them.
regionsOf :: Bool -> Sheet -> (FaceId -> FaceId -> Bool) -> [Region]
regionsOf fromAbove sheet nearer = [r | p <- panels, Just r <- [regionFor p]]
  where
    panels = sheetPanels sheet
    speck = sheetSpeck sheet

    regionFor p = case foldl' cut [panelRing p] (covering p) of
      [] -> Nothing
      pieces ->
        Just
          Region
            { regionFace = panelId p,
              -- The viewer sees the sheet's top side where the face lies
              -- top-up and the viewer is above it, or where both are the other
              -- way round.
              regionTopSide = panelFaceUp p == fromAbove,
              regionPieces = map (map (raise (sheetPlane sheet)) . tidy) pieces
            }

    covering p =
      [ q
        | q <- panels,
          panelId q /= panelId p,
          nearer (panelId q) (panelId p),
          overlap (panelRing p) (panelRing q) > speck
      ]

    -- Tested piece by piece rather than once against the whole face, and for
    -- the reason the comment above gives: a subtraction that takes nothing away
    -- is not free. After a few cuts a remnant may be a corner the next face does
    -- not reach at all, and running the subtraction on it anyway splits it into
    -- as many parts as that face has edges, every one of which the remaining
    -- faces then have to be tried against in turn.
    cut pieces q = concatMap (cutOne (panelRing q)) pieces
    cutOne ring piece
      | overlap ring piece <= speck = [piece]
      | otherwise = subtractConvex speck ring piece

    overlap ring piece = abs (signedArea (clipConvex ring piece))

    -- Clipping puts a corner in twice wherever the cut passed exactly through
    -- one, which costs nothing while all anybody wants is an area and shows up
    -- the moment the ring is drawn: a folded model, whose faces meet corner to
    -- corner constantly, produces them everywhere. Only /identical/ corners go;
    -- a corner left sitting in the middle of a straight side is harmless, and
    -- deciding whether one really is straight is a judgement this does not have
    -- to make.
    tidy ring = [b | (a, b) <- zip (rotate ring) ring, norm (b ^-^ a) > sheetHair sheet]
    rotate ps = drop (length ps - 1) ps <> take (length ps - 1) ps

-- | Every stretch that is drawn, by the line it lies on, each labelled with
-- the sheet whose edge it is.
--
-- Both of a 'VisibleForm's edge lists come from this, joined up by different
-- keys, so the two can never disagree about which stretches are drawn — only
-- about how finely they are cut.
shownStretches ::
  Sheet ->
  (FaceId -> FaceId -> Bool) ->
  [(Track, [((Assignment, Maybe FaceId), Double, Double)])]
shownStretches sheet nearer =
  [ (track, showingOn track (stretches hair rims track))
    | track <- tracks hair (sheetPlane sheet) (vertexAt sheet) (sheetCreases sheet)
  ]
  where
    hair = sheetHair sheet

    -- What can change which face is on top: the boundary of a face. A crease
    -- that bounds nothing is still drawn, but it hides nothing and reveals
    -- nothing, so nothing is cut at it.
    rims = [(p, q) | panel <- sheetPanels sheet, (p, q) <- ring (panelRing panel)]
    ring ps = zip ps (drop 1 ps <> take 1 ps)

    -- Whether a stretch is drawn and whose edge it is are one question with one
    -- answer, so this asks once rather than filtering and then labelling.
    showingOn track stretchesOn =
      [ ((assignment, nearest), s0, s1)
        | (assignment, s0, s1) <- stretchesOn,
          Just nearest <-
            [ showsAnEdge
                sheet
                nearer
                (trackDirection track)
                (pointAt track s0, pointAt track s1)
            ]
      ]

-- | The stretches of edge that are not hidden.
--
-- Joined up on the assignment alone, so a stretch that runs on over a change of
-- sheet behind it stays one line. That is the picture an ordinary drawing wants
-- and it is what 'joinRuns' was written for.
edgesOf :: [(Track, [((Assignment, Maybe FaceId), Double, Double)])] -> [VisibleEdge]
edgesOf shown =
  [ lineOn track assignment s0 s1
    | (track, ss) <- shown,
      (assignment, s0, s1) <- joinRuns [(a, s0, s1) | ((a, _), s0, s1) <- ss]
  ]

-- | The same, cut at every change of sheet as well, and labelled with it.
sheetEdgesOf ::
  [(Track, [((Assignment, Maybe FaceId), Double, Double)])] ->
  [(Maybe FaceId, VisibleEdge)]
sheetEdgesOf shown =
  [ (nearest, lineOn track assignment s0 s1)
    | (track, ss) <- shown,
      ((assignment, nearest), s0, s1) <- joinRuns ss
  ]

-- | Put back together the neighbouring stretches a cut turned out not to
-- separate.
--
-- A line is cut wherever a face boundary meets it, which is where the answer
-- /may/ change; often it does not, and the outline of a model would otherwise
-- come back as one line per face that happens to reach it. Purely cosmetic in
-- the picture, since the pieces abut exactly — but it is the difference between
-- an outline drawn as one stroke and the same outline drawn as nine.
--
-- Adjacency is exact equality of the two ends, which is sound because both
-- stretches took that number from the same list of cuts.
joinRuns :: (Eq a) => [(a, Double, Double)] -> [(a, Double, Double)]
joinRuns = \case
  (a, s0, s1) : (b, t0, t1) : rest
    | a == b, s1 == t0 -> joinRuns ((a, s0, t1) : rest)
  stretch : rest -> stretch : joinRuns rest
  [] -> []

-- | One straight line of the folded form, and the creases lying along it.
--
-- The creases are intervals along the line, measured from 'trackOrigin' in
-- units of 'trackDirection', which is a unit vector — so an interval's length
-- is a length.
data Track = Track
  { trackOrigin :: !V2,
    trackDirection :: !V2,
    -- | The @z@ the model lies at, carried so that a stretch worked out along
    -- this line can be put back into space without the sheet in hand.
    trackPlane :: !Double,
    trackCreases :: ![(Assignment, Double, Double)]
  }

-- | One stretch of a track, as a line in space.
lineOn :: Track -> Assignment -> Double -> Double -> VisibleEdge
lineOn track assignment s0 s1 =
  VisibleEdge
    { visibleAssignment = assignment,
      visibleFrom = raise (trackPlane track) (pointAt track s0),
      visibleTo = raise (trackPlane track) (pointAt track s1)
    }

-- | A point on a track, at the given distance along it.
pointAt :: Track -> Double -> V2
pointAt t s = trackOrigin t ^+^ (s *^ trackDirection t)

-- | How far along a track a point lies, and how far off it.
along, offset :: Track -> V2 -> Double
along t x = dot (x ^-^ trackOrigin t) (trackDirection t)
offset t x = cross2 (trackDirection t) (x ^-^ trackOrigin t)

-- | Gather the creases into the lines they lie on.
--
-- Order is the order the lines first appear, and creases keep their file order
-- within a line, so the output is reproducible — which the golden tests need.
--
-- A crease whose two ends land on the same point of the folded form is
-- dropped: it has no direction to give a line, and there is nothing there to
-- draw. That is not a corrupt file. Folding brings distinct corners of the
-- sheet together all the time, and an edge between two of them has been folded
-- out of existence.
tracks :: Double -> Double -> (VertexId -> V2) -> [Crease] -> [Track]
tracks hair plane at = foldl' add [] . concatMap segment
  where
    segment c = case normalize (q ^-^ p) of
      Just direction | norm (q ^-^ p) > hair -> [(creaseAssignment c, p, q, direction)]
      _ -> []
      where
        p = at (creaseFrom c)
        q = at (creaseTo c)

    -- The first track this segment lies on takes it; if there is none, it
    -- starts one of its own, at its own start and pointing its own way.
    add ts seg@(_, p, _, direction) = case break (lies seg) ts of
      (before, t : after) -> before <> (record t seg : after)
      (before, []) -> before <> [record (Track p direction plane []) seg]

    lies (_, p, q, _) t = abs (offset t p) <= hair && abs (offset t q) <= hair

    record t (assignment, p, q, _) =
      t {trackCreases = trackCreases t <> [(assignment, min sp sq, max sp sq)]}
      where
        sp = along t p
        sq = along t q

-- | Cut a track into the stretches over which nothing can change.
--
-- The cuts are its own creases' ends and every point where a face boundary
-- meets the line: a face that ends here, a face that crosses here, a face with
-- an edge that starts or stops here. Between two consecutive cuts the set of
-- faces on each side is fixed, so one test settles the whole stretch.
--
-- Only stretches with a crease along them come back, since a stretch of bare
-- line is not an edge of anything.
stretches :: Double -> [(V2, V2)] -> Track -> [(Assignment, Double, Double)]
stretches hair rims track = case concat [[lo, hi] | (_, lo, hi) <- trackCreases track] of
  [] -> []
  ends ->
    [ (strongest [a | (a, lo, hi) <- trackCreases track, lo <= mid, mid <= hi], s0, s1)
      | (s0, s1) <- zip cuts (drop 1 cuts),
        let mid = 0.5 * (s0 + s1),
        any (\(_, lo, hi) -> lo <= mid && mid <= hi) (trackCreases track)
    ]
    where
      -- Cuts beyond the creases would divide a stretch of line nobody draws.
      inRange s = s >= minimum ends && s <= maximum ends
      cuts = thin (sort (filter inRange (ends <> concatMap meeting rims)))
  where
    -- Where one edge of one face meets this line. An edge lying along the line
    -- contributes both its ends: the face it belongs to may stop halfway along
    -- a stretch, and what is beside the line changes there.
    meeting (a, b)
      | onLine a && onLine b = [along track a, along track b]
      | onLine a = [along track a]
      | onLine b = [along track b]
      -- Strictly opposite sides, so the crossing is inside the edge. The
      -- interpolation is safe for the reason 'Senbazuru.Geometry.Polygon' gives
      -- for its own: the denominator is a sum of same-signed numbers.
      | (da > 0) /= (db > 0) = [along track (a ^+^ ((da / (da - db)) *^ (b ^-^ a)))]
      | otherwise = []
      where
        da = offset track a
        db = offset track b
        onLine x = abs (offset track x) <= hair

    -- Two cuts a hair apart are one cut that rounding has split in two, and a
    -- stretch between them would be a line of no length. Keeping the first of
    -- each huddle also drops exact duplicates, which every shared corner of the
    -- folded form produces.
    thin [] = []
    thin (s : ss) = s : thin (dropWhile (\u -> u - s <= hair) ss)

-- | Which assignment to draw a stretch with, when several creases lie along
-- it.
--
-- The edge of the paper beats a fold, and a fold beats a construction line,
-- because that is the order of how much the reader needs to see: a fold that
-- landed exactly on the outline of the model does not stop the outline being
-- the outline. Ties go to whichever crease the file listed first, so the
-- answer does not depend on the order faces happened to be visited in.
--
-- @J@ is the identity, which is what makes folding the list from an empty
-- start total: a join is not a line at all, so anything at all beats it.
strongest :: [Assignment] -> Assignment
strongest = foldr stronger Join
  where
    stronger a b = if weight a >= weight b then a else b
    weight = \case
      Border -> 3 :: Int
      Cut -> 3
      Mountain -> 2
      Valley -> 2
      Flat -> 1
      Unassigned -> 1
      Join -> 0

-- | Does the paper differ across this stretch of line, and if so whose edge is
-- it?
--
-- 'Nothing' when the stretch is hidden. @Just mf@ when it is drawn, carrying
-- the nearer of the two sides' topmost faces — see 'visibleNearest' — or
-- 'Nothing' again where there is paper on neither side.
--
-- The topmost face along each side is found, and the stretch is drawn when the
-- two are not the same face. Paper on one side and nothing on the other counts
-- as different, which is what draws the silhouette of the model, and bare page
-- on both sides is drawn too — nothing is covering it, so nothing hides it.
--
-- No point is nudged to one side to ask the question, because a nudge small
-- enough to stay on the right side of the line is small enough to be rounding.
-- Instead each face is asked how far outside it the middle of the stretch is.
-- Well inside, the face is on both sides of the stretch; within a hair of the
-- boundary, the stretch runs along one of its edges and the face is on the side
-- its centre is; well outside, the face is not beside the stretch at all. One
-- number answers all three, and asking the midpoint alone is enough because the
-- line was cut wherever a face boundary meets it: the stretch is inside a face
-- for all of its length or for none of it.
--
-- Deciding the first two cases by clipping the stretch against the face instead
-- is what the first version did, and it is wrong in a way worth recording. A
-- stretch that lies along a face\'s edge clips to itself when rounding puts it a
-- hair inside and to nothing when rounding puts it a hair outside, and a clip
-- has no tolerance with which to call those the same answer. The face then
-- vanishes from the reckoning, the two sides agree because neither can see it,
-- and a visible crease stops in the middle of the paper.
showsAnEdge :: Sheet -> (FaceId -> FaceId -> Bool) -> V2 -> (V2, V2) -> Maybe (Maybe FaceId)
showsAnEdge sheet nearer direction (a, b) = case (top OnTheLeft, top OnTheRight) of
  -- Bare page on both sides. Nothing is covering the line, so nothing is
  -- hiding it: this is a crease that bounds no face, and a frame recording no
  -- faces at all is nothing but those. Drawing them is what keeps such a frame
  -- the wireframe it has always been rather than an empty page.
  (Nothing, Nothing) -> Just Nothing
  -- Paper on both sides. The same face on both is a crease with a layer over
  -- it and goes; two different faces are an edge, and the nearer of them is
  -- the sheet the reader is looking at the edge of.
  (Just l, Just r)
    | l == r -> Nothing
    | otherwise -> Just (Just (if nearer l r then l else r))
  -- Paper on one side only: the silhouette of that face, and there is no
  -- other candidate for whose edge it is.
  (Just l, Nothing) -> Just (Just l)
  (Nothing, Just r) -> Just (Just r)
  where
    top = fmap panelId . topmost . beside

    hair = sheetHair sheet
    mid = 0.5 *^ (a ^+^ b)

    beside side = [p | (p, s) <- sides, s == side || s == OnBothSides]
    sides = [(p, whichSide p) | p <- sheetPanels sheet, isBeside p]

    isBeside p = distanceOutside (panelRing p) mid <= hair

    whichSide p
      | distanceOutside (panelRing p) mid < negate hair = OnBothSides
      | cross2 direction (centroid (panelRing p) ^-^ mid) > 0 = OnTheLeft
      | otherwise = OnTheRight

    topmost = foldl' pick Nothing
    pick Nothing p = Just p
    pick (Just q) p
      | nearer (panelId p) (panelId q) = Just p
      | otherwise = Just q

-- | Where a face sits relative to a stretch of line it is beside.
data Side = OnTheLeft | OnTheRight | OnBothSides
  deriving stock (Eq)

-- | Put a point worked out in the plane back into space, at the plane the
-- model lies in.
raise :: Double -> V2 -> V3
raise z (V2 x y) = V3 x y z
