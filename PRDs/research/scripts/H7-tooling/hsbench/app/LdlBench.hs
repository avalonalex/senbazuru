-- How fast can a plain, readable Haskell sparse LDL^T be? Up-looking
-- factorization over an elimination tree, unboxed mutable vectors, and a
-- nested-dissection ordering taken from the sheet's MATERIAL coordinates:
-- paper is a flat square in material space however it is folded, so cutting
-- that square in half recursively, and numbering each cut line last, is a
-- good fill-reducing order for free. Reads the triplet files SparseBench
-- wrote (upper triangle, 3 scalars per vertex of an n x n grid).
module Main (main) where

import Control.Monad
import Control.Monad.ST
import Data.List (sortOn)
import Data.Vector.Unboxed qualified as U
import Data.Vector.Unboxed.Mutable qualified as M
import GHC.Clock (getMonotonicTime)
import System.Environment (getArgs, lookupEnv)

-- | Nested dissection of an n x n vertex grid in (row, column) material
-- coordinates: order both halves first, then the separating line.
dissect :: Int -> [Int]
dissect n = go 0 n 0 n
  where
    go r0 r1 c0 c1
      | (r1 - r0) * (c1 - c0) <= 4 = [r * n + c | r <- [r0 .. r1 - 1], c <- [c0 .. c1 - 1]]
      | r1 - r0 >= c1 - c0 =
          let m = (r0 + r1) `div` 2
           in go r0 m c0 c1 ++ go (m + 1) r1 c0 c1 ++ [m * n + c | c <- [c0 .. c1 - 1]]
      | otherwise =
          let m = (c0 + c1) `div` 2
           in go r0 r1 c0 m ++ go r0 r1 (m + 1) c1 ++ [r * n + m | r <- [r0 .. r1 - 1]]

-- | Compressed columns of the permuted upper triangle: for column k, the
-- rows i <= k and values.
data Csc = Csc {colStart :: U.Vector Int, rowIx :: U.Vector Int, vals :: U.Vector Double}

toCsc :: Int -> [(Int, Int, Double)] -> Csc
toCsc n entries =
  let upper = [(max i j, min i j, v) | (i, j, v) <- entries] -- (column, row, value), row <= column
      sorted = sortOn (\(c, r, _) -> (c, r)) upper
      counts = U.accum (+) (U.replicate n 0) [(c, 1 :: Int) | (c, _, _) <- sorted]
   in Csc (U.scanl (+) 0 counts) (U.fromList [r | (_, r, _) <- sorted]) (U.fromList [v | (_, _, v) <- sorted])

-- | Up-looking LDL^T. Returns (column pointers, row indices, values) of L
-- (unit diagonal, stored by column) and D.
factor :: Int -> Csc -> (U.Vector Int, U.Vector Int, U.Vector Double, U.Vector Double)
factor n (Csc cp ri vx) = runST $ do
  -- Symbolic pass: elimination tree and column counts of L.
  parent <- M.replicate n (-1)
  flag <- M.replicate n (-1)
  lnz <- M.replicate n (0 :: Int)
  forM_ [0 .. n - 1] $ \k -> do
    M.write flag k k
    forM_ [cp U.! k .. cp U.! (k + 1) - 1] $ \p -> do
      let walk i = do
            f <- M.read flag i
            when (i < k && f /= k) $ do
              pi' <- M.read parent i
              when (pi' == -1) (M.write parent i k)
              M.modify lnz (+ 1) i
              M.write flag i k
              pi'' <- M.read parent i
              walk pi''
      walk (ri U.! p)
  counts <- U.freeze lnz
  let lp = U.scanl (+) 0 counts
  li <- M.new (U.last lp)
  lx <- M.new (U.last lp)
  filled <- M.replicate n (0 :: Int)
  -- The symbolic pass left its own marks in flag; clear them before reusing it.
  M.set flag (-1)
  d <- M.replicate n 0
  y <- M.replicate n 0
  stack <- M.new n
  forM_ [0 .. n - 1] $ \k -> do
    M.write flag k k
    -- Scatter column k of A into y and collect the pattern of row k of L.
    top <- foldM' n
      ( \t p -> do
          let i0 = ri U.! p
          M.modify y (+ (vx U.! p)) i0
          -- walk up the tree, pushing unvisited nodes in topological order
          let climb i len = do
                f <- M.read flag i
                if i < k && f /= k
                  then do
                    M.write flag i k
                    M.write stack len i
                    pa <- M.read parent i
                    climb pa (len + 1)
                  else pure len
          len <- climb i0 0
          -- move this path just below the top part of the stack, copying
          -- from its far end first because the two ranges can overlap
          forM_ [len - 1, len - 2 .. 0] $ \q -> M.read stack q >>= M.write stack (t - len + q)
          pure (t - len)
      )
      [cp U.! k .. cp U.! (k + 1) - 1]
    dk0 <- M.read y k
    M.write y k 0
    dk <- foldM
      ( \acc s -> do
          i <- M.read stack s
          yi <- M.read y i
          M.write y i 0
          start <- pure (lp U.! i)
          fi <- M.read filled i
          forM_ [start .. start + fi - 1] $ \p -> do
            r <- M.read li p
            l <- M.read lx p
            M.modify y (subtract (l * yi)) r
          di <- M.read d i
          let lki = yi / di
          M.write li (start + fi) k
          M.write lx (start + fi) lki
          M.write filled i (fi + 1)
          pure (acc - lki * yi)
      )
      dk0
      [top .. n - 1]
    M.write d k dk
  (,,,) lp <$> U.freeze li <*> U.freeze lx <*> U.freeze d
  where
    foldM' start f xs = foldM f start xs

-- | Solve L D L^T x = b.
solve :: (U.Vector Int, U.Vector Int, U.Vector Double, U.Vector Double) -> U.Vector Double -> U.Vector Double
solve (lp, li, lx, d) b = runST $ do
  let n = U.length d
  x <- U.thaw b
  forM_ [0 .. n - 1] $ \j -> do
    xj <- M.read x j
    forM_ [lp U.! j .. lp U.! (j + 1) - 1] $ \p -> M.modify x (subtract (lx U.! p * xj)) (li U.! p)
  forM_ [0 .. n - 1] $ \j -> M.modify x (/ (d U.! j)) j
  forM_ [n - 1, n - 2 .. 0] $ \j -> do
    s <- foldM (\acc p -> (\v -> acc - lx U.! p * v) <$> M.read x (li U.! p)) 0 [lp U.! j .. lp U.! (j + 1) - 1]
    M.modify x (+ s) j
  U.freeze x

main :: IO ()
main = do
  files <- getArgs
  forM_ files $ \file -> do
    contents <- readFile file
    useAmd <- lookupEnv "AMD"
    amd <- case useAmd of
      Just _ -> Just . U.fromList . map read . lines <$> readFile (take (length file - 4) file ++ ".amd")
      Nothing -> pure Nothing
    let (header : rest) = lines contents
        n = read header :: Int
        side = round (sqrt (fromIntegral (n `div` 3) :: Double)) :: Int
        nd = U.fromList [3 * v + c | v <- dissect side, c <- [0 .. 2]] -- new -> old
        order = maybe nd id amd
        inverse = U.update (U.replicate n 0) (U.imap (\new old -> (old, new)) order)
        entries = [(inverse U.! read a, inverse U.! read b, read v) | l <- rest, let [a, b, v] = words l]
        a = toCsc n entries
    U.sum (vals a) `seq` pure ()
    times <- forM [1 :: Int .. 3] $ \r -> do
      t0 <- getMonotonicTime
      let a' = a {vals = U.map (* (1 + fromIntegral r * 0)) (vals a)}
          f@(lp, _, _, _) = factor n a'
          x = solve f (U.replicate n 1)
      U.sum x `seq` U.last lp `seq` pure ()
      t1 <- getMonotonicTime
      pure (t1 - t0, U.last lp)
    -- residual of the permuted system
    let f = factor n a
        x = solve f (U.replicate n 1)
        ax = U.accum (+) (U.replicate n 0) (concat [if r == c then [(r, v * x U.! c)] else [(r, v * x U.! c), (c, v * x U.! r)] | c <- [0 .. n - 1], p <- [colStart a U.! c .. colStart a U.! (c + 1) - 1], let r = rowIx a U.! p, let v = vals a U.! p])
        resid = sqrt (U.sum (U.map (^ (2 :: Int)) (U.zipWith (-) ax (U.replicate n 1)))) / sqrt (fromIntegral n)
    putStrLn (file ++ " scalars=" ++ show n ++ " L-nnz=" ++ show (snd (head times)) ++ " factor+solve(ms, 3 runs)=" ++ show [round (t * 1000) :: Int | (t, _) <- times] ++ " residual=" ++ show resid)
