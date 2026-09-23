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
--
-- == A fourth kind of file, which this module only reads as text
--
-- A /sequence source/, @.foldseq@, says how a model is folded, step by step
-- (see \"Fold sequences\" in docs/glossary.md). It is not a crease pattern,
-- and it does not become a 'FoldFile' here: running it needs the code that
-- folds paper and a second file, its sheet. So 'readSequenceText' hands back
-- its text and nothing more, and this module imports nothing of the sequence
-- language. 'decodeFile' refuses one by its extension, which is the only
-- thing that tells a mistaken @render blintz.foldseq@ from a FOLD file with
-- bad JSON in it.
module Senbazuru.Fold.Load
  ( -- * Reading, in whatever format
    LoadError (..),
    renderLoadError,
    loadFile,
    decodeFile,

    -- * Reading a sequence source, as text
    readSequenceText,
    decodeSequenceText,

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
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8', decodeUtf8Lenient)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types (FoldFile)
import Senbazuru.Import.Cp (parseCp)
import Senbazuru.Import.Opx (parseOpx)
import Senbazuru.Import.Segments (ImportError, foldFileFromSegments)
import System.FilePath (takeExtension)

-- | Why a file could not be loaded.
--
-- \"I could not read this\" is usually a typo in a path, and \"I could not
-- decode this\" means the bytes arrived and are not what the file said they
-- would be. Those are the two things a person holding the file needs told
-- apart, and 'explain' prints them with different words.
--
-- 'DecodeFailed' and 'ImportFailed' are both the second of those, and are two
-- constructors rather than one because they carry different evidence: aeson
-- hands back a message about JSON, while the crease-pattern readers can name
-- a line. A caller that only prints them will not notice the difference; one
-- that wants the line will.
--
-- The last two are about sequence sources. 'IsSequenceSource' is a file handed
-- to a reader of crease patterns that is not one. Its words name no command:
-- this message is also read in GHCi and by the material study, where a
-- command's name is no help, and the command line adds its own advice.
data LoadError
  = ReadFailed FilePath Text
  | DecodeFailed FilePath Text
  | ImportFailed FilePath ImportError
  | -- | A @.foldseq@ file, which describes how a model is folded rather than
    -- a crease pattern.
    IsSequenceSource FilePath
  | -- | A sequence source that is not UTF-8 text.
    NotUtf8 FilePath
  deriving stock (Eq, Show)

instance Explain LoadError where
  explain = \case
    ReadFailed path msg -> "cannot read " <> T.pack path <> ": " <> msg
    DecodeFailed path msg -> "cannot decode " <> T.pack path <> ": " <> msg
    ImportFailed path err -> "cannot decode " <> T.pack path <> ": " <> explain err
    IsSequenceSource path ->
      "cannot read " <> T.pack path <> " as a crease pattern: it is a fold sequence source, the steps that fold a model"
    NotUtf8 path -> "cannot decode " <> T.pack path <> ": a sequence source is UTF-8 text, and this is not"

-- | 'explain' for a 'LoadError', under the name the test suite already uses.
renderLoadError :: LoadError -> Text
renderLoadError = explain

-- | Decode bytes as whatever format the path names.
--
-- @.cp@ and @.opx@ go to their own readers, and a @.foldseq@ is refused as
-- a sequence source, which is no crease pattern at all. Everything else is
-- decoded as FOLD, which is what happened to every path before there was a
-- choice, and which keeps a file called @pattern.json@, or @pattern@ with no
-- extension at all, working. The extension is lowercased first, so a @.CP@
-- off a case-insensitive filesystem is still a @.cp@.
--
-- Pure, and separate from 'loadFile', so that a test can put bytes in without
-- putting a file on a disk.
decodeFile :: FilePath -> ByteString -> Either LoadError FoldFile
decodeFile path bytes = case map toLower (takeExtension path) of
  ".cp" -> imported parseCp
  ".opx" -> imported parseOpx
  ".foldseq" -> Left (IsSequenceSource path)
  _ -> decodedAsFold path bytes
  where
    -- Lenient decoding rather than strict: neither format says what encoding
    -- it is in, both are ASCII in practice, and one stray byte should not be
    -- the thing that stops a pattern of numbers loading.
    --
    -- A leading byte-order mark has to go before anything else sees it. It is
    -- a zero-width space, so it is invisible in a terminal and it is not
    -- whitespace to Data.Char -- it glues itself to the first field of the
    -- first line and the reader complains that the line type is not a number,
    -- naming a character nobody can see. Windows editors write one.
    imported parse = case parse (withoutBom (decodeUtf8Lenient bytes)) >>= foldFileFromSegments of
      Left err -> Left (ImportFailed path err)
      Right f -> Right f

-- | A leading byte-order mark removed, if there is one.
withoutBom :: Text -> Text
withoutBom text = fromMaybe text (T.stripPrefix "\65279" text)

-- | Read a crease pattern in whatever format senbazuru understands it.
--
-- The one to call unless you specifically want FOLD and nothing else. Errors
-- come back in 'Either' for the reason 'loadFoldFile' gives.
loadFile :: FilePath -> IO (Either LoadError FoldFile)
loadFile path = withBytes path (decodeFile path)

-- | Read a sequence source as text, and nothing more: it is parsed and run by
-- the sequence language, which this module knows nothing of.
readSequenceText :: FilePath -> IO (Either LoadError Text)
readSequenceText path = withBytes path (decodeSequenceText path)

-- | The text of a sequence source's bytes.
--
-- Strict UTF-8, where the crease-pattern readers are lenient. Their files are
-- numbers in practice, and one stray byte should not stop a pattern loading.
-- A source holds captions an author wrote, and a byte that is not UTF-8 would
-- otherwise become a replacement character in a caption, with no word said.
--
-- A leading byte-order mark goes, for the reason 'decodeFile' gives, and
-- nothing else changes: line ends, tabs and trailing space all reach the
-- parser as written, which counts its columns on exactly this text.
decodeSequenceText :: FilePath -> ByteString -> Either LoadError Text
decodeSequenceText path bytes = case decodeUtf8' bytes of
  Left _ -> Left (NotUtf8 path)
  Right text -> Right (withoutBom text)

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

instance Explain SaveError where
  explain (WriteFailed path msg) = "cannot write " <> T.pack path <> ": " <> msg

-- | 'explain' for a 'SaveError', under the name the test suite already uses.
renderSaveError :: SaveError -> Text
renderSaveError = explain

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
