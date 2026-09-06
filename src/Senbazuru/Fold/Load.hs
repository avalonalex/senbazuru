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
--
-- == Three formats in, one format out
--
-- Senbazuru also reads the two crease-pattern formats the desktop editors use
-- — Orihime and Oriedita's @.cp@, ORIPA's @.opx@ — because most crease
-- patterns in the wild are one of those rather than FOLD. 'loadFile' picks the
-- reader from the file's extension and hands back a 'FoldFile' either way, so
-- nothing downstream of this module has to know there was a choice. The two
-- readers are "Senbazuru.Import.Cp" and "Senbazuru.Import.Opx"; what they
-- have in common is "Senbazuru.Import.Segments".
--
-- Only reading is offered. Senbazuru writes FOLD and nothing else, because a
-- @.cp@ or an @.opx@ cannot hold what a FOLD file holds — no faces, no fold
-- angles, no frames — and writing one would be quietly throwing those away.
module Senbazuru.Fold.Load
  ( -- * Reading, in whatever format
    LoadError (..),
    renderLoadError,
    loadFile,
    decodeFile,

    -- * Reading FOLD in particular
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
import Data.Char (toLower)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8Lenient)
import Senbazuru.Fold.Types (FoldFile)
import Senbazuru.Import.Cp (parseCp)
import Senbazuru.Import.Opx (parseOpx)
import Senbazuru.Import.Segments (ImportError, foldFileFromSegments, renderImportError)
import System.FilePath (takeExtension)

-- | Why a file could not be loaded.
--
-- The cases are kept apart because they mean different things to whoever is
-- holding the file. \"I could not read this\" is usually a typo in a path;
-- \"I could not decode this\" means the bytes arrived but are not FOLD; and an
-- 'ImportFailed' means the bytes arrived, are one of the two crease-pattern
-- formats, and something in them is wrong at a line that can be named.
data LoadError
  = ReadFailed FilePath Text
  | DecodeFailed FilePath Text
  | ImportFailed FilePath ImportError
  deriving stock (Eq, Show)

-- | A message suitable for printing to a terminal.
renderLoadError :: LoadError -> Text
renderLoadError = \case
  ReadFailed path msg -> "cannot read " <> T.pack path <> ": " <> msg
  DecodeFailed path msg -> "cannot decode " <> T.pack path <> ": " <> msg
  ImportFailed path err -> "cannot read " <> T.pack path <> ": " <> renderImportError err

-- | Decode bytes as whatever format the path names.
--
-- @.cp@ and @.opx@ go to their own readers; everything else is decoded as
-- FOLD, which is what happened to every path before there was a choice, and
-- which keeps a file called @pattern.json@, or @pattern@ with no extension at
-- all, working. The extension is lowercased first, so a @.CP@ off a
-- case-insensitive filesystem is still a @.cp@.
--
-- Pure, and separate from 'loadFile', so that a test can put bytes in without
-- putting a file on a disk.
decodeFile :: FilePath -> ByteString -> Either LoadError FoldFile
decodeFile path bytes = case map toLower (takeExtension path) of
  ".cp" -> imported parseCp
  ".opx" -> imported parseOpx
  _ -> decodedAsFold path bytes
  where
    -- Lenient decoding rather than strict: neither format says what encoding
    -- it is in, both are ASCII in practice, and one stray byte should not be
    -- the thing that stops a pattern of numbers loading.
    imported parse = case parse (decodeUtf8Lenient bytes) >>= foldFileFromSegments of
      Left err -> Left (ImportFailed path err)
      Right f -> Right f

-- | Read a crease pattern in whatever format senbazuru understands it.
--
-- The one to call unless you specifically want FOLD and nothing else. Errors
-- come back in 'Either' for the reason 'loadFoldFile' gives.
loadFile :: FilePath -> IO (Either LoadError FoldFile)
loadFile path = withBytes path (decodeFile path)

-- | Decode FOLD from bytes.
--
-- Uses the strict decoder: @.fold@ files are small enough to hold in memory,
-- and lazy decoding would let a parse error surface far away from this call.
decodeFoldFile :: ByteString -> Either String FoldFile
decodeFoldFile = eitherDecodeStrict'

-- | Read and decode a @.fold@ file, whatever it is called.
--
-- Returns errors in 'Either' rather than throwing. A missing or malformed
-- input file is an expected outcome for a command-line tool, not an exceptional
-- one, and the caller is better placed to decide how loudly to complain.
loadFoldFile :: FilePath -> IO (Either LoadError FoldFile)
loadFoldFile path = withBytes path (decodedAsFold path)

decodedAsFold :: FilePath -> ByteString -> Either LoadError FoldFile
decodedAsFold path bytes = case decodeFoldFile bytes of
  Left err -> Left (DecodeFailed path (T.pack err))
  Right f -> Right f

-- | Read a file and hand its bytes to a decoder, turning the read failure that
-- a missing file or an unreadable directory throws into a 'Left'.
withBytes :: FilePath -> (ByteString -> Either LoadError a) -> IO (Either LoadError a)
withBytes path decode = do
  readResult <- try (BS.readFile path)
  pure $ case readResult of
    Left e -> Left (ReadFailed path (T.pack (show (e :: IOException))))
    Right bytes -> decode bytes

-- | Why a @.fold@ file could not be written.
--
-- Kept apart from 'LoadError' rather than folded into it as one more
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
