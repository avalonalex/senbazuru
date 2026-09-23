-- | One new material direction at the saved repaired 1/128 trial.
-- Rebuild the material rows and the same three-pair overlap guards plus the
-- vertex 27–plane 70 guard at that state. Solve just one local quadratic, then
-- test the full direction and thirty halvings against unchanged actual costs
-- and all-pair geometry. These numerical trials are not a folding motion.
--
-- The quadratic must be verified before any trial is selected. A tiny usable
-- fraction alone cannot establish equilibrium: retain the full movement test.
-- Source restoration and earlier controls are authenticated before any output.
module BodyFreshGallery (writeBodyFresh) where

import BodyContactDiagnosis
import BodyContactDirection
import BodyContactGallery (boxAround)
import BodyCorrectionArchive
import BodyCorrectionReplay
import BodyDirectionGallery (contactValue, pairWitnesses, reportValue, rowValue)
import BodyPatch
import BodyPatchCheckpoints
import BodyPatchSubdivisionGallery (writeState)
import BodyPlaneGuard
import BodyPlaneGuardGallery (drawContact, trianglePoints, vertexAt, xy)
import BodyRestorationArchive
import ContactQuadratic
import Control.Monad (forM, forM_, unless)
import CraneSpread
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldContact qualified as F
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

data Compared = Compared
  { comparedName :: String,
    comparedTitle :: Text,
    comparedProposal :: Maybe [V3],
    comparedCorrection :: IM.IntMap V3,
    comparedReport :: Maybe Value,
    comparedContacts :: [Value],
    comparedVerified :: Bool,
    comparedFailure :: Maybe Text,
    comparedTrials :: [ReplayCandidate]
  }

writeBodyFresh :: FilePath -> FilePath -> IO ()
writeBodyFresh source destination = do
  let output = destination </> "body-fresh"
      pairs = [(22, 63), (14, 55), (46, 70)]
  separateOutput source output
  putStrLn "Validate the repaired archive, then compute one fresh direction."
  hFlush stdout
  archive <- readRestorationArchive source
  let study = restorationStudy archive
      fixture = patchSpread study
      start = restorationMesh archive
      pins = spreadPins fixture
      free = [i | i <- [0 .. length (samples start) - 1], IM.notMember i pins]
      propose delta = [position p ^+^ IM.findWithDefault (V3 0 0 0) i delta | (i, p) <- zip [0 ..] (samples start)]
  model <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) start)
  allWitnesses <- checked (C.contactWitnesses model start)
  let ws = concatMap (`pairWitnesses` allWitnesses) pairs
      guards = map (contactGuard pins . C.witnessRow) ws
      constraints = [object ["triangles" .= (let (a, b) = C.witnessTriangles w in [a, b]), "rawGap" .= F.contactGap (C.witnessRow w), "floor" .= min 0 (F.contactGap (C.witnessRow w)), "lower" .= xyz (C.witnessLower w), "upper" .= xyz (C.witnessUpper w), "row" .= rowValue row] | (w, row) <- zip ws guards]
  unless (length guards == 12) (die "expected twelve refreshed overlap guards")
  rows <- checked (directionRows (spreadHinges fixture) pins model start)
  plane <- checked (measurePlane start 27 70)
  let guard = planeGuardRow pins plane
      floorDistance = min 0 (planeDistance plane)
  unless (planeDistance plane < 0 && planeDistance plane >= negate panelTolerance) (die "expected the saved vertex within the negative plane tolerance")
  putStrLn "Solve one fresh material quadratic at the repaired state."
  hFlush stdout
  added <- case constrainedStepDetailed OriginalWorkingSet 100 1e-3 free rows (guards ++ [guard]) of
    Left err -> pure (Compared "fresh" "Fresh material direction" Nothing IM.empty Nothing [] False (Just (explain err)) [])
    Right (delta, report, details) -> do
      let proposal = propose delta
      trials <- checked (replayCorrection study start proposal)
      pure (Compared "fresh" "Fresh material direction" (Just proposal) delta (Just (reportValue report)) (map contactValue (quadraticContacts details)) (quadraticConverged report) Nothing trials)
  let variants = [added]
      selected d = if comparedVerified d then firstPassing (comparedTrials d) else Nothing
      -- Keep a shared crop for the start, selected trial and next refusal.
      localMeshes = start : [savedMesh (measuredPoint (replayMeasure trial)) | d <- variants, Just chosen <- [selected d], trial <- comparedTrials d, replayScale trial `elem` [replayScale chosen, 2 * replayScale chosen]]
  tipPoints <- fmap concat $ forM localMeshes $ \mesh -> do
    vertex <- vertexAt mesh 27
    cut <- checked (pairSection mesh (46, 70))
    corners <- pairWitnesses (46, 70) <$> checked (C.contactWitnesses model mesh)
    pure (vertex : intersectionEnds cut ++ [C.witnessLower w | w <- corners, F.contactGap (C.witnessRow w) < 0])
  allPairPoints <- concat <$> traverse (trianglePoints start) [46, 70]
  let bounds = boxAround (map xy allPairPoints)
      tipBounds = boxAround (map xy tipPoints)
      export name title point = do
        state <- writeState output name title study point
        let mesh = savedMesh point
        cut <- checked (pairSection mesh (46, 70))
        m <- checked (measurePlane mesh 27 70)
        corners <- pairWitnesses (46, 70) <$> checked (C.contactWitnesses model mesh)
        forM_ [("pair", bounds), ("tip", tipBounds)] $ \(view, box) -> do
          drawing <- drawContact box mesh cut corners
          TIO.writeFile (output </> name ++ "-" ++ view ++ ".svg") drawing
        pure (state, object ["distance" .= planeDistance m, "margin" .= (planeDistance m + panelTolerance), "changeFromStart" .= (planeDistance m - planeDistance plane), "firstDistances" .= firstDistances cut, "secondDistances" .= secondDistances cut, "crosses" .= sectionCrosses cut, "intersection" .= map xyz (intersectionEnds cut), "intersectionLength" .= intersectionLength cut, "minimumGap" .= (case map (F.contactGap . C.witnessRow) corners of [] -> Nothing; gaps -> Just (minimum gaps)), "witnesses" .= [object ["lower" .= xyz (C.witnessLower w), "upper" .= xyz (C.witnessUpper w), "gap" .= F.contactGap (C.witnessRow w)] | w <- corners]])
  createDirectoryIfMissing True output
  forM_ (restorationFiles archive) $ \(name, bytes) -> do
    let path = output </> "source" </> name
    createDirectoryIfMissing True (takeDirectory path)
    BL.writeFile path bytes
  (initial, initialPair) <- export "start" "Saved repaired 1/128 state" (SavedPoint 0 start)
  entries <- forM variants $ \d -> do
    movement <- case comparedProposal d of
      Nothing -> pure Nothing
      Just proposal -> do full <- checked (scaledProposal 1 start proposal); Just <$> checked (savedMovement (SavedPoint 0 start) (SavedPoint 0 full))
    let actualDelta = case comparedProposal d of
          Nothing -> IM.empty
          Just proposal -> IM.fromList (zip [0 ..] (zipWith (\p q -> q ^-^ position p) (samples start) proposal))
        linearChange row = sum [dot gradient (IM.findWithDefault (V3 0 0 0) i actualDelta) | (i, gradient) <- IM.toList (fst row)]
        label k = comparedName d ++ "-" ++ show k
    trials <- forM (zip [0 :: Int ..] (comparedTrials d)) $ \(k, trial) -> do
      let point = measuredPoint (replayMeasure trial)
      (state, pair) <- export (label k) (comparedTitle d <> " · fraction 1/" <> T.pack (show (2 ^ k :: Integer))) point
      pure (object ["state" .= state, "pair" .= pair, "scale" .= replayScale trial, "movement" .= replayMovement trial, "costDecreased" .= replayCostDecreased trial, "geometryPassed" .= replayGeometryPassed trial, "predictedDistance" .= (planeDistance plane + replayScale trial * linearChange guard)])
    let chosen = [label k | (k, trial) <- zip [0 :: Int ..] (comparedTrials d), Just (replayScale trial) == fmap replayScale (selected d)]
    pure (object ["id" .= comparedName d, "title" .= comparedTitle d, "usesPlaneGuard" .= True, "failure" .= comparedFailure d, "proposal" .= fmap (map xyz) (comparedProposal d), "correction" .= [xyz (IM.findWithDefault (V3 0 0 0) i (comparedCorrection d)) | i <- [0 .. length (samples start) - 1]], "quadratic" .= comparedReport d, "contacts" .= comparedContacts d, "directionVerified" .= comparedVerified d, "fullMovement" .= movement, "selectedScale" .= fmap replayScale (selected d), "selectedState" .= chosen, "acceptedEndpoint" .= (isJust (selected d) && maybe False (<= 1e-7) movement), "guardLinearGaps" .= [g + linearChange row | row@(_, g) <- guards ++ [guard]], "predictedFullDistance" .= (planeDistance plane + linearChange guard), "trials" .= trials])
  let result = object ["gallery" .= ("body-fresh" :: Text), "issue" .= (351 :: Int), "newRestorations" .= (0 :: Int), "newQuadratics" .= (1 :: Int), "continuationSteps" .= (0 :: Int), "start" .= initial, "startPair" .= initialPair, "startPositions" .= map (xyz . position) (samples start), "source" .= restorationReport archive, "freeVertices" .= free, "materialRows" .= map rowValue rows, "constraints" .= constraints, "planeGuard" .= object ["vertex" .= (27 :: Int), "triangle" .= (70 :: Int), "distance" .= planeDistance plane, "floor" .= floorDistance, "gradient" .= rowValue (planeGradient plane, planeDistance plane), "row" .= rowValue guard], "directions" .= entries, "contactTolerance" .= panelTolerance, "lengthTolerance" .= (1e-5 :: Double), "movementTolerance" .= (1e-7 :: Double), "lengthWeight" .= (1e8 :: Double), "contactWeight" .= (1e10 :: Double), "damping" .= (1e-3 :: Double), "quadraticBudget" .= (100 :: Int), "continuousMotionChecked" .= False, "wholeCraneChecked" .= False, "drawingScale" .= (600 :: Double), "overlapBounds" .= boxValue bounds, "tipBounds" .= boxValue tipBounds]
  BL.writeFile (output </> "checks.json") (encode result)
  template <- TIO.readFile "study/fold-material/body-fresh.html"
  TIO.writeFile (destination </> "body-fresh.html") (T.replace "/*BODY_FRESH_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode result))) template)
  putStrLn ("Wrote " ++ destination </> "body-fresh.html")

boxValue :: Box -> [[Double]]
boxValue (Box (V2 a b) (V2 c d)) = [[a, b], [c, d]]
