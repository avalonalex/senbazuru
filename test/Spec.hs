-- hspec-discover scans this directory for modules named *Spec and builds the
-- test driver from them, so adding a spec file requires no edit here (only an
-- entry in the cabal file's other-modules).
{-# OPTIONS_GHC -F -pgmF hspec-discover #-}
