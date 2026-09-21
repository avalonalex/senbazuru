-- | Read-only inspection of the first crossing correction in the recovered
-- body-patch archive. Verify saved FOLD identities, trace linkage and reported
-- measurements before writing anything. Both cameras use unchanged positions;
-- the height chart is explicitly a measurement plot, not a deformed shape.
module BodyContactGallery (writeBodyContact) where

import BodyContactDiagnosis
import BodyPatch
import BodyPatchCheckpoints
import BodyPatchSubdivision (seedPassed)
import Control.Monad (forM, forM_, unless, when)
import CranePocket (buildCranePocket)
import CraneSpread
import Data.Aeson (FromJSON, Value, eitherDecode, encode, object, toJSON, withObject, (.:), (.=))
import Data.Aeson.Key (Key)
import Data.Aeson.Types (parseEither)
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.List (isPrefixOf)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldContact (ContactRow (..))
import FoldRelaxation (maxLengthError)
import Senbazuru.Diagram
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (crossingPanels, panelTolerance)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Svg
import SurfaceContact qualified as C
import System.Directory (canonicalizePath, createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (splitDirectories, (</>))

writeBodyContact :: FilePath -> FilePath -> IO ()
writeBodyContact source destination = do
  let output = destination </> "body-contact"
  src <- splitDirectories <$> canonicalizePath source
  dst <- splitDirectories <$> canonicalizePath output
  when (src `isPrefixOf` dst || dst `isPrefixOf` src) (die "contact source and output directories must not overlap")
  (rawReport, report) <- readJson (source </> "checks.json")
  (rawTrace, trace) <- readJson (source </> "trace.json")
  expect "gallery" ("body-subdivision" :: Text) report
  expect "lengthWeight" (1e8 :: Double) report
  expect "contactMultiplier" (100 :: Int) report
  expect "lengthTolerance" (1e-5 :: Double) report
  expect "contactTolerance" panelTolerance report
  expect "seedPassed" True report
  continuation <- field "continuation" report
  expect "trace" (trace :: [Value]) continuation
  crane <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= checked)
  atlas <- checked (buildCranePocket crane)
  study <- checked (bodyPatch atlas 1 5)
  let fixture = patchSpread study; base = spreadMesh fixture
  states <- field "states" report :: IO [Value]
  inputs <- forM ["seed", "step-1", "step-2"] $ \name -> do
    (raw, file) <- readJson (source </> name ++ ".fold")
    let frame = keyFrame file
    ps <- traverse vector (verticesCoords frame)
    unless (length ps == length (samples base)) (die "saved vertex count changed")
    let mesh = base {samples = zipWith (\p q -> p {position = q}) (samples base) ps}
    expected <- materialFrame <$> checked (spreadSurface fixture mesh)
    unless (frame == expected && spreadHeldError fixture mesh == 0) (die "saved material, topology, metadata or exact holds changed")
    entry <- case [s | s <- states, parseEither (withObject "state" (.: "id")) s == Right (T.pack name)] of
      [s] -> pure s
      _ -> die "missing or duplicated saved state"
    measured <- checked (measurePatch study (SavedPoint 0 mesh))
    expect "contact" (toJSON (measuredContact measured)) entry
    forM_ [("maxRelativeEdgeError", maxLengthError mesh), ("creaseEnergy", measuredCrease measured), ("panelEnergy", measuredPanel measured), ("totalCost", patchCost 1e8 measured)] $ \(key, value) -> do
      original <- field key entry
      unless (abs (original - value) <= 1e-12 * max 1 (abs value)) (die "saved measurements disagree with geometry")
    pure (name, raw, mesh, measured)
  (before, after, firstStep, secondStep) <- case (inputs, trace) of
    ([(_, _, seed, _), (_, _, a, _), (_, _, b, _)], s1 : s2 : _) -> do
      valid <- checked (seedPassed study seed)
      unless valid (die "saved seed no longer passes")
      verifyStep study 1 seed a s1
      verifyStep study 2 a b s2
      expect "scale" (0.25 :: Double) s2
      pure (a, b, s1, s2)
    _ -> die "expected seed, two checkpoints and two trace entries"
  contact <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) base)
  witnesses <- traverse (checked . C.contactWitnesses contact) [before, after]
  let selected = [(14, 55), (22, 63), (46, 70)]
      owners = IM.fromList (zip [0 ..] (refinedPanels (spreadRefined fixture)))
      sources = IM.fromList (zip [0 ..] (patchFaces study))
      identity i = do
        owner <- maybe (die "missing panel") pure (IM.lookup i owners)
        sourceFace <- maybe (die "missing crane face") pure (IM.lookup (unFaceId owner) sources)
        pure (object ["triangle" .= i, "panel" .= unFaceId owner, "sourceFace" .= unFaceId sourceFace])
  pairs <- forM selected $ \pair@(i, j) -> do
    ids <- traverse identity [i, j]
    inspected <- forM (zip3 [1 :: Int, 2] [before, after] witnesses) $ \(step, mesh, ws) -> do
      cut <- checked (pairSection mesh pair)
      let hits = [w | w <- ws, let (a, b) = C.witnessTriangles w, (min a b, max a b) == pair]
          named = ("triangle-" <> T.pack (show i), "triangle-" <> T.pack (show j))
      unless (not (null hits) && all ((== 0) . C.witnessClearance) hits) (die "expected this pair's zero-clearance solver coverage")
      full <- checked (spreadCheck fixture mesh)
      unless (sectionCrosses cut == (named `elem` crossingPanels full)) (die "section measurement and independent crossing check disagree")
      pure (step, mesh, cut, hits)
    pure (pair, ids, inspected)
  -- Archive checks and all measurements precede writes. No solver entry point is called.
  createDirectoryIfMissing True (output </> "source")
  forM_ (("checks.json", rawReport) : ("trace.json", rawTrace) : [(name ++ ".fold", raw) | (name, raw, _, _) <- inputs]) $ \(name, raw) -> BL.writeFile (output </> "source" </> name) raw
  entries <- forM pairs $ \(pair@(i, j), ids, inspected) -> do
    let stem = show i ++ "-" ++ show j
        focusPoints = concat [intersectionEnds cut ++ concat [[C.witnessLower w, C.witnessUpper w] | w <- ws, abs (contactGap (C.witnessRow w)) <= panelTolerance] | (_, _, cut, ws) <- inspected]
        zoom = boxAround (map xy focusPoints)
    rows <- forM inspected $ \(step, mesh, cut, ws) -> do
      let prefix = stem ++ "-" ++ show step
      TIO.writeFile (output </> prefix ++ "-context.svg") (drawPair (Box (V2 0.58 0) (V2 1.42 0.64)) mesh pair cut ws)
      TIO.writeFile (output </> prefix ++ "-zoom.svg") (drawPair zoom mesh pair cut ws)
      TIO.writeFile (output </> prefix ++ "-gaps.svg") (drawGaps ws)
      pure (object ["step" .= step, "prefix" .= prefix, "crosses" .= sectionCrosses cut, "sectionFirst" .= map xyz (sectionFirst cut), "sectionSecond" .= map xyz (sectionSecond cut), "firstDistances" .= firstDistances cut, "secondDistances" .= secondDistances cut, "intersection" .= map xyz (intersectionEnds cut), "intersectionLength" .= intersectionLength cut, "intersectionPixels" .= (600 * intersectionLength cut), "minimumGap" .= minimum (map (contactGap . C.witnessRow) ws), "pairContactCost" .= (5e9 * sum [min 0 (contactGap (C.witnessRow w)) ^ (2 :: Int) | w <- ws]), "witnesses" .= map witnessValue ws])
    pure (object ["id" .= stem, "identities" .= ids, "zoomBounds" .= boxValue zoom, "states" .= rows])
  let result = object ["gallery" .= ("body-contact" :: Text), "newSolves" .= (0 :: Int), "contactTolerance" .= panelTolerance, "lengthTolerance" .= (1e-5 :: Double), "lengthWeight" .= (1e8 :: Double), "contactWeight" .= (1e10 :: Double), "pairs" .= entries, "traceSteps" .= [firstStep, secondStep], "states" .= [object ["id" .= name, "lengthError" .= maxLengthError mesh, "holdError" .= spreadHeldError fixture mesh, "contact" .= measuredContact m, "creaseCost" .= measuredCrease m, "panelCost" .= measuredPanel m, "lengthCost" .= (5e7 * measuredLengthSquares m), "contactCost" .= (5e9 * measuredContactSquares m), "totalCost" .= patchCost 1e8 m] | (name, _, mesh, m) <- inputs]]
  BL.writeFile (output </> "checks.json") (encode result)
  template <- TIO.readFile "study/fold-material/body-contact.html"
  TIO.writeFile (destination </> "body-contact.html") (T.replace "/*BODY_CONTACT_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode result))) template)
  putStrLn ("Inspected saved correction 1 to 2 without solving. Wrote " ++ destination </> "body-contact.html")

verifyStep :: BodyPatch -> Int -> MaterialMesh -> MaterialMesh -> Value -> IO ()
verifyStep study number before after record = do
  forM_ [("beforeEnergy", before), ("candidateEnergy", after)] $ \(key, mesh) -> do
    measured <- checked (measurePatch study (SavedPoint 0 mesh))
    recorded <- field key record
    unless (abs (recorded - 2 * patchCost 1e8 measured) < 1e-12) (die "saved trace energy disagrees with positions")
  expect "iteration" number record
  expect "start" (map (xyz . position) (samples before)) record
  expect "candidate" (map (xyz . position) (samples after)) record
  proposal <- field "fullProposal" record >>= traverse vector
  scale <- field "scale" record
  unless (length proposal == length (samples before) && scale > 0 && scale <= (1 :: Double)) (die "invalid saved proposal")
  let expected = zipWith (\p q -> position p ^+^ scale *^ (q ^-^ position p)) (samples before) proposal
  unless (and (zipWith (\p q -> norm (p ^-^ position q) < 1e-12) expected (samples after))) (die "saved candidate differs from scaled full proposal")

witnessValue :: C.ContactWitness -> Value
witnessValue w = object ["triangles" .= C.witnessTriangles w, "lower" .= xyz (C.witnessLower w), "upper" .= xyz (C.witnessUpper w), "clearance" .= C.witnessClearance w, "gap" .= contactGap (C.witnessRow w), "gradient" .= [[toJSON i, toJSON (xyz g)] | (i, g) <- contactGradient (C.witnessRow w)]]

drawPair :: Box -> MaterialMesh -> (Int, Int) -> PairSection -> [C.ContactWitness] -> Text
drawPair bounds mesh (i, j) cut ws = renderSvg page (diagramWithExtent bounds shapes)
  where
    vertices = IM.fromList (zip [0 ..] (map (xy . position) (samples mesh)))
    topology = IM.fromList (zip [0 ..] (triangles mesh))
    ring k = case IM.lookup k topology of Just (a, b, c) -> [p | n <- [a, b, c, a], Just p <- [IM.lookup n vertices]]; Nothing -> []
    line c w = Polyline (solid (Colour c) w)
    shapes =
      [line "#dedbd2" 0.5 (ring k) | k <- IM.keys topology, k /= i, k /= j]
        ++ [line "#7056a2" 1.4 (ring i), line "#c98225" 1.4 (ring j)]
        ++ [line "#b82643" 3 (map xy (intersectionEnds cut))]
        ++ [Offset (V2 (-4) 4) (Label (Colour "#177970") 12 (xy (C.witnessLower w)) "●") | w <- ws]
    page = defaultPage {pageWidth = 560, pageHeight = 440, pageMargin = 28, pageBackground = Nothing, pageTitle = Just "Unchanged saved triangles: red intersection, green contact samples"}

-- Each horizontal station is one clipped corner, not physical distance.
-- The vertical scale is shared across both steps: one unit = contact tolerance.
drawGaps :: [C.ContactWitness] -> Text
drawGaps ws = renderSvg page (diagramWithExtent (Box (V2 (-0.5) (-1.25)) (V2 (fromIntegral (length ws) - 0.5) 1.25)) shapes)
  where
    line c w = Polyline (solid (Colour c) w)
    end = fromIntegral (length ws) - 0.5
    shapes =
      [line "#aaa79e" 0.8 [V2 (-0.5) y, V2 end y] | y <- [-1, 0, 1]]
        ++ [line "#177970" 2 [V2 (fromIntegral k) 0, V2 (fromIntegral k) (min 1.15 (max (-1.15) (contactGap (C.witnessRow w) / panelTolerance)))] | (k, w) <- zip [0 :: Int ..] ws]
        ++ [Offset (V2 (-4) 4) (Label (Colour "#177970") 12 (V2 (fromIntegral k) (min 1.15 (max (-1.15) (contactGap (C.witnessRow w) / panelTolerance)))) "●") | (k, w) <- zip [0 :: Int ..] ws]
    page = defaultPage {pageWidth = 560, pageHeight = 240, pageMargin = 28, pageBackground = Nothing, pageTitle = Just "Contact gaps: horizontal stations are sample indices; vertical guides are plus/minus 1e-7 and zero"}

boxAround :: [V2] -> Box
boxAround ps = case ps of
  [] -> Box (V2 0 0) (V2 1 1)
  _ -> let xs = [x | V2 x _ <- ps]; ys = [y | V2 _ y <- ps]; cx = (minimum xs + maximum xs) / 2; cy = (minimum ys + maximum ys) / 2; radius = max 1e-6 (0.8 * max (maximum xs - minimum xs) (maximum ys - minimum ys)) in Box (V2 (cx - radius) (cy - radius)) (V2 (cx + radius) (cy + radius))

boxValue :: Box -> [[Double]]
boxValue (Box (V2 x y) (V2 u v)) = [[x, y], [u, v]]

xy :: V3 -> V2
xy (V3 x y _) = V2 x y

xyz :: V3 -> [Double]
xyz (V3 x y z) = [x, y, z]

vector :: [Double] -> IO V3
vector [x, y, z] | all (\q -> not (isNaN q || isInfinite q)) [x, y, z] = pure (V3 x y z)
vector _ = die "saved positions need three finite coordinates"

readJson :: (FromJSON a) => FilePath -> IO (BL.ByteString, a)
readJson path = do bytes <- BL.readFile path; value <- either die pure (eitherDecode bytes); pure (bytes, value)

field :: (FromJSON a) => Key -> Value -> IO a
field key = either die pure . parseEither (withObject "saved archive" (.: key))

expect :: (Eq a, FromJSON a) => Key -> a -> Value -> IO ()
expect key expected record = do actual <- field key record; unless (actual == expected) (die ("changed archive field: " ++ show key))

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
