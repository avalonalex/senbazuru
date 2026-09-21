-- | Read-only inspection of the first crossing correction in the recovered
-- body-patch archive. Verify saved FOLD identities, trace linkage and reported
-- measurements before writing anything. Both cameras use unchanged positions;
-- the height chart is explicitly a measurement plot, not a deformed shape.
module BodyContactGallery (writeBodyContact, drawPair, boxAround) where

import BodyContactDiagnosis
import BodyCorrectionArchive
import BodyPatch
import BodyPatchCheckpoints
import Control.Monad (forM, forM_, unless)
import CraneSpread
import Data.Aeson (Value, encode, object, toJSON, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldContact (ContactRow (..))
import FoldRelaxation (maxLengthError)
import Senbazuru.Diagram
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Contact (crossingPanels, panelTolerance)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Svg
import SurfaceContact qualified as C
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))

writeBodyContact :: FilePath -> FilePath -> IO ()
writeBodyContact source destination = do
  let output = destination </> "body-contact"
  separateOutput source output
  archive <- readCorrectionArchive source
  let study = archiveStudy archive
      inputs = archiveStates archive
      fixture = patchSpread study
      base = spreadMesh fixture
  (before, after, firstStep, secondStep) <- case (inputs, archiveTrace archive) of
    ([_, (_, _, a, _), (_, _, b, _)], s1 : s2 : _) -> pure (a, b, s1, s2)
    _ -> die "expected two saved corrections"
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
  forM_ (archiveFiles archive) $ \(name, raw) -> BL.writeFile (output </> "source" </> name) raw
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
