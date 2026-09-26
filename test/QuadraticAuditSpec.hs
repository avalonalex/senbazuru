-- | Analytic examples distinguish equation rounding from a bad working set.
-- These tests never construct a body or run an active-set search.
module QuadraticAuditSpec (spec) where

import Data.Aeson (eitherDecodeStrict)
import Data.ByteString qualified as BS
import Data.Either (isLeft)
import QuadraticAudit
import QuadraticAuditArchive
import Test.Hspec

spec :: Spec
spec = describe "saved quadratic equality audit" $ do
  it "repairs rounded equality arithmetic without dropping any constraints" $ do
    result <- right (auditQuadratic tiny)
    auditPassed (savedMetrics result) `shouldBe` False
    exactStep result `shouldBe` [0, 0]
    exactForces result `shouldBe` [1]
    auditSelectedResidual (exactMetrics result) `shouldBe` 0
    auditBalanceSquared (exactMetrics result) `shouldBe` 0
    auditPassed (exactMetrics result) `shouldBe` True
    auditPassed (roundedMetrics result) `shouldBe` True

  it "still refuses an unselected stricter row after exact equality arithmetic" $ do
    result <- right (auditQuadratic tiny {auditRows = auditRows tiny ++ [AuditRow "stricter" [0, 1] (-0.1)]})
    auditPassed (exactMetrics result) `shouldBe` False
    auditViolation (exactMetrics result) `shouldBe` toRational (0.1 :: Double)

  it "refuses a selected equality that needs an attractive force" $ do
    result <- right (auditQuadratic tiny {auditCommon = -1})
    auditMinimumForce (exactMetrics result) `shouldBe` (-1)
    auditPassed (exactMetrics result) `shouldBe` False

  it "does not turn dependent selected equations into a unique solution" $ do
    auditQuadratic tiny {auditRows = auditRows tiny ++ auditRows tiny, auditSelected = [SelectedRow 0 1 1, SelectedRow 1 1 1]} `shouldBe` Left DependentAuditRows

  it "rejects malformed dimensions, ids, scales and nonfinite values" $ do
    mapM_
      (\p -> auditQuadratic p `shouldSatisfy` isLeft)
      [tiny {auditDamping = 0}, tiny {auditDamping = 0 / 0}, tiny {auditStep = [0]}, tiny {auditSelected = []}, tiny {auditSelected = [SelectedRow 4 1 1]}, tiny {auditSelected = [SelectedRow 0 1 0]}, tiny {auditSelected = [SelectedRow 0 1 1, SelectedRow 0 1 1]}, tiny {auditRows = [AuditRow "nonfinite" [0, 1 / 0] 0]}]

  it "checks the saved body equations without any geometry calculation" $ do
    bytes <- BS.readFile "study/fold-material/fixtures/body-angle-linear.json"
    value <- right (eitherDecodeStrict bytes)
    problem <- right (readAuditProblem value)
    result <- right (auditQuadratic problem)
    length (auditRows problem) `shouldBe` 1204
    length (auditSelected problem) `shouldBe` 12
    auditPassed (savedMetrics result) `shouldBe` False
    auditPassed (exactMetrics result) `shouldBe` True
    auditPassed (roundedMetrics result) `shouldBe` True
    auditSelectedResidual (exactMetrics result) `shouldBe` 0
    auditBalanceSquared (exactMetrics result) `shouldBe` 0
    (fromRational (normalizedCondition result) :: Double) `shouldSatisfy` (\x -> x > 3.08e7 && x < 3.10e7)
    (fromRational (largestStepChange result) :: Double) `shouldSatisfy` (< 1.36e-7)

tiny :: AuditProblem
tiny = AuditProblem 1 1 [0, -1e-8] [AuditRow "touching" [0, 1] 0, AuditRow "duplicate" [0, 1] 0] [SelectedRow 0 1 1]

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
