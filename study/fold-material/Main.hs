-- | Generate the fold-material cases and their inspectable measurements.
-- Run from the repository root; see study/fold-material/README.md.
module Main (main) where

import BasicBaseGallery (writeBasicBases)
import Control.Monad (unless)
import Data.Aeson (Value, eitherDecode, encode, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.ByteString.Lazy qualified as BL
import Data.Char (isAsciiLower, isDigit)
import Data.IntMap.Strict qualified as IM
import Data.List (find, foldl', nub, sortOn)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Ord (Down (..))
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldContact
import FoldMaterial
import FoldRelaxation
import PanelContact
import Senbazuru.Diagram (Colour (..), Diagram (..), Shape (..), solid)
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid)
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types (FoldFile (..))
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Render.Camera (View (..), basisFrom, bottomUp, depth, isometric, project)
import Senbazuru.Render.Steps (stepPage)
import Senbazuru.Render.Svg (Page (..), defaultPage, escapeXml, renderSvg)
import StudyCase
import System.Directory (createDirectoryIfMissing)
import System.Environment (getArgs)
import System.Exit (die)
import System.FilePath ((</>))

data Surface = Rounded | Sharp | Relaxed
  deriving stock (Eq, Show)

main :: IO ()
main = do
  args <- getArgs
  case args of
    [destination] -> generate destination
    ["--bird-svg", destination] -> writeBirdSequence destination
    ["--basic-bases", destination] -> writeBasicBases destination
    _ -> die "usage: stack run senbazuru-material-study -- [--bird-svg | --basic-bases] OUTPUT_DIRECTORY (from repository root)"

generate :: FilePath -> IO ()
generate destination = do
  createDirectoryIfMissing True destination
  specs <- BL.readFile "study/fold-material/cases.json" >>= either die pure . eitherDecode
  unless (not (null specs) && length (nub (map caseId specs)) == length specs && all validCase specs) $
    die "study cases need unique lowercase ids, nonempty steps"
  authored <- mapM loadCase specs
  runs <- mapM solve [("single", Single), ("double", Double)]
  let cases = [("single", Single), ("double", Double)]
      styles = [("rounded", Rounded, makeMesh 32), ("sharp", Sharp, sharpMesh 16)]
      starting = [(style ++ "-" ++ name, surface, which, build which) | (style, surface, build) <- styles, (name, which) <- cases]
      fitted = [(checkpointName name point, Relaxed, which, checkpointMesh point) | (name, which, result) <- runs, point <- checkpoints result]
      models = starting ++ fitted
      dataSet = object ([Key.fromString name .= modelValue surface which mesh | (name, surface, which, mesh) <- models] ++ [Key.fromString key .= authoredValue pose | (_, poses) <- authored, (key, _, pose) <- poses])
      catalog = object [Key.fromString (caseId spec) .= object ["title" .= caseTitle spec, "description" .= caseDescription spec, "source" .= caseSource spec, "fixedPanel" .= caseFixedPanel spec, "contact" .= caseContact spec, "steps" .= [object ["key" .= key, "label" .= poseLabel step, "angles" .= poseAngles step] | (key, step, _) <- poses]] | (spec, poses) <- authored]
      progress = object [Key.fromString name .= progressValue name which result | (name, which, result) <- runs]
  mapM_ (writeModel destination) models
  mapM_ (writeAuthored destination) [pose | (_, poses) <- authored, pose <- poses]
  writeBirdSequence destination
  writeBasicBases destination
  BL.writeFile (destination </> "cases.json") (encode catalog)
  BL.writeFile (destination </> "measurements.json") (encode (object ([Key.fromString name .= metrics surface which mesh | (name, surface, which, mesh) <- models] ++ [Key.fromString key .= meshMetrics Nothing (poseContact pose) (poseMesh pose) | (_, poses) <- authored, (key, _, pose) <- poses])))
  BL.writeFile (destination </> "relaxation.json") (encode progress)
  template <- TIO.readFile "study/fold-material/viewer.html"
  let json = TE.decodeUtf8 (BL.toStrict (encode dataSet))
  TIO.writeFile (destination </> "index.html") (T.replace "/*CASE_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode catalog))) (T.replace "/*RELAXATION_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode progress))) (T.replace "/*MODEL_DATA*/null" json template)))
  putStrLn ("Wrote study meshes, baseline SVGs, measurements.json, relaxation.json and index.html to " ++ destination)
  where
    solve (name, which) = case relaxPacket defaultSettings which (sharpMesh 16 which) of
      Left err -> die (T.unpack (explain err))
      Right result -> pure (name, which, result)

-- | The first study-to-library handoff uses ordinary FOLD and the same page
-- renderer as `senbazuru render --steps`. Keep the fast command available so
-- regenerating this fixture does not rerun the unrelated packet relaxation.
writeBirdSequence :: FilePath -> IO ()
writeBirdSequence destination = do
  createDirectoryIfMissing True destination
  specs <- BL.readFile "study/fold-material/cases.json" >>= either die pure . eitherDecode
  spec <- maybe (die "bird-petal case missing") pure (find ((== "bird-petal") . caseId) (specs :: [CaseSpec]))
  source <- loadFoldFile (caseSource spec) >>= either (die . T.unpack . explain) pure
  file <- either (die . T.unpack . explain) pure (buildCaseSequence spec source)
  BL.writeFile (destination </> "bird-base-sequence.fold") (encode file)
  above <- sideView (-1)
  below <- sideView 1
  mapM_ (writePage grid (otherFrames file) 1000) [("side-above", above), ("side-below", below), ("iso", isometric), ("bottom", bottomUp)]
  -- A compact README preview: the square, each petal lifted to 90 degrees,
  -- then the finished base. Reuse the checked states and the page's camera.
  let preview = [fr | (i, fr) <- zip [0 :: Int ..] (otherFrames file), i `elem` [0, 4, 11, 15]]
  -- The caption names these snapshots; they are not four consecutive steps.
  writePage grid {gridNumbering = Nothing} preview 300 ("preview", above)
  template <- TIO.readFile "study/fold-material/bird-sequence.html"
  let labels = T.concat ["<li>" <> escapeXml (poseLabel step) <> "</li>" | step <- caseSteps spec]
  TIO.writeFile (destination </> "bird-sequence.html") (T.replace "<!--STEPS-->" labels template)
  where
    -- Look along the x axis with equal horizontal and vertical components:
    -- 45 degrees above/below the sheet. Seeing the petal from its side makes
    -- its lift clearer than looking straight along its line of symmetry.
    sideView z = maybe (die "bird sequence side camera is invalid") pure (basisFrom (V3 (-1) 0 z) (V3 0 0 1))
    grid = (defaultGrid defaultTheme) {gridColumns = 4}
    writePage layout frames height (name, basis) = do
      result <- either (die . T.unpack . explain) pure (stepPage defaultTheme defaultBudget layout (View (Just basis) 0) False frames)
      diagram <- maybe (die "bird sequence has no figures") pure result
      TIO.writeFile (destination </> "bird-sequence-" ++ name ++ ".svg") (renderSvg defaultPage {pageWidth = 1000, pageHeight = height} diagram)

validCase :: CaseSpec -> Bool
validCase spec = not (null (caseId spec)) && all (\c -> isAsciiLower c || isDigit c || c == '-') (caseId spec) && not (null (caseSteps spec))

loadCase :: CaseSpec -> IO (CaseSpec, [(String, PoseSpec, StudyPose)])
loadCase spec = do
  source <- loadFoldFile (caseSource spec) >>= either (die . T.unpack . explain) pure
  poses <- mapM (build (keyFrame source)) (zip [0 :: Int ..] (caseSteps spec))
  pure (spec, poses)
  where
    build source (i, step) = case buildCasePose 3 spec source step of
      Left err -> die (caseId spec ++ " / " ++ T.unpack (poseLabel step) ++ ": " ++ T.unpack (explain err))
      Right pose -> pure (caseId spec ++ "-step-" ++ show i, step, pose)

writeAuthored :: FilePath -> (String, PoseSpec, StudyPose) -> IO ()
writeAuthored destination (key, step, pose) = do
  TIO.writeFile (destination </> key ++ ".obj") (obj (poseMesh pose))
  BL.writeFile (destination </> key ++ ".fold") (encode (surfaceFoldValue (T.unpack (poseLabel step)) (poseContact pose) (poseMesh pose)))

authoredValue :: StudyPose -> Value
authoredValue pose =
  let mesh = poseMesh pose
      (axis, orders) = fromMaybe (V3 0 0 1, []) (poseOrders pose)
      -- Each pass carries a lower panel's level to its upper neighbour.
      -- Contact validation has already refused cycles; N panels need at most
      -- N-1 passes. These levels only break depth ties in the viewer.
      initial = IM.fromList [(i, 0 :: Int) | (i, _) <- poseFaces pose]
      advance current = foldl' (\next (a, b) -> IM.insertWith max b (1 + IM.findWithDefault 0 a current) next) current orders
      levels = foldl' (\current _ -> advance current) initial (poseFaces pose)
      middle :: Double
      middle = fromIntegral (maximum (0 : IM.elems levels)) / 2
      rank i = fromIntegral (IM.findWithDefault 0 i levels) - middle
      -- A crease belongs to both incident panels. Draw each copy at its own
      -- depth level so viewing from either side reveals the right one.
      featureLines = [(a, b, rank i) | ((a, b), owners) <- zip (poseLines pose) (poseLinePanels pose), i <- owners]
   in object
        [ "positions" .= map (coords . position) (samples mesh),
          "material" .= map (\s -> [materialU s, materialV s]) (samples mesh),
          "triangles" .= map indices (triangles mesh),
          "panels" .= posePanels pose,
          "lines" .= [[coords a, coords b] | (a, b, _) <- featureLines],
          "depthRanks" .= map rank (posePanels pose),
          "lineDepthRanks" .= [r | (_, _, r) <- featureLines],
          "orderDirection" .= coords ((1 / norm axis) *^ axis),
          "metrics" .= meshMetrics Nothing (poseContact pose) mesh,
          "strain" .= measuredStrain mesh,
          "measuredStrain" .= measuredStrain mesh
        ]

checkpointName :: String -> Checkpoint -> String
checkpointName name point = "relaxed-" ++ name ++ "-" ++ show (completedIterations point)

progressValue :: String -> FoldCase -> Relaxation -> Value
progressValue name which result =
  object
    [ "converged" .= converged result,
      "tolerance" .= lengthTolerance defaultSettings,
      "contactTolerance" .= contactTolerance,
      "iterationLimit" .= iterationLimit defaultSettings,
      "steps" .= [object ["key" .= checkpointName name point, "iterations" .= completedIterations point, "error" .= checkpointError point, "contactError" .= maxOrderViolation (packetCheck which (checkpointMesh point))] | point <- checkpoints result]
    ]

writeModel :: FilePath -> (String, Surface, FoldCase, Mesh) -> IO ()
writeModel destination (name, surface, which, mesh) = do
  TIO.writeFile (destination </> name ++ ".obj") (obj mesh)
  BL.writeFile (destination </> name ++ ".fold") (encode (foldValue surface which mesh))
  -- This SVG painter assumes a fixed packet order. A relaxed mesh can violate
  -- that order, so offering it as a preview would hide actual intersections.
  if surface == Relaxed then pure () else TIO.writeFile (destination </> name ++ ".svg") (svg surface which mesh)

coords :: V3 -> [Double]
coords (V3 x y z) = [x, y, z]

indices :: Triangle -> [Int]
indices (a, b, c) = [a, b, c]

metrics :: Surface -> FoldCase -> Mesh -> Value
metrics surface which mesh = meshMetrics (if surface == Rounded then Nothing else Just (packetCheck which mesh)) Nothing mesh

meshMetrics :: Maybe PacketCheck -> Maybe ContactCheck -> Mesh -> Value
meshMetrics contact panels mesh =
  object
    [ "vertices" .= length (samples mesh),
      "triangles" .= length (triangles mesh),
      "connectedComponents" .= componentCount mesh,
      "surfaceAreaRatio" .= areaRatio mesh,
      "minEdgeStrain" .= minimum (0 : edgeStrains mesh),
      "maxEdgeStrain" .= maximum (0 : edgeStrains mesh),
      "minPrincipalStrain" .= minimum (0 : map fst (triangleStrains mesh)),
      "maxPrincipalStrain" .= maximum (0 : map snd (triangleStrains mesh)),
      "packetOrder" .= fmap contactValue contact,
      "panelContact" .= panels
    ]

contactValue :: PacketCheck -> Value
contactValue result =
  object
    [ "violatingPairs" .= violatingPairs result,
      "maxViolation" .= maxOrderViolation result,
      "uncheckedTriangles" .= uncheckedTriangles result
    ]

modelValue :: Surface -> FoldCase -> Mesh -> Value
modelValue surface which mesh =
  object
    [ "positions" .= map (coords . position) (samples mesh),
      "material" .= map (\s -> [materialU s, materialV s]) (samples mesh),
      "triangles" .= map indices (triangles mesh),
      "depthRanks" .= map triangleRank (resolvedTriangles mesh),
      "lineDepthRanks" .= [triangleRank (a, b, c) | (a, b, c) <- resolvedTriangles mesh, (p, q) <- [(a, b), (b, c), (c, a)], feature surface which p q],
      "panels" .= [if surface == Rounded then 0 else fromEnum (materialU a + materialU b + materialU c > 1.5) + 2 * fromEnum (which == Double && materialV a + materialV b + materialV c > 1.5) | (a, b, c) <- resolvedTriangles mesh],
      "lines" .= [[coords (position p), coords (position q)] | (a, b, c) <- resolvedTriangles mesh, (p, q) <- [(a, b), (b, c), (c, a)], feature surface which p q],
      "metrics" .= metrics surface which mesh,
      "strain" .= (if surface == Relaxed then measuredStrain mesh else map strain (resolvedTriangles mesh)),
      "measuredStrain" .= measuredStrain mesh
    ]
  where
    triangleRank (a, b, c) = packetLayer which ((materialU a + materialU b + materialU c) / 3) ((materialV a + materialV b + materialV c) / 3)
    extension = if surface == Sharp then sharpStretch else analyticStretch
    strain (a, b, c) = extension which ((materialU a + materialU b + materialU c) / 3) ((materialV a + materialV b + materialV c) / 3)

triangleStrains :: Mesh -> [(Double, Double)]
triangleStrains = mapMaybe principalStrains . resolvedTriangles

measuredStrain :: Mesh -> [Double]
measuredStrain = map (\(small, large) -> if abs small > abs large then small else large) . triangleStrains

foldValue :: Surface -> FoldCase -> Mesh -> Value
foldValue surface which = surfaceFoldValue (show surface ++ " " ++ show which) Nothing

surfaceFoldValue :: String -> Maybe ContactCheck -> Mesh -> Value
surfaceFoldValue title contact mesh =
  object $
    [ "file_spec" .= (1.2 :: Double),
      "file_creator" .= ("senbazuru fold-material study" :: T.Text),
      "file_title" .= title,
      "frame_classes" .= ["foldedForm" :: T.Text],
      "frame_attributes" .= ["3D" :: T.Text],
      "frame_unit" .= ("unit" :: T.Text),
      "frame_description" .= ("Generated zero-thickness study surface. Authored cases prescribe rigid crease angles; corrected single/double checkpoints fit lengths and the known packet order. No general contact or bending model is solved. Shared indices identify original material; see measurements.json and cases.json for checks and authored states." :: T.Text),
      "vertices_coords" .= map (coords . position) (samples mesh),
      "faces_vertices" .= map indices (triangles mesh),
      "senbazuru:material_coords" .= map (\s -> [materialU s, materialV s]) (samples mesh)
    ]
      ++ maybe [] (\report -> ["senbazuru:panel_contact" .= report]) contact

obj :: Mesh -> T.Text
obj mesh =
  T.unlines $
    ["# Connected material mid-surface study. No finite thickness or paper stiffness is solved."]
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
          layer = packetLayer which u v
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
   in boundary || (surface /= Rounded && crease)
