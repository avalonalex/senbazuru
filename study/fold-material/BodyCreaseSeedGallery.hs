-- | One bounded crease-based initialization, with failed angles preserved.
-- Only production-validated angles become a shared mesh. Readiness reuses the
-- previous initialization checks; a rigid pose is not a material equilibrium.
module BodyCreaseSeedGallery (writeBodyCreaseSeed, writeCreaseSeedState) where

import BodyCreaseSeed
import BodyInitializationCheck (probeInitialization)
import BodyPatch
import BodyPatchCheckpoints (SavedPoint (..))
import BodyPatchSubdivisionGallery (writeState)
import Control.Monad (forM, unless)
import CranePocket (buildCranePocket)
import CraneSpread
import CreaseSeed
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding (foldFrameWith)
import Senbazuru.Origami.Surface
import SurfaceContact qualified as C
import System.CPUTime (getCPUTime)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)

writeBodyCreaseSeed :: FilePath -> IO ()
writeBodyCreaseSeed destination = do
  source <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= checked)
  atlas <- checked (buildCranePocket source)
  baseline <- checked (bodyPatch atlas 0 0)
  let output = destination </> "body-crease-seed"
      paper = bodyCreasePattern baseline
  unless (length [a | a <- edgesAssignment paper, a `elem` [Mountain, Valley]] == 14) (fail "expected fourteen physical body creases")
  createDirectoryIfMissing True output
  BL.writeFile (output </> "material.fold") (encode (document "Unfolded body-patch material" paper))
  putStrLn "One angle construction: at most forty corrections; no material/contact solve."
  hFlush stdout
  started <- getCPUTime
  result <- checked (coordinateCreases 40 paper)
  TIO.putStrLn ("Angle construction: " <> angleStop result)
  finished <- getCPUTime
  let folded = foldFrameWith (angleFrame result)
      productionFailure = either (Just . explain) (const Nothing) folded
      trace = [object ["degrees" .= angleStepDegrees s, "maxResidual" .= angleStepResidual s, "cost" .= angleStepCost s, "fraction" .= angleStepFraction s, "linearResidual" .= angleLinearResidual s] | s <- angleHistory result]
  BL.writeFile (output </> "angles.fold") (encode (document "Candidate crease angles: closure is reported separately" (angleFrame result)))
  BL.writeFile (output </> "trace.json") (encode trace)
  closed <- writeCreaseSeedState output "closed" "Original closed patch" baseline
  candidates <- case (angleClosed result, folded) of
    (True, Right model) -> forM [0, 1] $ \level -> do
      old <- checked (bodyPatch atlas level 0)
      new <- checked (installCreaseSeed old model)
      writeCreaseSeedState output (if level == 0 then "coarse" else "fine") (if level == 0 then "Angle-derived body · 30 triangles" else "Subdivided same pose · 120 triangles") new
    _ -> pure []
  let report = object ["gallery" .= ("body-crease-seed" :: Text), "issue" .= (383 :: Int), "stopReason" .= angleStop result, "closurePassed" .= angleClosed result, "productionFailure" .= productionFailure, "anchorPatchEdge" .= unEdgeId (angleAnchor result), "sourceEdges" .= map unEdgeId (patchEdges baseline), "constructionCpuSeconds" .= (fromIntegral (finished - started) / 1e12 :: Double), "corrections" .= (length (angleHistory result) - 1), "budget" .= (40 :: Int), "trace" .= trace, "states" .= (closed : candidates), "acceptedMaterialEndpoint" .= False, "newBarrierSolves" .= (0 :: Int), "continuousMotionChecked" .= False, "wholeCraneChecked" .= False, "physicalThickness" .= (Nothing :: Maybe Double)]
      bytes = encode report
  BL.writeFile (output </> "checks.json") bytes
  template <- TIO.readFile "study/fold-material/body-crease-seed.html"
  TIO.writeFile (destination </> "body-crease-seed.html") (T.replace "/*CREASE_SEED_DATA*/null" (TE.decodeUtf8 (BL.toStrict bytes)) template)
  putStrLn ("Wrote " ++ destination </> "body-crease-seed.html")

writeCreaseSeedState :: FilePath -> String -> Text -> BodyPatch -> IO Value
writeCreaseSeedState output name title study = do
  let fixture = patchSpread study
      mesh = spreadMesh fixture
      original = refinedMesh (spreadRefined fixture)
      old = IM.fromList (zip [0 ..] (map position (samples original)))
  measured <- writeState output name title study (SavedPoint 0 mesh)
  model <- checked (C.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) (refinedPanels (spreadRefined fixture)) mesh)
  (ready, readiness) <- checked (probeInitialization study model mesh)
  pure (object ["id" .= name, "state" .= measured, "ready" .= ready, "readiness" .= readiness, "grips" .= [object ["vertex" .= i, "position" .= xyz p, "fromClosed" .= fmap xyz (IM.lookup i old), "movement" .= fmap (norm . (p ^-^)) (IM.lookup i old)] | (i, p) <- IM.toList (spreadPins fixture)]])

xyz :: V3 -> [Double]
xyz (V3 x y z) = [x, y, z]

document :: Text -> Frame -> FoldFile
document title frame = FoldFile (Just 1.2) (Just "senbazuru crease-based body initialization") Nothing (Just title) Nothing [] frame []

checked :: (Explain e) => Either e a -> IO a
checked = either (fail . T.unpack . explain) pure
