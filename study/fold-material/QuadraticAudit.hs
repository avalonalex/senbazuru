-- | Audit a saved constrained direction without searching for a new working
-- set or touching paper. A working set is the subset of inequalities the
-- optimizer treats as equalities. Here that subset is fixed by the archive.
--
-- Every input Double is converted to its exact binary rational value. Solving
-- those same equalities in Rational separates rounding in the linear algebra
-- from an infeasible choice of constraints. It cannot certify the derivatives
-- used to create the equations, or any actual folded geometry. The routine is
-- intentionally small and dense: exact arithmetic is a diagnostic, not a new
-- material solver. See docs/notes/body-angle-audit.md.
module QuadraticAudit
  ( AuditRow (..),
    SelectedRow (..),
    AuditProblem (..),
    AuditMetrics (..),
    AuditResult (..),
    AuditError (..),
    auditQuadratic,
  )
where

import Control.Monad (unless)
import Data.List (nub, transpose)
import Data.Text (Text)
import Senbazuru.Explain (Explain (..))

data AuditRow = AuditRow {auditName :: Text, auditCoefficients :: [Double], auditOffset :: Double} deriving stock (Eq, Show)

data SelectedRow = SelectedRow {selectedSource :: Int, selectedMultiplier :: Double, selectedScale :: Double} deriving stock (Eq, Show)

-- | The objective is (common + last coordinate)^2 + damping * ||step||^2.
-- A row (a,g) means a dot step + g >= 0. Multipliers in the saved input use
-- the original solver's response normalization; divide by scale to undo it.
data AuditProblem = AuditProblem
  { auditDamping :: Double,
    auditCommon :: Double,
    auditStep :: [Double],
    auditRows :: [AuditRow],
    auditSelected :: [SelectedRow]
  }
  deriving stock (Eq, Show)

data AuditMetrics = AuditMetrics
  { auditGaps :: [Rational],
    auditViolation :: Rational,
    auditComplementarity :: Rational,
    auditBalanceSquared :: Rational,
    auditMinimumForce :: Rational,
    auditSelectedResidual :: Rational,
    auditPassed :: Bool
  }
  deriving stock (Eq, Show)

data AuditResult = AuditResult
  { savedMetrics :: AuditMetrics,
    exactMetrics :: AuditMetrics,
    roundedMetrics :: AuditMetrics,
    exactStep :: [Rational],
    exactForces :: [Rational],
    normalizedCondition :: Rational,
    largestStepChange :: Rational
  }
  deriving stock (Eq, Show)

data AuditError = InvalidAudit | DependentAuditRows deriving stock (Eq, Show)

instance Explain AuditError where
  explain InvalidAudit = "the quadratic audit needs finite compatible rows, positive damping/scales and distinct valid selected row ids"
  explain DependentAuditRows = "the saved selected equations are exactly dependent; there is no unique equality solution to audit"

-- | Check all original rows, including duplicates and unselected rows. The
-- exact candidate and its once-rounded Double version are diagnostics only.
-- Neither is a request to change the stored paper or weaken the solver gates.
auditQuadratic :: AuditProblem -> Either AuditError AuditResult
auditQuadratic p = do
  let n = length (auditStep p)
      rows = auditRows p
      selected = auditSelected p
      indices = map selectedSource selected
      finite x = not (isNaN x || isInfinite x)
  unless (n > 0 && not (null rows) && not (null selected) && auditDamping p > 0 && all finite (auditDamping p : auditCommon p : auditStep p) && all (\r -> length (auditCoefficients r) == n && all finite (auditOffset r : auditCoefficients r)) rows && length indices == length (nub indices) && all (\s -> selectedSource s >= 0 && selectedSource s < length rows && finite (selectedMultiplier s) && finite (selectedScale s) && selectedScale s > 0) selected) (Left InvalidAudit)
  let as = map (map toRational . auditCoefficients) rows
      gs = map (toRational . auditOffset) rows
      at i xs = case drop i xs of x : _ -> Right x; [] -> Left InvalidAudit
  bs <- traverse (`at` as) indices
  offsets <- traverse (`at` gs) indices
  let h = replicate (n - 1) (toRational (auditDamping p)) ++ [1 + toRational (auditDamping p)]
      rhs = replicate (n - 1) 0 ++ [negate (toRational (auditCommon p))]
      base = zipWith (/) rhs h
      gram = [[dot a (zipWith (/) b h) | b <- bs] | a <- bs]
      demand = zipWith (\a g -> -g - dot a base) bs offsets
  inverse <- invert gram
  let forces = map (`dot` demand) inverse
      direction = zipWith (+) base (zipWith (/) (map (`dot` forces) (transpose bs)) h)
      scales = map (toRational . selectedScale) selected
      savedForces = zipWith (/) (map (toRational . selectedMultiplier) selected) scales
      measure d ls =
        let gaps = zipWith (\a g -> dot a d + g) as gs
            chosenGaps = [v | i <- indices, (j, v) <- zip [0 ..] gaps, j == i]
            forceAt i = sum [lambda * scale * scale | (j, lambda, scale) <- zip3 indices ls scales, i == j]
            violation = maximum (0 : map negate gaps)
            complementarity = maximum (0 : [abs (min g (forceAt i)) | (i, g) <- zip [0 ..] gaps])
            imbalance = zipWith (-) (zipWith (-) (zipWith (*) h d) rhs) (map (`dot` ls) (transpose bs))
            balance = dot imbalance imbalance
            minimumForce = minimum ls
            passed = violation <= toRational (1e-12 :: Double) && complementarity <= toRational (1e-12 :: Double) && balance <= toRational (1e-6 :: Double) ^ (2 :: Int) && minimumForce >= 0
         in AuditMetrics gaps violation complementarity balance minimumForce (maximum (0 : map abs chosenGaps)) passed
      rounded = map (toRational . (fromRational :: Rational -> Double))
      -- N = D^-1 Gram D^-1 is the solver's unit-diagonal response matrix.
      -- Its infinity condition number is ||N||inf * ||N^-1||inf. Use saved
      -- scales so the audit describes precisely that normalization.
      normalized = [[x / s / t | (x, t) <- zip row scales] | (row, s) <- zip gram scales]
      inverseNormalized = [[x * s * t | (x, t) <- zip row scales] | (row, s) <- zip inverse scales]
      normInf matrix = maximum (0 : map (sum . map abs) matrix)
  pure (AuditResult (measure (map toRational (auditStep p)) savedForces) (measure direction forces) (measure (rounded direction) (rounded forces)) direction forces (normInf normalized * normInf inverseNormalized) (maximum (0 : zipWith (\x y -> abs (x - y)) direction (map toRational (auditStep p)))))

dot :: [Rational] -> [Rational] -> Rational
dot a b = sum (zipWith (*) a b)

-- Exact Gauss-Jordan elimination, with row swaps when a diagonal is zero.
-- There is no rank tolerance: dependence here means exact dependence in the
-- recorded binary numbers. Approximate dependence is exposed by conditioning.
invert :: [[Rational]] -> Either AuditError [[Rational]]
invert matrix = go 0 (zipWith (++) matrix identity)
  where
    n = length matrix
    identity = [[if i == j then 1 else 0 | j <- [0 .. n - 1]] | i <- [0 .. n - 1]]
    go k rows
      | k == n = Right (map (drop n) rows)
      | otherwise = do
          let before = take k rows
              remaining = drop k rows
              coefficient row = case drop k row of x : _ -> x; [] -> 0
              pick [] = Nothing
              pick (row : rest)
                | coefficient row /= 0 = Just (row, rest)
                | otherwise = do (pivot, others) <- pick rest; pure (pivot, row : others)
          (pivot, others) <- maybe (Left DependentAuditRows) Right (pick remaining)
          let unit = map (/ coefficient pivot) pivot
              eliminate row = zipWith (-) row (map (coefficient row *) unit)
          go (k + 1) (map eliminate before ++ [unit] ++ map eliminate others)
