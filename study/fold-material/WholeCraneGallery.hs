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
import Data.Maybe (isJust, isNothing)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending (Hinge (..), bendingEnergy, hingeBends)
import FoldMaterial (areaRatio, componentCount, meshEdges)
import FoldRelaxation
import IllustrationComparison (illustrationPage, illustrationScale, sharedExtent)
import IllustrationVisibility
import PaperLighting (panelCornerNormals)
import PaperScreen (sheetChords)
import ScreenReport (PageScale (..), Screen (..), pictureFloorJson, screenJson, thresholdsJson, writeScreenScript)
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
import WholeCraneScreen (screenFrom, turningOn)

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
  -- Which chords the floor may use depends only on the flat sheet, and every
  -- pose here keeps the sheet's material and triangles ('spreadSurface'
  -- checks), so one sheet's chords serve every pose and every picture.
  chords <- checked (sheetChords (refinedMesh (spreadRefined fixture)))
  -- Every drawing here is an illustration page, sized to its drawing at
  -- 'illustrationScale', so the page draws every pose at that scale, and
  -- screens it there (owner decision 30).
  let scale = PageScale illustrationScale
      -- An area in square pixels, from one in square sheet units.
      squarePixels = pixelsPerSheet scale * pixelsPerSheet scale
  -- The screen measures false creases a second time on each pose made again
  -- one level finer, from its construction; the first candidate is not made
  -- again.
  finer <- checked (finerCrane study)
  let states = map Drawn drawnStates ++ [Refused endpoint | exists]
  measurements <- forM states $ \state -> do
    let (name, title, mesh) = case state of
          Drawn pose -> (craneStem pose, craneTitle pose, craneMesh pose)
          Refused adjusted -> ("correction", "Refused material adjustment · diagnostic", adjusted)
        drawn = case state of
          Drawn pose -> Just pose
          Refused _ -> Nothing
    sheet <- checked (spreadSurface fixture mesh)
    contact <- checked (spreadCheck fixture mesh)
    shape <- checked (wholeMeasurements study mesh)
    (crease, panel) <- checked (bendingEnergy (spreadHinges fixture) mesh)
    let points = IM.fromList (zip [0 ..] (samples mesh))
        edgeError = maximum (0 : [abs (norm (position a ^-^ position b) - norm (sampleMaterial a ^-^ sampleMaterial b)) | (i, j) <- meshEdges mesh, Just a <- [IM.lookup i points], Just b <- [IM.lookup j points]])
    bends <- checked (hingeBends (spreadHinges fixture) mesh)
    let angles = [object ["vertices" .= hingeVertices h, "role" .= show (hingeRole h), "preferredRadians" .= hingeRest h, "achievedRadians" .= angle, "stiffness" .= hingeStiffness h] | (h, angle) <- bends]
    turningFiner <- case state of
      Drawn pose -> checked (turningOn finer study (craneConstruction pose))
      Refused _ -> pure Nothing
    screen <- checked (screenFrom study chords contact bends turningFiner mesh)
    BL.writeFile (output </> name ++ ".fold") (encode (FoldFile (Just 1.2) (Just "senbazuru whole-crane study") Nothing (Just title) Nothing [] (materialFrame sheet) []))
    case state of
      -- The viewers get visible paper first, the pose's name with its
      -- caveat, and how the pose was made (WholeCraneExport).
      Drawn pose -> do
        bytes <- checked (viewerGlb pose sheet)
        BS.writeFile (output </> name ++ ".glb") bytes
        normals <- checked (panelCornerNormals (refinedPanels (spreadRefined fixture)) mesh)
        BL.writeFile (output </> name ++ "-lighting.json") (encode (object ["vertices" .= [[a, b, c] | (a, b, c) <- triangles mesh], "normals" .= map (map (xyz . toGltfAxes)) normals]))
      -- The refused adjustment is a diagnostic no viewer loads. It stays
      -- complete like the study's other diagnostics, and records no level.
      Refused _ -> do
        bytes <- checked (renderSurfaceGlb defaultBudget CompletePaper (Just title) sheet)
        BS.writeFile (output </> name ++ ".glb") bytes
    putStrLn (name ++ ": relative edge error " ++ show (maxLengthError mesh) ++ "; " ++ show shape)
    hFlush stdout
    pure (object ["id" .= name, "title" .= title, "geometry" .= fmap (geometryName . craneGeometry) drawn, "caveat" .= (craneCaveat =<< drawn), "vertices" .= length (samples mesh), "triangles" .= length (triangles mesh), "components" .= componentCount mesh, "areaRatio" .= areaRatio mesh, "maxRelativeEdgeError" .= maxLengthError mesh, "maxEdgeErrorPixels" .= (pixelsPerSheet scale * edgeError), "shape" .= shape, "creaseEnergy" .= crease, "panelEnergy" .= panel, "contact" .= contact, "minPrincipalStrain" .= negate (screenSquash screen), "maxPrincipalStrain" .= screenStretch screen, "angles" .= angles, "screen" .= screenJson scale screen])
  views <- forM [("upright", "Crane upright · three-quarter", V3 1 (sqrt 2) (-1), V3 0 (-1) 0), ("opposite", "Opposite side · three-quarter", V3 1 (sqrt 2) 1, V3 0 (-1) 0), ("low", "Low angle · three-quarter", V3 1 0.4 (-1), V3 0 (-1) 0), ("head", "From the head · slight tilt", V3 1 0.25 0.15, V3 0 (-1) 0), ("tail", "From the tail · slight tilt", V3 (-1) 0.25 0.15, V3 0 (-1) 0), ("top", "Above the body · slight tilt", V3 0 1 0.15, V3 (-1) 0 0), ("side", "Crane upright · side", V3 0 0 (-1), V3 0 (-1) 0), ("oblique", "Earlier camera · Z up", V3 (-1) 1 (sqrt 2), V3 0 0 1), ("reverse", "Earlier reverse · Z up", V3 1 1 (sqrt 2), V3 0 0 1), ("front", "Earlier front · Z up", V3 0 1 0.2, V3 0 0 1), ("below", "Under the body · slight tilt", V3 0 (-1) 0.15, V3 1 0 0)] $ \(viewId, title, direction, up) -> do
    basis <- maybe (die "invalid whole-crane camera") pure (basisFrom direction up)
    bounds <- checked (sharedExtent basis (map craneMesh drawnStates))
    let page = illustrationPage title bounds
        owners = refinedPanels (spreadRefined fixture)
    shown <- forM drawnStates $ \pose -> do
      let name = craneStem pose
          mesh = craneMesh pose
      sheet <- checked (spreadSurface fixture mesh)
      let frame = surfaceFrame sheet
      inherited <- checked (inheritedOrders fixture frame)
      audit <- checked (illustrationVisibility (0.1 / pixelsPerSheet scale) basis frame inherited)
      drawn <- case auditForm audit of
        Just visible | null (auditUncovered audit) -> pure (DepthDrawing visible [] 0)
        _ -> either (die . T.unpack) pure (depthDrawing basis frame inherited)
      let seen = depthForm drawn
          stem = name ++ "-" ++ viewId
          -- A placed pose's drawings say so in their title, the name a
          -- browser and a screen reader give the file, and in a caption in
          -- the page's top margin, where it cannot cover paper or change the
          -- page's size and so the drawing's scale.
          drawingPage = illustrationPage (withCaveat pose title) bounds
          Box (V2 x0 _) (V2 _ y1) = bounds
          caveat = [Offset (V2 0 (-5)) (Label (Colour "#30352f") 12 (V2 x0 y1) text) | Just text <- [craneCaveat pose]]
      let colourShapes = paperShapes basis (regions basis owners seen) seen
          shapes = map whitePaper colourShapes ++ [Fill (Colour "#bd4354") (depthMissing drawn)]
      writeSvg output drawingPage bounds stem (shapes ++ caveat)
      writeSvg output drawingPage bounds (stem ++ "-colours") (colourShapes ++ [Fill (Colour "#bd4354") (depthMissing drawn)] ++ caveat)
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
            writeSvg output drawingPage bounds (stem ++ "-book-full") (bookShapes 0 drawing ++ uncertainty ++ caveat)
            writeSvg output drawingPage bounds (stem ++ "-book") (bookShapes 2 drawing ++ uncertainty ++ caveat)
            writeSvg output drawingPage bounds (stem ++ "-book-omissions") (bookShapes 2 drawing ++ uncertainty ++ marks ++ caveat)
            pure [object ["id" .= viewId, "title" .= title, "caveat" .= craneCaveat pose, "stem" .= stem, "width" .= pageWidth page, "height" .= pageHeight page, "sourceAreaPixelsSquared" .= (squarePixels * sourceArea), "toneAreaPixelsSquared" .= (squarePixels * toneArea), "contours" .= [map xy [a, b] | (a, b) <- bookContours drawing], "creaseFragments" .= length (bookCreases drawing), "omittedCreases" .= [map xy [a, b] | (a, b) <- omitted], "tones" .= [object ["colour" .= colourText colour, "rings" .= map (map xy) rings] | (colour, rings) <- bookTones drawing]]]
          else pure []
      pure (shapes, object (["id" .= name, "stem" .= stem] ++ pictureFloorJson scale chords basis mesh ++ ["status" .= auditStatus audit, "resolved" .= (isJust (auditForm audit) && null (auditUncovered audit)), "unresolvedPairs" .= length [() | p <- auditPairs audit, isNothing (pairRelation p)], "depthPreviewMissingAreaPixelsSquared" .= (squarePixels * sum (map (abs . signedArea) (depthMissing drawn))), "depthPreviewIdTies" .= depthIdTies drawn, "previewRegions" .= [object ["triangle" .= unFaceId (regionFace r), "front" .= regionTopSide r, "pieces" .= map (map (xy . project basis)) (regionPieces r)] | r <- formRegions seen]]), book)
    let comparisons = case viewId of
          "oblique" -> [("comparison.svg", "before", "after", "Before · closed crane", "First opened candidate")]
          "upright" -> [("pillow-comparison.svg", "before", "pillow", "Before · closed crane", "Wider pillow target"), ("compact-comparison.svg", "before", "compact", "Before · closed crane", "Less spread target"), ("spread-comparison.svg", "pillow", "compact", "Earlier · wider target", "Revised · less spread"), ("body-width-comparison.svg", "compact", "narrow", "Previous body width", "Narrower body · same wing angle"), ("narrow-comparison.svg", "before", "narrow", "Before · closed crane", "Narrower body target")]
          "top" -> [("pillow-top-comparison.svg", "before", "pillow", "Before · closed crane", "Wider pillow target"), ("compact-top-comparison.svg", "before", "compact", "Before · closed crane", "Less spread target"), ("body-width-top-comparison.svg", "compact", "narrow", "Previous body width", "Narrower body · same wing angle")]
          _ -> []
    forM_ comparisons $ \(filename, left, right, leftLabel, rightLabel) -> do
      let Box (V2 x0 y0) (V2 x1 y1) = bounds
          labelledBounds = Box (V2 x0 y0) (V2 x1 (y1 + 0.08))
          -- Each side is chosen by its pose's stem, so no reordering of the
          -- poses can put a caption on the wrong one.
          figures = [diagramWithExtent labelledBounds (Label (Colour "#30352f") 14 (V2 x0 (y1 + 0.04)) (withCaveat pose label) : shapes) | (selected, label) <- [(left, leftLabel), (right, rightLabel)], ((shapes, _, _), pose) <- zip shown drawnStates, craneStem pose == selected]
      unless (length figures == 2) (die ("whole-crane comparison names a pose the gallery does not draw: " ++ filename))
      drawing <- maybe (die "no comparison figures") pure (gridOf (Grid 2 0.12 Nothing) figures)
      TIO.writeFile (output </> filename) (renderSvg (illustrationPage "Whole crane: before and after" (diagramExtent drawing)) drawing)
    pure (object ["id" .= viewId, "title" .= title, "direction" .= xyz direction, "up" .= xyz up, "width" .= pageWidth page, "height" .= pageHeight page, "states" .= [s | (_, s, _) <- shown]], concat [b | (_, _, b) <- shown])
  let bookReport = object ["pixelsPerSheetUnit" .= pixelsPerSheet scale, "minimumCreasePixels" .= (2 :: Int), "geometryChanged" .= False, "views" .= concatMap snd views]
  BL.writeFile (output </> "book-checks.json") (encode bookReport)
  bookTemplate <- TIO.readFile "study/fold-material/crane-book.html"
  TIO.writeFile (destination </> "crane-book.html") (T.replace "/*CRANE_BOOK_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode bookReport))) bookTemplate)
  let report = object ["issue" .= (399 :: Int), "newSolves" .= (if exists then 1 else 0 :: Int), "illustrationAccepted" .= False, "motionChecked" .= False, "inflationSimulated" .= False, "states" .= measurements, "screenThresholds" .= thresholdsJson scale, "openings" .= [object ["percent" .= percent, "id" .= name, "title" .= title, "wingArchStartDegrees" .= (-70 + fromIntegral percent * 0.4 :: Double)] | (percent, name, title) <- wholeCraneOpenings], "views" .= map fst views, "run" .= run, "pins" .= [(i, xyz p) | (i, p) <- IM.toList (spreadPins fixture)], "pillowConstruction" .= object ["newMaterialSolves" .= (0 :: Int), "savedBodyFixed" .= False, "rimY" .= (0.44 :: Double), "rise" .= (0.045 :: Double), "bodyHalfWidth" .= ((sqrt 2 - 1) / 2 :: Double), "wingArchStartDegrees" .= (-15 :: Double), "wingArchEndDegrees" .= (15 :: Double), "compactVariant" .= object ["bodyWidthScale" .= (0.75 :: Double), "wingArchStartDegrees" .= (-50 :: Double), "wingArchEndDegrees" .= (-20 :: Double)], "narrowVariant" .= object ["bodyWidthScale" .= (0.5 :: Double), "wingArchStartDegrees" .= (-50 :: Double), "wingArchEndDegrees" .= (-20 :: Double)]]]
  BL.writeFile (output </> "checks.json") (encode report)
  BL.writeFile (output </> "models.json") (encode [object ["title" .= withCaveat pose (craneTitle pose), "path" .= (craneStem pose ++ ".glb")] | pose <- drawnStates])
  viewer <- TIO.readFile "study/gltf/viewer.html"
  TIO.writeFile (output </> "index.html") (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer)
  -- The 3D control selects these same files, visible paper first. It never
  -- derives another pose in JavaScript. Include the earlier targets in the
  -- common framing so changing shapes cannot silently move the camera or
  -- rescale.
  let viewerData = object ["models" .= [object ["title" .= craneTitle pose, "caveat" .= craneCaveat pose, "path" .= (craneStem pose ++ ".glb"), "lighting" .= (craneStem pose ++ "-lighting.json")] | pose <- drawnStates], "openings" .= [object ["title" .= title, "path" .= (name ++ ".glb")] | (_, name, title) <- wholeCraneOpenings], "defaultModel" .= ("spread-0.glb" :: T.Text)]
  spreadViewer <- TIO.readFile "study/fold-material/whole-crane-3d.html"
  TIO.writeFile (output </> "spread.html") (T.replace "/*CRANE_VIEW_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode viewerData))) (T.replace "./node_modules/" "../checked-flap/node_modules/" spreadViewer))
  lightingModule <- TIO.readFile "study/fold-material/paper-lighting.mjs"
  TIO.writeFile (output </> "paper-lighting.mjs") lightingModule
  writeScreenScript destination
  template <- TIO.readFile "study/fold-material/whole-crane.html"
  TIO.writeFile (destination </> "whole-crane.html") (T.replace "/*WHOLE_CRANE_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode report))) template)

-- | What the gallery measures: each pose it draws, and the refused material
-- adjustment when one was run. The adjustment is a solve that failed, neither
-- folded nor placed, so it is kept apart from the drawn poses rather than
-- given a geometry level that would be false.
data Measured = Drawn CranePose | Refused MaterialMesh

positions :: MaterialMesh -> [[Double]]
positions = map (xyz . position) . samples

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
