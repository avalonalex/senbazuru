-- How fast is the 'ad' package at the element Hessians a Newton solver of a
-- discrete shell needs? Two elements: a hinge (4 vertices, 12 scalars) and a
-- St Venant-Kirchhoff membrane triangle (3 vertices, 9 scalars).
module Main (main) where

import Control.Monad (forM_)
import Data.List (foldl')
import GHC.Clock (getMonotonicTime)
import Numeric.AD (grad, hessian)
import Numeric.AD.Mode.Sparse qualified as S
import Numeric.AD.Double qualified as D

type P a = (a, a, a)

sub, crossP :: Num a => P a -> P a -> P a
sub (a, b, c) (d, e, f) = (a - d, b - e, c - f)
crossP (a, b, c) (d, e, f) = (b * f - c * e, c * d - a * f, a * e - b * d)

dotP :: Num a => P a -> P a -> a
dotP (a, b, c) (d, e, f) = a * d + b * e + c * f

-- Discrete-shells hinge: (theta - rest)^2 * restLength / restHeight.
hinge :: RealFloat a => [a] -> a
hinge [x0, y0, z0, x1, y1, z1, x2, y2, z2, x3, y3, z3] =
  let p0 = (x0, y0, z0); p1 = (x1, y1, z1); p2 = (x2, y2, z2); p3 = (x3, y3, z3)
      e = sub p1 p0
      n1 = crossP e (sub p2 p0)
      n2 = crossP (sub p3 p0) e
      le = sqrt (dotP e e)
      s = dotP (crossP n1 n2) e / le
      c = dotP n1 n2
      theta = atan2 s c
      rest = 2.5
   in (theta - rest) * (theta - rest) * 1.0 / 0.3
hinge _ = 0

-- StVK membrane on a triangle whose rest shape is (0,0), (1,0), (0,1).
stvk :: Floating a => [a] -> a
stvk [x0, y0, z0, x1, y1, z1, x2, y2, z2] =
  let a = sub (x1, y1, z1) (x0, y0, z0) -- F column 1 (Dm = I)
      b = sub (x2, y2, z2) (x0, y0, z0) -- F column 2
      e11 = (dotP a a - 1) / 2
      e22 = (dotP b b - 1) / 2
      e12 = dotP a b / 2
      mu = 1; lam = 1
      tr = e11 + e22
   in 0.5 * (mu * (e11 * e11 + e22 * e22 + 2 * e12 * e12) + lam / 2 * tr * tr)
stvk _ = 0

hingeAt, triAt :: Int -> [Double]
hingeAt k = let t = fromIntegral k * 1e-6 in [0, 0, 0, 1, 0, 0, 0.5, 0.8 + t, 0.1, 0.5, -0.7, 0.3 + t]
triAt k = let t = fromIntegral k * 1e-6 in [0, 0, 0, 1.1 + t, 0, 0.1, 0.05, 0.95, 0.2 + t]

timeIt :: String -> Int -> (Int -> Double) -> IO ()
timeIt label n f = do
  t0 <- getMonotonicTime
  let s = foldl' (\acc k -> acc + f k) 0 [1 .. n]
  s `seq` pure ()
  t1 <- getMonotonicTime
  putStrLn (label ++ ": " ++ show n ++ " evaluations, " ++ show ((t1 - t0) / fromIntegral n * 1e6) ++ " us each (checksum " ++ show s ++ ")")

main :: IO ()
main = do
  let n = 2000
  forM_ [1 :: Int, 2] $ \_ -> do
    timeIt "hinge value        " n (\k -> hinge (hingeAt k))
    timeIt "hinge grad (rev)   " n (\k -> sum (grad hinge (hingeAt k)))
    timeIt "hinge hessian      " n (\k -> sum (map sum (hessian hinge (hingeAt k))))
    timeIt "hinge hessian spars" n (\k -> sum (map sum (S.hessian hinge (hingeAt k))))
    timeIt "hinge grad  Double " n (\k -> sum (D.grad hinge (hingeAt k)))
    timeIt "hinge hess  Double " n (\k -> sum (map sum (D.hessian hinge (hingeAt k))))
    timeIt "stvk grad (rev)    " n (\k -> sum (grad stvk (triAt k)))
    timeIt "stvk hessian       " n (\k -> sum (map sum (hessian stvk (triAt k))))
  -- correctness: central difference of the gradient against the Hessian
  let x = hingeAt 7
      h = 1e-6
      hess = hessian hinge x
      fd i j = (grad hinge (bump j h x) !! i - grad hinge (bump j (-h) x) !! i) / (2 * h)
      bump j d xs = [if k == j then v + d else v | (k, v) <- zip [0 ..] xs]
      err = maximum [abs (hess !! i !! j - fd i j) | i <- [0 .. 11], j <- [0 .. 11]]
      asym = maximum [abs (hess !! i !! j - hess !! j !! i) | i <- [0 .. 11], j <- [0 .. 11]]
  print (take 3 (head (hessian hinge (hingeAt 7))))
  putStrLn ("hinge Hessian vs central difference of grad: max abs error " ++ show err ++ "; asymmetry " ++ show asym)
