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
-- order to draw in. It does not /compute/ an order — a file that supplies none
-- gets none, because working it out is
-- @docs\/notes\/layer-ordering.md@'s NP-hard problem and this is the half that
-- is free.
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
-- == A partial order is the expected answer
--
-- A file need not order every pair, and a missing pair is not missing
-- information: @0@, or no entry at all, is how FOLD says two faces do not
-- overlap in their interiors, and faces that do not overlap cannot obscure one
-- another whichever way round they are drawn. So the constraints are sorted
-- topologically and anything left unconstrained keeps its file order.
module Senbazuru.Origami.Layers
  ( paintOrder,
    LayerError (..),
    renderLayerError,
  )
where

import Data.IntMap.Strict qualified as IM
import Data.List (insert, sortOn)
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Fold.Query (Face (..))
import Senbazuru.Fold.Types (FaceId (..), FaceOrder (..), Stacking (..))
import Senbazuru.Geometry.V3 (V3, polygonNormal)
import Senbazuru.Geometry.VectorSpace (dot)

-- | Everything that stops a stacking being turned into a drawing order.
data LayerError
  = -- | A @faceOrders@ entry names a face the frame does not have. Validation
    -- proper is 'Senbazuru.Fold.Query.frameFaceOrders'; this is the same check
    -- from the other side, so that a caller cannot pass a mismatched pair of
    -- lists and get a quietly wrong picture.
    UnknownFace !FaceId
  | -- | The constraints run in a circle: @f@ in front of @g@ in front of @f@.
    -- No stack of paper does that, so the file is describing something
    -- impossible. Carries one face on the cycle.
    CyclicStacking !FaceId
  deriving stock (Eq, Show)

renderLayerError :: LayerError -> Text
renderLayerError = \case
  UnknownFace (FaceId f) -> "faceOrders refers to face " <> tshow f <> ", which does not exist"
  CyclicStacking (FaceId f) ->
    "the faceOrders run in a circle through face "
      <> tshow f
      <> "; no stack of paper can be in front of itself"

-- | The faces in the order to draw them, furthest from the viewer first.
--
-- @paintOrder towardsViewer faces orders@. The first argument points from the
-- model towards whoever is looking — for a camera it is the opposite of the
-- direction of view.
--
-- Every face comes back exactly once, ordered ones where the stacking puts them
-- and the rest in file order.
paintOrder :: V3 -> [Face] -> [FaceOrder] -> Either LayerError [FaceId]
paintOrder towardsViewer faces orders = do
  constraints <- concat <$> traverse drawnBefore orders
  map FaceId <$> topologically ids constraints
  where
    ids = map (unFaceId . faceId) faces

    normals =
      IM.fromList [(unFaceId (faceId f), polygonNormal (faceCorners f)) | f <- faces]

    -- One entry becomes at most one "draw this before that" pair.
    drawnBefore o = case orderStacking o of
      Unordered -> Right []
      stacking -> do
        normal <- case IM.lookup (unFaceId (orderRelativeTo o)) normals of
          Just n -> Right n
          Nothing -> Left (UnknownFace (orderRelativeTo o))
        _ <- case IM.lookup (unFaceId (orderFace o)) normals of
          Just n -> Right n
          Nothing -> Left (UnknownFace (orderFace o))
        let facingUs = dot normal towardsViewer
            f = unFaceId (orderFace o)
            g = unFaceId (orderRelativeTo o)
        pure $ case compare facingUs 0 of
          -- Edge on. The relation still holds in the model, but along the line
          -- of sight it separates nothing, so it constrains no drawing order.
          -- Silently dropping it is right; treating it as either order would be
          -- inventing a fact.
          EQ -> []
          GT -> [if stacking == Above then (g, f) else (f, g)]
          LT -> [if stacking == Above then (f, g) else (g, f)]

-- | Kahn's algorithm: repeatedly take a face nothing has to be drawn after.
--
-- The ready set is kept sorted so that faces nothing constrains come out in
-- file order and the output is reproducible, which golden tests need.
topologically :: [Int] -> [(Int, Int)] -> Either LayerError [Int]
topologically ids constraints = go (foldr insert [] (filter ((== 0) . indegree) ids)) indegrees []
  where
    successors = IM.fromListWith (<>) [(before, [after]) | (before, after) <- constraints]
    indegrees = IM.fromListWith (+) ([(i, 0 :: Int) | i <- ids] <> [(after, 1) | (_, after) <- constraints])
    indegree i = IM.findWithDefault 0 i indegrees

    go [] remaining done
      | length done == length ids = Right (reverse done)
      -- Anything left has an incoming edge that never cleared, so it is on a
      -- cycle. Naming the lowest is arbitrary but stable.
      | otherwise = case sortOn id [i | (i, n) <- IM.toList remaining, n > 0] of
          (stuck : _) -> Left (CyclicStacking (FaceId stuck))
          [] -> Right (reverse done)
    go (next : ready) remaining done =
      let after = IM.findWithDefault [] next successors
          remaining' = foldr (IM.adjust (subtract 1)) remaining after
          freed = [i | i <- after, IM.findWithDefault 1 i remaining' == 0]
       in go (foldr insert ready freed) remaining' (next : done)

tshow :: (Show a) => a -> Text
tshow = T.pack . show
