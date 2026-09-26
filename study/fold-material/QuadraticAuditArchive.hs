-- | Read the scalar snapshot of #386's first refused direction. The snapshot
-- retains every original inequality in order, including duplicates. Array ids
-- label crease increments; the last id labels the common-bound increment.
-- No mesh, derivative or optimization search is reconstructed by this reader.
module QuadraticAuditArchive (readAuditProblem) where

import Control.Monad (unless)
import Data.Aeson (Value, withObject, (.:))
import Data.Aeson.Types (parseEither)
import Data.List (nub)
import QuadraticAudit

readAuditProblem :: Value -> Either String AuditProblem
readAuditProblem = parseEither $ withObject "saved scalar quadratic" $ \o -> do
  damping <- o .: "damping"
  common <- o .: "common"
  step <- o .: "step"
  ids <- o .: "ids"
  unless (length (ids :: [Int]) == length step && length ids == length (nub ids)) (fail "saved direction ids must be distinct and match its coordinates")
  rows <- o .: "constraints" >>= traverse (withObject "constraint" $ \r -> AuditRow <$> r .: "name" <*> r .: "coefficients" <*> r .: "offset")
  selected <- o .: "selected" >>= traverse (withObject "selected row" $ \r -> SelectedRow <$> r .: "source" <*> r .: "multiplier" <*> r .: "scale")
  pure (AuditProblem damping common step rows selected)
