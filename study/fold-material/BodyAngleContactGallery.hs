-- | One declared contact-aware angle construction, with every refusal saved.
-- Unjoined provisional triangles are never exported as shared paper. The saved
-- joined start stays visible when no new candidate passes production folding.
module BodyAngleContactGallery (writeBodyAngleContact) where

import AngleContact
import BodyCreaseSeed
import BodyCreaseSeedGallery (writeCreaseSeedState)
import BodyPatch
import ContactQuadratic qualified as Q
import Control.Monad (forM, unless, when)
import CranePocket (buildCranePocket)
import CraneSpread
import CreaseSeed (creaseResiduals)
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.List (isPrefixOf)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Folding (foldFrameWith)
import Senbazuru.Origami.Surface
import System.CPUTime (getCPUTime)
import System.Directory (canonicalizePath, createDirectoryIfMissing)
import System.FilePath (splitDirectories, (</>))
import System.IO (hFlush, stdout)

writeBodyAngleContact :: FilePath -> FilePath -> IO ()
writeBodyAngleContact source destination = do
  let output = destination </> "body-angle-contact"
  src <- splitDirectories <$> canonicalizePath source
  dst <- splitDirectories <$> canonicalizePath output
  when (src `isPrefixOf` dst || dst `isPrefixOf` src) (fail "contact-angle source and output must not overlap")
  raw <- BL.readFile (source </> "angles.fold")
  saved <- keyFrame <$> (loadFoldFile (source </> "angles.fold") >>= checked)
  crane <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= checked)
  atlas <- checked (buildCranePocket crane)
  study <- checked (bodyPatch atlas 0 0)
  alignment <- checked (bodySeedAlignment study)
  let fixture = patchSpread study
      material = bodyCreasePattern study
      input = AngleContactInput material (refinedMesh (spreadRefined fixture)) (refinedPanels (spreadRefined fixture)) (spreadContactOrders fixture) alignment
  unless (verticesCoords saved == verticesCoords material && edgesVertices saved == edgesVertices material && facesVertices saved == facesVertices material && edgesAssignment saved == edgesAssignment material) (fail "saved crease seed changed body material")
  rs <- checked (creaseResiduals material (edgesFoldAngle saved))
  unless (maximum (0 : map abs rs) <= 1e-10) (fail "saved crease seed does not close")
  startModel <- checked (foldFrameWith saved)
  start <- checked (installCreaseSeed study startModel)
  createDirectoryIfMissing True output
  BL.writeFile (output </> "source-angles.fold") raw
  putStrLn "One contact-aware angle construction: forty outer / two hundred inner corrections maximum."
  hFlush stdout
  started <- getCPUTime
  result <- checked (contactAngleSearch 40 input (edgesFoldAngle saved))
  -- Force the retained trace before ending the construction timing.
  TIO.putStrLn (contactAngleStop result <> "; states " <> T.pack (show (length (contactAngleHistory result))))
  finished <- getCPUTime
  endpoint <- case reverse (contactAngleHistory result) of m : _ -> pure m; _ -> fail "missing angle state"
  let finalFrame = material {edgesFoldAngle = measuredDegrees endpoint}
      folded = foldFrameWith finalFrame
      joined = maximum (0 : map abs (measuredClosure endpoint)) <= 1e-10
      trace = map measurementValue (contactAngleHistory result)
      attempts = map attemptValue (contactAngleAttempts result)
  BL.writeFile (output </> "angles.fold") (encode (FoldFile (Just 1.2) (Just "senbazuru contact-aware angles: diagnostic") Nothing Nothing Nothing [] finalFrame []))
  closedState <- writeCreaseSeedState output "closed" "Original closed patch" study
  startState <- writeCreaseSeedState output "start" "Saved angle-only pose · intersecting" start
  candidates <- case (joined, folded) of
    (True, Right model) -> forM [0, 1] $ \level -> do
      original <- checked (bodyPatch atlas level 0)
      candidate <- checked (installCreaseSeed original model)
      writeCreaseSeedState output (if level == 0 then "final" else "fine") (if level == 0 then "Final joined diagnostic · 30 triangles" else "Same diagnostic subdivided · 120 triangles") candidate
    _ -> pure []
  let report = object ["issue" .= (385 :: Int), "settings" .= object ["method" .= show Q.OriginalWorkingSet, "damping" .= (1e-8 :: Double), "residualScale" .= (0.01 :: Double), "outerBudget" .= (40 :: Int), "innerBudget" .= (200 :: Int), "stepLimitDegrees" .= (5 :: Double), "targetDisjointGap" .= (1e-6 :: Double), "closureLimit" .= (1e-10 :: Double)], "stopReason" .= contactAngleStop result, "constructionCpuSeconds" .= (fromIntegral (finished - started) / 1e12 :: Double), "corrections" .= (length (contactAngleHistory result) - 1), "closurePassed" .= joined, "productionFailure" .= either (Just . explain) (const Nothing) folded, "states" .= (closedState : startState : candidates), "trace" .= trace, "attempts" .= attempts, "acceptedMaterialEndpoint" .= False, "newBarrierSolves" .= (0 :: Int), "continuousMotionChecked" .= False, "wholeCraneChecked" .= False]
      bytes = encode report
  BL.writeFile (output </> "checks.json") bytes
  BL.writeFile (output </> "trace.json") (encode trace)
  BL.writeFile (output </> "attempts.json") (encode attempts)
  template <- TIO.readFile "study/fold-material/body-angle-contact.html"
  TIO.writeFile (destination </> "body-angle-contact.html") (T.replace "/*ANGLE_CONTACT_DATA*/null" (TE.decodeUtf8 (BL.toStrict bytes)) template)
  putStrLn ("Wrote " ++ destination </> "body-angle-contact.html")

measurementValue :: AngleMeasurement -> Value
measurementValue m = object ["degrees" .= measuredDegrees m, "closure" .= measuredClosure m, "maxClosure" .= maximum (0 : map abs (measuredClosure m)), "worstResidual" .= measuredWorst m, "gaps" .= [object ["triangles" .= [a, b], "gap" .= g, "target" .= t] | ((a, b), g, t) <- measuredGaps m]]

attemptValue :: ContactAngleAttempt -> Value
attemptValue a = object ["constraints" .= [object ["name" .= constraintName c, "gradient" .= gradientValue (constraintGradient c), "offset" .= constraintOffset c] | c <- attemptConstraints a], "direction" .= fmap gradientValue (attemptDirection a), "linear" .= fmap reportValue (attemptReport a), "linearContacts" .= fmap (map contactValue . Q.quadraticContacts) (attemptDetails a), "failure" .= attemptFailure a, "trials" .= [object ["fraction" .= f, "degrees" .= degrees, "measurement" .= fmap measurementValue m, "refusal" .= refusal] | ContactAngleTrial f degrees m refusal <- attemptTrials a]]

gradientValue :: IM.IntMap V3 -> Value
gradientValue g = object ["ids" .= IM.keys g, "values" .= [[x, y, z] | V3 x y z <- IM.elems g]]

reportValue :: Q.QuadraticReport -> Value
reportValue r = object ["converged" .= Q.quadraticConverged r, "iterations" .= Q.quadraticIterations r, "violation" .= Q.quadraticViolation r, "complementarity" .= Q.quadraticComplementarity r, "balance" .= Q.quadraticBalance r, "active" .= Q.quadraticActive r]

checked :: (Explain e) => Either e a -> IO a
checked = either (fail . T.unpack . explain) pure

contactValue :: Q.ContactResidual -> Value
contactValue c = object ["id" .= Q.contactConstraint c, "sources" .= Q.contactSources c, "selected" .= Q.contactSelected c, "gap" .= Q.contactGap c, "multiplier" .= Q.contactNormalizedMultiplier c, "scale" .= Q.contactResponseScale c]
