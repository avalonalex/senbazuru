-- | A small constrained quadratic step for the fixed-lower-panel experiment.
-- Minimize the squared linearized material errors, with positive damping,
-- subject to linear gap inequalities. Contact is a constraint, not another
-- large penalty. This module knows no paper topology or drawing.
--
-- A working set contains constraints currently treated as touching. Solve
-- the material quadratic with those equalities, then move only as far as the
-- next gap allows. A negative contact multiplier releases its constraint:
-- paper can push against another layer but cannot pull it closer like glue.
-- Independent working rows avoid inverting a redundant contact system.
-- Feasibility, complementarity and force balance are checked against every
-- inequality and the ORIGINAL material rows before reporting convergence.
-- Complementarity means a separated contact exerts no force. Force balance
-- means material forces, contact forces and damping sum to zero. Numerically
-- dependent rows stay in these checks even when omitted from the working set.
-- The opt-in progressive exchange repairs several conflicting contacts one
-- replacement at a time. Intermediate candidates may still violate gaps;
-- reducing their aggregate error is progress inside this numerical solve,
-- never permission to accept a material step. Only the unchanged final checks
-- can report convergence. Detailed replay records stay separate from the
-- compact report needed during a full material solve.
-- This dense contact solve is deliberately limited to the small fixture.
module ContactQuadratic
  ( QuadraticRow,
    QuadraticReport (..),
    QuadraticDetails (..),
    ContactResidual (..),
    ContactExchange (..),
    QuadraticError (..),
    constrainedStep,
    constrainedStepWith,
    constrainedStepDetailed,
    ContactMethod (..),
  )
where

import Control.Monad (foldM, forM, unless)
import Data.IntMap.Strict qualified as IM
import Data.List (foldl', nub)
import Data.Maybe (fromMaybe, isJust)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import SparseSolve qualified as Sparse

-- | The comparison retains the original working-set policy as a baseline.
-- Exchange permits a stricter, almost parallel contact to replace one of the
-- selected equalities when the original policy stalls. All residual tests
-- still use every original inequality. Progressive exchange can take several
-- replacements: each lowers the summed squared negative gaps, while the final
-- residual caps remain unchanged. A partial repair is never convergence.
data ContactMethod = OriginalWorkingSet | ExchangeNearDependent | ProgressiveContactExchange deriving stock (Eq, Show)

type Vector = IM.IntMap V3

-- Material rows store residual r for ||J*d+r||^2; constraint rows store
-- current gap g for a*d+g >= 0. The caller supplies g >= 0, so d=0
-- is a feasible starting point. Both omit held coordinates.
type QuadraticRow = (Vector, Double)

data QuadraticReport = QuadraticReport
  { quadraticConverged :: !Bool,
    quadraticIterations :: !Int,
    quadraticViolation :: !Double,
    quadraticComplementarity :: !Double,
    quadraticBalance :: !Double,
    quadraticActive :: !Int
  }
  deriving stock (Eq, Show)

-- | Optional replay evidence. Constraint ids index the deduplicated nonzero
-- rows; source ids index the caller's original inequalities, including copies.
-- Multipliers use the unit-diagonal contact scaling; divide by responseScale
-- to recover the multiplier of an original row. These are numerical forces.
data ContactResidual = ContactResidual
  { contactConstraint :: !Int,
    contactSources :: [Int],
    contactSelected :: !Bool,
    contactGap :: !Double,
    contactNormalizedMultiplier :: !Double,
    contactResponseScale :: !Double
  }
  deriving stock (Eq, Show)

data ContactExchange = ContactExchange
  { exchangeRemoved :: !Int,
    exchangeInserted :: !Int,
    exchangeViolationBefore :: !Double,
    exchangeViolationAfter :: !Double
  }
  deriving stock (Eq, Show)

-- | Detailed evidence is built lazily and discarded by the ordinary entry
-- point. Long nonlinear runs need only the compact 'QuadraticReport'.
data QuadraticDetails = QuadraticDetails
  { quadraticContacts :: [ContactResidual],
    quadraticExchanges :: [ContactExchange]
  }
  deriving stock (Eq, Show)

data QuadraticError = InvalidQuadratic | FailedFactor | InvalidResponse | SingularWorkingSet
  deriving stock (Eq, Show)

instance Explain QuadraticError where
  explain InvalidQuadratic = "the contact quadratic needs finite rows on distinct vertex ids, nonnegative starting gaps, positive damping and a positive work budget"
  explain FailedFactor = "the contact quadratic could not factor its material equations"
  explain SingularWorkingSet = "the contact quadratic working constraints are numerically dependent"
  explain InvalidResponse = "the contact quadratic could not verify a positive finite response to a contact force"

-- | Balance tolerance matches the existing material solve. Gap tolerances
-- here govern the inner optimization only; exact geometry checks still gate
-- stored endpoints in the caller. Neither tolerances nor reports alter gaps.
constrainedStep :: Int -> Double -> [Int] -> [QuadraticRow] -> [QuadraticRow] -> Either QuadraticError (Vector, QuadraticReport)
constrainedStep = constrainedStepWith OriginalWorkingSet

constrainedStepWith :: ContactMethod -> Int -> Double -> [Int] -> [QuadraticRow] -> [QuadraticRow] -> Either QuadraticError (Vector, QuadraticReport)
constrainedStepWith method budget damping ids rows inequalities = do
  (step, report, _) <- constrainedStepDetailed method budget damping ids rows inequalities
  pure (step, report)

-- | Replay one linearized problem, retaining the contacts left unsatisfied
-- and every accepted exchange. Unconverged steps remain invalid
-- for the caller, even if their aggregate violation has decreased.
constrainedStepDetailed :: ContactMethod -> Int -> Double -> [Int] -> [QuadraticRow] -> [QuadraticRow] -> Either QuadraticError (Vector, QuadraticReport, QuadraticDetails)
constrainedStepDetailed method budget damping ids rows inequalities = do
  unless (budget > 0 && length ids == length (nub ids) && finite damping && damping > 0 && all valid (rows ++ inequalities)) (Left InvalidQuadratic)
  factor <- maybe (Left FailedFactor) Right (Sparse.factorNormal damping (IM.keys (scalar zero)) (map (scalar . fst) rows))
  let inverse = vector . Sparse.applyFactor factor . scalar
      rhs = foldl' (\b (a, r) -> add (-r) a b) zero rows
      initial = inverse rhs
  responses <- forM unique $ \(a, g) -> do
    let response = inverse a
        diagonal = inner a response
    unless (finite diagonal && diagonal > 0 && all finiteVector (IM.elems response)) (Left InvalidResponse)
    -- Unit diagonal in the small contact matrix improves its scale without
    -- changing the half-space or adding a penalty to it.
    let scale = sqrt diagonal
    pure (IM.map ((1 / scale) *^) a, g / scale, IM.map ((1 / scale) *^) response, scale)
  unless (all (\(a, g) -> squared a > 0 || g >= 0) inequalities && all ((>= 0) . snd) inequalities) (Left InvalidQuadratic)
  go rhs initial (IM.fromList (zip [0 ..] responses)) zero [] [] 0
  where
    unique = nub [(a, g) | (a, g) <- inequalities, squared a > 0]
    sources = IM.fromList [(i, [j | (j, original) <- zip [0 ..] inequalities, original == row]) | (i, row) <- zip [0 ..] unique]
    zero = IM.fromList [(i, V3 0 0 0) | i <- ids]
    valid (a, r) = finite r && all (\(i, v) -> IM.member i zero && finiteVector v) (IM.toList a)
    scalar values = IM.fromList [(3 * i + k, x) | (i, V3 a b c) <- IM.toList values, (k, x) <- zip [0 ..] [a, b, c]]
    vector values = IM.mapWithKey (\i _ -> V3 (get (3 * i)) (get (3 * i + 1)) (get (3 * i + 2))) zero where get k = IM.findWithDefault 0 k values
    action d = foldl' (\b (a, _) -> add (inner a d) a b) (IM.map (damping *^) d) rows
    go rhs initial constraints d working exchanges count = do
      active <- mapM (\i -> maybe (Left InvalidQuadratic) Right (IM.lookup i constraints)) working
      let matrix = [[inner a response | (_, _, response, _) <- active] | (a, _, _, _) <- active]
          demand = [-g - inner a initial | (a, g, _, _) <- active]
      multipliers <- maybe (Left SingularWorkingSet) Right (solveDense matrix demand)
      let paired = zip working multipliers
          target = foldl' (\v ((_, _, response, _), lambda) -> add lambda response v) initial (zip active multipliers)
          p = add (-1) d target
          lambdaAt i = fromMaybe 0 (lookup i paired)
          violation = maximum (0 : [max 0 (-((g + inner a d) * scale)) | (a, g, _, scale) <- IM.elems constraints])
          complementarity = maximum (0 : [abs (min (g + inner a d) (lambdaAt i)) * scale | (i, (a, g, _, scale)) <- IM.toList constraints])
          force = foldl' (\v ((a, _, _, _), lambda) -> add lambda a v) rhs (zip active multipliers)
          balance = sqrt (squared (add (-1) force (action d)))
          okay = all finite [violation, complementarity, balance] && all (>= 0) multipliers && violation <= 1e-12 && complementarity <= 1e-12 && balance <= 1e-6
          report = QuadraticReport okay count violation complementarity balance (length working)
          details = QuadraticDetails [ContactResidual i (IM.findWithDefault [] i sources) (i `elem` working) ((g + inner a d) * scale) (lambdaAt i) scale | (i, (a, g, _, scale)) <- IM.toList constraints] (reverse exchanges)
          blockers = [(max 0 ((g + inner a d) / negate (inner a p)), i) | (i, (a, g, _, scale)) <- IM.toList constraints, i `notElem` working, inner a p * scale < -1e-12]
          independent i = case IM.lookup i constraints of
            Nothing -> False
            Just candidate ->
              let enlarged = active ++ [candidate]
                  gram = [[inner a response | (_, _, response, _) <- enlarged] | (a, _, _, _) <- enlarged]
               in isJust (solveDense gram (replicate (length enlarged) 0))
          firstBlock = foldl' min (1, -1) [(scale, i) | (scale, i) <- blockers, independent i]
          negative = [(lambda, i) | (i, lambda) <- paired, lambda < 0]
      if okay || count >= budget
        then pure (d, report, details)
        else
          if squared p <= 1e-26 && not (null negative)
            then let (_, remove) = minimum negative in go rhs initial constraints d (filter (/= remove) working) exchanges (count + 1)
            else case firstBlock of
              (scale, i) | scale < 1 -> go rhs initial constraints (add scale p d) (working ++ [i]) exchanges (count + 1)
              _ ->
                if target == d
                  then case replacement initial constraints working d of
                    Just (next, selected, exchange) -> go rhs initial constraints next selected (exchange : exchanges) (count + 1)
                    Nothing -> pure (d, report, details)
                  else go rhs initial constraints target working exchanges (count + 1)

    -- A row too close to the current span to add can still have a stricter
    -- offset. Try replacing ONE equality, never dropping it from validation.
    -- The original exchange requires one replacement to fix every gap. Several
    -- independent weak contacts can make that impossible. Progressive exchange
    -- instead reduces the SUM of squared negative gaps in original row units:
    -- the maximum alone would miss fixing one of two equally bad contacts.
    -- Nonnegative forces are still required at each replacement. None of these
    -- candidates reaches the caller as converged until ALL original residual
    -- checks pass. The ordinary iteration budget also bounds the exchanges.
    replacement initial constraints working d
      | method == OriginalWorkingSet = Nothing
      | otherwise = case [ (target, selected, ContactExchange removed i (score d) (score target))
                           | (i, (a, g, _, scale)) <- IM.toList constraints,
                             i `notElem` working,
                             (g + inner a d) * scale < -1e-12,
                             removed <- working,
                             let selected = filter (/= removed) working ++ [i],
                             Just active <- [mapM (`IM.lookup` constraints) selected],
                             let matrix = [[inner b response | (_, _, response, _) <- active] | (b, _, _, _) <- active],
                             let demand = [-h - inner b initial | (b, h, _, _) <- active],
                             Just forces <- [solveDense matrix demand],
                             all (>= 0) forces,
                             let target = foldl' (\v ((_, _, response, _), force) -> add force response v) initial (zip active forces),
                             all finiteVector (IM.elems target),
                             (if method == ProgressiveContactExchange then score target < score d else all (\(b, h, _, size) -> (h + inner b target) * size >= -1e-12) (IM.elems constraints))
                         ] of
          candidate : _ -> Just candidate
          [] -> Nothing
      where
        score q = sum [let violation = max 0 (negate ((h + inner b q) * size)) in violation * violation | (b, h, _, size) <- IM.elems constraints]

-- The contact matrix is a Gram matrix in the material metric. Cholesky
-- tests independence without pivoting or modifying the quadratic. Only the
-- small working set is dense; the material factor is still reused.
solveDense :: [[Double]] -> [Double] -> Maybe [Double]
solveDense matrix rhs = do
  unless (length matrix == length rhs && all ((== length rhs) . length) matrix && all finite (rhs ++ concat matrix)) Nothing
  let indices = [0 .. length rhs - 1]
      entries = IM.fromList [(i, IM.fromList (zip indices row)) | (i, row) <- zip indices matrix]
      at i j m = IM.findWithDefault 0 j (IM.findWithDefault IM.empty i m)
      factorRow earlier i = do
        row <-
          foldM
            ( \current j ->
                let value = at i j entries - sum [IM.findWithDefault 0 k current * at j k earlier | k <- [0 .. j - 1]]
                    diagonal = at j j earlier
                 in if j == i
                      then
                        let pivot = at i i entries - sum [x * x | x <- IM.elems current]
                         in if pivot > 1e-12 && finite pivot then Just (IM.insert i (sqrt pivot) current) else Nothing
                      else if diagonal > 0 && finite value then Just (IM.insert j (value / diagonal) current) else Nothing
            )
            IM.empty
            [0 .. i]
        pure (IM.insert i row earlier)
  lower <- foldM factorRow IM.empty indices
  let known = IM.fromList (zip indices rhs)
      forward values i = IM.insert i ((IM.findWithDefault 0 i known - sum [at i j lower * IM.findWithDefault 0 j values | j <- [0 .. i - 1]]) / at i i lower) values
      intermediate = foldl' forward IM.empty indices
      backward values i = IM.insert i ((IM.findWithDefault 0 i intermediate - sum [at j i lower * IM.findWithDefault 0 j values | j <- [i + 1 .. length rhs - 1]]) / at i i lower) values
      answer = IM.elems (foldl' backward IM.empty (reverse indices))
  if all finite answer then Just answer else Nothing

inner :: Vector -> Vector -> Double
inner a b = sum (IM.elems (IM.intersectionWith dot a b))

squared :: Vector -> Double
squared a = inner a a

add :: Double -> Vector -> Vector -> Vector
add scale a b = IM.unionWith (^+^) b (IM.map (scale *^) a)

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)

finiteVector :: V3 -> Bool
finiteVector (V3 x y z) = all finite [x, y, z]
