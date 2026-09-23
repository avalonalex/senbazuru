-- | Inspect the archived moving-plane comparison without solving again.
-- Validate both saved proposals and every finite trial against the same paper
-- and acceptance checks before decomposing their distances. The original
-- quadratic reports remain archival evidence, not newly computed solutions.
--
-- Paper images and FOLD files are copied unchanged. Only the accounting charts
-- are new drawings; their axes are numerical measurements, not exaggerated
-- paper positions. Paths come from fixed direction and fraction indices.
module BodyPlaneLossGallery (writeBodyPlaneLoss) where

import BodyContactDiagnosis
import BodyCorrectionArchive
import BodyCorrectionReplay
import BodyDirectionGallery (rowValue)
import BodyPatch
import BodyPatchCheckpoints
import BodyPlaneGuard
import BodyPlaneLoss
import BodyShortArchive
import Control.Monad (forM, forM_, unless, when)
import CraneSpread
import Data.Aeson (FromJSON, Value, eitherDecode, encode, object, (.=))
import Data.Aeson.Key (Key)
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Senbazuru.Diagram
import Senbazuru.Explain (num)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Senbazuru.Render.Svg
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (takeDirectory, (</>))

data LossTrial = LossTrial String Value PlaneLoss

data LossDirection = LossDirection String Value [LossTrial]

writeBodyPlaneLoss :: FilePath -> FilePath -> IO ()
writeBodyPlaneLoss source destination = do
  let output = destination </> "body-plane-loss"
  separateOutput source output
  archive <- readShortArchive (source </> "source")
  (reportBytes, report) <- jsonFile (source </> "checks.json")
  expect "gallery" ("body-plane" :: Text) report
  expect "sourceAttempt" (10 :: Int) report
  expect "newQuadratics" (1 :: Int) report
  expect "continuationSteps" (0 :: Int) report
  forM_ ["continuousMotionChecked", "wholeCraneChecked"] $ \key -> expect key False report
  forM_ [("contactTolerance", 1e-7), ("lengthTolerance", 1e-5), ("movementTolerance", 1e-7), ("lengthWeight", 1e8), ("contactWeight", 1e10), ("damping", 1e-3)] $ \(key, x) -> expect key (x :: Double) report
  expect "quadraticBudget" (100 :: Int) report
  expect "drawingScale" (600 :: Double) report
  expect "sourceControl" (shortAttempt archive) report
  forM_ ["materialRows", "constraints"] $ \key -> do value <- field key (shortAttempt archive) :: IO Value; expect key value report
  start <- case [shortMesh s | s <- shortStates archive, shortName s == "before"] of [m] -> pure m; _ -> die "missing saved start of attempt ten"
  let study = shortStudy archive; fixture = patchSpread study
  expect "startPositions" (map (xyz . position) (samples start)) report
  before <- pose start
  measure <- checked (measurePlane start 27 70)
  plane <- field "planeGuard" report
  expect "vertex" (27 :: Int) plane
  expect "triangle" (70 :: Int) plane
  expect "gradient" (rowValue (planeGradient measure, planeDistance measure)) plane
  expect "row" (rowValue (planeGuardRow (spreadPins fixture) measure)) plane
  nearField 1e-17 "distance" (planeDistance measure) plane
  nearField 1e-17 "floor" (min 0 (planeDistance measure)) plane
  let readMesh name state = do
        (bytes, file) <- jsonFile (source </> name ++ ".fold")
        ps <- traverse vector (verticesCoords (keyFrame file))
        unless (length ps == length (samples start)) (die "plane archive vertex count changed")
        let mesh = start {samples = zipWith (\p q -> p {position = q}) (samples start) ps}
        expected <- materialFrame <$> checked (spreadSurface fixture mesh)
        unless (keyFrame file == expected) (die "plane archive material, topology or metadata changed")
        expect "id" name state
        checkState study mesh state
        pure (mesh, (name ++ ".fold", bytes))
  startRecord <- field "start" report
  (startMesh, startFile) <- readMesh "start" startRecord
  unless (startMesh == start) (die "plane archive started from another shape")
  directionRecords <- field "directions" report
  unless (length directionRecords == 2) (die "expected two saved plane directions")
  directions <- forM (zip ["control", "plane"] directionRecords) $ \(name, direction) -> do
    expect "id" name direction
    expect "usesPlaneGuard" (name == "plane") direction
    expect "failure" (Nothing :: Maybe Text) direction
    expect "directionVerified" True direction
    expect "acceptedEndpoint" False direction
    quadratic <- field "quadratic" direction
    expect "converged" True quadratic
    forM_ [("balance", 1e-6), ("complementarity", 1e-12), ("violation", 1e-12)] $ \(key, cap) -> do
      x <- field key quadratic; unless (finite x && x >= 0 && x <= cap) (die "archived quadratic report fails its numerical limits")
    proposal <- field "proposal" direction >>= traverse vector
    raw <- field "correction" direction >>= traverse vector
    unless (length raw == length (samples start) && length proposal == length raw && and (zipWith3 (\p d q -> position p ^+^ d == q) (samples start) raw proposal)) (die "archived raw correction does not produce its proposal")
    full <- checked (scaledProposal 1 start proposal)
    proposalPose <- pose full
    movement <- checked (savedMovement (SavedPoint 0 start) (SavedPoint 0 full))
    nearField 1e-14 "fullMovement" movement direction
    unless (movement > 1e-7) (die "archived full movement already meets equilibrium")
    replayed <- checked (replayCorrection study start proposal)
    selected <- maybe (die "saved direction has no passing trial") pure (firstPassing replayed)
    expect "selectedScale" (replayScale selected) direction
    records <- field "trials" direction
    unless (length records == 31) (die "plane archive lost trial fractions")
    entries <- forM (zip3 [0 :: Int ..] replayed records) $ \(k, trial, record) -> do
      let nameOfTrial = name ++ "-" ++ show k
      expect "scale" (replayScale trial) record
      expect "geometryPassed" (replayGeometryPassed trial) record
      expect "costDecreased" (replayCostDecreased trial) record
      nearField 1e-14 "movement" (replayMovement trial) record
      state <- field "state" record
      (mesh, bytes) <- readMesh nameOfTrial state
      unless (mesh == savedMesh (measuredPoint (replayMeasure trial))) (die "saved plane trial differs from its fraction of the proposal")
      after <- pose mesh
      loss <- checked (decomposePlane before proposalPose (replayScale trial) after)
      nearField 1e-16 "predictedDistance" (linearDistance loss) record
      pair <- field "pair" record
      measured <- checked (measurePlane mesh 27 70)
      nearField 1e-17 "distance" (planeDistance measured) pair
      nearField 1e-17 "margin" (planeDistance measured + 1e-7) pair
      section <- checked (pairSection mesh (46, 70))
      expect "crosses" (sectionCrosses section) pair
      nearField 1e-12 "intersectionLength" (intersectionLength section) pair
      pure (LossTrial nameOfTrial record loss, bytes)
    let selectedNames = [name ++ "-" ++ show k | (k, trial) <- zip [0 :: Int ..] replayed, replayScale trial == replayScale selected]
    expect "selectedState" selectedNames direction
    when (name == "control") $ forM_ ["proposal", "correction", "quadratic", "contacts", "selectedScale"] $ \key -> do expected <- field key (shortAttempt archive) :: IO Value; expect key expected direction
    pure (LossDirection name direction (map fst entries), map snd entries)
  -- Finish validating before writing. Each fixed-name paper asset is archived
  -- verbatim; no diagnostic displacement is installed as new paper geometry.
  let files = ("checks.json", reportBytes) : startFile : concatMap snd directions ++ [("source" </> name, bytes) | (name, bytes) <- shortFiles archive]
      stateNames = "start" : [name | (LossDirection _ _ trials, _) <- directions, LossTrial name _ _ <- trials]
  images <- forM [name ++ "-" ++ view ++ ".svg" | name <- stateNames, view <- ["tip", "pair", "side", "top", "underside", "material"]] $ \name -> do bytes <- BL.readFile (source </> name); pure (name, bytes)
  createDirectoryIfMissing True output
  forM_ (files ++ images) $ \(name, bytes) -> do
    let path = output </> "source" </> name
    createDirectoryIfMissing True (takeDirectory path)
    BL.writeFile path bytes
  forM_ [0 :: Int .. 30] $ \k -> do
    let entries = [(T.pack name, loss) | (LossDirection name _ trials, _) <- directions, (j, LossTrial _ _ loss) <- zip [0 :: Int ..] trials, j == k]
    TIO.writeFile (output </> "loss-" ++ show k ++ ".svg") (drawLoss entries)
  let result = object ["gallery" .= ("body-plane-loss" :: Text), "issue" .= (347 :: Int), "newSolves" .= (0 :: Int), "validatedTrials" .= (372 :: Int), "source" .= report, "reference" .= ("triangle 70 centroid; original winding" :: Text), "directions" .= [object ["id" .= name, "archived" .= record, "trials" .= [object ["id" .= trialName, "archived" .= trial, "accounting" .= lossValue loss] | LossTrial trialName trial loss <- trials]] | (LossDirection name record trials, _) <- directions]]
  BL.writeFile (output </> "checks.json") (encode result)
  template <- TIO.readFile "study/fold-material/body-plane-loss.html"
  TIO.writeFile (destination </> "body-plane-loss.html") (T.replace "/*BODY_PLANE_LOSS_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode result))) template)
  putStrLn ("Inspected 62 saved plane trials without new solves. Wrote " ++ destination </> "body-plane-loss.html")

lossValue :: PlaneLoss -> Value
lossValue m = object ([key .= f m | (key, f) <- [("initialDistance", initialDistance), ("actualDistance", actualDistance), ("linearDistance", linearDistance), ("quadraticDistance", quadraticDistance), ("relativeLinear", relativeLinear), ("rotationLinear", rotationLinear), ("rotationRemainder", rotationRemainder), ("motionInteraction", motionInteraction), ("relativeRounding", relativeRounding), ("reconciliationError", reconciliationError), ("rotationSecondOrder", rotationSecondOrder), ("interactionSecondOrder", interactionSecondOrder), ("normalTurn", normalTurn)]] ++ [key .= xyz (f m) | (key, f) <- [("startNormal", startNormal), ("trialNormal", trialNormal), ("normalDerivative", normalDerivative), ("normalQuadratic", normalQuadratic), ("startRelative", startRelative), ("trialRelative", trialRelative), ("relativeDerivative", relativeDerivative)]])

-- | One common numerical scale for both directions at the same fraction.
-- Bars are losses missed by the linear prediction, never displaced paper.
drawLoss :: [(Text, PlaneLoss)] -> Text
drawLoss entries = renderSvg page (diagramWithExtent bounds shapes)
  where
    groups = [("Plane rotation", rotationRemainder), ("Interaction", motionInteraction), ("Relative rounding", relativeRounding), ("Total missed", \m -> actualDistance m - linearDistance m)]
    values = [1e12 * f m | (_, m) <- entries, (_, f) <- groups]
    extent = maximum (1e-6 : map abs values)
    bounds = Box (V2 (-1.4) (-1.55)) (V2 6.8 1.4)
    line colour width = Polyline (solid (Colour colour) width)
    axes = [line "#918b7e" 1 [V2 (-0.4) 0, V2 6.5 0], line "#bcb7ab" 1 [V2 (-0.4) (-1), V2 (-0.4) 1]] ++ [Offset (V2 (-70) 4) (Label (Colour "#55584f") 11 (V2 (-0.4) y) (num (y * extent))) | y <- [-1, 0, 1]]
    bars = [let x = 2 * fromIntegral i + fromIntegral j * 0.3 - 0.15; y = 1e12 * f m / extent; colour = if j == 0 then "#777e87" else "#235e87" in line colour 14 [V2 x 0, V2 x y] | (i, (_, f)) <- zip [0 :: Int ..] groups, (j, (_, m)) <- zip [0 :: Int ..] entries]
    labels = [Offset (V2 (-48) 0) (Label (Colour "#55584f") 12 (V2 (2 * fromIntegral i) (-1.35)) title) | (i, (title, _)) <- zip [0 :: Int ..] groups]
    shapes = axes ++ bars ++ labels
    page = defaultPage {pageWidth = 900, pageHeight = 340, pageMargin = 30, pageBackground = Nothing, pageTitle = Just "Missed plane-distance change in units of 1e-12 sheet lengths: grey control, blue extra guard"}

pose :: MaterialMesh -> IO PlanePose
pose mesh = do
  unless (IM.lookup 70 (IM.fromList (zip [0 :: Int ..] (triangles mesh))) == Just (81, 71, 20)) (die "triangle 70 vertex identity changed")
  let point i = maybe (die "plane accounting lost a vertex") (pure . position) (IM.lookup i (IM.fromList (zip [0 :: Int ..] (samples mesh))))
  PlanePose <$> point 27 <*> point 81 <*> point 71 <*> point 20

jsonFile :: (FromJSON a) => FilePath -> IO (BL.ByteString, a)
jsonFile path = do bytes <- BL.readFile path; value <- either die pure (eitherDecode bytes); pure (bytes, value)

expect :: (Eq a, FromJSON a) => Key -> a -> Value -> IO ()
expect key expected record = do value <- field key record; unless (value == expected) (die ("changed plane archive field: " ++ show key))

nearField :: Double -> Key -> Double -> Value -> IO ()
nearField tolerance key expected record = do value <- field key record; unless (finite value && abs (value - expected) < tolerance) (die ("changed plane archive measurement: " ++ show key))

vector :: [Double] -> IO V3
vector [x, y, z] | all finite [x, y, z] = pure (V3 x y z)
vector _ = die "plane archive needs finite 3D coordinates"

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)
