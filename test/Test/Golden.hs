-- |
-- Module      : Test.Golden
-- Description : A minimal golden-file assertion.
--
-- A golden test pins the exact expected output of a renderer in a committed
-- file. It is the right tool here because the interesting property of an SVG
-- backend — \"does it produce this precise document?\" — is tedious to state as
-- individual assertions but trivial to state as a file, and because the diff on
-- a failing golden test tells you immediately /what/ changed in the drawing.
--
-- The cost is that golden tests fail whenever output changes intentionally, so
-- the failure message has to make regenerating easy. That is the whole reason
-- this helper writes a @.actual.svg@ next to the golden file instead of only
-- printing a mismatch.
--
-- Hand-rolled rather than pulled from a package because it is fifteen lines and
-- one fewer dependency to keep current.
module Test.Golden
  ( goldenText,
    goldenBytes,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import System.Directory (doesFileExist)
import System.FilePath (replaceExtension, takeExtension)
import Test.Hspec (Expectation, expectationFailure)

-- | Compare text against the contents of a golden file.
--
-- If the golden file does not exist, the test fails and tells you to create it;
-- silently accepting whatever the code currently produces would make the first
-- run of a broken renderer pass.
goldenText :: FilePath -> Text -> Expectation
goldenText goldenPath actual = do
  exists <- doesFileExist goldenPath
  if not exists
    then do
      TIO.writeFile actualPath actual
      expectationFailure $
        "golden file "
          <> goldenPath
          <> " does not exist.\nReview "
          <> actualPath
          <> " and, if it is correct, move it into place:\n  mv "
          <> actualPath
          <> " "
          <> goldenPath
    else do
      expected <- TIO.readFile goldenPath
      if expected == actual
        then pure ()
        else do
          TIO.writeFile actualPath actual
          expectationFailure $
            "output does not match "
              <> goldenPath
              <> "\n  first difference: "
              <> T.unpack (firstDifference expected actual)
              <> "\n  diff with:  diff "
              <> goldenPath
              <> " "
              <> actualPath
              <> "\n  accept with: mv "
              <> actualPath
              <> " "
              <> goldenPath
  where
    actualPath = replaceExtension goldenPath ".actual.svg"

-- | 'goldenText' for a binary file.
--
-- Same contract, same @.actual@ file beside the golden, and the one thing a
-- line number cannot give: the offset of the first byte that differs, which is
-- what tells you whether a @.glb@ changed in its JSON, its geometry, or only
-- in a length field.
goldenBytes :: FilePath -> ByteString -> Expectation
goldenBytes goldenPath actual = do
  exists <- doesFileExist goldenPath
  if not exists
    then do
      BS.writeFile actualPath actual
      expectationFailure $
        "golden file "
          <> goldenPath
          <> " does not exist.\nReview "
          <> actualPath
          <> " and, if it is correct, move it into place:\n  mv "
          <> actualPath
          <> " "
          <> goldenPath
    else do
      expected <- BS.readFile goldenPath
      if expected == actual
        then pure ()
        else do
          BS.writeFile actualPath actual
          expectationFailure $
            "output does not match "
              <> goldenPath
              <> "\n  first difference: "
              <> firstByte expected actual
              <> "\n  compare with: cmp -l "
              <> goldenPath
              <> " "
              <> actualPath
              <> "\n  accept with:  mv "
              <> actualPath
              <> " "
              <> goldenPath
  where
    actualPath = replaceExtension goldenPath (".actual" <> takeExtension goldenPath)

    firstByte expected actual' =
      case [i | (i, e, a) <- zip3 [0 :: Int ..] (BS.unpack expected) (BS.unpack actual'), e /= a] of
        (i : _) -> "byte " <> show i
        [] ->
          "lengths differ: expected "
            <> show (BS.length expected)
            <> " bytes, actual "
            <> show (BS.length actual')

-- | The first line that differs, reported with its line number, so the failure
-- message is useful without opening the diff.
firstDifference :: Text -> Text -> Text
firstDifference expected actual =
  case [ (i, e, a)
         | (i, e, a) <- zip3 [1 :: Int ..] expectedLines actualLines,
           e /= a
       ] of
    ((i, e, a) : _) ->
      "line "
        <> T.pack (show i)
        <> "\n    expected: "
        <> e
        <> "\n    actual:   "
        <> a
    [] ->
      "line counts differ: expected "
        <> T.pack (show (length expectedLines))
        <> ", actual "
        <> T.pack (show (length actualLines))
  where
    expectedLines = T.lines expected
    actualLines = T.lines actual
