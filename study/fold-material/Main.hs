-- | Generate the two fold-material examples and their inspectable measurements.
-- Run from the repository root; see study/fold-material/README.md.
module Main (main) where

import Data.Aeson (Value, encode, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.ByteString.Lazy qualified as BL
import Data.List (sortOn)
import Data.Ord (Down (..))
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldMaterial
import Senbazuru.Diagram (Colour (..), Diagram (..), Shape (..), solid)
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Render.Camera (depth, isometric, project)
import Senbazuru.Render.Svg (Page (..), defaultPage, renderSvg)
import System.Directory (createDirectoryIfMissing)
import System.Environment (getArgs)
import System.Exit (die)
import System.FilePath ((</>))

data Surface = Rounded | Sharp
  deriving stock (Eq, Show)

main :: IO ()
main = do
  args <- getArgs
  case args of
    [destination] -> generate destination
    _ -> die "usage: stack run senbazuru-material-study -- OUTPUT_DIRECTORY (from repository root)"

generate :: FilePath -> IO ()
generate destination = do
  createDirectoryIfMissing True destination
  let cases = [("single", Single), ("double", Double)]
      styles = [("rounded", Rounded, makeMesh 32), ("sharp", Sharp, sharpMesh 16)]
      models = [(style ++ "-" ++ name, surface, which, build which) | (style, surface, build) <- styles, (name, which) <- cases]
      dataSet = object [Key.fromString name .= modelValue surface which mesh | (name, surface, which, mesh) <- models]
  mapM_ (writeModel destination) models
  BL.writeFile (destination </> "measurements.json") (encode (object [Key.fromString name .= metrics mesh | (name, _, _, mesh) <- models]))
  template <- TIO.readFile "study/fold-material/viewer.html"
  let json = TE.decodeUtf8 (BL.toStrict (encode dataSet))
  TIO.writeFile (destination </> "index.html") (T.replace "/*MODEL_DATA*/null" json template)
  putStrLn ("Wrote single and double .obj, .fold, .svg, measurements.json and index.html to " ++ destination)

writeModel :: FilePath -> (String, Surface, FoldCase, Mesh) -> IO ()
writeModel destination (name, surface, which, mesh) = do
  TIO.writeFile (destination </> name ++ ".obj") (obj mesh)
  BL.writeFile (destination </> name ++ ".fold") (encode (foldValue surface which mesh))
  TIO.writeFile (destination </> name ++ ".svg") (svg surface which mesh)

coords :: V3 -> [Double]
coords (V3 x y z) = [x, y, z]

indices :: Triangle -> [Int]
indices (a, b, c) = [a, b, c]

metrics :: Mesh -> Value
metrics mesh =
  object
    [ "vertices" .= length (samples mesh),
      "triangles" .= length (triangles mesh),
      "connectedComponents" .= componentCount mesh,
      "surfaceAreaRatio" .= areaRatio mesh,
      "minEdgeStrain" .= minimum (0 : edgeStrains mesh),
      "maxEdgeStrain" .= maximum (0 : edgeStrains mesh)
    ]

modelValue :: Surface -> FoldCase -> Mesh -> Value
modelValue surface which mesh =
  object
    [ "positions" .= map (coords . position) (samples mesh),
      "material" .= map (\s -> [materialU s, materialV s]) (samples mesh),
      "triangles" .= map indices (triangles mesh),
      "lines" .= [[coords (position p), coords (position q)] | (a, b, c) <- resolvedTriangles mesh, (p, q) <- [(a, b), (b, c), (c, a)], feature surface which p q],
      "metrics" .= metrics mesh,
      "strain" .= map strain (resolvedTriangles mesh)
    ]
  where
    extension = if surface == Sharp then sharpStretch else analyticStretch
    strain (a, b, c) = extension which ((materialU a + materialU b + materialU c) / 3) ((materialV a + materialV b + materialV c) / 3)

foldValue :: Surface -> FoldCase -> Mesh -> Value
foldValue surface which mesh =
  object
    [ "file_spec" .= (1.2 :: Double),
      "file_creator" .= ("senbazuru fold-material study" :: T.Text),
      "file_title" .= (show surface ++ " " ++ show which),
      "frame_classes" .= ["foldedForm" :: T.Text],
      "frame_attributes" .= ["3D" :: T.Text],
      "frame_unit" .= ("unit" :: T.Text),
      "frame_description" .= ("Generated geometric study. Double folds distort material; not physical solutions. Shared indices identify original material." :: T.Text),
      "vertices_coords" .= map (coords . position) (samples mesh),
      "faces_vertices" .= map indices (triangles mesh),
      "senbazuru:material_coords" .= map (\s -> [materialU s, materialV s]) (samples mesh)
    ]

obj :: Mesh -> T.Text
obj mesh =
  T.unlines $
    ["# Connected material mid-surface. Double is a geometric counterexample, not a physical simulation."]
      ++ ["v " <> T.unwords (map (T.pack . show) (coords (position s))) | s <- samples mesh]
      ++ ["f " <> T.unwords (map (T.pack . show . (+ 1)) (indices t)) | t <- triangles mesh]

-- | A study preview using the existing Camera -> Diagram -> SVG pipeline.
-- The known packet order is painted bottom to top, sorting triangles within
-- each layer. Sorting ALL triangles by centre depth interleaves overlapping
-- layers: a triangle's centre is not the depth of its whole footprint.
-- This is specific to these almost-flat packets seen from above; it is not a
-- general hidden-surface algorithm. The WebGL viewer uses a depth buffer.
svg :: Surface -> FoldCase -> Mesh -> T.Text
svg surface which mesh = renderSvg page (Diagram (Box (V2 (-0.8) (-0.5)) (V2 0.8 0.7)) shapes)
  where
    page = defaultPage {pageWidth = 700, pageHeight = 525, pageMargin = 25, pageTitle = Just (T.pack (show which) <> " fold — geometric study")}
    order (a, b, c) =
      let u = (materialU a + materialU b + materialU c) / 3
          v = (materialV a + materialV b + materialV c) / 3
          firstHalf = if u <= 0.5 then 0 else 1 :: Int
          layer = if which == Single || v <= 0.5 then 2 + firstHalf else 1 - firstHalf
          centreDepth = depth isometric ((1 / 3) *^ (position a ^+^ position b ^+^ position c))
       in (layer, Down centreDepth)
    ordered = sortOn order (resolvedTriangles mesh)
    points = map (project isometric . position) (samples mesh)
    xs = map (\(V2 x _) -> x) points
    ys = map (\(V2 _ y) -> y) points
    middle values = (minimum (0 : values) + maximum (0 : values)) / 2
    centre = V2 (middle xs) (middle ys - 0.15)
    onPage = (^-^ centre) . project isometric . position
    projected (a, b, c) =
      let normal = cross (position b ^-^ position a) (position c ^-^ position a)
          colour = if dot normal (V3 1 (-1) 1) > 0 then Colour "#e5a86d" else Colour "#f5e9d6"
          edges = [Polyline (solid (Colour "#5d5042") 0.8) [onPage p, onPage q] | (p, q) <- [(a, b), (b, c), (c, a)], feature surface which p q]
       in Fill colour [map onPage [a, b, c]] : edges
    -- Merge adjacent fills until a stroke interrupts painting order. A hidden
    -- edge is painted before the nearer triangles that cover it.
    merge (Fill colour rings) (Fill next other : rest)
      | colour == next = Fill colour (rings ++ other) : rest
    merge shape rest = shape : rest
    drawing = foldr merge [] (concatMap projected ordered)
    label = T.pack (show surface ++ " " ++ show which) <> if which == Single then " · preserves lengths" else " · prescribed shape, measurable stretch"
    shapes = drawing ++ [Polyline (solid (Colour "#c7baa8") 0.7) [V2 (-0.7) (-0.32), V2 0.7 (-0.32)], Label (Colour "#342d27") 15 (V2 (-0.7) (-0.4)) label]

-- | Only the sheet boundary and actual sharp creases get ink. Triangulation
-- edges subdivide a surface for display; they are not additional crease marks.
feature :: Surface -> FoldCase -> Sample -> Sample -> Bool
feature surface which a b =
  let along coordinate value = coordinate a == value && coordinate b == value
      boundary = any (\coordinate -> along coordinate 0 || along coordinate 1) [materialU, materialV]
      crease = along materialU 0.5 || (which == Double && along materialV 0.5)
   in boundary || (surface == Sharp && crease)
