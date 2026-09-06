-- |
-- Module      : Senbazuru.Origami.Layers
-- Description : Turning FOLD's stacking relations into an order to draw in.
--
-- A folded model overlaps itself. Where two faces cover the same patch of page,
-- the picture is only right if the one nearer the viewer is drawn second, and
-- nothing about a face's coordinates says which that is: in a flat-folded model
-- every layer sits in the same plane, so there is no depth to compare at all.
--
-- FOLD records the answer in @faceOrders@, and this module turns it into an
-- order to draw in. It does not /compute/ an order: that is
-- "Senbazuru.Origami.Stacking"'s job, for the flat-folded frames it covers,
-- and its answer arrives here as a @faceOrders@ like any other. This is the
-- half that is free.
--
-- Two other questions are answered here because they are the same question
-- asked differently. 'layerDepths' says how many layers of paper are under each
-- face rather than merely which comes first, which is what a drawing that steps
-- the layers apart needs. 'showsTopSide' says which side of the sheet a face
-- presents to the viewer, which is the same winding and the same viewing
-- direction combined one step earlier.
--
-- == Two directions, and only one of them is the viewer's
--
-- @faceOrders@ says @f@ is above @g@ meaning __on the side @g@'s normal points
-- to__. That is a fact about the paper, fixed when the model was folded, and it
-- has nothing to do with where anyone is standing. Turning it into \"draw @f@
-- second\" needs the viewing direction as well:
--
-- * if @g@'s normal points towards the viewer, then above @g@ is in front of
--   @g@, and @f@ is drawn later;
-- * if it points away, above @g@ is behind it, and @f@ is drawn first.
--
-- Miss that second case and every model seen from its back face comes out
-- inside-out — which looks like a plausible drawing of a different model.
--
-- == The winding here is not advisory
--
-- Everywhere else senbazuru distrusts the winding a file states, because FOLD
-- specifies counterclockwise and real files disagree: filling does not care,
-- and folding measures the winding from the coordinates instead. Here it must
-- be taken exactly as written, because a face's normal /is defined by/ its
-- winding, and @faceOrders@'s signs were written against those normals. A file
-- with backwards windings has backwards normals and backwards signs, and the
-- two cancel. Recomputing the winding would uncancel them and invert the model.
--
-- == A partial order is the expected answer, and depth settles the rest
--
-- A file need not order every pair, and a missing pair is not missing
-- information: @0@, or no entry at all, is how FOLD says two faces do not
-- overlap __in their interiors__.
--
-- That is a statement about the paper, and it does not finish the drawing. Two
-- faces in different planes need no ordering — they genuinely do not overlap —
-- and can still cover the same patch of page once projected, one simply being
-- nearer the camera. So the constraints are sorted topologically, and wherever
-- the sort has a free choice it takes the face furthest from the viewer first.
-- Depth of the centroid is a rough measure and famously wrong for faces that
-- interpenetrate, but the cases a file has an opinion about are exactly the
-- cases it has already constrained, and file order is not a measure of anything
-- at all.
module Senbazuru.Origami.Layers
  ( paintOrder,
    layerDepths,
    showsTopSide,
  )
where

import Data.IntMap.Strict qualified as IM
import Data.List (foldl', sortOn)
import Data.Set qualified as S
import Senbazuru.Fold.Query (Face (..), FoldError (..))
import Senbazuru.Fold.Types (FaceId (..), FaceOrder (..), Stacking (..))
import Senbazuru.Geometry.V3 (V3, polygonNormal)
import Senbazuru.Geometry.VectorSpace

-- | The faces in the order to draw them, furthest from the viewer first.
--
-- @paintOrder towardsViewer faces orders@. The first argument points from the
-- model towards whoever is looking — for a camera it is the opposite of the
-- direction of view.
--
-- Every face comes back exactly once. Errors are the frame's own type, because
-- an ordering that cannot be drawn is a fact about the file rather than about
-- the drawing.
paintOrder :: V3 -> [Face] -> [FaceOrder] -> Either FoldError [FaceId]
paintOrder towardsViewer faces orders =
  map fst <$> layerDepths towardsViewer faces orders

-- | The same faces in the same order, each with the number of layers of paper
-- under it.
--
-- @layerDepths towardsViewer faces orders@. A face with nothing under it is at
-- depth 0; every other is one deeper than the deepest face it is drawn after.
-- That is the /longest/ chain below it and not a count of the faces below it,
-- and the difference is what makes the number mean \"which layer of the stack
-- is this\": three faces in a row come out 0, 1, 2 whether or not the file also
-- records the third as being over the first.
--
-- The property that follows, and the one a drawing relies on, is that the depth
-- __strictly increases along every relation the orders record__. So sorting the
-- faces by depth is itself a valid painting order, which is what lets a drawing
-- paint a whole layer at a time rather than a face at a time. And since FOLD
-- records an entry for exactly the pairs that overlap, faces sharing a depth
-- are faces that do not overlap: a crease pattern comes out all depth 0, and a
-- flat-folded model comes out in the layers a reader would count.
--
-- The order is 'paintOrder'\'s, furthest from the viewer first, and the depths
-- do not determine it: two faces at the same depth may be drawn in either
-- order, and this fixes one so the output is reproducible.
layerDepths :: V3 -> [Face] -> [FaceOrder] -> Either FoldError [(FaceId, Int)]
layerDepths towardsViewer faces orders = do
  constraints <- concat <$> traverse drawnBefore orders
  -- Deduplicated before counting anything. A file may say the same thing twice,
  -- and the two orderings [f, g, +1] and [g, f, -1] are one constraint written
  -- two ways -- both legal, and both arriving here as the same pair. Kahn's
  -- algorithm counts edges, so a repeated edge is decremented once per copy but
  -- frees its target once per copy too: the face comes out of the sort more than
  -- once, and the extra copies can pad the output enough that a genuine cycle
  -- slips past the "did everything come out?" check with the cyclic faces
  -- quietly missing from the drawing.
  let settled = S.toList (S.fromList constraints)
  order <- topologically ordering settled
  let depths = deepen (predecessorsOf settled) order
  pure [(FaceId i, IM.findWithDefault 0 i depths) | i <- order]
  where
    -- The order to prefer when the sort is free to choose: furthest away first.
    --
    -- How far a point reaches towards the viewer is exactly the negative of its
    -- depth, so furthest-first is this ascending, with no negation anywhere. The
    -- sign is easy to talk yourself into twice; the test that pins it puts two
    -- faces at different depths and asserts which is drawn first.
    --
    -- Face id breaks the remaining ties, so coplanar faces come out in file
    -- order and the output is reproducible.
    ordering =
      map snd
        . sortOn fst
        $ [((dot (centroid f) towardsViewer, unFaceId (faceId f)), unFaceId (faceId f)) | f <- faces]

    centroid f = case faceCorners f of
      [] -> zeroV
      cs -> (1 / fromIntegral (length cs)) *^ foldr (^+^) zeroV cs

    zeroV = 0 *^ towardsViewer

    normals =
      IM.fromList [(unFaceId (faceId f), polygonNormal (faceCorners f)) | f <- faces]

    normalOf fid = case IM.lookup (unFaceId fid) normals of
      Nothing -> Left (FaceOrderOutOfRange fid (length faces))
      Just n -> Right n

    -- One entry becomes at most one "draw this before that" pair.
    drawnBefore o = case orderStacking o of
      Unordered -> Right []
      stacking -> do
        _ <- normalOf (orderFace o)
        normal <- normalOf (orderRelativeTo o)
        let facingUs = dot normal towardsViewer
            -- Compared against the size of the vectors involved, not against
            -- zero. polygonNormal returns twice the area, so a large face
            -- almost edge on still has a dot product far from zero, and a small
            -- one squarely facing the viewer has a small one. An absolute test
            -- would call the second edge on and let the first be decided by
            -- rounding.
            negligible = 1e-9 * norm normal * norm towardsViewer
            f = unFaceId (orderFace o)
            g = unFaceId (orderRelativeTo o)
        if norm normal <= 0
          then Left (FaceWithoutNormal (orderRelativeTo o))
          else
            pure $
              if abs facingUs <= negligible
                then -- Edge on. The relation still holds in the model, but along
                -- the line of sight it separates nothing, so it constrains no
                -- drawing order. Inventing one from it would be making
                -- something up.
                  []
                else
                  if (facingUs > 0) == (stacking == Above)
                    then [(g, f)]
                    else [(f, g)]

-- | Which side of the sheet a face shows to a viewer looking from the given
-- direction.
--
-- @showsTopSide towardsViewer face@ is 'True' when the viewer is looking at the
-- __top__ side of the paper — the side a crease pattern is drawn on — and
-- 'False' when they are looking at its back. Origami paper is usually coloured
-- on one side and white on the other, so this is the difference between the two
-- colours in a drawing of a folded model.
--
-- The winding is read exactly as the file wrote it, for the reason the module
-- header gives: FOLD's normal /is/ the corner order, and turning a face over
-- reverses it. But
-- this is the one reading with nothing to cancel against. A file that wound
-- every face backwards has @faceOrders@ signs written against those same
-- backwards normals, so its layer order survives; the side of the paper has no
-- second wrong to meet, and such a file is drawn with its two colours swapped
-- and no way to tell. "Senbazuru.Origami.Visible" says the same of the same
-- question, reached from the other direction.
--
-- Two cases answer 'True' arbitrarily, and neither can be seen: a face with no
-- normal at all, whose corners are collinear or repeated, and a face turned
-- exactly edge on to the viewer. The first encloses no area and the second
-- projects to a line, so whichever side either is said to show, it paints
-- nothing.
showsTopSide :: V3 -> Face -> Bool
showsTopSide towardsViewer f = dot (polygonNormal (faceCorners f)) towardsViewer >= 0

-- | The faces each face has to be drawn after.
predecessorsOf :: [(Int, Int)] -> IM.IntMap [Int]
predecessorsOf constraints =
  IM.fromListWith (<>) [(after, [before]) | (before, after) <- constraints]

-- | How deep in the stack each face lies, given the faces in an order where
-- everything a face is drawn after comes before it.
--
-- One pass is enough precisely because of that: by the time a face is reached,
-- every face it sits on has its final depth, so there is nothing to revisit.
deepen :: IM.IntMap [Int] -> [Int] -> IM.IntMap Int
deepen predecessors = foldl' step IM.empty
  where
    step depths i = IM.insert i (level depths i) depths
    level depths i = case IM.findWithDefault [] i predecessors of
      [] -> 0
      ps -> 1 + maximum [IM.findWithDefault 0 p depths | p <- ps]

-- | Kahn's algorithm: repeatedly take a face nothing has to be drawn after.
--
-- The ready set is kept in the caller's preferred order, so faces the
-- constraints leave free come out furthest-first rather than in whatever order
-- the graph walk reached them.
topologically :: [Int] -> [(Int, Int)] -> Either FoldError [Int]
topologically preferred constraints = go (filter ((== 0) . indegree) preferred) indegrees []
  where
    rank = IM.fromList (zip preferred [0 :: Int ..])
    successors = IM.fromListWith (<>) [(before, [after]) | (before, after) <- constraints]
    indegrees =
      IM.fromListWith
        (+)
        ([(i, 0 :: Int) | i <- preferred] <> [(after, 1) | (_, after) <- constraints])
    indegree i = IM.findWithDefault 0 i indegrees

    insertReady i = insertBy (IM.findWithDefault maxBound i rank) i
    insertBy _ i [] = [i]
    insertBy r i (j : js)
      | r <= IM.findWithDefault maxBound j rank = i : j : js
      | otherwise = j : insertBy r i js

    go [] remaining done
      | length done == length preferred = Right (reverse done)
      -- Anything left still has an incoming edge, so it is on a cycle. Naming
      -- the lowest is arbitrary but stable.
      | otherwise = case sortOn id [i | (i, n) <- IM.toList remaining, n > 0] of
          (stuck : _) -> Left (ImpossibleStacking (FaceId stuck))
          [] -> Right (reverse done)
    go (next : ready) remaining done =
      let after = IM.findWithDefault [] next successors
          remaining' = foldr (IM.adjust (subtract 1)) remaining after
          freed = [i | i <- after, IM.findWithDefault 1 i remaining' == 0]
       in go (foldr insertReady ready freed) remaining' (next : done)
