-- | Up to ten material corrections from the saved fresh repaired state.
-- Each accepted shape gets a fresh quadratic (a local squared-error model)
-- with the same three pairs and moving-plane guard. A refused fraction may
-- receive ONE projection restoring that direction's starting plane distance.
-- Both raw and repaired shapes must pass actual geometry, cost descent and
-- the retained linear guards. Repair also checks overlap derivatives refreshed
-- at the refused shape; changing overlap topology remains diagnostic.
--
-- These are numerical corrections, not a continuously checked folding motion.
-- A tiny repair or selected fraction does not settle the material: equilibrium
-- still requires the verified FULL material proposal to be small. Source data
-- is authenticated before output, and no production solver policy is changed.
module BodyRestorationLoop
  ( writeBodyRestorationLoop,
    Candidate (..),
    TrialContext (..),
    assess,
    repairCandidate,
    displacement,
    margin,
  )
where

import BodyContactDiagnosis
import BodyContactDirection
import BodyContactGallery (boxAround)
import BodyContactRestoration
import BodyCorrectionArchive
import BodyCorrectionReplay
import BodyDirectionGallery (contactValue, pairWitnesses, reportValue, rowValue)
import BodyFreshArchive
import BodyPatch
import BodyPatchCheckpoints
import BodyPatchSubdivision (seedPassed)
import BodyPatchSubdivisionGallery (writeState)
import BodyPlaneGuard
import BodyPlaneGuardGallery (drawContact, trianglePoints, vertexAt, xy)
import BodyRestorationArchive
import ContactQuadratic
import Control.Monad (forM, forM_, unless)
import CraneSpread
import Data.Aeson (Value, encode, object, (.=))
import Data.Bifunctor (first)
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldContact qualified as F
import RestorationSearch
import Senbazuru.Explain (explain)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (panelTolerance)
import Senbazuru.Origami.Surface
import SurfaceContact qualified as C
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (takeDirectory, (</>))
import System.IO (hFlush, stdout)

data Candidate = Candidate
  { candidateMesh :: MaterialMesh,
    candidatePasses :: Bool,
    candidateDetails :: Value
  }

-- | Inputs shared by every fraction of one material direction. The comparison
-- may append another pair, but raw/repair acceptance must keep the same policy.
data TrialContext = TrialContext
  { trialStudy :: BodyPatch,
    trialStart :: MaterialMesh,
    trialBaseCost :: Double,
    trialGuards :: [QuadraticRow],
    trialPlaneTarget :: Double,
    trialWitnesses :: MaterialMesh -> Either C.ContactError [C.ContactWitness],
    trialInitialWitnesses :: [C.ContactWitness]
  }

pairs :: [(Int, Int)]
pairs = [(22, 63), (14, 55), (46, 70)]

positions :: MaterialMesh -> [[Double]]
positions = map (xyz . position) . samples

displacement :: MaterialMesh -> MaterialMesh -> IM.IntMap V3
displacement a b = IM.fromList (zip [0 ..] (zipWith (\p q -> position q ^-^ position p) (samples a) (samples b)))

margin :: QuadraticRow -> IM.IntMap V3 -> Double
margin (row, gap) delta = gap + sum [dot g (IM.findWithDefault (V3 0 0 0) i delta) | (i, g) <- IM.toList row]

-- | The same actual acceptance test for raw and repaired shapes. A repair
-- adds its refreshed guards; it never removes the original direction's guards.
assess :: BodyPatch -> MaterialMesh -> Double -> [Double] -> Value -> MaterialMesh -> Either SpreadError Candidate
assess study start beforeCost gaps extra mesh = do
  measured <- measurePatch study (SavedPoint 0 mesh)
  geometry <- seedPassed study mesh
  movement <- savedMovement (SavedPoint 0 start) (SavedPoint 0 mesh)
  let guards = all (>= -1e-12) gaps
      cheaper = patchCost 1e8 measured < beforeCost
  pure (Candidate mesh (guards && geometry && cheaper) (object ["guardsPassed" .= guards, "guardMargins" .= gaps, "geometryPassed" .= geometry, "costDecreased" .= cheaper, "movement" .= movement, "extra" .= extra]))

-- | Exactly one existing vertex 27–plane 70 repair. Refreshed overlap guards
-- include every named pair, including a newly added pair in a comparison.
-- A topology change is diagnostic; it never authorizes dropping a guard.
repairCandidate :: TrialContext -> Candidate -> Either SpreadError Candidate
repairCandidate context candidate = do
  let study = trialStudy context
      start = trialStart context
      fixture = patchSpread study
      pins = spreadPins fixture
      baseCost = trialBaseCost context
      guards = trialGuards context
      target = trialPlaneTarget context
      witnesses = trialWitnesses context
      ws = trialInitialWitnesses context
      identity w = (C.witnessTriangles w, map fst (F.contactGradient (C.witnessRow w)))
  let trial = candidateMesh candidate
  plane <- first (SpreadError . explain) (measurePlane trial 27 70)
  unless (planeDistance plane < target) (Left (SpreadError "No plane-distance loss to restore"))
  ws1 <- first (SpreadError . explain) (witnesses trial)
  unless (map identity ws == map identity ws1) (Left (SpreadError "Refused trial changed overlap witness topology"))
  correction <- first (SpreadError . explain) (restorePlane pins target plane)
  let repaired = trial {samples = [p {position = position p ^+^ IM.findWithDefault (V3 0 0 0) i correction} | (i, p) <- zip [0 ..] (samples trial)]}
      installed = displacement trial repaired
      refreshed = map (contactGuard pins . C.witnessRow) ws1
      repairPlane = (planeGradient plane, planeDistance plane - target)
      gaps = map (`margin` displacement start repaired) guards ++ map (`margin` installed) refreshed ++ [margin repairPlane installed]
  ws2 <- first (SpreadError . explain) (witnesses repaired)
  unless (map identity ws1 == map identity ws2) (Left (SpreadError "Repair changed overlap witness topology"))
  repairMovement <- savedMovement (SavedPoint 0 trial) (SavedPoint 0 repaired)
  planeAfter <- first (SpreadError . explain) (measurePlane repaired 27 70)
  old <- measurePatch study (SavedPoint 0 trial)
  new <- measurePatch study (SavedPoint 0 repaired)
  let extra = object ["targetDistance" .= target, "refusedDistance" .= planeDistance plane, "restoredDistance" .= planeDistance planeAfter, "gradient" .= rowValue (planeGradient plane, planeDistance plane), "refreshedGuards" .= map rowValue refreshed, "rawCorrection" .= [xyz (IM.findWithDefault (V3 0 0 0) i correction) | i <- [0 .. length (samples trial) - 1]], "repairMovement" .= repairMovement, "costChangeFromTrial" .= (patchCost 1e8 new - patchCost 1e8 old)]
  assess study start baseCost gaps extra repaired

writeBodyRestorationLoop :: FilePath -> FilePath -> IO ()
writeBodyRestorationLoop source destination = do
  let output = destination </> "body-restoration-loop"
      limit = 10 :: Int
  separateOutput source output
  putStrLn "Authenticate the saved fresh repair before continuing."
  hFlush stdout
  parent <- readFreshArchive (source </> "source")
  controls <- case [ts | ("fresh", _, ts) <- freshDirections parent] of [ts] -> pure ts; _ -> die "missing fresh direction"
  let control name = case [m | (n, m, _) <- controls, n == name] of [m] -> pure m; _ -> die "missing fresh repair control"
  half <- control "fresh-8"
  refused <- control "fresh-7"
  archive <- checkRestorationArchive source "body-fresh-restoration" (RestorationSource (freshStudy parent) (freshStart parent) half refused (freshReport parent) (freshFiles parent))
  let study = restorationStudy archive
      fixture = patchSpread study
      start = restorationMesh archive
      pins = spreadPins fixture
      free = [i | i <- [0 .. length (samples start) - 1], IM.notMember i pins]
  model <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) start)
  let witnesses mesh = do ws <- C.contactWitnesses model mesh; pure (concatMap (`pairWitnesses` ws) pairs)
  pairPoints <- concat <$> traverse (trianglePoints start) [46, 70]
  vertex <- vertexAt start 27
  cut <- checked (pairSection start (46, 70))
  initialWitnesses <- checked (witnesses start)
  let pairBox = boxAround (map xy pairPoints)
      tipBox = boxAround (map xy (vertex : intersectionEnds cut ++ [C.witnessLower w | w <- pairWitnesses (46, 70) initialWitnesses, F.contactGap (C.witnessRow w) < 0]))
  createDirectoryIfMissing True output
  forM_ (restorationFiles archive) $ \(name, bytes) -> do
    let path = output </> "source" </> name
    createDirectoryIfMissing True (takeDirectory path)
    BL.writeFile path bytes
  let export name title number mesh = do
        state <- writeState output name title study (SavedPoint number mesh)
        plane <- checked (measurePlane mesh 27 70)
        section <- checked (pairSection mesh (46, 70))
        ws <- checked (witnesses mesh)
        forM_ [("pair", pairBox), ("tip", tipBox)] $ \(view, box) -> do
          drawing <- drawContact box mesh section (pairWitnesses (46, 70) ws)
          TIO.writeFile (output </> name ++ "-" ++ view ++ ".svg") drawing
        pure (object ["state" .= state, "planeDistance" .= planeDistance plane, "planeMargin" .= (planeDistance plane + panelTolerance), "crosses46_70" .= sectionCrosses section, "intersectionLength" .= intersectionLength section])
      go number current before retained attempts = do
        putStrLn ("Material correction " ++ show number ++ " of ten: refresh equations and guards.")
        hFlush stdout
        ws <- checked (witnesses current)
        initial <- checked (measurePlane current 27 70)
        measured <- checked (measurePatch study (SavedPoint 0 current))
        let guards = map (contactGuard pins . C.witnessRow) ws ++ [planeGuardRow pins initial]
            baseCost = patchCost 1e8 measured
            target = min 0 (planeDistance initial)
            common = ["number" .= number, "before" .= before, "startPositions" .= positions current, "targetDistance" .= target]
            finish entry reason = do
              let trace = attempts ++ [entry]
              BL.writeFile (output </> "trace.json") (encode trace)
              pure (retained, trace, reason, False, current)
        if length ws /= 12 || planeDistance initial < negate panelTolerance || planeDistance initial >= 0
          then finish (object (common ++ ["failure" .= ("Contact configuration left the studied regime" :: Text), "directionVerified" .= False, "trials" .= ([] :: [Value])])) "contact-regime"
          else do
            rows <- checked (directionRows (spreadHinges fixture) pins model current)
            unless (abs (sum [r * r | (_, r) <- rows] - 2 * baseCost) < 1e-12) (die "material rows disagree with actual cost")
            let setup = common ++ ["materialRows" .= map rowValue rows, "guards" .= map rowValue guards, "constraints" .= [object ["triangles" .= (let (a, b) = C.witnessTriangles w in [a, b]), "vertices" .= map fst (F.contactGradient (C.witnessRow w)), "rawGap" .= F.contactGap (C.witnessRow w)] | w <- ws]]
            case constrainedStepDetailed OriginalWorkingSet 100 1e-3 free rows guards of
              Left err -> finish (object (setup ++ ["failure" .= explain err, "directionVerified" .= False, "trials" .= ([] :: [Value])])) "quadratic-error"
              Right (delta, report, details) -> do
                let proposal = [position p ^+^ IM.findWithDefault (V3 0 0 0) i delta | (i, p) <- zip [0 ..] (samples current)]
                    verified = quadraticConverged report
                    solved = setup ++ ["proposal" .= map xyz proposal, "correction" .= [xyz (IM.findWithDefault (V3 0 0 0) i delta) | i <- [0 .. length (samples current) - 1]], "quadratic" .= reportValue report, "contacts" .= map contactValue (quadraticContacts details), "directionVerified" .= verified]
                full <- checked (scaledProposal 1 current proposal)
                movement <- checked (savedMovement (SavedPoint 0 current) (SavedPoint 0 full))
                if not verified
                  then finish (object (solved ++ ["failure" .= ("Unverified quadratic; no candidate installed" :: Text), "fullMovement" .= movement, "trials" .= ([] :: [Value])])) "unverified-quadratic"
                  else do
                    rawTrials <- checked (replayCorrection study current proposal)
                    candidates <- forM rawTrials $ \trial -> do
                      let mesh = savedMesh (measuredPoint (replayMeasure trial))
                      checked (assess study current baseCost (map (`margin` displacement current mesh) guards) (object []) mesh)
                    let context = TrialContext study current baseCost guards target witnesses ws
                        repair = first explain . repairCandidate context
                        (visited, chosen) = searchWithRestoration candidatePasses repair candidates
                        label k = "attempt-" ++ show number ++ "-trial-" ++ show k
                    trials <- forM (zip3 [0 :: Int ..] replayFractions visited) $ \(k, scale, trial) -> do
                      raw <- export (label k) ("Original fraction 1/" <> T.pack (show (2 ^ k :: Integer))) number (candidateMesh (originalTrial trial))
                      restored <- case repairedTrial trial of
                        Nothing -> pure Nothing
                        Just (Left err) -> pure (Just (object ["failure" .= err]))
                        Just (Right repaired) -> do
                          state <- export (label k ++ "-repair") "One repair of this fraction" number (candidateMesh repaired)
                          pure (Just (object ["failure" .= (Nothing :: Maybe Text), "record" .= state, "checks" .= candidateDetails repaired, "passed" .= candidatePasses repaired]))
                      pure (object ["scale" .= scale, "record" .= raw, "checks" .= candidateDetails (originalTrial trial), "passed" .= candidatePasses (originalTrial trial), "restoration" .= restored])
                    let selectedState = fmap (\(k, _) -> label k ++ case drop k visited of RepairTrial _ (Just (Right _)) : _ -> "-repair"; _ -> "") chosen
                        entry = object (solved ++ ["failure" .= (Nothing :: Maybe Text), "fullMovement" .= movement, "selectedState" .= selectedState, "selectedScale" .= fmap (\(k, _) -> 2 ** negate (fromIntegral k) :: Double) chosen, "trials" .= trials])
                    case chosen of
                      Nothing -> finish entry "no-passing-trial"
                      Just (_, selected) -> do
                        let next = candidateMesh selected; trace = attempts ++ [entry]
                        state <- export ("step-" ++ show number) ("Retained correction " <> T.pack (show number)) number next
                        let chain = retained ++ [state]
                        BL.writeFile (output </> "trace.json") (encode trace)
                        putStrLn ("Retained " ++ show selectedState ++ "; full material movement " ++ show movement ++ ".")
                        hFlush stdout
                        if movement <= 1e-7
                          then pure (chain, trace, "equilibrium", True, next)
                          else
                            if number >= limit
                              then pure (chain, trace, "correction-budget", False, next)
                              else go (number + 1) next state chain trace
  initial <- export "start" "Saved fresh repaired state" 0 start
  (retained, attempts, reason, accepted, final) <- go 1 start initial [initial] []
  movement <- checked (savedMovement (SavedPoint 0 start) (SavedPoint 0 final))
  let result = object ["gallery" .= ("body-restoration-loop" :: Text), "issue" .= (356 :: Int), "iterationLimit" .= limit, "completedCorrections" .= (length retained - 1), "stopReason" .= (reason :: Text), "acceptedEndpoint" .= accepted, "source" .= restorationReport archive, "states" .= retained, "attempts" .= attempts, "maxMovementFromStart" .= movement, "freeVertices" .= free, "fractions" .= replayFractions, "maxRepairsPerTrial" .= (1 :: Int), "contactTolerance" .= panelTolerance, "lengthTolerance" .= (1e-5 :: Double), "movementTolerance" .= (1e-7 :: Double), "guardResidualTolerance" .= (1e-12 :: Double), "lengthWeight" .= (1e8 :: Double), "contactWeight" .= (1e10 :: Double), "damping" .= (1e-3 :: Double), "quadraticBudget" .= (100 :: Int), "drawingScale" .= (600 :: Double), "continuousMotionChecked" .= False, "wholeCraneChecked" .= False]
  BL.writeFile (output </> "checks.json") (encode result)
  template <- TIO.readFile "study/fold-material/body-restoration-loop.html"
  TIO.writeFile (destination </> "body-restoration-loop.html") (T.replace "/*BODY_LOOP_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode result))) template)
  putStrLn ("Stopped: " ++ T.unpack reason ++ ". Wrote " ++ destination </> "body-restoration-loop.html")
