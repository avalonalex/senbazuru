-- | Apply one minimum-movement restoration to the saved refused 1/128 trial.
-- The main direction and its passing 1/256 control are archive data. The only
-- new numerical calculation projects the refused state onto its linearized
-- plane-distance floor. There is no new material solve or continuation.
--
-- Keep both the original direction's overlap inequalities and their refreshed
-- derivatives at the refused trial. Their existing 1e-12 numerical residual
-- cap is unchanged. Actual all-pair contact and final-weight material cost
-- still decide the candidate, not the plane distance or tiny repair alone.
module BodyRestorationGallery (writeBodyRestoration, writeFreshRestoration) where

import BodyContactDiagnosis
import BodyContactDirection (contactGuard)
import BodyContactGallery (boxAround)
import BodyContactRestoration
import BodyCorrectionArchive
import BodyDirectionGallery (pairWitnesses, rowValue)
import BodyFreshArchive
import BodyPatch
import BodyPatchCheckpoints
import BodyPatchSubdivision (seedPassed)
import BodyPatchSubdivisionGallery (writeState)
import BodyPlaneArchive
import BodyPlaneGuard
import BodyPlaneGuardGallery (drawContact, trianglePoints, vertexAt, xy)
import Control.Monad (forM, forM_, unless)
import CraneSpread
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.List (zip7)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldContact qualified as F
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (panelTolerance)
import Senbazuru.Origami.Surface
import SurfaceContact qualified as C
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (takeDirectory, (</>))

-- | Shared measurement/repair path for both saved directions. Keeping the
-- archive adapters separate makes the repeated experiment change only its
-- inputs; the original repair's exported measurements remain reproducible.
data RestorationInput = RestorationInput
  { inputStudy :: BodyPatch,
    inputStart :: MaterialMesh,
    inputHalf :: MaterialMesh,
    inputRefused :: MaterialMesh,
    inputReport :: Value,
    inputFiles :: [(FilePath, BL.ByteString)]
  }

writeBodyRestoration :: FilePath -> FilePath -> IO ()
writeBodyRestoration source destination = do
  separateOutput source (destination </> "body-restoration")
  archive <- readPlaneArchive source
  (half, refused) <- restorationControls "plane" (planeDirections archive)
  let input = RestorationInput (planeStudy archive) (planeStart archive) half refused (planeReport archive) (planeFiles archive)
  renderRestoration "body-restoration" 349 "Saved start of attempt ten" destination input

writeFreshRestoration :: FilePath -> FilePath -> IO ()
writeFreshRestoration source destination = do
  separateOutput source (destination </> "body-fresh-restoration")
  archive <- readFreshArchive source
  (half, refused) <- restorationControls "fresh" (freshDirections archive)
  let input = RestorationInput (freshStudy archive) (freshStart archive) half refused (freshReport archive) (freshFiles archive)
  renderRestoration "body-fresh-restoration" 354 "Saved repaired start of fresh direction" destination input

restorationControls :: String -> [(String, Value, [(String, MaterialMesh, Value)])] -> IO (MaterialMesh, MaterialMesh)
restorationControls direction directions = case [(ts, record) | (name, record, ts) <- directions, name == direction] of
  [(ts, record)] -> do
    scale <- field "selectedScale" record
    unless (scale == (1 / 256 :: Double)) (die "restoration requires the saved passing 1/256 control")
    let named name = case [m | (n, m, _) <- ts, n == name] of [mesh] -> pure mesh; _ -> die "missing saved restoration trial"
    half <- named (direction ++ "-8")
    refused <- named (direction ++ "-7")
    pure (half, refused)
  _ -> die "expected one matching saved direction"

renderRestoration :: FilePath -> Int -> Text -> FilePath -> RestorationInput -> IO ()
renderRestoration galleryName issue startTitle destination input = do
  let output = destination </> galleryName
      study = inputStudy input
      fixture = patchSpread study
      start = inputStart input
      half = inputHalf input
      refused = inputRefused input
      pins = spreadPins fixture
      pairs = [(22, 63), (14, 55), (46, 70)]
      displacement a b = IM.fromList (zip [0 ..] (zipWith (\p q -> position q ^-^ position p) (samples a) (samples b)))
      dotRow row delta = sum [dot g (IM.findWithDefault (V3 0 0 0) i delta) | (i, g) <- IM.toList (fst row)]
      margin row delta = snd row + dotRow row delta
  initial <- checked (measurePlane start 27 70)
  before <- checked (measurePlane refused 27 70)
  let target = min 0 (planeDistance initial)
  unless (planeDistance before < negate panelTolerance) (die "saved 1/128 no longer has the expected plane loss")
  correction <- checked (restorePlane pins target before)
  let repaired = refused {samples = [p {position = position p ^+^ IM.findWithDefault (V3 0 0 0) i correction} | (i, p) <- zip [0 ..] (samples refused)]}
      installed = displacement refused repaired
  model <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) start)
  let witnesses mesh = do allRows <- checked (C.contactWitnesses model mesh); pure (concatMap (`pairWitnesses` allRows) pairs)
  ws0 <- witnesses start
  ws1 <- witnesses refused
  ws2 <- witnesses repaired
  let identity w = (C.witnessTriangles w, map fst (F.contactGradient (C.witnessRow w)))
  unless (length ws0 == 12 && map identity ws0 == map identity ws1 && map identity ws1 == map identity ws2) (die "overlap witness topology changed; cannot match the retained guards")
  let oldGuards = map (contactGuard pins . C.witnessRow) ws0
      refreshed = map (contactGuard pins . C.witnessRow) ws1
      oldMargins = map (`margin` displacement start repaired) oldGuards
      newMargins = map (`margin` installed) refreshed
      originalPlaneMargin = margin (planeGuardRow pins initial) (displacement start repaired)
      restorationPlaneMargin = planeDistance before - target + dotRow (planeGradient before, 0 :: Double) installed
      guardsPassed = all (>= -1e-12) (oldMargins ++ newMargins ++ [originalPlaneMargin, restorationPlaneMargin])
  measures <- traverse (checked . measurePatch study . SavedPoint 0) [start, half, refused, repaired]
  (baseCost, oldCost, newCost) <- case measures of [a, _, b, c] -> pure (patchCost 1e8 a, patchCost 1e8 b, patchCost 1e8 c); _ -> die "missing restoration measurements"
  geometry <- checked (seedPassed study repaired)
  after <- checked (measurePlane repaired 27 70)
  movement <- checked (savedMovement (SavedPoint 0 refused) (SavedPoint 0 repaired))
  mainMovement <- checked (savedMovement (SavedPoint 0 start) (SavedPoint 0 refused))
  let states = [("start", startTitle, start), ("half", "Saved passing 1/256", half), ("refused", "Saved refused 1/128", refused), ("restored", "One restoration at 1/128", repaired)]
  pairPoints <- concat <$> traverse (trianglePoints start) [46, 70]
  tipPoints <- fmap concat $ forM states $ \(_, _, mesh) -> do
    vertex <- vertexAt mesh 27
    cut <- checked (pairSection mesh (46, 70))
    corners <- pairWitnesses (46, 70) <$> checked (C.contactWitnesses model mesh)
    pure (vertex : intersectionEnds cut ++ [C.witnessLower w | w <- corners, F.contactGap (C.witnessRow w) < 0])
  let pairBox = boxAround (map xy pairPoints); tipBox = boxAround (map xy tipPoints)
  createDirectoryIfMissing True output
  forM_ (inputFiles input) $ \(name, bytes) -> do
    let path = output </> "source" </> name
    createDirectoryIfMissing True (takeDirectory path)
    BL.writeFile path bytes
  records <- forM states $ \(name, title, mesh) -> do
    state <- writeState output name title study (SavedPoint 0 mesh)
    m <- checked (measurePlane mesh 27 70)
    cut <- checked (pairSection mesh (46, 70))
    corners <- pairWitnesses (46, 70) <$> checked (C.contactWitnesses model mesh)
    forM_ [("pair", pairBox), ("tip", tipBox)] $ \(view, box) -> do
      drawing <- drawContact box mesh cut corners
      TIO.writeFile (output </> name ++ "-" ++ view ++ ".svg") drawing
    pure (object ["id" .= name, "state" .= state, "planeDistance" .= planeDistance m, "planeMargin" .= (planeDistance m + panelTolerance), "crosses46_70" .= sectionCrosses cut, "intersectionLength" .= intersectionLength cut])
  let constraints = [object ["triangles" .= (let (a, b) = C.witnessTriangles a0 in [a, b]), "originalRow" .= rowValue row0, "refreshedRow" .= rowValue row1, "originalLinearMargin" .= m0, "refreshedLinearMargin" .= m1, "originalGap" .= gap a0, "refusedGap" .= gap a1, "restoredGap" .= gap a2] | (a0, a1, a2, row0, row1, m0, m1) <- zip7 ws0 ws1 ws2 oldGuards refreshed oldMargins newMargins]
      gap = F.contactGap . C.witnessRow
      raw = [xyz (IM.findWithDefault (V3 0 0 0) i correction) | i <- [0 .. length (samples start) - 1]]
      result = object ["gallery" .= galleryName, "issue" .= issue, "restorationCount" .= (1 :: Int), "newMaterialSolves" .= (0 :: Int), "continuationSteps" .= (0 :: Int), "source" .= inputReport input, "states" .= records, "targetDistance" .= target, "refusedDistance" .= planeDistance before, "restoredDistance" .= planeDistance after, "predictedDistance" .= (planeDistance before + dotRow (planeGradient before, 0 :: Double) installed), "gradient" .= rowValue (planeGradient before, planeDistance before), "rawCorrection" .= raw, "correctionMovement" .= movement, "mainMovement" .= mainMovement, "constraints" .= constraints, "originalPlaneMargin" .= originalPlaneMargin, "restorationPlaneMargin" .= restorationPlaneMargin, "guardsPassed" .= guardsPassed, "geometryPassed" .= geometry, "costDecreased" .= (newCost < baseCost), "costChangeFromTrial" .= (newCost - oldCost), "candidatePassed" .= (guardsPassed && geometry && newCost < baseCost), "acceptedEndpoint" .= False, "continuousMotionChecked" .= False, "wholeCraneChecked" .= False, "contactTolerance" .= panelTolerance, "lengthTolerance" .= (1e-5 :: Double), "guardResidualTolerance" .= (1e-12 :: Double), "lengthWeight" .= (1e8 :: Double), "contactWeight" .= (1e10 :: Double)]
  BL.writeFile (output </> "checks.json") (encode result)
  template <- TIO.readFile ("study/fold-material" </> galleryName ++ ".html")
  TIO.writeFile (destination </> galleryName ++ ".html") (T.replace "/*BODY_RESTORATION_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode result))) template)
  putStrLn ("Wrote " ++ destination </> galleryName ++ ".html")
