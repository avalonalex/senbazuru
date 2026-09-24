-- | Construct a candidate separated pose before evaluating a contact barrier.
-- The saved sheet may already have negative gaps, where that barrier has no
-- value. This bounded construction instead penalizes clearance deficits and
-- edge-length errors, with a small tether to the saved position. All overlap
-- rows participate together; no pair-specific repair or bending solve runs.
--
-- There is one unknown position per material vertex, including shared crease
-- vertices. Exact holds are omitted from every row. Vertex-disjoint triangles
-- target a small positive gap; joined triangles target zero, since separating
-- their common material would tear the sheet. Numerical clearance is not
-- physical thickness. A decreasing construction cost does NOT certify paper:
-- the caller supplies the independent initialization-readiness check.
--
-- Every attempted fraction and failed linear solve is retained. The iteration,
-- linear-solve, line-search and displacement limits are fixed before this
-- experiment. Exhaustion is a diagnostic, never a reason to change parameters.
module BodyInitialization
  ( InitializationError (..),
    Initialization (..),
    InitialAttempt (..),
    InitialTrial (..),
    initializeSeparated,
    initializationRows,
    initializationCost,
    initializationDirection,
    initializationFractions,
    initializationTarget,
    initializationClearance,
    initializationMovementLimit,
    initialPositions,
    initializationMovement,
  )
where

import ContactQuadratic (QuadraticRow)
import Control.Monad (unless)
import CreaseInequality (materialRows)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (foldl')
import Data.Text (Text)
import FoldContact (ContactRow (..))
import Senbazuru.Explain (Explain (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import SparseSolve qualified as Sparse
import SurfaceContact qualified as C

newtype InitializationError = InitializationError Text deriving stock (Eq, Show)

instance Explain InitializationError where explain (InitializationError message) = message

data InitialTrial = InitialTrial
  { initialFraction :: Double,
    initialTrialMesh :: MaterialMesh,
    initialTrialCost :: Maybe Double,
    initialRefusal :: Maybe Text
  }
  deriving stock (Eq, Show)

data InitialAttempt = InitialAttempt
  { initialBefore :: MaterialMesh,
    initialProposal :: Maybe MaterialMesh,
    initialLinear :: Maybe Sparse.LinearReport,
    initialFailure :: Maybe Text,
    initialTrials :: [InitialTrial]
  }
  deriving stock (Eq, Show)

data Initialization = Initialization
  { initialHistory :: [MaterialMesh],
    initialAttempts :: [InitialAttempt],
    initialStop :: Text,
    initialReady :: Bool
  }
  deriving stock (Eq, Show)

initializationTarget, initializationClearance, initializationMovementLimit :: Double
initializationTarget = 1e-6
initializationClearance = 5e-7
initializationMovementLimit = 0.001

initializationFractions :: [Double]
initializationFractions = [2 ** negate (fromIntegral i) | i <- [0 :: Int .. 12]]

initialPositions :: MaterialMesh -> [V3]
initialPositions = map position . samples

initializationMovement :: MaterialMesh -> MaterialMesh -> Double
initializationMovement a b = maximum (0 : zipWith (\p q -> norm (q ^-^ p)) (initialPositions a) (initialPositions b))

-- | The positive target is assigned per triangle, not per source panel.
-- Two source panels can share a crease while their distant triangles can
-- separate. The old panel-wide clearance exemption would miss those layers.
initializationRows :: IM.IntMap V3 -> C.OrderedContact -> MaterialMesh -> MaterialMesh -> Either InitializationError [QuadraticRow]
initializationRows pins model start current = do
  unless (triangles start == triangles current && map sampleMaterial (samples start) == map sampleMaterial (samples current)) (bad "initialization changed material")
  lengths <- adapt (materialRows [] pins 1e8 current)
  ws <- adapt (C.contactWitnesses model current)
  let topology = IM.fromList (zip [0 ..] (triangles current))
      vertices i = case IM.lookup i topology of Just (a, b, c) -> [a, b, c]; Nothing -> []
      target w = let (a, b) = C.witnessTriangles w in if all (`notElem` vertices b) (vertices a) then initializationTarget else 0
      deficits = [(w, contactGap (C.witnessRow w) - target w) | w <- ws]
      contacts = [(IM.map (1e5 *^) (IM.difference (IM.fromListWith (^+^) (contactGradient (C.witnessRow w))) pins), 1e5 * gap) | (w, gap) <- deficits, gap < 0]
      anchors = [(IM.singleton i axis, dot axis (q ^-^ p)) | (i, (p, q)) <- zip [0 ..] (zip (initialPositions start) (initialPositions current)), IM.notMember i pins, axis <- [V3 1 0 0, V3 0 1 0, V3 0 0 1]]
      rows = lengths ++ contacts ++ anchors
  unless (all (\(g, r) -> finite r && all finiteV g) rows) (bad "nonfinite initialization rows")
  pure rows

initializationCost :: IM.IntMap V3 -> C.OrderedContact -> MaterialMesh -> MaterialMesh -> Either InitializationError Double
initializationCost pins model start current = do
  rows <- initializationRows pins model start current
  let cost = sum [r * r / 2 | (_, r) <- rows]
  unless (finite cost) (bad "nonfinite initialization cost")
  pure cost

-- | Check the original normal equations after applying their sparse factor.
-- A failed factor or residual stops the attempt instead of installing a tiny
-- unverified correction. Damping stabilizes this direction, not the objective.
initializationDirection :: [Int] -> [QuadraticRow] -> Either InitializationError (IM.IntMap V3, Sparse.LinearReport)
initializationDirection ids rows = do
  let zero = IM.fromList [(i, V3 0 0 0) | i <- ids]
      add values (gradient, amount) = IM.unionWith (^+^) values (IM.map (amount *^) gradient)
      inner a b = sum (IM.elems (IM.intersectionWith dot a b))
      rhs = foldl' add zero [(g, -r) | (g, r) <- rows]
      action values = foldl' add (IM.map (1e-3 *^) values) [(g, inner g values) | (g, _) <- rows]
      scalar values = IM.fromList [(3 * i + k, x) | (i, V3 a b c) <- IM.toList values, (k, x) <- zip [0 ..] [a, b, c]]
      vector values = IM.mapWithKey (\i _ -> V3 (get (3 * i)) (get (3 * i + 1)) (get (3 * i + 2))) zero where get k = IM.findWithDefault 0 k values
  factor <- maybe (bad "initialization factorization failed") Right (Sparse.factorNormal 1e-3 (IM.keys (scalar zero)) (map (scalar . fst) rows))
  pure (Sparse.conjugateGradient 2000 1e-6 (vector . Sparse.applyFactor factor . scalar) action rhs)

initializeSeparated :: Int -> IM.IntMap V3 -> C.OrderedContact -> (MaterialMesh -> Either InitializationError Bool) -> MaterialMesh -> Either InitializationError Initialization
initializeSeparated limit pins model ready start = do
  unless (limit >= 0 && limit <= 20 && all finiteV (initialPositions start)) (bad "initialization needs finite positions and a correction budget from zero to twenty")
  let points = IM.fromList (zip [0 ..] (initialPositions start))
  unless (all (\(i, p) -> finiteV p && IM.lookup i points == Just p) (IM.toList pins)) (bad "initialization holds must match the saved start exactly")
  _ <- initializationCost pins model start start
  go 0 [start] [] start
  where
    free = [i | i <- [0 .. length (samples start) - 1], IM.notMember i pins]
    finish history attempts = Initialization (reverse history) (reverse attempts)
    install scale current delta = current {samples = [s {position = position s ^+^ (scale *^ IM.findWithDefault (V3 0 0 0) i delta)} | (i, s) <- zip [0 ..] (samples current)]}
    go n history attempts current = do
      passed <- ready current
      if passed
        then pure (finish history attempts "ready" True)
        else
          if n >= limit
            then pure (finish history attempts "correction-budget" False)
            else do
              rows <- initializationRows pins model start current
              before <- initializationCost pins model start current
              case initializationDirection free rows of
                Left err -> pure (finish history (InitialAttempt current Nothing Nothing (Just (explain err)) [] : attempts) "linear-failure" False)
                Right (delta, report) -> do
                  let proposal = install 1 current delta
                      attempt ts failure = InitialAttempt current (Just proposal) (Just report) failure ts
                      search tried [] = (reverse tried, Nothing)
                      search tried (scale : rest) =
                        let candidate = install scale current delta
                            measured = if initializationMovement start candidate > initializationMovementLimit then bad "movement budget" else initializationCost pins model start candidate
                            (energy, refusal) = case measured of Left err -> (Nothing, Just (explain err)); Right cost -> (Just cost, if cost < before then Nothing else Just "construction cost did not decrease")
                            trial = InitialTrial scale candidate energy refusal
                         in case refusal of Nothing -> (reverse (trial : tried), Just candidate); Just _ -> search (trial : tried) rest
                  if not (Sparse.linearConverged report) || not (all finiteV (initialPositions proposal))
                    then pure (finish history (attempt [] (Just "linear residual or finite-position check failed") : attempts) "linear-failure" False)
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
