-- | A read-only audit of two archived runs. Copy the source bytes beside the
-- measurements so this gallery can be reproduced without rerunning a solve.
-- Numerical iterates remain wire diagrams, including hidden triangles; the
-- worst length edge and worst reversed order are marked, not visually repaired.
module BodyPatchCheckpointGallery (writeBodyPatchCheckpoints) where

import BodyPatch
import BodyPatchCheckpoints
import Control.Monad (forM, forM_, unless, when)
import CranePocket (buildCranePocket)
import CraneSpread
import Data.Aeson (FromJSON, Value, eitherDecode, encode, object, toJSON, withObject, (.:), (.=))
import Data.Aeson.Key (Key)
import Data.Aeson.Types (parseEither)
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.List (isPrefixOf, sortOn)
import Data.Map.Strict qualified as M
import Data.Ord (Down (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldMaterial (meshEdges)
import FoldRelaxation (maxLengthError)
import Senbazuru.Diagram
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Surface
import Senbazuru.Render.Camera (bottomUp, frontOn, project, topDown)
import Senbazuru.Render.Svg
import System.Directory (canonicalizePath, createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (splitDirectories, (</>))

writeBodyPatchCheckpoints :: FilePath -> FilePath -> IO ()
writeBodyPatchCheckpoints source destination = do
  let output = destination </> "body-checkpoints"
  src <- splitDirectories <$> canonicalizePath source
  dst <- splitDirectories <$> canonicalizePath output
  when (src `isPrefixOf` dst || dst `isPrefixOf` src) (die "checkpoint source and output directories must not overlap")
  (rawDocument, document) <- readJson (source </> "checks.json")
  crane <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= checked)
  atlas <- checked (buildCranePocket crane)
  inputs <- forM [("opening-5", 0), ("opening-5-fine", 1)] $ \(name, level) -> do
    study <- checked (bodyPatch atlas level 5)
    (rawReport, report) <- readJson (source </> name ++ "-check.json")
    (rawInitial, initial) <- readJson (source </> name ++ "-initial.fold")
    (rawFinal, final) <- readJson (source </> name ++ ".fold")
    (rawHistory, history) <- readJson (source </> name ++ "-history.json")
    points <- checked (readPatchArchive (T.pack name) study document report (keyFrame initial) (keyFrame final) history)
    measured <- traverse (checked . measurePatch study) points
    case reverse measured of
      m : _ -> do
        let near key value = do original <- field key report; unless (abs (original - value) <= 1e-12 * max 1 (abs value)) (die ("endpoint remeasurement differs: " ++ show key))
        near "maxRelativeEdgeError" (maxLengthError (savedMesh (measuredPoint m)))
        near "creaseEnergy" (measuredCrease m)
        near "panelEnergy" (measuredPanel m)
        oldContact <- field "contact" report
        unless (oldContact == toJSON (measuredContact m)) (die "endpoint contact remeasurement differs")
      [] -> die "no measured checkpoints"
    pure (name, study, report, measured, [(name ++ "-check.json", rawReport), (name ++ "-initial.fold", rawInitial), (name ++ ".fold", rawFinal), (name ++ "-history.json", rawHistory)])
  -- All input validation and measurement precedes writing any output.
  createDirectoryIfMissing True (output </> "source")
  BL.writeFile (output </> "source" </> "checks.json") rawDocument
  runs <- forM inputs $ \(name, study, report, measured, files) -> do
    mapM_ (\(file, bytes) -> BL.writeFile (output </> "source" </> file) bytes) files
    entries <- forM (zip (Nothing : map Just measured) measured) $ \(previous, m) -> do
      let point = measuredPoint m
          mesh = savedMesh point
          iteration = savedIteration point
          stem = name ++ "-" ++ show iteration
      weight <- checked (checkpointWeight iteration)
      movement <- traverse (\p -> checked (savedMovement (measuredPoint p) point)) previous
      let beforeCost = fmap (patchCost weight) previous
          afterCost = patchCost weight m
          edges = sortOn (Down . edgeRelativeError) (measuredEdges m)
          reversed = sortOn (\(_, _, depth) -> Down depth) (reversedOrders (measuredContact m))
          worstEdge = take 1 edges
          worstPair = take 1 reversed
      forM_ views $ \(view, projection, bounds, height) -> do
        TIO.writeFile (output </> stem ++ "-" ++ view ++ ".svg") (drawCheckpoint projection bounds height mesh worstEdge worstPair)
      pure
        ( object
            [ "iteration" .= iteration,
              "arrivalLengthWeight" .= weight,
              "previousIteration" .= fmap (savedIteration . measuredPoint) previous,
              "netMovementSincePrevious" .= movement,
              "maxRelativeEdgeError" .= maxLengthError mesh,
              "holdError" .= spreadHeldError (patchSpread study) mesh,
              "geometryPassed" .= (maxLengthError mesh <= 1e-5 && contactPassed (measuredContact m)),
              "contact" .= measuredContact m,
              "minimumSolverGap" .= measuredMinimumGap m,
              "bodyDepth" .= measuredBodyDepth m,
              "creaseEnergy" .= measuredCrease m,
              "panelEnergy" .= measuredPanel m,
              "lengthSquares" .= measuredLengthSquares m,
              "contactSquares" .= measuredContactSquares m,
              "lengthCost" .= (weight * measuredLengthSquares m / 2),
              "contactCost" .= (100 * weight * measuredContactSquares m / 2),
              "costAtArrivalWeight" .= afterCost,
              "previousCostAtArrivalWeight" .= beforeCost,
              "costDecreaseBetweenSavedPoints" .= fmap (\b -> b - afterCost) beforeCost,
              "lengthEdges" .= map (edgeJson study mesh weight) edges,
              "worstOrder" .= [object ["lower" .= a, "upper" .= b, "penetration" .= depth] | (a, b, depth) <- worstPair],
              "views" .= [object ["label" .= view, "path" .= (stem ++ "-" ++ view ++ ".svg")] | (view, _, _, _) <- views]
            ]
        )
    let fixture = patchSpread study
    pure (object ["id" .= name, "sourceReport" .= report, "triangles" .= [object ["id" .= ("triangle-" <> T.pack (show i)), "vertices" .= [a, b, c], "sourceFace" .= unFaceId sourceFace] | (i, ((a, b, c), owner)) <- zip [0 :: Int ..] (zip (triangles (spreadMesh fixture)) (refinedPanels (spreadRefined fixture))), Just sourceFace <- [M.lookup owner (M.fromList (zip (map FaceId [0 ..]) (patchFaces study)))]], "checkpoints" .= entries])
  let result = object ["gallery" .= ("body-checkpoints" :: Text), "newSolves" .= (0 :: Int), "lengthTolerance" .= (1e-5 :: Double), "contactTolerance" .= (1e-7 :: Double), "runs" .= runs]
  BL.writeFile (output </> "checks.json") (encode result)
  template <- TIO.readFile "study/fold-material/body-checkpoints.html"
  TIO.writeFile (destination </> "body-checkpoints.html") (T.replace "/*CHECKPOINT_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode result))) template)
  putStrLn ("Remeasured 50 archived checkpoints; no solves. Wrote " ++ destination </> "body-checkpoints.html")

edgeJson :: BodyPatch -> MaterialMesh -> Double -> PatchEdge -> Value
edgeJson study mesh weight e =
  object
    [ "vertices" .= [a, b],
      "material" .= [[materialU p, materialV p] | i <- [a, b], Just p <- [IM.lookup i points]],
      "sourceFaces" .= [unFaceId source | ((x, y, z), owner) <- zip (triangles mesh) owners, a `elem` [x, y, z], b `elem` [x, y, z], Just source <- [M.lookup owner sources]],
      "restLength" .= edgeRestLength e,
      "signedLengthChange" .= edgeLengthChange e,
      "relativeError" .= edgeRelativeError e,
      "cost" .= (weight * edgeLengthChange e ^ (2 :: Int) / 2)
    ]
  where
    (a, b) = edgeVertices e
    points = IM.fromList (zip [0 ..] (samples mesh))
    owners = refinedPanels (spreadRefined (patchSpread study))
    sources = M.fromList (zip (map FaceId [0 ..]) (patchFaces study))

views :: [(String, Sample V2 -> V2, Box, Double)]
views = [("side", project frontOn . position, box frontOn, 440), ("top", project topDown . position, box topDown, 440), ("underside", project bottomUp . position, box bottomUp, 440), ("material", sampleMaterial, Box (V2 0 0) (V2 1 1), 560)]
  where
    box basis = let V2 x y = project basis (V3 1 0.32 0) in Box (V2 (x - 0.42) (y - 0.32)) (V2 (x + 0.42) (y + 0.32))

drawCheckpoint :: (Sample V2 -> V2) -> Box -> Double -> MaterialMesh -> [PatchEdge] -> [(Text, Text, Double)] -> Text
drawCheckpoint projection bounds height mesh edges pairs = renderSvg page (diagramWithExtent bounds shapes)
  where
    page = defaultPage {pageWidth = 560, pageHeight = height, pageMargin = 28, pageBackground = Nothing, pageTitle = Just "Saved numerical checkpoint: hidden triangles included; no motion certification"}
    points = IM.fromList [(i, projection p) | (i, p) <- zip [0 ..] (samples mesh)]
    line colour width ids = Polyline (solid (Colour colour) width) [p | i <- ids, Just p <- [IM.lookup i points]]
    names = M.fromList [("triangle-" <> T.pack (show i), [a, b, c, a]) | (i, (a, b, c)) <- zip [0 :: Int ..] (triangles mesh)]
    shapes =
      [line "#bbb7ad" 0.65 [a, b] | (a, b) <- meshEdges mesh]
        ++ [line colour 2 ids | (lower, upper, _) <- pairs, (name, colour) <- [(lower, "#7555a3"), (upper, "#d38a30")], Just ids <- [M.lookup name names]]
        ++ [line "#c0392b" 3 [a, b] | e <- edges, edgeRelativeError e > 1e-5, let (a, b) = edgeVertices e]

readJson :: (FromJSON a) => FilePath -> IO (BL.ByteString, a)
readJson path = do bytes <- BL.readFile path; value <- either die pure (eitherDecode bytes); pure (bytes, value)

field :: (FromJSON a) => Key -> Value -> IO a
field key = either die pure . parseEither (withObject "saved report" (.: key))

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
