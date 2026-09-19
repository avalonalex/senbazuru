-- | Compare sixteen prescribed references, not sixteen solved endpoints.
-- UnevenBend explains the arc/chord distinction and the energy formulas.
-- This module retains every material edge and spring measurement, checks
-- known-order contact, and draws shared-scale plots through Diagram. The
-- browser only selects existing assets and measured tables.
module UnevenBendGallery (writeUnevenBends) where

import BandBoundary (BoundaryRule (..))
import BendLocations
import BendLocationsGallery (plotSvg, rowJson)
import ClosedCrease
import Control.Monad (forM)
import CoupledCrease
import CoupledCreaseGallery (matching)
import CreasePairContact
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldMaterial (componentCount)
import OuterStrip
import PrescribedBend
import Senbazuru.Diagram
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types (FoldFile (..))
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Senbazuru.Render.Svg
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import UnequalCrease (UnequalControl (..))
import UnevenBend

references :: [(ReferenceBend, String, Text)]
references = [(CylinderBend, "cylinder", "Constant cylindrical bend"), (AfterHeldStrip, "held-start", "Bend starts at 1/8")]

constructions :: [(BendConstruction, String, Text)]
constructions = [(SurfaceSamples, "samples", "Exact surface samples"), (FullSegments, "segments", "Full-length straight edges")]

colours :: [(OuterMesh, Text)]
colours = [(Coarse, "#a67832"), (OuterOnly, "#b65845"), (RestOnly, "#3c8979"), (Fine, "#375d83")]

writeUnevenBends :: FilePath -> IO ()
writeUnevenBends destination = do
  let output = destination </> "uneven-bends"
  createDirectoryIfMissing True output
  runs <- forM [(r, c, m) | r <- references, c <- constructions, m <- outerMeshes] $ \((ref, rk, title), (construction, ck, constructionLabel), (choice, mk, meshLabel)) -> do
    fixture <- checked (unevenFixture choice ref construction)
    original <- checked (outerFixture choice OriginalTurns MatchedHolds)
    measured <- checked (measureProbe fixture)
    located <- checked (locateBends fixture)
    gaps <- checked (auditPairContact (closedOwners fixture) (closedMesh fixture))
    sheet <- checked (closedSurface fixture)
    let mesh = closedMesh fixture
        stem = rk <> "-" <> ck <> "-" <> mk
        supports = bendSupports choice ref
        rows = IM.fromList (zip [0 ..] (samples mesh))
        holdChange keep = maximum (0 : [norm (position p ^-^ old) | (i, old) <- IM.toList (coupledPins original), Just p <- [IM.lookup i rows], keep (abs (materialU p))])
        expected = sum (map supportEnergy supports)
        ideal = referenceEnergy ref
        uncovered = ideal - sum (map supportIntegral supports)
        averaging = sum [supportIntegral s - supportEnergy s | s <- supports]
        targetDistance = maximum (0 : [norm (position p ^-^ referencePoint ref (abs (materialU p)) (materialV p)) | p <- samples mesh])
        angular = probeLowerEnergy measured + probeUpperEnergy measured + probeControlEnergy measured + probeCreaseEnergy measured
        report =
          object
            [ "id" .= stem,
              "reference" .= rk,
              "referenceLabel" .= title,
              "construction" .= ck,
              "constructionLabel" .= constructionLabel,
              "mesh" .= mk,
              "meshLabel" .= meshLabel,
              "bendStart" .= bendStart ref,
              "columns" .= map (fromRational :: Rational -> Double) (outerColumns choice),
              "vertices" .= length (samples mesh),
              "triangles" .= length (triangles mesh),
              "components" .= componentCount mesh,
              "sharedCreaseVertices" .= closedRoot fixture,
              "originalHeldVertices" .= IM.keys (coupledPins original),
              "innerHoldDisplacement" .= holdChange (<= 1 / 8),
              "outerHoldDisplacement" .= holdChange (== 1 / 2),
              "maxVertexDistanceToReference" .= targetDistance,
              "lowerPassive" .= probeLowerEnergy measured,
              "upperPassive" .= probeUpperEnergy measured,
              "imposed" .= probeControlEnergy measured,
              "crease" .= probeCreaseEnergy measured,
              "expectedPassive" .= expected,
              "referenceEnergy" .= ideal,
              "uncoveredEnergy" .= uncovered,
              "averagingDeficit" .= averaging,
              "lengthSquares" .= probeLengthSquares measured,
              "predictedLengthSquares" .= predictedLengthSquares choice ref construction,
              "maxRelativeEdgeError" .= probeRelativeError measured,
              "meetsLengthCap" .= (probeRelativeError measured <= 1e-5),
              "lengthEnergy" .= (1e10 * probeLengthSquares measured / 2),
              "lineSearchObjective" .= (1e10 * probeLengthSquares measured + 2 * angular),
              "maxCreaseError" .= probeCreaseError measured,
              "minimumExactGap" .= show (pairMinimum gaps),
              "maximumExactGap" .= show (pairMaximum gaps),
              "knownOrderPasses" .= (pairMinimum gaps >= 0),
              "supports" .= map (supportJson located) supports,
              "regions" .= [object ["panel" .= panel, "values" .= [object ["region" .= show region, "energy" .= value] | (region, value) <- regionEnergy (passive upper located)]] | (upper, panel) <- [(False, "lower" :: Text), (True, "upper")]]
            ]
        detail = object ["summary" .= report, "springs" .= map rowJson located, "edges" .= [object ["vertices" .= [a, b], "rest" .= edgeRest e, "actual" .= edgeActual e] | e <- probeEdges measured, let (a, b) = edgeIds e], "transverseRates" .= [object ["panel" .= panel, "values" .= transverseRates (passive upper located)] | (upper, panel) <- [(False, "lower" :: Text), (True, "upper")]]]
    BL.writeFile (output </> stem <> ".json") (encode detail)
    BL.writeFile (output </> stem <> ".fold") (encode (FoldFile (Just 1.2) (Just "senbazuru prescribed uneven bend study") Nothing (Just (title <> " · " <> constructionLabel <> " · " <> meshLabel)) Nothing [] (materialFrame sheet) []))
    TIO.writeFile (output </> stem <> ".svg") (profileSvg ref fixture)
    pure (ref, construction, choice, stem, fixture, measured, located, report)
  plots <- forM [(ref, rk, construction, ck, upper, panel) | (ref, rk, _) <- references, (construction, ck, _) <- constructions, (upper, panel) <- [(False, "lower" :: Text), (True, "upper")]] $ \(ref, rk, construction, ck, upper, panel) -> do
    let selected = [(choice, passive upper rows) | (r, c, choice, _, _, _, rows, _) <- runs, r == ref, c == construction]
        stem = rk <> "-" <> ck <> "-" <> T.unpack panel
        traces f = [(colour, f rows) | (choice, rows) <- selected, Just colour <- [lookup choice colours]]
        energyLine = [V2 0 0, V2 (bendStart ref) 0, V2 0.5 (referenceEnergy ref)]
        rates rows = [V2 d mean | (d, mean, _, _) <- transverseRates rows]
    TIO.writeFile (output </> stem <> "-energy.svg") (plotSvg "Cumulative passive energy" 0.072 False (("#aaa294", energyLine) : traces cumulativeEnergy) [])
    TIO.writeFile (output </> stem <> "-rates.svg") (plotSvg "Mean signed turn / material spacing" curvature True (traces rates) [])
    pure (object ["id" .= stem])
  comparisons <- forM [(a, b) | a@(r, c, ma, _, _, _, _, _) <- runs, b@(r', c', mb, _, _, _, _, _) <- runs, r == r', c == c', (ma, mb) `elem` outerPairs] $ \((_, _, _, ka, fa, pa, _, _), (_, _, _, kb, fb, pb, _, _)) -> do
    movement <- checked (matching (closedMesh fa) (closedMesh fb))
    let change upper = let a = if upper then probeUpperEnergy pa else probeLowerEnergy pa; b = if upper then probeUpperEnergy pb else probeLowerEnergy pb in object ["before" .= a, "after" .= b, "delta" .= (b - a), "percent" .= (100 * (b - a) / a)]
    pure (object ["before" .= ka, "after" .= kb, "maxMatchingVertexDistance" .= movement, "lower" .= change False, "upper" .= change True])
  let document = object ["gallery" .= ("uneven-bends" :: Text), "curvature" .= curvature, "panelStiffness" .= (0.2 :: Double), "lengthWeight" .= (1e10 :: Double), "lengthCap" .= (1e-5 :: Double), "equilibriumSolved" .= False, "contactCorrected" .= False, "originalHoldsApplied" .= False, "continuousMotionChecked" .= False, "runs" .= [report | (_, _, _, _, _, _, _, report) <- runs], "plots" .= plots, "comparisons" .= comparisons]
  BL.writeFile (output </> "checks.json") (encode document)
  template <- TIO.readFile "study/fold-material/uneven-bends.html"
  TIO.writeFile (destination </> "uneven-bends.html") (T.replace "/*UNEVEN_BENDS*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn "Wrote uneven-bends.html: sixteen prescribed references, without optimization or contact repair."

passive :: Bool -> [LocatedBend] -> [LocatedBend]
passive upper = filter (\h -> measuredUpper (locatedMeasure h) == upper && hingeRole (measuredHinge (locatedMeasure h)) == PanelBend)

supportJson :: [LocatedBend] -> BendSupport -> Value
supportJson rows s = object ["distance" .= supportDistance s, "interval" .= supportInterval s, "activeLength" .= supportActiveLength s, "turnMagnitude" .= supportTurn s, "discreteEnergy" .= supportEnergy s, "referenceIntegral" .= supportIntegral s, "averagingDeficit" .= (supportIntegral s - supportEnergy s), "lower" .= measured False, "upper" .= measured True]
  where
    measured upper =
      let selected = [h | h <- passive upper rows, locatedDistance h == supportDistance s, Just _ <- [locatedRate h]]
          weight h = norm (locatedTo h ^-^ locatedFrom h)
          totalWidth = sum (map weight selected)
       in object ["energy" .= sum (map (measuredEnergy . locatedMeasure) selected), "turnMagnitude" .= (if totalWidth == 0 then Nothing else Just (sum [weight h * abs (measuredAngle (locatedMeasure h)) | h <- selected] / totalWidth))]

profileSvg :: ReferenceBend -> ClosedCrease -> Text
profileSvg ref fixture = renderSvg defaultPage {pageWidth = 560, pageHeight = 290, pageMargin = 25, pageBackground = Nothing, pageTitle = Just "Prescribed profile and smooth reference"} $ diagramWithExtent (Box (V2 (-0.025) (-0.035)) (V2 0.535 0.19)) shapes
  where
    side (V3 x _ z) = V2 x z
    points = [side (position p) | p <- samples (closedMesh fixture), materialU p >= 0, materialV p == -0.5]
    shapes = [Polyline (solid (Colour "#bbb6ab") 3) [side (referencePoint ref (fromIntegral i / 400) 0) | i <- [0 :: Int .. 200]], Polyline (solid (Colour "#397f88") 2.5) points, Polyline (Stroke (Colour "#b35836") 1.5 (Dash [5, 5])) points, Label (Colour "#70685b") 12 (V2 0 (-0.023)) "crease", Label (Colour "#70685b") 12 (V2 0.40 (-0.023)) "outer edge"]

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
