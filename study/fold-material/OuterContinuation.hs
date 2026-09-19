-- | Resume only the two exhausted outer-strip endpoints. A saved position
-- is a starting guess, not a new rest shape: the unfolded material, held
-- vertices and angular springs must still come from OuterStrip. Otherwise
-- restarting would silently erase strain or change the loading experiment.
-- Paper and material coordinates are defined in docs/glossary.md.
--
-- This module binds a historical report to its fixture and checks the final
-- iteration budget. Fresh geometry measurements are compared separately by
-- the gallery before solving. Nothing here certifies a path through the
-- numerical iterates or a global energy minimum.
module OuterContinuation
  ( ContinuationCase (..),
    continuationId,
    continuationChoice,
    continuationRule,
    continuationControl,
    continuationFixture,
    continuationSettings,
    continuationWeight,
    sourceRecord,
    restartFixture,
    agreeMeasurements,
  )
where

import BandBoundary
import BendLocations (savedBendMesh)
import ClosedCrease
import Control.Monad (forM_, unless)
import CoupledCrease
import CreaseInequality (InequalityError (..))
import Data.Aeson (Value (..), withObject, (.:))
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types (parseEither)
import Data.Bifunctor (first)
import Data.Foldable (toList)
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Data.Text qualified as T
import FoldRelaxation (Settings (..))
import OuterStrip
import Senbazuru.Fold.Types (Frame)
import Senbazuru.Origami.Surface
import UnequalCrease

data ContinuationCase = RestBand | OuterWithoutContact
  deriving stock (Eq, Show, Enum, Bounded)

continuationId :: ContinuationCase -> Text
continuationId RestBand = "band-rest-fractional"
continuationId OuterWithoutContact = "band-off-outer-original"

continuationChoice :: ContinuationCase -> OuterMesh
continuationChoice RestBand = RestOnly
continuationChoice OuterWithoutContact = OuterOnly

continuationRule :: ContinuationCase -> BoundaryRule
continuationRule RestBand = FractionalTurns
continuationRule OuterWithoutContact = OriginalTurns

continuationControl :: ContinuationCase -> UnequalControl
continuationControl RestBand = UpperBand
continuationControl OuterWithoutContact = BandWithoutContact

continuationFixture :: ContinuationCase -> Either InequalityError CoupledFixture
continuationFixture c = outerFixture (continuationChoice c) (continuationRule c) (continuationControl c)

continuationSettings :: Settings
continuationSettings = Settings 40 1e-5

continuationWeight :: Double
continuationWeight = 1e10

-- | Require the original six-stage policy and a genuinely exhausted final
-- stage, not a refused step whose movement happens to be small.
-- Histories stay in the source report rather than being rewritten as new work.
sourceRecord :: ContinuationCase -> Value -> Either InequalityError Value
sourceRecord c document = do
  fixture <- continuationFixture c
  preference <- bandPreference
  parsed (readDocument fixture preference) document
  where
    parsed p = first (InequalityError . T.pack) . parseEither p
    readDocument fixture preference = withObject "outer-strip report" $ \o -> do
      name <- o .: "gallery"
      unless (name == ("outer-strip" :: Text)) (fail "expected saved outer-strip report")
      runs <- o .: "runs"
      case [r | r <- runs, parseEither (withObject "run" (.: "id")) r == Right (continuationId c)] of
        [r] -> readRun fixture preference r >> pure r
        _ -> fail "expected exactly one selected outer-strip run"
    readRun fixture preference = withObject "saved run" $ \o -> do
      let expect key value = do actual <- o .: key; unless (actual == value) (fail ("changed source policy: " ++ show key))
      expect "meshKey" (if c == RestBand then "rest" else "outer" :: Text)
      expect "rule" (if c == RestBand then "fractional" else "original" :: Text)
      expect "control" (if c == RestBand then "band" else "band-off" :: Text)
      expect "contactEnabled" (c == RestBand)
      expect "contactMethod" ("ProgressiveContactExchange" :: Text)
      expect "lengthWeights" ([1e2, 1e4, 1e6, 1e8, 1e9, continuationWeight] :: [Double])
      expect "iterationLimitPerStage" (iterationLimit continuationSettings)
      expect "lengthTolerance" (lengthTolerance continuationSettings)
      expect "columns" (map (fromRational :: Rational -> Double) (outerColumns (continuationChoice c)))
      expect "heldVertices" (IM.keys (coupledPins fixture))
      expect "sharedCreaseVertices" (closedRoot (coupledReference fixture))
      expect "vertices" (length (samples (coupledSeed fixture)))
      expect "triangles" (length (triangles (coupledSeed fixture)))
      expect "passed" False
      expect "refusal" Null
      band <- o .: "band"
      bounds <- band .: "bounds"
      turn <- band .: "desiredTurnRadians"
      stiffness <- band .: "bendingWeight"
      flat <- band .: "flatReferenceEnergy"
      unless (bounds == bandBounds preference && turn == bandDesiredTurn preference && stiffness == bandBendingWeight preference && flat == bandReferenceEnergy preference) (fail "changed source band preference")
      solve <- o .: "solve"
      converged <- solve .: "converged"
      iterations <- solve .: "iterations"
      steps <- solve .: "steps"
      unless (not converged && iterations == length steps && iterations > 40) (fail "expected an unfinished six-stage solve")
      weights <- mapM (withObject "step" (.: "lengthWeight")) steps
      unless (weights == concat [replicate (length (filter (== w) weights)) w | w <- [1e2, 1e4, 1e6, 1e8, 1e9, continuationWeight]] && all (`elem` weights) [1e2, 1e4, 1e6, 1e8, 1e9, continuationWeight]) (fail "source history changed its length schedule")
      unless (length (filter (== continuationWeight) weights) == 40) (fail "source final stage did not exhaust 40 iterations")
      forM_ (zip [1 :: Int ..] steps) $ \(i, step) -> withObject "step" (\s -> do actual <- s .: "iteration"; unless (actual == i) (fail "source step numbering changed")) step
      forM_ (drop (iterations - 40) steps) $ withObject "final stage" $ \s -> do
        accepted <- s .: "accepted"
        settled <- s .: "stageSettled"
        unless (accepted && not settled) (fail "source final stage stopped or settled before exhaustion")

-- | Change only the starting positions. savedBendMesh checks material ids,
-- winding, holds, original creases and stored layer identities against the
-- authored fixture; contact-off crossings are deliberately retained.
restartFixture :: CoupledFixture -> Frame -> Either InequalityError CoupledFixture
restartFixture fixture fr = do
  mesh <- savedBendMesh fixture fr
  pure fixture {coupledSeed = mesh}

-- | Recomputed reports must have the same fields and values. Only finite
-- floating-point measurements allow rounding at 1e-12 relative to unit scale;
-- missing checks, different identities and exact-gap strings are not ignored.
agreeMeasurements :: Value -> Value -> Either InequalityError ()
agreeMeasurements expected actual = unless (same expected actual) (Left (InequalityError "saved endpoint measurements disagree with the FOLD or authored fixture"))
  where
    same (Number a) (Number b) =
      let x = realToFrac a :: Double; y = realToFrac b :: Double
       in finite x && finite y && abs (x - y) <= 1e-12 * max 1 (max (abs x) (abs y))
    same (Object a) (Object b) = KM.size a == KM.size b && all (\(k, v) -> maybe False (same v) (KM.lookup k b)) (KM.toList a)
    same (Array a) (Array b) = length a == length b && and (zipWith same (toList a) (toList b))
    same a b = a == b
    finite x = not (isNaN x || isInfinite x)
