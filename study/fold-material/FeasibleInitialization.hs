-- | Find a separated starting shape without buying gaps by stretching paper.
-- Each material edge has two inequalities, bounding its relative length error.
-- One additional unknown bounds ALL remaining contact deficits: the amount by
-- which a gap falls short of its target. Reducing that common deficit improves
-- the worst gap, rather than a sum that can hide a worsening contact.
--
-- The quadratic solver needs a feasible linear starting point. Its extra
-- unknown starts at the measured worst deficit, so every contact inequality
-- initially holds even when the paper intersects. This is bookkeeping for
-- constructing a seed, not permission to accept intersecting paper. Actual
-- lengths, gaps and displacement are remeasured at every trial, and a separate
-- readiness check decides whether the result may enter a material solver.
--
-- Coordinates and the common deficit are scaled by one microunit of the sheet.
-- The existing solver stores vectors in V3 blocks: only the x coordinate of
-- the extra block is the scalar. Its y/z entries are unused and damped to zero.
-- This block is NEVER a material vertex. Small positive damping stabilizes
-- the direction and favors small increments; we do not claim an exact global
-- minimax solution. No bending energy participates in this construction.
module FeasibleInitialization
  ( FeasibleConstraint (..),
    FeasibleProblem (..),
    FeasibleTrial (..),
    FeasibleAttempt (..),
    FeasibleRun (..),
    feasibleInitialization,
    feasibilityProblem,
    clearanceDeficit,
    feasibilityRefusal,
    feasibilityScale,
    feasibilityDamping,
    feasibilityInnerBudget,
  )
where

import BodyInitialization
import ContactQuadratic qualified as Q
import Control.Monad (forM, unless)
import CreaseInequality (materialRows)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import FoldContact (ContactRow (..))
import FoldMaterial (meshEdges)
import FoldRelaxation (maxLengthError)
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import SurfaceContact qualified as C

data FeasibleConstraint = FeasibleConstraint
  { feasibleName :: Text,
    feasibleGradient :: IM.IntMap V3,
    feasibleOffset :: Double
  }
  deriving stock (Eq, Show)

data FeasibleProblem = FeasibleProblem
  { problemAuxiliary :: Int,
    problemDeficit :: Double,
    problemFree :: [Int],
    problemConstraints :: [FeasibleConstraint]
  }
  deriving stock (Eq, Show)

data FeasibleTrial = FeasibleTrial
  { feasibleFraction :: Double,
    feasibleTrialMesh :: MaterialMesh,
    feasibleTrialDeficit :: Maybe Double,
    feasibleTrialRefusal :: Maybe Text
  }
  deriving stock (Show)

data FeasibleAttempt = FeasibleAttempt
  { feasibleBefore :: MaterialMesh,
    feasibleProblem :: FeasibleProblem,
    feasibleProposal :: Maybe MaterialMesh,
    feasibleDelta :: Maybe (IM.IntMap V3),
    feasibleReport :: Maybe Q.QuadraticReport,
    feasibleDetails :: Maybe Q.QuadraticDetails,
    feasibleFailure :: Maybe Text,
    feasibleTrials :: [FeasibleTrial]
  }
  deriving stock (Show)

data FeasibleRun = FeasibleRun
  { feasibleHistory :: [MaterialMesh],
    feasibleAttempts :: [FeasibleAttempt],
    feasibleStop :: Text,
    feasibleReady :: Bool
  }
  deriving stock (Show)

feasibilityScale, feasibilityDamping :: Double
feasibilityScale = 1e-6
feasibilityDamping = 1e-8

feasibilityInnerBudget :: Int
feasibilityInnerBudget = 200

-- | All current inherited overlap corners participate, including positive gaps
-- and joined triangles. Only disjoint triangles have a positive target.
gapRows :: IM.IntMap V3 -> C.OrderedContact -> MaterialMesh -> Either InitializationError [(Text, Q.QuadraticRow)]
gapRows pins model mesh = do
  ws <- adapt (C.contactWitnesses model mesh)
  let topology = IM.fromList (zip [0 ..] (triangles mesh))
      vertices i = case IM.lookup i topology of Just (a, b, c) -> [a, b, c]; Nothing -> []
      row k w =
        let (a, b) = C.witnessTriangles w
            target = if all (`notElem` vertices b) (vertices a) then initializationTarget else 0
            r = C.witnessRow w
            gradient = IM.difference (IM.fromListWith (^+^) (contactGradient r)) pins
         in ("contact " <> tshow a <> "-" <> tshow b <> " corner " <> tshow k, (gradient, (contactGap r - target) / feasibilityScale))
  pure (zipWith row [0 :: Int ..] ws)

clearanceDeficit :: C.OrderedContact -> MaterialMesh -> Either InitializationError Double
clearanceDeficit model mesh = do
  rows <- gapRows IM.empty model mesh
  let deficit = feasibilityScale * maximum (0 : [negate gap | (_, (_, gap)) <- rows])
  unless (finite deficit) (bad "nonfinite clearance deficit")
  pure deficit

-- | The previous iterate is inside every length/box inequality. The common
-- deficit makes all contact inequalities feasible too, so zero increment is
-- valid input to the existing working-set solver. No gap is clamped or waived.
feasibilityProblem :: IM.IntMap V3 -> C.OrderedContact -> MaterialMesh -> MaterialMesh -> Either InitializationError FeasibleProblem
feasibilityProblem pins model start current = do
  unless (triangles start == triangles current && map sampleMaterial (samples start) == map sampleMaterial (samples current)) (bad "feasibility construction changed material")
  let points = IM.fromList (zip [0 ..] (samples current))
      vertex i = maybe (bad "missing feasibility material vertex") Right (IM.lookup i points)
      free = [i | i <- IM.keys points, IM.notMember i pins]
      auxiliary = length (samples current)
      scalar = IM.singleton auxiliary (V3 1 0 0)
  lengths <- adapt (materialRows [] pins 1 current)
  bounds <- forM (zip (meshEdges current) lengths) $ \((a, b), (g, r)) -> do
    p <- vertex a
    q <- vertex b
    let rest = norm (sampleMaterial q ^-^ sampleMaterial p)
        tolerance = 1e-5 * rest
        name = "length " <> tshow a <> "-" <> tshow b
    unless (finite rest && rest > 0) (bad "feasibility needs positive material edge lengths")
    pure [FeasibleConstraint (name <> " lower") g ((tolerance + r) / feasibilityScale), FeasibleConstraint (name <> " upper") (IM.map negateV g) ((tolerance - r) / feasibilityScale)]
  contacts <- gapRows pins model current
  let deficit = maximum (0 : [negate gap | (_, (_, gap)) <- contacts])
      overlap = [FeasibleConstraint name (IM.unionWith (^+^) g scalar) (gap + deficit) | (name, (g, gap)) <- contacts]
      boxes = [FeasibleConstraint ("box " <> tshow i <> " " <> tshow k <> " " <> tshow sign) (IM.singleton i (sign *^ axis)) ((initializationMovementLimit + sign * dot axis (q ^-^ p)) / feasibilityScale) | (i, (p, q)) <- zip [0 :: Int ..] (zip (initialPositions start) (initialPositions current)), IM.notMember i pins, (k, axis) <- zip [0 :: Int ..] axes, sign <- [-1, 1]]
      constraints = concat bounds ++ overlap ++ boxes ++ [FeasibleConstraint "deficit nonnegative" scalar deficit, FeasibleConstraint "deficit nonincreasing" (IM.map negateV scalar) 0]
  unless (all (\c -> finite (feasibleOffset c) && feasibleOffset c >= 0 && all finiteV (feasibleGradient c)) constraints) (bad "linear feasibility start is not finite or within its hard bounds")
  pure (FeasibleProblem auxiliary deficit (free ++ [auxiliary]) constraints)
  where
    axes = [V3 1 0 0, V3 0 1 0, V3 0 0 1]
    negateV = ((-1) *^)

-- | These are hard checks on actual geometry, not the linear prediction.
-- Caller also checks strict deficit descent. Intersections may remain during
-- construction; only the independent readiness check can accept a seed.
feasibilityRefusal :: IM.IntMap V3 -> MaterialMesh -> MaterialMesh -> Maybe Text
feasibilityRefusal pins start candidate
  | triangles start /= triangles candidate || map sampleMaterial (samples start) /= map sampleMaterial (samples candidate) = Just "material changed"
  | not (all finiteV (initialPositions candidate)) = Just "nonfinite positions"
  | any (\(i, p) -> IM.lookup i points /= Just p) (IM.toList pins) = Just "exact hold changed"
  | initializationMovement start candidate > initializationMovementLimit = Just "movement budget"
  | maxLengthError candidate > 1e-5 = Just "length limit"
  | otherwise = Nothing
  where
    points = IM.fromList (zip [0 ..] (initialPositions candidate))

feasibleInitialization :: Int -> IM.IntMap V3 -> C.OrderedContact -> (MaterialMesh -> Either InitializationError Bool) -> MaterialMesh -> Either InitializationError FeasibleRun
feasibleInitialization limit pins model ready start = do
  unless (limit >= 0 && limit <= 20 && not (null (samples start))) (bad "feasibility needs a nonempty mesh and a correction budget from zero to twenty")
  maybe (pure ()) bad (feasibilityRefusal pins start start)
  _ <- feasibilityProblem pins model start start
  go 0 [start] [] start
  where
    finish history attempts = FeasibleRun (reverse history) (reverse attempts)
    install scale current delta = current {samples = [s {position = position s ^+^ (scale * feasibilityScale *^ IM.findWithDefault (V3 0 0 0) i delta)} | (i, s) <- zip [0 ..] (samples current)]}
    go n history attempts current = do
      passed <- ready current
      if passed
        then pure (finish history attempts "ready" True)
        else
          if n >= limit
            then pure (finish history attempts "correction-budget" False)
            else do
              problem <- feasibilityProblem pins model start current
              before <- clearanceDeficit model current
              let objective = [(IM.singleton (problemAuxiliary problem) (V3 1 0 0), problemDeficit problem)]
                  inequalities = [(feasibleGradient c, feasibleOffset c) | c <- problemConstraints problem]
                  solve = Q.constrainedStepDetailed Q.OriginalWorkingSet feasibilityInnerBudget feasibilityDamping (problemFree problem) objective inequalities
              case solve of
                Left err -> pure (finish history (FeasibleAttempt current problem Nothing Nothing Nothing Nothing (Just (explain err)) [] : attempts) "constrained-direction-failure" False)
                Right (delta, report, details) -> do
                  let proposal = install 1 current delta
                      attempt ts failure = FeasibleAttempt current problem (Just proposal) (Just delta) (Just report) (Just details) failure ts
                      search tried [] = (reverse tried, Nothing)
                      search tried (scale : rest) =
                        let candidate = install scale current delta
                            measured = clearanceDeficit model candidate
                            score = either (const Nothing) Just measured
                            refusal = case feasibilityRefusal pins start candidate of
                              Just reason -> Just reason
                              Nothing -> case measured of Left err -> Just (explain err); Right deficit -> if deficit < before then Nothing else Just "worst deficit did not decrease"
                            trial = FeasibleTrial scale candidate score refusal
                         in case refusal of Nothing -> (reverse (trial : tried), Just candidate); Just _ -> search (trial : tried) rest
                  if not (Q.quadraticConverged report) || not (all finiteV delta)
                    then pure (finish history (attempt [] (Just "constrained direction did not pass its original-row checks") : attempts) "constrained-direction-failure" False)
                    else case search [] initializationFractions of
                      (trials, Nothing) -> pure (finish history (attempt trials Nothing : attempts) "line-search-budget" False)
                      (trials, Just next) -> go (n + 1) (next : history) (attempt trials Nothing : attempts) next

adapt :: (Explain e) => Either e a -> Either InitializationError a
adapt = first (InitializationError . explain)

bad :: Text -> Either InitializationError a
bad = Left . InitializationError

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)

finiteV :: V3 -> Bool
finiteV (V3 a b c) = all finite [a, b, c]
