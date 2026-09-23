module RestorationSearchSpec (spec) where

import RestorationSearch
import Test.Hspec

spec :: Spec
spec = describe "backtracking with one restoration per trial" $ do
  it "accepts a passing raw trial without evaluating repair or later trials" $ do
    searchWithRestoration (== (1 :: Int)) (const (Left ("unneeded" :: String))) [1, 2]
      `shouldBe` ([RepairTrial 1 Nothing], Just (0, 1))
  it "keeps a larger repaired trial before considering a passing half step" $ do
    searchWithRestoration (>= (0 :: Int)) (Right . negate :: Int -> Either String Int) [-2, 1]
      `shouldBe` ([RepairTrial (-2) (Just (Right 2))], Just (0, 2))
  it "does not repeatedly repair a refused candidate even if that could pass" $ do
    searchWithRestoration (== (0 :: Int)) (Right . (+ 1) :: Int -> Either String Int) [-2, 0]
      `shouldBe` ([RepairTrial (-2) (Just (Right (-1))), RepairTrial 0 Nothing], Just (1, 0))
  it "keeps a repair failure and then checks the next original trial" $ do
    searchWithRestoration (== (0 :: Int)) (const (Left ("no free response" :: String))) [-1, 0]
      `shouldBe` ([RepairTrial (-1) (Just (Left "no free response")), RepairTrial 0 Nothing], Just (1, 0))
  it "returns no candidate when all finite trials and repairs fail" $ do
    let (trials, selected) = searchWithRestoration (== (0 :: Int)) (Right :: Int -> Either String Int) [-3, -2, -1]
    length trials `shouldBe` 3
    selected `shouldBe` Nothing
