-- | Changes to holds and force scope must not change the material or the
-- independent validity check. Long diagnostic solves stay in the gallery.
module CraneInternalSpec (spec) where

import ClosedCrease
import Control.Monad (forM_)
import CraneInternal
import CraneRoot
import CraneSpread
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.Set qualified as S
import FoldRelaxation
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (contactPassed, reversedOrders)
import Senbazuru.Origami.Surface
import SurfaceContact qualified as Contact
import Test.Hspec
import WingLayers

spec :: Spec
spec = do
  beforeAll load $ describe "internal crane crease controls" $ do
    it "finds two joined lines while retaining all original material and grip identities" $ \source -> do
      original <- right (internalStudy source OriginalPatch)
      let fixture = rootSpread (internalRoot original)
      internalPairs original `shouldBe` [(FaceId 27, FaceId 8), (FaceId 43, FaceId 7)]
      forM_ internalCreases $ \eid -> do
        let line = internalLineVertices original eid
        S.size line `shouldBe` 9
        length (filter (`IM.member` spreadPins fixture) (S.toList line)) `shouldBe` 1
      forM_ [HeldLines, InternalForces, HeldLinesInternalForces] $ \control -> do
        changed <- right (internalStudy source control)
        let other = rootSpread (internalRoot changed)
        spreadMesh other `shouldBe` spreadMesh fixture
        spreadHinges other `shouldBe` spreadHinges fixture
        spreadOrders other `shouldBe` spreadOrders fixture
        spreadGrip other `shouldBe` spreadGrip fixture
        refinedEdges (spreadRefined other) `shouldBe` refinedEdges (spreadRefined fixture)
        forM_ (S.toList (spreadGrip fixture)) $ \v -> IM.lookup v (spreadPins other) `shouldBe` IM.lookup v (spreadPins fixture)

    it "adds only the sixteen previously free shared crease vertices to the holds" $ \source -> do
      original <- right (internalStudy source OriginalPatch)
      held <- right (internalStudy source HeldLines)
      let originalPins = spreadPins (rootSpread (internalRoot original))
          heldPins = spreadPins (rootSpread (internalRoot held))
          linesHeld = S.unions (map (internalLineVertices original) internalCreases)
      IM.intersection heldPins originalPins `shouldBe` originalPins
      IM.keys (IM.difference heldPins originalPins) `shouldBe` [v | v <- S.toAscList linesHeld, IM.notMember v originalPins]
      IM.size heldPins - IM.size originalPins `shouldBe` 16

    it "keeps omitted contact requirements in the independent full-sheet check" $ \source -> do
      study <- right (internalStudy source InternalForces)
      let root = internalRoot study
          fixture = crossedGrip (rootSpread root)
          bad = study {internalRoot = root {rootSpread = fixture}}
      internalRequirements study `shouldBe` internalPairs study
      length (spreadOrders fixture) `shouldBe` 902
      report <- right (spreadCheck fixture (spreadMesh fixture))
      contactPassed report `shouldBe` False
      reversedOrders report `shouldSatisfy` (not . null)
      fullInternalForces study `shouldBe` False
      right (internalAccepted bad (Relaxation [] True Nothing) (spreadMesh fixture)) `shouldReturn` False

  it "records held-contact refusals without changing the solved result" $ do
    free <- right (wingLayers 8 20)
    let fixture = free {layersPins = IM.fromList (zip [0 ..] (map position (samples (layersMesh free))))}
    contact <- right (Contact.prepareContact 0 (V3 0 0 1) [(FaceId 0, FaceId 1)] (layersOwners fixture) (layersMesh fixture))
    let solve = relaxPinnedContact (Settings 2 1e-5) (layersPins fixture) (layersHinges fixture) contact (layersMesh fixture)
    (result, audit) <- right (diagnosePinnedContact (Settings 2 1e-5) (layersPins fixture) (layersHinges fixture) contact (layersMesh fixture))
    solve `shouldBe` Right result
    (continuedResult, continued) <- right (continuePinnedContact (Settings 2 1e-5) (layersPins fixture) (layersHinges fixture) contact (layersMesh fixture))
    (tracedResult, traced) <- right (tracePinnedContact (Settings 2 1e-5) (layersPins fixture) (layersHinges fixture) contact (layersMesh fixture))
    tracedResult `shouldBe` continuedResult
    rejectionSummaries traced `shouldBe` rejectionSummaries continued
    solverSteps continued `shouldBe` []
    case solverSteps traced of
      [step] -> do
        solverScale step `shouldBe` Nothing
        solverFullProposal step `shouldBe` solverStart step
        equilibriumMovement (solverEquilibrium step) `shouldBe` 0
        length (solverRefusals step) `shouldBe` 31
        map trialScale (solverRefusals step) `shouldBe` [0.5 ^ n | n <- [0 :: Int .. 30]]
      _ -> expectationFailure "expected one stationary full-proposal record"
    tracePinnedContact (Settings 41 1e-5) (layersPins fixture) (layersHinges fixture) contact (layersMesh fixture) `shouldSatisfy` isLeft
    rejectionSummaries continued `shouldSatisfy` (not . null)
    forM_ (rejectionSummaries continued) $ \summary -> do
      trialLengthWeight (firstRejection summary) `shouldBe` 1e8
      trialLengthWeight (lastRejection summary) `shouldBe` 1e8
    rejectionSummaries audit `shouldSatisfy` (not . null)
    forM_ (rejectionSummaries audit) $ \summary -> do
      rejectionCount summary `shouldSatisfy` (> 0)
      forM_ [firstRejection summary, lastRejection summary] $ \trial -> do
        triangles (trialStart trial) `shouldBe` triangles (layersMesh fixture)
        trialScale trial `shouldSatisfy` (> 0)
        trialScale trial `shouldSatisfy` (<= 1)
        forM_ (IM.toList (layersPins fixture)) $ \(v, p) ->
          IM.lookup v (IM.fromList (zip [0 ..] (map position (samples (trialFinish trial))))) `shouldBe` Just p

  it "records a moving full proposal without changing final-weight corrections" $ do
    fixture <- right (closedCrease 1 Open)
    let mesh = closedMesh fixture
        pins = IM.fromList [(i, position p) | (i, p) <- zip [0 ..] (samples mesh), i `elem` closedRoot fixture]
        hinges = closedHinges fixture
        settings = Settings 2 1e-5
    contact <- right (Contact.prepareContact 0 (V3 0 0 1) [(FaceId 0, FaceId 1)] (closedOwners fixture) mesh)
    (ordinary, _) <- right (continuePinnedContact settings pins hinges contact mesh)
    (traced, audit) <- right (tracePinnedContact settings pins hinges contact mesh)
    traced `shouldBe` ordinary
    solverSteps audit `shouldSatisfy` (not . null)
    forM_ (solverSteps audit) $ \step -> do
      let distances = zipWith (\a b -> norm (position b ^-^ position a)) (samples (solverStart step)) (samples (solverFullProposal step))
          full = maximum (0 : distances)
      abs (full - equilibriumMovement (solverEquilibrium step)) `shouldSatisfy` (< 1e-14)
      full `shouldSatisfy` (> 1e-7)
      case solverScale step of
        Nothing -> solverCandidate step `shouldBe` solverStart step
        Just scale -> forM_ (zip3 (samples (solverStart step)) (samples (solverFullProposal step)) (samples (solverCandidate step))) $ \(a, b, c) ->
          norm (position c ^-^ (position a ^+^ (scale *^ (position b ^-^ position a)))) `shouldSatisfy` (< 1e-14)
      forM_ (solverStart step : solverFullProposal step : solverCandidate step : map trialFinish (solverRefusals step)) $ \candidate -> do
        triangles candidate `shouldBe` triangles mesh
        map sampleMaterial (samples candidate) `shouldBe` map sampleMaterial (samples mesh)
        forM_ (IM.toList pins) $ \(i, target) -> IM.lookup i (IM.fromList (zip [0 ..] (map position (samples candidate)))) `shouldBe` Just target

load :: IO Frame
load = keyFrame <$> (loadFoldFile "examples/crane.fold" >>= right)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
