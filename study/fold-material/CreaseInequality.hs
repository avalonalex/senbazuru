-- | Constrain the small crease's upper panel against its fixed lower partner.
-- Exact clipping finds the corners of every upper/lower overlap. Each corner
-- is a weighted combination of upper vertices (barycentric weights). Its gap
-- gives a linear inequality for a material step; clipping the proposed shape
-- again checks the actual overlaps, which can change when vertices move.
-- Dividing by the movable weight keeps a corner near a hold well scaled.
-- Length and angle costs, holds and damping match the penalty experiment.
--
-- A feasible repair raises all FREE upper vertices by the smallest common
-- vertical amount covering every negative clipped witness. At fixed x/y,
-- each witness moves by that amount times its free barycentric weight. An
-- entirely held negative witness is impossible. Directed rounding then picks
-- a representable height on the permitted side, never adding paper thickness.
-- The line search measures the energy AFTER this repair. Convergence requires
-- a verified constrained quadratic and a small full repaired step, not merely
-- a shortened or refused step. No numerical iterate is a folding certificate.
module CreaseInequality
  ( InequalityError (..),
    FeasibleRepair (..),
    InequalityStep (..),
    InequalityResult (..),
    restoreFeasible,
    solveInequality,
    ceilingDouble,
    materialRows,
  )
where

import ClosedCrease
import ContactQuadratic
import Control.Monad (foldM, forM, unless)
import CreaseCorrection
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import FoldBending
import FoldMaterial (meshEdges)
import FoldRelaxation (Settings (..), maxLengthError)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import Senbazuru.Explain (Explain (..), num, tshow)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface

newtype InequalityError = InequalityError Text deriving stock (Eq, Show)

instance Explain InequalityError where explain (InequalityError message) = message

data FeasibleRepair = FeasibleRepair
  { repairedMesh :: !MaterialMesh,
    commonLift :: !Rational,
    maxRoundingLift :: !Double
  }
  deriving stock (Eq, Show)

data InequalityStep = InequalityStep
  { stepIteration :: !Int,
    stepWeight :: !Double,
    stepQuadratic :: !QuadraticReport,
    stepMovement :: !Double,
    stepScale :: !Double,
    stepLift :: !Double,
    stepRounding :: !Double,
    stepEnergyBefore :: !Double,
    stepEnergyAfter :: !Double,
    stepMinGap :: !Rational,
    stepLengthError :: !Double,
    stepAccepted :: !Bool,
    stepSettled :: !Bool
  }
  deriving stock (Eq, Show)

data InequalityResult = InequalityResult
  { inequalityInitial :: !FeasibleRepair,
    inequalityMesh :: !MaterialMesh,
    inequalitySteps :: ![InequalityStep],
    inequalityConverged :: !Bool
  }
  deriving stock (Eq, Show)

-- | Round toward +infinity, including negative heights and zero. For finite
-- IEEE Doubles the ordered bit pattern gives the immediate larger value.
-- This is at most one adjacent representable value beyond ordinary rounding.
ceilingDouble :: Rational -> Either InequalityError Double
ceilingDouble value = do
  let rounded = fromRational value
      next
        | rounded == 0 = encodeFloat 1 (-1074)
        | rounded > 0 = castWord64ToDouble (castDoubleToWord64 rounded + 1)
        | otherwise = castWord64ToDouble (castDoubleToWord64 rounded - 1)
      result = if finite rounded && toRational rounded >= value then rounded else next
  unless (finite rounded && finite result) (Left (InequalityError "a feasible contact height exceeds finite coordinates"))
  pure result

restoreFeasible :: CreaseCorrection -> MaterialMesh -> Either InequalityError FeasibleRepair
restoreFeasible fixture mesh = do
  audit <- adapt (auditLowerGap fixture mesh)
  let actual = IM.fromList (zip [0 ..] (map position (samples mesh)))
      pins = correctionPins fixture
  unless (all (\(i, p) -> IM.lookup i actual == Just p) (IM.toList pins)) (Left (InequalityError "the contact repair requires every held vertex at its specified position"))
  unless (all (\(i, p) -> materialU p < 0 || IM.member i pins) (zip [0 ..] (samples mesh))) (Left (InequalityError "the contact repair requires the entire lower panel to be held"))
  let free i = IM.notMember i (correctionPins fixture)
  lifts <- forM [w | w <- gapWitnesses audit, witnessGap w < 0] $ \w -> do
    let movable = sum (IM.elems (IM.filterWithKey (\i _ -> free i) (witnessWeights w)))
    unless (movable > 0) (Left (InequalityError ("held upper vertices " <> tshow (IM.keys (witnessWeights w)) <> " require a negative gap of " <> num (fromRational (witnessGap w)))))
    pure (negate (witnessGap w) / movable)
  let amount = maximum (0 : lifts)
  moved <- forM (zip [0 ..] (samples mesh)) $ \(i, p) ->
    if free i
      then do
        let V3 x y z = position p
            target = toRational z + amount
        height <- ceilingDouble target
        pure (p {position = V3 x y height}, fromRational (toRational height - target))
      else pure (p, 0)
  let result = mesh {samples = map fst moved}
  checked <- adapt (auditLowerGap fixture result)
  unless (minimumGap checked >= 0) (Left (InequalityError "the contact repair failed its exact stored-coordinate check"))
  pure (FeasibleRepair result amount (maximum (0 : map snd moved)))

solveInequality :: Settings -> CreaseCorrection -> Either InequalityError InequalityResult
solveInequality settings fixture = do
  unless (iterationLimit settings > 0 && finite (lengthTolerance settings) && lengthTolerance settings > 0) (Left (InequalityError "the crease inequality needs a positive iteration budget and length tolerance"))
  initial <- restoreFeasible fixture (correctionSeed fixture)
  (mesh, history, settled) <- foldM stage (repairedMesh initial, [], False) [1e2, 1e4, 1e6, 1e8]
  pure (InequalityResult initial mesh history settled)
  where
    reference = correctionReference fixture
    pins = correctionPins fixture
    free i = IM.notMember i pins
    ids = [i | (i, p) <- zip [0 ..] (samples (correctionSeed fixture)), free i, materialU p < 0]
    rows = materialRows (closedHinges reference) pins
    energy weight mesh = do
      measured <- rows weight mesh
      let value = sum [r * r | (_, r) <- measured]
      unless (finite value) (Left (InequalityError "the constrained material objective is non-finite"))
      pure value
    stage (mesh, history, _) weight = advance weight mesh history 0
    advance weight mesh history count
      | count >= iterationLimit settings = pure (mesh, history, False)
      | otherwise = do
          material <- rows weight mesh
          gaps <- adapt (auditLowerGap fixture mesh)
          let constraints =
                [ (IM.map (\w -> fromRational (w / movable) *^ V3 (negate (fromRational (witnessSlope witness))) 0 1) weights, fromRational (witnessGap witness / movable))
                  | witness <- gapWitnesses gaps,
                    let weights = IM.filterWithKey (\i _ -> free i) (witnessWeights witness),
                    let movable = sum weights,
                    movable > 0
                ]
          (direction, quadratic) <- adapt (constrainedStep 2000 1e-3 ids material constraints)
          before <- energy weight mesh
          let candidate scale = mesh {samples = [p {position = position p ^+^ (scale *^ IM.findWithDefault (V3 0 0 0) i direction)} | (i, p) <- zip [0 ..] (samples mesh)]}
              repair scale = restoreFeasible fixture (candidate scale)
          full <- repair 1
          let movement = maximum (0 : [norm (position a ^-^ position b) | (a, b) <- zip (samples mesh) (samples (repairedMesh full))])
              settled = quadraticConverged quadratic && movement <= 1e-7 && (weight < 1e8 || maxLengthError mesh <= lengthTolerance settings)
              search scale remaining = case repair scale of
                Left _ -> if remaining == 0 then pure Nothing else search (scale / 2) (remaining - 1)
                Right fixed -> do
                  after <- energy weight (repairedMesh fixed)
                  if after < before then pure (Just (scale, fixed, after)) else if remaining == 0 then pure Nothing else search (scale / 2) (remaining - 1)
          trial <- if settled || not (quadraticConverged quadratic) then pure Nothing else search 1 (30 :: Int)
          let (scale, fixed, after) = fromMaybe (0, FeasibleRepair mesh 0 0, before) trial
              next = repairedMesh fixed
              accepted = scale > 0
          gap <- adapt (auditLowerGap fixture next)
          let record = InequalityStep (length history + 1) weight quadratic movement scale (fromRational (commonLift fixed)) (maxRoundingLift fixed) before after (minimumGap gap) (maxLengthError next) accepted settled
              history' = history ++ [record]
          if settled || not accepted then pure (next, history', settled) else advance weight next history' (count + 1)

-- | The same material objective for fixed and moving contact partners. Holds
-- remove unknown coordinates from gradients, without dropping their costs.
materialRows :: [Hinge] -> IM.IntMap V3 -> Double -> MaterialMesh -> Either InequalityError [QuadraticRow]
materialRows hinges pins weight mesh = do
  let points = IM.fromList (zip [0 ..] (samples mesh))
      vertex i = maybe (Left (InequalityError ("material edge lost vertex " <> tshow i))) Right (IM.lookup i points)
  lengths <- forM (meshEdges mesh) $ \(a, b) -> do
    p <- vertex a
    q <- vertex b
    let delta = position q ^-^ position p
        actual = norm delta
        rest = sqrt ((materialU q - materialU p) ^ (2 :: Int) + (materialV q - materialV p) ^ (2 :: Int))
    unless (finite actual && actual > 0) (Left (InequalityError "a constrained correction collapsed a material edge"))
    pure ([(a, ((-sqrt weight) / actual) *^ delta), (b, (sqrt weight / actual) *^ delta)], sqrt weight * (actual - rest))
  bends <- adapt (bendingRows hinges mesh)
  pure [(IM.filterWithKey (\i _ -> IM.notMember i pins) (IM.fromListWith (^+^) gradient), r) | (gradient, r) <- lengths ++ bends]

adapt :: (Explain e) => Either e a -> Either InequalityError a
adapt = first (InequalityError . explain)

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)
