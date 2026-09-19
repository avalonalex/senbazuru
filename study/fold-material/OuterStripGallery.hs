-- | An opt-in four-mesh experiment, using the existing material solver and
-- independent endpoint checks. Both uniform controls are re-solved so their
-- saved histories can be compared with the earlier length study. A refusal
-- retains its starting guess; a converged crossing remains diagnostic.
-- Numerical stages are inspectable, but are not a continuous folding route.
module OuterStripGallery (writeOuterStrip) where

import BandBoundary
import BendLocations
import BendLocationsGallery (plotPoint, plotSvg, regionJson, rowJson)
import ClosedCrease
import ContactQuadratic
import Control.Exception (evaluate)
import Control.Monad (forM, forM_)
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
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldRelaxation
import OuterStrip
import PrescribedBend
import Senbazuru.Diagram
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..))
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
import UnequalCreaseGallery (bendReportWith, gapSvg, mapSvg, profileSvg, sampleLocations, sampleReport)

data Run = Run
  { runId :: String,
    runControl :: String,
    runChoice :: OuterMesh,
    runRule :: BoundaryRule,
    runPassed :: Bool,
    runEndpoint :: Maybe MaterialMesh,
    runRows :: [LocatedBend],
    runReport :: Value,
    runModels :: [Value]
  }

rules :: [(BoundaryRule, String)]
rules = [(OriginalTurns, "original"), (FractionalTurns, "fractional")]

controls :: [(UnequalControl, String, Text)]
controls = [(MatchedHolds, "matched", "Matched holds"), (UpperBand, "band", "Upper band"), (BandWithoutContact, "band-off", "Band · contact off")]

weights :: [Double]
weights = [1e2, 1e4, 1e6, 1e8, 1e9, 1e10]

writeOuterStrip :: FilePath -> IO ()
writeOuterStrip destination = do
  let output = destination </> "outer-strip"
  createDirectoryIfMissing True output
  runs <- sequence [solveRun output choice meshKey meshLabel rule ruleKey control key title | (choice, meshKey, meshLabel) <- outerMeshes, (rule, ruleKey) <- rules, (control, key, title) <- controls]
  comparisons <- forM [(a, b) | a <- runs, b <- runs, runControl a == runControl b, runRule a == runRule b, (runChoice a, runChoice b) `elem` outerPairs] $ \(a, b) -> do
    difference <- checked (traverse (uncurry matching) ((,) <$> runEndpoint a <*> runEndpoint b))
    pure (object ["from" .= runId a, "to" .= runId b, "eligible" .= (runPassed a && runPassed b), "maxMatchingPositionChange" .= difference])
  forM_ [(rule, ruleKey, key, upper, panel) | (rule, ruleKey) <- rules, (_, key, _) <- controls, (upper, panel) <- [(False, "lower"), (True, "upper")]] $ \(rule, ruleKey, key, upper, panel) -> do
    let rates r = transverseRates [h | h <- runRows r, hingeRole (measuredHinge (locatedMeasure h)) == PanelBend, measuredUpper (locatedMeasure h) == upper]
        selected = [r | r <- runs, runRule r == rule, runControl r == key]
        top = maximum (1e-12 : [abs x | r <- selected, (_, mean, lo, hi) <- rates r, x <- [mean, lo, hi]])
        curves = [(colour (runChoice r), [V2 x mean | (x, mean, _, _) <- rates r]) | r <- selected]
        bars = [Polyline (solid (Colour (colour (runChoice r))) 0.7) [plotPoint top x lo, plotPoint top x hi] | r <- selected, (x, _, lo, hi) <- rates r]
    TIO.writeFile (output </> key ++ "-" ++ ruleKey ++ "-" ++ panel ++ "-turns.svg") (plotSvg "Signed turn / material spacing" top True curves bars)
  let document = object ["gallery" .= ("outer-strip" :: Text), "runs" .= map runReport runs, "comparisons" .= comparisons]
  BL.writeFile (output </> "checks.json") (encode document)
  BL.writeFile (output </> "models.json") (encode (concatMap runModels runs))
  viewer <- TIO.readFile "study/gltf/viewer.html"
  let compact = "header{padding:16px}header small,header h1,header p{display:none}#view{height:450px;min-height:450px}footer{padding:12px 16px}</style>"
  TIO.writeFile (output </> "index.html") (T.replace "</style>" compact (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer))
  template <- TIO.readFile "study/fold-material/outer-strip.html"
  TIO.writeFile (destination </> "outer-strip.html") (T.replace "/*OUTER_STRIP*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn "Wrote outer-strip.html and the four-mesh study."
  where
    colour Coarse = "#817567"
    colour OuterOnly = "#b36d26"
    colour RestOnly = "#8b5077"
    colour Fine = "#236e75"

solveRun :: FilePath -> OuterMesh -> String -> Text -> BoundaryRule -> String -> UnequalControl -> String -> Text -> IO Run
solveRun output choice meshKey meshLabel rule ruleKey control key title = do
  fixture <- checked (outerFixture choice rule control)
  preference <- checked bandPreference
  let stem = key ++ "-" ++ meshKey ++ "-" ++ ruleKey
      reference = coupledReference fixture
      settings = Settings 40 1e-5
      mode = unequalContactMode control
      attempt = solveCoupledMethod ProgressiveContactExchange weights mode settings fixture
  putStrLn ("Solving " ++ stem)
  hFlush stdout
  start <- getCPUTime
  _ <- evaluate (case attempt of Left _ -> 0; Right r -> maxLengthError (inequalityMesh r) + if inequalityConverged r then 1 else 0)
  finish <- getCPUTime
  let result = either (const Nothing) Just attempt
      refusal = either (Just . explain) (const Nothing) attempt
      candidates = ("before", "Original guess", coupledSeed fixture) : maybe [] (\r -> [("repair", "Numerical starting guess", repairedMesh (inequalityInitial r)), ("after", "Solver endpoint", inequalityMesh r)]) result
  audits <- mapM (\(_, _, mesh) -> checked (auditPairContact (closedOwners reference) mesh)) candidates
  let gapScale = maximum (1e-8 : [fromRational (max (abs (pairMinimum a)) (abs (pairMaximum a))) | a <- audits])
  stages <- forM (zip candidates audits) $ \((stage, label, mesh), audit) -> do
    (measurement, valid) <- measure fixture mesh
    bending <- checked (bendBreakdown fixture mesh)
    boundaries <- if control == MatchedHolds then pure Nothing else Just <$> checked (outerBoundaryMeasures choice reference {closedMesh = mesh})
    sampled <- checked (samplePairGaps (closedOwners reference) mesh sampleLocations)
    located <- checked (locateBends reference {closedMesh = mesh})
    sheet <- checked (coupledSurface fixture mesh)
    let name = stem ++ "-" ++ stage
        caption = title <> " · " <> meshLabel <> " · " <> T.pack ruleKey <> " · " <> label
        interval u = snd <$> outerInterval choice (abs u)
        report =
          object
            [ "measurement" .= measurement,
              "geometryPassed" .= valid,
              "bending" .= bendReportWith interval bending boundaries,
              "bandSupports" .= fmap (map supportJson) boundaries,
              "gapSamples" .= sampleReport sampled,
              "springs" .= map rowJson located,
              "regions" .= regionJson located,
              "transverseRates" .= [object ["panel" .= panel, "values" .= transverseRates [h | h <- located, hingeRole (measuredHinge (locatedMeasure h)) == PanelBend, measuredUpper (locatedMeasure h) == upper]] | (upper, panel) <- [(False, "lower" :: Text), (True, "upper")]]
            ]
    TIO.writeFile (output </> name ++ "-profile.svg") (profileSvg mesh)
    TIO.writeFile (output </> name ++ "-gaps.svg") (gapSvg gapScale audit)
    TIO.writeFile (output </> name ++ "-map.svg") (mapSvg sampled)
    BL.writeFile (output </> name ++ ".fold") (encode (FoldFile (Just 1.2) (Just "senbazuru outer-strip study") Nothing (Just caption) Nothing [] (materialFrame sheet) []))
    checked (renderSurfaceGlb defaultBudget CompletePaper (Just caption) sheet) >>= BS.writeFile (output </> name ++ ".glb")
    pure (stage, label, valid, located, report, object ["title" .= caption, "path" .= (name ++ ".glb")])
  TIO.writeFile (output </> meshKey ++ "-material.svg") (materialSvg choice)
  let passed = mode == EnforcePairOrder && maybe False inequalityConverged result && any (\(stage, _, valid, _, _, _) -> stage == "after" && valid) stages
      endpointRows = concat [rows | (stage, _, _, rows, _, _) <- stages, stage == "after"]
      report =
        object
          [ "id" .= stem,
            "control" .= key,
            "title" .= title,
            "meshKey" .= meshKey,
            "meshLabel" .= meshLabel,
            "rule" .= ruleKey,
            "columns" .= map (fromRational :: Rational -> Double) (outerColumns choice),
            "triangles" .= length (triangles (coupledSeed fixture)),
            "vertices" .= length (samples (coupledSeed fixture)),
            "sharedCreaseVertices" .= closedRoot reference,
            "heldVertices" .= IM.keys (coupledPins fixture),
            "lengthWeights" .= weights,
            "contactMethod" .= show ProgressiveContactExchange,
            "iterationLimitPerStage" .= iterationLimit settings,
            "lengthTolerance" .= lengthTolerance settings,
            "band" .= object ["bounds" .= bandBounds preference, "desiredTurnRadians" .= bandDesiredTurn preference, "bendingWeight" .= bandBendingWeight preference, "flatReferenceEnergy" .= bandReferenceEnergy preference],
            "passed" .= passed,
            "contactEnabled" .= (mode == EnforcePairOrder),
            "refusal" .= refusal,
            "solve" .= fmap resultReport result,
            "solveCpuSeconds" .= (fromIntegral (finish - start) / 1e12 :: Double),
            "states" .= object [Key.fromString stage .= value | (stage, _, _, _, value, _) <- stages],
            "stages" .= [object ["id" .= stage, "label" .= label] | (stage, label, _, _, _, _) <- stages],
            "continuousMotionChecked" .= False
          ]
  BL.writeFile (output </> stem ++ "-checks.json") (encode report)
  putStrLn (stem ++ ": endpoint passed " ++ show passed ++ maybe "" (\reason -> "; " ++ T.unpack reason) refusal)
  hFlush stdout
  pure (Run stem key choice rule passed (inequalityMesh <$> result) endpointRows report [v | (_, _, _, _, _, v) <- stages])

supportJson :: BoundaryMeasure -> Value
supportJson r =
  object
    [ "distance" .= boundaryDistance r,
      "widthRange" .= boundaryWidthRange r,
      "coveredInterval" .= boundaryInterval r,
      "fullSpan" .= boundaryFullSpan r,
      "fraction" .= boundaryFraction r,
      "angle" .= boundaryAngle r,
      "originalTarget" .= hingeRest (boundaryOriginal r),
      "originalStiffness" .= hingeStiffness (boundaryOriginal r),
      "fractionalTarget" .= hingeRest (boundaryCandidate r),
      "fractionalStiffness" .= hingeStiffness (boundaryCandidate r),
      "originalEnergy" .= boundaryOldEnergy r,
      "fractionalEnergy" .= boundaryNewEnergy r
    ]

materialSvg :: OuterMesh -> Text
materialSvg choice = renderSvg defaultPage {pageWidth = 560, pageHeight = 180, pageMargin = 20, pageTitle = Just "Columns on one unfolded panel"} $ diagramWithExtent (Box (V2 (-0.01) (-0.01)) (V2 0.51 0.14)) shapes
  where
    shapes =
      [Fill (Colour "#e2e9df") [[V2 0 0, V2 0.125 0, V2 0.125 0.1, V2 0 0.1]], Fill (Colour "#f5e1bd") [[V2 0.4375 0, V2 0.5 0, V2 0.5 0.1, V2 0.4375 0.1]]]
        ++ [Polyline (solid (Colour "#55534d") 0.8) [V2 (fromRational u) 0, V2 (fromRational u) 0.1] | u <- outerColumns choice]
        ++ [Label (Colour "#55534d") 11 (V2 x 0.12) label | (x, label) <- [(0, "crease"), (0.125, "1/8"), (0.4375, "7/16"), (0.5, "1/2")]]

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
