-- | Compare bending costs at the same locations on the unfolded sheet.
-- Material coordinates and panel bends are defined in docs/glossary.md.
-- Vertex ids change when a mesh is refined, so an edge is identified by its
-- two material endpoints, independent of their order. An added edge has no
-- old spring; it does not mean that the old paper was flat there.
--
-- Even a shared edge can have different neighboring triangles. Its angular
-- spring then measures a turn over a different distance and has a different
-- coefficient. The symmetric coefficient/angle split below is an algebraic
-- identity, not two physically realizable states or a causal explanation.
-- Keeping this accounting separate from IO makes it testable without solves.
module MatchedEnergy
  ( EdgeChange (..),
    compareBends,
    edgeDelta,
    coefficientPart,
    anglePart,
    bendEnergy,
    edgeDirection,
    matchedRecord,
  )
where

import BendLocations
import ClosedCrease
import Control.Monad (foldM, unless)
import CoupledCrease
import CreaseInequality (InequalityError (..))
import Data.Aeson (Value (..), withObject, (.:))
import Data.Aeson.Types (parseEither)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Data.Text (Text)
import Data.Text qualified as T
import FoldBending
import OuterStrip
import PrescribedBend
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Origami.Surface

data EdgeChange = EdgeChange
  { changeLocation :: !LocatedBend,
    oldBend :: !(Maybe LocatedBend),
    newBend :: !(Maybe LocatedBend)
  }
  deriving stock (Eq, Show)

bendEnergy :: Maybe LocatedBend -> Double
bendEnergy = maybe 0 (measuredEnergy . locatedMeasure)

edgeDelta :: EdgeChange -> Double
edgeDelta c = bendEnergy (newBend c) - bendEnergy (oldBend c)

-- | E = k theta^2 / 2. Averaging the two expansion orders gives a symmetric
-- split: reversing the comparison negates both parts. Added/removed springs
-- stay separate, since they have no coefficient or angle on the other mesh.
coefficientPart :: EdgeChange -> Double
coefficientPart c = case (oldBend c, newBend c) of
  (Just a, Just b) -> (stiffness b - stiffness a) * (angle a ^ (2 :: Int) + angle b ^ (2 :: Int)) / 4
  _ -> 0

anglePart :: EdgeChange -> Double
anglePart c = case (oldBend c, newBend c) of
  (Just a, Just b) -> (stiffness b + stiffness a) * (angle b ^ (2 :: Int) - angle a ^ (2 :: Int)) / 4
  _ -> 0

stiffness :: LocatedBend -> Double
stiffness = hingeStiffness . measuredHinge . locatedMeasure

angle :: LocatedBend -> Double
angle = measuredAngle . locatedMeasure

edgeDirection :: LocatedBend -> Text
edgeDirection h
  | u == u' = "Transverse"
  | v == v' = "Lengthwise"
  | otherwise = "Diagonal"
  where
    V2 u v = locatedFrom h
    V2 u' v' = locatedTo h

compareBends :: [LocatedBend] -> [LocatedBend] -> Either InequalityError [EdgeChange]
compareBends before after = do
  a <- index before
  b <- index after
  pure [EdgeChange h (M.lookup key a) (M.lookup key b) | (key, h) <- M.toAscList (M.union a b)]
  where
    index = foldM insert M.empty
    insert found h = do
      let point (V2 u v) = (u, v)
          p = point (locatedFrom h)
          q = point (locatedTo h)
          key = (min p q, max p q)
          spring = measuredHinge (locatedMeasure h)
          energy = measuredEnergy (locatedMeasure h)
          values = [fst p, snd p, fst q, snd q, angle h, stiffness h, energy]
      unless (all finite values && p /= q && hingeRole spring == PanelBend && hingeRest spring == 0 && stiffness h >= 0 && abs (angle h) <= pi && energy >= 0 && abs (energy - stiffness h * angle h ^ (2 :: Int) / 2) <= 1e-12 * max 1 energy) $
        Left (InequalityError "energy comparison requires finite, zero-rest passive bends with consistent costs")
      unless (M.notMember key found) (Left (InequalityError "duplicate passive edge at one material location"))
      pure (M.insert key h found)
    finite x = not (isNaN x || isInfinite x)

-- | Bind each archived matched control to its original policy. A converged
-- report remains historical evidence; fresh geometry and every saved spring
-- measurement are checked separately before a comparison is eligible.
matchedRecord :: OuterMesh -> Text -> Text -> CoupledFixture -> Value -> Either InequalityError Value
matchedRecord choice key rule fixture = first (InequalityError . T.pack) . parseEither readDocument
  where
    name = "matched-" <> key <> "-" <> rule
    readDocument = withObject "outer-strip archive" $ \o -> do
      gallery <- o .: "gallery"
      unless (gallery == ("outer-strip" :: Text)) (fail "expected an outer-strip archive")
      runs <- o .: "runs"
      case [r | r <- runs, parseEither (withObject "run" (.: "id")) r == Right name] of
        [r] -> readRun r >> pure r
        _ -> fail "expected exactly one matched-hold run"
    readRun = withObject "matched-hold run" $ \o -> do
      let expect k value = do actual <- o .: k; unless (actual == value) (fail ("changed matched-hold source policy: " ++ show k))
      unless (rule `elem` ["original", "fractional"]) (fail "unknown saved rule")
      expect "meshKey" key
      expect "rule" rule
      expect "control" ("matched" :: Text)
      expect "contactEnabled" True
      expect "contactMethod" ("ProgressiveContactExchange" :: Text)
      expect "lengthWeights" ([1e2, 1e4, 1e6, 1e8, 1e9, 1e10] :: [Double])
      expect "iterationLimitPerStage" (40 :: Int)
      expect "lengthTolerance" (1e-5 :: Double)
      expect "columns" (map (fromRational :: Rational -> Double) (outerColumns choice))
      expect "heldVertices" (IM.keys (coupledPins fixture))
      expect "sharedCreaseVertices" (closedRoot (coupledReference fixture))
      expect "vertices" (length (samples (coupledSeed fixture)))
      expect "triangles" (length (triangles (coupledSeed fixture)))
      expect "passed" True
      expect "refusal" Null
      solve <- o .: "solve"
      converged <- solve .: "converged"
      unless converged (fail "matched-hold source did not converge")
