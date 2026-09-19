-- | Restart boundaries and refusal cases, without another expensive material
-- solve in CI. The synthetic history tests the archive contract; it is never
-- used as evidence that a real endpoint converged or exhausted its budget.
module OuterContinuationSpec (spec) where

import ClosedCrease
import Control.Monad (forM_)
import CoupledCrease
import Data.Aeson (Value (..), object, toJSON, (.=))
import Data.Aeson.Key (Key)
import Data.Aeson.KeyMap qualified as KM
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import FoldRelaxation
import OuterContinuation
import OuterStrip
import PrescribedBend
import Senbazuru.Fold.Types (Frame (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Test.Hspec
import UnequalCrease

spec :: Spec
spec = describe "saved outer-strip continuation" $ do
  it "accepts only the two named policies with an exhausted final stage" $
    forM_ [RestBand, OuterWithoutContact] $ \c -> do
      r <- archiveRun c
      sourceRecord c (archive [r]) `shouldBe` Right r
      sourceRecord c (archive [r, r]) `shouldSatisfy` isLeft
      sourceRecord c (archive []) `shouldSatisfy` isLeft
      forM_ [object ["gallery" .= ("different" :: String), "runs" .= [r]], archive [set "contactEnabled" (Bool (c /= RestBand)) r], archive [set "lengthWeights" (toNumbers [1e2, 1e4, 1e6, 1e8, 1e9, 1e11]) r], archive [set "lengthTolerance" (Number 0.001) r], archive [set "heldVertices" (toNumbers []) r], archive [set "passed" (Bool True) r]] $ \d -> sourceRecord c d `shouldSatisfy` isLeft

  it "refuses a converged, shortened or prematurely stopped source history" $ do
    r <- archiveRun RestBand
    forM_ [history True 40 False, history False 39 False, history False 40 True] $ \h ->
      sourceRecord RestBand (archive [set "solve" h r]) `shouldSatisfy` isLeft

  it "keeps material, springs and holds when the saved shape is strained" $
    forM_ [RestBand, OuterWithoutContact] $ \c -> do
      fixture <- right (continuationFixture c)
      let original = coupledSeed fixture
          moved = original {samples = [if i == 16 then p {position = position p ^+^ V3 0 0 0.0005} else p | (i, p) <- zip [0 :: Int ..] (samples original)]}
      fr <- materialFrame <$> right (coupledSurface fixture moved)
      restart <- right (restartFixture fixture fr)
      coupledSeed restart `shouldBe` moved
      show (coupledReference restart) `shouldBe` show (coupledReference fixture)
      coupledPins restart `shouldBe` coupledPins fixture
      maxLengthError (coupledSeed restart) `shouldSatisfy` (> 1e-6)
      measured <- right (measureProbe (coupledReference restart) {closedMesh = coupledSeed restart})
      probeLengthSquares measured `shouldSatisfy` (> 0)
      let changedHold = original {samples = [if i == 0 then p {position = position p ^+^ V3 0 0 0.0005} else p | (i, p) <- zip [0 :: Int ..] (samples original)]}
      let coords = [[x, y, z] | p <- samples changedHold, let V3 x y z = position p]
      restartFixture fixture fr {verticesCoords = coords} `shouldSatisfy` isLeft

  it "binds all report fields, including contact results and spring costs" $ do
    let report = object ["energy" .= (0.25 :: Double), "contact" .= True, "exactGap" .= ("0 % 1" :: String)]
    agreeMeasurements report (set "energy" (Number 0.2500000000001) report) `shouldBe` Right ()
    forM_ [set "energy" (Number 0.25001) report, set "contact" (Bool False) report, set "exactGap" (String "1 % 1000") report, object ["energy" .= (0.25 :: Double)]] $ \bad ->
      agreeMeasurements report bad `shouldSatisfy` isLeft

-- These policies describe a short synthetic six-stage archive, not measured
-- results. Actual study exports are independently rechecked outside CI.
archiveRun :: ContinuationCase -> IO Value
archiveRun c = do
  fixture <- right (continuationFixture c)
  band <- right bandPreference
  pure
    ( object
        [ "id" .= continuationId c,
          "meshKey" .= (if c == RestBand then "rest" else "outer" :: String),
          "control" .= (if c == RestBand then "band" else "band-off" :: String),
          "rule" .= (if c == RestBand then "fractional" else "original" :: String),
          "contactEnabled" .= (c == RestBand),
          "contactMethod" .= ("ProgressiveContactExchange" :: String),
          "lengthWeights" .= ([1e2, 1e4, 1e6, 1e8, 1e9, 1e10] :: [Double]),
          "iterationLimitPerStage" .= (40 :: Int),
          "lengthTolerance" .= (1e-5 :: Double),
          "columns" .= map (fromRational :: Rational -> Double) (outerColumns (continuationChoice c)),
          "heldVertices" .= IM.keys (coupledPins fixture),
          "sharedCreaseVertices" .= closedRoot (coupledReference fixture),
          "vertices" .= length (samples (coupledSeed fixture)),
          "triangles" .= length (triangles (coupledSeed fixture)),
          "passed" .= False,
          "refusal" .= Null,
          "band" .= object ["bounds" .= bandBounds band, "desiredTurnRadians" .= bandDesiredTurn band, "bendingWeight" .= bandBendingWeight band, "flatReferenceEnergy" .= bandReferenceEnergy band],
          "solve" .= history False 40 False
        ]
    )

history :: Bool -> Int -> Bool -> Value
history converged finalCount stopped = object ["converged" .= converged, "iterations" .= length weights, "steps" .= [object ["iteration" .= i, "lengthWeight" .= w, "accepted" .= not (stopped && i == length weights), "stageSettled" .= (w < 1e10)] | (i, w) <- zip [1 :: Int ..] weights]]
  where
    weights = [1e2, 1e4, 1e6, 1e8, 1e9] ++ replicate finalCount (1e10 :: Double)

archive :: [Value] -> Value
archive runs = object ["gallery" .= ("outer-strip" :: String), "runs" .= runs]

set :: Key -> Value -> Value -> Value
set key value (Object o) = Object (KM.insert key value o)
set _ _ value = value

toNumbers :: [Double] -> Value
toNumbers = toJSON

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
