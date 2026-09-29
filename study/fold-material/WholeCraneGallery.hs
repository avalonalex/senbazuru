-- | Preserve a whole-crane guess and at most one bounded material adjustment.
-- Rendering reads the archived positions. It never launches another solve,
-- and every unaccepted state remains labelled as a static visual candidate.
module WholeCraneGallery (startWholeCrane, correctWholeCrane, viewWholeCrane) where

import BodyCorrectionArchive (checked, field, readArchiveBytes, separateOutput, xyz)
import BodyPatch (bodyPatch, patchSpread)
import BodyPatchSubdivisionGallery (equilibriumValue, stepValue)
import BodyVisibleLayersGallery (inheritedOrders, paperShapes, regions, writeSvg)
import Control.Monad (forM, forM_, unless, when)
import CraneBookDrawing
import CranePocket (buildCranePocket)
import CraneSpread
import Data.Aeson (Value, eitherDecode, encode, object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.List (find)
import Data.Maybe (isJust, isNothing)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending (Hinge (..), bendingEnergy, hingeAngle)
import FoldMaterial (areaRatio, componentCount, meshEdges)
import FoldRelaxation
import IllustrationComparison (illustrationPage, sharedExtent)
import IllustrationVisibility
import PaperLighting (panelCornerNormals)
import Senbazuru.Diagram
import Senbazuru.Diagram.Layout (Grid (..), gridOf)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.Polygon (signedArea)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Origami.Visible (Region (..), VisibleForm (..))
import Senbazuru.Render.Camera (basisFrom, project)
import Senbazuru.Render.Fidelity (geometryName)
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb, toGltfAxes)
import Senbazuru.Render.Svg (Page (..), renderSvg)
import SurfaceContact qualified as Contact
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)
import WholeCrane
import WholeCraneDrawing
import WholeCraneExport (viewerGlb)
import WholeCraneScreen (Screen (..), floorPixels, pictureFloor, screenFrom, screenJson, strainScreen, thresholdsJson)

startWholeCrane :: FilePath -> FilePath -> IO ()
startWholeCrane source destination = do
  let output = destination </> "whole-crane"
  separateOutput source output
  exists <- doesFileExist (output </> "initial.json")
  when exists (die "whole-crane initial.json exists; use the view or bounded correction command")
  study <- inputs source
  createDirectoryIfMissing True (output </> "source")
  readArchiveBytes source >>= BL.writeFile (output </> "source" </> "endpoint.fold")
  let fixture = wholeSpread study
  BL.writeFile (output </> "initial.json") (encode (object ["positions" .= positions (spreadMesh fixture), "pins" .= [(i, xyz p) | (i, p) <- IM.toList (spreadPins fixture)]]))
  viewWholeCrane destination

inputs :: FilePath -> IO WholeCrane
inputs path = do
  source <- loadFoldFile "examples/crane.fold" >>= checked
  atlas <- checked (buildCranePocket (keyFrame source))
  patch <- checked (bodyPatch atlas 1 10)
  file <- loadFoldFile path >>= checked
  reference <- loadFoldFile "study/fold-material/fixtures/whole-crane-body.fold" >>= checked
  unless (keyFrame file == keyFrame reference) (die "this bounded study requires the saved #394 body endpoint")
  body <- checked (surfaceFromFrame (keyFrame file) >>= requireMaterialCoordinates)
  let mesh = (spreadMesh (patchSpread patch)) {samples = surfaceSamples body}
  verified <- checked (spreadSurface (patchSpread patch) mesh)
  unless (keyFrame file == materialFrame verified) (die "saved body changed its material, triangles, edges or source identities")
  checked (wholeCrane atlas patch mesh)

readStudy :: FilePath -> IO WholeCrane
readStudy output = do
  study <- inputs (output </> "source" </> "endpoint.fold")
  initial <- readValue (output </> "initial.json")
  ps <- field "positions" initial
  pins <- field "pins" initial
  let fixture = wholeSpread study
  unless (ps == positions (spreadMesh fixture) && pins == [(i, xyz p) | (i, p) <- IM.toList (spreadPins fixture)]) (die "whole-crane initial construction or controls changed")
  pure study

correctWholeCrane :: FilePath -> IO ()
correctWholeCrane destination = do
  let output = destination </> "whole-crane"
  exists <- doesFileExist (output </> "run.json")
  when exists (die "bounded run already exists; use --whole-crane-view")
  study <- readStudy output
  let fixture = wholeSpread study
      guess = spreadMesh fixture
  contact <- checked (Contact.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) guess)
  putStrLn "One whole-crane adjustment: at most 40 corrections at length weight 1e8."
  hFlush stdout
  (run, audit) <- checked (tracePinnedContact (Settings 40 1e-5) (spreadPins fixture) (spreadHinges fixture) contact guess)
  let record = object ["iterationLimit" .= (40 :: Int), "lengthWeight" .= (1e8 :: Double), "contactWeight" .= (1e10 :: Double), "points" .= [object ["iteration" .= completedIterations p, "positions" .= positions (checkpointMesh p)] | p <- checkpoints run], "trace" .= map stepValue (solverSteps audit), "converged" .= converged run, "equilibrium" .= fmap equilibriumValue (equilibriumCheck run)]
  BL.writeFile (output </> "run.json") (encode record)
  putStrLn "Saved the bounded adjustment."
  hFlush stdout
  viewWholeCrane destination

viewWholeCrane :: FilePath -> IO ()
viewWholeCrane destination = do
  let output = destination </> "whole-crane"
  study <- readStudy output
  let fixture = wholeSpread study
      guess = spreadMesh fixture
  exists <- doesFileExist (output </> "run.json")
  run <- if exists then readValue (output </> "run.json") else pure (object [])
  endpoint <-
    if exists
      then do
        forM_ [("iterationLimit", 40), ("lengthWeight", 1e8), ("contactWeight", 1e10)] $ \(key, expected) -> do
          actual <- field key run
          unless (actual == (expected :: Double)) (die "whole-crane solver policy changed")
        records <- field "points" run :: IO [Value]
        trace <- field "trace" run :: IO [Value]
        indices <- traverse (field "iteration") trace :: IO [Int]
        unless (not (null indices) && indices == [1 .. length trace] && length trace <= 40) (die "invalid whole-crane correction history")
        starts <- traverse (field "start") trace
        ends <- traverse (field "candidate") trace
        unless (starts == take (length starts) (positions guess : ends)) (die "whole-crane trace does not continue the declared initial shape")
        let savedStates = IM.fromList ((0, positions guess) : zip indices ends)
        points <- forM records $ \r -> do
          iteration <- field "iteration" r
          ps <- field "positions" r >>= traverse vector
          unless (length ps == length (samples guess)) (die "whole-crane checkpoint count changed")
          unless (IM.lookup iteration savedStates == Just (map xyz ps)) (die "whole-crane checkpoint disagrees with the correction trace")
          let mesh = guess {samples = zipWith (\p q -> p {position = q}) (samples guess) ps}
          _ <- checked (spreadSurface fixture mesh)
          unless (spreadHeldError fixture mesh == 0) (die "whole-crane checkpoint moved a hold")
          pure mesh
        savedIndices <- traverse (field "iteration") records :: IO [Int]
        unless (take 1 savedIndices == [0] && take 1 (reverse savedIndices) == [length trace] && and (zipWith (<) savedIndices (drop 1 savedIndices))) (die "whole-crane checkpoint sequence is incomplete or unordered")
        case reverse points of p : _ -> pure p; _ -> die "missing whole-crane checkpoint"
      else pure guess
  drawnStates <- checked (wholeCranePoses study)
  let openings = wholeCraneOpenings
      -- A refused solve is neither folded nor placed, and no geometry level
      -- names it.
      states = drawnStates ++ [Pose "correction" "Refused material adjustment · diagnostic" Nothing endpoint | exists]
  measurements <- forM states $ \pose@(Pose name title geometry mesh) -> do
    sheet <- checked (spreadSurface fixture mesh)
    contact <- checked (spreadCheck fixture mesh)
    shape <- checked (wholeMeasurements study mesh)
    (crease, panel) <- checked (bendingEnergy (spreadHinges fixture) mesh)
    let points = IM.fromList (zip [0 ..] (samples mesh))
        edgeError = maximum (0 : [abs (norm (position a ^-^ position b) - norm (sampleMaterial a ^-^ sampleMaterial b)) | (i, j) <- meshEdges mesh, Just a <- [IM.lookup i points], Just b <- [IM.lookup j points]])
    bends <- forM (spreadHinges fixture) $ \h -> (,) h . fst <$> checked (hingeAngle h points)
    let angles = [object ["vertices" .= hingeVertices h, "role" .= show (hingeRole h), "preferredRadians" .= hingeRest h, "achievedRadians" .= angle, "stiffness" .= hingeStiffness h] | (h, angle) <- bends]
    screen <- checked (screenFrom study sheet contact bends mesh)
    BL.writeFile (output </> name ++ ".fold") (encode (FoldFile (Just 1.2) (Just "senbazuru whole-crane study") Nothing (Just title) Nothing [] (materialFrame sheet) []))
    -- The viewers get visible paper first, and how the pose was made
    -- (WholeCraneExport). The one pose no geometry level names, the refused
    -- adjustment, is a diagnostic no viewer loads: it stays complete like the
    -- study's other diagnostics, and records nothing.
    bytes <- checked (maybe (renderSurfaceGlb defaultBudget CompletePaper (Just title) sheet) (\g -> viewerGlb g title sheet) geometry)
    BS.writeFile (output </> name ++ ".glb") bytes
    when (name /= "correction") $ do
      normals <- checked (panelCornerNormals (refinedPanels (spreadRefined fixture)) mesh)
      BL.writeFile (output </> name ++ "-lighting.json") (encode (object ["vertices" .= [[a, b, c] | (a, b, c) <- triangles mesh], "normals" .= map (map (xyz . toGltfAxes)) normals]))
    putStrLn (name ++ ": relative edge error " ++ show (maxLengthError mesh) ++ "; " ++ show shape)
    hFlush stdout
    pure (object ["id" .= name, "title" .= title, "geometry" .= fmap geometryName geometry, "label" .= poseLabel pose, "vertices" .= length (samples mesh), "triangles" .= length (triangles mesh), "components" .= componentCount mesh, "areaRatio" .= areaRatio mesh, "maxRelativeEdgeError" .= maxLengthError mesh, "maxEdgeErrorPixels" .= (600 * edgeError), "shape" .= shape, "creaseEnergy" .= crease, "panelEnergy" .= panel, "contact" .= contact, "minPrincipalStrain" .= negate (screenSquash screen), "maxPrincipalStrain" .= screenStretch screen, "angles" .= angles, "screen" .= screenJson screen])
  views <- forM [("upright", "Crane upright · three-quarter", V3 1 (sqrt 2) (-1), V3 0 (-1) 0), ("opposite", "Opposite side · three-quarter", V3 1 (sqrt 2) 1, V3 0 (-1) 0), ("low", "Low angle · three-quarter", V3 1 0.4 (-1), V3 0 (-1) 0), ("head", "From the head · slight tilt", V3 1 0.25 0.15, V3 0 (-1) 0), ("tail", "From the tail · slight tilt", V3 (-1) 0.25 0.15, V3 0 (-1) 0), ("top", "Above the body · slight tilt", V3 0 1 0.15, V3 (-1) 0 0), ("side", "Crane upright · side", V3 0 0 (-1), V3 0 (-1) 0), ("oblique", "Earlier camera · Z up", V3 (-1) 1 (sqrt 2), V3 0 0 1), ("reverse", "Earlier reverse · Z up", V3 1 1 (sqrt 2), V3 0 0 1), ("front", "Earlier front · Z up", V3 0 1 0.2, V3 0 0 1), ("below", "Under the body · slight tilt", V3 0 (-1) 0.15, V3 1 0 0)] $ \(viewId, title, direction, up) -> do
    basis <- maybe (die "invalid whole-crane camera") pure (basisFrom direction up)
    bounds <- checked (sharedExtent basis (map poseMesh drawnStates))
    let page = illustrationPage title bounds
        owners = refinedPanels (spreadRefined fixture)
    shown <- forM drawnStates $ \pose@(Pose name _ _ mesh) -> do
      sheet <- checked (spreadSurface fixture mesh)
      let frame = surfaceFrame sheet
      inherited <- checked (inheritedOrders fixture frame)
      audit <- checked (illustrationVisibility (0.1 / 600) basis frame inherited)
      drawn <- case auditForm audit of
        Just visible | null (auditUncovered audit) -> pure (DepthDrawing visible [] 0)
        _ -> either (die . T.unpack) pure (depthDrawing basis frame inherited)
      let seen = depthForm drawn
          stem = name ++ "-" ++ viewId
          -- A placed pose's drawings say so in their title, the name a
          -- browser and a screen reader give the file.
          drawingPage = page {pageTitle = labelled pose <$> pageTitle page}
      let colourShapes = paperShapes basis (regions basis owners seen) seen
          shapes = map whitePaper colourShapes ++ [Fill (Colour "#bd4354") (depthMissing drawn)]
      writeSvg output drawingPage bounds stem shapes
      writeSvg output drawingPage bounds (stem ++ "-colours") (colourShapes ++ [Fill (Colour "#bd4354") (depthMissing drawn)])
      book <-
        if name == "spread-0" && viewId `elem` ["upright", "opposite", "low", "top"]
          then do
            drawing <- either (die . T.unpack) pure (bookDrawing basis owners mesh seen)
            let omitted = snd (selectedCreases 2 (bookCreases drawing))
                uncertainty = [Fill (Colour "#bd4354") (depthMissing drawn)]
                marks = [Polyline (solid (Colour "#c02f69") 2) [a, b] | (a, b) <- omitted]
                sourceArea = sum [abs (signedArea (map (project basis) ring)) | r <- formRegions seen, ring <- regionPieces r]
                toneArea = sum [abs (signedArea ring) | (_, rings) <- bookTones drawing, ring <- rings]
            unless (abs (sourceArea - toneArea) < 1e-10) (die "book tones changed visible paper coverage")
            writeSvg output drawingPage bounds (stem ++ "-book-full") (bookShapes 0 drawing ++ uncertainty)
            writeSvg output drawingPage bounds (stem ++ "-book") (bookShapes 2 drawing ++ uncertainty)
            writeSvg output drawingPage bounds (stem ++ "-book-omissions") (bookShapes 2 drawing ++ uncertainty ++ marks)
            pure [object ["id" .= viewId, "title" .= title, "stem" .= stem, "width" .= pageWidth page, "height" .= pageHeight page, "sourceAreaPixelsSquared" .= (360000 * sourceArea), "toneAreaPixelsSquared" .= (360000 * toneArea), "contours" .= [map xy [a, b] | (a, b) <- bookContours drawing], "creaseFragments" .= length (bookCreases drawing), "omittedCreases" .= [map xy [a, b] | (a, b) <- omitted], "tones" .= [object ["colour" .= colourText colour, "rings" .= map (map xy) rings] | (colour, rings) <- bookTones drawing]]]
          else pure []
      pure (shapes, object ["id" .= name, "stem" .= stem, "pictureFloorPixels" .= fmap floorPixels (pictureFloor basis 0 mesh), "pictureFloorPixelsAtScreen" .= fmap floorPixels (pictureFloor basis strainScreen mesh), "status" .= auditStatus audit, "resolved" .= (isJust (auditForm audit) && null (auditUncovered audit)), "unresolvedPairs" .= length [() | p <- auditPairs audit, isNothing (pairRelation p)], "depthPreviewMissingAreaPixelsSquared" .= (360000 * sum (map (abs . signedArea) (depthMissing drawn))), "depthPreviewIdTies" .= depthIdTies drawn, "previewRegions" .= [object ["triangle" .= unFaceId (regionFace r), "front" .= regionTopSide r, "pieces" .= map (map (xy . project basis)) (regionPieces r)] | r <- formRegions seen]], book)
    let comparisons = case viewId of
          "oblique" -> [("comparison.svg", 0, 1, "Before · closed crane", "First opened candidate")]
          "upright" -> [("pillow-comparison.svg", 0, 2, "Before · closed crane", "Wider pillow target"), ("compact-comparison.svg", 0, 3, "Before · closed crane", "Less spread target"), ("spread-comparison.svg", 2, 3, "Earlier · wider target", "Revised · less spread"), ("body-width-comparison.svg", 3, 4, "Previous body width", "Narrower body · same wing angle"), ("narrow-comparison.svg", 0, 4, "Before · closed crane", "Narrower body target")]
          "top" -> [("pillow-top-comparison.svg", 0, 2, "Before · closed crane", "Wider pillow target"), ("compact-top-comparison.svg", 0, 3, "Before · closed crane", "Less spread target"), ("body-width-top-comparison.svg", 3, 4, "Previous body width", "Narrower body · same wing angle")]
          _ -> []
    forM_ comparisons $ \(filename, left, right, leftLabel, rightLabel) -> do
      let Box (V2 x0 y0) (V2 x1 y1) = bounds
          labelledBounds = Box (V2 x0 y0) (V2 x1 (y1 + 0.08))
          figures = [diagramWithExtent labelledBounds (Label (Colour "#30352f") 14 (V2 x0 (y1 + 0.04)) (labelled pose label) : shapes) | (i, ((shapes, _, _), pose)) <- zip [0 :: Int ..] (zip shown drawnStates), (selected, label) <- [(left, leftLabel), (right, rightLabel)], i == selected]
      drawing <- maybe (die "no comparison figures") pure (gridOf (Grid 2 0.12 Nothing) figures)
      TIO.writeFile (output </> filename) (renderSvg (illustrationPage "Whole crane: before and after" (diagramExtent drawing)) drawing)
    pure (object ["id" .= viewId, "title" .= title, "direction" .= xyz direction, "up" .= xyz up, "width" .= pageWidth page, "height" .= pageHeight page, "states" .= [s | (_, s, _) <- shown]], concat [b | (_, _, b) <- shown])
  let bookReport = object ["pixelsPerSheetUnit" .= (600 :: Int), "minimumCreasePixels" .= (2 :: Int), "geometryChanged" .= False, "views" .= concatMap snd views]
  BL.writeFile (output </> "book-checks.json") (encode bookReport)
  bookTemplate <- TIO.readFile "study/fold-material/crane-book.html"
  TIO.writeFile (destination </> "crane-book.html") (T.replace "/*CRANE_BOOK_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode bookReport))) bookTemplate)
  let report = object ["issue" .= (399 :: Int), "newSolves" .= (if exists then 1 else 0 :: Int), "illustrationAccepted" .= False, "motionChecked" .= False, "inflationSimulated" .= False, "states" .= measurements, "screenThresholds" .= thresholdsJson, "openings" .= [object ["percent" .= percent, "id" .= name, "title" .= title, "wingArchStartDegrees" .= (-70 + fromIntegral percent * 0.4 :: Double)] | (percent, name, title) <- openings], "views" .= map fst views, "run" .= run, "pins" .= [(i, xyz p) | (i, p) <- IM.toList (spreadPins fixture)], "pillowConstruction" .= object ["newMaterialSolves" .= (0 :: Int), "savedBodyFixed" .= False, "rimY" .= (0.44 :: Double), "rise" .= (0.045 :: Double), "bodyHalfWidth" .= ((sqrt 2 - 1) / 2 :: Double), "wingArchStartDegrees" .= (-15 :: Double), "wingArchEndDegrees" .= (15 :: Double), "compactVariant" .= object ["bodyWidthScale" .= (0.75 :: Double), "wingArchStartDegrees" .= (-50 :: Double), "wingArchEndDegrees" .= (-20 :: Double)], "narrowVariant" .= object ["bodyWidthScale" .= (0.5 :: Double), "wingArchStartDegrees" .= (-50 :: Double), "wingArchEndDegrees" .= (-20 :: Double)]]]
  BL.writeFile (output </> "checks.json") (encode report)
  BL.writeFile (output </> "models.json") (encode [object ["title" .= labelled pose (poseTitle pose), "path" .= (poseName pose ++ ".glb")] | pose <- drawnStates])
  viewer <- TIO.readFile "study/gltf/viewer.html"
  TIO.writeFile (output </> "index.html") (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer)
  -- The 3D control selects these same files, visible paper first. It never
  -- derives another pose in JavaScript. Include the earlier targets in the
  -- common framing so changing shapes cannot silently move the camera or
  -- rescale.
  let viewerData = object ["models" .= [object ["title" .= poseTitle pose, "label" .= poseLabel pose, "path" .= (poseName pose ++ ".glb"), "lighting" .= (poseName pose ++ "-lighting.json")] | pose <- drawnStates], "openings" .= [object ["title" .= title, "label" .= (poseLabel =<< find ((== name) . poseName) drawnStates), "path" .= (name ++ ".glb")] | (_, name, title) <- openings], "defaultModel" .= ("spread-0.glb" :: T.Text)]
  spreadViewer <- TIO.readFile "study/fold-material/whole-crane-3d.html"
  TIO.writeFile (output </> "spread.html") (T.replace "/*CRANE_VIEW_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode viewerData))) (T.replace "./node_modules/" "../checked-flap/node_modules/" spreadViewer))
  lightingModule <- TIO.readFile "study/fold-material/paper-lighting.mjs"
  TIO.writeFile (output </> "paper-lighting.mjs") lightingModule
  template <- TIO.readFile "study/fold-material/whole-crane.html"
  TIO.writeFile (destination </> "whole-crane.html") (T.replace "/*WHOLE_CRANE_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode report))) template)

positions :: MaterialMesh -> [[Double]]
positions = map (xyz . position) . samples

-- | Text that names a pose, followed by what the pose is if it was placed
-- rather than folded: "Crane upright · three-quarter · shape sketch".
labelled :: Pose -> T.Text -> T.Text
labelled pose text = maybe text (\label -> text <> " · " <> label) (poseLabel pose)

readValue :: FilePath -> IO Value
readValue path = readArchiveBytes path >>= either die pure . eitherDecode

vector :: [Double] -> IO V3
vector [x, y, z] | all (\q -> not (isNaN q || isInfinite q)) [x, y, z] = pure (V3 x y z)
vector _ = die "expected three finite coordinates"

-- Plain paper has the same colour on both sides. The colour diagnostic uses
-- exactly the same visible pieces, so reverse-side patches stay inspectable.
whitePaper :: Shape -> Shape
whitePaper (Fill (Colour colour) rings) | colour `elem` ["#eee6cf", "#c58440"] = Fill (Colour "#eee6cf") rings
whitePaper shape = shape

xy :: V2 -> [Double]
xy (V2 x y) = [x, y]
