-- | The next length resolution of the held-panel experiment, with width
-- fixed. A material coordinate identifies a point on the original flat sheet
-- (see docs/glossary.md); adding columns does not add a new crease or change
-- the grips. The original four-case gallery remains a separate fixed archive.
--
-- A confirmed source must retain both solver histories: the original six
-- stages and the tighter final-weight restart. This module checks that
-- historical contract. The gallery separately remeasures the saved geometry,
-- so an archived "passed" flag cannot substitute for checking the paper.
module HeldRefinement
  ( refinementCases,
    refinementStop,
    refinementWeight,
    confirmedRecord,
  )
where

import Control.Monad (forM_, unless)
import CoupledCrease (coupledSeed)
import CreaseInequality (InequalityError (..))
import Data.Aeson (Value (..), object, withObject, (.:), (.=))
import Data.Aeson.Types (parseEither)
import Data.Bifunctor (first)
import Data.Text (Text)
import Data.Text qualified as T
import HeldCosts (heldRecord)
import HeldEquilibrium
import OuterContinuation (agreeMeasurements)
import Senbazuru.Origami.Surface (triangles)

refinementCases :: [(String, HeldLayout)]
refinementCases = [("uniform", UniformLayout), ("whole", WholeBendLayout)]

refinementStop :: Double
refinementStop = 1e-8

refinementWeight :: Double
refinementWeight = 1e10

confirmedRecord :: Text -> HeldLayout -> HeldCase -> Value -> Either InequalityError Value
confirmedRecord key layout c document = do
  unless (length (triangles (coupledSeed (heldFixture c))) == 256) (Left (InequalityError "refinement requires a confirmed 256-triangle source"))
  record <- parsed readDocument document
  source <- parsed (withObject "confirmed run" (.: "source")) record
  _ <- heldRecord key layout c (object ["gallery" .= ("held-equilibrium" :: Text), "runs" .= [source]])
  original <- parsed (withObject "original run" (\o -> o .: "states" >>= (.: "after"))) source
  seed <- parsed (withObject "confirmed run" (\o -> o .: "states" >>= (.: "source"))) record
  agreeMeasurements original seed
  pure record
  where
    parsed parser = first (InequalityError . T.pack) . parseEither parser
    readDocument = withObject "held confirmation archive" $ \o -> do
      gallery <- o .: "gallery"
      stop <- o .: "movementTolerance"
      originalStop <- o .: "sourceMovementTolerance"
      unless (gallery == ("held-confirmation" :: Text) && stop == refinementStop && originalStop == (1e-7 :: Double)) (fail "expected the original held-confirmation stopping policies")
      runs <- o .: "runs"
      case [r | r <- runs, parseEither (withObject "run" (.: "id")) r == Right key] of
        [r] -> readRun r >> pure r
        _ -> fail "expected exactly one selected confirmed run"
    readRun = withObject "confirmed run" $ \o -> do
      let expect k expected = do actual <- o .: k; unless (actual == expected) (fail ("changed confirmation policy: " ++ show k))
      expect "lengthWeights" [refinementWeight]
      expect "iterationLimitPerStage" (40 :: Int)
      expect "lengthTolerance" (1e-5 :: Double)
      expect "movementTolerance" refinementStop
      expect "contactMethod" ("ProgressiveContactExchange" :: Text)
      expect "contactEnabled" True
      expect "passed" True
      expect "refusal" Null
      expect "continuousMotionChecked" False
      expect "stages" (["source", "repair", "after"] :: [Text])
      solve <- o .: "solve"
      converged <- solve .: "converged"
      count <- solve .: "iterations"
      steps <- solve .: "steps"
      unless (converged && count == length steps && count > 0 && count <= 40) (fail "confirmation must converge within its original budget")
      forM_ (zip [1 :: Int ..] steps) $ \(i, step) ->
        withObject
          "confirmation step"
          ( \s -> do
              number <- s .: "iteration"
              weight <- s .: "lengthWeight"
              movement <- s .: "fullRepairedMovement"
              settled <- s .: "stageSettled"
              accepted <- s .: "accepted"
              quadratic <- s .: "quadratic"
              solved <- quadratic .: "converged"
              before <- s .: "energyBefore"
              after <- s .: "energyAfter"
              len <- s .: "lengthError"
              unless (number == i && weight == refinementWeight && finite movement && movement >= 0 && solved && finite before && finite after && finite len && len >= 0) (fail "invalid confirmation step")
              if i == count
                then unless (settled && not accepted && movement <= refinementStop && len <= 1e-5 && before == after) (fail "confirmation did not meet the tighter stopping test")
                else unless (accepted && not settled && after < before) (fail "confirmation stopped before its final step")
          )
          step
    finite :: Double -> Bool
    finite x = not (isNaN x || isInfinite x)
