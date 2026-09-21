-- | Compare replayed numerical candidates without solving or moving the archive.
-- The original quarter-step is a control, not the selected geometry-gated step.
-- All fractions are measured, including those below the first passing one;
-- exporting a candidate never implies equilibrium or a checked folding route.
module BodyCorrectionReplayGallery (writeBodyReplay) where

import BodyContactDiagnosis
import BodyContactGallery (boxAround, drawPair)
import BodyCorrectionArchive
import BodyCorrectionReplay
import BodyPatch
import BodyPatchCheckpointGallery (drawCheckpoint, views)
import BodyPatchCheckpoints
import Control.Monad (forM, forM_, unless)
import CraneSpread
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.List (sortOn)
import Data.Ord (Down (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldMaterial (componentCount)
import FoldRelaxation (maxLengthError)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Surface
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))

writeBodyReplay :: FilePath -> FilePath -> IO ()
writeBodyReplay source destination = do
  let output = destination </> "body-replay"
  separateOutput source output
  archive <- readCorrectionArchive source
  (start, original, step) <- case (archiveStates archive, archiveTrace archive) of
    ([_, (_, _, a, _), (_, _, b, _)], _ : s : _) -> pure (a, b, s)
    _ -> die "replay needs the first two saved corrections"
  rawProposal <- field "fullProposal" step
  proposal <- traverse vector rawProposal
  let study = archiveStudy archive
      fixture = patchSpread study
  candidates <- checked (replayCorrection study start proposal)
  before <- checked (measurePatch study (SavedPoint 1 start))
  let beforeCost = patchCost 1e8 before
      selected = firstPassing candidates
      states = ("start", ReplayCandidate 0 before 0 (componentCount start == 1 && spreadHeldError fixture start == 0 && maxLengthError start <= 1e-5 && contactPassed (measuredContact before)) False) : [("fraction-" ++ show k, c) | (k, c) <- zip [0 :: Int ..] candidates]
  -- Bind the recomputed original choice and refusals to their saved costs.
  forM_ candidates $ \c -> case replayScale c of
    0.25 -> do
      movement <- checked (savedMovement (SavedPoint 2 original) (measuredPoint (replayMeasure c)))
      unless (movement < 1e-12) (die "quarter replay differs from saved correction")
    _ -> pure ()
  refusals <- field "refusals" step :: IO [Value]
  forM_ refusals $ \r -> do
    scale <- field "scale" r
    energy <- field "afterEnergy" r
    case [c | c <- candidates, replayScale c == scale] of
      [c] -> unless (abs (2 * patchCost 1e8 (replayMeasure c) - energy) <= 1e-10 * max 1 (abs energy)) (die "replayed refusal cost differs from archive")
      _ -> die "saved refusal is outside replay fractions"
  -- Validate every export and intersection before any writes.
  prepared <- forM states $ \(name, c) -> do
    let mesh = savedMesh (measuredPoint (replayMeasure c))
    sheet <- checked (spreadSurface fixture mesh)
    sections <- traverse (\pair -> (pair,) <$> checked (pairSection mesh pair)) [(14, 55), (22, 63), (46, 70)]
    pure (name, c, sheet, sections)
  let crop pair = boxAround [V2 x y | (_, c, _, sections) <- prepared, replayScale c `elem` [0, 0.25], (other, cut) <- sections, other == pair, V3 x y _ <- intersectionEnds cut]
  createDirectoryIfMissing True (output </> "source")
  forM_ (archiveFiles archive) $ \(name, bytes) -> BL.writeFile (output </> "source" </> name) bytes
  entries <- forM prepared $ \(name, c, sheet, sections) -> do
    let m = replayMeasure c
        mesh = savedMesh (measuredPoint m)
        title = T.pack name
        edges = take 1 (sortOn (Down . edgeRelativeError) (measuredEdges m))
        pairs = take 1 (sortOn (\(_, _, d) -> Down d) (reversedOrders (measuredContact m)) ++ [(a, b, 0) | (a, b) <- crossingPanels (measuredContact m)])
    BL.writeFile (output </> name ++ ".fold") (encode (FoldFile (Just 1.2) (Just "senbazuru body correction replay") Nothing (Just title) Nothing [] (materialFrame sheet) []))
    forM_ views $ \(view, projection, bounds, height) -> TIO.writeFile (output </> name ++ "-" ++ view ++ ".svg") (drawCheckpoint projection bounds height mesh edges pairs)
    forM_ sections $ \(pair@(i, j), cut) -> TIO.writeFile (output </> name ++ "-pair-" ++ show i ++ "-" ++ show j ++ ".svg") (drawPair (crop pair) mesh pair cut [])
    pure (object ["id" .= name, "scale" .= replayScale c, "geometryPassed" .= replayGeometryPassed c, "costDecreased" .= replayCostDecreased c, "bothPassed" .= (replayGeometryPassed c && replayCostDecreased c), "movement" .= replayMovement c, "components" .= componentCount mesh, "holdError" .= spreadHeldError fixture mesh, "maxRelativeEdgeError" .= maxLengthError mesh, "contact" .= measuredContact m, "minimumSolverGap" .= measuredMinimumGap m, "bodyDepth" .= measuredBodyDepth m, "creaseCost" .= measuredCrease m, "panelCost" .= measuredPanel m, "lengthCost" .= (5e7 * measuredLengthSquares m), "contactCost" .= (5e9 * measuredContactSquares m), "totalCost" .= patchCost 1e8 m, "costDecrease" .= (beforeCost - patchCost 1e8 m), "sections" .= [object ["pair" .= pair, "crosses" .= sectionCrosses cut, "intersectionLength" .= intersectionLength cut, "intersection" .= map xyz (intersectionEnds cut)] | (pair, cut) <- sections]])
  let report = object ["gallery" .= ("body-replay" :: Text), "newSolves" .= (0 :: Int), "lengthWeight" .= (1e8 :: Double), "contactWeight" .= (1e10 :: Double), "lengthTolerance" .= (1e-5 :: Double), "contactTolerance" .= panelTolerance, "fractions" .= replayFractions, "selectedScale" .= fmap replayScale selected, "sourceStep" .= step, "acceptedEndpoint" .= False, "continuousMotionChecked" .= False, "states" .= entries]
  BL.writeFile (output </> "checks.json") (encode report)
  template <- TIO.readFile "study/fold-material/body-replay.html"
  TIO.writeFile (destination </> "body-replay.html") (T.replace "/*BODY_REPLAY_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode report))) template)
  putStrLn ("Replayed 31 fractions without solving; first passing fraction " ++ show (fmap replayScale selected) ++ ". Wrote " ++ destination </> "body-replay.html")
  where
    vector [x, y, z] = pure (V3 x y z)
    vector _ = die "saved proposal needs three coordinates"
