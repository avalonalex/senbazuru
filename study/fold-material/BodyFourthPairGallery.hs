-- | One matched material direction with six additional overlap inequalities.
-- Use the start of correction ten in the saved repair loop, not its final
-- retained shape. The first thirteen rows keep their old order; append the
-- six corners of pair 55–93, whose declared lower triangle is 93. A guard
-- preserves min(0, gap), so it is stricter than the final contact tolerance.
--
-- Reuse the loop's actual acceptance and one-repair policy. Only the main
-- quadratic receives new constraints; no weight, hold, budget or tolerance
-- changes, and no vertex 30 plane guard is introduced. The saved proposal is
-- replayed as control without solving it again. Errors and refused fractions
-- remain diagnostic; a small selected fraction does not settle the material.
module BodyFourthPairGallery (writeBodyFourthPair) where

import BodyContactDiagnosis
import BodyContactDirection
import BodyContactGallery (boxAround, drawPair)
import BodyCorrectionArchive
import BodyCorrectionReplay
import BodyDirectionGallery (contactValue, pairWitnesses, reportValue, rowValue)
import BodyLoopArchive
import BodyPatch
import BodyPatchCheckpoints
import BodyPatchSubdivisionGallery (writeState)
import BodyPlaneGuard
import BodyPlaneGuardGallery (trianglePoints, vertexAt, xy)
import BodyRestorationLoop (Candidate (..), TrialContext (..), assess, displacement, margin, repairCandidate)
import ContactQuadratic
import Control.Monad (forM, forM_, unless)
import CraneSpread
import Data.Aeson (Value, encode, object, (.=))
import Data.Bifunctor (first)
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldContact qualified as F
import RestorationSearch
import Senbazuru.Explain (explain)
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (panelTolerance)
import Senbazuru.Origami.Surface
import SurfaceContact qualified as C
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (takeDirectory, (</>))
import System.IO (hFlush, stdout)

data Direction = Direction
  { directionName :: String,
    directionTitle :: Text,
    directionGuards :: [QuadraticRow],
    directionProposal :: Maybe [V3],
    directionRaw :: [V3],
    directionReport :: Maybe Value,
    directionContacts :: [Value],
    directionVerified :: Bool,
    directionFailure :: Maybe Text,
    directionTrials :: [RepairTrial Text Candidate],
    directionSelected :: Maybe (Int, Candidate)
  }

writeBodyFourthPair :: FilePath -> FilePath -> IO ()
writeBodyFourthPair source destination = do
  let output = destination </> "body-fourth-pair"
      oldPairs = [(22, 63), (14, 55), (46, 70)]
  separateOutput source output
  progress "Authenticate the saved repair loop before the one-direction comparison."
  archive <- readLoopArchive source
  before <- case [s | s <- loopStates archive, loopName s == "before"] of
    [s] -> pure s
    _ -> die "missing start of final correction"
  let study = loopStudy archive
      fixture = patchSpread study
      start = loopMesh before
      pins = spreadPins fixture
      free = [i | i <- [0 .. length (samples start) - 1], IM.notMember i pins]
      attempt = loopAttempt archive
  model <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) start)
  let witnesses pairs mesh = do
        ws <- C.contactWitnesses model mesh
        pure (concatMap (`pairWitnesses` ws) pairs)
  oldWitnesses <- checked (witnesses oldPairs start)
  addedWitnesses <- checked (witnesses [(55, 93)] start)
  unless (length oldWitnesses == 12 && length addedWitnesses == 6 && all ((== (93, 55)) . C.witnessTriangles) addedWitnesses) (die "expected twelve old and six ordered new overlap corners")
  plane <- checked (measurePlane start 27 70)
  let target = min 0 (planeDistance plane)
      oldGuards = map (contactGuard pins . C.witnessRow) oldWitnesses ++ [planeGuardRow pins plane]
      addedGuards = map (contactGuard pins . C.witnessRow) addedWitnesses
      newGuards = oldGuards ++ addedGuards
  rows <- checked (directionRows (spreadHinges fixture) pins model start)
  oldRows <- field "materialRows" attempt
  savedGuards <- field "guards" attempt
  unless (oldRows == map rowValue rows && savedGuards == map rowValue oldGuards) (die "comparison changed the saved material or first thirteen guards")
  measured <- checked (measurePatch study (SavedPoint 0 start))
  let baseCost = patchCost 1e8 measured
  unless (abs (sum [r * r | (_, r) <- rows] - 2 * baseCost) < 1e-12) (die "material rows disagree with starting cost")
  let replay d = case (directionVerified d, directionProposal d) of
        (True, Just proposal) -> do
          rawTrials <- checked (replayCorrection study start proposal)
          let guards = directionGuards d
              pairs = if directionName d == "control" then oldPairs else oldPairs ++ [(55, 93)]
              initial = if directionName d == "control" then oldWitnesses else oldWitnesses ++ addedWitnesses
              context = TrialContext study start baseCost guards target (witnesses pairs) initial
          candidates <- forM rawTrials $ \trial -> do
            let mesh = savedMesh (measuredPoint (replayMeasure trial))
            checked (assess study start baseCost (map (`margin` displacement start mesh) guards) (object []) mesh)
          let (visited, selected) = searchWithRestoration candidatePasses (first explain . repairCandidate context) candidates
          pure d {directionTrials = visited, directionSelected = selected}
        _ -> pure d
  savedProposal <- field "proposal" attempt >>= traverse vector
  savedRaw <- field "correction" attempt >>= traverse vector
  savedReport <- field "quadratic" attempt
  savedContacts <- field "contacts" attempt
  control <- replay (Direction "control" "Saved direction · 13 guards" oldGuards (Just savedProposal) savedRaw (Just savedReport) savedContacts True Nothing [] Nothing)
  -- This also regression-checks the extracted shared acceptance/repair policy.
  -- Names of new exports differ, but the source's checks and decisions must not.
  checkControl attempt control
  progress "Compute one quadratic with nineteen guards; retain the original solver policy."
  added <- case constrainedStepDetailed OriginalWorkingSet 100 1e-3 free rows newGuards of
    Left err -> pure (Direction "added" "Six additional overlap guards" newGuards Nothing [] Nothing [] False (Just (explain err)) [] Nothing)
    Right (delta, report, details) -> do
      let raw = [IM.findWithDefault (V3 0 0 0) i delta | i <- [0 .. length (samples start) - 1]]
          proposal = zipWith (^+^) (map position (samples start)) raw
          verified = quadraticConverged report
      replay (Direction "added" "Six additional overlap guards" newGuards (Just proposal) raw (Just (reportValue report)) (map contactValue (quadraticContacts details)) verified (if verified then Nothing else Just "Unverified quadratic; no trial selected") [] Nothing)
  let variants = [control, added]
      nearby = start : [candidateMesh c | d <- variants, Just (k, _) <- [directionSelected d], (i, trial) <- zip [0 :: Int ..] (directionTrials d), i >= k - 1, c <- originalTrial trial : case repairedTrial trial of Just (Right m) -> [m]; _ -> []]
  points <- concat <$> traverse (trianglePoints start) [55, 93]
  tipPoints <- fmap concat $ forM nearby $ \mesh -> do
    v <- vertexAt mesh 30
    cut <- checked (pairSection mesh (55, 93))
    ws <- checked (witnesses [(55, 93)] mesh)
    pure (v : intersectionEnds cut ++ [C.witnessLower w | w <- ws, abs (F.contactGap (C.witnessRow w)) < panelTolerance])
  let bounds = boxAround (map xy points)
      tipBounds = boxAround (map xy tipPoints)
  createDirectoryIfMissing True output
  forM_ (loopFiles archive) $ \(name, bytes) -> do
    let path = output </> "source" </> name
    createDirectoryIfMissing True (takeDirectory path)
    BL.writeFile path bytes
  let export name title mesh = do
        state <- writeState output name title study (SavedPoint 0 mesh)
        cut <- checked (pairSection mesh (55, 93))
        m30 <- checked (measurePlane mesh 30 93)
        m27 <- checked (measurePlane mesh 27 70)
        ws <- checked (witnesses [(55, 93)] mesh)
        forM_ [("pair", bounds), ("tip", tipBounds)] $ \(view, box) ->
          TIO.writeFile (output </> name ++ "-" ++ view ++ ".svg") (drawPair box mesh (55, 93) cut ws)
        pure (object ["state" .= state, "plane30" .= planeDistance m30, "plane27" .= planeDistance m27, "firstDistances" .= firstDistances cut, "secondDistances" .= secondDistances cut, "crosses55_93" .= sectionCrosses cut, "intersectionLength" .= intersectionLength cut, "minimumPairGap" .= (case map (F.contactGap . C.witnessRow) ws of [] -> Nothing; gaps -> Just (minimum gaps)), "pairWitnesses" .= [object ["triangles" .= (let (a, b) = C.witnessTriangles w in [a, b]), "lower" .= xyz (C.witnessLower w), "upper" .= xyz (C.witnessUpper w), "gap" .= F.contactGap (C.witnessRow w), "row" .= rowValue (contactGuard pins (C.witnessRow w))] | w <- ws]])
  initial <- export "start" "Saved start of correction ten" start
  entries <- forM variants $ \d -> do
    let label k = directionName d ++ "-" ++ show k
    trials <- forM (zip3 [0 :: Int ..] replayFractions (directionTrials d)) $ \(k, scale, trial) -> do
      record <- export (label k) (directionTitle d <> " · 1/" <> T.pack (show (2 ^ k :: Integer))) (candidateMesh (originalTrial trial))
      repair <- case repairedTrial trial of
        Nothing -> pure Nothing
        Just (Left err) -> pure (Just (object ["failure" .= err]))
        Just (Right fixed) -> do
          result <- export (label k ++ "-repair") "One repair of this fraction" (candidateMesh fixed)
          pure (Just (object ["failure" .= (Nothing :: Maybe Text), "record" .= result, "checks" .= candidateDetails fixed, "passed" .= candidatePasses fixed]))
      pure (object ["scale" .= scale, "record" .= record, "checks" .= candidateDetails (originalTrial trial), "passed" .= candidatePasses (originalTrial trial), "restoration" .= repair])
    fullMovement <- case directionProposal d of
      Nothing -> pure Nothing
      Just proposal -> do
        full <- checked (scaledProposal 1 start proposal)
        Just <$> checked (savedMovement (SavedPoint 0 start) (SavedPoint 0 full))
    let chosen = fmap (\(k, _) -> label k ++ case drop k (directionTrials d) of RepairTrial _ (Just (Right _)) : _ -> "-repair"; _ -> "") (directionSelected d)
        selectedScale = fmap (\(k, _) -> 2 ** negate (fromIntegral k) :: Double) (directionSelected d)
    progress (directionName d ++ ": selected " ++ show chosen ++ "; full movement " ++ show fullMovement)
    pure (object ["id" .= directionName d, "title" .= directionTitle d, "guards" .= map rowValue (directionGuards d), "proposal" .= fmap (map xyz) (directionProposal d), "correction" .= map xyz (directionRaw d), "quadratic" .= directionReport d, "contacts" .= directionContacts d, "directionVerified" .= directionVerified d, "failure" .= directionFailure d, "fullMovement" .= fullMovement, "selectedScale" .= selectedScale, "selectedState" .= chosen, "acceptedEndpoint" .= (isJust chosen && maybe False (<= 1e-7) fullMovement), "trials" .= trials])
  let result =
        object
          [ "gallery" .= ("body-fourth-pair" :: Text),
            "issue" .= (363 :: Int),
            "newQuadratics" .= (1 :: Int),
            "continuationSteps" .= (0 :: Int),
            "sourceAttempt" .= (10 :: Int),
            "sourceStart" .= ("step-9.fold" :: Text),
            "start" .= initial,
            "startPositions" .= map (xyz . position) (samples start),
            "freeVertices" .= free,
            "materialRows" .= map rowValue rows,
            "oldGuardCount" .= (13 :: Int),
            "addedGuardCount" .= (6 :: Int),
            "planeGuardIndex" .= (12 :: Int),
            "planeTarget" .= target,
            "constraints" .= [object ["guard" .= i, "triangles" .= (let (a, b) = C.witnessTriangles w in [a, b]), "rawGap" .= F.contactGap (C.witnessRow w), "lower" .= xyz (C.witnessLower w), "upper" .= xyz (C.witnessUpper w)] | (i, w) <- zip ([0 .. 11] ++ [13 .. 18 :: Int]) (oldWitnesses ++ addedWitnesses)],
            "directions" .= entries,
            "fractions" .= replayFractions,
            "maxRepairsPerTrial" .= (1 :: Int),
            "contactTolerance" .= panelTolerance,
            "lengthTolerance" .= (1e-5 :: Double),
            "guardResidualTolerance" .= (1e-12 :: Double),
            "movementTolerance" .= (1e-7 :: Double),
            "lengthWeight" .= (1e8 :: Double),
            "contactWeight" .= (1e10 :: Double),
            "damping" .= (1e-3 :: Double),
            "quadraticBudget" .= (100 :: Int),
            "drawingScale" .= (600 :: Double),
            "overlapBounds" .= boxValue bounds,
            "tipBounds" .= boxValue tipBounds,
            "continuousMotionChecked" .= False,
            "wholeCraneChecked" .= False
          ]
      bytes = encode result
  BL.writeFile (output </> "checks.json") bytes
  template <- TIO.readFile "study/fold-material/body-fourth-pair.html"
  TIO.writeFile (destination </> "body-fourth-pair.html") (T.replace "/*BODY_FOURTH_DATA*/null" (TE.decodeUtf8 (BL.toStrict bytes)) template)
  progress ("Wrote " ++ destination </> "body-fourth-pair.html")

checkControl :: Value -> Direction -> IO ()
checkControl attempt d = do
  trials <- field "trials" attempt :: IO [Value]
  unless (length trials == length (directionTrials d)) (die "shared search changed control trial count")
  forM_ (zip trials (directionTrials d)) $ \(record, trial) -> do
    checks <- field "checks" record
    passed <- field "passed" record
    unless (checks == candidateDetails (originalTrial trial) && passed == candidatePasses (originalTrial trial)) (die "shared search changed the saved control checks")
    restored <- field "restoration" record :: IO (Maybe Value)
    case (restored, repairedTrial trial) of
      (Nothing, Nothing) -> pure ()
      (Just old, Just (Left err)) -> do
        failure <- field "failure" old
        unless (failure == err) (die "shared search changed control repair refusal")
      (Just old, Just (Right fixed)) -> do
        expected <- field "checks" old
        accepted <- field "passed" old
        unless (expected == candidateDetails fixed && accepted == candidatePasses fixed) (die "shared search changed a saved control repair")
      _ -> die "shared search changed the control repair decision"
  scale <- field "selectedScale" attempt
  unless (fmap (\(k, _) -> 2 ** negate (fromIntegral k) :: Double) (directionSelected d) == Just scale) (die "shared search changed the selected control fraction")

boxValue :: Box -> [[Double]]
boxValue (Box (V2 a b) (V2 c d)) = [[a, b], [c, d]]

vector :: [Double] -> IO V3
vector [x, y, z] = pure (V3 x y z)
vector _ = die "saved direction must contain three coordinates per vertex"

progress :: String -> IO ()
progress message = putStrLn message >> hFlush stdout
