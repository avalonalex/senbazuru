-- |
-- Module      : Senbazuru.Sequence.Write
-- Description : A run as a sequence file: one FOLD file holding every state it reached.
--
-- A run's states become a /sequence file/ (see docs/glossary.md, "Fold
-- sequences"): an ordinary FOLD file that @render --steps@ draws as a page and
-- @export --frame@ turns into a model, so nothing reading it needs to know a
-- sequence made it. The frames are 'Senbazuru.Sequence.Record.writtenStates',
-- which is where the state rule, the captions and the vendor keys are; this
-- module lays them out.
--
-- == The layout, and the line that looks off by one
--
-- The key frame holds only the file's metadata, no vertices. State 0, the
-- sheet laid flat, is @file_frames[0]@, and state k is @file_frames[k]@. Every
-- verb counts the key frame as frame 0, so state k is @--frame k+1@. That is
-- not an off-by-one: the key frame holds no state, as in
-- @examples\/bird-base-sequence.fold@ (PRDs\/decisions.md, D24).
--
-- Keeping the states out of the key frame is what lets a state be one of many
-- rather than the file's own geometry, and keeps the sheet's own keys from
-- being mistaken for a state's.
module Senbazuru.Sequence.Write
  ( FileHeader (..),
    noFileHeader,
    writeSequence,
  )
where

import Data.Text (Text)
import Senbazuru.Fold.Types (FoldFile (..), emptyFrame)
import Senbazuru.Sequence.Error (SequenceError)
import Senbazuru.Sequence.Record (Run (..), WrittenState (..), writtenStates)

-- | What a written file says about itself that the run does not know: who
-- wrote the sequence, and a description of it. The title is the sequence's
-- own.
data FileHeader = FileHeader
  { headerAuthor :: Maybe Text,
    headerDescription :: Maybe Text
  }
  deriving stock (Eq, Show)

-- | A file that says nothing more than the run does.
noFileHeader :: FileHeader
noFileHeader = FileHeader Nothing Nothing

-- | The run as a sequence file: FOLD 1.2, made by senbazuru, titled as the
-- sequence is, its class @diagrams@, and every state the run reached. Refused
-- only for a state that cannot be written.
--
-- The sheet's own @file_classes@ and top-level keys are not copied: until #73
-- separates a file's keys from a frame's, there is no telling which describe
-- the sheet and which the file.
writeSequence :: FileHeader -> Run -> Either SequenceError FoldFile
writeSequence header run = do
  states <- writtenStates run
  pure
    FoldFile
      { fileSpec = Just 1.2,
        fileCreator = Just "senbazuru",
        fileAuthor = headerAuthor header,
        fileTitle = runTitle run,
        fileDescription = headerDescription header,
        fileClasses = ["diagrams"],
        keyFrame = emptyFrame,
        otherFrames = map stateFrame states
      }
