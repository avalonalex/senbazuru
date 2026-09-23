-- | One direction comparison at the archived blocked body shape. The matched
-- unconstrained quadratic separates changes in numerical solution from the
-- effect of contact guards at one or two pairs. All 31 fractions remain diagnostics;
-- only a verified quadratic plus nonlinear cost and geometry gates selects a
-- trial. This command never starts a continuation or declares a folding path.
module BodyDirectionGallery (writeBodyDirection, writeBodyPairs) where

import BodyContactDiagnosis
import BodyContactDirection
import BodyContactGallery (boxAround, drawPair)
import BodyCorrectionArchive
import BodyCorrectionReplay
import BodyPatch
import BodyPatchCheckpoints
import BodyPatchSubdivisionGallery (writeState)
import ContactQuadratic
import Control.Monad (forM, forM_, unless, when)
import CraneSpread
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.List (sortOn)
import Data.Maybe (fromMaybe, isJust)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldContact qualified as F
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import SurfaceContact qualified as C
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)

writeBodyDirection :: FilePath -> FilePath -> IO ()
writeBodyDirection = writeComparison False

-- | Keep the original one-pair gallery and add the newly exposed pair without
-- changing its baseline. Constraint ids in each direction index the shared
-- export; working-set source ids index that direction's constraint list.
writeBodyPairs :: FilePath -> FilePath -> IO ()
writeBodyPairs = writeComparison True

writeComparison :: Bool -> FilePath -> FilePath -> IO ()
writeComparison both source destination = do
  let gallery = if both then "body-pairs" else "body-direction"
      pairs = if both then [(22, 63), (14, 55)] else [(22, 63)]
      output = destination </> gallery
  separateOutput source output
  archive <- readBlockedArchive source
  let study = blockedStudy archive
      fixture = patchSpread study
      start = blockedMesh archive
      pins = spreadPins fixture
      free = [i | i <- [0 .. length (samples start) - 1], IM.notMember i pins]
      positions mesh = map (xyz . position) (samples mesh)
      propose delta = [position p ^+^ IM.findWithDefault (V3 0 0 0) i delta | (i, p) <- zip [0 ..] (samples start)]
  model <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) start)
  allWitnesses <- checked (C.contactWitnesses model start)
  views <- forM pairs $ \pair -> do
    let ws = pairWitnesses pair allWitnesses
    when (null ws) (die ("no archived overlap corners for " ++ show pair))
    cut <- checked (pairSection start pair)
    let bounds = boxAround [V2 x y | w <- ws, V3 x y _ <- [C.witnessLower w, C.witnessUpper w]]
        -- The second pair does not intersect at the saved start. Centre its
        -- tip view on the two closest overlap corners instead of an empty box.
        tipPoints = case intersectionEnds cut of
          [] -> concat [[C.witnessLower w, C.witnessUpper w] | w <- take 2 (sortOn (abs . F.contactGap . C.witnessRow) ws)]
          ps -> ps
        tipBounds = boxAround [V2 x y | V3 x y _ <- tipPoints]
    pure (pair, ws, bounds, tipBounds)
  let witnesses = concat [ws | (_, ws, _, _) <- views]
      firstWitnesses = pairWitnesses (22, 63) allWitnesses
  unless (length firstWitnesses == 4) (die "expected four archived overlap corners for pair 22–63")
  rows <- checked (directionRows (spreadHinges fixture) pins model start)
  let guards = map (contactGuard pins . C.witnessRow) witnesses
      firstIds = [0 .. length firstWitnesses - 1]
      allIds = [0 .. length guards - 1]
  putStrLn "Matched quadratic directions from one saved shape; no continuation."
  hFlush stdout
  (ordinary, ordinaryReport, ordinaryDetails) <- checked (constrainedStepDetailed OriginalWorkingSet 100 1e-3 free rows [])
  (guarded, guardedReport, guardedDetails) <- checked (constrainedStepDetailed OriginalWorkingSet 100 1e-3 free rows (take (length firstWitnesses) guards))
  extra <-
    if both
      then do
        (delta, report, details) <- checked (constrainedStepDetailed OriginalWorkingSet 100 1e-3 free rows guards)
        pure [("both", "Both contact pairs", propose delta, Just (report, details), Just delta, allIds)]
      else pure []
  let variants = [("archived", "Archived ordinary proposal", blockedProposal archive, Nothing, Nothing, []), ("control", "Matched unconstrained quadratic", propose ordinary, Just (ordinaryReport, ordinaryDetails), Just ordinary, []), ("guarded", "Contact-aware quadratic", propose guarded, Just (guardedReport, guardedDetails), Just guarded, firstIds)] ++ extra
      draw name mesh = do
        current <- checked (C.contactWitnesses model mesh)
        forM_ views $ \(pair, _, bounds, tipBounds) -> do
          cut <- checked (pairSection mesh pair)
          let ws = pairWitnesses pair current
              suffix = pairSuffix pair
          TIO.writeFile (output </> name ++ "-pair" ++ suffix ++ ".svg") (drawPair bounds mesh pair cut ws)
          TIO.writeFile (output </> name ++ "-tip" ++ suffix ++ ".svg") (drawPair tipBounds mesh pair cut ws)
      export name title point = do
        state <- writeState output name title study point
        draw name (savedMesh point)
        pure state
  createDirectoryIfMissing True (output </> "source" </> "source")
  forM_ (blockedFiles archive) $ \(name, bytes) -> BL.writeFile (output </> "source" </> name) bytes
  initial <- export "start" "Saved blocked shape" (SavedPoint 0 start)
  before <- checked (measurePatch study (SavedPoint 0 start))
  unless (abs (sum [r * r | (_, r) <- rows] - 2 * patchCost 1e8 before) < 1e-12) (die "direction rows changed the saved objective")
  comparisons <- forM variants $ \(key, title, proposal, quadratic, correction, constraintIds) -> do
    trials <- checked (replayCorrection study start proposal)
    full <- checked (scaledProposal 1 start proposal)
    movement <- checked (savedMovement (SavedPoint 0 start) (SavedPoint 0 full))
    let verified = maybe True (quadraticConverged . fst) quadratic
        selected = if verified then firstPassing trials else Nothing
        delta = IM.fromList (zip [0 ..] (zipWith (\p q -> q ^-^ position p) (samples start) proposal))
        linearGap (a, g) = g + sum [dot gradient (IM.findWithDefault (V3 0 0 0) i delta) | (i, gradient) <- IM.toList a]
        label k = key ++ "-" ++ show k
        -- Subtracting rounded proposal positions loses low bits. Keep the
        -- actual solved vector so its force balance can be independently
        -- checked under the stiff penalties; geometry uses stored positions.
        rawDelta = fromMaybe delta correction
    values <- forM (zip [0 :: Int ..] trials) $ \(k, trial) -> do
      let point = measuredPoint (replayMeasure trial)
      entry <- export (label k) (title <> " · fraction 1/" <> T.pack (show (2 ^ k :: Integer))) point
      cut <- checked (pairSection (savedMesh point) (22, 63))
      pairChecks <- forM pairs $ \pair@(a, b) -> do
        section <- checked (pairSection (savedMesh point) pair)
        pure (object ["triangles" .= [a, b], "intersectionLength" .= intersectionLength section, "crosses" .= sectionCrosses section])
      pure (object ["pairs" .= pairChecks, "state" .= entry, "scale" .= replayScale trial, "movement" .= replayMovement trial, "costDecreased" .= replayCostDecreased trial, "geometryPassed" .= replayGeometryPassed trial, "pairIntersectionLength" .= intersectionLength cut, "pairCrosses" .= sectionCrosses cut])
    let chosen = [label k | (k, trial) <- zip [0 :: Int ..] trials, Just (replayScale trial) == fmap replayScale selected]
    pure (object ["id" .= key, "title" .= title, "proposal" .= map xyz proposal, "correction" .= [xyz (IM.findWithDefault (V3 0 0 0) i rawDelta) | i <- [0 .. length (samples start) - 1]], "quadratic" .= fmap (reportValue . fst) quadratic, "contacts" .= maybe [] (map contactValue . quadraticContacts . snd) quadratic, "fullMovement" .= movement, "directionVerified" .= verified, "selectedState" .= chosen, "selectedScale" .= fmap replayScale selected, "acceptedEndpoint" .= (isJust selected && movement <= 1e-7), "constraintIds" .= constraintIds, "guardLinearGaps" .= map linearGap guards, "trials" .= values])
  let constraints = [object ["triangles" .= (let (a, b) = C.witnessTriangles w in [a, b]), "rawGap" .= F.contactGap (C.witnessRow w), "floor" .= min 0 (F.contactGap (C.witnessRow w)), "lower" .= xyz (C.witnessLower w), "upper" .= xyz (C.witnessUpper w), "row" .= rowValue row] | (w, row) <- zip witnesses guards]
      report = object ["gallery" .= T.pack gallery, "pairs" .= [[a, b] | (a, b) <- pairs], "pair" .= [22 :: Int, 63], "sourceIteration" .= (8 :: Int), "lengthWeight" .= (1e8 :: Double), "contactWeight" .= (1e10 :: Double), "damping" .= (1e-3 :: Double), "quadraticBudget" .= (100 :: Int), "lengthTolerance" .= (1e-5 :: Double), "contactTolerance" .= (1e-7 :: Double), "movementTolerance" .= (1e-7 :: Double), "continuousMotionChecked" .= False, "wholeCraneChecked" .= False, "start" .= initial, "startPositions" .= positions start, "freeVertices" .= free, "materialRows" .= map rowValue rows, "constraints" .= constraints, "directions" .= comparisons]
  BL.writeFile (output </> "checks.json") (encode report)
  template <- TIO.readFile ("study/fold-material" </> gallery ++ ".html")
  TIO.writeFile (destination </> gallery ++ ".html") (T.replace "/*BODY_DIRECTION_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode report))) template)
  putStrLn ("Wrote " ++ destination </> gallery ++ ".html")

rowValue :: QuadraticRow -> Value
rowValue (gradient, residual) = object ["gradient" .= [object ["vertex" .= i, "vector" .= xyz v] | (i, v) <- IM.toList gradient], "residual" .= residual]

reportValue :: QuadraticReport -> Value
reportValue r = object ["converged" .= quadraticConverged r, "iterations" .= quadraticIterations r, "violation" .= quadraticViolation r, "complementarity" .= quadraticComplementarity r, "balance" .= quadraticBalance r, "active" .= quadraticActive r]

contactValue :: ContactResidual -> Value
contactValue c = object ["sources" .= contactSources c, "selected" .= contactSelected c, "gap" .= contactGap c, "multiplier" .= contactNormalizedMultiplier c, "responseScale" .= contactResponseScale c]

-- Order is carried by each witness, while a geometric pair is unordered.
pairWitnesses :: (Int, Int) -> [C.ContactWitness] -> [C.ContactWitness]
pairWitnesses (a, b) = filter (\w -> let (c, d) = C.witnessTriangles w in min a b == min c d && max a b == max c d)

-- Retain the first gallery's filenames for pair 22–63.
pairSuffix :: (Int, Int) -> String
pairSuffix (22, 63) = ""
pairSuffix (a, b) = "-" ++ show a ++ "-" ++ show b
