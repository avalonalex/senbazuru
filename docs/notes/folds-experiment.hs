-- | Standalone experiment backing docs/notes/folds.md and
-- docs/notes/strict-fields.md.
--
--   ghc -O0 -rtsopts -o folds folds-experiment.hs
--   ./folds foldl      5000000 +RTS -s
--   ./folds strictbox  1000000 +RTS -s
--
-- Repeat with -O2 to watch the strictness analyser erase every difference.
--
-- Not part of the build: it lives outside src/, app/ and test/, so neither
-- stack, ormolu nor hlint looks at it.

import Data.List (foldl')
import System.Environment (getArgs)

-- Sums, to compare foldl with foldl' ----------------------------------------

-- Builds a tower of unevaluated (+) closures, forced only at the very end.
viaFoldl :: Int -> Int
viaFoldl n = foldl (+) 0 [1 .. n]

-- Forces the accumulator each step. An Int in WHNF is just the Int.
viaFoldl' :: Int -> Int
viaFoldl' n = foldl' (+) 0 [1 .. n]

-- Accumulators, to show WHNF is not deep ------------------------------------

-- Tuple fields are lazy, so WHNF is (,) <thunk> <thunk>: foldl' stops at the
-- constructor and the thunks pile up regardless.
viaLazyPair :: Int -> Int
viaLazyPair n = case foldl' step (0, 0) [1 .. n] of (s, c) -> s + c
  where
    step (s, c) x = (s + x, c + 1)

data P = P !Int !Int

-- Same fold, strict fields: forcing the constructor now reaches the Ints.
viaStrictPair :: Int -> Int
viaStrictPair n = case foldl' step (P 0 0) [1 .. n] of P s c -> s + c
  where
    step (P s c) x = P (s + x) (c + 1)

-- The shape Senbazuru.Geometry.boxFromPoints actually uses -------------------

data LBox = LBox Double Double Double Double
data SBox = SBox !Double !Double !Double !Double

pts :: Int -> [(Double, Double)]
pts n = [(fromIntegral i, fromIntegral (i `mod` 97)) | i <- [1 .. n]]

viaLazyBox :: Int -> Double
viaLazyBox n = case foldl' g (LBox 0 0 0 0) (pts n) of LBox a b c d -> a + b + c + d
  where
    g (LBox a b c d) (x, y) = LBox (min a x) (min b y) (max c x) (max d y)

viaStrictBox :: Int -> Double
viaStrictBox n = case foldl' g (SBox 0 0 0 0) (pts n) of SBox a b c d -> a + b + c + d
  where
    g (SBox a b c d) (x, y) = SBox (min a x) (min b y) (max c x) (max d y)

main :: IO ()
main = do
  args <- getArgs
  case args of
    [mode, n] -> case mode of
      "foldl" -> print (viaFoldl (read n))
      "foldl'" -> print (viaFoldl' (read n))
      "lazypair" -> print (viaLazyPair (read n))
      "strictpair" -> print (viaStrictPair (read n))
      "lazybox" -> print (viaLazyBox (read n))
      "strictbox" -> print (viaStrictBox (read n))
      _ -> usage
    _ -> usage
  where
    usage =
      putStrLn
        "usage: folds (foldl|foldl'|lazypair|strictpair|lazybox|strictbox) COUNT"
