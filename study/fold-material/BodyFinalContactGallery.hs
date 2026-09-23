-- | Explain the final saved 46–70 refusal without proposing another move.
-- The overlap guard and whole-triangle plane test measure different points:
-- vertex 27 lies outside triangle 70's top-view outline. Extending that
-- triangle's plane to the vertex is legitimate for the crossing test, but
-- is not another overlap corner or a physical contact there.
--
-- All paper drawings share unmodified positions and fixed crops. The margin
-- chart is explicitly a measurement plot: it magnifies distance minus the
-- stopping threshold, not the paper. Source validation lives in BodyShortArchive.
module BodyFinalContactGallery (writeBodyFinalContact) where

import BodyContactDiagnosis
import BodyContactGallery (boxAround)
import BodyCorrectionArchive
import BodyDirectionGallery (pairWitnesses)
import BodyPatch
import BodyPatchCheckpoints (SavedPoint (..))
import BodyPatchSubdivisionGallery (writeState)
import BodyShortArchive
import Control.Monad (forM, forM_, unless)
import CraneSpread
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.List (sortOn)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldContact qualified as F
import Senbazuru.Diagram
import Senbazuru.Explain (num)
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.Polygon (distanceOutside, signedArea)
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (panelTolerance)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Svg
import SurfaceContact qualified as C
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (takeDirectory, (</>))

data Inspected = Inspected
  { inspectedState :: ShortState,
    inspectedSection :: PairSection,
    inspectedWitnesses :: [C.ContactWitness],
    inspectedVertex :: V3,
    inspectedDistance :: Double,
    inspectedOutside :: Double,
    inspectedExtendedGap :: Double
  }

writeBodyFinalContact :: FilePath -> FilePath -> IO ()
writeBodyFinalContact source destination = do
  let output = destination </> "body-final"
  separateOutput source output
  archive <- readShortArchive source
  let study = shortStudy archive
      fixture = patchSpread study
      states = sortOn shortScale (shortStates archive)
  model <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) (spreadMesh fixture))
  inspected <- forM states $ \state -> do
    let mesh = shortMesh state
    cut <- checked (pairSection mesh (46, 70))
    ids <- triangleIds mesh 46
    distance <- maybe (die "triangle 46 no longer contains vertex 27") pure (lookup 27 (zip ids (firstDistances cut)))
    vertex <- vertexAt mesh 27
    points <- triangleIds mesh 70 >>= traverse (vertexAt mesh)
    normal <- case points of
      [a, b, c] -> pure (let n = cross (b ^-^ a) (c ^-^ a) in (1 / norm n) *^ n)
      _ -> die "expected triangle 70"
    ws <- pairWitnesses (46, 70) <$> checked (C.contactWitnesses model mesh)
    unless (length ws == 4) (die "the final pair must retain four overlap corners")
    let outline = map xy points
        -- Only the 2D outline is rewound for distanceOutside's convention.
        -- Plane distances keep the original 3D face winding and its sign.
        outside = distanceOutside (if signedArea outline < 0 then reverse outline else outline) (xy vertex)
        V3 _ _ nz = normal
        -- d = nz * (vertexHeight - planeHeight). The upper-minus-lower
        -- vertical gap to the extended plane therefore has the opposite sign.
        extended = negate distance / nz
    unless (outside > 0 && abs nz > 1e-12) (die "expected vertex 27 outside the projected triangle with a nonvertical plane")
    pure (Inspected state cut ws vertex distance outside extended)
  let overlapBox = boxAround [xy p | item <- inspected, w <- inspectedWitnesses item, p <- [C.witnessLower w, C.witnessUpper w]]
      tipBox = boxAround [xy p | item <- inspected, p <- inspectedVertex item : intersectionEnds (inspectedSection item) ++ [C.witnessLower w | w <- inspectedWitnesses item, F.contactGap (C.witnessRow w) < 0]]
  createDirectoryIfMissing True output
  forM_ (shortFiles archive) $ \(name, bytes) -> do
    let path = output </> "source" </> name
    createDirectoryIfMissing True (takeDirectory path)
    BL.writeFile path bytes
  constraints <- field "constraints" (shortAttempt archive) :: IO [Value]
  linearGaps <- field "guardLinearGaps" (shortAttempt archive) :: IO [Double]
  unless (length constraints == length linearGaps) (die "saved gap predictions lost their corner indices")
  predictions <- fmap concat $ forM (zip constraints linearGaps) $ \(record, predicted) -> do
    pair <- field "triangles" record :: IO [Int]
    gap <- field "rawGap" record
    pure [(gap, predicted - max 0 gap) | pair == [46, 70]]
  unless (length predictions == 4) (die "saved attempt has no four-corner prediction for 46–70")
  entries <- forM inspected $ \item -> do
    let state = inspectedState item
        mesh = shortMesh state
        cut = inspectedSection item
        ws = inspectedWitnesses item
        name = shortName state
    measured <- writeState output name (shortTitle state) study (SavedPoint 10 mesh)
    forM_ [("pair", overlapBox), ("tip", tipBox)] $ \(view, box) -> do
      drawing <- drawInspection box item
      TIO.writeFile (output </> name ++ "-" ++ view ++ ".svg") drawing
    first <- triangleIds mesh 46
    second <- triangleIds mesh 70
    pure (object ["id" .= name, "title" .= shortTitle state, "sourceFile" .= shortSource state, "scale" .= shortScale state, "state" .= measured, "vertex27" .= xyz (inspectedVertex item), "vertex27PlaneDistance" .= inspectedDistance item, "thresholdMargin" .= (inspectedDistance item + panelTolerance), "vertex27OutsideDistance" .= inspectedOutside item, "extendedVerticalGapAt27" .= inspectedExtendedGap item, "firstVertices" .= first, "secondVertices" .= second, "firstDistances" .= firstDistances cut, "secondDistances" .= secondDistances cut, "firstStraddles" .= straddles (firstDistances cut), "secondStraddles" .= straddles (secondDistances cut), "sectionFirst" .= map xyz (sectionFirst cut), "sectionSecond" .= map xyz (sectionSecond cut), "intersection" .= map xyz (intersectionEnds cut), "intersectionLength" .= intersectionLength cut, "crosses" .= sectionCrosses cut, "minimumGap" .= minimum (map (F.contactGap . C.witnessRow) ws), "predictedMinimumGap" .= minimum [g + shortScale state * d | (g, d) <- predictions], "witnesses" .= [object ["lower" .= xyz (C.witnessLower w), "upper" .= xyz (C.witnessUpper w), "gap" .= F.contactGap (C.witnessRow w)] | w <- ws]])
  TIO.writeFile (output </> "threshold.svg") (drawMargins inspected)
  let result = object ["gallery" .= ("body-final" :: Text), "issue" .= (342 :: Int), "newSolves" .= (0 :: Int), "sourceAttempt" .= (10 :: Int), "validatedSourceTrials" .= (310 :: Int), "pair" .= [46 :: Int, 70], "contactTolerance" .= panelTolerance, "lengthTolerance" .= (1e-5 :: Double), "drawingScale" .= (600 :: Double), "continuousMotionChecked" .= False, "wholeCraneChecked" .= False, "overlapBounds" .= boxValue overlapBox, "tipBounds" .= boxValue tipBox, "states" .= entries]
  BL.writeFile (output </> "checks.json") (encode result)
  template <- TIO.readFile "study/fold-material/body-final.html"
  TIO.writeFile (destination </> "body-final.html") (T.replace "/*BODY_FINAL_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode result))) template)
  putStrLn ("Inspected the saved final contact without solving. Wrote " ++ destination </> "body-final.html")

drawInspection :: Box -> Inspected -> IO Text
drawInspection bounds item = do
  let mesh = shortMesh (inspectedState item)
      ws = inspectedWitnesses item
      vertex = xy (inspectedVertex item)
  rings <- forM [(46, "#7056a2"), (70, "#c98225")] $ \(i, colour) -> do
    points <- triangleIds mesh i >>= traverse (vertexAt mesh)
    pure (line colour 1.4 (map xy (points ++ take 1 points)))
  let marks = [Offset (V2 (-4) 4) (Label (Colour "#177970") 12 (xy (C.witnessLower w)) "●") | w <- ws]
      gapLabels = [Offset (V2 (-75) 24) (Label (Colour "#177970") 13 (xy (C.witnessLower w)) "Gap corner") | w <- ws, F.contactGap (C.witnessRow w) < 0]
      shapes = rings ++ [line "#b82643" 3 (map xy (intersectionEnds (inspectedSection item)))] ++ marks ++ gapLabels ++ [Offset (V2 (-4) 4) (Label (Colour "#235e87") 14 vertex "●"), Offset (V2 8 (-12)) (Label (Colour "#235e87") 13 vertex "Vertex 27")]
      page = defaultPage {pageWidth = 560, pageHeight = 440, pageMargin = 28, pageBackground = Nothing, pageTitle = Just "Triangle 46 (purple), triangle 70 (orange), overlap gap corner (green) and vertex 27 (blue)"}
  pure (renderSvg page (diagramWithExtent bounds shapes))

drawMargins :: [Inspected] -> Text
drawMargins items = renderSvg page (diagramWithExtent bounds shapes)
  where
    values = [(fromIntegral i, 1e12 * (inspectedDistance item + panelTolerance), shortName (inspectedState item)) | (i, item) <- zip [0 :: Int ..] items]
    bounds = Box (V2 (-0.5) (-0.4)) (V2 2.5 1.5)
    shapes = line "#918b7e" 1 [V2 (-0.4) 0, V2 2.4 0] : concat [let colour = if y < 0 then "#b82643" else "#235e87" in [line colour 14 [V2 x 0, V2 x y], Offset (V2 (-38) 0) (Label (Colour "#55584f") 13 (V2 x (-0.29)) (T.pack name)), Offset (V2 (-32) (if y < 0 then -28 else -10)) (Label (Colour colour) 12 (V2 x y) (num y))] | (x, y, name) <- values]
    page = defaultPage {pageWidth = 720, pageHeight = 300, pageMargin = 28, pageBackground = Nothing, pageTitle = Just "Distance to the negative plane threshold, in units of 1e-12 sheet lengths"}

straddles :: [Double] -> Bool
straddles ds = any (< negate panelTolerance) ds && any (> panelTolerance) ds

triangleIds :: MaterialMesh -> Int -> IO [Int]
triangleIds mesh i = maybe (die ("missing triangle " ++ show i)) (\(a, b, c) -> pure [a, b, c]) (IM.lookup i (IM.fromList (zip [0 ..] (triangles mesh))))

vertexAt :: MaterialMesh -> Int -> IO V3
vertexAt mesh i = maybe (die ("missing vertex " ++ show i)) (pure . position) (IM.lookup i (IM.fromList (zip [0 ..] (samples mesh))))

line :: Text -> Double -> [V2] -> Shape
line colour width = Polyline (solid (Colour colour) width)

boxValue :: Box -> [[Double]]
boxValue (Box (V2 a b) (V2 c d)) = [[a, b], [c, d]]

xy :: V3 -> V2
xy (V3 x y _) = V2 x y
