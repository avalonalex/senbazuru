-- A hand-written hyper-dual number, the "write the dual by hand" route of
-- issue #62 extended to second derivatives: value + e1 part + e2 part + e1e2
-- part, with e1^2 = e2^2 = 0. Seeding e1 on x_i and e2 on x_j gives
-- d2f/dx_i dx_j in the e1e2 part, so a 12x12 symmetric Hessian takes 78 runs.
module Main (main) where

import Data.List (foldl')
import GHC.Clock (getMonotonicTime)

data H = H !Double !Double !Double !Double deriving stock (Show)

-- Apply a scalar function given f, f', f'' at the value part.
lift1 :: (Double -> Double) -> (Double -> Double) -> (Double -> Double) -> H -> H
lift1 f f' f'' (H a b c d) = H (f a) (f' a * b) (f' a * c) (f' a * d + f'' a * b * c)

instance Num H where
  H a b c d + H a' b' c' d' = H (a + a') (b + b') (c + c') (d + d')
  H a b c d - H a' b' c' d' = H (a - a') (b - b') (c - c') (d - d')
  H a b c d * H a' b' c' d' = H (a * a') (a * b' + b * a') (a * c' + c * a') (a * d' + b * c' + c * b' + d * a')
  negate (H a b c d) = H (negate a) (negate b) (negate c) (negate d)
  abs x@(H a _ _ _) = if a < 0 then negate x else x
  signum (H a _ _ _) = H (signum a) 0 0 0
  fromInteger n = H (fromInteger n) 0 0 0

instance Fractional H where
  recip = lift1 recip (\x -> -1 / (x * x)) (\x -> 2 / (x * x * x))
  fromRational r = H (fromRational r) 0 0 0

sqrtH :: H -> H
sqrtH = lift1 sqrt (\x -> 0.5 / sqrt x) (\x -> -0.25 / (x * sqrt x))

-- atan2 y x through its partial derivatives.
atan2H :: H -> H -> H
atan2H (H y yb yc yd) (H x xb xc xd) =
  let r2 = x * x + y * y
      fy = x / r2
      fx = -y / r2
      fyy = -2 * x * y / (r2 * r2)
      fxx = 2 * x * y / (r2 * r2)
      fxy = (y * y - x * x) / (r2 * r2)
   in H (atan2 y x) (fy * yb + fx * xb) (fy * yc + fx * xc)
        (fy * yd + fx * xd + fyy * yb * yc + fxx * xb * xc + fxy * (xb * yc + yb * xc))

type P = (H, H, H)

sub, crossP :: P -> P -> P
sub (a, b, c) (d, e, f) = (a - d, b - e, c - f)
crossP (a, b, c) (d, e, f) = (b * f - c * e, c * d - a * f, a * e - b * d)

dotP :: P -> P -> H
dotP (a, b, c) (d, e, f) = a * d + b * e + c * f

hinge :: [H] -> H
hinge [x0, y0, z0, x1, y1, z1, x2, y2, z2, x3, y3, z3] =
  let p0 = (x0, y0, z0); p1 = (x1, y1, z1); p2 = (x2, y2, z2); p3 = (x3, y3, z3)
      e = sub p1 p0
      n1 = crossP e (sub p2 p0)
      n2 = crossP (sub p3 p0) e
      le = sqrtH (dotP e e)
      s = dotP (crossP n1 n2) e / le
      c = dotP n1 n2
      theta = atan2H s c
   in (theta - 2.5) * (theta - 2.5) * (1.0 / 0.3)
hinge _ = 0

hessianH :: ([H] -> H) -> [Double] -> [[Double]]
hessianH f xs =
  let n = length xs
      entry i j = let H _ _ _ d = f [H x (if k == i then 1 else 0) (if k == j then 1 else 0) 0 | (k, x) <- zip [0 ..] xs] in d
      upper = [[if j >= i then entry i j else 0 | j <- [0 .. n - 1]] | i <- [0 .. n - 1]]
   in [[if j >= i then upper !! i !! j else upper !! j !! i | j <- [0 .. n - 1]] | i <- [0 .. n - 1]]

hingeAt :: Int -> [Double]
hingeAt k = let t = fromIntegral k * 1e-6 in [0, 0, 0, 1, 0, 0, 0.5, 0.8 + t, 0.1, 0.5, -0.7, 0.3 + t]

main :: IO ()
main = do
  let n = 20000 :: Int
  mapM_
    ( \_ -> do
        t0 <- getMonotonicTime
        let s = foldl' (\acc k -> acc + sum (map sum (hessianH hinge (hingeAt k)))) 0 [1 .. n]
        s `seq` pure ()
        t1 <- getMonotonicTime
        putStrLn ("hyper-dual hinge hessian: " ++ show ((t1 - t0) / fromIntegral n * 1e6) ++ " us each (checksum " ++ show s ++ ")")
    )
    [1 :: Int, 2, 3]
  print (take 3 (head (hessianH hinge (hingeAt 7))))
