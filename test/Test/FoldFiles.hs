-- |
-- Module      : Test.FoldFiles
-- Description : A checked-in FOLD file the code regenerates, compared as such files must be.
--
-- Some fixtures in @examples\/@ are files senbazuru writes itself, such as
-- @bird-base-sequence.fold@ and @blintz-sequence.fold@, and a test holds the
-- code to them. A byte comparison is too strict for them: coordinates come out
-- of trigonometry, which macOS and Linux compute differently in the last few
-- bits. So everything is compared exactly but the coordinates, and those to
-- within a tolerance; frame counts, topology, angles, orders, captions and
-- vendor keys stay exact.
--
-- On a mismatch it writes @x.actual.fold@ beside the fixture, as
-- "Test.Golden" does, so that accepting an intended change is reading a diff
-- and moving a file.
module Test.FoldFiles
  ( goldenFoldFile,
  )
where

import Data.ByteString qualified as BS
import Senbazuru.Fold.Load (encodeFoldFile, loadFoldFile)
import Senbazuru.Fold.Types (FoldFile (..), Frame (..))
import System.Directory (doesFileExist)
import System.FilePath (replaceExtension, takeExtension)
import Test.Hspec (Expectation, expectationFailure)

-- | The file with every frame's coordinates left out, for comparing the rest
-- exactly.
withoutCoordinates :: FoldFile -> FoldFile
withoutCoordinates file =
  file
    { keyFrame = clear (keyFrame file),
      otherFrames = map clear (otherFrames file)
    }
  where
    clear fr = fr {verticesCoords = []}

-- | The file matches the checked-in one: exactly but for coordinates, each
-- within the tolerance of the one it stands for, and as many of them.
goldenFoldFile :: Double -> FilePath -> FoldFile -> Expectation
goldenFoldFile tolerance path actual = do
  exists <- doesFileExist path
  bytes <- either (fail . show) pure (encodeFoldFile actual)
  let refuse why = BS.writeFile actualPath bytes >> expectationFailure (why <> "\n  diff with:  diff " <> path <> " " <> actualPath <> "\n  accept with: mv " <> actualPath <> " " <> path)
  if not exists
    then refuse ("fixture " <> path <> " does not exist; review " <> actualPath)
    else do
      expected <- loadFoldFile path >>= either (fail . show) pure
      if withoutCoordinates expected /= withoutCoordinates actual
        then refuse ("output does not match " <> path <> " apart from coordinates")
        else case mismatches expected of
          [] -> pure ()
          (n, v, want, got) : _ -> refuse ("frame " <> show n <> ", vertex " <> show v <> " is " <> show got <> " where " <> path <> " has " <> show want <> ", more than " <> show tolerance <> " apart")
  where
    actualPath = replaceExtension path (".actual" <> takeExtension path)
    frames file = keyFrame file : otherFrames file
    -- Where the coordinates differ, frame by frame, the key frame as frame
    -- 0 as every verb counts it: a vertex with a different number of
    -- coordinates, or one beyond the tolerance.
    mismatches expected =
      [ (n, v, want, got)
        | (n, a, b) <- zip3 [0 :: Int ..] (frames expected) (frames actual),
          (v, want, got) <- zip3 [0 :: Int ..] (verticesCoords a) (verticesCoords b),
          length want /= length got || or (zipWith (\x y -> abs (x - y) > tolerance) want got)
      ]
