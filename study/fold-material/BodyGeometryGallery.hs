-- | Resume one saved body-patch shape while refusing invalid endpoints.
-- The archive supplies material and controls; only the acceptance gate changes.
-- Draw returned meshes, not merely proposed ones: an equilibrium check or a
-- failed search may leave the current mesh unchanged. Numerical corrections
-- are not a folding path. See docs/notes/body-geometry-continuation.md.
module BodyGeometryGallery (writeBodyGeometry) where

import BodyContactDiagnosis
import BodyContactGallery (boxAround, drawPair)
import BodyCorrectionArchive
import BodyPatch
import BodyPatchCheckpoints
import BodyPatchSubdivision (seedPassed)
import BodyPatchSubdivisionGallery (equilibriumValue, stepValue, writeState)
import Control.Monad (forM, forM_, unless)
import CraneSpread
import Data.Aeson (encode, object, (.=))
import Data.Bifunctor (first)
import Data.ByteString.Lazy qualified as BL
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldMaterial (componentCount)
import FoldRelaxation
import Senbazuru.Explain (explain, num, tshow)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Contact (contactPassed, crossingPanels, reversedOrders)
import Senbazuru.Origami.Surface
import SurfaceContact qualified as Contact
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)
import WingBending (finalMesh)

writeBodyGeometry :: FilePath -> FilePath -> IO ()
writeBodyGeometry source destination = do
  let output = destination </> "body-geometry"
  separateOutput source output
  archive <- readCorrectionArchive source
  (start, original) <- case archiveStates archive of
    [_, (_, _, a, _), (_, _, b, _)] -> pure (a, b)
    _ -> die "expected saved start and original correction"
  let study = archiveStudy archive
      fixture = patchSpread study
      -- Give the independent checks their existing tolerances. A returned
      -- failure explains the gate, not a new contribution to the objective.
      geometry mesh = do
        _ <- first explain (spreadSurface fixture mesh)
        contact <- first explain (spreadCheck fixture mesh)
        unless
          (componentCount mesh == 1 && spreadHeldError fixture mesh == 0 && maxLengthError mesh <= 1e-5 && contactPassed contact)
          (Left ("components " <> tshow (componentCount mesh) <> "; hold error " <> num (spreadHeldError fixture mesh) <> "; relative length error " <> num (maxLengthError mesh) <> "; crossings " <> tshow (crossingPanels contact) <> "; reversed orders " <> tshow (reversedOrders contact)))
  either (die . T.unpack) pure (geometry start)
  contact <- checked (Contact.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) start)
  putStrLn "One geometry-gated continuation: at most 40 corrections; original archive stays unchanged."
  hFlush stdout
  (run, audit) <- checked (traceCheckedPinnedContact geometry (Settings 40 1e-5) (spreadPins fixture) (spreadHinges fixture) contact start)
  endpoint <- checked (finalMesh run)
  accepted <- checked (patchAccepted study run endpoint)
  let steps = solverSteps audit
      -- The following starts, followed by the final returned mesh, are the
      -- authoritative outcomes even if a stationary trial was not installed.
      finishes = map solverStart (drop 1 steps) ++ [endpoint | not (null steps)]
      points = SavedPoint 0 start : zipWith SavedPoint [1 ..] finishes
      controls = [("original", "Original quarter-step · three crossings", SavedPoint 2 original)]
      states = controls ++ [("step-" ++ show (savedIteration p), "Checked correction " <> tshow (savedIteration p), p) | p <- points]
  forM_ points $ \p -> do
    valid <- checked (seedPassed study (savedMesh p))
    unless valid (die "a returned correction failed independent geometry")
  metrics <- forM (zip steps finishes) $ \(step, finish) -> do
    before <- checked (measurePatch study (SavedPoint 0 (solverStart step)))
    after <- checked (measurePatch study (SavedPoint 0 finish))
    movement <- checked (savedMovement (measuredPoint before) (measuredPoint after))
    unless (movement == 0 || patchCost 1e8 after < patchCost 1e8 before) (die "installed correction did not lower cost")
    -- Recompute both sides of the solver objective independently of its rows.
    unless (abs (2 * patchCost 1e8 before - solverBeforeEnergy step) < 1e-10) (die "starting cost differs from solver trace")
    forM_ (solverCandidateEnergy step) $ \energy -> do
      measured <- checked (measurePatch study (SavedPoint 0 (solverCandidate step)))
      unless (abs (2 * patchCost 1e8 measured - energy) < 1e-10) (die "candidate cost differs from solver trace")
    pure (object ["iteration" .= solverIteration step, "scale" .= solverScale step, "installedMovement" .= movement, "costDecrease" .= (patchCost 1e8 before - patchCost 1e8 after), "equilibrium" .= equilibriumValue (solverEquilibrium step), "refusals" .= length (solverRefusals step)])
  prepared <- forM states $ \(name, title, point) -> do
    sections <- traverse (\pair -> (pair,) <$> checked (pairSection (savedMesh point) pair)) [(14, 55), (22, 63), (46, 70)]
    pure (name, title, point, sections)
  let crop pair = boxAround [V2 x y | (name, _, _, sections) <- prepared, name `elem` ["original", "step-0"], (other, cut) <- sections, other == pair, V3 x y _ <- intersectionEnds cut]
  createDirectoryIfMissing True (output </> "source")
  forM_ (archiveFiles archive) $ \(name, bytes) -> BL.writeFile (output </> "source" </> name) bytes
  entries <- forM prepared $ \(name, title, point, sections) -> do
    entry <- writeState output name title study point
    forM_ sections $ \(pair@(i, j), cut) -> TIO.writeFile (output </> name ++ "-pair-" ++ show i ++ "-" ++ show j ++ ".svg") (drawPair (crop pair) (savedMesh point) pair cut [])
    pure entry
  movement <- checked (savedMovement (SavedPoint 0 start) (SavedPoint 0 endpoint))
  let trace = map stepValue steps
      report = object ["gallery" .= ("body-geometry" :: T.Text), "sourceIteration" .= (1 :: Int), "iterationLimit" .= (40 :: Int), "lengthWeight" .= (1e8 :: Double), "contactWeight" .= (1e10 :: Double), "lengthTolerance" .= (1e-5 :: Double), "contactTolerance" .= (1e-7 :: Double), "movementTolerance" .= (1e-7 :: Double), "acceptedEndpoint" .= accepted, "converged" .= converged run, "equilibrium" .= fmap equilibriumValue (equilibriumCheck run), "blockedIterations" .= map blockedIteration (blockedStages audit), "movementFromStart" .= movement, "continuousMotionChecked" .= False, "wholeCraneChecked" .= False, "steps" .= metrics, "states" .= entries]
  BL.writeFile (output </> "trace.json") (encode trace)
  BL.writeFile (output </> "checks.json") (encode report)
  template <- TIO.readFile "study/fold-material/body-geometry.html"
  TIO.writeFile (destination </> "body-geometry.html") (T.replace "/*BODY_GEOMETRY_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode report))) template)
  putStrLn ("Wrote " ++ destination </> "body-geometry.html" ++ "; corrections " ++ show (length steps) ++ ", blocked " ++ show (map blockedIteration (blockedStages audit)) ++ ", accepted " ++ show accepted)
