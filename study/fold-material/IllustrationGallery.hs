-- | Inspect already solved paper at its intended illustration size. This
-- command never runs a material solve: it reads the saved 8x2 study, rechecks
-- endpoint geometry, and uses the existing visible-region/SVG pipeline.
-- Source convergence is historical evidence, kept separately from the fresh
-- geometry checks. A crossing control cannot become accepted because its
-- drawing resembles an accepted one.
--
-- Four cameras share a fixed 600 page units per sheet unit. The browser's
-- mask samples and polygon exposure complement the exact-on-triangles
-- position bound. Changing the sampling grid can diagnose pixel sensitivity;
-- it cannot certify visibility stability or a physical folding movement.
module IllustrationGallery (writeIllustrationComparison) where

import ClosedCrease (closedOwners)
import Control.Monad (forM, forM_, unless)
import CoupledCrease
import CoupledCreaseGallery (measure)
import Data.Aeson (Value, eitherDecode, encode, object, withObject, (.:), (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.Types (Parser, parseEither)
import Data.ByteString.Lazy qualified as BL
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import IllustrationComparison
import Senbazuru.Diagram (Colour (..), Diagram (..))
import Senbazuru.Diagram.Style (Notation (..), defaultTheme)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.VectorSpace (norm, (*^))
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.CreasePattern (creasePatternFrom)
import Senbazuru.Render.Projected (projectedForm)
import Senbazuru.Render.Svg
import System.Directory (copyFile, createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)
import UnequalCrease

data Endpoint = Endpoint
  { endpointId :: Text,
    endpointControl :: Text,
    endpointMeshKey :: Text,
    endpointFrame :: Frame,
    endpointMesh :: MaterialMesh,
    endpointOwners :: [FaceId],
    endpointValid :: Bool,
    endpointReport :: Value
  }

writeIllustrationComparison :: FilePath -> FilePath -> IO ()
writeIllustrationComparison source destination = do
  report <- BL.readFile (source </> "checks.json") >>= either die pure . eitherDecode
  runs <-
    parsed
      ( withObject
          "8x2 report"
          ( \o -> do
              gallery <- o .: "gallery"
              unless (gallery == ("band-refinement-8x2" :: Text)) (fail "expected saved band-refinement-8x2 output")
              o .: "runs"
          )
      )
      report
  let output = destination </> "illustration-refinement"
  createDirectoryIfMissing True output
  copyFile (source </> "checks.json") (output </> "source-checks.json")
  endpoints <- forM [(c, n, w) | c <- ["matched", "band", "band-off"], (n, w) <- [(4, 2), (8, 1), (8, 2)]] $ \(control, n, w) -> loadEndpoint source output runs control n w
  cameras <- checked illustrationViews
  comparisons <- forM [(control, from) | control <- ["matched", "band", "band-off"], from <- ["4x2", "8x1"]] $ \(control, from) -> do
    a <- select endpoints control from
    b <- select endpoints control "8x2"
    differences <- checked (materialDifferences (endpointMesh a) (endpointMesh b))
    pure (a, b, differences)
  views <- forM cameras $ \(key, label, basis) -> do
    extent <- checked (sharedExtent basis (map endpointMesh endpoints))
    let page = illustrationPage label extent
    rendered <- forM endpoints $ \endpoint -> do
      let stem = endpointId endpoint <> "-" <> key
          fr = endpointFrame endpoint
      putStrLn ("Drawing " <> T.unpack stem)
      hFlush stdout
      let attempt = projectedForm basis fr (faceOrders fr)
      case attempt of
        Right (Just seen) -> do
          ordinary <- checked (creasePatternFrom defaultTheme defaultBudget FoldedFormNotation basis fr)
          TIO.writeFile (output </> T.unpack stem <> ".svg") (renderSvg page {pageBackground = Just (Colour "#ffffff")} ordinary {diagramExtent = extent})
          masks <- checked (visibleMasks basis extent (endpointOwners endpoint) seen)
          forM_ masks $ \(kind, drawing) -> TIO.writeFile (output </> T.unpack (stem <> "-" <> kind) <> ".svg") (renderSvg page drawing)
          regions <- checked (layerRegions basis (endpointOwners endpoint) seen)
          let exposure owner =
                let pieces = concat [rs | (n, rs) <- regions, n == owner]
                    (area, spanPixels) = exposureMeasures (map (map (600 *^)) pieces)
                 in object ["owner" .= unFaceId owner, "areaPixelsSquared" .= area, "maxColumnSpanPixels" .= spanPixels]
          pure (endpointId endpoint, Just seen, object ["id" .= endpointId endpoint, "stem" .= stem, "resolved" .= True, "exposure" .= map exposure [FaceId 0, FaceId 1]])
        _ -> pure (endpointId endpoint, Nothing, object ["id" .= endpointId endpoint, "resolved" .= False, "reason" .= either explain (const "View has unresolved projected visibility; no fallback is graded.") attempt])
    pairs <- forM comparisons $ \(a, b, differences) -> do
      let seen eid = case [form | (i, Just form, _) <- rendered, i == eid] of form : _ -> Just form; [] -> Nothing
          name = endpointControl a <> "-" <> endpointMeshKey a <> "-" <> key <> "-overlay.svg"
      resolved <- case (seen (endpointId a), seen (endpointId b)) of
        (Just sa, Just sb) -> TIO.writeFile (output </> T.unpack name) (renderSvg page (inkOverlay basis extent sa sb)) >> pure True
        _ -> pure False
      pure (object ["control" .= endpointControl a, "from" .= endpointMeshKey a, "to" .= endpointMeshKey b, "a" .= endpointId a, "b" .= endpointId b, "eligible" .= (endpointValid a && endpointValid b), "resolved" .= resolved, "overlay" .= name, "maxProjectedPixels" .= (600 * projectedChange basis differences), "maxSpatialChange" .= maximum (0 : map norm differences), "overlapCorners" .= length differences])
    pure (object ["key" .= key, "label" .= label, "width" .= pageWidth page, "height" .= pageHeight page, "renders" .= [r | (_, _, r) <- rendered], "pairs" .= pairs])
  BL.writeFile (output </> "comparison.json") (encode (object ["pixelsPerUnit" .= (600 :: Int), "pixelBudget" .= (2 :: Int), "sampleScale" .= (2 :: Int), "endpoints" .= map endpointReport endpoints, "views" .= views]))
  copyFile "study/fold-material/illustration-metrics.js" (output </> "metrics.js")
  copyFile "study/fold-material/illustration-refinement.html" (destination </> "illustration-refinement.html")
  putStrLn ("Wrote illustration-refinement.html; source geometry was not changed or re-solved: " <> output)

loadEndpoint :: FilePath -> FilePath -> [Value] -> Text -> Int -> Int -> IO Endpoint
loadEndpoint source output runs control n w = do
  let stem = control <> "-" <> T.pack (show n) <> if w == 1 then "" else "-w" <> T.pack (show w)
      meshKey = T.pack (show n <> "x" <> show w)
      filename = T.unpack stem <> "-after.fold"
      getId = parseEither (withObject "run" (.: "id"))
  record <- case [r | r <- runs, getId r == Right stem] of [r] -> pure r; _ -> die ("expected one saved run for " <> T.unpack stem)
  (reportedPass, converged, originalMeasurements) <-
    parsed
      ( withObject
          "run"
          ( \o -> do
              pass <- o .: "passed"
              solve <- o .: "solve"
              settled <- solve .: "converged"
              measurements <- o .: "measurements"
              after <- measurements .: "after"
              pure (pass, settled, after)
          )
      )
      record
  file <- loadFoldFile (source </> filename) >>= checked
  let fr = keyFrame file
  sheet <- checked (surfaceFromFrame fr >>= requireMaterialCoordinates)
  faces <- forM (facesVertices fr) $ \case
    [VertexId a, VertexId b, VertexId c] -> pure (a, b, c)
    _ -> die "illustration comparison requires triangulated saved paper"
  let mesh = Mesh (surfaceSamples sheet) faces
      kind = case control of "matched" -> MatchedHolds; "band" -> UpperBand; _ -> BandWithoutContact
  fixture <- checked (unequalCreaseWithWidth n w kind)
  checked (checkCoupledMaterial fixture mesh)
  expected <- checked (coupledSurface fixture mesh)
  let expectedFrame = materialFrame expected
  unless (edgesVertices fr == edgesVertices expectedFrame && edgesAssignment fr == edgesAssignment expectedFrame && faceOrders fr == faceOrders expectedFrame && frameExtras fr == frameExtras expectedFrame) $
    die "saved endpoint has changed edge, source-panel or layer identities"
  (measurement, valid) <- measure fixture mesh
  -- Measurements bind the historical solver report to the supplied endpoint.
  -- Compare the actual stored coordinates through independent checks, rather
  -- than trusting a stale `passed` flag beside a possibly edited FOLD file.
  forM_ ["maxRelativeEdgeError", "maxCreaseErrorRadians", "panelBendingEnergy", "heldPositionError"] $ \key -> do
    a <- parsed (withObject "measurement" (.: Key.fromText key)) originalMeasurements
    b <- parsed (withObject "measurement" (.: Key.fromText key)) measurement
    unless (abs (a - b :: Double) <= 1e-12 * max 1 (abs a)) (die "saved report disagrees with endpoint measurements")
  copyFile (source </> filename) (output </> filename)
  let eligible = control /= "band-off" && reportedPass && converged && valid
      evidence = object ["id" .= stem, "control" .= control, "mesh" .= meshKey, "eligible" .= eligible, "sourcePassed" .= reportedPass, "sourceConverged" .= converged, "geometryPassed" .= valid, "measurements" .= measurement, "fold" .= filename]
  pure (Endpoint stem control meshKey fr mesh (closedOwners (coupledReference fixture)) eligible evidence)

select :: [Endpoint] -> Text -> Text -> IO Endpoint
select endpoints control key = maybe (die "missing comparison endpoint") pure (find (\e -> endpointControl e == control && endpointMeshKey e == key) endpoints)

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure

parsed :: (Value -> Parser a) -> Value -> IO a
parsed parser = either die pure . parseEither parser
