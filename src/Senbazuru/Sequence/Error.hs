-- |
-- Module      : Senbazuru.Sequence.Error
-- Description : One type for every way a fold sequence can be refused, and how it reaches a person.
--
-- A fold sequence is refused in stages. Its text may not parse. It may parse
-- and still make no sense without any paper: a step that unfolds a step which
-- does not exist. Later it may make sense and still be impossible to fold.
-- Each stage is a different piece of code, and all of them hand back the same
-- 'SequenceError', so that whoever runs a sequence has one thing to catch and
-- one way to print it. That is why this module sits below the parser and the
-- checker and is imported by both: the type they share can live in neither.
--
-- This is the first half of it, the half that needs no paper: 'ParseFailed'
-- and 'StaticRefused'. The refusals that come from folding arrive with the
-- code that folds.
--
-- == A refusal reaches a person as three pieces, kept apart
--
-- 'explain' gives the message, one line. 'sourceLocation' gives
-- @path:line:col@. 'excerpt' gives the source line with a caret under the
-- offending text. A command line prints all three. They are not one string
-- for three reasons, each of which was a bug waiting to happen:
--
-- * A sequence built in Haskell has no position, so for it the last two are
--   'Nothing' and the message has to stand alone.
-- * __The message never holds the source's path, though every line a command
--   prints starts with one.__ That looks like an omission and is the design:
--   the path comes from 'sourceLocation', so no line of output names it twice,
--   and a Haskell author gets the same sentence with no prefix.
-- * A message is also read at a GHCi prompt and by the material study, where
--   a flag or a command's name would be noise. So no message here names one.
--
-- == Why a static refusal names its step as well as its span
--
-- 'StaticRefused' carries a 'Place' beside its 'Span', which looks redundant.
-- For parsed text it nearly is. For a built sequence the span is 'NoSpan', and
-- then the message's first words, @step 2 (c1)@, are the only place its author
-- can look.
--
-- == A parse problem is data, not a sentence
--
-- A 'ParseProblem' records what was found, what would have been accepted, and
-- often a 'Hint': a constructor saying which well-known mistake this is, such
-- as writing @left@ where paper is named by compass. The words are chosen
-- here, in one 'Explain' instance, so a test can match on the mistake without
-- matching on the wording, and the wording can improve without the parser
-- changing.
--
-- == The names @expect refused@ may use
--
-- A sequence can say that it expects a move to be refused, and how:
-- @expect refused FlapCovered { … }@. The checker has to tell a real kind from
-- a typo before any paper exists to refuse anything, so the names are listed
-- here, in 'refusalKinds', from the design's catalogue of refusals. Most of
-- them name a refusal whose code is not written yet; each gains its producer
-- at the milestone that folds that kind of move.
module Senbazuru.Sequence.Error
  ( -- * The error
    SequenceError (..),
    Place (..),

    -- * Text that does not parse
    ParseProblem (..),
    Found (..),
    Hint (..),
    quote,

    -- * Text that parses and cannot mean anything
    StaticProblem (..),
    NameKind (..),
    Bound (..),
    RepeatObstacle (..),

    -- * The kinds a sequence may expect
    refusalKinds,

    -- * Where, for a person
    errorSpan,
    sourceLocation,
    excerpt,
  )
where

import Data.Char (ord)
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Numeric (showHex)
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Sequence.Syntax (Name (..), RefusalKind (..), Span (..), exactNumber)

-- | Every way a sequence can be refused before any paper is folded.
data SequenceError
  = -- | The text is not a sequence source.
    ParseFailed ParseProblem
  | -- | The sequence cannot mean anything, whatever the paper. The 'Span' is
    -- 'NoSpan' for a sequence built in Haskell; the 'Place' is always there.
    StaticRefused Place Span StaticProblem
  deriving stock (Eq, Show)

-- | Where in a sequence a static problem is, in words an author can use
-- without a file: the header, or a step counted from 1 with its name if it has
-- one. Steps are counted as written, including any that draw no picture.
data Place = InHeader | InStep Int (Maybe Name)
  deriving stock (Eq, Show)

-- | What went wrong reading text: where, what was there, what could have been,
-- and which common mistake it looks like, if any.
data ParseProblem = ParseProblem
  { problemSpan :: Span,
    problemFound :: Found,
    -- | What would have been accepted here, as short labels: @a point@,
    -- @"{"@. Shown only when there is no hint, since a hint says more.
    problemExpected :: [Text],
    problemHint :: Maybe Hint
  }
  deriving stock (Eq, Show)

-- | What the parser met. A failed keyword reports the whole word, so a message
-- says @found "left"@ and not @found \'l\'@. The end of a line has a
-- constructor of its own because a statement that stops short is a common
-- mistake, and a quoted newline is no way to say so.
data Found = FoundWord Text | FoundChar Char | FoundLineEnd | FoundEnd
  deriving stock (Eq, Show)

-- | A mistake common enough to have its own sentence.
data Hint
  = -- | @left@, @top@ and the like where paper is expected. Paper is named by
    -- compass, because a compass word stays true when the model is turned.
    ViewWordForMaterial Text
  | -- | A move the language reserves a word for and cannot express yet, such
    -- as @squash@.
    FutureMove Text
  | -- | A reserved word where a name was expected.
    ReservedName Text
  | -- | A bare number where an angle belongs. The number is kept so that the
    -- message can show the correction: @write 90°@.
    NeedsUnit Rational
  | -- | A character that looks like the degree sign and is not: @º@ (U+00BA)
    -- or @˚@ (U+02DA).
    NotDegreeSign Char
  | -- | A minus sign where the language allows none.
    StraySign
  | -- | @n\/0@. A parse problem and not a static one, because no 'Rational'
    -- can hold it, so no tree could carry it as far as the checker.
    ZeroDenominator
  | -- | A count of layers or of turns too large for the tree to hold. A parse
    -- problem for the same reason: the tree keeps a count in an 'Int', and
    -- narrowing a larger number would wrap it round to a small one in silence.
    CountTooLarge Integer
  | -- | A @{@ that is never closed, with the words that opened it:
    -- @step half@. Its span is the brace, not the end of the file, because
    -- the brace is what the author has to find.
    UnclosedBlock Text
  | -- | A first line @foldseq N@ with an N this reader does not know.
    UnsupportedVersion Integer
  | -- | The text starts with @{@: someone handed over a FOLD file.
    LooksLikeFold
  | -- | @fraction r along edge S@. Refused because nothing says which end of
    -- the edge @r@ counts from.
    FractionAlongEdge
  | -- | A header line given twice, with the line number of the first.
    DuplicateHeader Text Int
  | -- | A header line written after a step.
    HeaderAfterStep Text
  | -- | A construct the grammar has and this version does not run yet, such as
    -- a @settle@ block.
    NotYetSupported Text
  | -- | A word the language spells another way: what was written, then the
    -- language's spelling. @center@ is @centre@, @counterclockwise@ is
    -- @anticlockwise@. Those words are reserved for the sake of this hint.
    SpelledOtherwise Text Text
  | -- | The header has no @sheet@ line, the one line a source must have: a
    -- sequence has to say what paper it starts from.
    SheetMissing
  | -- | @L to P@: a line laid onto a point. A point can be laid onto a line
    -- and a line onto a line, and the other way round names no fold.
    LineOntoPoint
  | -- | @nearest@ after @P to Q@ or @P to L@. It chooses between the two ways
    -- one line can be laid onto another, and those forms have only one way.
    NearestWithoutTwoLines
  deriving stock (Eq, Ord, Show)

-- | What a name names. A point's name where a line belongs is the mistake the
-- Haskell builder's types catch and text cannot.
data NameKind = PointName | LineName | StepName
  deriving stock (Eq, Show, Enum, Bounded)

-- | One end of an allowed range, and whether the end itself is allowed.
data Bound = Inclusive Rational | Exclusive Rational
  deriving stock (Eq, Show)

-- | Why a step cannot be repeated mirrored or turned. A repeat carries the
-- step's moves to another part of the sheet by moving the /names/ in them,
-- and each of these is something a name on the sheet cannot express.
data RepeatObstacle
  = -- | The step has a @model [...]@ line, which is in the model's coordinates
    -- as seen and not a place on the sheet.
    UsesModelCoordinates
  | -- | The step says @top N layers@, and a count from the reader's side means
    -- different paper elsewhere.
    CountsLayers
  | -- | The mirror line or the centre of the turn is named by a construction,
    -- such as where two lines meet. It has to be an exact point of the sheet:
    -- a corner, the centre, @(u, v)@ or the midpoint of an edge, so that the
    -- moved names stay exact.
    IsometryByConstruction
  deriving stock (Eq, Show, Enum, Bounded)

-- | What can be wrong with a sequence that parsed, or was built, before any
-- paper is involved.
data StaticProblem
  = -- | A name nothing defines, or nothing defines /yet/: a name may be used
    -- only after the step or move that gives it.
    UnknownName Name
  | -- | A name given twice.
    DuplicateName Name
  | -- | A name of one kind where another belongs: the name, the kind wanted,
    -- the kind it is.
    WrongKind Name NameKind NameKind
  | -- | A step that does nothing: no move, or only @let@s. It would draw a
    -- picture identical to the one before it.
    EmptyStep
  | -- | @fraction r along@ with @r@ outside 0 to 1.
    RatioOutOfRange Rational
  | -- | @rotate k\/8@ with @k@ outside 1 to 7.
    NotEighths Int
  | -- | @turned k\/4@ with @k@ outside 1 to 3.
    NotQuarters Int
  | -- | A /macro-move/ is a named move that turns several creases together,
    -- such as @collapse@, and runs until its driving crease reaches an angle.
    -- This is that angle, or the angle of an in-between pose, outside what
    -- the move allows: the angle, then the lower and upper ends of the range.
    ParameterOutOfRange Rational Bound Bound
  | -- | @expect refused KIND@ with a kind that names no refusal.
    UnknownRefusalKind RefusalKind
  | -- | @continue NAME@, where the named step is not exactly one macro-move.
    NotASingleMacro Name
  | -- | @unfold NAME@ or @repeat NAME@, where the named step draws no picture
    -- of its own and so has nothing to undo or do again.
    NotAFigure Name
  | -- | @hinge of NAME@, where the named step made several moves and so has no
    -- one line it turned paper about.
    HingeOfSeveralMoves Name
  | -- | @repeat NAME@ with a mirror or a turn, where something cannot be
    -- carried to another part of the sheet: the step, and what is in the way.
    RepeatUnmappable Name RepeatObstacle
  | -- | @repeat N..M@ where M's step comes before N's: the two names, as
    -- written. A range runs forwards through the steps, so this one holds
    -- nothing. The design's catalogue has no entry for it; it is here because
    -- it needs no paper to see.
    RangeRunsBackwards Name Name
  | -- | Only a Haskell builder can make the rest; text cannot spell them. A
    -- 'Name' that is not a name token, such as @"two words"@.
    NotANameToken Name
  | -- | A 'Name' that is a reserved word, compared ignoring case.
    ReservedWordAsName Name
  | -- | @top N layers@ with @N@ below 1.
    LayerCountNotPositive Int
  | -- | A negative number where text allows no sign, such as a fold's angle.
    SignNotAllowed Rational
  | -- | @unfold@ naming no step. The grammar wants at least one name, and a
    -- Haskell list can be empty.
    UnfoldNamesNothing
  deriving stock (Eq, Show)

instance Explain SequenceError where
  explain = \case
    ParseFailed problem -> explain problem
    StaticRefused place _ problem -> placeWords place <> ": " <> explain problem
    where
      placeWords = \case
        InHeader -> "header"
        InStep n Nothing -> "step " <> tshow n
        InStep n (Just (Name name)) -> "step " <> tshow n <> " (" <> name <> ")"

instance Explain ParseProblem where
  explain problem = case problemHint problem of
    Just hint -> explain hint
    Nothing -> case problemExpected problem of
      [] -> "found " <> foundWords (problemFound problem) <> ", which cannot come here"
      labels -> "found " <> foundWords (problemFound problem) <> " where " <> oneOf labels <> " was expected"
    where
      foundWords = \case
        FoundWord word -> quote word
        FoundChar c -> quote (T.singleton c)
        FoundLineEnd -> "the end of the line"
        FoundEnd -> "the end of the source"

instance Explain StaticProblem where
  explain = \case
    UnknownName (Name name) ->
      quote name <> " is not defined here; a name can be used only after the step or move that gives it"
    DuplicateName (Name name) -> quote name <> " is already defined, and a name can be given only once"
    WrongKind (Name name) wanted actual ->
      quote name <> " names " <> kindWords actual <> ", and " <> kindWords wanted <> " is needed here"
    EmptyStep -> "this step makes no move, so it would draw the same picture as the step before it"
    RatioOutOfRange r -> "fraction " <> exactNumber r <> " is outside 0 to 1"
    NotEighths k -> "rotate " <> tshow k <> "/8: a turn is 1 to 7 eighths"
    NotQuarters k -> "turned " <> tshow k <> "/4: a turn is 1 to 3 quarters"
    ParameterOutOfRange a lower upper ->
      exactNumber a <> "° is out of range: it must be " <> lowerWords lower <> " and " <> upperWords upper
    UnknownRefusalKind (RefusalKind kind) -> quote kind <> " is not a kind of refusal"
    NotASingleMacro (Name name) ->
      quote name <> " cannot be continued: a step can be continued only if it is exactly one macro-move"
    NotAFigure (Name name) ->
      quote name <> " draws no picture of its own, so there is nothing to unfold or repeat"
    HingeOfSeveralMoves (Name name) ->
      quote name <> " makes several moves, so it has no one hinge; name the line another way"
    RepeatUnmappable (Name name) obstacle ->
      quote name <> " cannot be repeated mirrored or turned: " <> obstacleWords obstacle
    RangeRunsBackwards (Name from) (Name to) ->
      quote (from <> ".." <> to) <> " runs backwards: " <> quote to <> " comes before " <> quote from <> "; write " <> quote (to <> ".." <> from)
    NotANameToken (Name name) ->
      quote name <> " is not a name: a name is a letter, then letters, digits, - and _"
    ReservedWordAsName (Name name) -> quote name <> " is a reserved word and cannot be a name"
    LayerCountNotPositive n -> "top " <> tshow n <> " layers selects no layer; the count starts at 1"
    SignNotAllowed r ->
      exactNumber r <> " is negative, and a sign is allowed only in (u, v), in model pairs and in pose angles"
    UnfoldNamesNothing -> "unfold names no step; it needs at least one"
    where
      obstacleWords = \case
        UsesModelCoordinates -> "it has a model [...] line, which is not a place on the sheet"
        CountsLayers -> "it says top N layers, and a count of layers means different paper elsewhere"
        IsometryByConstruction -> "the mirror line or the centre of the turn is a construction, and has to be a corner, the centre, (u, v) or the midpoint of an edge"
      kindWords = \case
        PointName -> "a point"
        LineName -> "a line"
        StepName -> "a step"
      lowerWords = \case
        Inclusive r -> "at least " <> exactNumber r <> "°"
        Exclusive r -> "more than " <> exactNumber r <> "°"
      upperWords = \case
        Inclusive r -> "at most " <> exactNumber r <> "°"
        Exclusive r -> "less than " <> exactNumber r <> "°"

instance Explain Hint where
  explain = hintWords

hintWords :: Hint -> Text
hintWords = \case
  ViewWordForMaterial word ->
    quote word
      <> " names a direction on the page; paper is named by compass: edge north, east, south or west, and corner south-west, south-east, north-east or north-west"
  FutureMove word ->
    quote word <> " is reserved for a move the language cannot express yet; write not modelled " <> quote word
  ReservedName word -> quote word <> " is a reserved word and cannot be a name"
  NeedsUnit a -> "an angle needs its unit: write " <> exactNumber a <> "°"
  NotDegreeSign c ->
    quote (T.singleton c) <> " (" <> codePoint c <> ") is not the degree sign; write ° (" <> codePoint '°' <> ") or deg"
  StraySign -> "a minus sign is allowed only in (u, v), in model pairs and in pose angles"
  ZeroDenominator -> "a fraction cannot have a denominator of 0"
  CountTooLarge n -> tshow n <> " is too large to be a count of layers or of turns"
  UnclosedBlock opening -> "the " <> quote "{" <> " opening " <> opening <> " is never closed"
  UnsupportedVersion n -> "this is foldseq version " <> tshow n <> ", and only version 1 is understood"
  LooksLikeFold -> "this looks like a FOLD file, not a sequence source"
  FractionAlongEdge ->
    "fraction along an edge is not allowed, because nothing says which end it counts from; write fraction r along [P, Q]"
  DuplicateHeader line firstLine -> line <> " is given twice; the first is on line " <> tshow firstLine
  HeaderAfterStep line -> line <> " is a header line, and header lines come before the first step"
  NotYetSupported what -> what <> " is not supported yet"
  SpelledOtherwise written ours -> quote written <> " is spelled " <> quote ours <> " here"
  SheetMissing -> "there is no sheet line; a sequence has to say what paper it starts from: sheet square, or sheet and a file"
  LineOntoPoint -> "a line cannot be laid onto a point; lay the point onto the line, or name a second line"
  NearestWithoutTwoLines ->
    "nearest chooses between the two ways of laying one line onto another, and there is only one way to make this fold"
  where
    codePoint c = "U+" <> T.justifyRight 4 '0' (T.toUpper (T.pack (showHex (ord c) "")))

-- | A word of the source as a message shows it, between double quotes.
-- Exported for the parser, which quotes the keywords it expected: what was
-- found and what was expected stand in one sentence, and have to be quoted
-- alike.
quote :: Text -> Text
quote text = "\"" <> text <> "\""

-- | @a@, @a or b@, @a, b or c@
oneOf :: [Text] -> Text
oneOf = \case
  [] -> ""
  [only] -> only
  [first, second] -> first <> " or " <> second
  first : rest -> first <> ", " <> oneOf rest

-- | The names @expect refused@ may use, from the design's catalogue of
-- refusals (@PRDs\/02-language-semantics.md@, §12). Only refusals that
-- /running a move/ can raise are here. A parse or static problem inside the
-- expected move refuses the whole sequence before anything runs, so expecting
-- one would never come true.
--
-- The groups follow the type each refusal will belong to. Three of the groups
-- name constructors that exist today, in "Senbazuru.Origami.Flap",
-- "Senbazuru.Origami.Folding" and "Senbazuru.Origami.ThroughLayers", and a
-- test holds this list to their spelling.
refusalKinds :: [RefusalKind]
refusalKinds =
  map RefusalKind . concat $
    [ -- naming paper against a state
      ["NearMiss", "VertexMiss", "TwoVerticesWithin", "NotInOneFace", "OffThePaper", "PlacementsDisagree"],
      ["EdgeNotStraight", "CreaseNotStraight", "EmptyCrease", "ConstructionInTheAir"],
      ["NoSolution", "NeedsNearest", "NearestAmbiguous", "DegenerateConstruction", "NoCreaseThere"],
      ["MarkOnSeveralLayers", "EndTie", "LandmarkAmbiguous"],
      -- choosing which paper moves
      ["SeedMissing", "SeedOnTheLine", "SegmentStraddles", "SeedSplit", "UnorderedOverlap", "DepthChangesAlong"],
      ["SelectionCoupled", "NoUncoupledFlap", "FlapCovered", "LineStopsInSelectedFace", "NothingSelected"],
      ["ExistingHingeFlat", "LayersInTheAir"],
      -- macro-moves
      ["NoMatch", "SeveralMatches", "KeepingNotAPair", "PetalGeometryUnsupported", "DegenerateRabbitEar"],
      ["RoleCreaseChanged", "MacroStateChanged", "NotBeyondReached"],
      -- layer order
      ["RelationOnOneFace", "RelationNotOverlapping", "RelationsContradict", "StillAmbiguous", "SeveralStackings"],
      ["GaveUpStacking"],
      -- the library's own refusals of a turn, a fold or a crease
      ["FlapCoupled", "FlapNotHinge", "FlapNotBoundary", "FlapUnalignedCrease", "FlapEndpointOrder"],
      ["FlapStackOrder", "FlapStartMismatch", "FlapMovingNotFlat", "FlapMovesBothWays"],
      ["TornAt", "AngleNotAchieved", "LineStopsOnTheModel"],
      -- the run itself
      ["ReanchorNotFlat", "JoinBroken", "MoveLeavesFigure", "RepeatNotSymmetric", "CheckpointOutlineDiffers"],
      ["UnfoldChangedSince"]
    ]

-- | Where the error is, or 'NoSpan' for a sequence that was never text.
errorSpan :: SequenceError -> Span
errorSpan = \case
  ParseFailed problem -> problemSpan problem
  StaticRefused _ sp _ -> sp

-- | @path:line:col@ of where the error starts, counted from 1, with a column
-- counting characters and a tab counting as one. 'Nothing' for 'NoSpan'.
sourceLocation :: SequenceError -> Maybe Text
sourceLocation err = case errorSpan err of
  NoSpan -> Nothing
  Span path line column _ _ -> Just (T.pack path <> ":" <> tshow line <> ":" <> tshow column)

-- | The offending line of the source with a caret under the offending text,
-- the only output here that takes more than one line:
--
-- >   |
-- > 7 |   fold behind edge left to edge east
-- >   |                    ^^^^
--
-- The first argument is the text the error's positions refer to. 'Nothing'
-- for 'NoSpan', and for a position the text does not have.
--
-- __The caret line copies every tab of the source line__, which looks like a
-- slip and is what keeps the caret under the right character: a tab's width
-- is the reader's terminal's business, and a copied tab is as wide as the
-- one above it, where a space would not be.
--
-- That is the only width handled. A column counts characters, and a terminal
-- draws some characters two cells wide, so a caption in Japanese earlier on
-- the same line leaves the caret short of its word by one cell for each. The
-- line and column in 'sourceLocation' are still right, and they are what an
-- editor jumps to.
--
-- A span running past its first line is underlined to the end of that line,
-- which is how a whole step or an unclosed block points at where it opens.
excerpt :: Text -> SequenceError -> Maybe Text
excerpt source err = case errorSpan err of
  NoSpan -> Nothing
  Span _ startLine startColumn endLine endColumn -> do
    sourceLine <- lineAt startLine
    let number = tshow startLine
        gutter = T.replicate (T.length number) " " <> " |"
        before = T.take (startColumn - 1) sourceLine
        padding = T.map (\c -> if c == '\t' then '\t' else ' ') before
        toEndOfLine = T.length sourceLine - T.length before
        wanted
          | endLine == startLine = endColumn - startColumn
          | otherwise = toEndOfLine
        -- At least one caret, and none past the end of the line.
        carets = T.replicate (max 1 (min wanted toEndOfLine)) "^"
    pure (T.intercalate "\n" [gutter, number <> " | " <> sourceLine, gutter <> " " <> padding <> carets])
  where
    -- A line keeps no trailing carriage return, so a file with Windows line
    -- ends shows the same excerpt.
    lineAt n
      | n < 1 = Nothing
      | otherwise = T.dropWhileEnd (== '\r') <$> listToMaybe (drop (n - 1) (T.splitOn "\n" source))
