-- | Analytic force balances test the optimizer without paper geometry.
module ContactQuadraticSpec (spec) where

import ContactQuadratic
import Control.Monad (forM_)
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Test.Hspec

spec :: Spec
spec = describe "small constrained material quadratic" $ do
  it "balances a coupled contact against the material objective" $ do
    -- With damping 1, the unconstrained minimum is (-1/2,-1).
    -- On x+y=0 the minimum is (1/4,-1/4), with positive contact force.
    (step, report) <- right (constrainedStep 20 1 [0] material [row (V3 1 1 0) 0])
    near step (V3 0.25 (-0.25) 0)
    quadraticConverged report `shouldBe` True
    quadraticActive report `shouldBe` 1
    quadraticBalance report `shouldSatisfy` (< 1e-10)

  it "allows separation without an attractive contact force" $ do
    (step, report) <- right (constrainedStep 20 1 [0] material [row (V3 1 0 0) 1])
    near step (V3 (-0.5) (-1) 0)
    quadraticConverged report `shouldBe` True
    quadraticActive report `shouldBe` 0

  it "handles duplicate and linearly dependent touching constraints" $ do
    let x = row (V3 1 0 0) 0
        y = row (V3 0 1 0) 0
        sumRow = row (V3 1 1 0) 0
    forM_ [[x, y, x, sumRow], [sumRow, y, x], [row (V3 2 0 0) 0, x, y]] $ \constraints -> do
      (step, report) <- right (constrainedStep 30 1 [0] material constraints)
      near step (V3 0 0 0)
      quadraticConverged report `shouldBe` True
      quadraticViolation report `shouldSatisfy` (<= 1e-12)

  it "releases a provisional contact when the final force would pull" $ do
    -- x+y>=0 blocks first at the origin, but x>=0 pushes the final solution
    -- to (0,1). The first contact must release and allow x+y to become positive.
    (step, report) <- right (constrainedStep 30 1 [0] [row (V3 1 0 0) 4, row (V3 0 1 0) (-2)] [row (V3 1 1 0) 0, row (V3 1 0 0) 0])
    near step (V3 0 1 0)
    quadraticConverged report `shouldBe` True
    quadraticActive report `shouldBe` 1

  it "exchanges a nearly parallel weaker contact without relaxing any residual" $ do
    -- x >= 0 is selected first. At y = -1, x + e*y >= 0 is stricter,
    -- but its extra direction is too small to add to the current dense factor.
    let e = 1e-7
        constraints = [row (V3 1 0 0) 0, row (V3 1 e 0) 0]
        y = (e - 2) / (2 * (1 + e * e))
    (_, old) <- right (constrainedStep 30 1 [0] material constraints)
    quadraticConverged old `shouldBe` False
    quadraticViolation old `shouldSatisfy` (> 1e-8)
    forM_ [constraints, reverse constraints, constraints ++ take 1 constraints] $ \gaps -> do
      (step, report) <- right (constrainedStepWith ExchangeNearDependent 30 1 [0] material gaps)
      near step (V3 (-(e * y)) y 0)
      quadraticConverged report `shouldBe` True
      quadraticViolation report `shouldSatisfy` (<= 1e-12)
      quadraticComplementarity report `shouldSatisfy` (<= 1e-12)
      quadraticBalance report `shouldSatisfy` (<= 1e-6)
    (_, exhausted) <- right (constrainedStepWith ExchangeNearDependent 2 1 [0] material constraints)
    quadraticConverged exhausted `shouldBe` False

  it "does not call an exhausted working set converged" $ do
    (_, report) <- right (constrainedStep 1 1 [0] material [row (V3 1 1 0) 0])
    quadraticConverged report `shouldBe` False

  it "refuses invalid equations and an infeasible starting gap" $ do
    forM_ [constrainedStep 0 1 [0] material [], constrainedStep 10 0 [0] material [], constrainedStep 10 1 [0, 0] material [], constrainedStep 10 1 [] material [], constrainedStep 10 1 [0] material [row (V3 1 0 0) (-1)], constrainedStep 10 1 [0] material [(IM.empty, -1)], constrainedStep 10 1 [0] [row (V3 (0 / 0) 0 0) 0] []] $ \result -> result `shouldSatisfy` isLeft

material :: [QuadraticRow]
material = [row (V3 1 0 0) 1, row (V3 0 1 0) 2]

row :: V3 -> Double -> QuadraticRow
row v r = (IM.singleton 0 v, r)

near :: IM.IntMap V3 -> V3 -> Expectation
near actual expected = maybe (expectationFailure "lost the free vertex") (\v -> norm (v ^-^ expected) `shouldSatisfy` (< 1e-10)) (IM.lookup 0 actual)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
