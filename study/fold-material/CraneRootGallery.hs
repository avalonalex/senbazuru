-- | Publish the controlled root comparisons with their numerical evidence.
-- Renderer failures retain complete-sheet GLBs and their errors separately
-- from physical acceptance. Failed endpoints have diagnostic FOLD files but
-- cannot enter the accepted
-- 3D model selector. Root spring residuals are reported separately from the
-- original folded creases, because a soft preference is not an exact hold.
-- Every control, accepted or not, carries its paper screen
-- ("CraneSpreadScreen").
--
-- Two controls repeat with the wing hinged at the neck and tail bases (#455).
-- There a released control turns the wing's base as one piece, at the angle
-- 'searchBase' finds, so its reported root turn is that chosen angle, not
-- something the solve settled.
module CraneRootGallery (writeCraneRoot, goldenSection) where

import Control.Exception (evaluate)
import Control.Monad (forM, forM_, when)
import CraneRoot
import CraneSpread
import CraneSpreadGallery (screenKeys, spreadFigure)
import CraneWing (studyHinge)
import Data.Aeson (encode, object, (.=))
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Either (isRight)
import Data.IntMap.Strict qualified as IM
import Data.List.NonEmpty (nonEmpty)
import Data.Maybe (isJust, isNothing)
import Data.Set qualified as S
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldMaterial (areaRatio, componentCount)
import FoldRelaxation
import ScreenReport (Figure (..), Screen (..), pageScale, thresholdsJson, writeScreenScript)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types (FoldFile (..), unEdgeId, unFaceId)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import Senbazuru.Render.Svg (formatNumber)
import SparseSolve (LinearReport (..))
import System.CPUTime (getCPUTime)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)
import WingBending (finalMesh)
import WingBendingGallery (refinement)

writeCraneRoot :: FilePath -> IO ()
writeCraneRoot destination = do
  let output = destination </> "crane-root"
      -- The last two hinge the wing at the neck and tail bases, where a
      -- crane's wing opens (#455), above the wing's widest point.
      controls =
        [ ("held", "Held root · 30°", 3, HeldRoot, False, studyHinge),
          ("released", "Released strip · 30° preference", 3, ReleasedRoot, False, studyHinge),
          ("weaker", "Released strip · weaker spring", 3, WeakerRoot, False, studyHinge),
          ("flat", "Released strip · flat preference", 3, FlatRoot, False, studyHinge),
          ("fine", "Flat preference · finer mesh", 4, FlatRoot, False, studyHinge),
          ("body", "Flat preference · nearby body free", 3, FreeBody, False, studyHinge),
          ("crossed-grip", "Upper grip below lower · incompatible", 3, FlatRoot, True, studyHinge),
          ("held-neck", "Held root · 30° · hinge at the neck and tail bases", 3, HeldRoot, False, neckHinge),
          ("flat-neck", "Flat preference · hinge at the neck and tail bases", 3, FlatRoot, False, neckHinge)
        ]
  createDirectoryIfMissing True output
  source <- loadFoldFile "examples/crane.fold" >>= checked
  runs <- forM controls $ \(stem, title, level, control, invalid, hinge) -> do
    original <- checked (craneRootAt hinge (keyFrame source) level control)
    let posed = if invalid then original {rootSpread = crossedGrip (rootSpread original)} else original
        limit = if invalid then 2 else 40
        settings = Settings limit 1e-5
        -- A control whose base 'rigidBase' would turn searches for the angle
        -- to turn it at. Every other control is one ordinary solve: a held
        -- one already holds its base, and below the widest point there is
        -- none.
        hasBase = spreadPins (rootSpread (rigidBase 30 posed (spreadMesh (rootSpread posed)))) /= spreadPins (rootSpread posed)
    putStrLn ("Solving " ++ stem)
    hFlush stdout
    start <- getCPUTime
    (study, result, mesh, search) <-
      if hasBase
        then do
          found <- checked (searchBase settings posed)
          pure (baseStudy found, baseResult found, baseMesh found, Just found)
        else do
          r <- checked (solveSpread settings (rootSpread posed))
          m <- checked (finalMesh r)
          pure (posed, r, m, Nothing)
    let fixture = rootSpread study
    _ <- evaluate (maxLengthError mesh + if converged result then 1 else 0)
    settled <- getCPUTime
    accepted <- checked (rootAccepted study result mesh)
    contact <- checked (spreadCheck fixture mesh)
    angles <- checked (rootAngles study mesh)
    creaseError <- checked (originalCreaseError study mesh)
    (creaseEnergy, panelEnergy) <- checked (bendingEnergy (spreadHinges fixture) mesh)
    sheet <- checked (spreadSurface fixture mesh)
    profile <- checked (rootProfile study mesh)
    let visibleResult = renderSurfaceGlb defaultBudget VisiblePaper (Just title) sheet
        drawing = spreadFigure [sheet]
        -- The gallery draws an accepted control by itself where it can. That
        -- drawing is the control's picture, and one of the page's drawings.
        own = if accepted then either (const Nothing) Just drawing else Nothing
        visible = accepted && isRight visibleResult
        visibleError = if accepted then either (Just . explain) (const Nothing) visibleResult else Nothing
        svgError = if accepted then either Just (const Nothing) drawing else Nothing
    (screen, screened) <- either (die . T.unpack) pure (screenKeys fixture contact (isJust own) mesh)
    let degrees = map ((180 / pi *) . abs . snd) angles
        equilibrium check = let linear = equilibriumLinear check in object ["linearConverged" .= linearConverged linear, "linearResidual" .= linearResidual linear, "linearThreshold" .= linearThreshold linear, "fullMovement" .= equilibriumMovement check, "movementThreshold" .= (1e-7 :: Double)]
        measured =
          [ "id" .= stem,
            "title" .= title,
            "refinement" .= level,
            "control" .= show control,
            "iterationLimitPerStage" .= limit,
            "accepted" .= accepted,
            "visibleGlbAvailable" .= visible,
            "visibleGlbError" .= visibleError,
            "svgError" .= svgError,
            "converged" .= converged result,
            "equilibrium" .= fmap equilibrium (equilibriumCheck result),
            "vertices" .= length (samples mesh),
            "triangles" .= length (triangles mesh),
            "components" .= componentCount mesh,
            "heldVertices" .= IM.size (spreadPins fixture),
            "neighbourPanels" .= map unFaceId (S.toList (rootNeighbours study)),
            "sourceOrders" .= length (spreadOrders fixture),
            "activeSourceOrders" .= length (spreadContactOrders fixture),
            "rootAnglesRadians" .= [object ["sourceEdge" .= unEdgeId eid, "angle" .= angle] | (eid, angle) <- angles],
            "minRootDegrees" .= minimum (180 : degrees),
            "maxRootDegrees" .= maximum (0 : degrees),
            "maxOriginalCreaseErrorRadians" .= creaseError,
            "maxRelativeEdgeError" .= maxLengthError mesh,
            "areaRatio" .= areaRatio mesh,
            "minPrincipalStrain" .= negate (screenSquash screen),
            "maxPrincipalStrain" .= screenStretch screen,
            "heldPositionError" .= spreadHeldError fixture mesh,
            "bodyMovement" .= rootBodyMovement study mesh,
            "creaseEnergy" .= creaseEnergy,
            "panelEnergy" .= panelEnergy,
            "contact" .= contact,
            "solveCpuSeconds" .= (fromIntegral (settled - start) / 1e12 :: Double),
            "continuousMotionChecked" .= False
          ]
            ++ ["hingeY" .= rootHingeY study | rootHingeY study /= studyHinge]
            ++ concat [["baseDegrees" .= baseDegrees found, "baseSearch" .= [object ["degrees" .= degree, "energy" .= energy, "converged" .= settledThere] | (degree, energy, settledThere) <- baseTried found]] | Just found <- [search]]
        report scale = object (measured ++ maybe [] screened scale)
        file = FoldFile (Just 1.2) (Just "senbazuru crane root material study") Nothing (Just title) Nothing [] (materialFrame sheet) []
    BL.writeFile (output </> stem ++ ".fold") (encode file)
    -- A control's measurements are written before any renderer runs, so an
    -- export failure cannot discard them. Its screen waits for the page's
    -- scale, and the file is written again with it below.
    BL.writeFile (output </> stem ++ "-check.json") (encode (object measured))
    when accepted $ case visibleResult of
      Right bytes -> BS.writeFile (output </> stem ++ ".glb") bytes
      Left err -> do
        putStrLn (stem ++ ": stable-view export unavailable: " ++ T.unpack (explain err))
        bytes <- checked (renderSurfaceGlb defaultBudget CompletePaper (Just title) sheet)
        BS.writeFile (output </> stem ++ "-complete.glb") bytes
    forM_ own $ \svg -> TIO.writeFile (output </> stem ++ ".svg") (figureSvg svg)
    forM_ svgError $ \err -> putStrLn (stem ++ ": SVG unavailable: " ++ T.unpack err)
    putStrLn (stem ++ ": " ++ if accepted then "accepted" else "unaccepted diagnostic")
    hFlush stdout
    pure (stem, title, accepted, sheet, report, creaseEnergy + panelEnergy, profile, visible, own)
  let bent = [(sheet, energy) | (stem, _, True, sheet, _, energy, _, _, _) <- runs, stem `elem` ["flat", "fine"]]
      comparisons = [object ["geometry" .= refinement a b, "relativeTotalEnergyChange" .= (abs (eb - ea) / ea)] | ((a, ea), (b, eb)) <- zip bent (drop 1 bent)]
      -- The page's scale is the largest of the controls' own drawings. The
      -- comparison and the two hinge figures draw some of them together, on
      -- the same page from the same camera, so they are never larger; the
      -- profiles are a plot of heights along the wing, not a drawing of the
      -- paper.
      scale = pageScale <$> nonEmpty [own | (_, _, _, _, _, _, _, _, Just own) <- runs]
      reports = [(stem, report scale) | (stem, _, _, _, report, _, _, _, _) <- runs]
  forM_ reports $ \(stem, report) -> BL.writeFile (output </> stem ++ "-check.json") (encode report)
  let document = object ["runs" .= map snd reports, "refinement" .= comparisons, "screenThresholds" .= fmap thresholdsJson scale]
  BL.writeFile (output </> "checks.json") (encode document)
  when (isNothing scale) (die "No crane-root control was drawn, so the page has no scale to screen at; checks.json holds the measurements without screens. Refusing to publish the gallery")
  let comparison = [(title, sheet) | (stem, title, True, sheet, _, _, _, True, _) <- runs, stem `elem` ["held", "flat", "body"]]
  drawing <- either (die . T.unpack) pure (spreadFigure (map snd comparison))
  TIO.writeFile (output </> "comparison.svg") (figureSvg drawing)
  TIO.writeFile (output </> "profile.svg") (profileSvg [(stem, points) | (stem, _, True, _, _, _, points, _, _) <- runs, stem `elem` ["held", "released", "weaker", "flat", "body", "held-neck", "flat-neck"]])
  -- Each control beside the same control hinged at the neck and tail bases,
  -- drawn together from one camera at one scale.
  forM_ [("hinge-held", "held", "held-neck"), ("hinge-flat", "flat", "flat-neck")] $ \(name, quarter, neck) ->
    case [sheet | wanted <- [quarter, neck], (stem, _, True, sheet, _, _, _, _, _) <- runs, stem == wanted] of
      pair@[_, _] -> either (die . T.unpack) (TIO.writeFile (output </> name ++ ".svg") . figureSvg) (spreadFigure pair)
      _ -> putStrLn (name ++ ": both controls must be accepted to draw them side by side")
  BL.writeFile (output </> "models.json") (encode [object ["title" .= title, "path" .= (stem ++ ".glb")] | (stem, title, True, _, _, _, _, True, _) <- runs])
  viewer <- TIO.readFile "study/gltf/viewer.html"
  TIO.writeFile (output </> "index.html") (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer)
  writeScreenScript destination
  template <- TIO.readFile "study/fold-material/crane-root.html"
  TIO.writeFile (destination </> "crane-root.html") (T.replace "/*ROOT_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn ("Wrote crane-root.html and measurements to " ++ destination)

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure

-- One scale for every profile; the hinge at 1/4 lies halfway along the plot
-- and the neck and tail bases, y = 0.376, at x = 288. y points towards the
-- body and z points up in the model. Negating both draws the wing tip to the
-- right and its downward displacement down the SVG page. A control hinged at
-- the neck and tail bases is dashed, in the colour of its 1/4 counterpart.
profileSvg :: [(String, [V3])] -> T.Text
profileSvg curves =
  "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1080 590\" role=\"img\"><title>Measured side profiles through the wing root</title>"
    <> "<path d=\"M40 80H1040M540 50V580M288 50V580\" stroke=\"#c2b7a4\" stroke-dasharray=\"4 5\" fill=\"none\"/>"
    <> "<g font-family=\"system-ui,sans-serif\" font-size=\"18\" fill=\"#292d28\"><text x=\"40\" y=\"35\">Body</text><text x=\"545\" y=\"35\">Hinge at y = 1/4 (solid)</text><text x=\"278\" y=\"548\" text-anchor=\"end\">Neck and tail bases,</text><text x=\"278\" y=\"570\" text-anchor=\"end\">y = 0.376 (dashed)</text><text x=\"930\" y=\"35\">Wing tip</text></g>"
    <> T.concat ["<polyline fill=\"none\" stroke=\"" <> color base <> "\" stroke-width=\"2.5\"" <> dash <> " points=\"" <> T.unwords [formatNumber (40 + 2000 * (0.5 - y)) <> "," <> formatNumber (80 - 2000 * z) | V3 _ y z <- points] <> "\"/>" | (stem, points) <- curves, let (base, dash) = neck stem]
    <> "</svg>"
  where
    neck stem = case T.stripSuffix "-neck" (T.pack stem) of
      Just quarter -> (T.unpack quarter, " stroke-dasharray=\"7 4\"")
      Nothing -> (stem, "")
    color stem = case stem of "held" -> "#675949"; "released" -> "#a94e32"; "weaker" -> "#bc862b"; "flat" -> "#267364"; _ -> "#5654a0"

-- | The neck and tail bases: on the folded fixture the wing's outline returns
-- to its narrow width here and the neck and tail paper begins beside it.
neckHinge :: Double
neckHinge = 0.376

-- | A released control whose base turns as one piece ('rigidBase'), held at
-- the angle that leaves the paper, hinge included, the least bending energy.
data BaseSearch = BaseSearch
  { baseDegrees :: !Double,
    baseStudy :: !CraneRoot,
    baseResult :: !Relaxation,
    baseMesh :: !MaterialMesh,
    -- | Every angle tried, in degrees, with its bending energy and whether
    -- its solve converged, in order. An unconverged energy still steers the
    -- search, so the record says which ones were.
    baseTried :: ![(Double, Double, Bool)]
  }

-- | Search 15 to 45 degrees, to 0.05 degree. The first two solves start
-- from the control's own mesh, and each later one from the mesh of the
-- bracket point beside it.
searchBase :: Settings -> CraneRoot -> Either SpreadError BaseSearch
searchBase settings study = do
  ((theta, _, (_, found)), tried) <- goldenSection 0.05 15 45 (spreadMesh (rootSpread study), Nothing) solveAt
  (turned, result, mesh) <- maybe (Left (SpreadError "the base search made no solve")) Right found
  pure (BaseSearch theta turned result mesh [(degree, energy, maybe False (\(_, r, _) -> converged r) made) | (degree, energy, (_, made)) <- tried])
  where
    solveAt (start, _) theta = do
      let turned = rigidBase theta study start
      result <- solveSpread settings (rootSpread turned)
      mesh <- first (SpreadError . explain) (finalMesh result)
      (crease, panel) <- first (SpreadError . explain) (bendingEnergy (spreadHinges (rootSpread turned)) mesh)
      pure (crease + panel, (mesh, Just (turned, result, mesh)))

-- | The least value of @f@ on [@lo@, @hi@] by golden-section search, narrowed
-- until the bracket is narrower than @tolerance@, which must be positive and
-- well above the rounding of @lo@ and @hi@: a bracket that rounding stops
-- shrinking never gets narrower, and the search would not end. Each
-- evaluation is handed the payload of the interior point that stays beside
-- it, the nearest point already evaluated, so a solve can start from the last
-- one nearby. Returns the best argument, its value and
-- payload, and every evaluation, with its payload, in the order made. It
-- assumes one minimum in the bracket, as a search by bracketing must.
goldenSection :: Double -> Double -> Double -> s -> (s -> Double -> Either e (Double, s)) -> Either e ((Double, Double, s), [(Double, Double, s)])
goldenSection tolerance lo hi start f = do
  (fc, sc) <- f start c0
  (fd, sd) <- f start d0
  go lo hi (c0, fc, sc) (d0, fd, sd) [(d0, fd, sd), (c0, fc, sc)]
  where
    phi = (sqrt 5 - 1) / 2
    c0 = hi - phi * (hi - lo)
    d0 = lo + phi * (hi - lo)
    go a b c@(xc, fc, sc) d@(xd, fd, sd) tried
      | b - a < tolerance = Right (if fc <= fd then c else d, reverse tried)
      | fc <= fd = do
          let x = xd - phi * (xd - a)
          (fx, sx) <- f sc x
          go a xd (x, fx, sx) c ((x, fx, sx) : tried)
      | otherwise = do
          let x = xc + phi * (b - xc)
          (fx, sx) <- f sd x
          go xc b d (x, fx, sx) ((x, fx, sx) : tried)
