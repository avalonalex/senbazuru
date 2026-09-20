-- | Fast accounting and archive-boundary checks. Synthetic history below
-- tests parsing only: it is not evidence that the sampled seeds converged.
module HeldCostsSpec (spec) where

import BendLocations
import BendRefinement (gridColumns)
import ClosedCrease
import Control.Monad (forM_)
import CoupledCrease
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson.KeyMap qualified as KM
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.Text qualified as T
import FoldBending
import HeldBend
import HeldCosts
import HeldEquilibrium
import MatchedEnergy
import PrescribedBend
import Senbazuru.Origami.Surface
import Test.Hspec

spec :: Spec
spec = describe "held-panel saved cost accounting" $ do
  it "places boundary edges in fixed bins, including the exact near-free endpoint" $ do
    map heldRegion [0, 0.124, 1 / 8, 0.13, 5 / 32, 0.16, 0.5] `shouldBe` [FixedInterior, FixedInterior, FixedBoundary, FirstFreeInterval, FirstFreeInterval, RemainingFree, RemainingFree]

  it "accounts for every passive spring in four comparisons and both panels" $ do
    endpoints <- mapM (\(key, layout, budget) -> do c <- right (heldCase layout budget); rows <- right (locateBends (coupledReference (heldFixture c))); pure (key, rows)) heldCases
    forM_ heldPairs $ \(ka, kb) -> forM_ [False, True] $ \upper -> do
      let get key = case lookup key endpoints of Just rs -> pure [h | h <- rs, hingeRole (measuredHinge (locatedMeasure h)) == PanelBend, measuredUpper (locatedMeasure h) == upper]; Nothing -> fail "missing fixture"
      a <- get ka
      b <- get kb
      cs <- right (compareBends a b)
      let bins = [[c | c <- cs, heldRegion (locatedDistance (changeLocation c)) == region] | region <- [minBound .. maxBound]]
          total rs = sum (map (measuredEnergy . locatedMeasure) rs)
      sum (map length bins) `shouldBe` length cs
      near (sum [sum (map edgeDelta bin) | bin <- bins]) (total b - total a)
      forM_ [a, b] $ \rows -> do
        let angles = transverseAngles rows
            rates = transverseRates rows
        map (\(x, _, _, _) -> x) angles `shouldBe` map (\(x, _, _, _) -> x) rates
        forM_ (angles ++ rates) $ \(_, mean, lo, hi) -> do
          (lo <= mean + 1e-12 && mean <= hi + 1e-12) `shouldBe` True
        sum [measuredEnergy (locatedMeasure h) | h <- rows, heldRegion (locatedDistance h) == FixedInterior] `shouldSatisfy` (< 1e-12)

  it "requires the original fixture and complete converged stopping policy" $ do
    c <- right (heldCase WholeBendLayout Triangles128)
    let r = archive c
        doc rs = object ["gallery" .= ("held-equilibrium" :: String), "runs" .= (rs :: [Value])]
        readOne = heldRecord "whole-128" WholeBendLayout c
        set k v (Object o) = Object (KM.insert k v o)
        set _ _ v = v
        solved steps = object ["converged" .= True, "iterations" .= length steps, "steps" .= steps]
        step i w = object ["iteration" .= (i :: Int), "lengthWeight" .= w, "stageSettled" .= True, "fullRepairedMovement" .= (1e-8 :: Double), "lengthError" .= (1e-6 :: Double), "quadratic" .= object ["converged" .= True]]
        history = zipWith step [1 ..] equilibriumWeights
    readOne (doc [r]) `shouldBe` Right r
    readOne (doc []) `shouldSatisfy` isLeft
    readOne (doc [r, r]) `shouldSatisfy` isLeft
    forM_ [set "passed" (Bool False) r, set "layout" (String "UniformLayout") r, set "heldVertices" (Array mempty) r, set "columns" (Array mempty) r, set "lengthTolerance" (Number 0.001) r, set "contactEnabled" (Bool False) r, set "curveArcLength" (Number 0.2) r, set "solve" (solved (take 5 history)) r, set "solve" (solved (reverse history)) r, set "solve" (solved (map (set "stageSettled" (Bool False)) history)) r, set "solve" (solved (map (set "fullRepairedMovement" (Number 0.001)) history)) r, set "solve" (solved (map (set "quadratic" (object ["converged" .= False])) history)) r] $ \bad -> readOne (doc [bad]) `shouldSatisfy` isLeft

archive :: HeldCase -> Value
archive c =
  object
    [ "id" .= ("whole-128" :: String),
      "layout" .= show WholeBendLayout,
      "columns" .= map (fromRational :: Rational -> Double) (gridColumns (heldGrid c)),
      "vertices" .= length (samples (coupledSeed f)),
      "triangles" .= length (triangles (coupledSeed f)),
      "components" .= (1 :: Int),
      "heldVertices" .= IM.keys (coupledPins f),
      "sharedCreaseVertices" .= closedRoot (coupledReference f),
      "curveCurvature" .= curveCurvature (caseCurve c),
      "curveArcLength" .= curveArcLength (caseCurve c),
      "seedGripRoundoff" .= heldGripRoundoff c,
      "contactMethod" .= ("ProgressiveContactExchange" :: String),
      "lengthWeights" .= equilibriumWeights,
      "iterationLimitPerStage" .= (40 :: Int),
      "lengthTolerance" .= (1e-5 :: Double),
      "contactEnabled" .= True,
      "passed" .= True,
      "refusal" .= Null,
      "stages" .= (["before", "repair", "after"] :: [T.Text]),
      "continuousMotionChecked" .= False,
      "solve" .= object ["converged" .= True, "iterations" .= (6 :: Int), "steps" .= [object ["iteration" .= i, "lengthWeight" .= w, "stageSettled" .= True, "fullRepairedMovement" .= (1e-8 :: Double), "lengthError" .= (1e-6 :: Double), "quadratic" .= object ["converged" .= True]] | (i, w) <- zip [1 :: Int ..] equilibriumWeights]]
    ]
  where
    f = heldFixture c

near :: Double -> Double -> Expectation
near a b = abs (a - b) `shouldSatisfy` (< 1e-11)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
