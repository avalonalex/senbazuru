-- | Publish matched body-angle experiments, keeping diagnostic endpoints out
-- of the accepted 3D selector. Every solve is evaluated under both the old
-- strict-angle policy and the selected-preference policy; those two verdicts
-- describe one mesh, not two different physical solutions. Every trial,
-- accepted or not, carries its paper screen ("CraneSpreadScreen").
module CraneBodyGallery (writeCraneBody) where

import Control.Exception (evaluate)
import Control.Monad (forM, forM_, when)
import CraneBody
import CraneRoot
import CraneSpread
import CraneSpreadGallery (screenKeys, spreadFigure)
import CraneWing (wingRoot)
import Data.Aeson (encode, object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.List.NonEmpty (nonEmpty)
import Data.Maybe (isJust, isNothing)
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import FoldMaterial (areaRatio, componentCount)
import FoldRelaxation
import RigidBase (Base (..), BaseCheck (..), BaseSearch (..), baseReport, checkBase, checkPassed, searchBase, spreadSolve, takeBase)
import ScreenReport (Figure (..), PageScale (..), pageScale, thresholdsJson, writeScreenScript)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import SparseSolve (LinearReport (..))
import System.CPUTime (getCPUTime)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)
import WingBending (finalMesh)

writeCraneBody :: FilePath -> IO ()
writeCraneBody destination = do
  let output = destination </> "crane-body"
      controls = [("fixed", "Fixed body reference", OriginalPreferences), ("original", "Free patch · original springs", OriginalPreferences), ("weaker", "Free patch · selected springs × 0.1", WeakerBody), ("open", "Free patch · selected preference 170°", OpenBody), ("crossed", "Incompatible upper grip", WeakerBody)]
  createDirectoryIfMissing True output
  source <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= checked)
  -- The wing hinges at its root, found by rule (owner decisions 34 and 35).
  hinge <- either (die . T.unpack) pure (wingRoot source)
  -- Every control turns the wing's base as one piece. The fixed control
  -- holds the body and prefers a flat hinge, so it is the gallery's
  -- flat-preference control: it searches for the base angle, and every other
  -- control takes the angle it finds (owner decision 36).
  fixedRoot <- checked (craneRootAt hinge source 3 FlatRoot)
  putStrLn "Searching the fixed control's base angle"
  hFlush stdout
  searchStart <- getCPUTime
  search <- checked (searchBase (spreadSolve (Settings 40 1e-5)) fixedRoot)
  _ <- evaluate (baseDegrees search)
  searchEnd <- getCPUTime
  let theta = baseDegrees search
  putStrLn ("Base angle " ++ show theta ++ " degrees")
  results <- forM controls $ \(stem, title, control) -> do
    base <- checked (craneBodyAt hinge source 3 control)
    let held = bodyRoot base
        posed
          | stem == "fixed" = fixedRoot
          | stem == "crossed" = held {rootSpread = crossedGrip (rootSpread held)}
          | otherwise = held
        limit = if stem == "crossed" then 2 else 40
        settings = Settings limit 1e-5
    putStrLn ("Solving " ++ stem)
    hFlush stdout
    start <- getCPUTime
    -- The incompatible grip is made to fail, so the gallery can never accept
    -- it and the check could not change its verdict: it takes the search's
    -- angle unchecked (owner decision 36).
    (root, result, set) <- case stem of
      "fixed" -> pure (baseStudy search, baseResult search, Searched)
      "crossed" -> do
        (turned, r, ()) <- checked (takeBase (spreadSolve settings) theta posed)
        pure (turned, r, Taken)
      _ -> do
        check <- checked (checkBase (spreadSolve settings) theta posed)
        pure (checkStudy check, checkResult check, Checked check)
    let study = base {bodyRoot = root}
        fixture = rootSpread root
    mesh <- checked (finalMesh result)
    _ <- evaluate (maxLengthError mesh + if converged result then 1 else 0)
    settled <- getCPUTime
    (strictValid, valid) <- checked (bodyAccepted study result mesh)
    let passed = case set of Checked check -> checkPassed check; _ -> True
        strict = strictValid && passed
        accepted = valid && passed
        seconds = fromIntegral (settled - start) / 1e12 + (if stem == "fixed" then fromIntegral (searchEnd - searchStart) / 1e12 else 0)
    contact <- checked (spreadCheck fixture mesh)
    (selectedError, retainedError) <- checked (bodyAngleErrors study mesh)
    angles <- checked (bodyAngles study mesh)
    roots <- checked (rootAngles root mesh)
    (creaseEnergy, panelEnergy) <- checked (bendingEnergy (spreadHinges fixture) mesh)
    sheet <- checked (spreadSurface fixture mesh)
    let drawing = spreadFigure [sheet]
        -- The gallery draws an accepted trial by itself where it can. That
        -- drawing is the trial's picture, and one of the page's drawings.
        own = if accepted then either (const Nothing) Just drawing else Nothing
    (_, screened) <- either (die . T.unpack) pure (screenKeys fixture contact (isJust own) mesh)
    let measured =
          [ "id" .= stem,
            "title" .= (title :: Text),
            "control" .= show control,
            "strictAccepted" .= strict,
            "selectedAccepted" .= accepted,
            "converged" .= converged result,
            "equilibrium" .= fmap equilibrium (equilibriumCheck result),
            "iterationLimitPerStage" .= limit,
            "iterations" .= maximum (0 : map completedIterations (checkpoints result)),
            "refinement" .= (3 :: Int),
            "vertices" .= length (samples mesh),
            "triangles" .= length (triangles mesh),
            "components" .= componentCount mesh,
            "heldVertices" .= IM.size (spreadPins fixture),
            "sourceOrders" .= length (spreadOrders fixture),
            "activeSourceOrders" .= length (spreadContactOrders fixture),
            "releasedPanels" .= (if stem == "fixed" then [] else map unFaceId (S.toAscList (rootNeighbours root))),
            "selectedCreases" .= map unEdgeId (S.toAscList (bodySelected study)),
            "angles" .= [object ["sourceEdge" .= unEdgeId (angleSource a), "selected" .= angleSelected a, "achievedRadians" .= angleAchieved a, "originalRadians" .= angleOriginal a, "preferredRadians" .= anglePreferred a] | a <- angles],
            "rootAnglesRadians" .= map snd roots,
            "maxSelectedOriginalErrorRadians" .= selectedError,
            "maxRetainedOriginalErrorRadians" .= retainedError,
            "maxRelativeEdgeError" .= maxLengthError mesh,
            "areaRatio" .= areaRatio mesh,
            "heldPositionError" .= spreadHeldError fixture mesh,
            "bodyMovement" .= rootBodyMovement root mesh,
            "creaseEnergy" .= creaseEnergy,
            "panelEnergy" .= panelEnergy,
            "contact" .= contact,
            "hingeY" .= hinge,
            "baseDegrees" .= theta,
            "base" .= baseReport search set,
            "solveCpuSeconds" .= (seconds :: Double),
            "continuousMotionChecked" .= False
          ]
        report scale = object (measured ++ maybe [] screened scale)
        file = FoldFile (Just 1.2) (Just "senbazuru body crease preferences") Nothing (Just title) Nothing [] (materialFrame sheet) []
    BL.writeFile (output </> stem ++ ".fold") (encode file)
    -- Publish measurements before attempting a renderer: export failures must
    -- not discard an expensive experiment or turn physical acceptance false.
    -- The screen waits for the page's scale, and the file is written again
    -- with it below.
    BL.writeFile (output </> stem ++ "-check.json") (encode (object measured))
    export <-
      if accepted
        then do
          let stable = renderSurfaceGlb defaultBudget VisiblePaper (Just title) sheet
          case stable of
            Right bytes -> do
              BS.writeFile (output </> stem ++ ".glb") bytes
              pure Nothing
            Left err -> do
              bytes <- checked (renderSurfaceGlb defaultBudget CompletePaper (Just title) sheet)
              BS.writeFile (output </> stem ++ "-complete.glb") bytes
              pure (Just (explain err))
        else pure Nothing
    forM_ own $ \svg -> TIO.writeFile (output </> stem ++ ".svg") (figureSvg svg)
    case (accepted, drawing) of
      (True, Left err) -> putStrLn (T.unpack err)
      _ -> pure ()
    putStrLn (stem ++ ": strict " ++ show strict ++ ", selected " ++ show accepted ++ "; length " ++ show (maxLengthError mesh) ++ "; selected/retained angle " ++ show (selectedError, retainedError))
    hFlush stdout
    pure ((stem, title, accepted, export, report, own), (stem, accepted, samples mesh))
  let runs = map fst results
      -- The page's drawings are the accepted trials' own, written beside it;
      -- the page itself shows none of them.
      scale = pageScale <$> nonEmpty [own | (_, _, _, _, _, Just own) <- runs]
      reports = [(stem, report scale) | (stem, _, _, _, report, _) <- runs]
  forM_ reports $ \(stem, report) -> BL.writeFile (output </> stem ++ "-check.json") (encode report)
  -- How far each free-patch trial's paper lies from the fixed body's, on
  -- every run: the comparison owner decision 39 keeps, which says whether the
  -- quick tier's held body is a label or a change of shape.
  let held = heldComparison (pixelsPerSheet <$> scale) "fixed" (map snd results)
      document = object ["runs" .= map snd reports, "exports" .= [object ["id" .= stem, "stableAvailable" .= (accepted && isNothing err), "error" .= err] | (stem, _, accepted, err, _, _) <- runs], "screenThresholds" .= fmap thresholdsJson scale, "heldComparison" .= held]
  BL.writeFile (output </> "checks.json") (encode document)
  when (isNothing scale) (die "No crane-body trial was drawn, so the page has no scale to screen at; checks.json holds the measurements without screens. Refusing to publish the page")
  BL.writeFile (output </> "models.json") (encode [object ["title" .= title, "path" .= (stem ++ ".glb")] | (stem, title, True, Nothing, _, _) <- runs])
  viewer <- TIO.readFile "study/gltf/viewer.html"
  TIO.writeFile (output </> "index.html") (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer)
  writeScreenScript destination
  template <- TIO.readFile "study/fold-material/crane-body.html"
  TIO.writeFile (destination </> "crane-body.html") (T.replace "/*BODY_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn ("Wrote crane-body.html and measurements to " ++ destination)
  where
    equilibrium check = let linear = equilibriumLinear check in object ["linearConverged" .= linearConverged linear, "linearResidual" .= linearResidual linear, "linearThreshold" .= linearThreshold linear, "fullMovement" .= equilibriumMovement check, "movementThreshold" .= (1e-7 :: Double)]

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
