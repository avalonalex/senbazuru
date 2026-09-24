-- | Export the constraint-first construction with the same readiness gates as
-- the earlier weighted attempt. The large linear audit is a separate file so
-- inspecting a drawing does not parse thousands of constraint rows. A refused
-- full proposal is explicitly diagnostic and never joins the retained history.
module BodyFeasibilityGallery (writeBodyFeasibility) where

import BodyCorrectionArchive
import BodyFourthArchive
import BodyInitialization
import BodyInitializationCheck (probeInitialization)
import BodyPatch
import BodyPatchCheckpoints
import BodyPatchSubdivisionGallery (writeState)
import ContactQuadratic qualified as Q
import Control.Monad (forM, forM_, unless, when)
import CraneSpread
import Data.Aeson (Value, encode, object, toJSON, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FeasibleInitialization
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface
import SurfaceContact qualified as C
import System.CPUTime (getCPUTime)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (takeDirectory, (</>))
import System.IO (hFlush, stdout)

writeBodyFeasibility :: FilePath -> FilePath -> IO ()
writeBodyFeasibility source destination = do
  let output = destination </> "body-feasibility"
  separateOutput source output
  putStrLn "Authenticate the saved start; try at most twenty constraint-first corrections."
  hFlush stdout
  archive <- readFourthArchive source
  start <- case [fourthMesh s | s <- fourthStates archive, fourthName s == "start"] of [s] -> pure s; _ -> die "missing feasibility start"
  let study = fourthStudy archive
      fixture = patchSpread study
      pins = spreadPins fixture
  model <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) start)
  started <- getCPUTime
  result <- checked (feasibleInitialization 20 pins model (fmap fst . probeInitialization study model) start)
  TIO.putStrLn ("Feasibility initialization stopped: " <> feasibleStop result)
  hFlush stdout
  finished <- getCPUTime
  let seconds = fromIntegral (finished - started) / 1e12 :: Double
  createDirectoryIfMissing True output
  forM_ (fourthFiles archive) $ \(name, bytes) -> do
    let path = output </> "source" </> name
    createDirectoryIfMissing True (takeDirectory path)
    BL.writeFile path bytes
  let record name title retained i mesh = do
        state <- writeState output name title study (SavedPoint i mesh)
        (_, checks) <- checked (probeInitialization study model mesh)
        deficit <- checked (clearanceDeficit model mesh)
        unless (triangles mesh == triangles start && map sampleMaterial (samples mesh) == map sampleMaterial (samples start) && spreadHeldError fixture mesh == 0) (die "feasibility changed material or exact holds")
        when retained $ maybe (pure ()) (die . T.unpack) (feasibilityRefusal pins start mesh)
        pure (object ["id" .= name, "state" .= state, "readiness" .= checks, "retained" .= retained, "worstDeficit" .= deficit, "movement" .= initializationMovement start mesh])
  history <- forM (zip [0 :: Int ..] (feasibleHistory result)) $ \(i, mesh) -> record ("step-" ++ show i) (if i == 0 then "Saved start" else "Retained correction " <> T.pack (show i)) True i mesh
  diagnostic <- case reverse (feasibleAttempts result) of
    attempt : _
      | Just proposal <- feasibleProposal attempt,
        Just _ <- feasibleFailure attempt -> do
          state <- record "unverified-proposal" "Unverified full proposal · never retained" False (length (feasibleAttempts result)) proposal
          pure [state]
    _ -> pure []
  let report = object ["gallery" .= ("body-feasibility" :: Text), "issue" .= (381 :: Int), "states" .= history, "diagnostics" .= diagnostic, "attempts" .= map summaryValue (feasibleAttempts result), "stopReason" .= feasibleStop result, "constructionCpuSeconds" .= seconds, "initializationReady" .= feasibleReady result, "completedCorrections" .= (length (feasibleHistory result) - 1), "correctionBudget" .= (20 :: Int), "fractions" .= initializationFractions, "quadraticBudget" .= feasibilityInnerBudget, "coordinateScale" .= feasibilityScale, "damping" .= feasibilityDamping, "targetGap" .= initializationTarget, "barrierClearance" .= initializationClearance, "searchDistance" .= (0.03 :: Double), "activationRange" .= (0.001 :: Double), "movementLimit" .= initializationMovementLimit, "relativeLengthLimit" .= (1e-5 :: Double), "drawingScale" .= (600 :: Double), "acceptedMaterialEndpoint" .= False, "newBarrierSolves" .= (0 :: Int), "continuousMotionChecked" .= False, "physicalThickness" .= (Nothing :: Maybe Double), "wholeCraneChecked" .= False, "sourceFileCount" .= length (fourthFiles archive), "sourceStart" .= ("body-fourth-pair/start.fold" :: Text)]
      bytes = encode report
  BL.writeFile (output </> "checks.json") bytes
  BL.writeFile (output </> "trace.json") (encode (map attemptValue (feasibleAttempts result)))
  template <- TIO.readFile "study/fold-material/body-feasibility.html"
  TIO.writeFile (destination </> "body-feasibility.html") (T.replace "/*BODY_FEASIBILITY_DATA*/null" (TE.decodeUtf8 (BL.toStrict bytes)) template)
  putStrLn ("Wrote " ++ destination </> "body-feasibility.html")

summaryValue :: FeasibleAttempt -> Value
summaryValue a = object ["failure" .= feasibleFailure a, "quadratic" .= fmap reportValue (feasibleReport a), "constraints" .= length (problemConstraints (feasibleProblem a)), "trials" .= [object ["scale" .= feasibleFraction t, "worstDeficit" .= feasibleTrialDeficit t, "refusal" .= feasibleTrialRefusal t] | t <- feasibleTrials a]]

attemptValue :: FeasibleAttempt -> Value
attemptValue a =
  let p = feasibleProblem a
   in object ["before" .= positions (feasibleBefore a), "auxiliary" .= problemAuxiliary p, "startingDeficit" .= problemDeficit p, "free" .= problemFree p, "constraints" .= [object ["name" .= feasibleName c, "gradient" .= vectorValue (feasibleGradient c), "offset" .= feasibleOffset c] | c <- problemConstraints p], "normalizedDelta" .= fmap vectorValue (feasibleDelta a), "proposal" .= fmap positions (feasibleProposal a), "failure" .= feasibleFailure a, "quadratic" .= fmap reportValue (feasibleReport a), "details" .= fmap detailsValue (feasibleDetails a), "trials" .= [object ["scale" .= feasibleFraction t, "positions" .= positions (feasibleTrialMesh t), "worstDeficit" .= feasibleTrialDeficit t, "refusal" .= feasibleTrialRefusal t] | t <- feasibleTrials a]]

reportValue :: Q.QuadraticReport -> Value
reportValue r = object ["converged" .= Q.quadraticConverged r, "iterations" .= Q.quadraticIterations r, "violation" .= Q.quadraticViolation r, "complementarity" .= Q.quadraticComplementarity r, "balance" .= Q.quadraticBalance r, "active" .= Q.quadraticActive r]

detailsValue :: Q.QuadraticDetails -> Value
detailsValue d = object ["contacts" .= [object ["id" .= Q.contactConstraint r, "sources" .= Q.contactSources r, "selected" .= Q.contactSelected r, "gap" .= Q.contactGap r, "multiplier" .= Q.contactNormalizedMultiplier r, "responseScale" .= Q.contactResponseScale r] | r <- Q.quadraticContacts d], "exchanges" .= length (Q.quadraticExchanges d)]

vectorValue :: IM.IntMap V3 -> Value
vectorValue v = toJSON [object ["vertex" .= i, "vector" .= xyz p] | (i, p) <- IM.toList v]

positions :: MaterialMesh -> [[Double]]
positions = map xyz . initialPositions
