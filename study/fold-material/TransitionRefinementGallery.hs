-- | Compare fixed mesh placements at equal triangle counts. All per-mesh
-- measurements and FOLD/profile exports reuse BendRefinementGallery, keeping
-- the previous uniform ladder reproducible. New plots show the actual column
-- locations alongside analytic-cost errors; the browser does no geometry.
-- The later comparison adds whole-bend priority and all three pairwise
-- geometric differences. The original two-placement gallery stays reproducible.
module TransitionRefinementGallery (writeTransitionRefinement, writeWholeBendRefinement) where

import BendRefinement
import BendRefinementGallery (ReferenceExport (..), writeReferenceState)
import Control.Monad (forM, forM_)
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import HeldBend
import PrescribedBend
import Senbazuru.Diagram
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Render.Svg
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import TransitionRefinement

type PlacedRun = (String, ReferenceMesh, ReferenceConstruction, ProbeMeasure, Value)

data PlacementStudy = TransitionStudy | WholeBendStudy

writeTransitionRefinement :: FilePath -> IO ()
writeTransitionRefinement = writePlacementStudy TransitionStudy

writeWholeBendRefinement :: FilePath -> IO ()
writeWholeBendRefinement = writePlacementStudy WholeBendStudy

writePlacementStudy :: PlacementStudy -> FilePath -> IO ()
writePlacementStudy study destination = do
  let folder = case study of TransitionStudy -> "transition-refinement"; WholeBendStudy -> "whole-bend"
      output = destination </> folder
      constructions = [(SampledReference, "samples"), (LengthReference, "segments")]
      budgets = [(m, k, t) | (m, k, t) <- referenceMeshes, m /= Uneven120]
  createDirectoryIfMissing True output
  groups <- forM [(CircularArc, "circular"), (SmoothTransition, "smooth")] $ \(family, name) -> do
    curve <- checked (commonCurveWith family)
    V3 tx ty tz <- checked gripTarget
    sets <- forM budgets $ \(budget, mk, label) -> do
      local <- checked (transitionGrid budget curve)
      let uniform = referenceGrid budget
      extra <- case study of
        TransitionStudy -> pure []
        WholeBendStudy -> do
          whole <- checked (wholeBendGrid budget curve)
          pure [("whole", whole)]
      let placements = [("uniform", uniform), ("local", local)] ++ extra
      TIO.writeFile (output </> name <> "-" <> mk <> "-columns.svg") (columnsSvg study curve placements)
      runs <- forM constructions $ \(construction, ck) -> do
        states <- forM placements $ \(placement, grid) -> do
          let stem = name <> "-" <> ck <> "-" <> mk <> "-" <> placement
              columns = gridColumns grid
              priority = if placement == "whole" then wholeBendPriority curve else intervalPriority curve
              priorities = [object ["interval" .= map (fromRational :: Rational -> Double) [a, b], "weightedLength" .= (fromRational (priority a b) :: Double)] | (a, b) <- zip columns (drop 1 columns)]
              description = ReferenceExport stem (T.pack name <> " · " <> T.pack ck <> " · " <> label <> " · " <> T.pack placement) ["construction" .= ck, "mesh" .= mk, "label" .= label, "placement" .= placement, "intervalPriorities" .= priorities]
          (_, measured, report) <- writeReferenceState output curve grid construction description
          pure (placement, budget, construction, measured, report)
        comparisons <- forM [(a, b) | (i, a) <- zip [0 :: Int ..] placements, (j, b) <- zip [0 ..] placements, i < j] $ \((left, a), (right, b)) -> do
          (distance, location) <- checked (profileDifference a b construction curve)
          let names = case study of TransitionStudy -> []; WholeBendStudy -> ["leftPlacement" .= left, "rightPlacement" .= right]
          pure (object (["construction" .= ck, "mesh" .= mk, "maxMaterialDisplacement" .= distance, "atMaterialDistance" .= location] ++ names))
        pure (states, comparisons)
      pure (concatMap fst runs, concatMap snd runs)
    let runs = concatMap fst sets
    forM_ constructions $ \(construction, ck) -> TIO.writeFile (output </> name <> "-" <> ck <> "-errors.svg") (errorsSvg study curve construction runs)
    let region = case study of TransitionStudy -> []; WholeBendStudy -> let (a, b) = wholeBendRegion curve in ["wholeBendRegion" .= ([fromRational a, fromRational b] :: [Double])]
    pure (object (["id" .= name, "gripTarget" .= [tx, ty, tz], "curvature" .= curveCurvature curve, "bendLength" .= curveArcLength curve, "continuousEnergy" .= curveEnergy curve, "windows" .= [[fromRational a, fromRational b] :: [Double] | (a, b) <- transitionWindows curve], "runs" .= [r | (_, _, _, _, r) <- runs], "comparisons" .= concatMap snd sets] ++ region))
  let document = object ["groups" .= groups, "windowRadius" .= (fromRational transitionWindowRadius :: Double), "insideDensity" .= (4 :: Int), "outsideDensity" .= (1 :: Int), "materialCoefficient" .= (0.2 :: Double), "widthStrips" .= (2 :: Int), "lengthCap" .= (1e-5 :: Double), "materialOptimizerRun" .= False, "perMeshFitRun" .= False, "gripsCopied" .= False, "continuousMotionChecked" .= False]
  BL.writeFile (output </> "checks.json") (encode document)
  template <- TIO.readFile ("study/fold-material" </> folder <> ".html")
  TIO.writeFile (destination </> folder <> ".html") (T.replace "/*TRANSITION_REFINEMENT*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn ("Wrote " <> folder <> ".html: equal-budget controls; placement uses geometry, never energy.")

placementStyles :: PlacementStudy -> [(String, Text, Text)]
placementStyles TransitionStudy = [("uniform", "Uniform", "#397f88"), ("local", "Local", "#b35836")]
placementStyles WholeBendStudy = [("uniform", "Uniform", "#397f88"), ("local", "Joins", "#b35836"), ("whole", "Whole bend", "#785f9b")]

columnsSvg :: PlacementStudy -> HeldCurve -> [(String, ReferenceGrid)] -> Text
columnsSvg study curve placements = renderSvg defaultPage {pageWidth = 650, pageHeight = height, pageMargin = 0, pageBackground = Nothing, pageTitle = Just "Where the same number of columns goes"} $ diagramWithExtent (Box (V2 0 0) (V2 650 height)) shapes
  where
    height = case study of TransitionStudy -> 200; WholeBendStudy -> 260
    x s = 100 + 1000 * fromRational s
    regions = case study of
      TransitionStudy -> [(a, b, 55, 155) | (a, b) <- transitionWindows curve]
      WholeBendStudy -> [(a, b, 120, 150) | (a, b) <- transitionWindows curve] ++ [let (a, b) = wholeBendRegion curve in (a, b, 60, 90)]
    rows = [(grid, height - 65 - 60 * fromIntegral i, label, colour) | (i, (name, label, colour)) <- zip [0 :: Int ..] (placementStyles study), (key, grid) <- placements, key == name]
    shapes = [Fill (Colour "#eee1cb") [[V2 (x a) lo, V2 (x b) lo, V2 (x b) hi, V2 (x a) hi]] | (a, b, lo, hi) <- regions] ++ concat [[Polyline (solid (Colour colour) 1) [V2 100 y, V2 600 y], Label (Colour colour) 12 (V2 10 y) label] ++ [Polyline (solid (Colour colour) 1) [V2 (x s) (y - 10), V2 (x s) (y + 10)] | s <- gridColumns grid] | (grid, y, label, colour) <- rows] ++ [Label (Colour "#6d675b") 12 (V2 (x s) 30) label | (s, label) <- [(0, "0"), (1 / 8, "1/8"), (1 / 4, "1/4"), (3 / 8, "3/8"), (1 / 2, "1/2")]] ++ [Label (Colour "#6d675b") 12 (V2 185 5) "Material distance from the shared crease"]

errorsSvg :: PlacementStudy -> HeldCurve -> ReferenceConstruction -> [PlacedRun] -> Text
errorsSvg study curve construction runs = renderSvg defaultPage {pageWidth = 650, pageHeight = 300, pageMargin = 0, pageBackground = Nothing, pageTitle = Just "Absolute analytic-cost error (%)"} $ diagramWithExtent (Box (V2 0 0) (V2 650 300)) shapes
  where
    xy mesh measured = let n = fromIntegral (8 * (length (referenceColumns mesh) - 1)); e = 100 * abs (probeLowerEnergy measured / curveEnergy curve - 1) in V2 (60 + 130 * logBase 2 (n / 64)) (45 + 9 * e)
    shapes = [Polyline (solid (Colour "#ddd5c7") 0.7) [V2 60 (45 + 9 * v), V2 580 (45 + 9 * v)] | v <- [0, 5, 10, 15, 20]] ++ [Label (Colour "#6d675b") 12 (V2 20 (45 + 9 * v)) (tshow (round v :: Int) <> "%") | v <- [0, 5, 10, 15, 20]] ++ [Label (Colour "#6d675b") 12 (V2 (60 + 130 * fromIntegral i) 22) (tshow n) | (i, n) <- zip [0 :: Int ..] [64, 128, 256, 512, 1024 :: Int]] ++ [Label (Colour "#6d675b") 12 (V2 280 2) "Triangles"] ++ [Polyline (solid (Colour colour) 2) [xy m p | (name, m, c, p, _) <- runs, c == construction, name == placement] | (placement, _, colour) <- placementStyles study]

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
