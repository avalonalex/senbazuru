-- | One indexed material surface, before any camera or display separation.
-- A crease joins two regions of the same sheet; two folded layers occupying
-- the same position are still different material. Vertex ids, never equality
-- of folded coordinates, decide which corners and edge midpoints are shared.
-- See docs/glossary.md for material coordinates, panels and creases.
--
-- 'Surface' keeps the FOLD topology but owns the current positions. Its private
-- frame has no coordinates: 'surfaceFrame' restores them from the samples.
-- There is consequently only one place to change a material point's position.
-- Crease edges and panel ids survive triangulation; subdivision diagonals are
-- numerical edges, not extra creases. 'refineSurfaceWithEdges' carries source
-- edge ids through midpoint subdivision. 'refineSurface' interpolates WITHIN an
-- already placed rigid panel, never between folding states.
--
-- The material parameter records what we know about the original sheet.
-- Folding supplies @Surface V2@. A standalone folded FOLD file may have no
-- original-sheet coordinates, so reading it supplies @Surface (Maybe V2)@.
-- This distinction prevents a length check from silently treating its folded
-- x/y coordinates as undeformed material. Both can be rendered.
--
-- Physical thickness and directional layer requirements are data here, not
-- forces or display offsets. Constructing a surface validates references and
-- coordinates; it does not certify lengths, achieved crease angles or contact.
-- The folding producer and study checks still establish those facts.
module Senbazuru.Origami.Surface
  ( Surface,
    SurfaceError (..),
    Sample (..),
    Mesh (..),
    MaterialSample,
    MaterialMesh,
    Triangle,
    materialSample,
    materialU,
    materialV,
    surfaceFromFrame,
    surfaceFromFolded,
    requireMaterialCoordinates,
    surfaceFrame,
    materialFrame,
    surfaceSamples,
    surfaceFaces,
    withFaceOrders,
    surfaceFeatures,
    surfacePanelSamples,
    transformSurface,
    surfaceThickness,
    withPhysicalThickness,
    surfaceLayerRequirements,
    withLayerRequirements,
    refineSurface,
    RefinedSurface (..),
    refineSurfaceWithEdges,
  )
where

import Control.Monad (unless)
import Data.Aeson (Result (..), fromJSON, toJSON)
import Data.Aeson.KeyMap qualified as KM
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (sort)
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Query (Crease (..), Face (..), FoldError, FrameKind (..), edgeKey, frameCreases, frameFaceOrders, frameFaces, frameKind, frameVertices, ringEdges)
import Senbazuru.Fold.Types (Assignment (..), EdgeId (..), FaceId (..), FaceOrder, Frame (..), VertexId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (isConvex)
import Senbazuru.Geometry.Rigid (Rigid (..), applyRigid, matApply)
import Senbazuru.Geometry.V3 (V3 (..), cross, hasRelief, modelSpan, polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding (Folded (..))

data Sample material = Sample
  { sampleMaterial :: !material,
    position :: !V3
  }
  deriving stock (Eq, Show)

type Triangle = (Int, Int, Int)

-- | An indexed triangulation. Raw meshes can describe invalid experiments;
-- the 'Surface' constructors and 'refineSurface' validate their own outputs.
data Mesh material = Mesh
  { samples :: ![Sample material],
    triangles :: ![Triangle]
  }
  deriving stock (Eq, Show)

type MaterialSample = Sample V2

type MaterialMesh = Mesh V2

-- | A triangle mesh with its source panel and edge identities. Edge segments
-- keep the source edge's direction and id as shared midpoints are inserted.
-- Only source edges present in the triangulation occur here; a caller needing
-- a particular crease must check that it is represented. Fan diagonals have
-- no source id unless the input explicitly records that edge.
data RefinedSurface = RefinedSurface
  { refinedMesh :: !MaterialMesh,
    refinedPanels :: ![FaceId],
    refinedEdges :: ![(EdgeId, (Int, Int))]
  }
  deriving stock (Eq, Show)

materialSample :: Double -> Double -> V3 -> MaterialSample
materialSample u v = Sample (V2 u v)

materialU, materialV :: MaterialSample -> Double
materialU (Sample (V2 u _) _) = u
materialV (Sample (V2 _ v) _) = v

data Surface material = Surface
  { topology :: !Frame,
    storedSamples :: ![Sample material],
    materialThickness :: !(Maybe Double),
    -- | A direction and lower/upper panel pairs, independent of the camera.
    -- Unlike FOLD faceOrders, these may constrain separated panels too.
    layerRequirements :: !(Maybe (V3, [(FaceId, FaceId)]))
  }
  deriving stock (Eq, Show)

data SurfaceError
  = SurfaceFrameError !FoldError
  | SurfaceNonFinite !VertexId
  | SurfaceMaterialMismatch
  | SurfaceMaterialNotFlat !VertexId
  | SurfaceMissingMaterial !VertexId
  | SurfaceInvalidMaterialCoordinates
  | SurfaceMaterialCount !Int !Int
  | SurfaceInvalidMaterialPoint !VertexId
  | SurfaceBadThickness !Double
  | SurfaceBadDirection !V3
  | SurfaceBadLayerPair !FaceId !FaceId
  | SurfaceBadRefinement !Int
  | SurfaceNonConvex !FaceId
  | SurfaceNonPlanar !FaceId
  | SurfaceDegenerateFan !FaceId
  | SurfaceJoinedCut !EdgeId
  | SurfaceMissingVertex !VertexId
  deriving stock (Eq, Show)

surfaceSamples :: Surface material -> [Sample material]
surfaceSamples = storedSamples

surfaceThickness :: Surface material -> Maybe Double
surfaceThickness = materialThickness

surfaceLayerRequirements :: Surface material -> Maybe (V3, [(FaceId, FaceId)])
surfaceLayerRequirements = layerRequirements

instance Explain SurfaceError where
  explain = \case
    SurfaceFrameError err -> explain err
    SurfaceNonFinite vid -> "surface vertex " <> tshow vid <> " needs finite coordinates"
    SurfaceMaterialMismatch -> "the material pattern and folded surface must use the same vertex, edge and panel ids"
    SurfaceMaterialNotFlat vid -> "material vertex " <> tshow vid <> " must lie in the original z = 0 sheet"
    SurfaceMissingMaterial vid -> "surface vertex " <> tshow vid <> " has no original-sheet coordinates; material measurements need the source pattern"
    SurfaceInvalidMaterialCoordinates -> "senbazuru:material_coords must be an array of two-coordinate material points"
    SurfaceMaterialCount expected actual -> "senbazuru:material_coords needs " <> tshow expected <> " points, one per surface vertex, but has " <> tshow actual
    SurfaceInvalidMaterialPoint vid -> "senbazuru:material_coords vertex " <> tshow vid <> " needs exactly two finite coordinates"
    SurfaceBadThickness t -> "physical thickness must be a finite nonnegative distance, got " <> tshow t
    SurfaceBadDirection v -> "layer requirements need a finite nonzero direction, got " <> tshow v
    SurfaceBadLayerPair a b -> "layer requirement " <> tshow a <> " / " <> tshow b <> " must name two distinct surface panels"
    SurfaceBadRefinement n -> "surface subdivision level must be between 0 and 5, got " <> tshow n
    SurfaceNonConvex fid -> "surface panel " <> tshow fid <> " must be convex to triangulate by a fan"
    SurfaceNonPlanar fid -> "surface panel " <> tshow fid <> " must be planar to subdivide as a rigid panel"
    SurfaceDegenerateFan fid -> "surface panel " <> tshow fid <> " has a zero-area or unrepresentable triangle in its first-corner fan"
    SurfaceJoinedCut eid -> "cut edge " <> tshow eid <> " still shares vertices between panels; split the cut topology before refining it"
    SurfaceMissingVertex vid -> "surface topology refers to missing vertex " <> tshow vid

-- | Read already prepared faces. A caller needing to trace absent faces first
-- uses Fold.Crossings.withPlanarFaces; a crease-pattern drawing deliberately
-- does not acquire that policy just by using this representation.
surfaceFromFrame :: Frame -> Either SurfaceError (Surface (Maybe V2))
surfaceFromFrame fr = do
  points <- checkedPoints fr
  let known = frameKind (frameClasses fr) points == CreasePattern && all ((== 0) . v3z) points
      material (V3 u v _) = if known then Just (V2 u v) else Nothing
  original <- case KM.lookup "senbazuru:material_coords" (frameExtras fr) of
    Nothing -> Right (map material points)
    Just value -> case fromJSON value of
      Error _ -> Left SurfaceInvalidMaterialCoordinates
      Success coordinates -> do
        unless (length coordinates == length points) (Left (SurfaceMaterialCount (length points) (length coordinates)))
        traverse readMaterial (zip [0 ..] coordinates)
  buildSurface fr original points
  where
    readMaterial (i, [u, v])
      | all finite [u, v] = Right (Just (V2 u v))
      | otherwise = Left (SurfaceInvalidMaterialPoint (VertexId i))
    readMaterial (i, _) = Left (SurfaceInvalidMaterialPoint (VertexId i))

-- | Use the CUT pattern returned by folding, with the folded frame's winding.
-- An original input can have different ids after crossing cuts; it is not a
-- material map for these vertices. Folded's two frames share that numbering.
surfaceFromFolded :: Folded -> Either SurfaceError (Surface V2)
surfaceFromFolded folded = do
  let flat = foldedPattern folded
      placed = foldedFrame folded
  material <- checkedPoints flat
  points <- checkedPoints placed
  unless (length material == length points && edgesVertices flat == edgesVertices placed && map sort (facesVertices flat) == map sort (facesVertices placed)) $
    Left SurfaceMaterialMismatch
  mapM_ (\(i, V3 _ _ z) -> unless (z == 0) (Left (SurfaceMaterialNotFlat (VertexId i)))) (zip [0 ..] material)
  buildSurface placed [V2 u v | V3 u v _ <- material] points

-- | Refine the knowledge carried by a read frame before measuring material.
-- The type of the result guarantees coordinates for every sample; callers
-- cannot replace missing coordinates with the current folded x/y position.
requireMaterialCoordinates :: Surface (Maybe V2) -> Either SurfaceError (Surface V2)
requireMaterialCoordinates sheet = do
  known <- traverse require (zip [0 ..] (surfaceSamples sheet))
  pure sheet {storedSamples = known}
  where
    require (i, Sample material p) = case material of
      Nothing -> Left (SurfaceMissingMaterial (VertexId i))
      Just uv -> Right (Sample uv p)

checkedPoints :: Frame -> Either SurfaceError [V3]
checkedPoints fr = do
  points <- first SurfaceFrameError (frameVertices fr)
  mapM_ (\(i, p) -> unless (finitePoint p) (Left (SurfaceNonFinite (VertexId i)))) (zip [0 ..] points)
  pure points

buildSurface :: Frame -> [material] -> [V3] -> Either SurfaceError (Surface material)
buildSurface fr material points = do
  _ <- first SurfaceFrameError (frameFaces fr)
  _ <- first SurfaceFrameError (frameCreases fr)
  _ <- first SurfaceFrameError (frameFaceOrders fr)
  -- Positions and material are constructed together by the public producers.
  unless (length material == length points) (Left SurfaceMaterialMismatch)
  pure (Surface fr {verticesCoords = []} (zipWith Sample material points) Nothing Nothing)

surfaceFrame :: Surface material -> Frame
surfaceFrame sheet = (topology sheet) {verticesCoords = [let V3 x y z = position p in [x, y, z] | p <- surfaceSamples sheet]}

-- | Geometry plus the study's existing explicit original-sheet map. Ordinary
-- 'surfaceFrame' needs no material map and does not invent one. This export
-- requires known coordinates, so reloading it can retain them even when folded
-- x/y coordinates no longer describe the sheet. The key is our extension, not
-- a standard FOLD field. Physical thickness and directional requirements are
-- not serialised by this function. No contact certificate is implied.
materialFrame :: Surface V2 -> Frame
materialFrame sheet =
  let fr = surfaceFrame sheet
      coordinates = [[materialU p, materialV p] | p <- surfaceSamples sheet]
   in fr {frameExtras = KM.insert "senbazuru:material_coords" (toJSON coordinates) (frameExtras fr)}

surfaceFaces :: Surface material -> Either SurfaceError [Face]
surfaceFaces = first SurfaceFrameError . frameFaces . surfaceFrame

-- | Store coplanar FOLD orders against the existing panel winding. Directional
-- requirements for open panels remain separate and are not written as FOLD
-- orders just because the same pair of panels occurs in both.
withFaceOrders :: [FaceOrder] -> Surface material -> Either SurfaceError (Surface material)
withFaceOrders orders sheet = do
  _ <- first SurfaceFrameError (frameFaceOrders (surfaceFrame sheet) {faceOrders = orders})
  pure sheet {topology = (topology sheet) {faceOrders = orders, frameExtras = mempty}}

surfacePanelSamples :: Surface material -> Either SurfaceError [(FaceId, [Sample material])]
surfacePanelSamples sheet = do
  faces <- surfaceFaces sheet
  let indexed = IM.fromList (zip [0 ..] (surfaceSamples sheet))
      lookupSample vid = maybe (Left (SurfaceMissingVertex vid)) Right (IM.lookup (unVertexId vid) indexed)
  traverse (\face -> (,) (faceId face) <$> traverse lookupSample (faceVertexIds face)) faces

-- | Original border/crease edges and their incident panels. A guide that has
-- a nonzero angle is active too; mesh diagonals never enter this list.
surfaceFeatures :: Surface material -> Either SurfaceError [(Crease, [FaceId])]
surfaceFeatures sheet = do
  let fr = surfaceFrame sheet
      angles = IM.fromList (zip [0 ..] (edgesFoldAngle fr))
      active c = creaseAssignment c `elem` [Border, Mountain, Valley, Unassigned, Cut] || abs (IM.findWithDefault 0 (unEdgeId (creaseId c)) angles) > 1e-10
  creases <- first SurfaceFrameError (frameCreases fr)
  faces <- surfaceFaces sheet
  let owners = M.fromListWith (++) [(edgeKey a b, [faceId face]) | face <- faces, (a, b) <- ringEdges (faceVertexIds face)]
  pure [(c, sort (M.findWithDefault [] (edgeKey (creaseFrom c) (creaseTo c)) owners)) | c <- creases, active c]

-- | Change the stationary reference frame, moving layer directions with it.
-- This moves all shared vertices together and leaves material coordinates and
-- physical thickness unchanged. It is not a folding-state interpolator.
transformSurface :: Rigid -> Surface material -> Either SurfaceError (Surface material)
transformSurface motion sheet = do
  let points = [p {position = applyRigid motion (position p)} | p <- surfaceSamples sheet]
      dimension = if hasRelief (map position points) then "3D" else "2D"
      attribute a = if a `elem` ["2D", "3D"] then dimension else a
      moved = sheet {storedSamples = points, topology = (topology sheet) {frameAttributes = map attribute (frameAttributes (topology sheet)), frameExtras = mempty}}
  _ <- checkedPoints (surfaceFrame moved)
  case surfaceLayerRequirements sheet of
    Nothing -> Right moved
    Just (axis, pairs) -> withLayerRequirements (matApply (rigidLinear motion) axis) pairs moved

-- | Thickness in the same model units as the coordinates. 'Nothing' means
-- unspecified; @Just 0@ explicitly describes zero thickness. No current
-- renderer or contact check interprets this property as a display offset.
withPhysicalThickness :: Maybe Double -> Surface material -> Either SurfaceError (Surface material)
withPhysicalThickness thickness sheet = do
  mapM_ (\t -> unless (finite t && t >= 0) (Left (SurfaceBadThickness t))) thickness
  pure sheet {materialThickness = thickness}

withLayerRequirements :: V3 -> [(FaceId, FaceId)] -> Surface material -> Either SurfaceError (Surface material)
withLayerRequirements direction pairs sheet = do
  unless (finitePoint direction && finite (norm direction) && norm direction > 0) (Left (SurfaceBadDirection direction))
  let count = length (facesVertices (topology sheet))
      valid fid = unFaceId fid >= 0 && unFaceId fid < count
  mapM_ (\(a, b) -> unless (a /= b && valid a && valid b) (Left (SurfaceBadLayerPair a b))) pairs
  pure sheet {layerRequirements = Just (direction, pairs)}

-- | Convex, planar panels as triangles with shared edge midpoints and one
-- original panel id per triangle. Refinement never rewrites the surface's
-- crease graph or creates new physical creases.
refineSurface :: Int -> Surface V2 -> Either SurfaceError (MaterialMesh, [FaceId])
refineSurface levels sheet = do
  refined <- refineSurfaceWithEdges levels sheet
  pure (refinedMesh refined, refinedPanels refined)

-- | Subdivide geometry and source-edge ownership together. Matching starts
-- from vertex ids, never material or spatial coordinates: two cut edges can
-- occupy exactly the same line and still remain separate material.
refineSurfaceWithEdges :: Int -> Surface V2 -> Either SurfaceError RefinedSurface
refineSurfaceWithEdges levels sheet = do
  unless (levels >= 0 && levels <= 5) (Left (SurfaceBadRefinement levels))
  faces <- surfaceFaces sheet
  features <- surfaceFeatures sheet
  mapM_ (\(edge, owners) -> unless (creaseAssignment edge /= Cut || length owners <= 1) (Left (SurfaceJoinedCut (creaseId edge)))) features
  mapM_ planarConvex faces
  let tagged = [(triangle, faceId face) | face <- faces, triangle <- fan (map unVertexId (faceVertexIds face))]
      meshKeys = S.fromList [edgeKey (VertexId a) (VertexId b) | ((i, j, k), _) <- tagged, (a, b) <- [(i, j), (j, k), (k, i)]]
      edges = [(EdgeId i, (unVertexId a, unVertexId b)) | (i, (a, b)) <- zip [0 ..] (edgesVertices (surfaceFrame sheet)), S.member (edgeKey a b) meshKeys]
  (points, refined, segments) <- subdivide levels (surfaceSamples sheet) tagged edges
  pure (RefinedSurface (Mesh points (map fst refined)) (map snd refined) segments)
  where
    span' = modelSpan (map position (surfaceSamples sheet))
    scale = if span' > 0 then span' else 1
    hair = 1e-9 * scale
    planarConvex face = case faceCorners face of
      [] -> Left (SurfaceNonConvex (faceId face))
      origin : _ -> case normalize (polygonNormal (faceCorners face)) of
        Nothing -> Left (SurfaceNonConvex (faceId face))
        Just normal@(V3 nx ny nz) -> do
          unless (all ((<= hair) . abs . dot normal . (^-^ origin)) (faceCorners face)) (Left (SurfaceNonPlanar (faceId face)))
          let flatten (V3 x y z)
                | abs nx >= max (abs ny) (abs nz) = V2 y z
                | abs ny >= abs nz = V2 x z
                | otherwise = V2 x y
          unless (isConvex (1e-12 * scale * scale) (map flatten (faceCorners face))) (Left (SurfaceNonConvex (faceId face)))
          let areas = [norm (cross (b ^-^ a) (c ^-^ a)) | (a, b, c) <- fan (faceCorners face)]
          unless (all (\area -> finite area && area > 0) areas) (Left (SurfaceDegenerateFan (faceId face)))

fan :: [a] -> [(a, a, a)]
fan (a : b : c : rest) = (a, b, c) : fan (a : c : rest)
fan _ = []

subdivide :: Int -> [MaterialSample] -> [(Triangle, FaceId)] -> [(EdgeId, (Int, Int))] -> Either SurfaceError ([MaterialSample], [(Triangle, FaceId)], [(EdgeId, (Int, Int))])
subdivide 0 points faces edges = Right (points, faces, edges)
subdivide n points faces edges = do
  let indexed = IM.fromList (zip [0 ..] points)
      keys = S.toList (S.fromList [ordered i j | ((a, b, c), _) <- faces, (i, j) <- [(a, b), (b, c), (c, a)]])
      lookupPoint i = maybe (Left (SurfaceMissingVertex (VertexId i))) Right (IM.lookup i indexed)
      midpoint (a, b) = do
        p <- lookupPoint a
        q <- lookupPoint b
        pure (materialSample ((materialU p + materialU q) / 2) ((materialV p + materialV q) / 2) (0.5 *^ (position p ^+^ position q)))
  added <- traverse midpoint keys
  let ids = M.fromList (zip keys [length points ..])
      lookupMid a b = maybe (Left (SurfaceMissingVertex (VertexId a))) Right (M.lookup (ordered a b) ids)
      split ((a, b, c), panel) = do
        ab <- lookupMid a b
        bc <- lookupMid b c
        ca <- lookupMid c a
        pure [((a, ab, ca), panel), ((ab, b, bc), panel), ((ca, bc, c), panel), ((ab, bc, ca), panel)]
  refined <- concat <$> traverse split faces
  segments <- concat <$> traverse (\(eid, (a, b)) -> do mid <- lookupMid a b; pure [(eid, (a, mid)), (eid, (mid, b))]) edges
  subdivide (n - 1) (points ++ added) refined segments
  where
    ordered a b = (min a b, max a b)

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)

finitePoint :: V3 -> Bool
finitePoint (V3 x y z) = all finite [x, y, z]
