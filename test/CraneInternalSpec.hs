-- | Changes to holds and force scope must not change the material or the
-- independent validity check. Long diagnostic solves stay in the gallery.
module CraneInternalSpec (spec) where

import Control.Monad (forM_)
import CraneInternal
import CraneRoot
import CraneSpread
import Data.IntMap.Strict qualified as IM
import Data.Set qualified as S
import FoldRelaxation
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
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
    (_, continued) <- right (continuePinnedContact (Settings 2 1e-5) (layersPins fixture) (layersHinges fixture) contact (layersMesh fixture))
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

load :: IO Frame
load = keyFrame <$> (loadFoldFile "examples/crane.fold" >>= right)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
