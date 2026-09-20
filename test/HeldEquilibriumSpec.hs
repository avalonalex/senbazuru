-- | Verify the experiment's material and boundary conditions without adding
-- its four expensive solves to CI. The shared solver has its own regressions.
module HeldEquilibriumSpec (spec) where

import BendRefinement
import ClosedCrease
import Control.Monad (forM_)
import CoupledCrease
import CreasePairContact
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import FoldBending
import FoldMaterial (componentCount)
import HeldBend
import HeldEquilibrium
import IllustrationComparison (materialDifferences)
import PrescribedBend
import Senbazuru.Fold.Types (EdgeId (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Test.Hspec

spec :: Spec
spec = describe "held-panel equilibrium fixtures" $ do
  it "keeps exact original grips and one shared crease in all four sampled seeds" $ do
    V3 x _ z <- right gripTarget
    forM_ heldCases $ \(_, layout, budget) -> do
      c <- right (heldCase layout budget)
      let fixture = heldFixture c
          seed = coupledSeed fixture
          size = case budget of Triangles128 -> 128; Triangles256 -> 256
      length (triangles seed) `shouldBe` size
      componentCount seed `shouldBe` 1
      closedRoot (coupledReference fixture) `shouldBe` [0, 1, 2]
      heldGripRoundoff c `shouldSatisfy` (<= 1e-12)
      forM_ (zip [0 ..] (samples seed)) $ \(i, p) -> do
        let u = abs (materialU p)
            y = materialV p
            target | u <= 1 / 8 = Just (V3 u y 0) | u == 1 / 2 = Just (V3 x y z) | otherwise = Nothing
        IM.lookup i (coupledPins fixture) `shouldBe` target
        forM_ target $ \t -> position p `shouldBe` t
      checkCoupledMaterial fixture seed `shouldBe` Right ()

  it "preserves passive flat rests and reports sampled length errors instead of fitting them away" $
    forM_ heldCases $ \(_, layout, budget) -> do
      c <- right (heldCase layout budget)
      let reference = coupledReference (heldFixture c)
      m <- right (measureProbe reference)
      probeRelativeError m `shouldSatisfy` (> 1e-5)
      probeControlEnergy m `shouldBe` 0
      probeCreaseError m `shouldSatisfy` (< 1e-12)
      forM_ (closedHinges reference) $ \h -> case hingeRole h of
        SurfaceCrease edge -> do
          edge `shouldBe` EdgeId 0
          hingeRest h `shouldBe` pi
          hingeStiffness h `shouldBe` 0.5
        PanelBend -> hingeRest h `shouldBe` 0
        BendControl -> expectationFailure "the starting curve must not become an imposed spring"
        other -> expectationFailure ("unexpected crease role " ++ show other)
      expected <- right (gridReference (heldGrid c) SampledReference (caseCurve c))
      closedHinges reference `shouldBe` closedHinges expected

  it "keeps exact touching order without welding the two layers" $
    forM_ heldCases $ \(_, layout, budget) -> do
      c <- right (heldCase layout budget)
      let reference = coupledReference (heldFixture c)
          mesh = closedMesh reference
          byMaterial = M.fromList [((materialU p, materialV p), (i, position p)) | (i, p) <- zip [0 :: Int ..] (samples mesh)]
      forM_ (zip [0 :: Int ..] (samples mesh)) $ \(i, p) -> case M.lookup (negate (materialU p), materialV p) byMaterial of
        Just (j, q) -> do
          q `shouldBe` position p
          (i == j) `shouldBe` (materialU p == 0)
        Nothing -> expectationFailure "missing opposite panel"
      audit <- right (auditPairContact (closedOwners reference) mesh)
      pairMinimum audit `shouldBe` 0
      pairMaximum audit `shouldBe` 0

  it "rejects a moved grip and altered material identities" $ do
    c <- right (heldCase WholeBendLayout Triangles128)
    let f = heldFixture c
        mesh = coupledSeed f
        alter op = mesh {samples = [if i == (0 :: Int) then op p else p | (i, p) <- zip [0 ..] (samples mesh)]}
    checkCoupledMaterial f (alter (\p -> p {position = position p ^+^ V3 0 0 1e-8})) `shouldSatisfy` isLeft
    checkCoupledMaterial f (alter (\p -> p {sampleMaterial = sampleMaterial p ^+^ sampleMaterial p})) `shouldSatisfy` isLeft

  it "compares unmatched vertices across the complete material sheet" $ do
    a <- right (heldCase UniformLayout Triangles128)
    b <- right (heldCase WholeBendLayout Triangles128)
    let ma = coupledSeed (heldFixture a); mb = coupledSeed (heldFixture b)
    ds <- right (materialDifferences ma mb)
    maximum (map norm ds) `shouldSatisfy` (> 1e-5)
    same <- right (materialDifferences ma ma)
    maximum (map norm same) `shouldSatisfy` (< 1e-12)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
