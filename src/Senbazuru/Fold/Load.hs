-- |
-- Module      : Senbazuru.Fold.Load
-- Description : Reading and decoding @.fold@ files from disk.
--
-- This is the only module in the library that performs I/O. Keeping the
-- boundary that narrow means everything else is pure and directly testable
-- without touching the filesystem: 'decodeFoldFile' takes bytes, and the tests
-- can hand it a literal.
module Senbazuru.Fold.Load
  ( LoadError (..),
    renderLoadError,
    loadFoldFile,
    decodeFoldFile,
  )
where

import Control.Exception (IOException, try)
import Data.Aeson (eitherDecodeStrict')
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
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
