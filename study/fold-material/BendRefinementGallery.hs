-- | A fixed-reference refinement ladder with raw geometry and spring rows.
-- BendRefinement builds each approximation; this boundary measures it through
-- the existing length, angle and exact touching-order checks. The analytic
-- cost is a numerical reference, not a calibrated stiffness of real paper.
-- The page selects exported data only; all geometry and plots are Haskell.
module BendRefinementGallery (writeBendRefinement, ReferenceExport (..), writeReferenceState) where

import BendLocations (locateBends)
import BendLocationsGallery (rowJson)
import BendRefinement
import ClosedCrease
import Control.Monad (forM, forM_)
import CoupledCreaseGallery (matching)
import CreasePairContact
import Data.Aeson (Value, encode, object, (.=))
import Data.Aeson.Types (Pair)
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldMaterial (componentCount)
import HeldBend
import PrescribedBend
import Senbazuru.Diagram
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Types (FoldFile (..))
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Senbazuru.Render.Svg
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))

constructions :: [(ReferenceConstruction, String)]
constructions = [(SampledReference, "samples"), (LengthReference, "segments")]

type Run = (ReferenceConstruction, ReferenceMesh, String, ClosedCrease, ProbeMeasure, Value)

writeBendRefinement :: FilePath -> IO ()
writeBendRefinement destination = do
  let output = destination </> "bend-refinement"
  createDirectoryIfMissing True output
  groups <- forM [(CircularArc, "circular"), (SmoothTransition, "smooth")] $ \(family, name) -> do
    curve <- checked (commonCurveWith family)
    target <- checked gripTarget
    runs <- forM [(c, m) | c <- constructions, m <- referenceMeshes] $ \((construction, ck), (choice, mk, label)) -> do
      let stem = name <> "-" <> ck <> "-" <> mk
          description = ReferenceExport stem (T.pack name <> " · " <> T.pack ck <> " · " <> label) ["construction" .= ck, "mesh" .= mk, "label" .= label, "anchor" .= (choice == Uneven120)]
      (paper, measured, report) <- writeReferenceState output curve (referenceGrid choice) construction description
      pure (construction, choice, stem, paper, measured, report)
    comparisons <- forM [(a, b) | a@(c, m, _, _, _, _) <- runs, b@(d, n, _, _, _, _) <- runs, c == d, (m, n) `elem` pairs] $ \((_, _, a, pa, ma, _), (_, _, b, pb, mb, _)) -> do
      movement <- checked (matching (closedMesh pa) (closedMesh pb))
      let delta before after = object ["difference" .= (after - before), "relativeChangePercent" .= (100 * abs (after - before) / abs before)]
      pure (object ["before" .= a, "after" .= b, "matchingVertexMovement" .= movement, "lower" .= delta (probeLowerEnergy ma) (probeLowerEnergy mb), "upper" .= delta (probeUpperEnergy ma) (probeUpperEnergy mb)])
    forM_ constructions $ \(c, ck) -> TIO.writeFile (output </> name <> "-" <> ck <> "-errors.svg") (errorSvg curve c runs)
    pure (object ["id" .= name, "curvature" .= curveCurvature curve, "bendLength" .= curveArcLength curve, "continuousEnergy" .= curveEnergy curve, "gripTarget" .= coords target, "runs" .= [r | (_, _, _, _, _, r) <- runs], "comparisons" .= comparisons])
  let document = object ["groups" .= groups, "materialCoefficient" .= (0.2 :: Double), "widthStrips" .= (2 :: Int), "lengthCap" .= (1e-5 :: Double), "materialOptimizerRun" .= False, "perMeshFitRun" .= False, "gripsCopied" .= False, "continuousMotionChecked" .= False]
  BL.writeFile (output </> "checks.json") (encode document)
  template <- TIO.readFile "study/fold-material/bend-refinement.html"
  TIO.writeFile (destination </> "bend-refinement.html") (T.replace "/*BEND_REFINEMENT*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn "Wrote bend-refinement.html: 24 fixed-curve references; no per-mesh fits or material solves."
  where
    pairs = [(Uniform64, Uniform128), (Uniform128, Uniform256), (Uniform256, Uniform512), (Uniform512, Uniform1024), (Uniform64, Uneven120)]

-- | Metadata belongs to the experiment; all measurements and exports share
-- one implementation so a new placement policy cannot quietly change them.
data ReferenceExport = ReferenceExport
  { exportStem :: String,
    exportTitle :: Text,
    exportFields :: [Pair]
  }

writeReferenceState :: FilePath -> HeldCurve -> ReferenceGrid -> ReferenceConstruction -> ReferenceExport -> IO (ClosedCrease, ProbeMeasure, Value)
writeReferenceState output curve grid construction description = do
  target <- checked gripTarget
  paper <- checked (gridReference grid construction curve)
  measured <- checked (measureProbe paper)
  rows <- checked (locateBends paper)
  gaps <- checked (auditPairContact (closedOwners paper) (closedMesh paper))
  surface <- checked (closedSurface paper)
  let mesh = closedMesh paper
      stem = exportStem description
      outer = maximum (0 : [norm (position p ^-^ V3 x (materialV p) z) | p <- samples mesh, abs (materialU p) == 0.5, let V3 x _ z = target])
      inner = maximum (0 : [norm (position p ^-^ V3 (abs (materialU p)) (materialV p) 0) | p <- samples mesh, abs (materialU p) <= heldStart])
      distance = maximum (0 : [norm (position p ^-^ curvePoint curve (abs (materialU p)) (materialV p)) | p <- samples mesh])
      energy = curveEnergy curve
      errors cost = object ["signedDifference" .= (cost - energy), "absoluteError" .= abs (cost - energy), "relativeErrorPercent" .= (100 * abs (cost - energy) / energy)]
      columns = map (fromRational :: Rational -> Double) (gridColumns grid)
      report =
        object $
          [ "id" .= stem,
            "columns" .= columns,
            "maxColumnSpacing" .= maximum (0 : zipWith (-) (drop 1 columns) columns),
            "vertices" .= length (samples mesh),
            "triangles" .= length (triangles mesh),
            "components" .= componentCount mesh,
            "sharedCreaseVertices" .= closedRoot paper,
            "innerGripMovement" .= inner,
            "outerGripMovement" .= outer,
            "maxVertexDistanceToCurve" .= distance,
            "maxRelativeEdgeError" .= probeRelativeError measured,
            "lengthPasses" .= (probeRelativeError measured <= 1e-5),
            "maxCreaseError" .= probeCreaseError measured,
            "minimumExactGap" .= show (pairMinimum gaps),
            "maximumExactGap" .= show (pairMaximum gaps),
            "lowerPassive" .= probeLowerEnergy measured,
            "upperPassive" .= probeUpperEnergy measured,
            "lowerError" .= errors (probeLowerEnergy measured),
            "upperError" .= errors (probeUpperEnergy measured),
            "predictedPassive" .= gridAngularCost grid curve,
            "continuousEnergy" .= energy,
            "creaseEnergy" .= probeCreaseEnergy measured,
            "controlEnergy" .= probeControlEnergy measured,
            "lengthSquares" .= probeLengthSquares measured,
            "lengthEnergy" .= (1e10 * probeLengthSquares measured / 2),
            "diagnostic" .= True
          ]
            ++ exportFields description
      detail = object ["summary" .= report, "springs" .= map rowJson rows, "edges" .= [object ["vertices" .= [a, b], "rest" .= edgeRest e, "actual" .= edgeActual e] | e <- probeEdges measured, let (a, b) = edgeIds e]]
  BL.writeFile (output </> stem <> ".json") (encode detail)
  BL.writeFile (output </> stem <> ".fold") (encode (FoldFile (Just 1.2) (Just "senbazuru fixed bend refinement") Nothing (Just (exportTitle description)) Nothing [] (materialFrame surface) []))
  TIO.writeFile (output </> stem <> ".svg") (profileSvg curve target paper)
  pure (paper, measured, report)

coords :: V3 -> [Double]
coords (V3 x y z) = [x, y, z]

profileSvg :: HeldCurve -> V3 -> ClosedCrease -> Text
profileSvg curve (V3 tx _ tz) paper = renderSvg defaultPage {pageWidth = 600, pageHeight = 280, pageMargin = 25, pageBackground = Nothing, pageTitle = Just "Fixed curve and its triangle approximation"} $ diagramWithExtent (Box (V2 (-0.025) (-0.025)) (V2 0.535 0.19)) shapes
  where
    side (V3 x _ z) = V2 x z
    points = [side (position p) | p <- samples (closedMesh paper), materialU p >= 0, materialV p == -0.5]
    shapes = [Polyline (solid (Colour "#bab4a8") 4) [side (curvePoint curve (fromIntegral i / 800) 0) | i <- [0 :: Int .. 400]], Polyline (solid (Colour "#397f88") 2) points, Polyline (Stroke (Colour "#b35836") 1 (Dash [5, 5])) points, Polyline (solid (Colour "#343d32") 3) [V2 0 0, V2 heldStart 0], Polyline (solid (Colour "#343d32") 2) [V2 (tx - 0.005) (tz - 0.005), V2 (tx + 0.005) (tz + 0.005)], Polyline (solid (Colour "#343d32") 2) [V2 (tx - 0.005) (tz + 0.005), V2 (tx + 0.005) (tz - 0.005)]] ++ [Polyline (solid (Colour "#70685b") 0.6) [V2 x (z - 0.002), V2 x (z + 0.002)] | V2 x z <- points]

-- One linear vertical scale in percent for every family. A mesh-to-mesh gap
-- is deliberately absent from this plot: zero means agreement with the fixed
-- analytic integral. The uneven mesh is an isolated cross, not a ladder step.
errorSvg :: HeldCurve -> ReferenceConstruction -> [Run] -> Text
errorSvg curve construction runs = renderSvg defaultPage {pageWidth = 650, pageHeight = 300, pageMargin = 0, pageBackground = Nothing, pageTitle = Just "Absolute error against analytic cost (%)"} $ diagramWithExtent (Box (V2 0 0) (V2 650 300)) shapes
  where
    selected = [(m, p) | (c, m, _, _, p, _) <- runs, c == construction]
    xy m p = let n = fromIntegral (8 * (length (referenceColumns m) - 1)); err = 100 * abs (probeLowerEnergy p / curveEnergy curve - 1) in V2 (60 + 130 * logBase 2 (n / 64)) (45 + 9 * err)
    points = [xy m p | (m, p) <- selected, m /= Uneven120]
    anchors = [xy m p | (m, p) <- selected, m == Uneven120]
    shapes = [Polyline (solid (Colour "#ddd5c7") 0.7) [V2 60 (45 + 9 * v), V2 580 (45 + 9 * v)] | v <- [0, 5, 10, 15, 20]] ++ [Label (Colour "#6d675b") 12 (V2 20 (45 + 9 * v)) (tshow (round v :: Int) <> "%") | v <- [0, 5, 10, 15, 20]] ++ [Label (Colour "#6d675b") 12 (V2 (60 + 130 * fromIntegral i) 22) (tshow n) | (i, n) <- zip [0 :: Int ..] [64, 128, 256, 512, 1024 :: Int]] ++ [Label (Colour "#6d675b") 12 (V2 240 2) "Triangles (each step halves spacing)", Polyline (solid (Colour "#397f88") 2) points] ++ [Polyline (solid (Colour "#397f88") 2) [V2 (x - 3) y, V2 (x + 3) y] | V2 x y <- points] ++ concat [[Polyline (solid (Colour "#b35836") 2) [V2 (x - 4) (y - 4), V2 (x + 4) (y + 4)], Polyline (solid (Colour "#b35836") 2) [V2 (x - 4) (y + 4), V2 (x + 4) (y - 4)]] | V2 x y <- anchors]

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
