-- | One final-weight continuation, conditional on a valid inherited seed.
-- The saved coarse and failed fine controls are validated and copied before
-- solving. Wire drawings include hidden triangles; no numerical correction is
-- advertised as a physical folding route. Full proposals and refusals are
-- archived separately from the solver's returned checkpoints.
module BodyPatchSubdivisionGallery (writeBodyPatchSubdivision, writeState, stepValue, equilibriumValue) where

import BodyPatch
import BodyPatchCheckpointGallery (drawCheckpoint, views)
import BodyPatchCheckpoints
import BodyPatchSubdivision
import Control.Monad (forM, forM_, unless, when)
import CranePocket (buildCranePocket)
import CraneSpread
import Data.Aeson (FromJSON, Value, eitherDecode, encode, object, toJSON, withObject, (.:), (.=))
import Data.Aeson.Key (Key)
import Data.Aeson.Types (parseEither)
import Data.ByteString.Lazy qualified as BL
import Data.List (isPrefixOf, sortOn)
import Data.Ord (Down (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldMaterial (componentCount)
import FoldRelaxation
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Contact (crossingPanels, reversedOrders)
import Senbazuru.Origami.Surface
import SparseSolve (LinearReport (..))
import SurfaceContact qualified as Contact
import System.Directory (canonicalizePath, createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (splitDirectories, (</>))
import System.IO (hFlush, stdout)
import WingBending (finalMesh)

writeBodyPatchSubdivision :: FilePath -> FilePath -> IO ()
writeBodyPatchSubdivision source destination = do
  let output = destination </> "body-subdivision"
  src <- splitDirectories <$> canonicalizePath source
  dst <- splitDirectories <$> canonicalizePath output
  when (src `isPrefixOf` dst || dst `isPrefixOf` src) (die "subdivision source and output directories must not overlap")
  (rawDocument, document) <- readJson (source </> "checks.json")
  crane <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= checked)
  atlas <- checked (buildCranePocket crane)
  inputs <- forM [("opening-5", 0), ("opening-5-fine", 1)] $ \(name, level) -> do
    study <- checked (bodyPatch atlas level 5)
    (rawReport, report) <- readJson (source </> name ++ "-check.json")
    (rawInitial, initial) <- readJson (source </> name ++ "-initial.fold")
    (rawFinal, final) <- readJson (source </> name ++ ".fold")
    (rawHistory, history) <- readJson (source </> name ++ "-history.json")
    points <- checked (readPatchArchive (T.pack name) study document report (keyFrame initial) (keyFrame final) history)
    point <- case reverse points of p : _ -> pure p; [] -> die "missing archived endpoint"
    measured <- checked (measurePatch study point)
    forM_ [("maxRelativeEdgeError", maxLengthError (savedMesh point)), ("creaseEnergy", measuredCrease measured), ("panelEnergy", measuredPanel measured)] $ \(key, value) -> do
      original <- field key report
      unless (abs (original - value) <= 1e-12 * max 1 (abs value)) (die "archived endpoint measurements disagree")
    oldContact <- field "contact" report
    unless (oldContact == toJSON (measuredContact measured)) (die "archived endpoint contact disagrees")
    pure (study, point, [(name ++ "-check.json", rawReport), (name ++ "-initial.fold", rawInitial), (name ++ ".fold", rawFinal), (name ++ "-history.json", rawHistory)])
  case inputs of
    [(coarse, parent, coarseFiles), (fine, control, fineFiles)] -> do
      seed <- checked (subdivideRecovered coarse fine (savedMesh parent))
      validParent <- checked (seedPassed coarse (savedMesh parent))
      validSeed <- checked (seedPassed fine seed)
      createDirectoryIfMissing True (output </> "source")
      forM_ (("checks.json", rawDocument) : coarseFiles ++ fineFiles) $ \(name, bytes) -> BL.writeFile (output </> "source" </> name) bytes
      baseline <- sequence [writeState output "coarse" "Recovered coarse endpoint · unsettled" coarse parent, writeState output "seed" "Subdivided current shape · before continuation" fine (SavedPoint 0 seed), writeState output "control" "Original failed refined endpoint" fine control]
      let fixture = patchSpread fine
      result <-
        if validParent && validSeed
          then do
            putStrLn "Inherited geometry passes; one continuation, at most 40 corrections at length weight 1e8."
            hFlush stdout
            contact <- checked (Contact.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) seed)
            pure (Just (tracePinnedContact (Settings 40 1e-5) (spreadPins fixture) (spreadHinges fixture) contact seed))
          else pure Nothing
      (states, continuation) <- case result of
        Nothing -> pure ([], object ["ran" .= False, "reason" .= ("Inherited geometry did not pass; no solve attempted" :: Text)])
        Just (Left err) -> pure ([], object ["ran" .= True, "accepted" .= False, "failure" .= explain err])
        Just (Right (run, audit)) -> do
          endpoint <- checked (finalMesh run)
          accepted <- checked (patchAccepted fine run endpoint)
          snapshots <- forM (checkpoints run) $ \p -> writeState output ("step-" ++ show (completedIterations p)) ("Continuation checkpoint " <> T.pack (show (completedIterations p))) fine (SavedPoint (completedIterations p) (checkpointMesh p))
          let trace = map stepValue (solverSteps audit)
          BL.writeFile (output </> "trace.json") (encode trace)
          movement <- checked (savedMovement (SavedPoint 0 seed) (SavedPoint 0 endpoint))
          pure (snapshots, object ["ran" .= True, "accepted" .= accepted, "converged" .= converged run, "equilibrium" .= fmap equilibriumValue (equilibriumCheck run), "steps" .= length trace, "blockedIterations" .= map blockedIteration (blockedStages audit), "maxMovementFromSeed" .= movement, "trace" .= trace])
      let report = object ["gallery" .= ("body-subdivision" :: Text), "parentPassed" .= validParent, "seedPassed" .= validSeed, "iterationLimit" .= (40 :: Int), "lengthWeight" .= (1e8 :: Double), "contactMultiplier" .= (100 :: Int), "lengthTolerance" .= (1e-5 :: Double), "contactTolerance" .= (1e-7 :: Double), "wholeCraneChecked" .= False, "continuousMotionChecked" .= False, "states" .= (baseline ++ states), "continuation" .= continuation]
      BL.writeFile (output </> "checks.json") (encode report)
      template <- TIO.readFile "study/fold-material/body-subdivision.html"
      TIO.writeFile (destination </> "body-subdivision.html") (T.replace "/*SUBDIVISION_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode report))) template)
      putStrLn ("Wrote " ++ destination </> "body-subdivision.html")
    _ -> die "expected two archived controls"

writeState :: FilePath -> String -> Text -> BodyPatch -> SavedPoint -> IO Value
writeState output stem title study point = do
  let mesh = savedMesh point
      fixture = patchSpread study
  measured <- checked (measurePatch study point)
  valid <- checked (seedPassed study mesh)
  sheet <- checked (spreadSurface fixture mesh)
  BL.writeFile (output </> stem ++ ".fold") (encode (FoldFile (Just 1.2) (Just "senbazuru body subdivision study") Nothing (Just title) Nothing [] (materialFrame sheet) []))
  let worstEdge = take 1 (sortOn (Down . edgeRelativeError) (measuredEdges measured))
      worstOrder = take 1 (sortOn (\(_, _, d) -> Down d) (reversedOrders (measuredContact measured)) ++ [(a, b, 0) | (a, b) <- crossingPanels (measuredContact measured)])
  forM_ views $ \(name, projection, bounds, height) -> TIO.writeFile (output </> stem ++ "-" ++ name ++ ".svg") (drawCheckpoint projection bounds height mesh worstEdge worstOrder)
  angles <- checked (patchAngles study mesh)
  marks <- checked (patchLandmarks study mesh)
  pure (object ["id" .= stem, "title" .= title, "iteration" .= savedIteration point, "vertices" .= length (samples mesh), "triangles" .= length (triangles mesh), "components" .= componentCount mesh, "geometryPassed" .= valid, "holdError" .= spreadHeldError fixture mesh, "maxRelativeEdgeError" .= maxLengthError mesh, "contact" .= measuredContact measured, "minimumSolverGap" .= measuredMinimumGap measured, "creaseEnergy" .= measuredCrease measured, "panelEnergy" .= measuredPanel measured, "lengthCost" .= (5e7 * measuredLengthSquares measured), "contactCost" .= (5e9 * measuredContactSquares measured), "totalCost" .= patchCost 1e8 measured, "bodyDepth" .= measuredBodyDepth measured, "angles" .= [object ["sourceEdge" .= unEdgeId eid, "angle" .= a, "restAngle" .= r] | (eid, a, r) <- angles], "landmarks" .= [object ["name" .= name, "reference" .= xyz p, "position" .= xyz q] | (name, p, q) <- marks], "views" .= [name | (name, _, _, _) <- views]])

stepValue :: SolverStep -> Value
stepValue step = object ["iteration" .= solverIteration step, "start" .= positions (solverStart step), "fullProposal" .= positions (solverFullProposal step), "candidate" .= positions (solverCandidate step), "scale" .= solverScale step, "equilibrium" .= equilibriumValue (solverEquilibrium step), "beforeEnergy" .= solverBeforeEnergy step, "candidateEnergy" .= solverCandidateEnergy step, "refusals" .= map refusalValue (solverRefusals step)]

refusalValue :: RejectedTrial -> Value
refusalValue trial = object ["iteration" .= trialIteration trial, "scale" .= trialScale trial, "reason" .= explain (trialReason trial), "afterEnergy" .= trialAfterEnergy trial, "positions" .= positions (trialFinish trial)]

equilibriumValue :: EquilibriumCheck -> Value
equilibriumValue check = let linear = equilibriumLinear check in object ["linearConverged" .= linearConverged linear, "linearResidual" .= linearResidual linear, "linearThreshold" .= linearThreshold linear, "linearIterations" .= linearIterations linear, "factored" .= equilibriumFactored check, "fullMovement" .= equilibriumMovement check, "movementThreshold" .= (1e-7 :: Double)]

positions :: MaterialMesh -> [[Double]]
positions = map (xyz . position) . samples

xyz :: V3 -> [Double]
xyz (V3 x y z) = [x, y, z]

readJson :: (FromJSON a) => FilePath -> IO (BL.ByteString, a)
readJson path = do bytes <- BL.readFile path; value <- either die pure (eitherDecode bytes); pure (bytes, value)

field :: (FromJSON a) => Key -> Value -> IO a
field key = either die pure . parseEither (withObject "archive" (.: key))

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
