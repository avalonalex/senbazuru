-- | Standalone experiment backing docs/notes/strict-fields.md.
--
-- Folds a million points twice with the same foldl' and the same function,
-- differing only in whether the accumulator's fields are strict.
--
--   ghc -O0 -rtsopts -o leak strict-fields-experiment.hs
--   ./leak strict 1000000 +RTS -s     -- ~44 KB peak residency
--   ./leak lazy   1000000 +RTS -s     -- ~198 MB peak residency
--
-- Repeat with -O2 to watch the strictness analyser erase the difference.
--
-- Not part of the build: it lives outside src/, app/ and test/, so neither
-- stack, ormolu nor hlint looks at it.

import Data.List (foldl')
import System.Environment (getArgs)

-- Same fold, same foldl', differing only in field strictness.
data SBox = SBox !Double !Double !Double !Double
data LBox = LBox Double Double Double Double

pts :: Int -> [(Double, Double)]
pts n = [(fromIntegral i, fromIntegral (i `mod` 97)) | i <- [1 .. n]]

strictRun :: Int -> Double
strictRun n = case foldl' g (SBox 0 0 0 0) (pts n) of SBox a b c d -> a + b + c + d
  where g (SBox a b c d) (x, y) = SBox (min a x) (min b y) (max c x) (max d y)

lazyRun :: Int -> Double
lazyRun n = case foldl' g (LBox 0 0 0 0) (pts n) of LBox a b c d -> a + b + c + d
  where g (LBox a b c d) (x, y) = LBox (min a x) (min b y) (max c x) (max d y)

main :: IO ()
main = do
  [mode, n] <- getArgs
  print $ (if mode == "strict" then strictRun else lazyRun) (read n)
