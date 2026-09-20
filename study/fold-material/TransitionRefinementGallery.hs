-- | Compare two mesh placements at equal triangle counts. All per-mesh
-- measurements and FOLD/profile exports reuse BendRefinementGallery, keeping
-- the previous uniform ladder reproducible. New plots show the actual column
-- locations alongside analytic-cost errors; the browser does no geometry.
module TransitionRefinementGallery (writeTransitionRefinement) where

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

writeTransitionRefinement :: FilePath -> IO ()
writeTransitionRefinement destination = do
  let output = destination </> "transition-refinement"
      constructions = [(SampledReference, "samples"), (LengthReference, "segments")]
      budgets = [(m, k, t) | (m, k, t) <- referenceMeshes, m /= Uneven120]
  createDirectoryIfMissing True output
  groups <- forM [(CircularArc, "circular"), (SmoothTransition, "smooth")] $ \(family, name) -> do
    curve <- checked (commonCurveWith family)
    V3 tx ty tz <- checked gripTarget
    sets <- forM budgets $ \(budget, mk, label) -> do
      local <- checked (transitionGrid budget curve)
      let uniform = referenceGrid budget
      TIO.writeFile (output </> name <> "-" <> mk <> "-columns.svg") (columnsSvg curve uniform local)
      runs <- forM constructions $ \(construction, ck) -> do
        states <- forM [("uniform", uniform), ("local", local)] $ \(placement, grid) -> do
          let stem = name <> "-" <> ck <> "-" <> mk <> "-" <> placement
              columns = gridColumns grid
              priorities = [object ["interval" .= map (fromRational :: Rational -> Double) [a, b], "weightedLength" .= (fromRational (intervalPriority curve a b) :: Double)] | (a, b) <- zip columns (drop 1 columns)]
              description = ReferenceExport stem (T.pack name <> " · " <> T.pack ck <> " · " <> label <> " · " <> T.pack placement) ["construction" .= ck, "mesh" .= mk, "label" .= label, "placement" .= placement, "intervalPriorities" .= priorities]
          (_, measured, report) <- writeReferenceState output curve grid construction description
          pure (placement, budget, construction, measured, report)
        (distance, location) <- checked (profileDifference uniform local construction curve)
        pure (states, object ["construction" .= ck, "mesh" .= mk, "maxMaterialDisplacement" .= distance, "atMaterialDistance" .= location])
      pure (concatMap fst runs, map snd runs)
    let runs = concatMap fst sets
    forM_ constructions $ \(construction, ck) -> TIO.writeFile (output </> name <> "-" <> ck <> "-errors.svg") (errorsSvg curve construction runs)
    pure (object ["id" .= name, "gripTarget" .= [tx, ty, tz], "curvature" .= curveCurvature curve, "bendLength" .= curveArcLength curve, "continuousEnergy" .= curveEnergy curve, "windows" .= [[fromRational a, fromRational b] :: [Double] | (a, b) <- transitionWindows curve], "runs" .= [r | (_, _, _, _, r) <- runs], "comparisons" .= concatMap snd sets])
  let document = object ["groups" .= groups, "windowRadius" .= (fromRational transitionWindowRadius :: Double), "insideDensity" .= (4 :: Int), "outsideDensity" .= (1 :: Int), "materialCoefficient" .= (0.2 :: Double), "widthStrips" .= (2 :: Int), "lengthCap" .= (1e-5 :: Double), "materialOptimizerRun" .= False, "perMeshFitRun" .= False, "gripsCopied" .= False, "continuousMotionChecked" .= False]
  BL.writeFile (output </> "checks.json") (encode document)
  template <- TIO.readFile "study/fold-material/transition-refinement.html"
  TIO.writeFile (destination </> "transition-refinement.html") (T.replace "/*TRANSITION_REFINEMENT*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn "Wrote transition-refinement.html: 40 equal-budget controls; placement uses geometry, never energy."

columnsSvg :: HeldCurve -> ReferenceGrid -> ReferenceGrid -> Text
columnsSvg curve uniform local = renderSvg defaultPage {pageWidth = 650, pageHeight = 200, pageMargin = 0, pageBackground = Nothing, pageTitle = Just "Where the same number of columns goes"} $ diagramWithExtent (Box (V2 0 0) (V2 650 200)) shapes
  where
    x s = 100 + 1000 * fromRational s
    shapes = [Fill (Colour "#eee1cb") [[V2 (x a) 55, V2 (x b) 55, V2 (x b) 155, V2 (x a) 155]] | (a, b) <- transitionWindows curve] ++ concat [[Polyline (solid (Colour colour) 1) [V2 100 y, V2 600 y], Label (Colour colour) 12 (V2 10 y) label] ++ [Polyline (solid (Colour colour) 1) [V2 (x s) (y - 10), V2 (x s) (y + 10)] | s <- gridColumns grid] | (grid, y, label, colour) <- [(uniform, 135, "Uniform", "#397f88"), (local, 75, "Local", "#b35836")]] ++ [Label (Colour "#6d675b") 12 (V2 (x s) 30) label | (s, label) <- [(0, "0"), (1 / 8, "1/8"), (1 / 4, "1/4"), (3 / 8, "3/8"), (1 / 2, "1/2")]] ++ [Label (Colour "#6d675b") 12 (V2 185 5) "Material distance from the shared crease"]

errorsSvg :: HeldCurve -> ReferenceConstruction -> [PlacedRun] -> Text
errorsSvg curve construction runs = renderSvg defaultPage {pageWidth = 650, pageHeight = 300, pageMargin = 0, pageBackground = Nothing, pageTitle = Just "Absolute analytic-cost error (%)"} $ diagramWithExtent (Box (V2 0 0) (V2 650 300)) shapes
  where
    xy mesh measured = let n = fromIntegral (8 * (length (referenceColumns mesh) - 1)); e = 100 * abs (probeLowerEnergy measured / curveEnergy curve - 1) in V2 (60 + 130 * logBase 2 (n / 64)) (45 + 9 * e)
    shapes = [Polyline (solid (Colour "#ddd5c7") 0.7) [V2 60 (45 + 9 * v), V2 580 (45 + 9 * v)] | v <- [0, 5, 10, 15, 20]] ++ [Label (Colour "#6d675b") 12 (V2 20 (45 + 9 * v)) (tshow (round v :: Int) <> "%") | v <- [0, 5, 10, 15, 20]] ++ [Label (Colour "#6d675b") 12 (V2 (60 + 130 * fromIntegral i) 22) (tshow n) | (i, n) <- zip [0 :: Int ..] [64, 128, 256, 512, 1024 :: Int]] ++ [Label (Colour "#6d675b") 12 (V2 280 2) "Triangles"] ++ [Polyline (solid (Colour colour) 2) [xy m p | (name, m, c, p, _) <- runs, c == construction, name == placement] | (placement, colour) <- [("uniform", "#397f88"), ("local", "#b35836")]]

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
