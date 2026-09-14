-- | Draw a material atlas, not an opened crane. Colours name regions of the
-- original sheet. Folded highlights include buried paper deliberately and
-- keep every vertex in place; they are labelled as x-ray views. All geometry
-- is prepared here as Diagram values, with the ordinary SVG writer handling
-- page scaling and y inversion. The unmodified FOLD and GLB remain available.
module CranePocketGallery (writeCranePocket, pocketReport, pocketSvg) where

import Control.Monad (forM_)
import CranePocket
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (nub, sort)
import Data.Map.Strict qualified as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Senbazuru.Diagram
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (Crease (..))
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..), boxFromPoints)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import Senbazuru.Render.Svg
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))

writeCranePocket :: FilePath -> IO ()
writeCranePocket destination = do
  let output = destination </> "crane-pocket"
  createDirectoryIfMissing True output
  source <- loadFoldFile "examples/crane.fold" >>= checked
  study <- checked (buildCranePocket (keyFrame source))
  let sheet = pocketSurface study
      report = pocketReport study
      file = FoldFile (Just 1.2) (Just "senbazuru crane pocket map") Nothing (Just "Unchanged crane for material mapping") Nothing [] (materialFrame sheet) []
  BL.writeFile (output </> "crane.fold") (encode file)
  BL.writeFile (output </> "map.json") (encode report)
  forM_ (Nothing : map Just regions) $ \selected -> do
    let key = maybe "all" regionKey selected
    TIO.writeFile (output </> T.unpack ("material-" <> key <> ".svg")) (pocketSvg False selected study)
    TIO.writeFile (output </> T.unpack ("folded-" <> key <> ".svg")) (pocketSvg True selected study)
  bytes <- checked (renderSurfaceGlb defaultBudget VisiblePaper (Just "Unchanged folded crane") sheet)
  BS.writeFile (output </> "crane.glb") bytes
  BL.writeFile (output </> "models.json") (encode [object ["title" .= ("Unchanged folded crane" :: Text), "path" .= ("crane.glb" :: Text)]])
  viewer <- TIO.readFile "study/gltf/viewer.html"
  TIO.writeFile (output </> "index.html") (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer)
  template <- TIO.readFile "study/fold-material/crane-pocket.html"
  TIO.writeFile (destination </> "crane-pocket.html") (T.replace "/*POCKET_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode report))) template)
  putStrLn ("Wrote crane-pocket.html, material maps and unchanged FOLD/GLB to " ++ destination)

pocketReport :: PocketMap -> Value
pocketReport study =
  object
    [ "regions" .= [object ["key" .= regionKey r, "title" .= regionName r, "colour" .= colourText (regionColour r), "faces" .= map unFaceId (regionFaces study r), "materialArea" .= regionArea study r] | r <- regions],
      "edges" .= map edgeValue (pocketEdges study),
      "interfaces" .= [object ["regions" .= map regionKey pair, "edges" .= map (unEdgeId . creaseId . pocketCrease) es] | (pair, es) <- M.toAscList interfaces],
      "coreBoundary" .= map unEdgeId (pocketCoreBoundary study),
      "centre" .= landmark (pocketCentre study),
      "tips" .= [object ["region" .= regionKey r, "landmark" .= landmark v] | (r, v) <- pocketTips study],
      "undersideLandmarks" .= map landmark (pocketLips study),
      "maxLipSeparation" .= maximum (0 : [norm (position p ^-^ position q) | a <- pocketLips study, b <- pocketLips study, Just p <- [M.lookup a points], Just q <- [M.lookup b points]]),
      "checks" .= object ["faces" .= M.size (pocketRegions study), "vertices" .= length (surfaceSamples sheet), "edges" .= length (pocketEdges study), "eulerCharacteristic" .= (length (surfaceSamples sheet) - length (pocketEdges study) + M.size (pocketRegions study)), "maxRelativeMaterialError" .= materialError study, "sourceOrders" .= length (faceOrders (surfaceFrame sheet)), "coreBoundaryIsInternal" .= True, "regionPartitionConnected" .= True, "geometryChanged" .= False, "closedCavityIdentified" .= False, "openingMotionChecked" .= False]
    ]
  where
    sheet = pocketSurface study
    points = M.fromList (zip (map VertexId [0 ..]) (surfaceSamples sheet))
    owners e = nub [r | fid <- pocketOwners e, Just r <- [M.lookup fid (pocketRegions study)]]
    interfaces = M.fromListWith (++) [(sort (owners e), [e]) | e <- pocketEdges study, length (owners e) == 2]
    edgeValue e = object ["id" .= unEdgeId (creaseId (pocketCrease e)), "assignment" .= creaseAssignment (pocketCrease e), "owners" .= map unFaceId (pocketOwners e), "regions" .= map regionKey (owners e), "role" .= roleName (pocketRole e)]
    landmark v = object (["id" .= unVertexId v] ++ ["material" .= [u, w] | Just p <- [M.lookup v points], let { V2 u w = sampleMaterial p }] ++ ["position" .= [x, y, z] | Just p <- [M.lookup v points], let V3 x y z = position p])

-- | A common full-sheet extent for every selection; the folded view likewise
-- keeps one scale. Turning both folded x and y round gives a 180-degree view,
-- with the closed wings pointing up. SVG's y inversion happens in renderSvg.
pocketSvg :: Bool -> Maybe Region -> PocketMap -> Text
pocketSvg folded selected study = renderSvg page drawing
  where
    sheet = pocketSurface study
    frame = surfaceFrame sheet
    ps = zip (map VertexId [0 ..]) (surfaceSamples sheet)
    point p = if folded then let V3 x y _ = position p in V2 (-x) (-y) else sampleMaterial p
    points = M.fromList [(v, point p) | (v, p) <- ps]
    ringPoints ring = [p | v <- ring, Just p <- [M.lookup v points]]
    tagged = zip (map FaceId [0 ..]) (facesVertices frame)
    shapes =
      [Fill (Colour "#e8e1d4") [ringPoints ring | (_, ring) <- tagged]]
        ++ [Fill (regionColour r) [ringPoints ring | (fid, ring) <- tagged, fid `elem` regionFaces study r] | r <- regions, maybe (not folded) (== r) selected]
        ++ [Polyline (edgeStroke e) (ringPoints [creaseFrom (pocketCrease e), creaseTo (pocketCrease e)]) | e <- pocketEdges study]
        ++ concat [marker p | v <- pocketLips study, Just p <- [M.lookup v points]]
        ++ [Offset (V2 5 (-5)) (Label (Colour "#853b67") 11 p ("v" <> tshow (unVertexId v))) | not folded, v <- pocketLips study, Just p <- [M.lookup v points]]
    drawing = diagramWithExtent (fromMaybe (Box (V2 0 0) (V2 1 1)) (boxFromPoints (M.elems points))) shapes
    page = defaultPage {pageWidth = 640, pageHeight = 560, pageMargin = 34, pageBackground = Nothing, pageTitle = Just (if folded then "Folded x-ray material map" else "Original-sheet material map")}
    marker (V2 x y) = [Polyline (solid (Colour "#853b67") 2) [V2 (x - 0.008) y, V2 (x + 0.008) y], Polyline (solid (Colour "#853b67") 2) [V2 x (y - 0.008), V2 x (y + 0.008)]]
    edgeStroke e
      | folded = solid (Colour "#59584d") (if pocketRole e == SheetBoundary then 1.1 else 0.5)
      | otherwise = case pocketRole e of
          SheetBoundary -> solid (Colour "#292d28") 1.6
          UncreasedConnection -> Stroke (Colour "#747469") 0.65 (Dash [2, 3])
          AuthoredRoot -> Stroke (Colour "#853b67") 1.8 (Dash [5, 3])
          CandidateOpening -> solid (Colour "#a13b1e") 2
          RetainedPreference -> solid (Colour "#55574e") 0.7

regionColour :: Region -> Colour
regionColour = \case
  BodyCore -> Colour "#e4bd66"
  WingA -> Colour "#91b3a3"
  WingB -> Colour "#94b4c9"
  Tail -> Colour "#d7a185"
  NeckHead -> Colour "#b2a0c2"

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
