-- | Locate costs beside a fixed strip without another equilibrium solve.
-- A passive bend is an angular spring between triangles (see the glossary).
-- Assign its whole cost to the midpoint of its material edge: this accounts
-- for every spring, but is not a physical energy density. The neighboring
-- triangles can straddle a bin boundary. Bins are fixed before reading costs;
-- the first free bin is one interval of the uniform 128-triangle mesh.
--
-- Archive validation binds historical convergence to the original fixture
-- and stopping policy. The gallery separately reconstructs every endpoint
-- measurement and checks its material, holds and contact. Neither check proves
-- a global energy minimum or a continuous folding route.
module HeldCosts
  ( HeldRegion (..),
    heldRegion,
    heldRecord,
    heldHistory,
    transverseAngles,
    heldPairs,
  )
where

import BendLocations
import BendRefinement (gridColumns)
import ClosedCrease
import Control.Monad (forM_, unless)
import CoupledCrease
import CreaseInequality (InequalityError (..))
import Data.Aeson (Value (..), withObject, (.:))
import Data.Aeson.Types (Parser, parseEither)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (group)
import Data.Map.Strict qualified as M
import Data.Text (Text)
import Data.Text qualified as T
import FoldRelaxation (Settings (..))
import HeldBend
import HeldEquilibrium
import PrescribedBend
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Origami.Surface

data HeldRegion = FixedInterior | FixedBoundary | FirstFreeInterval | RemainingFree
  deriving stock (Eq, Ord, Show, Enum, Bounded)

heldRegion :: Double -> HeldRegion
heldRegion x
  | x < 1 / 8 = FixedInterior
  | x == 1 / 8 = FixedBoundary
  | x <= 5 / 32 = FirstFreeInterval
  | otherwise = RemainingFree

heldPairs :: [(String, String)]
heldPairs = [("uniform-128", "uniform-256"), ("whole-128", "whole-256"), ("uniform-128", "whole-128"), ("uniform-256", "whole-256")]

-- | Transverse edges run parallel to the crease. Weight their turns by
-- material width, retaining the range across width so a mean cannot hide a
-- bulge. These are raw angles; BendLocations.transverseRates additionally
-- divides each angle by its own neighboring material-column spacing.
transverseAngles :: [LocatedBend] -> [(Double, Double, Double, Double)]
transverseAngles rows = map summarize (M.toAscList bins)
  where
    bins = M.fromListWith (++) [(locatedDistance h, [(abs (v' - v), measuredAngle (locatedMeasure h))]) | h <- rows, let V2 u v = locatedFrom h, let V2 u' v' = locatedTo h, u == u', v /= v']
    summarize (x, entries) = (x, sum [w * a | (w, a) <- entries] / sum (map fst entries), minimum (map snd entries), maximum (map snd entries))

heldRecord :: Text -> HeldLayout -> HeldCase -> Value -> Either InequalityError Value
heldRecord key layout c = first (InequalityError . T.pack) . parseEither readDocument
  where
    fixture = heldFixture c
    readDocument = withObject "held equilibrium archive" $ \o -> do
      gallery <- o .: "gallery"
      unless (gallery == ("held-equilibrium" :: Text)) (fail "expected held-equilibrium archive")
      runs <- o .: "runs"
      case [r | r <- runs, parseEither (withObject "run" (.: "id")) r == Right key] of
        [r] -> readRun r >> pure r
        _ -> fail "expected exactly one selected held-panel run"
    readRun = withObject "held-panel run" $ \o -> do
      let expect k value = do actual <- o .: k; unless (actual == value) (fail ("changed held-panel policy: " ++ show k))
          near k expected = do
            actual <- o .: k
            unless (finite actual && abs (actual - expected) <= 1e-12 * max 1 (abs expected)) (fail ("changed held-panel curve: " ++ show k))
      expect "layout" (show layout)
      expect "columns" (map (fromRational :: Rational -> Double) (gridColumns (heldGrid c)))
      expect "vertices" (length (samples (coupledSeed fixture)))
      expect "triangles" (length (triangles (coupledSeed fixture)))
      expect "components" (1 :: Int)
      expect "heldVertices" (IM.keys (coupledPins fixture))
      expect "sharedCreaseVertices" (closedRoot (coupledReference fixture))
      near "curveCurvature" (curveCurvature (caseCurve c))
      near "curveArcLength" (curveArcLength (caseCurve c))
      near "seedGripRoundoff" (heldGripRoundoff c)
      expect "contactMethod" ("ProgressiveContactExchange" :: Text)
      expect "lengthWeights" equilibriumWeights
      expect "iterationLimitPerStage" (iterationLimit equilibriumSettings)
      expect "lengthTolerance" (lengthTolerance equilibriumSettings)
      expect "contactEnabled" True
      expect "passed" True
      expect "refusal" Null
      expect "stages" (["before", "repair", "after"] :: [Text])
      expect "continuousMotionChecked" False
      o .: "solve" >>= heldHistory

-- | Original six-stage history, shared by both held-panel archive formats.
heldHistory :: Value -> Parser ()
heldHistory = withObject "held solve" $ \solve -> do
  converged <- solve .: "converged"
  iterations <- solve .: "iterations"
  steps <- solve .: "steps"
  unless (converged && iterations == length steps) (fail "source solve did not converge or its history is incomplete")
  weights <- mapM (withObject "step" (.: "lengthWeight")) steps
  let blocks = group weights
  unless (map (take 1) blocks == map (: []) equilibriumWeights && all ((<= iterationLimit equilibriumSettings) . length) blocks) (fail "source history changed the length schedule or iteration budget")
  forM_ (zip [1 :: Int ..] steps) $ \(i, step) -> withObject "step" (\s -> do actual <- s .: "iteration"; unless (actual == i) (fail "source step numbering changed")) step
  case reverse steps of
    final : _ ->
      withObject
        "final step"
        ( \s -> do
            settled <- s .: "stageSettled"
            movement <- s .: "fullRepairedMovement"
            len <- s .: "lengthError"
            quadratic <- s .: "quadratic"
            solved <- quadratic .: "converged"
            unless (settled && solved && finite movement && movement >= 0 && movement <= 1e-7 && finite len && len >= 0 && len <= lengthTolerance equilibriumSettings) (fail "source final step does not satisfy the stopping policy")
        )
        final
    _ -> fail "missing source solver history"

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)
