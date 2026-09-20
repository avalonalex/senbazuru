-- | Fixed 512-triangle fixtures and archive provenance, without expensive
-- solves in CI. Synthetic histories exercise the reader, not physics claims.
module HeldRefinementSpec (spec) where

import BendRefinement (gridColumns)
import ClosedCrease
import Control.Monad (forM_)
import CoupledCrease
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson.Key qualified
import Data.Aeson.KeyMap qualified as KM
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.Text qualified as T
import FoldBending
import FoldMaterial (componentCount)
import HeldBend
import HeldEquilibrium
import HeldRefinement
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface
import Test.Hspec

spec :: Spec
spec = describe "held-panel 256-to-512 refinement" $ do
  it "refines only length, retaining the original grips, material and springs" $ do
    V3 x _ z <- right gripTarget
    forM_ refinementCases $ \(_, layout) -> do
      c <- right (heldCase layout Triangles512)
      let f = heldFixture c
          seed = coupledSeed f
      length (triangles seed) `shouldBe` 512
      length (samples seed) `shouldBe` 387
      componentCount seed `shouldBe` 1
      closedRoot (coupledReference f) `shouldBe` [0, 1, 2]
      heldGripRoundoff c `shouldSatisfy` (<= 1e-12)
      forM_ (zip [0 ..] (samples seed)) $ \(i, p) -> do
        let u = abs (materialU p)
            y = materialV p
            grip | u <= 1 / 8 = Just (V3 u y 0) | u == 1 / 2 = Just (V3 x y z) | otherwise = Nothing
        y `shouldSatisfy` (`elem` [-0.5, 0, 0.5])
        IM.lookup i (coupledPins f) `shouldBe` grip
        forM_ grip $ \target -> position p `shouldBe` target
      forM_ (closedHinges (coupledReference f)) $ \h -> case hingeRole h of
        PanelBend -> hingeRest h `shouldBe` 0
        SurfaceCrease _ -> do hingeRest h `shouldBe` pi; hingeStiffness h `shouldBe` 0.5
        _ -> expectationFailure "refinement added a bend preference"
      checkCoupledMaterial f seed `shouldBe` Right ()

  it "requires both saved solver histories and the tighter final stop" $ do
    c <- right (heldCase WholeBendLayout Triangles256)
    let original = archive c
        sourceState = object ["measured" .= True]
        step = object ["iteration" .= (1 :: Int), "lengthWeight" .= refinementWeight, "stageSettled" .= True, "accepted" .= False, "fullRepairedMovement" .= (1e-9 :: Double), "lengthError" .= (1e-6 :: Double), "quadratic" .= object ["converged" .= True], "energyBefore" .= (1 :: Int), "energyAfter" .= (1 :: Int)]
        solve steps = object ["converged" .= True, "iterations" .= length steps, "steps" .= steps]
        r = object ["id" .= ("whole-256" :: String), "source" .= original, "states" .= object ["source" .= sourceState], "lengthWeights" .= [refinementWeight], "iterationLimitPerStage" .= (40 :: Int), "lengthTolerance" .= (1e-5 :: Double), "movementTolerance" .= refinementStop, "contactMethod" .= ("ProgressiveContactExchange" :: String), "contactEnabled" .= True, "passed" .= True, "refusal" .= Null, "continuousMotionChecked" .= False, "stages" .= (["source", "repair", "after"] :: [String]), "solve" .= solve [step]]
        doc runs = object ["gallery" .= ("held-confirmation" :: String), "movementTolerance" .= refinementStop, "sourceMovementTolerance" .= (1e-7 :: Double), "runs" .= (runs :: [Value])]
        readOne = confirmedRecord "whole-256" WholeBendLayout c
    readOne (doc [r]) `shouldBe` Right r
    forM_ [[], [r, r]] $ \runs -> readOne (doc runs) `shouldSatisfy` isLeft
    forM_ [set "passed" (Bool False) r, set "movementTolerance" (Number 1e-7) r, set "source" (set "contactEnabled" (Bool False) original) r, set "states" (object ["source" .= object ["measured" .= False]]) r, set "solve" (set "converged" (Bool False) (solve [step])) r, set "solve" (solve (replicate 41 step)) r] $ \bad -> readOne (doc [bad]) `shouldSatisfy` isLeft
    forM_ [set "accepted" (Bool True) step, set "stageSettled" (Bool False) step, set "fullRepairedMovement" (Number 1e-7) step, set "quadratic" (object ["converged" .= False]) step, set "energyAfter" (Number 0.5) step, set "lengthWeight" (Number 1e9) step, set "lengthError" (Number 1e-4) step] $ \bad -> readOne (doc [set "solve" (solve [bad]) r]) `shouldSatisfy` isLeft
    readOne (doc [set "solve" (solve [step, set "iteration" (Number 2) step]) r]) `shouldSatisfy` isLeft
    let moving = set "accepted" (Bool True) (set "stageSettled" (Bool False) (set "energyAfter" (Number 0.5) step))
        two = set "solve" (solve [moving, set "iteration" (Number 2) step]) r
    readOne (doc [two]) `shouldBe` Right two
    small <- right (heldCase WholeBendLayout Triangles128)
    confirmedRecord "whole-256" WholeBendLayout small (doc [r]) `shouldSatisfy` isLeft

set :: Data.Aeson.Key.Key -> Value -> Value -> Value
set k value (Object o) = Object (KM.insert k value o)
set _ _ value = value

archive :: HeldCase -> Value
archive c =
  object
    [ "id" .= ("whole-256" :: String),
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
      "states" .= object ["after" .= object ["measured" .= True]],
      "solve" .= object ["converged" .= True, "iterations" .= (6 :: Int), "steps" .= [object ["iteration" .= i, "lengthWeight" .= w, "stageSettled" .= True, "fullRepairedMovement" .= (1e-8 :: Double), "lengthError" .= (1e-6 :: Double), "quadratic" .= object ["converged" .= True]] | (i, w) <- zip [1 :: Int ..] equilibriumWeights]]
    ]
  where
    f = heldFixture c

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
