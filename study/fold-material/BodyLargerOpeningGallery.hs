-- | One bounded solve with new grips, then repeatable rendering of its archive.
-- run.json is written before any visibility work and cannot be overwritten by
-- the solve command. The view command rechecks the input archive and retained
-- material, but never optimises positions. Numerical checkpoints are static
-- candidates; the gallery makes no claim about the route between them.
module BodyLargerOpeningGallery (solveLargerOpening, viewLargerOpening) where

import BodyContactDiagnosis (PairSection (..), pairSection)
import BodyCorrectionArchive
import BodyOpeningArchive
import BodyPatch
import BodyPatchCheckpoints
import BodyPatchSubdivisionGallery (equilibriumValue, stepValue, writeState)
import BodyVisibleLayersGallery (compareForms, creaseMasks, inheritedOrders, pairJson, paperShapes, regionJson, regions, unionRings, writeSvg)
import Control.Monad (forM, forM_, when)
import CraneSpread
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending (Hinge (..))
import FoldMaterial (componentCount)
import FoldRelaxation
import IllustrationComparison (illustrationPage, illustrationViews, sharedExtent)
import IllustrationVisibility
import Senbazuru.Diagram
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Query (Face (..), frameFaces)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (signedArea)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Contact (crossingPanels, uncheckedOrders, unorderedContacts)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Camera (project)
import Senbazuru.Render.Svg (Page (..))
import SurfaceContact qualified as Contact
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)
import Text.Read (readMaybe)

-- | Deliberately fixed target, budget and policy; no parameter sweep.
solveLargerOpening :: FilePath -> FilePath -> IO ()
solveLargerOpening source destination = do
  let output = destination </> "body-larger-opening"
  separateOutput source output
  exists <- doesFileExist (output </> "run.json")
  when exists (die "run.json already exists; use --body-larger-opening-view to render without another solve")
  archive <- readCorrectionArchive source
  (_, target, seed, guess) <- openingInputs archive
  createDirectoryIfMissing True (output </> "source")
  forM_ (archiveFiles archive) $ \(name, bytes) -> BL.writeFile (output </> "source" </> name) bytes
  let fixture = patchSpread target
      positions = map (xyz . position) . samples
  BL.writeFile (output </> "initial.json") (encode (object ["seed" .= positions seed, "guess" .= positions guess, "pins" .= [(i, xyz p) | (i, p) <- IM.toList (spreadPins fixture)]]))
  contact <- checked (Contact.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) guess)
  putStrLn "One 10-degree target: at most 40 corrections at length weight 1e8."
  hFlush stdout
  let result = tracePinnedContact (Settings 40 1e-5) (spreadPins fixture) (spreadHinges fixture) contact guess
      record = case result of
        Left err -> object ["failure" .= explain err, "points" .= ([] :: [Value]), "converged" .= False]
        Right (run, audit) -> object ["points" .= [object ["iteration" .= completedIterations p, "positions" .= positions (checkpointMesh p)] | p <- checkpoints run], "trace" .= map stepValue (solverSteps audit), "converged" .= converged run, "equilibrium" .= fmap equilibriumValue (equilibriumCheck run), "blockedIterations" .= map blockedIteration (blockedStages audit)]
  BL.writeFile (output </> "run.json") (encode (object ["issue" .= (393 :: Int), "targetDegrees" .= (10 :: Int), "iterationLimit" .= (40 :: Int), "lengthWeight" .= (1e8 :: Double), "contactWeight" .= (1e10 :: Double), "result" .= record]))
  putStrLn "Saved the bounded run; rendering does not repeat it."
  hFlush stdout
  viewLargerOpening destination

viewLargerOpening :: FilePath -> IO ()
viewLargerOpening destination = do
  let output = destination </> "body-larger-opening"
  archive <- readOpeningArchive output
  let old = openingOld archive
      target = openingTarget archive
      seed = openingSeed archive
      guess = openingInitial archive
      run = openingRun archive
      points = openingPoints archive
      endpoint = case reverse points of p : _ -> p; [] -> SavedPoint 0 guess
      states = [("seed", "Recovered 5° seed", old, SavedPoint 0 seed), ("guess", "10° initial guess · may strain", target, SavedPoint 0 guess), ("endpoint", "10° bounded endpoint", target, endpoint)]
  measurements <- forM states $ \(name, title, study, point) -> measure output name title study seed point
  -- Preserve every returned checkpoint as raw material geometry and strict
  -- measurements, including the unchanged mesh when a search is refused.
  history <- forM points $ \p -> writeState output ("step-" ++ show (savedIteration p)) "Numerical checkpoint · not a folding step" target p
  cameras <- checked illustrationViews
  views <- forM cameras $ \(viewId, title, basis) -> do
    bounds <- checked (sharedExtent basis [savedMesh p | (_, _, _, p) <- states])
    let page = illustrationPage title bounds
        owners = refinedPanels (spreadRefined (patchSpread target))
    shown <- forM states $ \(name, _, study, point) -> do
      sheet <- checked (spreadSurface (patchSpread study) (savedMesh point))
      let frame = surfaceFrame sheet
      inherited <- checked (inheritedOrders (patchSpread study) frame)
      audit <- checked (illustrationVisibility (0.1 / 600) basis frame inherited)
      faces <- checked (frameFaces frame)
      let unresolved = unionRings (auditUncovered audit ++ [pairOverlap p | p <- auditPairs audit, isNothing (pairRelation p)])
          wire = [Polyline (solid (Colour "#8e968a") 0.4) (map (project basis) (faceCorners face) ++ take 1 (map (project basis) (faceCorners face))) | face <- faces]
          shapes = case auditForm audit of
            Just seen -> paperShapes basis (regions basis owners seen) seen
            Nothing -> wire
          stem = name ++ "-" ++ T.unpack viewId
      writeSvg output page bounds (stem ++ "-paper") (shapes ++ [Fill (Colour "#bd4354") unresolved])
      writeSvg output page bounds (stem ++ "-wire") wire
      pure (object ["id" .= name, "stem" .= stem, "status" .= auditStatus audit, "regions" .= fmap (map regionJson . regions basis owners) (auditForm audit), "creases" .= fmap (map (map xy) . creaseMasks basis) (auditForm audit), "uncovered" .= map (map xy) (unionRings (auditUncovered audit)), "pairs" .= map pairJson (auditPairs audit), "resolved" .= (isJust (auditForm audit) && null unresolved), "unresolvedPairs" .= length [() | p <- auditPairs audit, isNothing (pairRelation p)], "uncoveredAreaPixelsSquared" .= (360000 * sum (map (abs . signedArea) (unionRings (auditUncovered audit)))), "maxOverriddenDepthPixels" .= (600 * maximum (0 : map pairOverriddenDepth (auditPairs audit)))], audit)
    differences <- case shown of
      [(_, a), _, (_, b)] -> compareForms output page bounds basis owners (T.unpack viewId ++ "-difference") a b
      _ -> die "expected seed, guess and endpoint"
    pure (object ["id" .= viewId, "title" .= title, "width" .= pageWidth page, "height" .= pageHeight page, "states" .= map fst shown, "differences" .= differences])
  let report = object ["issue" .= (393 :: Int), "pixelsPerSheetUnit" .= (600 :: Int), "newSolves" .= (1 :: Int), "motionChecked" .= False, "wholeCraneChecked" .= False, "run" .= run, "states" .= measurements, "history" .= history, "corePanels" .= map unFaceId (patchCore target), "pins" .= [(i, xyz p) | (i, p) <- IM.toList (spreadPins (patchSpread target))], "hinges" .= [object ["vertices" .= hingeVertices h, "role" .= show (hingeRole h), "restAngle" .= hingeRest h, "stiffness" .= hingeStiffness h] | h <- spreadHinges (patchSpread target)], "views" .= views]
  BL.writeFile (output </> "checks.json") (encode report)
  template <- TIO.readFile "study/fold-material/body-larger-opening.html"
  TIO.writeFile (destination </> "body-larger-opening.html") (T.replace "/*BODY_OPENING_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode report))) template)
  putStrLn ("Wrote " ++ destination </> "body-larger-opening.html")

measure :: FilePath -> String -> T.Text -> BodyPatch -> MaterialMesh -> SavedPoint -> IO Value
measure output name title study seed point = do
  metrics <- writeState output name title study point
  m <- checked (measurePatch study point)
  base <- checked (measurePatch study (SavedPoint 0 seed))
  movement <- checked (savedMovement (SavedPoint 0 seed) point)
  pairs <- forM (crossingPanels (measuredContact m)) $ \(a, b) -> (,) <$> triangle a <*> triangle b
  sections <- forM pairs $ \pair -> (pair,) <$> checked (pairSection (savedMesh point) pair)
  let maxEdge = 600 * maximum (0 : map (abs . edgeLengthChange) (measuredEdges m))
      strain = maxLengthError (savedMesh point)
      reversed = 600 * max 0 (negate (fromMaybe 0 (measuredMinimumGap m)))
      intersection = 600 * maximum (0 : [intersectionLength s | (_, s) <- sections])
      depthGain = 600 * (measuredBodyDepth m - measuredBodyDepth base)
      intact = componentCount (savedMesh point) == 1 && spreadHeldError (patchSpread study) (savedMesh point) == 0
      knownOrders = null (uncheckedOrders (measuredContact m)) && null (unorderedContacts (measuredContact m))
      screen = intact && knownOrders && maxEdge <= 0.1 && strain <= 0.001 && reversed <= 0.1 && intersection <= 0.1
  pure (object ["id" .= name, "title" .= title, "metrics" .= metrics, "maxAbsoluteEdgeErrorPixels" .= maxEdge, "maxReversedHeightPixels" .= reversed, "maxFailedIntersectionPixels" .= intersection, "depthGainPixels" .= depthGain, "maxMovementFromSeedPixels" .= (600 * movement), "distanceScreensPassed" .= screen, "usefulDepthGain" .= (depthGain >= 2), "edges" .= [object ["vertices" .= edgeVertices e, "rest" .= edgeRestLength e, "change" .= edgeLengthChange e] | e <- measuredEdges m], "crossings" .= [object ["pair" .= pair, "ends" .= map xyz (intersectionEnds s), "lengthPixels" .= (600 * intersectionLength s)] | (pair, s) <- sections]])
  where
    triangle t = maybe (die "unexpected triangle name") pure (T.stripPrefix "triangle-" t >>= readMaybe . T.unpack)

xy :: V2 -> [Double]
xy (V2 x y) = [x, y]
