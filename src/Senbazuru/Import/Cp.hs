-- |
-- Module      : Senbazuru.Import.Cp
-- Description : Reading Orihime and Oriedita @.cp@ crease patterns.
--
-- A @.cp@ file is one crease to a line, five whitespace-separated fields:
--
-- > 1 -200.0 -200.0 -200.0 0.0
-- > 2 200.0 200.0 117.15728752538102 -0.0
--
-- a type code, then the two endpoints as @x1 y1 x2 y2@. That is the entire
-- format. There is no header, no version, no units and no comments; a @.cp@
-- with nothing in it is an empty file. It is the format MT777's Orihime
-- wrote, which its fork <https://github.com/oriedita/oriedita Oriedita> still
-- writes, and it is what most crease patterns shared as files actually are.
--
-- What it does /not/ store is the point of "Senbazuru.Import.Segments": no
-- vertices, no faces, no connectivity. Read that module before this one.
--
-- == The type codes
--
-- The four the format has always had:
--
-- +------+------------------+---------------+
-- | Code | The line is      | Read as       |
-- +======+==================+===============+
-- | 1    | the paper's edge | @B@ (border)  |
-- +------+------------------+---------------+
-- | 2    | a mountain fold  | @M@           |
-- +------+------------------+---------------+
-- | 3    | a valley fold    | @V@           |
-- +------+------------------+---------------+
-- | 4    | auxiliary        | @F@ (flat)    |
-- +------+------------------+---------------+
--
-- An /auxiliary/ line is a construction line: drawn on the pattern, not folded
-- when the model is folded. FOLD's @F@ says exactly that, so the two agree —
-- and remember that senbazuru has to dissolve @F@ edges before counting the
-- creases at a vertex, or the parity Maekawa's theorem depends on comes out
-- wrong. See "Senbazuru.Origami.FlatFold".
--
-- Codes 5 to 11 are Oriedita's, and are read as auxiliary too. Its internal
-- @LineColor@ enumeration numbers the colours from zero — black 0, red 1, blue
-- 2, cyan 3, then orange, magenta, green, yellow, purple, other, grey — and
-- the file stores the colour plus one. So the table above is black, red, blue,
-- cyan, and Oriedita's seven further auxiliary colours run on to 11. Which
-- colour a construction line was drawn in is dropped: FOLD has nowhere to put
-- it, and Oriedita itself puts it in vendor keys under @oriedita:@.
--
-- Everything else, code 0 included, is refused with the line number. 0 would
-- be @LineColor@'s @NONE@, which is Oriedita's internal marker for a line that
-- is not there; a file containing one is using a numbering senbazuru does not
-- know, and guessing at it is worse than saying so.
module Senbazuru.Import.Cp
  ( parseCp,
    assignmentForCode,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Read qualified as TR
import Senbazuru.Fold.Types (Assignment (..))
import Senbazuru.Import.Segments
  ( ImportError (..),
    Segment (..),
    fromScreenPoint,
    readNumber,
  )

-- | Read the segments of a @.cp@ file.
--
-- Blank lines are skipped, so the trailing newline every writer leaves is not
-- an error, and each line is stripped first, so a file saved on Windows does
-- not fail on its carriage returns. Line numbers count the file's real lines,
-- blank ones included, because that is what an editor will show.
parseCp :: Text -> Either ImportError [Segment]
parseCp text = traverse parseLine (filter (not . T.null . snd) numbered)
  where
    numbered = zip [1 ..] (map T.strip (T.lines text))

-- | One line: @type x1 y1 x2 y2@.
parseLine :: (Int, Text) -> Either ImportError Segment
parseLine (line, content) = case T.words content of
  [t, x1, y1, x2, y2] -> do
    code <- readCode line t
    assignment <- maybe (Left (UnknownLineType line code)) Right (assignmentForCode code)
    start <- fromScreenPoint <$> readCoord line "x1" x1 <*> readCoord line "y1" y1
    end <- fromScreenPoint <$> readCoord line "x2" x2 <*> readCoord line "y2" y2
    pure Segment {segLine = line, segStart = start, segEnd = end, segAssignment = assignment}
  fields ->
    Left . MalformedLine line $
      "expected a type and four coordinates, found "
        <> T.pack (show (length fields))
        <> " fields"

-- | The type code, which is a plain integer.
readCode :: Int -> Text -> Either ImportError Int
readCode line field = case TR.signed TR.decimal field of
  Right (code, rest) | T.null rest -> Right code
  _ -> Left (MalformedLine line ("line type is not a whole number: " <> field))

-- | One coordinate. The reading is
-- 'Senbazuru.Import.Segments.readNumber', shared with the @.opx@ reader; what
-- is here is the complaint, which names the field.
readCoord :: Int -> Text -> Text -> Either ImportError Double
readCoord line name field = case readNumber field of
  Just value -> Right value
  Nothing -> Left (MalformedLine line (name <> " is not a number: " <> field))

-- | What a type code means, or 'Nothing' if the format does not define it.
--
-- Exported because the table is the interesting part of this module, and a
-- test that walks it is worth more than one that reads a file and hopes.
assignmentForCode :: Int -> Maybe Assignment
assignmentForCode = \case
  1 -> Just Border
  2 -> Just Mountain
  3 -> Just Valley
  code | code >= 4 && code <= 11 -> Just Flat
  _ -> Nothing
