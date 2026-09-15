-- | Compare separated layers and contact-mediated response on one small sheet.
-- A contact-disabled counterfactual has the same holds and springs; it remains
-- a diagnostic even if its material solve converges. Projected material rows
-- show the shape, while magnified gap marks cover every overlap corner across
-- the width. They are not a folding path or a contact-area measurement.
module UnequalCreaseGallery (writeUnequalCrease) where

import ClosedCrease
import Control.Exception (evaluate)
import Control.Monad (forM)
import CoupledCrease
import CoupledCreaseGallery (matching, measure)
import CreaseInequality
import CreaseInequalityGallery (resultReport)
import CreasePairContact
import Data.Aeson (Value, encode, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.List (nub)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldRelaxation
import Senbazuru.Diagram
import Senbazuru.Explain (Explain (..), num)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import Senbazuru.Render.Svg
import System.CPUTime (getCPUTime)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)
import UnequalCrease

controls :: [(String, Text, UnequalControl)]
controls = [("matched", "Matched holds", MatchedHolds), ("open", "Open the upper grip", OpenUpperGrip), ("curl", "Upper bend preference", UpperCurl), ("off", "Same preference · contact off", CurlWithoutContact), ("conflicting", "Incompatible held rows", CrossedHolds)]

writeUnequalCrease :: FilePath -> IO ()
writeUnequalCrease destination = do
  let output = destination </> "unequal-crease"
  createDirectoryIfMissing True output
  runs <- forM [(n, c) | n <- [1, 2], c <- controls] $ \(n, (key, title, control)) -> do
    fixture <- checked (unequalCrease n control)
    let stem = key ++ "-" ++ show n
        reference = coupledReference fixture
        mode = unequalContactMode control
        attempt = solveCoupledWith mode (Settings 40 1e-5) fixture
    putStrLn ("Solving " ++ stem)
    hFlush stdout
    start <- getCPUTime
    _ <- evaluate (case attempt of Left _ -> 0; Right r -> maxLengthError (inequalityMesh r) + if inequalityConverged r then 1 else 0)
    finish <- getCPUTime
    let result = either (const Nothing) Just attempt
        refusal = either (Just . explain) (const Nothing) attempt
        candidates = ("before", "Original guess", coupledSeed fixture) : maybe [] (\r -> [("repair", "Numerical starting guess", repairedMesh (inequalityInitial r)), ("after", "Solver endpoint", inequalityMesh r)]) result
    audits <- mapM (checked . auditPairContact (closedOwners reference) . (\(_, _, m) -> m)) candidates
    let gapScale = maximum (1e-8 : [fromRational (max (abs (pairMinimum a)) (abs (pairMaximum a))) | a <- audits])
    stages <- forM (zip candidates audits) $ \((stage, label, mesh), audit) -> do
      (measurement, valid) <- measure fixture mesh
      sheet <- checked (coupledSurface fixture mesh)
      let name = stem ++ "-" ++ stage
          caption = title <> " · " <> label <> " · " <> T.pack (show (32 * n)) <> " triangles"
      TIO.writeFile (output </> name ++ "-profile.svg") (profileSvg mesh)
      TIO.writeFile (output </> name ++ "-gaps.svg") (gapSvg gapScale audit)
      BL.writeFile (output </> name ++ ".fold") (encode (FoldFile (Just 1.2) (Just "senbazuru unequal crease") Nothing (Just caption) Nothing [] (materialFrame sheet) []))
      checked (renderSurfaceGlb defaultBudget CompletePaper (Just caption) sheet) >>= BS.writeFile (output </> name ++ ".glb")
      pure (stage, label, measurement, valid, object ["title" .= caption, "path" .= (name ++ ".glb")])
    let passed = mode == EnforcePairOrder && maybe False inequalityConverged result && any (\(s, _, _, valid, _) -> s == "after" && valid) stages
        report =
          object
            [ "id" .= stem,
              "control" .= key,
              "title" .= title,
              "subdivision" .= n,
              "triangles" .= length (triangles (coupledSeed fixture)),
              "vertices" .= length (samples (coupledSeed fixture)),
              "heldVertices" .= IM.keys (coupledPins fixture),
              "sharedCreaseVertices" .= closedRoot reference,
              "bendControls" .= [object ["vertices" .= hingeVertices h, "restRadians" .= hingeRest h, "stiffness" .= hingeStiffness h] | h <- closedHinges reference, hingeRole h == BendControl],
              "contactEnabled" .= (mode == EnforcePairOrder),
              "passed" .= passed,
              "refusal" .= refusal,
              "solve" .= fmap resultReport result,
              "solveCpuSeconds" .= (fromIntegral (finish - start) / 1e12 :: Double),
              "gapPlotScale" .= gapScale,
              "measurements" .= object [Key.fromString s .= v | (s, _, v, _, _) <- stages],
              "stages" .= [object ["id" .= s, "label" .= label] | (s, label, _, _, _) <- stages],
              "continuousMotionChecked" .= False
            ]
    putStrLn (stem ++ ": endpoint passed " ++ show passed ++ maybe "" (\reason -> "; " ++ T.unpack reason) refusal)
    hFlush stdout
    pure (key, n, report, [v | (_, _, _, _, v) <- stages], fmap inequalityMesh result)
  refinement <- forM [(key, a, b) | (key, 1, _, _, Just a) <- runs, (other, 2, _, _, Just b) <- runs, key == other] $ \(key, a, b) -> do
    difference <- checked (matching a b)
    pure (object ["control" .= key, "maxMatchingPositionChange" .= difference])
  responses <- forM [(key, n, a, b) | ("matched", n, _, _, Just a) <- runs, (key, k, _, _, Just b) <- runs, n == k] $ \(key, n, a, b) -> response key n a b
  contactEffect <- forM [(n, a, b) | ("off", n, _, _, Just a) <- runs, ("curl", k, _, _, Just b) <- runs, n == k] $ \(n, a, b) -> response "curl" n a b
  let document = object ["runs" .= [r | (_, _, r, _, _) <- runs], "refinement" .= refinement, "responses" .= responses, "contactEffect" .= contactEffect]
  BL.writeFile (output </> "checks.json") (encode document)
  BL.writeFile (output </> "models.json") (encode (concat [ms | (_, _, _, ms, _) <- runs]))
  viewer <- TIO.readFile "study/gltf/viewer.html"
  let compact = "header{padding:16px}header small,header h1,header p{display:none}#view{height:450px;min-height:450px}footer{padding:12px 16px}</style>"
  TIO.writeFile (output </> "index.html") (T.replace "</style>" compact (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer))
  template <- TIO.readFile "study/fold-material/unequal-crease.html"
  TIO.writeFile (destination </> "unequal-crease.html") (T.replace "/*UNEQUAL_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn ("Wrote unequal-crease.html and measurements to " ++ destination)

response :: String -> Int -> MaterialMesh -> MaterialMesh -> IO Value
response key n a b = do
  (lower, upper) <- checked (panelChanges a b)
  pure (object ["control" .= key, "subdivision" .= n, "lowerChange" .= lower, "upperChange" .= upper])

profileSvg :: MaterialMesh -> Text
profileSvg mesh = drawing "Projected material rows" (Box (V2 (-0.03) (-0.05)) (V2 0.54 0.21)) shapes
  where
    shapes =
      [Polyline (solid (Colour colour) 1.4) [V2 x z | p <- samples mesh, materialU p * side >= 0, materialV p == row, let V3 x _ z = position p] | (side, colour) <- [(1, "#386d69"), (-1, "#a66828")], row <- [-0.5, 0, 0.5]]
        ++ [Label (Colour "#70685b") 12 (V2 0 (-0.035)) "crease", Label (Colour "#70685b") 12 (V2 0.38 (-0.035)) "outer edge"]

gapSvg :: Double -> PairAudit -> Text
gapSvg scale audit = drawing "Exact gaps at overlap corners, magnified" (Box (V2 (-0.03) (-0.15)) (V2 0.54 0.16)) shapes
  where
    points = nub [(fromRational x, fromRational (pairGap w)) | w <- pairWitnesses audit, let (x, _) = pairLocation w]
    shapes =
      [Polyline (solid (Colour "#aaa292") 1) [V2 0 0, V2 0.5 0], Label (Colour "#70685b") 12 (V2 0 0.13) ("gap scale +/- " <> num scale), Label (Colour "#70685b") 12 (V2 0 (-0.135)) "x position across the overlap"]
        ++ [Polyline (solid (Colour (if gap < 0 then "#b6412b" else "#386d69")) 1) [V2 x 0, V2 x (0.1 * gap / scale)] | (x, gap) <- points]

drawing :: Text -> Box -> [Shape] -> Text
drawing title extent shapes = renderSvg defaultPage {pageWidth = 560, pageHeight = 290, pageMargin = 20, pageBackground = Nothing, pageTitle = Just title} (diagramWithExtent extent shapes)

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
