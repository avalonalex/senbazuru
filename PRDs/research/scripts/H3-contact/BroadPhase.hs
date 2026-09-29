{-# LANGUAGE BangPatterns #-}

-- | Timing fixture: is a pure-Haskell broad phase fast enough for a
-- few thousand triangles of a layered paper stack?
--
-- Input lines: level x1 y1 z1 x2 y2 z2 x3 y3 z3. Pairs on the same level are
-- skipped (they are one flat layer and cannot overlap). For each other pair
-- whose boxes, padded by dhat, overlap, the narrow phase takes the minimum of
-- 6 point-triangle and 9 edge-edge distances and counts pairs within dhat.
-- Brute force and a uniform grid must agree on every count.
module Main (main) where

import Control.Exception (evaluate)
import Data.Array.Unboxed
import Data.IntMap.Strict qualified as IM
import Data.List (foldl')
import System.CPUTime (getCPUTime)
import System.Environment (getArgs)
import Text.Printf (printf)

type P = (Double, Double, Double)

sub3 :: P -> P -> P
sub3 (a, b, c) (d, e, f) = (a - d, b - e, c - f)

add3 :: P -> P -> P
add3 (a, b, c) (d, e, f) = (a + d, b + e, c + f)

mul3 :: Double -> P -> P
mul3 s (a, b, c) = (s * a, s * b, s * c)

dot3 :: P -> P -> Double
dot3 (a, b, c) (d, e, f) = a * d + b * e + c * f

norm3 :: P -> Double
norm3 p = sqrt (dot3 p p)

clamp01 :: Double -> Double
clamp01 = max 0 . min 1

-- Ericson 5.1.5
closestPT :: P -> P -> P -> P -> P
closestPT p a b c
  | d1 <= 0 && d2 <= 0 = a
  | d3 >= 0 && d4 <= d3 = b
  | vc <= 0 && d1 >= 0 && d3 <= 0 = add3 a (mul3 (d1 / (d1 - d3)) ab)
  | d6 >= 0 && d5 <= d6 = c
  | vb <= 0 && d2 >= 0 && d6 <= 0 = add3 a (mul3 (d2 / (d2 - d6)) ac)
  | va <= 0 && d4 - d3 >= 0 && d5 - d6 >= 0 = add3 b (mul3 ((d4 - d3) / ((d4 - d3) + (d5 - d6))) (sub3 c b))
  | otherwise = let den = 1 / (va + vb + vc) in add3 a (add3 (mul3 (vb * den) ab) (mul3 (vc * den) ac))
  where
    ab = sub3 b a
    ac = sub3 c a
    ap = sub3 p a
    d1 = dot3 ab ap
    d2 = dot3 ac ap
    bp = sub3 p b
    d3 = dot3 ab bp
    d4 = dot3 ac bp
    cp = sub3 p c
    d5 = dot3 ab cp
    d6 = dot3 ac cp
    vc = d1 * d4 - d3 * d2
    vb = d5 * d2 - d1 * d6
    va = d3 * d6 - d5 * d4

-- Ericson 5.1.9, segments assumed non-degenerate
distEE :: P -> P -> P -> P -> Double
distEE p1 q1 p2 q2 =
  let d1 = sub3 q1 p1
      d2 = sub3 q2 p2
      r = sub3 p1 p2
      a = dot3 d1 d1
      e = dot3 d2 d2
      f = dot3 d2 r
      c = dot3 d1 r
      b = dot3 d1 d2
      den = a * e - b * b
      s0 = if den > 1e-12 * a * e then clamp01 ((b * f - c * e) / den) else 0
      t0 = (b * s0 + f) / e
      (s, t)
        | t0 < 0 = (clamp01 (-c / a), 0)
        | t0 > 1 = (clamp01 ((b - c) / a), 1)
        | otherwise = (s0, t0)
   in norm3 (sub3 (add3 p1 (mul3 s d1)) (add3 p2 (mul3 t d2)))

data Mesh = Mesh {levels :: UArray Int Int, coords :: UArray Int Double, count :: Int}

corner :: Mesh -> Int -> Int -> P
corner m t k = let o = 9 * t + 3 * k; c = coords m in (c ! o, c ! (o + 1), c ! (o + 2))

triDistance :: Mesh -> Int -> Int -> Double
triDistance m i j =
  let [a0, a1, a2] = map (corner m i) [0, 1, 2]
      [b0, b1, b2] = map (corner m j) [0, 1, 2]
      pts = [norm3 (sub3 p (closestPT p b0 b1 b2)) | p <- [a0, a1, a2]] ++ [norm3 (sub3 p (closestPT p a0 a1 a2)) | p <- [b0, b1, b2]]
      ea = [(a0, a1), (a1, a2), (a2, a0)]
      eb = [(b0, b1), (b1, b2), (b2, b0)]
      ees = [distEE p q r s | (p, q) <- ea, (r, s) <- eb]
   in minimum (pts ++ ees)

type Box = (Double, Double, Double, Double, Double, Double)

box :: Mesh -> Double -> Int -> Box
box m pad t =
  let ps = map (corner m t) [0, 1, 2]
      xs = [x | (x, _, _) <- ps]
      ys = [y | (_, y, _) <- ps]
      zs = [z | (_, _, z) <- ps]
   in (minimum xs - pad, minimum ys - pad, minimum zs - pad, maximum xs + pad, maximum ys + pad, maximum zs + pad)

overlaps :: Box -> Box -> Bool
overlaps (a, b, c, d, e, f) (g, h, i, j, k, l) = not (d < g || j < a || e < h || k < b || f < i || l < c)

-- | (candidate pairs, pairs within dhat)
brute :: Mesh -> Double -> (Int, Int)
brute m dhat =
  let n = count m
      bs = listArray (0, n - 1) [box m (dhat / 2) t | t <- [0 .. n - 1]] :: Array Int Box
      lv = levels m
      go !c !w i j
        | i >= n = (c, w)
        | j >= n = go c w (i + 1) (i + 2)
        | lv ! i /= lv ! j && overlaps (bs ! i) (bs ! j) =
            let w' = if triDistance m i j < dhat then w + 1 else w in go (c + 1) w' i (j + 1)
        | otherwise = go c w i (j + 1)
   in go 0 0 0 1

grid :: Mesh -> Double -> Double -> (Int, Int)
grid m dhat cell =
  let n = count m
      bs = listArray (0, n - 1) [box m (dhat / 2) t | t <- [0 .. n - 1]] :: Array Int Box
      lv = levels m
      ix v = floor (v / cell) :: Int
      key x y z = ((x + 512) * 1024 + (y + 512)) * 1024 + (z + 512)
      cellsOf (a, b, c, d, e, f) = [key x y z | x <- [ix a .. ix d], y <- [ix b .. ix e], z <- [ix c .. ix f]]
      table = foldl' (\acc t -> foldl' (\a k -> IM.insertWith (++) k [t] a) acc (cellsOf (bs ! t))) IM.empty [0 .. n - 1]
      -- count a pair only in the cell holding the low corner of the boxes' overlap
      owner (a, b, c, _, _, _) (g, h, i, _, _, _) = key (ix (max a g)) (ix (max b h)) (ix (max c i))
      visit (!c, !w) (k, ts) =
        foldl'
          ( \(!c', !w') (i, j) ->
              if lv ! i /= lv ! j && overlaps (bs ! i) (bs ! j) && owner (bs ! i) (bs ! j) == k
                then (c' + 1, if triDistance m i j < dhat then w' + 1 else w')
                else (c', w')
          )
          (c, w)
          [(i, j) | (i : rest) <- tailsOf ts, j <- rest]
   in foldl' visit (0, 0) (IM.toList table)

tailsOf :: [a] -> [[a]]
tailsOf [] = []
tailsOf xs@(_ : r) = xs : tailsOf r

-- | Run five times. The repetition index perturbs dhat by 1e-12 relative, so
-- GHC cannot share one evaluated result between repetitions.
timed :: String -> (Int -> (Int, Int)) -> IO ()
timed label act = do
  ts <- mapM once [1 :: Int .. 5]
  printf "%s results=%s seconds=%s\n" label (show (map fst ts)) (show [fromIntegral t / 1e12 :: Double | (_, t) <- ts])
  where
    once k = do
      t0 <- getCPUTime
      r@(a, b) <- evaluate (act k)
      _ <- evaluate (a + b)
      t1 <- getCPUTime
      pure (r, t1 - t0)

main :: IO ()
main = do
  [path, dhatS, cellS] <- getArgs
  rows <- map (map read . words) . lines <$> readFile path :: IO [[Double]]
  let n = length rows
      m = Mesh (listArray (0, n - 1) [round (head r) | r <- rows]) (listArray (0, 9 * n - 1) (concatMap tail rows)) n
      dhat = read dhatS
      cell = read cellS
  _ <- evaluate (coords m ! (9 * n - 1))
  printf "triangles=%d dhat=%s cell=%s\n" n dhatS cellS
  let jitter k = dhat * (1 + 1e-12 * fromIntegral k)
  timed "grid " (\k -> grid m (jitter k) cell)
  timed "brute" (\k -> brute m (jitter k))
