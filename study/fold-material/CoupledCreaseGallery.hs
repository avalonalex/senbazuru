-- | Show that releasing the lower panel changes the solved paper. The
-- displacement plots use one scale for both panels and all stages of a run;
-- they are magnified measurements, not distorted 3D geometry. Refusals retain
-- the original guess only. Every successful solve still gets separate static
-- endpoint checks and a two-resolution comparison at matching material points.
module CoupledCreaseGallery (writeCoupledCrease) where

import ClosedCrease
import Control.Exception (evaluate)
import Control.Monad (forM, forM_)
import CoupledCrease
import CreaseCorrection
import CreaseInequality
import CreaseInequalityGallery (resultReport)
import CreasePairContact
import Data.Aeson (Value, encode, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldMaterial (componentCount)
import FoldRelaxation
import Senbazuru.Diagram
import Senbazuru.Explain (Explain (..), num)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import Senbazuru.Render.Svg
import System.CPUTime (getCPUTime)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)

controls :: [(String, Text, Maybe CoupledControl)]
controls = [("fixed", "Fixed lower baseline", Nothing), ("touching", "Both free · touching", Just BothTouching), ("penetrating", "Both free · penetrating", Just BothPenetrating), ("tiny", "Both free · tiny penetration", Just BothTiny), ("conflicting", "Incompatible held rows", Just IncompatibleHolds)]

writeCoupledCrease :: FilePath -> IO ()
writeCoupledCrease destination = do
  let output = destination </> "coupled-crease"
  createDirectoryIfMissing True output
  runs <- forM [(n, c) | n <- [1, 2], c <- controls] $ \(n, (key, title, control)) -> do
    (fixture, attempt) <- case control of
      Nothing -> do
        fixed <- checked (creaseCorrection n PenetratingGuess)
        pure (CoupledFixture (correctionReference fixed) (correctionSeed fixed) (correctionPins fixed), solveInequality (Settings 40 1e-5) fixed)
      Just c -> do
        both <- checked (coupledCrease n c)
        pure (both, solveCoupled (Settings 40 1e-5) both)
    let stem = key ++ "-" ++ show n
        seed = coupledSeed fixture
        reference = closedMesh (coupledReference fixture)
    putStrLn ("Solving " ++ stem)
    hFlush stdout
    start <- getCPUTime
    _ <- evaluate (case attempt of Left _ -> 0; Right r -> maxLengthError (inequalityMesh r) + if inequalityConverged r then 1 else 0)
    finish <- getCPUTime
    let result = either (const Nothing) Just attempt
        refusal = either (Just . explain) (const Nothing) attempt
        candidates = ("before", "Original guess", seed) : maybe [] (\r -> [("repair", "Feasible starting guess", repairedMesh (inequalityInitial r)), ("after", "Settled endpoint", inequalityMesh r)]) result
        scale = maximum (1e-8 : [norm (position a ^-^ position b) | (_, _, mesh) <- candidates, (a, b) <- zip (samples reference) (samples mesh)])
    stages <- forM candidates $ \(stage, label, mesh) -> do
      (measurement, valid) <- measure fixture mesh
      sheet <- checked (coupledSurface fixture mesh)
      let name = stem ++ "-" ++ stage
          caption = title <> " · " <> label <> " · " <> T.pack (show (32 * n)) <> " triangles"
      forM_ [(-1, "upper"), (1, "lower")] $ \(side, which) -> TIO.writeFile (output </> name ++ "-" ++ which ++ ".svg") (motionSvg reference mesh side scale)
      BL.writeFile (output </> name ++ ".fold") (encode (FoldFile (Just 1.2) (Just "senbazuru coupled crease") Nothing (Just caption) Nothing [] (materialFrame sheet) []))
      bytes <- checked (renderSurfaceGlb defaultBudget CompletePaper (Just caption) sheet)
      BS.writeFile (output </> name ++ ".glb") bytes
      pure (stage, label, measurement, valid, object ["title" .= caption, "path" .= (name ++ ".glb")])
    let passed = maybe False inequalityConverged result && any (\(s, _, _, valid, _) -> s == "after" && valid) stages
        report =
          object
            [ "id" .= stem,
              "control" .= key,
              "title" .= title,
              "subdivision" .= n,
              "triangles" .= length (triangles seed),
              "vertices" .= length (samples seed),
              "components" .= componentCount seed,
              "sharedCreaseVertices" .= closedRoot (coupledReference fixture),
              "heldVertices" .= IM.keys (coupledPins fixture),
              "passed" .= passed,
              "refusal" .= refusal,
              "solve" .= fmap resultReport result,
              "solveCpuSeconds" .= (fromIntegral (finish - start) / 1e12 :: Double),
              "movementPlotScale" .= scale,
              "measurements" .= object [Key.fromString s .= v | (s, _, v, _, _) <- stages],
              "stages" .= [object ["id" .= s, "label" .= label] | (s, label, _, _, _) <- stages],
              "continuousMotionChecked" .= False
            ]
    putStrLn (stem ++ ": endpoint passed " ++ show passed ++ maybe "" (\reason -> "; " ++ T.unpack reason) refusal)
    hFlush stdout
    pure (key, n, report, [v | (_, _, _, _, v) <- stages], fmap inequalityMesh result)
  refinements <- forM [(key, coarse, fine) | (key, 1, _, _, Just coarse) <- runs, (other, 2, _, _, Just fine) <- runs, key == other] $ \(key, coarse, fine) -> do
    difference <- checked (matching coarse fine)
    pure (object ["control" .= key, "maxMatchingPositionChange" .= difference])
  let document = object ["runs" .= [r | (_, _, r, _, _) <- runs], "refinement" .= refinements]
  BL.writeFile (output </> "checks.json") (encode document)
  BL.writeFile (output </> "models.json") (encode (concat [ms | (_, _, _, ms, _) <- runs]))
  viewer <- TIO.readFile "study/gltf/viewer.html"
  let compact = "header{padding:16px}header small,header h1,header p{display:none}#view{height:450px;min-height:450px}footer{padding:12px 16px}</style>"
  TIO.writeFile (output </> "index.html") (T.replace "</style>" compact (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer))
  template <- TIO.readFile "study/fold-material/coupled-crease.html"
  TIO.writeFile (destination </> "coupled-crease.html") (T.replace "/*COUPLED_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn ("Wrote coupled-crease.html and two-panel measurements to " ++ destination)

measure :: CoupledFixture -> MaterialMesh -> IO (Value, Bool)
measure fixture mesh = do
  checked (checkCoupledMaterial fixture mesh)
  gap <- checked (auditPairContact owners mesh)
  contact <- checked (checkTriangleContact (V3 0 0 1) [(FaceId 0, FaceId 1)] owners mesh)
  let vertices = IM.fromList (zip [0 ..] (samples mesh))
  angles <- mapM (checked . (`hingeAngle` vertices)) [h | h <- closedHinges (coupledReference fixture), SurfaceCrease _ <- [hingeRole h]]
  (creaseEnergy, panelEnergy) <- checked (bendingEnergy (closedHinges (coupledReference fixture)) mesh)
  let angleErrorMax = maximum (0 : [abs (angleError a pi) | (a, _) <- angles])
      lengthError = maxLengthError mesh
      movement side = maximum (0 : [norm (position a ^-^ position b) | (a, b) <- zip (samples reference) (samples mesh), signum (materialU a) == side])
      rational r = object ["exact" .= show r, "value" .= (fromRational r :: Double)]
      passed = pairMinimum gap >= 0 && lengthError <= 1e-5 && angleErrorMax <= 1e-5 && contactPassed contact
  pure (object ["minGap" .= rational (pairMinimum gap), "maxGap" .= rational (pairMaximum gap), "maxRelativeEdgeError" .= lengthError, "maxCreaseErrorRadians" .= angleErrorMax, "creaseRadians" .= map fst angles, "heldPositionError" .= (0 :: Double), "contact" .= contact, "lowerMovement" .= movement 1, "upperMovement" .= movement (-1), "panelBendingEnergy" .= panelEnergy, "creaseEnergy" .= creaseEnergy], passed)
  where
    reference = closedMesh (coupledReference fixture); owners = closedOwners (coupledReference fixture)

matching :: MaterialMesh -> MaterialMesh -> Either InequalityError Double
matching coarse fine = do
  distances <- forM (samples coarse) $ \p -> case M.lookup (materialU p, materialV p) positions of
    Nothing -> Left (InequalityError "refinement lost a material point from the coarse mesh")
    Just q -> pure (norm (position p ^-^ q))
  pure (maximum (0 : distances))
  where
    positions = M.fromList [((materialU p, materialV p), position p) | p <- samples fine]

motionSvg :: MaterialMesh -> MaterialMesh -> Double -> Double -> Text
motionSvg reference mesh side scale = renderSvg defaultPage {pageWidth = 560, pageHeight = 270, pageMargin = 20, pageBackground = Nothing, pageTitle = Just "Panel displacement, magnified"} (diagramWithExtent extent shapes)
  where
    extent = Box (V2 (-0.03) (-0.07)) (V2 0.54 0.19)
    colour = Colour (if side > 0 then "#386d69" else "#a66828")
    curves = [[V2 (abs (materialU a)) (0.12 * norm (position a ^-^ position b) / scale) | (a, b) <- zip (samples reference) (samples mesh), materialU a * side >= 0, materialV a == row] | row <- [-0.5, 0, 0.5]]
    shapes = [Polyline (solid (Colour "#a49b8b") 1) [V2 0 0, V2 0.5 0], Label colour 12 (V2 0 0.15) ("scale maximum " <> num scale <> " sheet lengths"), Label (Colour "#70685b") 12 (V2 0 (-0.04)) "crease", Label (Colour "#70685b") 12 (V2 0.39 (-0.04)) "outer hold"] ++ [Polyline (solid colour 1.3) points | points <- curves]

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
