-- |
-- Module      : Senbazuru.Import.Opx
-- Description : Reading ORIPA @.opx@ crease patterns.
--
-- An @.opx@ file holds the same thing a @.cp@ file does — a flat list of line
-- segments with a type code — wrapped in a great deal of XML. Read
-- "Senbazuru.Import.Segments" first for what that list is missing.
--
-- The XML is not a designed file format. ORIPA is a Java program, and it saves
-- by handing its @oripa.DataSet@ object to @java.beans.XMLEncoder@, which
-- writes out whatever fields the bean happens to have:
--
-- > <object class="oripa.OriLineProxy">
-- >  <void property="type">
-- >   <int>2</int>
-- >  </void>
-- >  <void property="x0">
-- >   <double>200.0</double>
-- >  </void>
-- >  ...
--
-- Two consequences make this worth writing down, because both look like
-- nothing until they bite.
--
-- __The properties are named, and the order they come in is not the order you
-- expect.__ ORIPA writes @x0@, @x1@, @y0@, @y1@ — both @x@s, then both @y@s —
-- because @XMLEncoder@ sorts a bean's properties by name. A reader that takes
-- the four numbers in the order they appear puts the second point's @x@ into
-- the first point's @y@ and draws a crease pattern that is subtly, plausibly
-- wrong. Names are the only thing to go by, and this module goes by them.
--
-- __A property equal to zero is not written at all.__ @XMLEncoder@ omits any
-- value that already matches a freshly constructed bean's, and a fresh
-- @OriLineProxy@ is all zeroes. So a crease along the @y@ axis loses both its
-- @x@ coordinates, and an auxiliary line — type 0 — loses its @type@ and is
-- indistinguishable from a line with no type at all. Absent means zero here,
-- which is the opposite of the rule FOLD is read by, where absent means the
-- file made no claim. That is not a contradiction: FOLD is a format someone
-- designed, and this is a memory dump of a Java object.
--
-- There are also two dialects, twenty years apart, because @XMLEncoder@
-- changed how it writes a field with no public setter. Old files say
-- @\<void property=\"lines\"\>@ and new ones say @\<void method=\"getField\"\>@
-- with the name in a @\<string\>@. Neither wrapper is read here: this module
-- looks for @oripa.OriLineProxy@ objects wherever they are and ignores
-- everything around them, which makes both dialects the same file.
--
-- == The type codes
--
-- +------+------------------+---------------+
-- | Code | The line is      | Read as       |
-- +======+==================+===============+
-- | 0    | auxiliary        | @F@ (flat)    |
-- +------+------------------+---------------+
-- | 1    | the paper's edge | @B@ (border)  |
-- +------+------------------+---------------+
-- | 2    | a mountain fold  | @M@           |
-- +------+------------------+---------------+
-- | 3    | a valley fold    | @V@           |
-- +------+------------------+---------------+
--
-- The two formats agree on 1, 2 and 3 and disagree about where auxiliary
-- sits: 0 here, 4 in a @.cp@ file. See "Senbazuru.Import.Cp" for that table
-- and [the note](https://github.com/avalonalex/senbazuru/blob/main/docs/notes/cp-and-opx.md)
-- for how both were established.
module Senbazuru.Import.Opx
  ( parseOpx,
    assignmentForCode,
  )
where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Read qualified as TR
import Senbazuru.Fold.Types (Assignment (..))
import Senbazuru.Import.Segments
  ( ImportError (..),
    Segment (..),
    fromScreenPoint,
  )
import Text.HTML.TagSoup (ParseOptions (..), Tag (..), parseOptions, parseTagsOptions)

-- | Read the segments of an @.opx@ file.
--
-- Positions are turned on so that a complaint can name a line of the XML,
-- which is the only landmark a person scrolling through one of these has.
parseOpx :: Text -> Either ImportError [Segment]
parseOpx = collect 1 [] . parseTagsOptions parseOptions {optTagPosition = True}

-- | The class name every crease in the file is an instance of.
proxyClass :: Text
proxyClass = "oripa.OriLineProxy"

-- | Walk the whole tag stream, picking up each @OriLineProxy@ object and
-- skipping everything else — the header, the paper size, the array wrapper,
-- and whichever dialect of them this file uses.
--
-- The 'Int' threaded through every case is the line the last 'TagPosition'
-- announced, which is where an error will be reported.
collect :: Int -> [Segment] -> [Tag Text] -> Either ImportError [Segment]
collect _ found [] = Right (reverse found)
collect _ found (TagPosition row _ : rest) = collect row found rest
collect row found (TagOpen name attrs : rest)
  | name == "object",
    lookup "class" attrs == Just proxyClass = do
      (row', fields, rest') <- properties row [] rest
      segment <- segmentFrom row fields
      collect row' (segment : found) rest'
collect row found (_ : rest) = collect row found rest

-- | Every @\<void property=\"...\"\>@ up to the end of the enclosing object.
properties :: Int -> [(Text, Double)] -> [Tag Text] -> Either ImportError (Int, [(Text, Double)], [Tag Text])
properties _row fields (TagPosition r _ : rest) = properties r fields rest
properties row fields (TagClose "object" : rest) = Right (row, fields, rest)
properties row fields (TagOpen "void" attrs : rest)
  | Just name <- lookup "property" attrs = do
      (row', value, rest') <- propertyValue row rest
      properties row' ((name, value) : fields) rest'
properties row fields (_ : rest) = properties row fields rest
properties row _ [] = Left (MalformedLine row "an <object> that is never closed")

-- | The number inside one property.
--
-- The wrapping element says which Java type it was — @\<int\>@ for the line
-- type, @\<double\>@ for a coordinate — and all of them are read as 'Double',
-- since that is what a coordinate is and the type code is checked for being
-- whole afterwards.
propertyValue :: Int -> [Tag Text] -> Either ImportError (Int, Double, [Tag Text])
propertyValue _row (TagPosition r _ : rest) = propertyValue r rest
propertyValue row (TagOpen name _ : rest)
  | name `elem` ["int", "long", "short", "float", "double"] = number row rest
propertyValue row (TagClose "void" : _) = Left (MalformedLine row "a property with no value in it")
propertyValue row (_ : rest) = propertyValue row rest
propertyValue row [] = Left (MalformedLine row "a property with no value in it")

number :: Int -> [Tag Text] -> Either ImportError (Int, Double, [Tag Text])
number _row (TagPosition r _ : rest) = number r rest
number row (TagText raw : rest) = case TR.double (T.strip raw) of
  Right (value, leftover) | T.null leftover -> Right (row, value, rest)
  _ -> Left (MalformedLine row ("not a number: " <> T.strip raw))
number row _ = Left (MalformedLine row "a property with no value in it")

-- | One @OriLineProxy@'s properties as a segment.
--
-- Anything the file left out is zero, for the reason in the module header, and
-- anything it named that we do not recognise is ignored rather than refused:
-- a later ORIPA adding a field to that bean should not stop the creases being
-- readable.
segmentFrom :: Int -> [(Text, Double)] -> Either ImportError Segment
segmentFrom row fields = do
  code <- wholeNumber row (valueOf "type")
  assignment <- maybe (Left (UnknownLineType row code)) Right (assignmentForCode code)
  pure
    Segment
      { segLine = row,
        segStart = fromScreenPoint (valueOf "x0") (valueOf "y0"),
        segEnd = fromScreenPoint (valueOf "x1") (valueOf "y1"),
        segAssignment = assignment
      }
  where
    valueOf name = fromMaybe 0 (lookup name fields)

wholeNumber :: Int -> Double -> Either ImportError Int
wholeNumber row value
  | fromIntegral rounded == value = Right rounded
  | otherwise = Left (MalformedLine row ("line type is not a whole number: " <> T.pack (show value)))
  where
    rounded = round value :: Int

-- | What a type code means, or 'Nothing' if ORIPA does not define it.
--
-- Exported for the same reason "Senbazuru.Import.Cp" exports its table: the
-- table is the part worth testing directly.
assignmentForCode :: Int -> Maybe Assignment
assignmentForCode = \case
  0 -> Just Flat
  1 -> Just Border
  2 -> Just Mountain
  3 -> Just Valley
  _ -> Nothing
