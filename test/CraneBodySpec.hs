-- | Isolate angle policy from material changes and from solver acceptance.
-- An all-held copy of the original flat crane is a cheap, known equilibrium
-- for testing the gates. Full free-patch solves are measured by the gallery;
-- repeating their long failed iterations here would add little coverage.
module CraneBodySpec (spec) where

import Control.Monad (forM_)
import CraneBody
import CraneRoot
import CraneSpread
import Data.IntMap.Strict qualified as IM
import Data.Set qualified as S
import FoldBending
import FoldRelaxation
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Surface
import Test.Hspec
import WingBending (finalMesh)

spec :: Spec
-- Each example owns its solver state; any shared fixture is immutable.
spec = parallel $ beforeAll load $ describe "selected crane body angle preferences" $ do
  it "changes only the two selected springs on the existing released patch" $ \studies -> do
    let baseline = rootSpread (bodyRoot (originalBody studies))
    forM_ [originalBody studies, weakBody studies, openBody studies] $ \study -> do
      let fixture = rootSpread (bodyRoot study)
      bodySelected study `shouldBe` S.fromList (map EdgeId [21, 46])
      rootNeighbours (bodyRoot study) `shouldBe` S.fromList (map FaceId [7, 8, 27, 43])
      spreadMesh fixture `shouldBe` spreadMesh baseline
      spreadPins fixture `shouldBe` spreadPins baseline
      spreadGrip fixture `shouldBe` spreadGrip baseline
      spreadOrders fixture `shouldBe` spreadOrders baseline
      spreadContactOrders fixture `shouldBe` spreadContactOrders baseline
      refinedEdges (spreadRefined fixture) `shouldBe` refinedEdges (spreadRefined baseline)
      let retained = filter (not . selected study)
      retained (spreadHinges fixture) `shouldBe` retained (spreadHinges baseline)
    let weak = rootSpread (bodyRoot (weakBody studies))
    sum (map hingeStiffness (filter (selected (weakBody studies)) (spreadHinges weak)))
      `shouldSatisfy` (\weight -> abs (weight / sum (map hingeStiffness (filter (selected (originalBody studies)) (spreadHinges baseline))) - 0.1) < 1e-12)
    map hingeRest (spreadHinges weak) `shouldBe` map hingeRest (spreadHinges baseline)

  it "keeps the original fold angles separate from the new spring preferences" $ \studies -> do
    let study = openBody studies
        fixture = rootSpread (bodyRoot study)
        flat = refinedMesh (spreadRefined fixture)
    angles <- filter angleSelected <$> right (bodyAngles study flat)
    angles `shouldSatisfy` (not . null)
    forM_ angles $ \a -> do
      angleOriginal a `shouldBe` pi
      anglePreferred a `shouldSatisfy` (\p -> abs (p - 170 * pi / 180) < 1e-12)
      abs (angleError (angleAchieved a) (angleOriginal a)) `shouldSatisfy` (< 1e-9)
      abs (angleError (angleAchieved a) (anglePreferred a)) `shouldSatisfy` (> 0.17)
    (originalEnergy, _) <- right (bendingEnergy (bodyOriginalHinges study) flat)
    (changedEnergy, _) <- right (bendingEnergy (spreadHinges fixture) flat)
    changedEnergy `shouldSatisfy` (> originalEnergy)

  it "waives only selected original-angle errors and still requires equilibrium" $ \studies -> do
    let study = heldBody studies
        result = heldResult studies
        mesh = heldMesh studies
        shift choose h = if choose h then h {hingeRest = hingeRest h - 0.02} else h
        changedSelected = study {bodyOriginalHinges = map (shift (selected study)) (bodyOriginalHinges study)}
        changedOther = study {bodyOriginalHinges = map (shift (\h -> hingeRole h == SurfaceCrease (EdgeId 5))) (bodyOriginalHinges study)}
    -- Perturb only the reference targets, leaving one verified physical mesh
    -- and its solver result identical. This isolates which angle gate applies.
    right (bodyAccepted study result mesh) `shouldReturn` (True, True)
    right (bodyAccepted changedSelected result mesh) `shouldReturn` (False, True)
    right (bodyAccepted changedOther result mesh) `shouldReturn` (False, False)
    right (bodyAccepted changedSelected result {converged = False} mesh) `shouldReturn` (False, False)

  it "does not let the selected policy hide an incompatible touching-layer grip" $ \studies -> do
    let study = originalBody studies
        root = bodyRoot study
        crossed = crossedGrip (rootSpread root)
        invalid = study {bodyRoot = root {rootSpread = crossed}}
    contact <- right (spreadCheck crossed (spreadMesh crossed))
    reversedOrders contact `shouldSatisfy` (not . null)
    right (bodyAccepted invalid (heldResult studies) (spreadMesh crossed)) `shouldReturn` (False, False)

data Studies = Studies
  { originalBody :: CraneBody,
    weakBody :: CraneBody,
    openBody :: CraneBody,
    heldBody :: CraneBody,
    heldResult :: Relaxation,
    heldMesh :: MaterialMesh
  }

load :: IO Studies
load = do
  source <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= right)
  original <- right (craneBody source 3 OriginalPreferences)
  weak <- right (craneBody source 3 WeakerBody)
  opened <- right (craneBody source 3 OpenBody)
  let root = bodyRoot opened
      fixture = rootSpread root
      flat = refinedMesh (spreadRefined fixture)
      held = opened {bodyRoot = root {rootSpread = fixture {spreadMesh = flat, spreadPins = IM.fromList (zip [0 ..] (map position (samples flat)))}}}
  result <- right (solveSpread (Settings 2 1e-5) (rootSpread (bodyRoot held)))
  mesh <- right (finalMesh result)
  pure (Studies original weak opened held result mesh)

selected :: CraneBody -> Hinge -> Bool
selected study h = case hingeRole h of SurfaceCrease eid -> S.member eid (bodySelected study); _ -> False

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
