-- | Export one bounded construction, including failed initialization gates.
-- Authentication reuses the saved direction archive; changing a seed without
-- changing its evidence is refused before constructing any new candidate.
-- A ready seed is only an input to a future barrier experiment, not settled
-- material or a continuously checked physical folding motion.
module BodyInitializationGallery (writeBodyInitialization) where

import BodyCorrectionArchive
import BodyFourthArchive
import BodyInitialization
import BodyInitializationCheck (probeInitialization)
import BodyPatch
import BodyPatchCheckpoints
import BodyPatchSubdivisionGallery (writeState)
import Control.Monad (forM, forM_, unless)
import CraneSpread
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface
import SparseSolve qualified as Sparse
import SurfaceContact qualified as C
import System.CPUTime (getCPUTime)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (takeDirectory, (</>))
import System.IO (hFlush, stdout)

writeBodyInitialization :: FilePath -> FilePath -> IO ()
writeBodyInitialization source destination = do
  let output = destination </> "body-initialization"
  separateOutput source output
  putStrLn "Authenticate the saved start; attempt at most twenty joint initialization corrections."
  hFlush stdout
  archive <- readFourthArchive source
  saved <- case [s | s <- fourthStates archive, fourthName s == "start"] of [s] -> pure s; _ -> die "missing initialization start"
  let study = fourthStudy archive
      fixture = patchSpread study
      start = fourthMesh saved
      pins = spreadPins fixture
  model <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) start)
  let ready mesh = fst <$> probeInitialization study model mesh
  started <- getCPUTime
  result <- checked (initializeSeparated 20 pins model ready start)
  TIO.putStrLn ("Initialization stopped: " <> initialStop result)
  hFlush stdout
  finished <- getCPUTime
  let constructionSeconds = fromIntegral (finished - started) / 1e12 :: Double
  createDirectoryIfMissing True output
  forM_ (fourthFiles archive) $ \(name, bytes) -> do
    let path = output </> "source" </> name
    createDirectoryIfMissing True (takeDirectory path)
    BL.writeFile path bytes
  records <- forM (zip [0 :: Int ..] (initialHistory result)) $ \(i, mesh) -> do
    let name = "step-" ++ show i
    state <- writeState output name (if i == 0 then "Saved start" else "Initialization correction " <> T.pack (show i)) study (SavedPoint i mesh)
    (_, checks) <- checked (probeInitialization study model mesh)
    rows <- checked (initializationRows pins model start mesh)
    cost <- checked (initializationCost pins model start mesh)
    unless (triangles mesh == triangles start && map sampleMaterial (samples mesh) == map sampleMaterial (samples start) && spreadHeldError fixture mesh == 0) (die "initializer changed material or exact holds")
    pure (object ["id" .= name, "state" .= state, "readiness" .= checks, "constructionCost" .= cost, "constructionRows" .= length rows, "movement" .= initializationMovement start mesh])
  let trace = map attemptValue (initialAttempts result)
      report = object ["gallery" .= ("body-initialization" :: Text), "issue" .= (379 :: Int), "states" .= records, "stopReason" .= initialStop result, "constructionCpuSeconds" .= constructionSeconds, "initializationReady" .= initialReady result, "completedCorrections" .= (length (initialHistory result) - 1), "attempts" .= trace, "correctionBudget" .= (20 :: Int), "fractions" .= initializationFractions, "linearBudget" .= (2000 :: Int), "linearResidualFloor" .= (1e-6 :: Double), "damping" .= (1e-3 :: Double), "targetGap" .= initializationTarget, "barrierClearance" .= initializationClearance, "searchDistance" .= (0.03 :: Double), "activationRange" .= (0.001 :: Double), "movementLimit" .= initializationMovementLimit, "lengthWeight" .= (1e8 :: Double), "gapWeight" .= (1e10 :: Double), "tetherWeight" .= (1 :: Double), "drawingScale" .= (600 :: Double), "acceptedMaterialEndpoint" .= False, "newBarrierSolves" .= (0 :: Int), "physicalThickness" .= (Nothing :: Maybe Double), "continuousMotionChecked" .= False, "wholeCraneChecked" .= False, "sourceStart" .= ("body-fourth-pair/start.fold" :: Text), "sourceFileCount" .= length (fourthFiles archive)]
      bytes = encode report
  BL.writeFile (output </> "checks.json") bytes
  BL.writeFile (output </> "trace.json") (encode trace)
  template <- TIO.readFile "study/fold-material/body-initialization.html"
  TIO.writeFile (destination </> "body-initialization.html") (T.replace "/*BODY_INITIALIZATION_DATA*/null" (TE.decodeUtf8 (BL.toStrict bytes)) template)
  putStrLn ("Wrote " ++ destination </> "body-initialization.html")

attemptValue :: InitialAttempt -> Value
attemptValue attempt = object ["before" .= positions (initialBefore attempt), "proposal" .= fmap positions (initialProposal attempt), "failure" .= initialFailure attempt, "linear" .= fmap linearValue (initialLinear attempt), "trials" .= map trialValue (initialTrials attempt)]
  where
    linearValue r = object ["converged" .= Sparse.linearConverged r, "iterations" .= Sparse.linearIterations r, "residual" .= Sparse.linearResidual r, "threshold" .= Sparse.linearThreshold r]
    trialValue t = object ["scale" .= initialFraction t, "positions" .= positions (initialTrialMesh t), "constructionCost" .= initialTrialCost t, "refusal" .= initialRefusal t]

positions :: MaterialMesh -> [[Double]]
positions = map xyz . initialPositions
