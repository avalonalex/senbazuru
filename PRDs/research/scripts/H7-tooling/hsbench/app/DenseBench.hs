-- Dense Cholesky with hmatrix (LAPACK via Apple Accelerate on macOS).
module Main (main) where

import GHC.Clock (getMonotonicTime)
import Numeric.LinearAlgebra hiding ((<>))
import Numeric.LinearAlgebra qualified as LA

main :: IO ()
main = mapM_ run [1000, 3000, 6000]
  where
    run n = do
      let a = (n >< n) [sin (fromIntegral (i * 7 + j * 13)) | i <- [0 .. n - 1], j <- [0 .. n - 1]] :: Matrix Double
          spd = trustSym (tr a LA.<> a + scalar (fromIntegral n) * ident n)
      t0 <- spd `seq` sumElements (unSym spd) `seq` getMonotonicTime
      let c = chol spd
      t1 <- sumElements c `seq` getMonotonicTime
      putStrLn ("dense chol n=" ++ show n ++ ": " ++ show (t1 - t0) ++ " s")
