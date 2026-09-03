-- | Entry point. All the actual work lives in "Senbazuru.Cli".
module Main (main) where

import Senbazuru.Cli (runCli)

main :: IO ()
main = runCli
