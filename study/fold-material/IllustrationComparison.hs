-- | Compare the same material surface at a declared drawing scale. Material
-- coordinates are positions on the original sheet (see docs/glossary.md).
-- Merely matching old vertices misses bends at new vertices; even taking both
-- vertex sets misses intersections of differently oriented subdivision edges.
-- Instead, intersect every pair of material triangles. Their spatial
-- difference is linear on each overlap, so its largest projected length is
-- attained at an overlap corner. This measures the whole piecewise-flat sheet,
-- without moving a vertex or solving for a new shape.
--
-- Visibility is a separate question. A small displacement may uncover a buried
-- crease. The gallery therefore also renders the existing SVG backend and
-- exports masks from its projected visible regions for a sampled pixel check.
module IllustrationComparison
  ( IllustrationError (..),
    illustrationViews,
    materialDifferences,
    projectedChange,
    sharedExtent,
    illustrationPage,
    visibleMasks,
    inkOverlay,
  )
where

import Control.Monad (unless)
import Data.IntMap.Strict qualified as IM
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Senbazuru.Diagram
import Senbazuru.Diagram.Style
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..), boxFromPoints)
import Senbazuru.Geometry.Polygon (clipConvex, cross2, signedArea)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Senbazuru.Origami.Visible
import Senbazuru.Render.Camera
import Senbazuru.Render.Svg

newtype IllustrationError = IllustrationError Text deriving stock (Eq, Show)

instance Explain IllustrationError where explain (IllustrationError message) = message

illustrationViews :: Either IllustrationError [(Text, Text, Basis)]
illustrationViews = do
  above <- camera (V3 0 (-1) (-1))
  below <- camera (V3 0 (-1) 1)
  low <- camera (V3 0 (-1) (-tan (pi / 12)))
  pure [("top", "Top", topDown), ("above", "Side · 45° above", above), ("below", "Side · 45° below", below), ("low", "Side · 15° above", low)]
  where
    camera direction = maybe (Left (IllustrationError "invalid study camera")) Right (basisFrom direction (V3 0 0 1))

-- | Exact locations of the extrema for two triangulated material maps, up to
-- the polygon clipper's floating-point arithmetic. The gallery additionally
-- checks both meshes against the same authored sheet before calling this.
materialDifferences :: MaterialMesh -> MaterialMesh -> Either IllustrationError [V3]
materialDifferences a b = do
  as <- materialTriangles a
  bs <- materialTriangles b
  let overlaps = [(x, y, ring) | x <- as, y <- bs, let ring = clipConvex (map sampleMaterial x) (map sampleMaterial y), abs (signedArea ring) > 1e-14]
      covered = sum [abs (signedArea ring) | (_, _, ring) <- overlaps]
      area ts = sum [abs (signedArea (map sampleMaterial t)) | t <- ts]
  unless (abs (covered - area as) < 1e-10 && abs (covered - area bs) < 1e-10 && covered > 0) $
    Left (IllustrationError "refinement meshes must cover the same material area")
  sequence [liftMaterial x p >>= \u -> (u ^-^) <$> liftMaterial y p | (x, y, ring) <- overlaps, p <- ring]

materialTriangles :: MaterialMesh -> Either IllustrationError [[MaterialSample]]
materialTriangles mesh = traverse triangle (triangles mesh)
  where
    points = IM.fromList (zip [0 ..] (samples mesh))
    triangle (a, b, c) = do
      ps <- traverse (\i -> maybe (Left (IllustrationError "missing material vertex")) Right (IM.lookup i points)) [a, b, c]
      unless (abs (signedArea (map sampleMaterial ps)) > 1e-14) (Left (IllustrationError "degenerate material triangle"))
      -- The clipper expects anticlockwise polygons; retain each point's
      -- spatial position when reversing the material triangle.
      pure (if signedArea (map sampleMaterial ps) < 0 then reverse ps else ps)

liftMaterial :: [MaterialSample] -> V2 -> Either IllustrationError V3
liftMaterial [a, b, c] p =
  let u = sampleMaterial b ^-^ sampleMaterial a
      v = sampleMaterial c ^-^ sampleMaterial a
      q = p ^-^ sampleMaterial a
      determinant = cross2 u v
      wb = cross2 q v / determinant
      wc = cross2 u q / determinant
   in Right ((1 - wb - wc) *^ position a ^+^ wb *^ position b ^+^ wc *^ position c)
liftMaterial _ _ = Left (IllustrationError "expected a material triangle")

projectedChange :: Basis -> [V3] -> Double
projectedChange basis = maximum . (0 :) . map (norm . project basis)

-- | All poses share this box for one camera. Scale is never fitted separately
-- to each mesh: fitting would hide real movement and introduce false movement.
sharedExtent :: Basis -> [MaterialMesh] -> Either IllustrationError Box
sharedExtent basis = maybe (Left (IllustrationError "no points to draw")) Right . boxFromPoints . map (project basis . position) . concatMap samples

illustrationPage :: Text -> Box -> Page
illustrationPage title (Box (V2 x0 y0) (V2 x1 y1)) =
  defaultPage
    { pageWidth = 600 * (x1 - x0) + 40,
      pageHeight = 600 * (y1 - y0) + 40,
      pageMargin = 20,
      pageBackground = Nothing,
      pageTitle = Just title
    }

-- | The layer colours identify source panels, independently of front/back
-- paper colour. The masks do not change the paper or the ordinary SVG view.
visibleMasks :: Basis -> Box -> [FaceId] -> VisibleForm -> Either IllustrationError [(Text, Diagram)]
visibleMasks basis extent owners seen = do
  regions <- traverse owned (formRegions seen)
  let rings = concatMap snd regions
      colour n = if n == FaceId 0 then Colour "#ff0000" else Colour "#0000ff"
      layers = [Fill (colour n) (concat [ps | (owner, ps) <- regions, owner == n]) | n <- [FaceId 0, FaceId 1]]
      creases = [Polyline (solid (Colour "#000000") 1) [project basis (visibleFrom e), project basis (visibleTo e)] | e <- formEdges seen, visibleAssignment e `elem` [Mountain, Valley, Flat, Unassigned]]
  pure [("silhouette", diagramWithExtent extent [Fill (Colour "#000000") rings]), ("layers", diagramWithExtent extent layers), ("creases", diagramWithExtent extent creases)]
  where
    byFace = IM.fromList (zip [0 ..] owners)
    owned region = do
      owner <- maybe (Left (IllustrationError "visible region has no source panel")) Right (IM.lookup (unFaceId (regionFace region)) byFace)
      unless (owner `elem` [FaceId 0, FaceId 1]) (Left (IllustrationError "expected two source panels"))
      pure (owner, map (map (project basis)) (regionPieces region))

-- | Two coloured traces of the actual visible ink; no opacity, offset or
-- magnified gap. Projection and scale are exactly those of the full drawings.
inkOverlay :: Basis -> Box -> VisibleForm -> VisibleForm -> Diagram
inkOverlay basis extent a b = diagramWithExtent extent (inkFor (Colour "#007d9b") a ++ inkFor (Colour "#b83769") b)
  where
    inkFor colour = mapMaybe (edge colour) . formEdges
    edge colour e = do
      _ <- strokeFor defaultTheme FoldedFormNotation (visibleAssignment e)
      pure (Polyline (solid colour 0.8) [project basis (visibleFrom e), project basis (visibleTo e)])
