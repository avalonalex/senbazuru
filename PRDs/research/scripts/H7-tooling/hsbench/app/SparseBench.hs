-- Benchmark the study's SparseSolve LDL^T on the sparsity pattern of a
-- triangulated n x n sheet: one length row per edge (6 scalars) and one
-- hinge row per interior edge (12 scalars), as in the study's Gauss-Newton
-- normal matrix J^T J + damping I. Also writes the matrix as triplets so
-- other solvers can factor exactly the same system.
module Main (main) where

import Data.IntMap.Strict qualified as IM
import Data.List (foldl')
import Data.Map.Strict qualified as M
import GHC.Clock (getMonotonicTime)
import SparseSolve
import System.Environment (getArgs)
import System.IO

-- A tiny deterministic pseudo-random stream (LCG) so runs are repeatable.
lcg :: Int -> [Double]
lcg seed = map toD (tail (iterate step seed))
  where
    step x = (1103515245 * x + 12345) `mod` 2147483648
    toD x = fromIntegral x / 2147483648 - 0.5

main :: IO ()
main = do
  [nStr, out] <- getArgs
  let n = read nStr :: Int
      vid i j = i * n + j
      tris = concat [[(vid i j, vid (i + 1) j, vid (i + 1) (j + 1)), (vid i j, vid (i + 1) (j + 1), vid i (j + 1))] | i <- [0 .. n - 2], j <- [0 .. n - 2]]
      key a b = (min a b, max a b)
      -- edge -> opposite vertices
      opposite = M.fromListWith (++) (concat [[(key a b, [c]), (key b c, [a]), (key c a, [b])] | (a, b, c) <- tris])
      edges = M.toList opposite
      rs = lcg 42
      scal v k = 3 * v + k
      edgeRow ((a, b), _) r = IM.fromListWith (+) (concat [[(scal a k, 1e4 * (r + fromIntegral k * 0.3)), (scal b k, -1e4 * (r + fromIntegral k * 0.3))] | k <- [0 .. 2]])
      hingeRow ((a, b), [c, d]) r = Just (IM.fromListWith (+) [(scal v k, r * fromIntegral (k + 1) + fromIntegral w) | (w, v) <- zip [1 :: Int ..] [a, b, c, d], k <- [0 .. 2]])
      hingeRow _ _ = Nothing
      grads = zipWith edgeRow edges rs ++ [g | (e, r) <- zip edges (drop 100000 rs), Just g <- [hingeRow e r]]
      ids = [scal v k | v <- [0 .. n * n - 1], k <- [0 .. 2]]
      damping = 1e-3
  _ <- evaluateList grads
  t0 <- getMonotonicTime
  let Just factor = factorNormal damping ids grads
      rhs = IM.fromList [(i, 1) | i <- ids]
      x1 = applyFactor factor rhs
  s1 <- pure $! sum (IM.elems x1)
  t1 <- getMonotonicTime
  let x2 = applyFactor factor (IM.map (* 2) rhs)
  s2 <- pure $! sum (IM.elems x2)
  t2 <- getMonotonicTime
  hPutStrLn stderr ("n=" ++ show n ++ " vertices=" ++ show (n * n) ++ " scalars=" ++ show (length ids) ++ " rows=" ++ show (length grads) ++ " factor+solve=" ++ show (t1 - t0) ++ "s second-solve=" ++ show (t2 - t1) ++ "s check=" ++ show (s1, s2))
  -- Assemble the same normal matrix explicitly and write upper triangle triplets.
  let addRow acc g = IM.foldlWithKey' (\m i a -> IM.insertWith (IM.unionWith (+)) i (IM.map (a *) g) m) acc g
      mat = foldl' addRow (IM.fromList [(i, IM.singleton i damping) | i <- ids]) grads
  withFile out WriteMode $ \h -> do
    hPutStrLn h (show (length ids))
    mapM_ (\(i, row) -> mapM_ (\(j, v) -> if j >= i then hPutStrLn h (show i ++ " " ++ show j ++ " " ++ show v) else pure ()) (IM.toList row)) (IM.toList mat)

evaluateList :: [IM.IntMap Double] -> IO Int
evaluateList xs = pure $! foldl' (\acc m -> acc + IM.size m) 0 xs
