-- | Read-only drawing-scale audit of the saved body experiments. The archive
-- readers bind positions to their original material and holds; this module
-- never asks for a solver direction. Failed geometry remains failed under its
-- historical checks. Pixel screens select diagnostic regions, not accepted
-- paper. In particular a production painter fallback is NOT a visibility proof.
module BodyVisualToleranceGallery (writeBodyVisualTolerance) where

import BodyContactDiagnosis (PairSection (..), pairSection)
import BodyCorrectionArchive (CorrectionArchive (..), checked, readArchiveBytes, readCorrectionArchive, separateOutput, xyz)
import BodyCreaseSeed (installCreaseSeed)
import BodyPatch
import BodyPatchCheckpoints
import BodyPatchSubdivision (seedPassed)
import Control.Monad (forM, forM_, unless)
import CranePocket (buildCranePocket)
import CraneSpread
import Data.Aeson (FromJSON, Value, eitherDecode, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.List (nub)
import Data.Map.Strict qualified as M
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldContact (ContactRow (..))
import FoldMaterial (meshEdges)
import FoldRelaxation (maxLengthError)
import IllustrationComparison (illustrationPage, illustrationViews, sharedExtent)
import IllustrationTolerance
import Senbazuru.Diagram
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (ContactCheck (..))
import Senbazuru.Origami.Folding (foldFrameWith)
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Camera (Basis, View (..), project)
import Senbazuru.Render.CreasePattern (surfaceDiagram)
import Senbazuru.Render.Projected (projectedForm)
import Senbazuru.Render.Svg
import SurfaceContact qualified as C
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (takeDirectory, (</>))
import Text.Read (readMaybe)

type Case = (String, Text, BodyPatch, MaterialMesh)

-- | SOURCE contains body-subdivision/, body-patch/ and body-crease-seed/.
-- Output may share their parent, but must never overlap any input directory.
writeBodyVisualTolerance :: FilePath -> FilePath -> IO ()
writeBodyVisualTolerance source destination = do
  let output = destination </> "body-visual-tolerances"
  forM_ ["body-subdivision", "body-patch", "body-crease-seed"] $ \name -> separateOutput (source </> name) output
  archive <- readCorrectionArchive (source </> "body-subdivision")
  (controls, controlFiles) <- readControls source
  let cases = [(name, T.pack name <> " · recovered subdivision", archiveStudy archive, mesh) | (name, _, mesh, _) <- archiveStates archive] ++ controls
      sourceFiles = [("body-subdivision" </> name, bytes) | (name, bytes) <- archiveFiles archive] ++ controlFiles
  cameras <- checked illustrationViews
  extents <- forM cameras $ \(name, title, basis) -> do
    bounds <- checked (sharedExtent basis [mesh | (_, _, _, mesh) <- cases])
    pure (name, title, basis, bounds)
  createDirectoryIfMissing True (output </> "source")
  forM_ sourceFiles $ \(name, bytes) -> do
    let path = output </> "source" </> name
    createDirectoryIfMissing True (takeDirectory path)
    BL.writeFile path bytes
  reference <- case archiveStates archive of
    (_, _, firstMesh, _) : _ -> pure firstMesh
    _ -> die "missing recovered reference"
  reports <- traverse (writeCase output extents reference) cases
  let report = object ["gallery" .= ("body-visual-tolerances" :: Text), "issue" .= (389 :: Int), "pixelsPerSheetUnit" .= scale, "newSolves" .= (0 :: Int), "distanceScreensPixels" .= screens, "cases" .= reports, "sourceFiles" .= map fst sourceFiles, "cameras" .= [object ["id" .= name, "title" .= title] | (name, title, _, _) <- extents]]
  BL.writeFile (output </> "checks.json") (encode report)
  template <- TIO.readFile "study/fold-material/body-visual-tolerances.html"
  TIO.writeFile (destination </> "body-visual-tolerances.html") (T.replace "/*VISUAL_TOLERANCE_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode report))) template)
  putStrLn ("Measured saved geometry only. Wrote " ++ destination </> "body-visual-tolerances.html")

scale :: Double
scale = 600

screens :: [Double]
screens = [0, 0.1, 0.5, 1]

readControls :: FilePath -> IO ([Case], [(FilePath, BL.ByteString)])
readControls source = do
  crane <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= checked)
  atlas <- checked (buildCranePocket crane)
  let patchSource = source </> "body-patch"
      angleSource = source </> "body-crease-seed"
  (rawReport, report) <- readJson (patchSource </> "checks.json")
  (rawSingle, single) <- readJson (patchSource </> "opening-5-fine-check.json")
  (rawInitial, initial) <- readJson (patchSource </> "opening-5-fine-initial.fold")
  (rawFinal, final) <- readJson (patchSource </> "opening-5-fine.fold")
  (rawHistory, history) <- readJson (patchSource </> "opening-5-fine-history.json")
  fine <- checked (bodyPatch atlas 1 5)
  points <- checked (readPatchArchive "opening-5-fine" fine report single (keyFrame initial) (keyFrame final) history)
  endpoint <- case reverse points of p : _ -> pure (savedMesh p); _ -> die "missing archived fine endpoint"
  (rawAngles, angles) <- readJson (angleSource </> "angles.fold")
  (rawCoarse, coarse) <- readJson (angleSource </> "coarse.fold")
  baseline <- checked (bodyPatch atlas 0 0)
  folded <- checked (foldFrameWith (keyFrame angles))
  angleStudy <- checked (installCreaseSeed baseline folded)
  let angleMesh = spreadMesh (patchSpread angleStudy)
  expected <- materialFrame <$> checked (spreadSurface (patchSpread angleStudy) angleMesh)
  unless (keyFrame coarse == expected) (die "saved angle pose differs from the validated saved crease angles")
  pure
    ( [("strained", "Original fine endpoint · 160 corrections", fine, endpoint), ("angle", "Angle-derived seed · changed grip positions", angleStudy, angleMesh)],
      [("body-patch" </> name, bytes) | (name, bytes) <- [("checks.json", rawReport), ("opening-5-fine-check.json", rawSingle), ("opening-5-fine-initial.fold", rawInitial), ("opening-5-fine.fold", rawFinal), ("opening-5-fine-history.json", rawHistory)]]
        ++ [("body-crease-seed" </> name, bytes) | (name, bytes) <- [("angles.fold", rawAngles), ("coarse.fold", rawCoarse)]]
    )

writeCase :: FilePath -> [(Text, Text, Basis, Box)] -> MaterialMesh -> Case -> IO Value
writeCase output cameras reference (name, title, study, mesh) = do
  measured <- checked (measurePatch study (SavedPoint 0 mesh))
  strict <- checked (seedPassed study mesh)
  let fixture = patchSpread study
  sheet <- checked (spreadSurface fixture mesh)
  model <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) mesh)
  witnesses <- checked (C.contactWitnesses model mesh)
  let groups = M.toList (M.fromListWith (flip (++)) [(C.witnessTriangles w, [w]) | w <- witnesses])
      gaps ws = [(C.witnessLower w, contactGap (C.witnessRow w)) | w <- ws]
      patches cap = [(pair, negativeRegion (cap / scale) (gaps ws)) | (pair, ws) <- groups]
      maxNegativeGap = maximum (0 : [negate (contactGap (C.witnessRow w)) | w <- witnesses])
      changes = if name `elem` ["seed", "step-1", "step-2"] then Just (zipWith (\a b -> position a ^-^ position b) (samples mesh) (samples reference)) else Nothing
      edgeError = maximum (0 : map (abs . edgeLengthChange) (measuredEdges measured))
  pairs <- traverse parsePair (crossingPanels (measuredContact measured))
  sections <- forM (nub pairs) $ \pair -> do section <- checked (pairSection mesh pair); pure (pair, section)
  views <- forM cameras $ \(viewId, _, basis, bounds) -> do
    let stem = name ++ "-" ++ T.unpack viewId
        page = illustrationPage title bounds
        wire = wireShapes basis mesh
        frame = surfaceFrame sheet
        visibility = case projectedForm basis frame (faceOrders frame) of
          Left err -> "Refused: " <> explain err
          Right Nothing -> "Whole-face/wire fallback: hidden edges and colours are not verified"
          Right (Just _) -> "Projected visible regions available"
        preview = surfaceDiagram defaultTheme defaultBudget (View (Just basis) 0) sheet
        (previewStatus, drawing) = case preview of
          Left err -> ("Renderer refused; showing wire: " <> explain err, diagramWithExtent bounds wire)
          Right picture -> (visibility, picture {diagramExtent = bounds})
    TIO.writeFile (output </> stem ++ "-paper.svg") (renderSvg page drawing)
    TIO.writeFile (output </> stem ++ "-wire.svg") (renderSvg page (diagramWithExtent bounds wire))
    regions <- forM (zip [0 :: Int ..] screens) $ \(index, cap) -> do
      let rings = [(pair, map (project basis) ring) | (pair, ring) <- patches cap, length ring >= 3]
          intersectionLines = [Polyline (solid (Colour "#ad2635") 1.5) (map (project basis) (intersectionEnds section)) | (_, section) <- sections, intersectionLength section * scale > cap]
          shapes = Fill (Colour "#d88362") (map snd rings) : intersectionLines
      TIO.writeFile (output </> stem ++ "-regions-" ++ show index ++ ".svg") (renderSvg page (diagramWithExtent bounds shapes))
      pure (object ["allowancePixels" .= cap, "pairCount" .= length rings, "areaSumPixelsSquared" .= (scale * scale * sum (map (projectedArea . snd) rings)), "maxPairDiameterPixels" .= (scale * maximum (0 : map (projectedDiameter . snd) rings))])
    pure (object ["id" .= viewId, "stem" .= stem, "width" .= pageWidth page, "height" .= pageHeight page, "previewStatus" .= previewStatus, "maxProjectedMovementFromSeedPixels" .= fmap (\ds -> scale * maximum (0 : map (norm . project basis) ds)) changes, "regions" .= regions, "maxIntersectionPixels" .= (scale * maximum (0 : [projectedDiameter (map (project basis) (intersectionEnds section)) | (_, section) <- sections]))])
  pure
    ( object
        [ "id" .= name,
          "title" .= title,
          "strictGeometryPassed" .= strict,
          "convergedClaim" .= False,
          "maxMovementFromSeedPixels" .= fmap (\ds -> scale * maximum (0 : map norm ds)) changes,
          "triangles" .= length (triangles mesh),
          "holdError" .= spreadHeldError fixture mesh,
          "maxRelativeLengthError" .= maxLengthError mesh,
          "maxAbsoluteLengthErrorPixels" .= (edgeError * scale),
          "maxNegativeGapPixels" .= (maxNegativeGap * scale),
          "bodyDepthPixels" .= (measuredBodyDepth measured * scale),
          "contact" .= measuredContact measured,
          "views" .= views,
          "edges" .= [object ["vertices" .= edgeVertices e, "restLength" .= edgeRestLength e, "signedLengthChange" .= edgeLengthChange e, "relativeError" .= edgeRelativeError e] | e <- measuredEdges measured],
          "contacts" .= [object ["triangles" .= pair, "corners" .= [object ["lower" .= xyz (C.witnessLower w), "upper" .= xyz (C.witnessUpper w), "gap" .= contactGap (C.witnessRow w)] | w <- ws]] | (pair, ws) <- groups],
          "crossings" .= [object ["triangles" .= pair, "lengthPixels" .= (intersectionLength section * scale), "ends" .= map xyz (intersectionEnds section)] | (pair, section) <- sections]
        ]
    )

wireShapes :: Basis -> MaterialMesh -> [Shape]
wireShapes basis mesh = [Polyline (solid (Colour "#8c8d89") 0.55) [p, q] | (a, b) <- meshEdges mesh, Just p <- [IM.lookup a points], Just q <- [IM.lookup b points]]
  where
    points = IM.fromList [(i, project basis (position p)) | (i, p) <- zip [0 ..] (samples mesh)]

parsePair :: (Text, Text) -> IO (Int, Int)
parsePair (a, b) = (,) <$> parse a <*> parse b
  where
    parse name = case T.stripPrefix "triangle-" name >>= readMaybe . T.unpack of Just i -> pure i; Nothing -> die "unexpected archived triangle name"

readJson :: (FromJSON a) => FilePath -> IO (BL.ByteString, a)
readJson path = do bytes <- readArchiveBytes path; value <- either die pure (eitherDecode bytes); pure (bytes, value)
