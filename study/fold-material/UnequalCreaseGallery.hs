-- | Compare separated layers and contact-mediated response on one small sheet.
-- A contact-disabled counterfactual has the same holds and springs; it remains
-- a diagnostic even if its material solve converges. Projected material rows
-- show the shape, while magnified gap marks cover every overlap corner across
-- the width. They are not a folding path or a contact-area measurement.
module UnequalCreaseGallery (writeUnequalCrease, writeUnequalRefinement, writeFineCrease, writeCombinedRefinement, writeBandRefinement, writeCombinedBandRefinement, writeBandRefinement8, writeBandContact, writeBandLength) where

import ClosedCrease
import ContactQuadratic
import Control.Exception (evaluate)
import Control.Monad (forM, when)
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
import Data.List (nub, sortOn)
import Data.Ord (Down (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldMaterial (meshEdges)
import FoldRelaxation
import Senbazuru.Diagram
import Senbazuru.Explain (Explain (..), num, tshow)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
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

-- | A comparison can change a mesh or a numerical policy, but names both.
-- Old commands retain their original solver and output names.
data GalleryCase = GalleryCase
  { caseLength :: Int,
    caseWidth :: Int,
    caseKey :: String,
    caseLabel :: Text,
    caseSuffix :: String,
    caseWeights :: [Double],
    caseMethod :: ContactMethod
  }
  deriving stock (Eq)

meshCase :: (Int, Int) -> GalleryCase
meshCase (n, w) = GalleryCase n w (meshKey n w) (T.pack (show (32 * n * w)) <> " triangles · length " <> T.pack (show n) <> " × width " <> T.pack (show w)) (show n ++ if w == 1 then "" else "-w" ++ show w) [1e2, 1e4, 1e6, 1e8] OriginalWorkingSet

writeUnequalCrease :: FilePath -> IO ()
writeUnequalCrease = writeGallery "unequal-crease" (map meshCase [(1, 1), (2, 1)]) controls

-- | Three lengths and an independent doubling across the width.
writeUnequalRefinement :: FilePath -> IO ()
writeUnequalRefinement = writeGallery "unequal-refinement" (map meshCase refinementMeshes) comparisonControls

-- | Repeat the same grid with one stronger policy on EVERY mesh. Changing
-- only the finest solve would confound numerical policy and mesh resolution.
-- The original grid stays available so its measurements remain reproducible.
writeCombinedRefinement :: FilePath -> IO ()
writeCombinedRefinement =
  writeGallery
    "combined-refinement"
    combinedMeshes
    comparisonControls

writeBandRefinement :: FilePath -> IO ()
writeBandRefinement = writeGallery "band-refinement" combinedMeshes bandControls

-- | Apply both isolated numerical repairs to every mesh and loading control.
-- Keep the old band command reproducible: changing only its failed cases
-- would mix different objectives and contact policies in one refinement grid.
writeCombinedBandRefinement :: FilePath -> IO ()
writeCombinedBandRefinement =
  writeGallery
    "combined-band-refinement"
    (map bandRefinementCase (refinementMeshes ++ [(4, 2)]))
    bandControls

-- | One more length doubling, with width and numerical policy held fixed.
-- Re-solve the two references so both successive changes are inspectable in
-- one gallery; retain failed endpoints rather than tuning the finest case.
writeBandRefinement8 :: FilePath -> IO ()
writeBandRefinement8 =
  writeGallery
    "band-refinement-8"
    (map bandRefinementCase [(2, 1), (4, 1), (8, 1)])
    [c | c@(key, _, _) <- bandControls, key `elem` ["matched", "band", "band-off"]]

bandRefinementCase :: (Int, Int) -> GalleryCase
bandRefinementCase size = (meshCase size) {caseWeights = [1e2, 1e4, 1e6, 1e8, 1e9, 1e10], caseMethod = ProgressiveContactExchange}

-- | Replay the two failed band endpoints and compare complete solves, changing
-- only the contact exchange policy. Fine contact-off length enforcement is a
-- separate experiment; this keeps the original length schedule on every run.
writeBandContact :: FilePath -> IO ()
writeBandContact = writeGallery "band-contact" choices bandControls
  where
    choices =
      [ base {caseKey = caseKey base ++ "-" ++ key, caseSuffix = caseSuffix base ++ "-" ++ key, caseLabel = caseLabel base <> " · " <> label, caseMethod = method}
        | base <- combinedMeshes,
          caseLength base == 2,
          (key, label, method) <- [("single", "Single exchange", ExchangeNearDependent), ("progressive", "Progressive exchanges", ProgressiveContactExchange)]
      ]

-- | Separate a finite length penalty from insufficient work. Replaying the
-- old contact-off endpoints at the SAME weight is the extra-work control;
-- the complete comparison changes only the final length-weight schedule.
-- A settled crossing sheet remains diagnostic, regardless of its lengths.
writeBandLength :: FilePath -> IO ()
writeBandLength = writeGallery "band-length" choices [c | c@(key, _, _) <- bandControls, key `elem` ["matched", "band-off"]]
  where
    choices =
      [ base {caseKey = caseKey base ++ "-" ++ key, caseSuffix = caseSuffix base ++ "-" ++ key, caseLabel = caseLabel base <> " · " <> label, caseWeights = weights}
        | base <- combinedMeshes,
          caseLength base == 4,
          (key, label, weights) <- [("baseline", "Through 1e9", caseWeights base), ("stronger", "Extra 1e10 stage", caseWeights base ++ [1e10])]
      ]

bandControls :: [(String, Text, UnequalControl)]
bandControls = comparisonControls ++ [("band", "Distributed bend preference", UpperBand), ("band-off", "Distributed preference · contact off", BandWithoutContact)]

combinedMeshes :: [GalleryCase]
combinedMeshes = [(meshCase size) {caseWeights = [1e2, 1e4, 1e6, 1e8, 1e9], caseMethod = ExchangeNearDependent} | size <- refinementMeshes ++ [(4, 2)]]

refinementMeshes :: [(Int, Int)]
refinementMeshes = [(1, 1), (2, 1), (4, 1), (1, 2), (2, 2)]

writeFineCrease :: FilePath -> IO ()
writeFineCrease =
  writeGallery
    "fine-crease"
    [ (meshCase (4, 1)) {caseKey = key, caseLabel = label, caseSuffix = "4-" ++ key, caseWeights = weights, caseMethod = method}
      | (key, label, weights, method) <-
          [ ("baseline", "Original schedule and contacts", [1e2, 1e4, 1e6, 1e8], OriginalWorkingSet),
            ("penalty", "Extra length stage only", [1e2, 1e4, 1e6, 1e8, 1e9], OriginalWorkingSet),
            ("contact", "Contact exchange only", [1e2, 1e4, 1e6, 1e8], ExchangeNearDependent),
            ("exchange", "Extra length stage + contact exchange", [1e2, 1e4, 1e6, 1e8, 1e9], ExchangeNearDependent)
          ]
    ]
    comparisonControls

comparisonControls :: [(String, Text, UnequalControl)]
comparisonControls = [c | c@(key, _, _) <- controls, key `elem` ["matched", "curl", "off"]]

writeGallery :: String -> [GalleryCase] -> [(String, Text, UnequalControl)] -> FilePath -> IO ()
writeGallery gallery resolutions selected destination = do
  let output = destination </> gallery
  createDirectoryIfMissing True output
  runs <- forM [(choice, c) | choice <- resolutions, c <- selected] $ \(choice, (key, title, control)) -> do
    let n = caseLength choice; w = caseWidth choice
    fixture <- checked (unequalCreaseWithWidth n w control)
    band <- if control `elem` [UpperBand, BandWithoutContact] then Just <$> checked bandPreference else pure Nothing
    let stem = key ++ "-" ++ caseSuffix choice
        reference = coupledReference fixture
        mode = unequalContactMode control
        settings = Settings 40 1e-5
        attempt = solveCoupledMethod (caseMethod choice) (caseWeights choice) mode settings fixture
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
      bending <- checked (bendBreakdown fixture mesh)
      sampled <- checked (samplePairGaps (closedOwners reference) mesh sampleLocations)
      sheet <- checked (coupledSurface fixture mesh)
      let name = stem ++ "-" ++ stage
          detail = case gallery of
            "fine-crease" -> " · " <> caseLabel choice
            _ | gallery `elem` ["combined-refinement", "band-refinement", "combined-band-refinement", "band-refinement-8"] -> " · length " <> T.pack (show n) <> " × width " <> T.pack (show w) <> " · combined solver"
            _ -> ""
          description = if gallery `elem` ["band-contact", "band-length"] then caseLabel choice else T.pack (show (32 * n * w)) <> " triangles" <> detail
          caption = title <> " · " <> label <> " · " <> description
      TIO.writeFile (output </> name ++ "-map.svg") (mapSvg sampled)
      TIO.writeFile (output </> name ++ "-profile.svg") (profileSvg mesh)
      TIO.writeFile (output </> name ++ "-gaps.svg") (gapSvg gapScale audit)
      BL.writeFile (output </> name ++ ".fold") (encode (FoldFile (Just 1.2) (Just "senbazuru unequal crease") Nothing (Just caption) Nothing [] (materialFrame sheet) []))
      checked (renderSurfaceGlb defaultBudget CompletePaper (Just caption) sheet) >>= BS.writeFile (output </> name ++ ".glb")
      pure (stage, label, measurement, valid, sampleReport sampled, bendReport (n <$ band) bending, object ["title" .= caption, "path" .= (name ++ ".glb")])
    when (gallery == "fine-crease" && caseKey choice == "baseline" && control == UpperCurl) $ case result of
      Nothing -> pure ()
      Just r -> do
        replay <- replayContact 1e8 [OriginalWorkingSet, ExchangeNearDependent] fixture (inequalityMesh r)
        BL.writeFile (output </> "contact-step.json") (encode replay)
    replay <-
      if gallery == "band-contact" && caseMethod choice == ExchangeNearDependent && control == UpperBand
        then case result of
          Nothing -> pure Nothing
          Just r -> do
            evidence <- replayContact 1e9 [OriginalWorkingSet, ExchangeNearDependent, ProgressiveContactExchange] fixture (inequalityMesh r)
            BL.writeFile (output </> stem ++ "-contact-step.json") (encode evidence)
            pure (Just evidence)
        else pure Nothing
    lengthDiagnostics <-
      if gallery == "band-length"
        then Just . object <$> mapM (\(stage, _, mesh) -> (Key.fromString stage .=) <$> lengthReport mesh) candidates
        else pure Nothing
    lengthReplay <-
      if gallery == "band-length" && caseWeights choice == caseWeights (meshCase (n, w)) ++ [1e9] && control == BandWithoutContact
        then case result of
          Nothing -> pure Nothing
          Just r -> do
            evidence <- replayLength fixture (inequalityMesh r)
            BL.writeFile (output </> stem ++ "-length-replay.json") (encode evidence)
            pure (Just evidence)
        else pure Nothing
    let passed = mode == EnforcePairOrder && maybe False inequalityConverged result && any (\(s, _, _, valid, _, _, _) -> s == "after" && valid) stages
        report =
          object
            [ "id" .= stem,
              "control" .= key,
              "title" .= title,
              "subdivision" .= n,
              "widthSubdivision" .= w,
              "meshKey" .= caseKey choice,
              "choiceLabel" .= caseLabel choice,
              "lengthWeights" .= caseWeights choice,
              "contactMethod" .= show (caseMethod choice),
              "iterationLimitPerStage" .= iterationLimit settings,
              "lengthTolerance" .= lengthTolerance settings,
              "triangles" .= length (triangles (coupledSeed fixture)),
              "vertices" .= length (samples (coupledSeed fixture)),
              "heldVertices" .= IM.keys (coupledPins fixture),
              "sharedCreaseVertices" .= closedRoot reference,
              "contactReplay" .= replay,
              "lengthDiagnostics" .= lengthDiagnostics,
              "lengthReplay" .= lengthReplay,
              "band" .= fmap (\b -> object ["bounds" .= bandBounds b, "desiredTurnRadians" .= bandDesiredTurn b, "bendingWeight" .= bandBendingWeight b, "flatReferenceEnergy" .= bandReferenceEnergy b]) band,
              "bendControls" .= [object ["vertices" .= hingeVertices h, "restRadians" .= hingeRest h, "stiffness" .= hingeStiffness h] | h <- closedHinges reference, hingeRole h == BendControl],
              "contactEnabled" .= (mode == EnforcePairOrder),
              "passed" .= passed,
              "refusal" .= refusal,
              "solve" .= fmap resultReport result,
              "solveCpuSeconds" .= (fromIntegral (finish - start) / 1e12 :: Double),
              "gapPlotScale" .= gapScale,
              "measurements" .= object [Key.fromString s .= v | (s, _, v, _, _, _, _) <- stages],
              "bending" .= object [Key.fromString s .= v | (s, _, _, _, _, v, _) <- stages],
              "gapSamples" .= object [Key.fromString s .= v | (s, _, _, _, v, _, _) <- stages],
              "stages" .= [object ["id" .= s, "label" .= label] | (s, label, _, _, _, _, _) <- stages],
              "continuousMotionChecked" .= False
            ]
    putStrLn (stem ++ ": endpoint passed " ++ show passed ++ maybe "" (\reason -> "; " ++ T.unpack reason) refusal)
    hFlush stdout
    pure (key, choice, report, [v | (_, _, _, _, _, _, v) <- stages], fmap inequalityMesh result)
  refinement <- forM [(key, na, nb, a, b) | (key, na, _, _, Just a) <- runs, (other, nb, _, _, Just b) <- runs, key == other, comparable na nb] $ \(key, na, nb, a, b) -> do
    difference <- checked (matching a b)
    pure (object ["control" .= key, "fromMesh" .= caseKey na, "toMesh" .= caseKey nb, "maxMatchingPositionChange" .= difference])
  responses <- forM [(key, n, a, b) | ("matched", n, _, _, Just a) <- runs, (key, k, _, _, Just b) <- runs, n == k] $ \(key, n, a, b) -> response key n a b
  contactEffect <- forM [(on, n, a, b) | (off, on) <- [("off", "curl"), ("band-off", "band")], (ca, n, _, _, Just a) <- runs, ca == off, (cb, k, _, _, Just b) <- runs, cb == on, n == k] $ \(on, n, a, b) -> response on n a b
  let document = object ["gallery" .= gallery, "runs" .= [r | (_, _, r, _, _) <- runs], "refinement" .= refinement, "responses" .= responses, "contactEffect" .= contactEffect]
  BL.writeFile (output </> "checks.json") (encode document)
  BL.writeFile (output </> "models.json") (encode (concat [ms | (_, _, _, ms, _) <- runs]))
  viewer <- TIO.readFile "study/gltf/viewer.html"
  let compact = "header{padding:16px}header small,header h1,header p{display:none}#view{height:450px;min-height:450px}footer{padding:12px 16px}</style>"
  TIO.writeFile (output </> "index.html") (T.replace "</style>" compact (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer))
  template <- TIO.readFile "study/fold-material/unequal-crease.html"
  TIO.writeFile (destination </> gallery ++ ".html") (T.replace "/*UNEQUAL_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn ("Wrote " ++ gallery ++ ".html and measurements to " ++ destination)
  where
    comparable a b
      | gallery == "band-length" = caseWidth a == caseWidth b && caseWeights b == caseWeights a ++ [1e10]
      | gallery == "band-contact" = caseWidth a == caseWidth b && caseMethod a == ExchangeNearDependent && caseMethod b == ProgressiveContactExchange
      | gallery == "fine-crease" = caseKey a == "baseline" && caseKey b /= "baseline"
      | otherwise = (caseLength b == 2 * caseLength a && caseWidth b == caseWidth a) || (caseLength b == caseLength a && caseWidth b == 2 * caseWidth a)

bendReport :: Maybe Int -> BendBreakdown -> Value
bendReport subdivision b =
  object
    [ "lowerPassiveEnergy" .= lowerPassiveEnergy b,
      "upperPassiveEnergy" .= upperPassiveEnergy b,
      "imposedEnergy" .= imposedBendEnergy b,
      "controlTurns"
        .= [ object
               [ "vertices" .= turnVertices t,
                 "materialU" .= turnU t,
                 "materialVRange" .= turnVRange t,
                 "materialInterval" .= (subdivision >>= (\n -> bandInterval n (round (abs (turnU t) * fromIntegral (8 * n))))),
                 "actualRadians" .= turnActual t,
                 "preferredRadians" .= turnPreferred t,
                 "passiveStiffness" .= turnPassiveStiffness t,
                 "imposedStiffness" .= turnImposedStiffness t,
                 "passiveEnergy" .= turnPassiveEnergy t,
                 "imposedEnergy" .= turnImposedEnergy t
               ]
             | t <- controlTurns b
           ]
    ]

response :: String -> GalleryCase -> MaterialMesh -> MaterialMesh -> IO Value
response key choice a b = do
  (lower, upper) <- checked (panelChanges a b)
  pure
    ( object
        [ "control" .= key,
          "subdivision" .= caseLength choice,
          "widthSubdivision" .= caseWidth choice,
          "meshKey" .= caseKey choice,
          "lowerChange" .= lower,
          "upperChange" .= upper
        ]
    )

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

-- Cell centres avoid counting held boundaries as contact area. Locations and
-- threshold are identical for every mesh; counts are samples, not exact areas.
sampleLocations :: [(Rational, Rational)]
sampleLocations = [(fromIntegral (2 * i + 1) / 160, fromIntegral (2 * j + 1) / 80 - 1 / 2) | j <- [0 :: Int .. 39], i <- [0 :: Int .. 39]]

meshKey :: Int -> Int -> String
meshKey n w = show n ++ "x" ++ show w

sampleReport :: [Maybe Rational] -> Value
sampleReport gaps = object ["threshold" .= (1e-7 :: Double), "locations" .= [[fromRational x :: Double, fromRational y] | (x, y) <- sampleLocations], "gaps" .= map (fmap (fromRational :: Rational -> Double)) gaps, "outside" .= length [() | Nothing <- gaps], "crossing" .= length [() | Just g <- gaps, g < 0], "nearContact" .= length [() | Just g <- gaps, g >= 0, g <= 1 / 10000000], "separated" .= length [() | Just g <- gaps, g > 1 / 10000000]]

mapSvg :: [Maybe Rational] -> Text
mapSvg gaps =
  drawing
    "Sampled gap map in projected x/y"
    (Box (V2 0 (-0.5)) (V2 0.5 0.5))
    [Fill (Colour colour) [cell x y | ((rx, ry), gap) <- zip sampleLocations gaps, colourFor gap == colour, let x = fromRational rx; y = fromRational ry] | colour <- ["#ddd7cd", "#b6412b", "#386d69", "#d3a052"]]
  where
    cell x y = [V2 (x - 0.00625) (y - 0.0125), V2 (x + 0.00625) (y - 0.0125), V2 (x + 0.00625) (y + 0.0125), V2 (x - 0.00625) (y + 0.0125)]
    colourFor Nothing = "#ddd7cd"
    colourFor (Just g)
      | g < 0 = "#b6412b"
      | g <= 1 / 10000000 = "#386d69"
      | otherwise = "#d3a052"

-- The same stored endpoint supplies both linearized problems. Saving the rows
-- makes the numerical failure independently inspectable without a new route.
replayContact :: Double -> [ContactMethod] -> CoupledFixture -> MaterialMesh -> IO Value
replayContact weight methods fixture mesh = do
  (material, gaps) <- checked (coupledRows EnforcePairOrder fixture weight mesh)
  let ids = [i | (i, _) <- zip [0 ..] (samples mesh), IM.notMember i (coupledPins fixture)]
      row (coefficients, residual) = object ["residual" .= residual, "coefficients" .= [(i, [x, y, z]) | (i, V3 x y z) <- IM.toList coefficients]]
      report method = do
        (step, r, details) <- checked (constrainedStepDetailed method 2000 1e-3 ids material gaps)
        let contacts = [object ["constraint" .= contactConstraint c, "sourceRows" .= contactSources c, "selected" .= contactSelected c, "gap" .= contactGap c, "normalizedMultiplier" .= contactNormalizedMultiplier c, "responseScale" .= contactResponseScale c] | c <- quadraticContacts details]
            exchanges = [object ["removed" .= exchangeRemoved e, "inserted" .= exchangeInserted e, "squaredViolationBefore" .= exchangeViolationBefore e, "squaredViolationAfter" .= exchangeViolationAfter e] | e <- quadraticExchanges details]
        pure (object ["method" .= show method, "converged" .= quadraticConverged r, "iterations" .= quadraticIterations r, "violation" .= quadraticViolation r, "complementarity" .= quadraticComplementarity r, "balance" .= quadraticBalance r, "activeConstraints" .= quadraticActive r, "step" .= [(i, [x, y, z]) | (i, V3 x y z) <- IM.toList step], "contacts" .= contacts, "exchanges" .= exchanges])
  reports <- mapM report methods
  pure (object ["lengthWeight" .= weight, "damping" .= (1e-3 :: Double), "freeVertices" .= ids, "materialRows" .= map row material, "contactRows" .= map row gaps, "reports" .= reports])

-- Original edge lengths are measured in material coordinates. The solver
-- penalizes ABSOLUTE length errors, whereas acceptance uses RELATIVE error;
-- short edges can therefore miss the cap even at a settled penalized shape.
-- Retain every edge so the maximum and the length cost can be recomputed.
lengthReport :: MaterialMesh -> IO Value
lengthReport mesh = do
  let vertices = IM.fromList (zip [0 ..] (samples mesh))
      vertex i = checked (maybe (Left (InequalityError ("length report lost vertex " <> tshow i))) Right (IM.lookup i vertices))
  edges <- forM (meshEdges mesh) $ \(a, b) -> do
    p <- vertex a
    q <- vertex b
    let rest = sqrt ((materialU p - materialU q) ^ (2 :: Int) + (materialV p - materialV q) ^ (2 :: Int))
        actual = norm (position p ^-^ position q)
    pure (a, b, rest, actual, actual / rest - 1)
  pure
    ( object
        [ "sumSquaredError" .= sum [(actual - rest) ^ (2 :: Int) | (_, _, rest, actual, _) <- edges],
          "edges" .= [object ["vertices" .= [a, b], "rest" .= rest, "actual" .= actual, "relativeError" .= err] | (a, b, rest, actual, err) <- sortOn (\(_, _, _, _, err) -> Down (abs err)) edges]
        ]
    )

-- The saved failed endpoint, not a softened fresh guess, starts both runs.
-- This isolates more work at the same weight from a stronger penalty. The
-- full vectors and step history remain available for independent checks.
replayLength :: CoupledFixture -> MaterialMesh -> IO Value
replayLength fixture mesh = do
  reports <- forM [1e9, 1e10] $ \weight -> do
    result <- checked (solveCoupledMethod ExchangeNearDependent [weight] WithoutPairContact (Settings 40 1e-5) fixture {coupledSeed = mesh})
    let endpoint = inequalityMesh result
    (measurement, _) <- measure fixture endpoint
    lengths <- lengthReport endpoint
    changes <- checked (panelChanges mesh endpoint)
    pure (object ["lengthWeight" .= weight, "solve" .= resultReport result, "measurements" .= measurement, "lengthDiagnostics" .= lengths, "panelChanges" .= changes, "positions" .= coordinates endpoint])
  pure (object ["sourcePositions" .= coordinates mesh, "iterationLimit" .= (40 :: Int), "lengthTolerance" .= (1e-5 :: Double), "reports" .= reports])
  where
    coordinates m = [[x, y, z] | p <- samples m, let V3 x y z = position p]
