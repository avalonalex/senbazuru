-- |
-- Module      : Senbazuru.Fold.Load
-- Description : Reading and writing @.fold@ files on disk.
--
-- This is the only module in the library that performs I/O, in either
-- direction. Keeping the boundary that narrow means everything else is pure
-- and directly testable without touching the filesystem: 'decodeFoldFile'
-- takes bytes and 'encodeFoldFile' returns them, and the tests can hand one to
-- the other without a temporary directory.
--
-- The module is called @Load@ because reading came first. What the two halves
-- share is not loading but the filesystem, which is the thing worth having one
-- module for.
module Senbazuru.Fold.Load
  ( -- * Reading
    LoadError (..),
    renderLoadError,
    loadFoldFile,
    decodeFoldFile,

    -- * Writing
    SaveError (..),
    renderSaveError,
    saveFoldFile,
    encodeFoldFile,
  )
where

import Control.Exception (IOException, try)
import Data.Aeson (eitherDecodeStrict', encode)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Fold.Types (FoldFile)

-- | Why a @.fold@ file could not be loaded.
--
-- The two cases are kept apart because they mean different things to whoever
-- is holding the file: \"I could not read this\" is usually a typo in a path,
-- while \"I could not decode this\" means the bytes arrived but are not FOLD.
data LoadError
  = ReadFailed FilePath Text
  | DecodeFailed FilePath Text
  deriving stock (Eq, Show)

-- | A message suitable for printing to a terminal.
renderLoadError :: LoadError -> Text
renderLoadError = \case
  ReadFailed path msg -> "cannot read " <> T.pack path <> ": " <> msg
  DecodeFailed path msg -> "cannot decode " <> T.pack path <> ": " <> msg

-- | Decode FOLD from bytes.
--
-- Uses the strict decoder: @.fold@ files are small enough to hold in memory,
-- and lazy decoding would let a parse error surface far away from this call.
decodeFoldFile :: ByteString -> Either String FoldFile
decodeFoldFile = eitherDecodeStrict'

-- | Read and decode a @.fold@ file.
--
-- Returns errors in 'Either' rather than throwing. A missing or malformed
-- input file is an expected outcome for a command-line tool, not an exceptional
-- one, and the caller is better placed to decide how loudly to complain.
loadFoldFile :: FilePath -> IO (Either LoadError FoldFile)
loadFoldFile path = do
  readResult <- try (BS.readFile path)
  pure $ case readResult of
    Left e -> Left (ReadFailed path (T.pack (show (e :: IOException))))
    Right bytes -> case decodeFoldFile bytes of
      Left err -> Left (DecodeFailed path (T.pack err))
      Right f -> Right f

-- | Why a @.fold@ file could not be written.
--
-- Kept apart from 'LoadError' rather than folded into it as a third
-- constructor: nothing that writes a file can produce a decode failure, and a
-- caller that has to pattern-match on cases it can never see learns nothing
-- from the type.
data SaveError = WriteFailed FilePath Text
  deriving stock (Eq, Show)

-- | A message suitable for printing to a terminal.
renderSaveError :: SaveError -> Text
renderSaveError (WriteFailed path msg) = "cannot write " <> T.pack path <> ": " <> msg

-- | Encode FOLD to bytes.
--
-- What goes in and what stays out is decided by the 'Data.Aeson.ToJSON'
-- instances in "Senbazuru.Fold.Types"; this only flattens the result. The
-- output is compact — one line — because a @.fold@ file is interchange between
-- tools rather than something to read, and it ends in a newline because a file
-- on disk should.
encodeFoldFile :: FoldFile -> ByteString
encodeFoldFile f = BL.toStrict (encode f) <> "\n"

-- | Encode a @.fold@ file and write it.
--
-- Returns errors in 'Either' for the same reason 'loadFoldFile' does: a full
-- disk or an unwritable directory is an expected outcome for a command-line
-- tool, and the caller decides how loudly to complain.
saveFoldFile :: FilePath -> FoldFile -> IO (Either SaveError ())
saveFoldFile path f = do
  writeResult <- try (BS.writeFile path (encodeFoldFile f))
  pure $ case writeResult of
    Left e -> Left (WriteFailed path (T.pack (show (e :: IOException))))
    Right () -> Right ()
