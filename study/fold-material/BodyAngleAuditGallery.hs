-- | Present the saved angle problem's numerical audit, without importing any
-- body construction or material solver. The input is a compact, lossless copy
-- of the archived scalar equations; unused y/z entries were all zero. Its
-- provenance names the source report and its SHA256. Output contains numbers,
-- not a new pose: an equality solution cannot certify folded paper.
module BodyAngleAuditGallery (writeBodyAngleAudit) where

import Control.Monad (unless)
import Data.Aeson (Value, eitherDecodeStrict, encode, object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (zip4)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import QuadraticAudit
import QuadraticAuditArchive (readAuditProblem)
import Senbazuru.Explain (Explain (..))
import System.Directory (canonicalizePath, createDirectoryIfMissing)
import System.FilePath ((</>))

writeBodyAngleAudit :: FilePath -> FilePath -> IO ()
writeBodyAngleAudit source destination = do
  let output = destination </> "body-angle-audit"
  sourcePath <- canonicalizePath source
  outputPath <- canonicalizePath (output </> "problem.json")
  unless (sourcePath /= outputPath) (fail "the audit output must not replace its source")
  bytes <- BS.readFile source
  value <- either fail pure (eitherDecodeStrict bytes)
  problem <- either fail pure (readAuditProblem value)
  result <- either (fail . T.unpack . explain) pure (auditQuadratic problem)
  let number x = fromRational x :: Double
      selected = map selectedSource (auditSelected problem)
      rowValues = [object ["source" .= i, "name" .= auditName row, "selected" .= (i `elem` selected), "savedGap" .= number before, "exactGap" .= number after, "roundedGap" .= number rounded] | (i, (row, before, after, rounded)) <- zip [0 :: Int ..] (zip4 (auditRows problem) (auditGaps (savedMetrics result)) (auditGaps (exactMetrics result)) (auditGaps (roundedMetrics result)))]
      report = object ["issue" .= (387 :: Int), "newBodySolves" .= (0 :: Int), "newActiveSetSearches" .= (0 :: Int), "geometryTrials" .= (0 :: Int), "acceptedPaper" .= False, "variables" .= length (auditStep problem), "constraints" .= length (auditRows problem), "selectedCount" .= length selected, "saved" .= metricsValue (savedMetrics result), "exact" .= metricsValue (exactMetrics result), "rounded" .= metricsValue (roundedMetrics result), "normalizedInfinityCondition" .= number (normalizedCondition result), "largestDirectionChange" .= number (largestStepChange result), "largestAngleChangeDegrees" .= maximum (0 : zipWith (\x y -> abs (number x - y)) (take (length (auditStep problem) - 1) (exactStep result)) (auditStep problem)), "exactDirection" .= map number (exactStep result), "exactOriginalMultipliers" .= map number (exactForces result), "rows" .= rowValues]
  createDirectoryIfMissing True output
  BS.writeFile (output </> "problem.json") bytes
  BL.writeFile (output </> "checks.json") (encode report)
  template <- TIO.readFile "study/fold-material/body-angle-audit.html"
  TIO.writeFile (destination </> "body-angle-audit.html") (T.replace "/*ANGLE_AUDIT_DATA*/null" (TE.decodeUtf8 (BL.toStrict (encode report))) template)
  putStrLn ("Audited saved equations without body solves. Wrote " ++ destination </> "body-angle-audit.html")

metricsValue :: AuditMetrics -> Value
metricsValue m = object ["passed" .= auditPassed m, "violation" .= number (auditViolation m), "complementarity" .= number (auditComplementarity m), "balance" .= sqrt (number (auditBalanceSquared m)), "minimumOriginalMultiplier" .= number (auditMinimumForce m), "selectedResidual" .= number (auditSelectedResidual m), "exactSelectedEqualities" .= (auditSelectedResidual m == 0), "exactBalance" .= (auditBalanceSquared m == 0)]
  where
    number x = fromRational x :: Double
