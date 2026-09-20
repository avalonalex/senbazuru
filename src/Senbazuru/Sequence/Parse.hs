-- |
-- Module      : Senbazuru.Sequence.Parse
-- Description : A sequence source, the text an author writes, read into a 'Sequence'.
--
-- The second of the two ways to write a fold sequence. The first is Haskell,
-- in "Senbazuru.Sequence.Build"; this one is text in a @.foldseq@ file, and
-- both make the same 'Sequence', so that a test can say the Haskell blintz and
-- the text blintz are equal and mean it.
--
-- It is __not__ an input format in the sense "Senbazuru.Import.Cp" is one, and
-- it does not live beside it. A crease-pattern file describes paper and becomes
-- a @Frame@. A sequence source is a program: running it needs the code that
-- folds paper, and a second file, its sheet. @docs\/architecture.md@ has the
-- rule and its reasons. Nothing here folds anything; the text becomes a tree
-- and stops.
--
-- == The grammar
--
-- A space between items means sequence, @|@ choice, @?@ optional, @*@ zero or
-- more, @+@ one or more. Quoted words are keywords; upper-case names are
-- tokens, described after.
--
-- > source     = "foldseq" INTEGER (SEPS header)* (SEPS step)* (SEPS "closing" STRING)? SEP*
-- > block(x)   = "{" SEP* (x (SEPS x)*)? SEP* "}"
-- >
-- > header     = "title" STRING | "sheet" ("square" | STRING) | "anchor" point
-- >            | ("coloured" | "white") "side" "up" | "start" "folded" stacking
-- > stacking   = "{" SEP* "stacking" "first" SEP* "}" | block("layers" point "above" point)
-- >
-- > step       = "step" NAME? STRING? block(move)
-- > move       = "fold" sense ANGLE? line layers? seed?
-- >            | ("fold" "and" "unfold" | "precrease") sense line layers? seed?
-- >            | "unfold" NAME+ | "turn" "over" ("left-right" | "top-bottom")
-- >            | "rotate" INTEGER"/8" "turn" ("clockwise" | "anticlockwise")
-- >            | "anchor" point | "mark" NAME "=" point ("in" "face" "containing" point)?
-- >            | "let" NAME "=" (line | point)
-- >            | macro "until" ANGLE ("sample" ANGLE+)? | "continue" NAME "until" ANGLE
-- >            | "together" block(move) | "pose" block("crease" segment "at" SIGNED_ANGLE)
-- >            | "repeat" NAME (".." NAME)? ("mirrored" "across" segment | "turned" INTEGER"/4" "about" point)?
-- >            | "checkpoint" STRING stacking | "not" "modelled" STRING
-- >            | "expect" "refused" KIND "{" SEP* move SEP* "}"
-- > macro      = "collapse" "at" point ("keeping" segment "flat")? | "rabbit-ear" "at" point
-- >            | "petal" ("tip" point | "top" "flap")
-- > sense      = "valley" | "mountain" | "in" "front" | "behind"
-- > layers     = "all" "layers" | "top" "layer" | "top" INTEGER "layers" | "top" "flap"
-- > seed       = "moving" point | "flap" "containing" point
-- >
-- > point      = "corner" ("south-west" | "south-east" | "north-east" | "north-west") | "centre"
-- >            | "(" SIGNED "," SIGNED ")" | "midpoint" "of" (segment | "edge" compass)
-- >            | "fraction" NUMBER "along" segment | "meet" simple simple
-- >            | "end" "of" "crease" "of" NAME "nearest" point | NAME
-- > segment    = "[" point "," point "]"
-- > compass    = "north" | "east" | "south" | "west"
-- > line       = alignment | simple
-- > simple     = "edge" compass | segment | "perpendicular" "to" simple "through" point
-- >            | "crease" segment | "hinge" "of" NAME | "crease" "of" NAME
-- >            | "model" "[" pair "," pair "]" | "(" line ")" | NAME
-- > pair       = "(" SIGNED "," SIGNED ")"
-- > alignment  = point "to" point | point "to" simple
-- >            | point "to" simple "through" point nearest?
-- >            | point "to" simple "and" point "to" simple nearest?
-- >            | point "to" simple "perpendicular" "to" simple
-- >            | simple "to" simple nearest?
-- > nearest    = "nearest" point
--
-- The design's grammar also has a @settle { … }@ block in a step and a
-- @material { … }@ line in the header, for the material study. Both are
-- refused here as not yet supported; "Senbazuru.Sequence.Syntax" says why the
-- tree has nowhere to put them yet.
--
-- == The tokens
--
-- * A comment runs from @#@ to the end of its line, outside a string.
-- * @SEP@ is a newline or @;@. Indentation means nothing. __Inside @( )@ and
--   @[ ]@ a newline is only a space__, so a long construction can wrap; that
--   is the one place where a newline does not end a statement.
-- * A word is a letter, then letters, digits, @-@ and @_@, read as far as
--   possible, so @north-west@ and @rabbit-ear@ are one word each. A word on
--   the reserved list is a keyword. Any other word is a @NAME@:
--   @first-petal@ is a name although @first@ is reserved.
-- * @KIND@ is a word starting with a capital letter.
-- * @STRING@ is @"…"@ on one line, with @\\"@, @\\\\@, @\\n@, @\\t@ and
--   @\\u{…}@ for a character by its code in hex. A code that is no
--   character's is refused: one above U+10FFFF, or a surrogate, U+D800 to
--   U+DFFF, which 'Text' would swap for U+FFFD without a word.
-- * @INTEGER@ is digits only. The version is read at any size, so that an
--   absurd one is refused as itself. A count of layers or of turns too large
--   for the tree's 'Int' is refused, because narrowing it would wrap it round
--   to a small one. @NUMBER@ is @175@, @0.58@ or @29\/50@, and every
--   one of them is exact: @0.58@ /is/ @29\/50@. @SIGNED@ is a @NUMBER@ with an
--   optional @-@ directly before it, allowed only in @(u, v)@, in @model@
--   pairs and in a @pose@'s angles.
-- * @ANGLE@ is a @NUMBER@ followed at once by @°@ or @deg@.
--
-- __@rotate 2\/8@ is not read as a quarter.__ After @rotate@ and @turned@ the
-- denominator is part of the word, @\/8@ or @\/4@, and the number before it is
-- kept as typed, because the tree stores a count of eighths, not a fraction.
--
-- == The reserved words
--
-- 'reservedWords' holds them. No name may be one, compared ignoring case, even
-- where only a name could appear, so a step cannot be called @front@. The list
-- is longer than the grammar above needs, on purpose. It holds the words of
-- the blocks not yet supported; words for what the reader /sees/ (@left@,
-- @top@), so that paper is always named by compass and the mistake gets its
-- own message; the names of moves the language cannot express yet (@squash@,
-- @sink@), so that a later version can add them without breaking a source that
-- used one as a name; and a few spellings from the other side of the Atlantic
-- (@center@), reserved only so that they can be corrected.
--
-- == Where the design's two hard cases go
--
-- Both arise inside an /alignment/: a fold line named by what the fold brings
-- together, as in @corner south-west to centre@, the fold that lays that
-- corner onto the centre. The grammar has six forms of it, and every one has a
-- @to@ in it. What stands on either side of the @to@, a point or a line, is
-- called an /operand/ below.
--
-- __A bare name beside @to@.__ In @fold valley a to b@ the parser cannot know
-- whether @b@ names a point or a line: that depends on a @let@ it has not been
-- asked to understand. It reads such a name as a point and leaves the kind to
-- the checker. The whole result goes through
-- 'Senbazuru.Sequence.Syntax.canonical' at the end, so what comes out is
-- always the one tree a text has.
--
-- __@(@ starts two things__ where an operand is expected, a coordinate and a
-- parenthesised line. No line starts with a number, so a digit or a @-@ after
-- the @(@ means a coordinate.
--
-- == Errors are data before they are words
--
-- A failure comes back as a 'ParseProblem': where, what was found, what would
-- have been accepted, and often a 'Hint' naming a well-known mistake, such as
-- @edge left@ or a bare @90@ for an angle. megaparsec's own positions and
-- messages are not used. It counts a tab as several columns, and its
-- \"unexpected \'l\'\" is less use than @found "left"@, so the position is
-- recounted from the text, one column to a character, and the word is read
-- whole.
module Senbazuru.Sequence.Parse
  ( parseSequence,
    reservedWords,
  )
where

import Control.Applicative (empty, (<|>))
import Control.Monad (void, when)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Reader (ReaderT, ask, asks, local, runReaderT)
import Control.Monad.Trans.State.Strict (StateT, evalStateT, get, put)
import Data.Char (chr, digitToInt, isAlpha, isAlphaNum, isDigit, isHexDigit, isUpper)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.List.NonEmpty qualified as NE
import Data.Maybe (fromMaybe)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Sequence.Error
import Senbazuru.Sequence.Syntax
import Text.Megaparsec
  ( ErrorFancy (..),
    ErrorItem (..),
    ParseError (..),
    Parsec,
    atEnd,
    bundleErrors,
    choice,
    getOffset,
    hidden,
    label,
    lookAhead,
    many,
    option,
    optional,
    parseError,
    runParser,
    satisfy,
    sepEndBy,
    skipMany,
    some,
    takeWhile1P,
    takeWhileP,
    try,
  )
import Text.Megaparsec.Char (char, string)

-- | Read a sequence source. The path is only recorded in the spans; nothing
-- is opened.
parseSequence :: FilePath -> Text -> Either SequenceError Sequence
parseSequence path source =
  case runParser (evalStateT (runReaderT sourceFile env) 0) path source of
    Left bundle -> Left (ParseFailed (problemFrom env source (NE.head (bundleErrors bundle))))
    Right parsed -> Right (canonical parsed)
  where
    env = Env {envPath = path, envLineStarts = lineStartsOf source, envWrapped = False}

-- | What the parser carries that megaparsec does not.
--
-- The reader holds the file's name and where its lines start, for making
-- spans, and whether a newline is a space just now, which is true only inside
-- brackets. The state holds the offset at which the last token /ended/. A
-- token also swallows the spaces and comments after it, so the parser's own
-- position is past them, and a span that ended there would underline a
-- comment.
type Parser = ReaderT Env (StateT Int (Parsec Refusal Text))

data Env = Env
  { envPath :: FilePath,
    envLineStarts :: IntMap Int,
    envWrapped :: Bool
  }

-- | A hint, with how many characters of the text it is about. megaparsec
-- wants its custom errors ordered, and nothing here depends on the order.
data Refusal = Refusal Hint Int
  deriving stock (Eq, Ord)

-- ---------------------------------------------------------------------------
-- Words that cannot be names

-- | Every reserved word. The module header says why the list is longer than
-- the grammar.
reservedWords :: Set Text
reservedWords =
  Set.fromList . concat $
    [ -- the header
      ["foldseq", "title", "sheet", "square", "anchor", "coloured", "white", "side", "up", "start", "folded"],
      ["layers", "above", "stacking", "first", "material", "closing"],
      -- structure
      ["step", "together", "pose", "settle", "checkpoint", "not", "modelled", "expect", "refused", "repeat"],
      ["mirrored", "across", "turned", "about", "mark", "let"],
      -- folds
      ["fold", "and", "unfold", "precrease", "valley", "mountain", "in", "front", "behind", "all", "top"],
      ["layer", "flap", "containing", "moving", "face"],
      -- how the model is shown
      ["turn", "over", "left-right", "top-bottom", "rotate", "clockwise", "anticlockwise"],
      -- naming paper
      ["corner", "south-west", "south-east", "north-east", "north-west", "edge", "north", "east", "south", "west"],
      ["centre", "midpoint", "of", "fraction", "along", "meet", "end", "crease", "nearest", "to", "perpendicular"],
      ["through", "hinge", "model"],
      -- macro-moves
      ["collapse", "at", "keeping", "flat", "until", "rabbit-ear", "petal", "tip", "sample", "continue"],
      -- the blocks not yet supported
      ["refine", "hold", "grip", "stationary", "closed", "band", "material-band", "across-hinge", "crease-line"],
      ["upper", "lower", "union", "minus", "rigid-pose", "arc-grip", "rest", "except", "before", "after"],
      ["stiffness", "size", "thickness"],
      viewWords,
      futureMoves,
      map fst otherSpellings
    ]

-- | Words for what the reader sees. Paper is never named by them.
viewWords :: [Text]
viewWords = ["left", "right", "top", "bottom", "front", "behind"]

-- | Moves the language reserves a word for and cannot express yet.
futureMoves :: [Text]
futureMoves = ["squash", "sink", "swivel", "crimp", "pleat", "reverse", "inside-reverse", "outside-reverse"]

-- | Spellings that are not the language's, each with the one that is.
otherSpellings :: [(Text, Text)]
otherSpellings =
  [ ("center", "centre"),
    ("colored", "coloured"),
    ("counterclockwise", "anticlockwise"),
    ("counter-clockwise", "anticlockwise"),
    ("anti-clockwise", "anticlockwise")
  ]

-- ---------------------------------------------------------------------------
-- Space, separators and tokens

-- | Spaces and comments. A newline counts only where the text is wrapped
-- inside brackets. A carriage return always counts, so a file with Windows
-- line ends reads the same.
--
-- 'hidden' keeps it out of every error: without it each message would offer
-- @"#"@ among the things that could have come next, which is true and no help.
space :: Parser ()
space = hidden $ do
  newlineIsSpace <- asks envWrapped
  let blank c = c == ' ' || c == '\t' || c == '\r' || (newlineIsSpace && c == '\n')
  skipMany (void (takeWhile1P Nothing blank) <|> (char '#' *> void (takeWhileP Nothing (/= '\n'))))

-- | A token: the thing itself, a note of where it ended, then the space after.
lexeme :: Parser a -> Parser a
lexeme token = do
  value <- token
  end <- getOffset
  lift (put end)
  space
  pure value

-- | One statement separator, and the blank lines and comments after it.
separator :: Parser ()
separator = label "a new line or \";\"" (lexeme (void (char '\n' <|> char ';')))

wordChar :: Char -> Bool
wordChar c = isAlphaNum c || c == '-' || c == '_'

-- | A word, with nothing consumed after it.
rawWord :: Parser Text
rawWord = T.cons <$> satisfy isAlpha <*> takeWhileP Nothing wordChar

-- | A keyword: the next word, if it is exactly this one.
--
-- The word is looked at before anything is consumed, and that is not
-- fussiness. The obvious way, reading the letters and then checking that no
-- more follow, fails /after/ the letters when more do follow: @to@ against
-- @top@ fails at the @p@. megaparsec keeps whichever failure is furthest along
-- the text, so that stray failure would win, and a message would point into
-- the middle of a word. Peeking keeps every failure at the word's start.
keyword :: Text -> Parser ()
keyword word = label (T.unpack (quote word)) . lexeme $ do
  next <- lookAhead rawWord
  if next == word then void rawWord else empty

symbol :: Text -> Parser ()
symbol text = label (T.unpack (quote text)) (lexeme (void (string text)))

-- | Something between brackets, where a newline is only a space. The closing
-- bracket is read outside that, so the space after it follows the rule of
-- wherever the brackets stand.
bracketed :: Text -> Text -> Parser a -> Parser a
bracketed open close inside = do
  value <- wrapped (symbol open *> inside)
  symbol close
  pure value

-- | Run a parser with a newline counting as a space.
wrapped :: Parser a -> Parser a
wrapped = local (\env -> env {envWrapped = True})

-- | A name. A reserved word here is refused by name, whichever word it is.
name :: Parser Name
name = label "a name" . lexeme $ do
  start <- getOffset
  word <- rawWord
  when (T.toLower word `Set.member` reservedWords) (refuse start (T.length word) (ReservedName word))
  pure (Name word)

-- | The word after @expect refused@: a word starting with a capital.
refusalKind :: Parser RefusalKind
refusalKind = label "a kind of refusal" . lexeme $ do
  word <- lookAhead rawWord
  if maybe False (isUpper . fst) (T.uncons word) then RefusalKind word <$ rawWord else empty

-- | A string. What could have come next is said in words, not as the tokens
-- themselves: a string left open is a common mistake, and a message that
-- quotes a quote, @expected \"\"\"@, is hard to read.
stringLiteral :: Parser Text
stringLiteral = label "a string" . lexeme $ do
  void (char '"')
  pieces <- many (plain <|> escaped)
  void (label "the closing quote of the string" (char '"'))
  pure (T.pack pieces)
  where
    plain = satisfy (\c -> c /= '"' && c /= '\\' && c /= '\n')
    escaped =
      hidden (char '\\')
        *> label
          "one of the escapes \\\", \\\\, \\n, \\t and \\u{…}"
          ( choice
              [ '"' <$ char '"',
                '\\' <$ char '\\',
                '\n' <$ char 'n',
                '\t' <$ char 't',
                char 'u' *> char '{' *> codePoint <* char '}'
              ]
          )
    -- The surrogates, U+D800 to U+DFFF, are codes and not characters. 'chr'
    -- takes one all the same, and 'T.pack' would then swap it for U+FFFD, so
    -- the author's text would change without a word.
    --
    -- The digits are looked at before they are consumed, as a keyword is, so
    -- that a code refused is pointed at where it starts.
    codePoint = label "a character's code in hex" $ do
      digits <- lookAhead (takeWhile1P Nothing isHexDigit)
      let code = T.foldl' (\total d -> total * 16 + digitToInt d) 0 digits
          surrogate = code >= 0xD800 && code <= 0xDFFF
      if T.length digits <= 6 && code <= 0x10FFFF && not surrogate
        then chr code <$ takeWhileP Nothing isHexDigit
        else empty

-- ---------------------------------------------------------------------------
-- Numbers

digits1 :: Parser Text
digits1 = takeWhile1P (Just "a digit") isDigit

valueOf :: Text -> Integer
valueOf = T.foldl' (\total d -> total * 10 + toInteger (digitToInt d)) 0

-- | A whole number the tree keeps in an 'Int', with nothing consumed after it.
--
-- One too large for an 'Int' is refused, because 'fromInteger' narrows
-- without a word: @top 18446744073709551617 layers@, which is 2^64 + 1, would
-- come out as @top layer@.
rawCount :: Parser Int
rawCount = do
  start <- getOffset
  digits <- digits1
  let value = valueOf digits
  when (value > toInteger (maxBound :: Int)) (refuse start (T.length digits) (CountTooLarge value))
  pure (fromInteger value)

integer :: Parser Int
integer = label "a whole number" (lexeme rawCount)

-- | A number as written, exactly: @175@, @0.58@ or @29\/50@. Nothing is
-- consumed after it, because an angle's unit has to follow at once.
--
-- The decimal point is taken only when a digit follows it. That is what makes
-- @0..1\/32@ the number 0 and then @..@, and not a malformed decimal.
rawNumber :: Parser Rational
rawNumber = do
  start <- getOffset
  whole <- digits1
  decimals <- optional (try (char '.' *> digits1))
  case decimals of
    Just places -> pure (fromInteger (valueOf whole) + fromInteger (valueOf places) / 10 ^ T.length places)
    Nothing -> do
      below <- optional (try (char '/' *> digits1))
      case below of
        Nothing -> pure (fromInteger (valueOf whole))
        Just bottom -> do
          end <- getOffset
          when (valueOf bottom == 0) (refuse start (end - start) ZeroDenominator)
          pure (fromInteger (valueOf whole) / fromInteger (valueOf bottom))

-- | Refuse a minus sign where the language allows none.
noSign :: Parser ()
noSign = do
  start <- getOffset
  signed <- option False (True <$ lookAhead (char '-'))
  when signed (refuse start 1 StraySign)

number :: Parser Rational
number = label "a number" (noSign *> lexeme rawNumber)

signedNumber :: Parser Rational
signedNumber = label "a number" . lexeme $ do
  negative <- option False (True <$ char '-')
  value <- rawNumber
  pure (if negative then negate value else value)

-- | The unit that has to follow an angle's number at once. A bare number gets
-- the hint that shows the fix, and so do the two characters that only look
-- like the degree sign.
--
-- @deg@ is matched as a whole word, peeked at first as a keyword is, so that
-- @90degrees@ is a number with no unit and not a failure at the @r@.
--
-- The look-alikes are tested before the letters, and the order matters: @º@,
-- the masculine ordinal, /is/ a letter.
degrees :: Int -> Rational -> Parser ()
degrees start value = do
  here <- getOffset
  next <- optional (lookAhead (satisfy (const True)))
  case next of
    Just '°' -> void (char '°')
    Just c
      | c == 'º' || c == '˚' -> refuse here 1 (NotDegreeSign c)
      | isAlpha c -> do
          unit <- lookAhead rawWord
          if unit == "deg" then void rawWord else needsUnit here
    _ -> needsUnit here
  where
    needsUnit here = refuse start (here - start) (NeedsUnit value)

angle :: Parser Rational
angle = label "an angle" $ do
  noSign
  start <- getOffset
  lexeme (rawNumber >>= \value -> value <$ degrees start value)

signedAngle :: Parser Rational
signedAngle = label "an angle" . lexeme $ do
  negative <- option False (True <$ char '-')
  start <- getOffset
  value <- rawNumber
  degrees start value
  pure (if negative then negate value else value)

-- | A count of eighths or quarters of a turn: a whole number, then the
-- denominator as part of the word, kept as typed.
turnCount :: Text -> Parser Int
turnCount denominator =
  label "a turn" . lexeme $
    rawCount <* label (T.unpack (quote denominator)) (string denominator)

-- ---------------------------------------------------------------------------
-- The file

sourceFile :: Parser Sequence
sourceFile = do
  -- 'hidden', or every wrong first line would be told that a @{@ could have
  -- stood there, when a @{@ is only ever refused.
  looksLikeFold <- option False (True <$ lookAhead (hidden (char '{')))
  when looksLikeFold (refuse 0 1 LooksLikeFold)
  keyword "foldseq"
  versionAt <- getOffset
  -- Read at full width, so that an absurd version is refused as itself.
  version <- label "a whole number" (lexeme (valueOf <$> digits1))
  versionEnd <- lift get
  when (version /= 1) (refuse versionAt (versionEnd - versionAt) (UnsupportedVersion version))
  headerLines versionEnd emptyDraft

-- | The header's lines as they are collected, each at most once.
data Draft = Draft
  { draftTitle :: Maybe Text,
    draftSheet :: Maybe (Located SheetSource),
    draftAnchor :: Maybe (Located Point),
    draftSide :: Maybe Side,
    draftStart :: Maybe (Located Start),
    -- | Each line seen, with the number of the line it was on.
    draftSeen :: [(Text, Int)]
  }

emptyDraft :: Draft
emptyDraft = Draft Nothing Nothing Nothing Nothing Nothing []

-- | Header lines, in any order, until a step, the closing caption or the end.
headerLines :: Int -> Draft -> Parser Sequence
headerLines versionEnd draft =
  endOrMore (finish versionEnd draft [] Nothing) $
    choice [headerLine >>= headerLines versionEnd, stepsAndClosing versionEnd draft []]
  where
    headerLine =
      label "a header line" . choice $
        [ once "title" (\_ text -> draft {draftTitle = Just text}) stringLiteral,
          once "sheet" (\sp sheet -> draft {draftSheet = Just (Located sp sheet)}) sheetSource,
          once "anchor" (\sp p -> draft {draftAnchor = Just (Located sp p)}) point,
          once "start" (\sp spec -> draft {draftStart = Just (Located sp (StartFolded spec))}) (keyword "folded" *> stackingBlock "start folded"),
          side "coloured" ColouredUp,
          side "white" WhiteUp,
          notYet "material" "a material block",
          respelled
        ]

    -- A header line opened by this keyword, refused if it was seen before.
    once word = onceAs word word

    -- Both spellings of the side count as the one line, @side@.
    side word which = onceAs "side" word (\_ () -> draft {draftSide = Just which}) (keyword "side" *> keyword "up")

    -- A line is remembered under its key and underlined as it was written.
    -- For the side the two differ: the key is @side@, the word @coloured@ or
    -- @white@.
    onceAs key word update value = do
      start <- getOffset
      keyword word
      case lookup key (draftSeen draft) of
        Just firstLine -> refuse start (T.length word) (DuplicateHeader key firstLine)
        Nothing -> pure ()
      parsed <- value
      sp <- spanFrom start
      lineNumber <- lineOf start
      pure (update sp parsed) {draftSeen = (key, lineNumber) : draftSeen draft}

    sheetSource = (UnitSquare <$ keyword "square") <|> (SheetFile . T.unpack <$> stringLiteral)

-- | The steps, then perhaps the closing caption. A header line from here on
-- is refused as misplaced, not as unknown.
stepsAndClosing :: Int -> Draft -> [Located Step] -> Parser Sequence
stepsAndClosing versionEnd draft stepsSoFar =
  label "a step or the closing caption" . choice $
    [ step >>= \next -> continueWith (next : stepsSoFar),
      keyword "closing" *> stringLiteral >>= \caption -> many separator *> atEndOrFail *> finish versionEnd draft stepsSoFar (Just caption),
      headerAfterStep
    ]
  where
    continueWith steps = endOrMore (finish versionEnd draft steps Nothing) (stepsAndClosing versionEnd draft steps)

    atEndOrFail = do
      finished <- atEnd
      if finished then pure () else label "the end of the source" empty

    headerAfterStep
      | null stepsSoFar = empty
      | otherwise = do
          (start, word) <- wordWhere (`elem` ["title", "sheet", "anchor", "coloured", "white", "start", "material"])
          refuse start (T.length word) (HeaderAfterStep word)

-- | What follows a statement at the top level: the end of the source, at once
-- or after separators, or else separators and then more.
endOrMore :: Parser a -> Parser a -> Parser a
endOrMore atTheEnd more = do
  finished <- atEnd
  if finished
    then atTheEnd
    else do
      void (some separator)
      finishedNow <- atEnd
      if finishedNow then atTheEnd else more

finish :: Int -> Draft -> [Located Step] -> Maybe Text -> Parser Sequence
finish versionEnd draft newestFirst closing = case draftSheet draft of
  Nothing -> refuse 0 versionEnd SheetMissing
  Just sheet ->
    pure
      Sequence
        { seqHeader =
            Header
              { hTitle = draftTitle draft,
                hSheet = sheet,
                hAnchor = draftAnchor draft,
                hSide = fromMaybe ColouredUp (draftSide draft),
                hStart = fromMaybe (Located NoSpan StartFlat) (draftStart draft),
                hClosing = closing
              },
          seqSteps = reverse newestFirst
        }

-- | @{ stacking first }@, alone in its block, or relations between layers.
stackingBlock :: Text -> Parser StackingSpec
stackingBlock opening = do
  open <- getOffset
  symbol "{"
  void (many separator)
  spec <-
    (StackingFirst <$ (keyword "stacking" *> keyword "first") <* many separator)
      <|> (Relations <$> (relation `sepEndBy` some separator))
  closeBlock open opening
  pure spec
  where
    relation = LayerAbove <$> (keyword "layers" *> point) <*> (keyword "above" *> point)

-- | @{ x; x; … }@
block :: Text -> Parser a -> Parser [a]
block opening item = do
  open <- getOffset
  symbol "{"
  void (many separator)
  items <- item `sepEndBy` some separator
  closeBlock open opening
  pure items

-- | The closing brace. At the end of the text the mistake is an open block,
-- and the place to look is the brace that opened it, not the last line.
closeBlock :: Int -> Text -> Parser ()
closeBlock open opening = do
  finished <- atEnd
  if finished then refuse open 1 (UnclosedBlock opening) else symbol "}"

step :: Parser (Located Step)
step = located $ do
  keyword "step"
  stepLabel <- optional name
  caption <- optional stringLiteral
  let opening = maybe "step" (\(Name text) -> "step " <> text) stepLabel
  moves <- block opening (located move)
  pure (Step stepLabel caption moves)

-- ---------------------------------------------------------------------------
-- Moves

move :: Parser Move
move =
  label "a move" . choice $
    [ keyword "fold" *> (foldAndUnfold <|> fold),
      keyword "precrease" *> precrease,
      Unfold <$> (keyword "unfold" *> some name),
      keyword "turn" *> keyword "over" *> (TurnOver <$> pageAxis),
      keyword "rotate" *> (Rotate <$> turnCount "/8" <*> (keyword "turn" *> turning)),
      Anchor <$> (keyword "anchor" *> point),
      keyword "mark" *> (Mark <$> name <*> (symbol "=" *> point) <*> optional (keyword "in" *> keyword "face" *> keyword "containing" *> point)),
      keyword "let" *> letBinding,
      macro,
      keyword "continue" *> (Continue <$> name <*> (keyword "until" *> angle)),
      keyword "together" *> (Together <$> block "together" (located move)),
      keyword "pose" *> (Pose <$> block "pose" posedCrease),
      keyword "repeat" *> (Repeat <$> name <*> optional (symbol ".." *> name) <*> optional isometry),
      keyword "checkpoint" *> (Checkpoint . T.unpack <$> stringLiteral <*> stackingBlock "checkpoint"),
      keyword "not" *> keyword "modelled" *> (NotModelled <$> stringLiteral),
      keyword "expect" *> keyword "refused" *> (ExpectRefused <$> refusalKind <*> expected),
      notYet "settle" "a settle block",
      futureMove
    ]
  where
    foldAndUnfold = keyword "and" *> keyword "unfold" *> precrease
    precrease = FoldAndUnfold <$> sense <*> line <*> layers <*> seed
    fold = Fold <$> sense <*> amount <*> line <*> layers <*> seed

    sense =
      label "valley or mountain" . choice $
        [ ValleyFold <$ keyword "valley",
          MountainFold <$ keyword "mountain",
          ValleyFold <$ (keyword "in" *> keyword "front"),
          MountainFold <$ keyword "behind"
        ]

    -- No line starts with a digit, so a digit here is the fold's angle.
    amount = do
      startsNumber <- option False (True <$ lookAhead (satisfy (\c -> isDigit c || c == '-')))
      if startsNumber then Degrees <$> angle else pure ToFlat

    layers =
      option FlapOfFirstArgument . choice $
        [ AllLayers <$ (keyword "all" *> keyword "layers"),
          keyword "top" *> choice [TopLayers 1 <$ keyword "layer", TopFlap <$ keyword "flap", TopLayers <$> integer <* keyword "layers"]
        ]

    seed = optional ((keyword "moving" <|> (keyword "flap" *> keyword "containing")) *> point)

    pageAxis = (LeftRight <$ keyword "left-right") <|> (TopBottom <$ keyword "top-bottom")
    turning = choice [Clockwise <$ keyword "clockwise", Anticlockwise <$ keyword "anticlockwise", respelled]

    macro = Macro <$> macroCall <*> option [] (keyword "sample" *> some angle)
    macroCall =
      choice
        [ keyword "collapse" *> keyword "at" *> (Collapse <$> point <*> optional (keyword "keeping" *> segmentEnds <* keyword "flat") <*> untilAngle),
          keyword "rabbit-ear" *> keyword "at" *> (RabbitEar <$> point <*> untilAngle),
          keyword "petal" *> (Petal <$> petalTip <*> untilAngle)
        ]
    petalTip = (TipAt <$> (keyword "tip" *> point)) <|> (TopFlapTip <$ (keyword "top" *> keyword "flap"))
    untilAngle = keyword "until" *> angle

    posedCrease = (\(p, q) a -> (p, q, a)) <$> (keyword "crease" *> segmentEnds) <*> (keyword "at" *> signedAngle)

    isometry =
      (uncurry MirroredAcross <$> (keyword "mirrored" *> keyword "across" *> segmentEnds))
        <|> (keyword "turned" *> (TurnedQuarters <$> turnCount "/4" <*> (keyword "about" *> point)))

    expected = do
      open <- getOffset
      symbol "{"
      void (many separator)
      inner <- move
      void (many separator)
      closeBlock open "expect refused"
      pure inner

    futureMove = do
      (start, word) <- wordWhere (`elem` futureMoves)
      refuse start (T.length word) (FutureMove word)

-- | @let N = …@. A bare name on the right is read as a point, like any name
-- whose kind the text does not say.
letBinding :: Parser Move
letBinding = do
  bound <- name
  symbol "="
  start <- getOffset
  first <- operand
  let alone = case first of
        OPoint p -> BindPoint p
        OLine l -> BindLine l
        OName n -> BindPoint (PointNamed n)
  Let bound <$> ((BindLine <$> (keyword "to" *> alignment start first)) <|> pure alone)

-- | The next word, if it passes a test; consumed if so, and otherwise nothing
-- is.
--
-- Every hint below reads its word with this and refuses only afterwards, and
-- the order matters. A parser that fails having consumed nothing is an
-- invitation to try the next alternative, and the next alternative's
-- complaint would then replace the hint: @anchor center@ used to be refused
-- as a reserved word used as a name, which is true and says nothing about
-- spelling. Consuming the word first makes the hint the last word.
wordWhere :: (Text -> Bool) -> Parser (Int, Text)
wordWhere wanted = do
  start <- getOffset
  word <- lookAhead rawWord
  if wanted word then (start, word) <$ rawWord else empty

-- | A construct the grammar has and this version does not run.
notYet :: Text -> Text -> Parser a
notYet word what = do
  start <- getOffset
  keyword word
  refuse start (T.length word) (NotYetSupported what)

-- | A word spelled another way than the language spells it.
respelled :: Parser a
respelled = do
  (start, word) <- wordWhere (`elem` map fst otherSpellings)
  case lookup word otherSpellings of
    Just ours -> refuse start (T.length word) (SpelledOtherwise word ours)
    Nothing -> empty

-- ---------------------------------------------------------------------------
-- Points and lines

-- | What can stand on either side of @to@: a point, a simple line, or a bare
-- name, whose kind the text does not say.
data Operand = OPoint Point | OLine Line | OName Name

-- | The word that may follow the second operand of an alignment, which is what
-- says which alignment it is.
data AlignmentWord = Through | AndAnother | Perpendicular | Nearest

point :: Parser Point
point = label "a point" (choice [pointForm, coordinate, viewWord, respelled, PointNamed <$> name])

-- | A line where an alignment would have to be in parentheses.
simpleLine :: Parser Line
simpleLine = label "a line" (choice [lineForm, parenthesised, viewWord, LineNamed <$> name])

-- The label keeps a message short. Without it, a statement cut short after
-- @to@ would list every word a point or a line can start with.
operand :: Parser Operand
operand =
  label "a point or a line" . choice $
    [ OPoint <$> pointForm,
      OLine <$> lineForm,
      parenthesisedOrCoordinate,
      viewWord,
      respelled,
      OName <$> name
    ]
  where
    -- No line starts with a number, so a digit or a sign after the bracket
    -- means a coordinate. The bracket is read as 'bracketed' reads it, so that
    -- whatever may stand between it and the number there, a new line or a
    -- comment, may stand there here.
    parenthesisedOrCoordinate = do
      isCoordinate <- option False (True <$ lookAhead (try (wrapped (symbol "(") *> satisfy (\c -> isDigit c || c == '-'))))
      if isCoordinate then OPoint <$> coordinate else OLine <$> parenthesised

-- | A point that starts with a keyword of its own.
pointForm :: Parser Point
pointForm =
  choice
    [ keyword "corner" *> (CornerOf <$> corner),
      Centre <$ keyword "centre",
      keyword "midpoint" *> keyword "of" *> ((MidpointOfEdge <$> (keyword "edge" *> compass)) <|> (uncurry MidpointOf <$> segmentEnds)),
      keyword "fraction" *> ((\r (p, q) -> FractionAlong r p q) <$> number <*> (keyword "along" *> (alongEdge <|> segmentEnds))),
      keyword "meet" *> (Meet <$> simpleLine <*> simpleLine),
      keyword "end" *> keyword "of" *> keyword "crease" *> keyword "of" *> (EndOfCreaseOf <$> name <*> (keyword "nearest" *> point))
    ]
  where
    alongEdge = do
      start <- getOffset
      keyword "edge"
      refuse start 4 FractionAlongEdge
    corner =
      label "a corner of the sheet" . choice $
        [ SouthWest <$ keyword "south-west",
          SouthEast <$ keyword "south-east",
          NorthEast <$ keyword "north-east",
          NorthWest <$ keyword "north-west",
          viewWordOrCompound
        ]

coordinate :: Parser Point
coordinate = uncurry AtSheet <$> numberPair

numberPair :: Parser (Rational, Rational)
numberPair = bracketed "(" ")" ((,) <$> signedNumber <*> (symbol "," *> signedNumber))

segmentEnds :: Parser (Point, Point)
segmentEnds = label "a segment [P, Q]" (bracketed "[" "]" ((,) <$> point <*> (symbol "," *> point)))

compass :: Parser Compass
compass =
  label "a side of the sheet" . choice $
    [North <$ keyword "north", East <$ keyword "east", South <$ keyword "south", West <$ keyword "west", viewWordOrCompound]

-- | A word for what the reader sees, where paper is being named.
viewWord :: Parser a
viewWord = do
  (start, word) <- wordWhere (`elem` viewWords)
  refuse start (T.length word) (ViewWordForMaterial word)

-- | The same, where only a corner or a side of the sheet can come, and there a
-- word made of view words counts too: @top-left@. Elsewhere such a word is an
-- ordinary name, as @first-petal@ is, because only whole words are reserved.
viewWordOrCompound :: Parser a
viewWordOrCompound = do
  (start, word) <- wordWhere (all (`elem` viewWords) . T.splitOn "-")
  refuse start (T.length word) (ViewWordForMaterial word)

-- | A line that starts with a keyword or a bracket of its own.
lineForm :: Parser Line
lineForm =
  choice
    [ keyword "edge" *> (EdgeOf <$> compass),
      uncurry Segment <$> segmentEnds,
      keyword "perpendicular" *> keyword "to" *> (PerpendicularThrough <$> simpleLine <*> (keyword "through" *> point)),
      keyword "crease" *> ((CreaseOf <$> (keyword "of" *> name)) <|> (uncurry ExistingCrease <$> segmentEnds)),
      keyword "hinge" *> keyword "of" *> (HingeOf <$> name),
      keyword "model" *> bracketed "[" "]" (ModelSegment <$> numberPair <*> (symbol "," *> numberPair))
    ]

parenthesised :: Parser Line
parenthesised = bracketed "(" ")" line

-- | A line standing alone: after @fold@, or inside parentheses.
line :: Parser Line
line = label "a line" $ do
  start <- getOffset
  first <- operand
  case first of
    OPoint _ -> keyword "to" *> alignment start first
    OLine l -> (keyword "to" *> alignment start first) <|> pure l
    OName n -> (keyword "to" *> alignment start first) <|> pure (LineNamed n)

-- | Everything after the first @to@. Which of the six forms this is, is
-- decided by the word after the second operand, and where there is none, by
-- what the two operands are.
--
-- The word is looked for first and the form is built afterwards, outside any
-- choice between alternatives. That is on purpose. Two of the refusals below
-- point /back/, at an operand already read, and megaparsec keeps whichever of
-- two competing failures is further along the text. Raised as one alternative
-- among several, a refusal that points back would always lose to the
-- alternatives that failed at the current position.
alignment :: Int -> Operand -> Parser Line
alignment firstAt first = do
  secondAt <- getOffset
  second <- operand
  secondEnd <- lift get
  nextAt <- getOffset
  next <-
    optional . choice $
      [ Through <$ keyword "through",
        AndAnother <$ keyword "and",
        Perpendicular <$ (keyword "perpendicular" *> keyword "to"),
        Nearest <$ lookAhead (keyword "nearest")
      ]
  case next of
    Just Through -> do
      p <- asPoint firstAt first
      l <- asLine secondAt second
      PointToLineThrough p l <$> point <*> nearest
    Just AndAnother -> do
      p <- asPoint firstAt first
      l1 <- asLine secondAt second
      q <- point
      l2 <- keyword "to" *> simpleLine
      TwoToTwo p l1 q l2 <$> nearest
    Just Perpendicular -> do
      p <- asPoint firstAt first
      l1 <- asLine secondAt second
      PointToLinePerpendicular p l1 <$> simpleLine
    -- @nearest@ with no other word can only end a line laid onto a line.
    Just Nearest -> case (first, second) of
      (OPoint _, _) -> refuse nextAt 7 NearestWithoutTwoLines
      (_, OPoint _) -> refuse nextAt 7 NearestWithoutTwoLines
      _ -> LineOnto <$> asLine firstAt first <*> asLine secondAt second <*> nearest
    Nothing -> case (first, second) of
      (OLine l1, OLine l2) -> pure (LineOnto l1 l2 Nothing)
      (OLine l1, OName b) -> pure (LineOnto l1 (LineNamed b) Nothing)
      (OLine _, OPoint _) -> refuse secondAt (secondEnd - secondAt) LineOntoPoint
      (_, OLine l) -> (`PointToLine` l) <$> asPoint firstAt first
      (_, OPoint q) -> (`Onto` q) <$> asPoint firstAt first
      (_, OName b) -> (`Onto` PointNamed b) <$> asPoint firstAt first
  where
    nearest = optional (keyword "nearest" *> point)

    asPoint at = \case
      OPoint p -> pure p
      OName n -> pure (PointNamed n)
      OLine _ -> expectedAt at "a point"

    asLine at = \case
      OLine l -> pure l
      OName n -> pure (LineNamed n)
      OPoint _ -> expectedAt at "a line"

-- ---------------------------------------------------------------------------
-- Spans and failures

-- | A piece of the tree with the span it was written at: from where it starts
-- to where its last token ended.
located :: Parser a -> Parser (Located a)
located piece = do
  start <- getOffset
  value <- piece
  sp <- spanFrom start
  pure (Located sp value)

spanFrom :: Int -> Parser Span
spanFrom start = do
  end <- lift get
  env <- ask
  pure (spanBetween env start end)

-- | The span between two offsets, the second exclusive. The two may be on
-- different lines: text inside brackets can wrap.
spanBetween :: Env -> Int -> Int -> Span
spanBetween env start end = Span (envPath env) startLine startColumn endLine endColumn
  where
    (startLine, startColumn) = positionOf (envLineStarts env) start
    (endLine, endColumn) = positionOf (envLineStarts env) end

lineOf :: Int -> Parser Int
lineOf offset = asks (fst . (`positionOf` offset) . envLineStarts)

-- | Fail with a hint about this many characters from this offset.
refuse :: Int -> Int -> Hint -> Parser a
refuse at width hint = parseError (FancyError at (Set.singleton (ErrorCustom (Refusal hint width))))

-- | Fail at an earlier offset, saying what should have been there.
expectedAt :: Int -> String -> Parser a
expectedAt at what = case NE.nonEmpty what of
  Just text -> parseError (TrivialError at Nothing (Set.singleton (Label text)))
  Nothing -> empty

-- | Where each line starts: the offset of its first character, and the line's
-- number. Line 1 starts at 0, so every offset has a line at or before it.
lineStartsOf :: Text -> IntMap Int
lineStartsOf source =
  IntMap.fromDistinctAscList (zip (0 : [index + 1 | (index, c) <- zip [0 ..] (T.unpack source), c == '\n']) [1 ..])

-- | Line and column of an offset, both counted from 1, one column to a
-- character: the last line that starts at or before the offset, and how far
-- into it the offset is. The second case is never reached, because line 1
-- starts at 0 and no offset is negative.
positionOf :: IntMap Int -> Int -> (Int, Int)
positionOf starts offset = case IntMap.lookupLE offset starts of
  Just (lineStart, lineNumber) -> (lineNumber, offset - lineStart + 1)
  Nothing -> (1, offset + 1)

-- | megaparsec's error as the language's own. Only the first error is used.
problemFrom :: Env -> Text -> ParseError Text Refusal -> ParseProblem
problemFrom env source = \case
  FancyError at problems
    | Refusal hint width : _ <- [refusal | ErrorCustom refusal <- Set.toList problems] ->
        ParseProblem (spanOf at width) (foundAt at) [] (Just hint)
    | otherwise -> ParseProblem (spanOf at (widthOf (foundAt at))) (foundAt at) [] Nothing
  -- The items are turned into words before they are listed, not after. A
  -- token and a label can spell the same thing, and would be listed twice.
  TrivialError at _ expectedItems ->
    ParseProblem (spanOf at (widthOf (foundAt at))) (foundAt at) (Set.toList (Set.map itemWords expectedItems)) Nothing
  where
    spanOf at width = spanBetween env at (at + width)

    -- What is at the offset, read whole: a word, a number, or one character.
    foundAt at = case T.uncons (T.drop at source) of
      Nothing -> FoundEnd
      Just (c, _)
        | c == '\n' || c == '\r' -> FoundLineEnd
        | isAlpha c -> FoundWord (T.takeWhile wordChar (T.drop at source))
        | isDigit c -> FoundWord (T.takeWhile (\d -> isDigit d || d == '.' || d == '/') (T.drop at source))
        | otherwise -> FoundChar c

    widthOf = \case
      FoundWord word -> T.length word
      FoundChar _ -> 1
      FoundLineEnd -> 0
      FoundEnd -> 0

    itemWords = \case
      Tokens characters -> quote (T.pack (NE.toList characters))
      Label text -> T.pack (NE.toList text)
      EndOfInput -> "the end of the source"
