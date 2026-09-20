-- | Archive counterexamples and stage accounting, without material solves.
module BodyPatchCheckpointSpec (spec) where

import BodyPatch
import BodyPatchCheckpoints
import CranePocket
import CraneSpread
import Data.Aeson (Value (..), object, toJSON, (.=))
import Data.Aeson.Key (Key)
import Data.Aeson.KeyMap qualified as KM
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import FoldRelaxation (maxLengthError)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (contactPassed)
import Senbazuru.Origami.Surface
import Test.Hspec

spec :: Spec
spec = beforeAll load $ describe "saved body-patch checkpoints" $ do
  it "binds histories to both FOLD endpoints and the exact exhausted policy" $ \atlas -> do
    study <- right (bodyPatch atlas 0 5)
    let fixture = patchSpread study
        mesh = spreadMesh fixture
        record = sourceRecord study
        document records = object ["iterationLimitPerStage" .= (40 :: Int), "lengthWeights" .= ([1e2, 1e4, 1e6, 1e8] :: [Double]), "lengthTolerance" .= (1e-5 :: Double), "runs" .= (records :: [Value])]
        history schedule = toJSON [snapshot i mesh | i <- schedule]
    frame <- materialFrame <$> right (spreadSurface fixture mesh)
    let readOne = readPatchArchive "opening-5" study
        good = readOne (document [record]) record frame frame (history savedSchedule)
    fmap (map savedIteration) good `shouldBe` Right savedSchedule
    readOne (document [record, record]) record frame frame (history savedSchedule) `shouldSatisfy` isLeft
    mapM_ (\h -> readOne (document [record]) record frame frame h `shouldSatisfy` isLeft) [history (drop 1 savedSchedule), history (reverse savedSchedule), history (0 : savedSchedule)]
    mapM_
      (\r -> readOne (document [r]) r frame frame (history savedSchedule) `shouldSatisfy` isLeft)
      [set "converged" (Bool True) record, set "iterations" (Number 159) record, set "equilibrium" (object []) record, set "blockedStages" (toJSON [1 :: Int]) record, set "pins" (toJSON ([] :: [Value])) record]
    readOne (document [record]) (set "accepted" (Bool True) record) frame frame (history savedSchedule) `shouldSatisfy` isLeft
    readOne (set "lengthTolerance" (Number 0.01) (document [record])) record frame frame (history savedSchedule) `shouldSatisfy` isLeft
    readOne (document [record]) record frame {facesVertices = drop 1 (facesVertices frame)} frame (history savedSchedule) `shouldSatisfy` isLeft
    readOne (document [record]) record frame frame {frameExtras = mempty} (history savedSchedule) `shouldSatisfy` isLeft
    let moved = mesh {samples = [p {position = position p ^+^ V3 0.001 0 0} | p <- samples mesh]}
        badHold = toJSON (snapshot 0 mesh : [snapshot i moved | i <- drop 1 savedSchedule])
    readOne (document [record]) record frame frame badHold `shouldSatisfy` isLeft
    let freeMove = mesh {samples = [if i == (0 :: Int) then p {position = position p ^+^ V3 0.001 0 0} else p | (i, p) <- zip [0 ..] (samples mesh)]}
    movedFrame <- materialFrame <$> right (spreadSurface fixture freeMove)
    readOne (document [record]) record frame movedFrame (history savedSchedule) `shouldSatisfy` isLeft

  it "refuses malformed positions and false archived length errors" $ \atlas -> do
    study <- right (bodyPatch atlas 0 5)
    let fixture = patchSpread study
        mesh = spreadMesh fixture
        r = sourceRecord study
        doc = object ["iterationLimitPerStage" .= (40 :: Int), "lengthWeights" .= ([1e2, 1e4, 1e6, 1e8] :: [Double]), "lengthTolerance" .= (1e-5 :: Double), "runs" .= [r]]
        h first = toJSON (first : [snapshot i mesh | i <- drop 1 savedSchedule])
    frame <- materialFrame <$> right (spreadSurface fixture mesh)
    mapM_
      (\first -> readPatchArchive "opening-5" study doc r frame frame (h first) `shouldSatisfy` isLeft)
      [set "positions" (toJSON ([[0, 0]] :: [[Double]])) (snapshot 0 mesh), set "maxRelativeEdgeError" (Number 0) (snapshot 0 mesh)]

  it "does not mistake a penalty increase for an uphill interval" $ \atlas -> do
    study <- right (bodyPatch atlas 0 5)
    m <- right (measurePatch study (SavedPoint 40 (spreadMesh (patchSpread study))))
    checkpointWeight 40 `shouldBe` Right 1e2
    checkpointWeight 41 `shouldBe` Right 1e4
    checkpointWeight 120 `shouldBe` Right 1e6
    checkpointWeight 121 `shouldBe` Right 1e8
    checkpointWeight (-1) `shouldSatisfy` isLeft
    checkpointWeight 161 `shouldSatisfy` isLeft
    patchCost 1e4 m `shouldSatisfy` (> patchCost 1e2 m)
    savedMovement (measuredPoint m) (measuredPoint m) `shouldBe` Right 0
    let altered = (savedMesh (measuredPoint m)) {triangles = []}
    savedMovement (measuredPoint m) (SavedPoint 41 altered) `shouldSatisfy` isLeft

  it "remeasures the flat reference and accounts for each unique length edge once" $ \atlas -> do
    study <- right (bodyPatch atlas 0 0)
    m <- right (measurePatch study (SavedPoint 0 (spreadMesh (patchSpread study))))
    contactPassed (measuredContact m) `shouldBe` True
    patchCost 1e8 m `shouldSatisfy` (< 1e-15)
    study5 <- right (bodyPatch atlas 0 5)
    p <- right (measurePatch study5 (SavedPoint 0 (spreadMesh (patchSpread study5))))
    let sumSquares = sum [edgeLengthChange e ^ (2 :: Int) | e <- measuredEdges p]
    measuredLengthSquares p `shouldBe` sumSquares
    patchCost 100 p `shouldBe` 50 * sumSquares + 5000 * measuredContactSquares p + measuredCrease p + measuredPanel p

snapshot :: Int -> MaterialMesh -> Value
snapshot i mesh = object ["iteration" .= i, "maxRelativeEdgeError" .= maxLengthError mesh, "positions" .= [xyz (position p) | p <- samples mesh]]

sourceRecord :: BodyPatch -> Value
sourceRecord study = object ["id" .= ("opening-5" :: String), "degrees" .= (5 :: Int), "level" .= patchLevel study, "vertices" .= length (samples mesh), "triangles" .= length (triangles mesh), "sourceFaces" .= map unFaceId (patchFaces study), "corePanels" .= map unFaceId (patchCore study), "sourceEdges" .= map unEdgeId (patchEdges study), "sourceVertices" .= map unVertexId (patchVertices study), "sourceOrders" .= [[unFaceId a, unFaceId b] | (a, b) <- spreadOrders fixture], "pins" .= [object ["vertex" .= i, "position" .= xyz p] | (i, p) <- IM.toList (spreadPins fixture)], "iterations" .= (160 :: Int), "blockedStages" .= ([] :: [Value]), "converged" .= False, "accepted" .= False, "equilibrium" .= Null, "wholeCraneChecked" .= False, "continuousMotionChecked" .= False]
  where
    fixture = patchSpread study; mesh = spreadMesh fixture

xyz :: V3 -> [Double]
xyz (V3 x y z) = [x, y, z]

set :: Key -> Value -> Value -> Value
set key value (Object o) = Object (KM.insert key value o)
set _ _ value = value

load :: IO PocketMap
load = do source <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= right); right (buildCranePocket source)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
