-- | Check the original equations independently of their factorization.
module SparseSolveSpec (spec) where

import Data.IntMap.Strict qualified as IM
import Data.Maybe (isNothing)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import SparseSolve
import Test.Hspec
import Test.QuickCheck

spec :: Spec
spec = describe "coupled sparse linear solve" $ do
  it "recovers solutions of small positive normal systems" $ property $ \(NonEmpty raw) ->
    let values = take 30 (raw :: [Int])
        rows = [IM.fromList [(i, fromIntegral ((v `mod` 11) - 5)), ((i + 1) `mod` 7, 0.3)] | (k, v) <- zip [0 :: Int ..] values, let i = k `mod` 7]
        target = IM.fromList [(i, fromIntegral (i - 3)) | i <- [0 .. 6]]
        rhs = normal 0.2 rows target
     in case factorNormal 0.2 [0 .. 6] rows of
          Nothing -> counterexample "positive damping must give a positive system" False
          Just factor -> property $ largest (IM.unionWith (-) (applyFactor factor rhs) target) < 1e-9
  it "removes held coordinates and permits sparse ids and a sparse right side" $ do
    factor <- some (factorNormal 1 [4, 9] [IM.fromList [(4, 1), (9, -1), (88, 1e8)]])
    let answer = applyFactor factor (IM.singleton 4 1)
    IM.keys answer `shouldBe` [4, 9]
    largest (IM.unionWith (-) answer (IM.fromList [(4, 2 / 3), (9, 1 / 3)])) `shouldSatisfy` (< 1e-12)
  it "verifies stiff coupled motion against the original rows" $ do
    let ids = [0 .. 59]
        rows = [IM.fromList [(i, 1e5), (i + 1, -1e5)] | i <- [0 .. 58]]
        rhs = IM.fromList [(i, if even i then 1 else -1) | i <- ids]
        action = vectors . normal 1e-3 rows . scalars
    factor <- some (factorNormal 1e-3 ids rows)
    let (answer, report) = conjugateGradient 20 1e-6 (vectors . applyFactor factor . scalars) action (vectors rhs)
        actual = IM.intersectionWith (^-^) (vectors rhs) (action answer)
        residual = sqrt (sum (map (\v -> dot v v) (IM.elems actual)))
    linearConverged report `shouldBe` True
    linearResidual report `shouldBe` residual
    residual `shouldSatisfy` (<= linearThreshold report)
    linearIterations report `shouldSatisfy` (< 20)
  it "reports exhausted work and invalid directions without claiming equilibrium" $ do
    let rhs = vectors (IM.singleton 7 1)
        (_, exhausted) = conjugateGradient 0 1e-6 id id rhs
        (_, invalid) = conjugateGradient 10 1e-6 id (IM.map negateV) rhs
        negateV = ((-1) *^)
    linearConverged exhausted `shouldBe` False
    linearResidual exhausted `shouldBe` 1
    linearConverged invalid `shouldBe` False
  it "accepts a zero right side without factorization work" $ do
    let (_, report) = conjugateGradient 0 1e-6 id id (vectors (IM.singleton 0 0))
    linearConverged report `shouldBe` True
    linearIterations report `shouldBe` 0
    linearResidual report `shouldBe` 0
  it "refuses nonfinite or nonpositive factor data" $ do
    factorNormal 0 [0] [] `shouldSatisfy` isNothing
    factorNormal (0 / 0) [0] [] `shouldSatisfy` isNothing
    factorNormal 1 [0] [IM.singleton 0 (1 / 0)] `shouldSatisfy` isNothing

normal :: Double -> [IM.IntMap Double] -> IM.IntMap Double -> IM.IntMap Double
normal damping rows values = IM.mapWithKey coordinate values
  where
    coordinate i v = damping * v + sum [IM.findWithDefault 0 i row * sum (IM.elems (IM.intersectionWith (*) row values)) | row <- rows]

vectors :: IM.IntMap Double -> IM.IntMap V3
vectors = IM.map (\x -> V3 x 0 0)

scalars :: IM.IntMap V3 -> IM.IntMap Double
scalars = IM.map (\(V3 x _ _) -> x)

largest :: IM.IntMap Double -> Double
largest = maximum . (0 :) . map abs . IM.elems

some :: Maybe a -> IO a
some = maybe (fail "expected a positive factor") pure
