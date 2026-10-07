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
  ( withoutCoordinates,
    goldenFoldFile,
  )
where

import Control.Monad (unless)
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
        else
          unless (and (zipWith close (frames expected) (frames actual))) $
            refuse ("coordinates differ from " <> path <> " by more than " <> show tolerance)
  where
    actualPath = replaceExtension path (".actual" <> takeExtension path)
    frames file = keyFrame file : otherFrames file
    close a b =
      map length (verticesCoords a) == map length (verticesCoords b)
        && and (zipWith (\x y -> abs (x - y) <= tolerance) (concat (verticesCoords a)) (concat (verticesCoords b)))
