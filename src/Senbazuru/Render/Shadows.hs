-- | What a view of an open fold is judged by, wherever it is judged: each
-- face's /shadow/, its outline in the picture with the depth of its plane
-- behind every point of it; the two yardsticks; the near and far the file's
-- orders say; the coverage check; and lifting the visible form back onto the
-- camera plane. See docs/glossary.md for the fold vocabulary.
--
-- These live apart from "Senbazuru.Render.Projected" because they have a second
-- consumer. The material study's @IllustrationVisibility@ decides some pairs of
-- panels differently from production, by a depth-tie allowance, so it cannot
-- call 'Senbazuru.Render.Projected.projectedForm'. It kept copies of the rest
-- instead, and they fell behind production twice in a week: #459 made the
-- coverage check cut again, skipping nothing, any piece its first pass lets
-- through, and #463 began judging areas in the picture by the picture's speck.
-- Each time, the copy called paper uncovered that production draws. Both now
-- import this module, and what is left to differ is the decision about each
-- pair: production's @orderPair@, the study's @auditPair@. The library imports
-- no study code, as for "Senbazuru.Origami.HingeSweep".
--
-- Two yardsticks judge a view, and they are measured against different sizes
-- on purpose. Lengths in the model, how far a corner is from its face's plane
-- and how far apart two faces are along the line of sight, are judged by a
-- hair of the model's own size in 3D ('modelHair'). Areas in the picture,
-- whether a shadow is too small to paint, whether two overlap and whether the
-- visible regions cover a face, are judged by the speck
-- "Senbazuru.Origami.Flat" gives the flattened frame ('picture'), not by a 3D
-- speck worked out like the hair, because "Senbazuru.Origami.Visible" cuts the
-- regions with the flattened frame's. The two differ either way: seen
-- isometrically, the unit square's shadow is sqrt 2 across and its speck twice
-- the 3D one, while a model deep along the line of sight has the larger 3D
-- speck. Judged by one speck and cut with the other, a corner between the two
-- was dropped by the cutting and then refused as uncovered.
module Senbazuru.Render.Shadows
  ( Shadow (shadowId, shadowRing, shadowFront, shadowDepth),
    shadowOf,
    edgesAccountedFor,
    suppliedNearness,
    modelHair,
    picture,
    uncoveredParts,
    liftForm,
  )
where

import Control.Monad (foldM)
import Data.List (foldl')
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Senbazuru.Fold.Query (Face (..), FoldError (..), edgeKey, ringEdges)
import Senbazuru.Fold.Types (FaceId, FaceOrder (..), Stacking (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (clipConvex, isConvex, signedArea, subtractConvex)
import Senbazuru.Geometry.V3 (V3 (..), polygonNormal, spanAlong)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Flat (yardsticks)
import Senbazuru.Origami.Visible (Region (..), VisibleEdge (..), VisibleForm (..))
import Senbazuru.Render.Camera (Basis, basisForward, basisRight, basisUp, project)

-- | A face's shadow. The ring is turned anticlockwise, and 'shadowFront' says
-- whether the face's own winding already ran that way in the picture.
-- 'shadowDepth' increases away from the viewer. The constructor is not exported, as for
-- 'Basis', so every shadow is one 'shadowOf' made: convex, and more than a
-- speck in area.
data Shadow = Shadow
  { shadowId :: !FaceId,
    shadowRing :: ![V2],
    shadowFront :: !Bool,
    shadowDepth :: V2 -> Double
  }

-- | A face's shadow in this view. 'Nothing' declines the view: the face is not
-- planar to a hair, or its shadow is not convex. @Just Nothing@ leaves the
-- face out, because it is edge-on or its shadow is no more than a speck, and
-- 'edgesAccountedFor' says whether that is safe.
shadowOf :: Basis -> Double -> Double -> Face -> Maybe (Maybe Shadow)
shadowOf basis hair speck face = case faceCorners face of
  [] -> Nothing
  origin : _ -> do
    normal <- normalize (polygonNormal (faceCorners face))
    let ring = map (project basis) (faceCorners face)
        area = signedArea ring
        facing = dot normal (basisForward basis)
        planar = all ((<= hair) . abs . dot normal . (^-^ origin)) (faceCorners face)
        depthAt (V2 x y) =
          (dot normal origin - x * dot normal (basisRight basis) - y * dot normal (basisUp basis)) / facing
    if not planar || not (isConvex speck ring)
      then Nothing
      else
        if abs area <= speck || abs facing <= 1e-9
          then Just Nothing
          else Just (Just (Shadow (faceId face) (if area > 0 then ring else reverse ring) (area > 0) depthAt))

-- | An edge-on face paints no area. It can be omitted when all its edges also
-- belong to surviving neighbours, which supply their real depth and outline.
-- A free edge seen end-on needs a separate line-depth test, so decline that
-- case rather than accidentally hiding it behind unrelated paper.
edgesAccountedFor :: [Face] -> [Maybe Shadow] -> Bool
edgesAccountedFor faces projected = all (`S.member` retained) omitted
  where
    keys face = [edgeKey a b | (a, b) <- ringEdges (faceVertexIds face)]
    retained = S.fromList (concat [keys f | (f, Just _) <- zip faces projected])
    omitted = concat [keys f | (f, Nothing) <- zip faces projected]

-- | FOLD signs refer to the second face's normal. Camera projection preserves
-- its facing sign, including when looking from underneath. Record both ways
-- round so a reversed entry cannot evade the contradiction check.
suppliedNearness :: [Shadow] -> [FaceOrder] -> Either FoldError (M.Map (FaceId, FaceId) Bool)
suppliedNearness panels orders = foldM record M.empty (concatMap entries orders)
  where
    fronts = M.fromList [(shadowId p, shadowFront p) | p <- panels]
    entries o = case orderStacking o of
      Unordered -> []
      stacking
        | Just front <- M.lookup (orderRelativeTo o) fronts,
          M.member (orderFace o) fronts ->
            let f = orderFace o
                g = orderRelativeTo o
                near = (stacking == Above) == front
             in [((f, g), near), ((g, f), not near)]
      _ -> []
    record known (pair@(f, g), near) = case M.lookup pair known of
      Just previous | previous /= near -> Left (ContradictoryStacking f g)
      _ -> Right (M.insert pair near known)

-- | The hair every length in the model is judged by: a billionth of the
-- model's largest extent in 3D, or of a unit if that is larger (see the
-- header).
modelHair :: [V3] -> Double
modelHair vertices = 1e-9 * scale
  where
    scale = maximum (1 : [spanAlong component vertices | component <- [v3x, v3y, v3z]])

-- | A view's vertices as its temporary frame holds them, flat in the picture,
-- and the speck "Senbazuru.Origami.Flat" gives that frame, which every area in
-- the picture is judged by (see the header).
picture :: Basis -> [V3] -> ([V3], Double)
picture basis vertices = (pictured, snd (yardsticks pictured))
  where
    pictured = [V3 x y 0 | V2 x y <- map (project basis) vertices]

-- | For each shadow, the parts of it that no visible region covers, by the
-- rule 'Senbazuru.Render.Projected.projectedForm' refuses a view by: a shadow
-- with any part left is a hole. Areas are in the picture, so @speck@ is the one
-- 'picture' gives.
--
-- The first pass skips a cut that would take no more than @speck@ of a piece,
-- for the reason "Senbazuru.Origami.Visible" gives for the same rule in its
-- @regionsOf@: a cut that takes almost nothing still splits the piece, and
-- every part must then be tried against every region left. Skipped cuts add
-- up, though. A piece a few specks big comes through whenever each region
-- over it covers no more than a speck of it, however much they cover between
-- them, as a corner does in ProjectedSpec. So a piece that comes through is
-- cut again by every region, skipping nothing, and is left only if more than
-- a speck of it remains. Measuring what remains, rather than adding up what
-- each region covers, counts a patch two regions share once.
uncoveredParts :: Double -> VisibleForm -> [[V2]] -> [[[V2]]]
uncoveredParts speck seen = map leftOver
  where
    regions = [[V2 x y | V3 x y _ <- piece] | region <- formRegions seen, piece <- regionPieces region]
    leftOver ring =
      concat
        [ left
          | piece <- foldl' (cut speck) [ring] regions,
            let left = foldl' (cut 0) [piece] regions,
            sum (map (abs . signedArea) left) > speck
        ]
    cut allowance pieces cover = concatMap (cutOne allowance cover) pieces
    cutOne allowance cover piece
      | abs (signedArea (clipConvex cover piece)) <= allowance = [piece]
      | otherwise = subtractConvex allowance cover piece

-- | The visible form found in the flattened frame, put back onto the camera
-- plane and given the input frame's face ids, so that the caller can project
-- it through the same basis as its other geometry.
liftForm :: Basis -> (FaceId -> FaceId) -> VisibleForm -> VisibleForm
liftForm basis originalId seen =
  seen
    { formRegions = [r {regionFace = originalId (regionFace r), regionPieces = map (map liftPoint) (regionPieces r)} | r <- formRegions seen],
      formEdges = map liftEdge (formEdges seen),
      formSheetEdges = [(fmap originalId owner, liftEdge edge) | (owner, edge) <- formSheetEdges seen]
    }
  where
    liftPoint (V3 x y _) = x *^ basisRight basis ^+^ y *^ basisUp basis
    liftEdge edge = edge {visibleFrom = liftPoint (visibleFrom edge), visibleTo = liftPoint (visibleTo edge)}
