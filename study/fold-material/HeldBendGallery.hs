-- | Inspect the grip-preserving reference without implying equilibrium.
-- HeldBend owns the geometric construction and its endpoint fit. Here every
-- final material edge is checked after roundoff-sized grip copies, and raw
-- fit residuals remain visible alongside the two diagnostic controls. All
-- projection and plotting stays in Haskell; the browser selects saved data.
module HeldBendGallery (writeHeldBends) where

import BendLocations
import BendLocationsGallery (plotSvg, rowJson)
import ClosedCrease
import Control.Monad (forM, forM_)
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
import HeldBend
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

constructions :: [(HeldConstruction, String, Text)]
constructions = [(CurveSamples, "samples", "Same smooth curve · sampled"), (FullLengthReference, "segments", "Same chord directions · full lengths"), (FullLengthHeld, "held", "Full lengths · fit the original grips")]

colours :: [(OuterMesh, Text)]
colours = [(Coarse, "#a67832"), (OuterOnly, "#b65845"), (RestOnly, "#3c8979"), (Fine, "#375d83")]

writeHeldBends :: FilePath -> IO ()
writeHeldBends destination = do
  reference <- checked commonCurve
  target <- checked gripTarget
  let output = destination </> "held-bend"
  createDirectoryIfMissing True output
  runs <- forM [(c, m) | c <- constructions, m <- outerMeshes] $ \((construction, ck, label), (choice, mk, meshLabel)) -> do
    probe <- checked (heldProbe choice construction)
    let paper = heldPaper probe
        mesh = closedMesh paper
        c = heldCurve probe
        pins = coupledPins (heldOriginal probe)
        stem = ck <> "-" <> mk
    measured <- checked (measureProbe paper)
    located <- checked (locateBends paper)
    gaps <- checked (auditPairContact (closedOwners paper) mesh)
    sheet <- checked (closedSurface paper)
    let pointMap = IM.fromList (zip [0 ..] (samples mesh))
        holdMove keep = maximum (0 : [norm (position p ^-^ old) | (i, old) <- IM.toList pins, Just p <- [IM.lookup i pointMap], keep (abs (materialU p))])
        exactHolds = all (\(i, old) -> fmap position (IM.lookup i pointMap) == Just old) (IM.toList pins)
        lengthPass = probeRelativeError measured <= 1e-5
        knownOrder = pairMinimum gaps >= 0
        angular = probeLowerEnergy measured + probeUpperEnergy measured + probeCreaseEnergy measured + probeControlEnergy measured
        referenceMove = maximum (0 : [norm (position p ^-^ curvePoint reference (abs (materialU p)) (materialV p)) | p <- samples mesh])
        report =
          object
            [ "id" .= stem,
              "construction" .= ck,
              "constructionLabel" .= label,
              "mesh" .= mk,
              "meshLabel" .= meshLabel,
              "columns" .= map (fromRational :: Rational -> Double) (outerColumns choice),
              "vertices" .= length (samples mesh),
              "triangles" .= length (triangles mesh),
              "components" .= componentCount mesh,
              "curve" .= curveJson c,
              "sharedCreaseVertices" .= closedRoot paper,
              "heldVertices" .= IM.keys pins,
              "innerHoldDisplacement" .= holdMove (<= heldStart),
              "outerHoldDisplacement" .= holdMove (== 0.5),
              "exactHolds" .= exactHolds,
              "rawEndpoint" .= coords (heldRawEndpoint probe),
              "rawGripResidual" .= norm (heldRawEndpoint probe ^-^ target),
              "pinAdjustment" .= heldPinAdjustment probe,
              "fitSteps" .= [object ["iteration" .= fitIteration s, "curve" .= curveJson (fitCurve s), "residual" .= fitResidual s] | s <- heldFitSteps probe],
              "lowerPassive" .= probeLowerEnergy measured,
              "upperPassive" .= probeUpperEnergy measured,
              "crease" .= probeCreaseEnergy measured,
              "imposed" .= probeControlEnergy measured,
              "predictedPassive" .= predictedPassive choice c,
              "curveEnergy" .= curveEnergy c,
              "commonReferenceEnergy" .= curveEnergy reference,
              "lengthSquares" .= probeLengthSquares measured,
              "lengthEnergy" .= (1e10 * probeLengthSquares measured / 2),
              "lineSearchObjective" .= (1e10 * probeLengthSquares measured + 2 * angular),
              "maxRelativeEdgeError" .= probeRelativeError measured,
              "lengthPasses" .= lengthPass,
              "maxCreaseError" .= probeCreaseError measured,
              "minimumExactGap" .= show (pairMinimum gaps),
              "maximumExactGap" .= show (pairMaximum gaps),
              "knownOrderPasses" .= knownOrder,
              "geometryPasses" .= (lengthPass && exactHolds && knownOrder && probeCreaseError measured <= 1e-5 && componentCount mesh == 1),
              "maxVertexDistanceToCommonCurve" .= referenceMove,
              "supports" .= supportJson choice c located
            ]
        detail = object ["summary" .= report, "springs" .= map rowJson located, "edges" .= [object ["vertices" .= [a, b], "rest" .= edgeRest e, "actual" .= edgeActual e] | e <- probeEdges measured, let (a, b) = edgeIds e], "transverseRates" .= [object ["panel" .= panel, "values" .= transverseRates (passive upper located)] | (upper, panel) <- [(False, "lower" :: Text), (True, "upper")]]]
    BL.writeFile (output </> stem <> ".json") (encode detail)
    BL.writeFile (output </> stem <> ".fold") (encode (FoldFile (Just 1.2) (Just "senbazuru prescribed held-bend study") Nothing (Just (label <> " · " <> meshLabel)) Nothing [] (materialFrame sheet) []))
    TIO.writeFile (output </> stem <> ".svg") (profileSvg reference target probe)
    pure (construction, choice, stem, probe, measured, located, report)
  forM_ [(c, ck, upper, panel) | (c, ck, _) <- constructions, (upper, panel) <- [(False, "lower"), (True, "upper")]] $ \(c, ck, upper, panel) -> do
    let selected = [(m, passive upper rows) | (mode, m, _, _, _, rows, _) <- runs, mode == c]
        traces f = [(colour, f rows) | (m, rows) <- selected, Just colour <- [lookup m colours]]
        end = heldStart + curveArcLength reference
        ideal = [V2 0 0, V2 heldStart 0, V2 end (curveEnergy reference), V2 0.5 (curveEnergy reference)]
        stem = ck <> "-" <> panel
    TIO.writeFile (output </> stem <> "-energy.svg") (plotSvg "Cumulative passive energy" 0.18 False (("#aaa294", ideal) : traces cumulativeEnergy) [])
    TIO.writeFile (output </> stem <> "-rates.svg") (plotSvg "Signed turn / material spacing" 4 True (traces (map (\(d, a, _, _) -> V2 d a) . transverseRates)) [])
  comparisons <- forM [(a, b) | a@(c, m, _, _, _, _, _) <- runs, b@(c', m', _, _, _, _, _) <- runs, c == c', (m, m') `elem` outerPairs] $ \((_, _, ka, fa, pa, _, _), (_, _, kb, fb, pb, _, _)) -> do
    movement <- checked (matching (closedMesh (heldPaper fa)) (closedMesh (heldPaper fb)))
    let change upper = let a = if upper then probeUpperEnergy pa else probeLowerEnergy pa; b = if upper then probeUpperEnergy pb else probeLowerEnergy pb in object ["delta" .= (b - a), "percent" .= (100 * (b - a) / a)]
    pure (object ["before" .= ka, "after" .= kb, "maxMatchingVertexDistance" .= movement, "lower" .= change False, "upper" .= change True])
  let document = object ["gallery" .= ("held-bend" :: Text), "commonCurve" .= curveJson reference, "gripTarget" .= coords target, "lengthCap" .= (1e-5 :: Double), "geometricFitTolerance" .= (1e-14 :: Double), "materialOptimizerRun" .= False, "contactCorrected" .= False, "continuousMotionChecked" .= False, "runs" .= [r | (_, _, _, _, _, _, r) <- runs], "comparisons" .= comparisons]
  BL.writeFile (output </> "checks.json") (encode document)
  template <- TIO.readFile "study/fold-material/held-bend.html"
  TIO.writeFile (destination </> "held-bend.html") (T.replace "/*HELD_BEND*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn "Wrote held-bend.html: twelve prescribed references, with geometric fits separate from material equilibrium."

passive :: Bool -> [LocatedBend] -> [LocatedBend]
passive upper = filter (\h -> measuredUpper (locatedMeasure h) == upper && hingeRole (measuredHinge (locatedMeasure h)) == PanelBend)

curveJson :: HeldCurve -> Value
curveJson c = object ["curvature" .= curveCurvature c, "arcLength" .= curveArcLength c, "arcEnd" .= (heldStart + curveArcLength c), "straightLength" .= (freeLength - curveArcLength c), "finalTurn" .= (curveCurvature c * curveArcLength c), "continuousEnergy" .= curveEnergy c]

coords :: V3 -> [Double]
coords (V3 x y z) = [x, y, z]

supportJson :: OuterMesh -> HeldCurve -> [LocatedBend] -> [Value]
supportJson mesh c rows =
  [ let left = (a + b) / 2
        right = (b + d) / 2
        turn x y = let V3 dx _ dz = curvePoint c y 0 ^-^ curvePoint c x 0 in atan2 dz dx
        expected = turn b d - turn a b
        cost = 0.1 * expected * expected / (right - left)
        integral = 0.1 * curveCurvature c ^ (2 :: Int) * max 0 (min right (heldStart + curveArcLength c) - max left heldStart)
        measured upper = let hs = [h | h <- passive upper rows, locatedDistance h == b, Just _ <- [locatedRate h]] in sum [measuredEnergy (locatedMeasure h) | h <- hs]
     in object ["distance" .= b, "interval" .= [left, right], "turnMagnitude" .= abs expected, "predictedCost" .= cost, "referenceIntegral" .= integral, "lower" .= measured False, "upper" .= measured True]
    | (a, b, d) <- zip3 columns (drop 1 columns) (drop 2 columns)
  ]
  where
    columns = map fromRational (outerColumns mesh)

profileSvg :: HeldCurve -> V3 -> HeldProbe -> Text
profileSvg reference target probe = renderSvg defaultPage {pageWidth = 560, pageHeight = 290, pageMargin = 25, pageBackground = Nothing, pageTitle = Just "Prescribed profile with original grips"} $ diagramWithExtent (Box (V2 (-0.025) (-0.035)) (V2 0.535 0.19)) shapes
  where
    side (V3 x _ z) = V2 x z
    points = [side (position p) | p <- samples (closedMesh (heldPaper probe)), materialU p >= 0, materialV p == -0.5]
    V2 tx tz = side target
    marks = [Polyline (solid (Colour "#70685b") 0.7) [V2 x (z - 0.002), V2 x (z + 0.002)] | V2 x z <- points]
    shapes = [Polyline (solid (Colour "#bbb6ab") 3) [side (curvePoint reference (fromIntegral i / 400) 0) | i <- [0 :: Int .. 200]], Polyline (solid (Colour "#397f88") 2) points, Polyline (Stroke (Colour "#b35836") 1 (Dash [5, 5])) points, Polyline (solid (Colour "#343d32") 3) [V2 0 0, V2 heldStart 0], Polyline (solid (Colour "#343d32") 2) [V2 (tx - 0.005) (tz - 0.005), V2 (tx + 0.005) (tz + 0.005)], Polyline (solid (Colour "#343d32") 2) [V2 (tx - 0.005) (tz + 0.005), V2 (tx + 0.005) (tz - 0.005)], Label (Colour "#70685b") 12 (V2 0 (-0.025)) "held inner strip", Label (Colour "#70685b") 12 (V2 0.37 (-0.025)) "× outer grip"] ++ marks

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
