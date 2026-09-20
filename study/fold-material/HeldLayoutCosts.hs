-- | Locate numerical length penalties beside passive bending costs. Material
-- coordinates identify points on the unfolded sheet (docs/glossary.md).
-- Length cost is w (actual - rest)^2 / 2, using absolute errors, not relative
-- strain. A short edge can therefore have the worst strain without having
-- the largest cost. This is a numerical restraint, not calibrated elasticity.
--
-- Count each material edge once, including boundary edges. The two panels
-- share their crease edges; keeping those in a third category avoids doubling
-- them. Match layouts by unordered material endpoints, never vertex ids.
-- Midpoint bins are discrete accounting, not physical energy densities.
-- Archive readers bind both saved resolutions to their unchanged policies;
-- the gallery checks their actual geometry separately, without a solver.
module HeldLayoutCosts
  ( LengthSide (..),
    LocatedLength (..),
    LengthChange (..),
    locateLengths,
    compareLengths,
    lengthCost,
    lengthDelta,
    lengthDistance,
    lengthDirection,
    layoutCases,
    layoutRecord,
  )
where

import BendRefinement (gridColumns)
import ClosedCrease (closedRoot)
import Control.Monad (foldM, forM, unless)
import CoupledCrease (coupledPins, coupledReference, coupledSeed)
import CreaseInequality (InequalityError (..))
import Data.Aeson (Value (..), withObject, (.:))
import Data.Aeson.Types (parseEither)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Data.Text (Text)
import Data.Text qualified as T
import FoldMaterial (meshEdges)
import HeldCosts (heldHistory)
import HeldEquilibrium
import HeldRefinement (confirmationHistory, confirmedRecord, refinementStop, refinementWeight)
import OuterContinuation (agreeMeasurements)
import PrescribedBend (EdgeMeasure (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface

data LengthSide = LowerLength | UpperLength | SharedLength deriving stock (Eq, Show)

data LocatedLength = LocatedLength
  { lengthMeasure :: !EdgeMeasure,
    lengthFrom :: !V2,
    lengthTo :: !V2,
    lengthSide :: !LengthSide
  }
  deriving stock (Eq, Show)

data LengthChange = LengthChange
  { oldLength :: !(Maybe LocatedLength),
    newLength :: !(Maybe LocatedLength),
    lengthLocation :: !LocatedLength
  }
  deriving stock (Eq, Show)

lengthCost :: LocatedLength -> Double
lengthCost h = refinementWeight * (edgeActual e - edgeRest e) ^ (2 :: Int) / 2
  where
    e = lengthMeasure h

lengthDelta :: LengthChange -> Double
lengthDelta c = maybe 0 lengthCost (newLength c) - maybe 0 lengthCost (oldLength c)

lengthDistance :: LocatedLength -> Double
lengthDistance h = (abs u + abs v) / 2
  where
    V2 u _ = lengthFrom h; V2 v _ = lengthTo h

lengthDirection :: LocatedLength -> Text
lengthDirection h | u == u' = "Transverse" | v == v' = "Lengthwise" | otherwise = "Diagonal"
  where
    V2 u v = lengthFrom h; V2 u' v' = lengthTo h

locateLengths :: MaterialMesh -> [EdgeMeasure] -> Either InequalityError [LocatedLength]
locateLengths mesh measured = do
  let supplied = M.fromList [(ordered (edgeIds e), e) | e <- measured]
  unless (M.size supplied == length measured && M.keys supplied == M.keys (M.fromList [(ordered edge, ()) | edge <- meshEdges mesh])) (Left (InequalityError "length accounting requires every unique material edge exactly once"))
  forM measured $ \e -> do
    let (a, b) = edgeIds e
    p <- point a
    q <- point b
    let from@(V2 u _) = sampleMaterial p
        to@(V2 u' _) = sampleMaterial q
        rest = norm (to ^-^ from)
        actual = norm (position q ^-^ position p)
        side | u == 0 && u' == 0 = SharedLength | u + u' < 0 = UpperLength | otherwise = LowerLength
    unless (all finite [rest, actual, edgeRest e, edgeActual e] && rest > 0 && u * u' >= 0 && abs (rest - edgeRest e) <= 1e-12 && abs (actual - edgeActual e) <= 1e-12) (Left (InequalityError "length rows disagree with the two-panel material mesh"))
    pure (LocatedLength e from to side)
  where
    vertices = IM.fromList (zip [0 ..] (samples mesh))
    point i = maybe (Left (InequalityError "length edge lost its material vertex")) Right (IM.lookup i vertices)
    ordered (a, b) = (min a b, max a b)
    finite x = not (isNaN x || isInfinite x)

compareLengths :: [LocatedLength] -> [LocatedLength] -> Either InequalityError [LengthChange]
compareLengths before after = do
  a <- index before
  b <- index after
  pure [LengthChange (M.lookup k a) (M.lookup k b) h | (k, h) <- M.toAscList (M.union a b)]
  where
    index = foldM insert M.empty
    insert found h = do
      let pair (V2 u v) = (u, v); a = pair (lengthFrom h); b = pair (lengthTo h); key = (min a b, max a b)
      unless (M.notMember key found) (Left (InequalityError "duplicate material edge in length comparison"))
      pure (M.insert key h found)

layoutCases :: [(String, HeldLayout, HeldBudget)]
layoutCases = [("uniform-256", UniformLayout, Triangles256), ("whole-256", WholeBendLayout, Triangles256), ("uniform-512", UniformLayout, Triangles512), ("whole-512", WholeBendLayout, Triangles512)]

-- | Read the bundled refinement archive and its retained confirmation report.
-- Return the exact historical record and the endpoint measurements to recheck.
layoutRecord :: Text -> HeldLayout -> HeldBudget -> HeldCase -> Value -> Value -> Either InequalityError (Value, Value)
layoutRecord key layout budget c document original = do
  gallery <- parsed (withObject "refinement archive" (.: "gallery")) document
  unless (gallery == ("held-refinement" :: Text)) (Left (InequalityError "expected held-refinement archive"))
  case budget of
    Triangles256 -> do
      r <- parsed (select "sources") document
      history <- parsed (withObject "source" (.: "history")) r
      confirmed <- confirmedRecord key layout c original
      agreeMeasurements history confirmed
      state <- parsed (withObject "source" (.: "state")) r
      saved <- parsed (withObject "confirmation" (\o -> o .: "states" >>= (.: "after"))) confirmed
      agreeMeasurements state saved
      pure (history, state)
    Triangles512 -> do
      r <- parsed (select "runs") document
      parsed readFine r
      state <- parsed (withObject "fine run" (\o -> o .: "states" >>= (.: "after"))) r
      pure (r, state)
    _ -> Left (InequalityError "layout costs require saved 256 or 512 endpoints")
  where
    parsed parser = first (InequalityError . T.pack) . parseEither parser
    select field = withObject "refinement archive" $ \o -> do
      stop <- o .: "sourceMovementTolerance"
      unless (stop == refinementStop) (fail "changed source confirmation stop")
      entries <- o .: field
      case [r | r <- entries, parseEither (withObject "entry" (.: "id")) r == Right key] of
        [r] -> pure r
        _ -> fail "expected exactly one selected saved endpoint"
    readFine = withObject "fine endpoint" $ \o -> do
      let expect field value = do actual <- o .: field; unless (actual == value) (fail ("changed fine-mesh policy: " ++ show field))
          fixture = heldFixture c
      expect "layout" (show layout)
      expect "vertices" (length (samples (coupledSeed fixture)))
      expect "triangles" (length (triangles (coupledSeed fixture)))
      expect "columns" (map (fromRational :: Rational -> Double) (gridColumns (heldGrid c)))
      expect "heldVertices" (IM.keys (coupledPins fixture))
      expect "sharedCreaseVertices" (closedRoot (coupledReference fixture))
      expect "lengthWeights" equilibriumWeights
      expect "iterationLimitPerStage" (40 :: Int)
      expect "lengthTolerance" (1e-5 :: Double)
      expect "contactMethod" ("ProgressiveContactExchange" :: Text)
      expect "contactEnabled" True
      expect "passed" True
      expect "continuousMotionChecked" False
      expect "stages" (["before", "repair", "solved", "confirmation-repair", "after"] :: [Text])
      expect "comparisonState" (key <> "-after")
      primary <- o .: "primary"
      oldStop <- primary .: "movementTolerance"
      oldRefusal <- primary .: "refusal"
      unless (oldStop == (1e-7 :: Double) && oldRefusal == Null) (fail "changed primary solve policy")
      primary .: "solve" >>= heldHistory
      confirmation <- o .: "confirmation"
      stop <- confirmation .: "movementTolerance"
      weights <- confirmation .: "lengthWeights"
      refusal <- confirmation .: "refusal"
      skipped <- confirmation .: "skipped"
      unless (stop == refinementStop && weights == [refinementWeight] && refusal == Null && skipped == Null) (fail "fine endpoint lacks its original confirmation")
      confirmation .: "solve" >>= confirmationHistory
