-- | Accounting counterexamples and archive refusals, without material solves.
module HeldLayoutCostsSpec (spec) where

import BendRefinement (gridColumns)
import ClosedCrease
import Control.Monad (forM_)
import CoupledCrease
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson.Key (Key)
import Data.Aeson.KeyMap qualified as KM
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.Maybe (fromMaybe)
import HeldEquilibrium
import HeldLayoutCosts
import HeldRefinement (refinementWeight)
import PrescribedBend
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Origami.Surface
import Test.Hspec

spec :: Spec
spec = describe "saved layout and length costs" $ do
  it "accounts for every edge once, including the shared crease" $ forM_ layoutCases $ \(_, layout, budget) -> do
    c <- right (heldCase layout budget)
    let fixture = heldFixture c; mesh = coupledSeed fixture
    m <- right (measureProbe (coupledReference fixture))
    rows <- right (locateLengths mesh (probeEdges m))
    let groups = [[h | h <- rows, lengthSide h == side] | side <- [LowerLength, UpperLength, SharedLength]]
    sum (map length groups) `shouldBe` length (probeEdges m)
    length [h | h <- rows, lengthSide h == SharedLength] `shouldBe` 2
    near (sum (map lengthCost rows)) (refinementWeight * probeLengthSquares m / 2)
    forM_ rows $ \h -> lengthDirection h `shouldSatisfy` (`elem` ["Transverse", "Lengthwise", "Diagonal"])
    locateLengths mesh (drop 1 (probeEdges m)) `shouldSatisfy` isLeft
    locateLengths mesh (probeEdges m ++ take 1 (probeEdges m)) `shouldSatisfy` isLeft
    locateLengths mesh [e {edgeActual = edgeActual e + 0.1} | e <- probeEdges m] `shouldSatisfy` isLeft

  it "keeps replacement edges and negates their accounting when reversed" $ forM_ [Triangles256, Triangles512] $ \budget -> do
    let rows layout = do c <- right (heldCase layout budget); m <- right (measureProbe (coupledReference (heldFixture c))); right (locateLengths (coupledSeed (heldFixture c)) (probeEdges m))
    a <- rows UniformLayout
    b <- rows WholeBendLayout
    forward <- right (compareLengths a b)
    backward <- right (compareLengths b a)
    length forward `shouldBe` length backward
    near (sum (map lengthDelta forward)) (sum (map lengthCost b) - sum (map lengthCost a))
    forM_ (zip forward backward) $ \(x, y) -> near (lengthDelta x) (negate (lengthDelta y))
    compareLengths (a ++ take 1 a) b `shouldSatisfy` isLeft

  it "distinguishes worst relative error from largest absolute-error cost" $ do
    let short = LocatedLength (EdgeMeasure (0, 1) 0.001 0.001000001) (V2 0 0) (V2 0.001 0) LowerLength
        long = LocatedLength (EdgeMeasure (2, 3) 1 1.00000001) (V2 0 0) (V2 0 1) SharedLength
        strain h = let e = lengthMeasure h in abs (edgeActual e / edgeRest e - 1)
    strain short `shouldSatisfy` (> strain long)
    lengthCost short `shouldSatisfy` (< lengthCost long)

  it "refuses a changed fine-mesh history even when its passed flag is true" $ do
    c <- right (heldCase WholeBendLayout Triangles512)
    let r = fineRecord c
        doc entries = object ["gallery" .= ("held-refinement" :: String), "sourceMovementTolerance" .= (1e-8 :: Double), "runs" .= (entries :: [Value])]
        readOne = layoutRecord "whole-512" WholeBendLayout Triangles512 c
        get field (Object o) = fromMaybe Null (KM.lookup field o); get _ _ = Null
        primary = get "primary" r
        confirmation = get "confirmation" r
    readOne (doc [r]) Null `shouldBe` Right (r, object [])
    forM_ [[], [r, r]] $ \entries -> readOne (doc entries) Null `shouldSatisfy` isLeft
    forM_ [set "columns" (Array mempty) r, set "heldVertices" (Array mempty) r, set "passed" (Bool False) r, set "contactEnabled" (Bool False) r, set "comparisonState" (String "whole-512-solved") r, set "primary" (set "movementTolerance" (Number 1e-6) primary) r, set "primary" (set "solve" (set "converged" (Bool False) (get "solve" primary)) primary) r, set "confirmation" (set "movementTolerance" (Number 1e-7) confirmation) r, set "confirmation" (set "skipped" (String "budget") confirmation) r, set "confirmation" (set "solve" (set "converged" (Bool False) (get "solve" confirmation)) confirmation) r] $ \bad -> readOne (doc [bad]) Null `shouldSatisfy` isLeft

fineRecord :: HeldCase -> Value
fineRecord c = object ["id" .= ("whole-512" :: String), "layout" .= show WholeBendLayout, "vertices" .= length (samples mesh), "triangles" .= length (triangles mesh), "columns" .= map (fromRational :: Rational -> Double) (gridColumns (heldGrid c)), "heldVertices" .= IM.keys (coupledPins fixture), "sharedCreaseVertices" .= closedRoot (coupledReference fixture), "lengthWeights" .= equilibriumWeights, "iterationLimitPerStage" .= (40 :: Int), "lengthTolerance" .= (1e-5 :: Double), "contactMethod" .= ("ProgressiveContactExchange" :: String), "contactEnabled" .= True, "passed" .= True, "continuousMotionChecked" .= False, "stages" .= (["before", "repair", "solved", "confirmation-repair", "after"] :: [String]), "comparisonState" .= ("whole-512-after" :: String), "states" .= object ["after" .= object []], "primary" .= object ["movementTolerance" .= (1e-7 :: Double), "refusal" .= Null, "solve" .= history (zipWith step [1 ..] equilibriumWeights)], "confirmation" .= object ["movementTolerance" .= (1e-8 :: Double), "lengthWeights" .= [refinementWeight], "refusal" .= Null, "skipped" .= Null, "solve" .= history [step 1 refinementWeight]]]
  where
    fixture = heldFixture c
    mesh = coupledSeed fixture
    step i weight = object ["iteration" .= (i :: Int), "lengthWeight" .= weight, "stageSettled" .= True, "accepted" .= False, "fullRepairedMovement" .= (1e-9 :: Double), "lengthError" .= (1e-6 :: Double), "energyBefore" .= (1 :: Int), "energyAfter" .= (1 :: Int), "quadratic" .= object ["converged" .= True]]
    history steps = object ["converged" .= True, "iterations" .= length steps, "steps" .= steps]

set :: Key -> Value -> Value -> Value
set k v (Object o) = Object (KM.insert k v o)
set _ _ v = v

near :: Double -> Double -> Expectation
near a b = abs (a - b) `shouldSatisfy` (< 1e-9)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
