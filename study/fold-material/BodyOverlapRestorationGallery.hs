-- | Repair one moving overlap corner in an authenticated, refused body trial.
-- An overlap gap measures the upper triangle's height minus the lower one's
-- at a corner of their projected overlap. Restore 14–55 corner zero to its
-- starting gap with one minimum-movement projection. That corner and both
-- triangles move; SurfaceContact supplies the complete local derivative.
--
-- A repair of one contact can disturb another. Keep the nineteen original
-- guards, eighteen refreshed overlap guards, stronger starting-gap target,
-- actual all-pair contact and material checks separate. A failure is exported
-- as a diagnostic, without a second repair or a new material direction.
module BodyOverlapRestorationGallery (writeBodyOverlapRestoration) where

import BodyContactDiagnosis
import BodyContactDirection (contactGuard)
import BodyContactGallery (boxAround)
import BodyContactRestoration (restoreOverlap)
import BodyCorrectionArchive
import BodyDirectionGallery (pairWitnesses, rowValue)
import BodyFourthArchive
import BodyGuardedInspection (drawInspection)
import BodyPatch
import BodyPatchCheckpoints
import BodyPatchSubdivisionGallery (writeState)
import BodyPlaneGuard
import BodyPlaneGuardGallery (trianglePoints, xy)
import BodyRestorationLoop (Candidate (..), assess, displacement, margin)
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
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (panelTolerance)
import Senbazuru.Origami.Surface
import SurfaceContact qualified as C
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (takeDirectory, (</>))
import System.IO (hFlush, stdout)

writeBodyOverlapRestoration :: FilePath -> FilePath -> IO ()
writeBodyOverlapRestoration source destination = do
  let output = destination </> "body-overlap-restoration"
  separateOutput source output
  putStrLn "Authenticate saved directions, then restore one overlap gap without a material solve."
  hFlush stdout
  archive <- readFourthArchive source
  startState <- named archive "start"
  refusedState <- named archive "refused"
  let study = fourthStudy archive
      fixture = patchSpread study
      pins = spreadPins fixture
      start = fourthMesh startState
      refused = fourthMesh refusedState
      pairs = [(22, 63), (14, 55), (46, 70), (55, 93)]
  model <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) start)
  let witnesses mesh = do ws <- checked (C.contactWitnesses model mesh); pure (concatMap (`pairWitnesses` ws) pairs)
      identity w = (C.witnessTriangles w, map fst (F.contactGradient (C.witnessRow w)))
      gap = F.contactGap . C.witnessRow
  initial <- witnesses start
  before <- witnesses refused
  unless (length initial == 18 && map identity initial == map identity before) (die "saved overlap identities changed")
  a <- cornerZero initial
  b <- cornerZero before
  let target = gap a
      targetRow = (fst (contactGuard pins (C.witnessRow b)), gap b - target)
  unless (gap b < target) (die "saved corner no longer loses its starting gap")
  plane <- checked (measurePlane start 27 70)
  let overlaps = map (contactGuard pins . C.witnessRow) initial
      original = take 12 overlaps ++ [planeGuardRow pins plane] ++ drop 12 overlaps
      refreshed = map (contactGuard pins . C.witnessRow) before
  savedGuards <- field "guards" (fourthDirection archive) :: IO [Value]
  unless (savedGuards == map rowValue original) (die "repair must retain all nineteen original guards")
  raw <- checked (restoreOverlap pins target (C.witnessRow b))
  let repaired = refused {samples = [p {position = position p ^+^ IM.findWithDefault (V3 0 0 0) i raw} | (i, p) <- zip [0 ..] (samples refused)]}
      installed = displacement refused repaired
      oldMargins = map (`margin` displacement start repaired) original
      newMargins = map (`margin` installed) refreshed
      targetMargin = margin targetRow installed
  after <- witnesses repaired
  let sameCorners = map identity before == map identity after
  c <- cornerZero after
  measures <- traverse (checked . measurePatch study . SavedPoint 0) [start, refused, repaired]
  (baseCost, trialCost, newCost) <- case measures of [x, y, z] -> pure (patchCost 1e8 x, patchCost 1e8 y, patchCost 1e8 z); _ -> die "missing repair measurements"
  candidate <- checked (assess study start baseCost (oldMargins ++ newMargins ++ [targetMargin]) (object []) repaired)
  movement <- checked (savedMovement (SavedPoint 0 refused) (SavedPoint 0 repaired))
  fullMovement <- field "fullMovement" (fourthDirection archive) :: IO Double
  let actualTargetPassed = gap c - target >= -1e-12
      passed = sameCorners && actualTargetPassed && candidatePasses candidate
      controls = sortOn fourthScale (fourthStates archive)
      states = [(fourthName s, fourthTitle s, fourthMesh s) | s <- controls] ++ [("restored", "One overlap repair · diagnostic unless all checks pass", repaired)]
  inspected <- forM states $ \(name, title, mesh) -> do
    cut <- checked (pairSection mesh (14, 55))
    ws <- pairWitnesses (14, 55) <$> checked (C.contactWitnesses model mesh)
    pure (name, title, mesh, cut, ws)
  ps <- concat <$> traverse (trianglePoints start) [14, 55]
  let pairBox = boxAround (map xy ps)
      tipBox = boxAround [xy p | (_, _, _, cut, ws) <- inspected, p <- intersectionEnds cut ++ map C.witnessLower (take 1 ws)]
  createDirectoryIfMissing True output
  forM_ (fourthFiles archive) $ \(name, bytes) -> do
    let path = output </> "source" </> name
    createDirectoryIfMissing True (takeDirectory path)
    BL.writeFile path bytes
  records <- forM inspected $ \(name, title, mesh, cut, ws) -> do
    record <-
      if name == "restored"
        then writeState output name title study (SavedPoint 0 mesh)
        else do
          s <- named archive name
          forM_ (".fold" : ["-" ++ v ++ ".svg" | v <- ["side", "top", "underside", "material"]]) $ \suffix ->
            readArchiveBytes (source </> fourthSource s ++ suffix) >>= BL.writeFile (output </> name ++ suffix)
          field "state" (fourthRecord s)
    forM_ [("pair", pairBox), ("tip", tipBox)] $ \(view, bounds) -> drawInspection bounds mesh cut ws >>= TIO.writeFile (output </> name ++ "-" ++ view ++ ".svg")
    other <- checked (pairSection mesh (55, 93))
    allWs <- witnesses mesh
    pure (object ["id" .= name, "title" .= title, "state" .= record, "crosses14_55" .= sectionCrosses cut, "intersection14_55" .= intersectionLength cut, "crosses55_93" .= sectionCrosses other, "intersection55_93" .= intersectionLength other, "corners" .= map witnessValue allWs])
  let constraints = [object ["index" .= i, "row" .= rowValue r, "margin" .= m] | (i, (r, m)) <- zip [0 :: Int ..] (zip original oldMargins)]
      freshConstraints = [object ["index" .= i, "row" .= rowValue r, "margin" .= m] | (i, (r, m)) <- zip [0 :: Int ..] (zip refreshed newMargins)]
      vectors d = [xyz (IM.findWithDefault (V3 0 0 0) i d) | i <- [0 .. length (samples start) - 1]]
      result = object ["gallery" .= ("body-overlap-restoration" :: Text), "issue" .= (373 :: Int), "newMaterialSolves" .= (0 :: Int), "restorationCount" .= (1 :: Int), "continuationSteps" .= (0 :: Int), "states" .= records, "originalGuards" .= constraints, "refreshedGuards" .= freshConstraints, "targetGuard" .= rowValue targetRow, "targetMargin" .= targetMargin, "targetGap" .= target, "refusedGap" .= gap b, "restoredGap" .= gap c, "actualTargetPassed" .= actualTargetPassed, "sameOverlapIdentities" .= sameCorners, "rawCorrection" .= vectors raw, "installedCorrection" .= vectors installed, "correctionMovement" .= movement, "unscaledMaterialMovement" .= fullMovement, "costChangeFromTrial" .= (newCost - trialCost), "checks" .= candidateDetails candidate, "candidatePassed" .= passed, "acceptedEndpoint" .= False, "continuousMotionChecked" .= False, "wholeCraneChecked" .= False, "contactTolerance" .= panelTolerance, "guardResidualTolerance" .= (1e-12 :: Double), "movementTolerance" .= (1e-7 :: Double), "lengthTolerance" .= (1e-5 :: Double), "lengthWeight" .= (1e8 :: Double), "contactWeight" .= (1e10 :: Double), "drawingScale" .= (600 :: Double)]
      bytes = encode result
  BL.writeFile (output </> "checks.json") bytes
  template <- TIO.readFile "study/fold-material/body-overlap-restoration.html"
  TIO.writeFile (destination </> "body-overlap-restoration.html") (T.replace "/*BODY_OVERLAP_DATA*/null" (TE.decodeUtf8 (BL.toStrict bytes)) template)
  putStrLn ("Wrote " ++ destination </> "body-overlap-restoration.html")

named :: FourthArchive -> String -> IO FourthState
named archive name = case [s | s <- fourthStates archive, fourthName s == name] of [s] -> pure s; _ -> die ("missing saved state " ++ name)

cornerZero :: [C.ContactWitness] -> IO C.ContactWitness
cornerZero ws = case pairWitnesses (14, 55) ws of
  w : rest | length rest == 3 && C.witnessTriangles w == (55, 14) -> pure w
  _ -> die "missing four ordered corners of 55 below 14"

witnessValue :: C.ContactWitness -> Value
witnessValue w = object ["triangles" .= (let (a, b) = C.witnessTriangles w in [a, b]), "lower" .= xyz (C.witnessLower w), "upper" .= xyz (C.witnessUpper w), "gap" .= F.contactGap (C.witnessRow w), "gradient" .= rowValue (IM.fromListWith (^+^) (F.contactGradient (C.witnessRow w)), F.contactGap (C.witnessRow w))]
