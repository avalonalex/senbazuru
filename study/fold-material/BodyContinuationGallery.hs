-- | A bounded continuation of the saved body correction. The three named
-- triangle pairs are specimen policy, not discovered contacts. Each retained
-- shape gets fresh overlap corners, derivatives and material rows; the order
-- requirements and all nonlinear acceptance limits stay fixed.
--
-- This driver keeps the returned chain separate from the 31 diagnostic trials
-- per attempt. A tiny selected fraction cannot establish equilibrium: that
-- still uses the full proposed movement. Failed quadratics and exhausted
-- searches leave the last valid shape in place, with their evidence exported.
-- See docs/notes/body-short-corrections.md; these are numerical corrections,
-- not instructions or a continuously checked flexible folding motion.
module BodyContinuationGallery (writeBodyContinuation) where

import BodyContactDiagnosis
import BodyContactDirection
import BodyContactGallery (boxAround, drawPair)
import BodyCorrectionArchive
import BodyCorrectionReplay
import BodyDirectionGallery (contactValue, pairWitnesses, reportValue, rowValue)
import BodyPatch
import BodyPatchCheckpoints
import BodyPatchSubdivisionGallery (writeState)
import ContactQuadratic
import Control.Monad (forM, forM_, unless)
import CraneSpread
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.List (sortOn)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldContact qualified as F
import Senbazuru.Explain (explain)
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import SurfaceContact qualified as C
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)

writeBodyContinuation :: FilePath -> FilePath -> IO ()
writeBodyContinuation source destination = do
  let output = destination </> "body-short"
      pairs = [(22, 63), (14, 55), (46, 70)]
      limit = 10 :: Int
  separateOutput source output
  archive <- readBlockedArchive source
  let study = blockedStudy archive
      fixture = patchSpread study
      start = blockedMesh archive
      pins = spreadPins fixture
      free = [i | i <- [0 .. length (samples start) - 1], IM.notMember i pins]
      positions = map (xyz . position) . samples
  model <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) start)
  initialWitnesses <- checked (C.contactWitnesses model start)
  crops <- forM pairs $ \pair -> do
    let ws = pairWitnesses pair initialWitnesses
    anchor <- case sortOn (abs . F.contactGap . C.witnessRow) ws of
      w : _ -> pure (xy (C.witnessLower w))
      [] -> die "the saved body must cover all three original contact pairs"
    let bounds = boxAround [xy p | w <- ws, p <- [C.witnessLower w, C.witnessUpper w]]
        -- One fixed 0.002-unit square per pair, even after the tip moves.
        -- The broader overlap view remains available for trials outside it.
        tip = Box (anchor ^-^ V2 0.001 0.001) (anchor ^+^ V2 0.001 0.001)
    pure (pair, bounds, tip)
  createDirectoryIfMissing True (output </> "source" </> "source")
  forM_ (blockedFiles archive) $ \(name, bytes) -> BL.writeFile (output </> "source" </> name) bytes
  let export name title point = do
        entry <- writeState output name title study point
        ws <- checked (C.contactWitnesses model (savedMesh point))
        forM_ crops $ \(pair@(a, b), bounds, tip) -> do
          cut <- checked (pairSection (savedMesh point) pair)
          forM_ [("pair", bounds), ("tip", tip)] $ \(view, box) ->
            TIO.writeFile (output </> name ++ "-" ++ view ++ "-" ++ show a ++ "-" ++ show b ++ ".svg") (drawPair box (savedMesh point) pair cut (pairWitnesses pair ws))
        pure entry
      -- Each invocation is a new approximation at exactly the retained mesh.
      -- Do not carry the old rows or corners into this recursive call.
      go number current before retained attempts = do
        putStrLn ("Body correction " ++ show number ++ " of " ++ show limit ++ ": refresh rows and contact corners.")
        hFlush stdout
        allWitnesses <- checked (C.contactWitnesses model current)
        let witnesses = concatMap (`pairWitnesses` allWitnesses) pairs
            guards = map (contactGuard pins . C.witnessRow) witnesses
            constraints = [constraintValue w row | (w, row) <- zip witnesses guards]
        rows <- checked (directionRows (spreadHinges fixture) pins model current)
        measured <- checked (measurePatch study (SavedPoint (number - 1) current))
        unless (abs (sum [r * r | (_, r) <- rows] - 2 * patchCost 1e8 measured) < 1e-12) (die "refreshed rows disagree with the unchanged objective")
        let common = ["number" .= number, "before" .= before, "startPositions" .= positions current, "materialRows" .= map rowValue rows, "constraints" .= constraints]
            finish entry reason accepted chain = do
              let trace = attempts ++ [entry]
              BL.writeFile (output </> "trace.json") (encode trace)
              pure (chain, trace, reason, accepted, current)
        case constrainedStepDetailed OriginalWorkingSet 100 1e-3 free rows guards of
          Left err -> finish (object (common ++ ["failure" .= explain err, "directionVerified" .= False, "trials" .= ([] :: [Value]), "selectedState" .= ([] :: [String])])) "quadratic-error" False retained
          Right (delta, report, details) -> do
            let proposal = [position p ^+^ IM.findWithDefault (V3 0 0 0) i delta | (i, p) <- zip [0 ..] (samples current)]
            full <- checked (scaledProposal 1 current proposal)
            movement <- checked (savedMovement (SavedPoint 0 current) (SavedPoint 0 full))
            trials <- checked (replayCorrection study current proposal)
            let verified = quadraticConverged report
                selected = if verified then firstPassing trials else Nothing
                actualDelta = zipWith (\p q -> q ^-^ position p) (samples current) proposal
                actualVector = IM.fromList (zip [0 ..] actualDelta)
                linearGap (a, g) = g + sum [dot v (IM.findWithDefault (V3 0 0 0) i actualVector) | (i, v) <- IM.toList a]
                label k = "attempt-" ++ show number ++ "-trial-" ++ show k
            values <- forM (zip [0 :: Int ..] trials) $ \(k, trial) -> do
              let point = (measuredPoint (replayMeasure trial)) {savedIteration = number}
              state <- export (label k) ("Attempt " <> T.pack (show number) <> " · fraction 1/" <> T.pack (show (2 ^ k :: Integer))) point
              ws <- checked (C.contactWitnesses model (savedMesh point))
              checks <- forM pairs $ \pair@(a, b) -> do
                cut <- checked (pairSection (savedMesh point) pair)
                pure (object ["triangles" .= [a, b], "crosses" .= sectionCrosses cut, "intersectionLength" .= intersectionLength cut, "witnesses" .= map witnessValue (pairWitnesses pair ws)])
              pure (object ["state" .= state, "scale" .= replayScale trial, "movement" .= replayMovement trial, "costDecreased" .= replayCostDecreased trial, "geometryPassed" .= replayGeometryPassed trial, "pairs" .= checks])
            let chosen = [label k | (k, trial) <- zip [0 :: Int ..] trials, Just (replayScale trial) == fmap replayScale selected]
                entry = object (common ++ ["failure" .= (Nothing :: Maybe Text), "proposal" .= map xyz proposal, "correction" .= [xyz (IM.findWithDefault (V3 0 0 0) i delta) | i <- [0 .. length (samples current) - 1]], "quadratic" .= reportValue report, "contacts" .= map contactValue (quadraticContacts details), "fullMovement" .= movement, "directionVerified" .= verified, "guardLinearGaps" .= map linearGap guards, "selectedState" .= chosen, "selectedScale" .= fmap replayScale selected, "trials" .= values])
            case selected of
              Nothing -> finish entry (if verified then "no-passing-trial" else "unverified-quadratic") False retained
              Just candidate -> do
                let point = (measuredPoint (replayMeasure candidate)) {savedIteration = number}
                    next = savedMesh point
                    trace = attempts ++ [entry]
                state <- export ("step-" ++ show number) ("Retained correction " <> T.pack (show number)) point
                let chain = retained ++ [state]
                BL.writeFile (output </> "trace.json") (encode trace)
                putStrLn ("Retained fraction " ++ show (replayScale candidate) ++ "; full movement " ++ show movement ++ ".")
                hFlush stdout
                if movement <= 1e-7
                  then pure (chain, trace, "equilibrium", True, next)
                  else
                    if number >= limit
                      then pure (chain, trace, "correction-budget", False, next)
                      else go (number + 1) next state chain trace
  initial <- export "start" "Saved blocked shape" (SavedPoint 0 start)
  (retained, attempts, reason, accepted, final) <- go 1 start initial [initial] []
  movement <- checked (savedMovement (SavedPoint 0 start) (SavedPoint 0 final))
  let result = object ["gallery" .= ("body-short" :: Text), "sourceIteration" .= (8 :: Int), "iterationLimit" .= limit, "completedCorrections" .= (length retained - 1), "stopReason" .= (reason :: Text), "acceptedEndpoint" .= accepted, "lengthWeight" .= (1e8 :: Double), "contactWeight" .= (1e10 :: Double), "damping" .= (1e-3 :: Double), "quadraticBudget" .= (100 :: Int), "lengthTolerance" .= (1e-5 :: Double), "contactTolerance" .= (1e-7 :: Double), "movementTolerance" .= (1e-7 :: Double), "continuousMotionChecked" .= False, "wholeCraneChecked" .= False, "freeVertices" .= free, "pairs" .= [[a, b] | (a, b) <- pairs], "maxMovementFromStart" .= movement, "states" .= retained, "attempts" .= attempts]
  BL.writeFile (output </> "checks.json") (encode result)
  template <- TIO.readFile "study/fold-material/body-short.html"
  TIO.writeFile (destination </> "body-short.html") (T.replace "/*BODY_SHORT_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode result))) template)
  putStrLn ("Stopped: " ++ T.unpack reason ++ ". Wrote " ++ destination </> "body-short.html")

witnessValue :: C.ContactWitness -> Value
witnessValue w = object ["triangles" .= (let (a, b) = C.witnessTriangles w in [a, b]), "lower" .= xyz (C.witnessLower w), "upper" .= xyz (C.witnessUpper w), "gap" .= F.contactGap (C.witnessRow w)]

constraintValue :: C.ContactWitness -> QuadraticRow -> Value
constraintValue w row = object ["triangles" .= (let (a, b) = C.witnessTriangles w in [a, b]), "rawGap" .= F.contactGap (C.witnessRow w), "floor" .= min 0 (F.contactGap (C.witnessRow w)), "lower" .= xyz (C.witnessLower w), "upper" .= xyz (C.witnessUpper w), "row" .= rowValue row]

xy :: V3 -> V2
xy (V3 x y _) = V2 x y
