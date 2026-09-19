-- |
-- Tests for the sequence language's error type, and for how an error reaches a
-- person.
--
-- There is no parser or checker yet, so nothing here produces an error: each
-- test builds one by hand and looks at what comes out. That is enough to pin
-- the three things the rest of the language will lean on.
--
-- __The shape of a message.__ A message is one line that can follow a colon:
-- no capital to open, no full stop to close, no path, and no word that only
-- makes sense at a command line. Nothing in the types says so, and a new
-- constructor is exactly where the rule gets broken, so every constructor of
-- 'StaticProblem' and 'Hint' is sampled. 'sampledStatic' and 'sampledHint'
-- exist for one reason: they match on every constructor with no catch-all, so
-- a constructor added without a sample here is a compiler warning.
--
-- __The excerpt__, which is fiddly in ways that only show on a real line: the
-- caret must sit under the right character when the line holds a tab, must not
-- run past the end of the line, and must still appear for a span with no
-- width. The three examples the language's design prints are reproduced
-- character for character, location included.
--
-- __The list of refusal kinds__ is hand-written text that has to agree with
-- constructors elsewhere in the library. Eleven of its names exist as
-- constructors today, and a test reads each one's spelling off a real value.
module Senbazuru.Sequence.ErrorSpec (spec) where

import Data.Char (isAlphaNum, isUpper)
import Data.List (nub)
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Query (CreaseEnd (..), FoldError (..))
import Senbazuru.Fold.Types (EdgeId (..), FaceId (..), VertexId (..))
import Senbazuru.Origami.Flap (FlapError (..))
import Senbazuru.Origami.Folding (FoldingError (..))
import Senbazuru.Origami.ThroughLayers (ThroughError (..))
import Senbazuru.Sequence.Error
import Senbazuru.Sequence.Syntax (RefusalKind (..), Span (..))
import Test.Hspec

spec :: Spec
spec = do
  describe "a message" $ do
    it "says something, for every static problem and every hint" $
      [who | (who, msg) <- everyMessage, T.null msg] `shouldBe` []

    it "does not open with a capital, so it can follow a colon" $
      [who | (who, msg) <- everyMessage, maybe False (isUpper . fst) (T.uncons msg)] `shouldBe` []

    it "ends without a full stop and stays on one line" $
      [who | (who, msg) <- everyMessage, "." `T.isSuffixOf` msg || T.any (== '\n') msg] `shouldBe` []

    -- A message is also read at a GHCi prompt and by the material study, where
    -- a command's name or a flag would mean nothing.
    it "names no command and no flag" $
      [who | (who, msg) <- everyMessage, any (`T.isInfixOf` msg) ["senbazuru", "--", " run "]] `shouldBe` []

  describe "a static refusal" $ do
    it "opens with its step and the step's name, the only place a Haskell author can look" $
      explain (StaticRefused (InStep 2 (Just "c1")) NoSpan (DuplicateName "c1"))
        `shouldBe` "step 2 (c1): \"c1\" is already defined, and a name can be given only once"

    it "opens with the step alone when it has no name, and with the header for a header line" $
      map (T.takeWhile (/= ':') . explain) [StaticRefused (InStep 3 Nothing) NoSpan EmptyStep, StaticRefused InHeader NoSpan (UnknownName "tip")]
        `shouldBe` ["step 3", "header"]

    it "has no location and no excerpt when the sequence was never text" $ do
      let err = StaticRefused (InStep 2 (Just "c1")) NoSpan (DuplicateName "c1")
      (sourceLocation err, excerpt "anything" err) `shouldBe` (Nothing, Nothing)

    it "says which way a range is open" $
      explain (ParameterOutOfRange 200 (Exclusive 0) (Inclusive 180))
        `shouldBe` "200° is out of range: it must be more than 0° and at most 180°"

    -- A number in a message is spelled as the printer spells it, or an author
    -- is told about a 0.58 that appears nowhere in the printed sequence.
    it "spells a number exactly, as the printer does" $
      explain (RatioOutOfRange (158 / 100)) `shouldBe` "fraction 79/50 is outside 0 to 1"

  describe "a parse problem" $ do
    it "is its hint, when it has one" $
      explain (problemAt NoSpan (FoundWord "90") ["an angle"] (Just (NeedsUnit 90)))
        `shouldBe` "an angle needs its unit: write 90°"

    it "otherwise says what was found and what could have been there" $
      map
        explain
        [ problemAt NoSpan (FoundWord "fold") ["step", "closing"] Nothing,
          problemAt NoSpan (FoundChar '}') ["a move", "settle", "\"}\""] Nothing,
          problemAt NoSpan FoundEnd ["\"}\""] Nothing,
          problemAt NoSpan (FoundWord "fold") [] Nothing
        ]
        `shouldBe` [ "found \"fold\" where step or closing was expected",
                     "found \"}\" where a move, settle or \"}\" was expected",
                     "found the end of the source where \"}\" was expected",
                     "found \"fold\", which cannot come here"
                   ]

    it "names both code points for a character that only looks like the degree sign" $
      explain (problemAt NoSpan (FoundChar 'º') [] (Just (NotDegreeSign 'º')))
        `shouldBe` "\"º\" (U+00BA) is not the degree sign; write ° (U+00B0) or deg"

  describe "sourceLocation" $
    it "is path, line and column of where the error starts" $
      sourceLocation (ParseFailed (problemAt (Span "examples/w.foldseq" 7 20 7 24) (FoundWord "left") [] Nothing))
        `shouldBe` Just "examples/w.foldseq:7:20"

  -- The three outputs the design prints, on the sources it prints them for.
  describe "excerpt, on the design's three examples" $ do
    it "underlines a word" $
      excerptOf quarterFoldTyped (Span "quarter.foldseq" 7 20 7 24)
        `shouldBe` Just "  |\n7 |   fold behind edge left to edge east\n  |                    ^^^^"

    it "widens the gutter for a two-digit line number" $
      excerptOf (T.replicate 12 "\n" <> "  fold behind 90 corner north-west to midpoint of edge north\n") (Span "wing.foldseq" 13 15 13 17)
        `shouldBe` Just "   |\n13 |   fold behind 90 corner north-west to midpoint of edge north\n   |               ^^"

    it "points one caret at the brace of an unclosed block" $
      excerptOf quarterFoldTyped (Span "quarter.foldseq" 6 56 6 57)
        `shouldBe` Just "  |\n6 | step half \"Fold the left half behind, onto the right.\" {\n  |                                                        ^"

  describe "excerpt, where it is easy to get wrong" $ do
    -- A tab's width is the terminal's business. Copying it keeps the caret
    -- under the right character whatever that width is; a space would not.
    it "copies each tab of the source line into the caret line" $
      excerptOf "\tfold\tvalley edge left\n" (Span "t.foldseq" 1 19 1 23)
        `shouldBe` Just "  |\n1 | \tfold\tvalley edge left\n  | \t    \t            ^^^^"

    it "underlines a span that runs past its first line to the end of that line" $
      excerptOf "step {\n  unfold\n}\n" (Span "t.foldseq" 1 1 3 2)
        `shouldBe` Just "  |\n1 | step {\n  | ^^^^^^"

    it "draws one caret for a span with no width, and none past the end of the line" $
      map (excerptOf "fold\n") [Span "t.foldseq" 1 5 1 5, Span "t.foldseq" 1 3 1 40]
        `shouldBe` [Just "  |\n1 | fold\n  |     ^", Just "  |\n1 | fold\n  |   ^^"]

    it "shows the same line whether the file ends its lines with a carriage return or not" $
      excerptOf "fold left\r\nunfold\r\n" (Span "t.foldseq" 1 6 1 10)
        `shouldBe` excerptOf "fold left\nunfold\n" (Span "t.foldseq" 1 6 1 10)

    it "is nothing for a line the text does not have" $
      map (excerptOf "fold\n") [Span "t.foldseq" 9 1 9 2, Span "t.foldseq" 0 1 0 2]
        `shouldBe` [Nothing, Nothing]

  describe "refusalKinds" $ do
    it "lists no kind twice" $
      length (nub refusalKinds) `shouldBe` length refusalKinds

    -- The text reads a kind as a word starting with a capital, so a name that
    -- is not one could never be written after @expect refused@.
    it "holds only names a source can spell as a kind" $
      [kind | RefusalKind kind <- refusalKinds, not (spellableKind kind)] `shouldBe` []

    it "holds the kinds the design's own examples expect" $
      filter (`notElem` refusalKinds) (map RefusalKind ["FlapCovered", "FlapEndpointOrder", "ExistingHingeFlat"]) `shouldBe` []

    -- Eleven of the names are constructors that exist today. Reading the
    -- spelling off a real value means a renamed constructor fails here, not
    -- months later when a sequence expects a refusal that can no longer be
    -- named.
    it "spells today's constructors as the library does" $
      filter (`notElem` refusalKinds) (map RefusalKind constructorsOfToday) `shouldBe` []

-- | The constructor name of each refusal in 'refusalKinds' that already
-- exists in the library, read from a real value.
constructorsOfToday :: [Text]
constructorsOfToday =
  map
    (T.takeWhile isAlphaNum . T.pack)
    [ show (FlapCoupled (EdgeId 0) [VertexId 0]),
      show (FlapNotHinge (EdgeId 0)),
      show (FlapNotBoundary (EdgeId 0)),
      show (FlapUnalignedCrease (EdgeId 0)),
      show (FlapEndpointOrder 0 NoVertices),
      show (FlapStackOrder NoVertices),
      show FlapStartMismatch,
      show (TornAt (VertexId 0) 0),
      show (AngleNotAchieved (EdgeId 0) 0),
      show (LineStopsOnTheModel FromEnd (FaceId 0)),
      show (GaveUpStacking 0)
    ]

spellableKind :: Text -> Bool
spellableKind kind = case T.uncons kind of
  Just (c, rest) -> isUpper c && T.all isAlphaNum rest
  Nothing -> False

problemAt :: Span -> Found -> [Text] -> Maybe Hint -> ParseProblem
problemAt sp found expected hint =
  ParseProblem {problemSpan = sp, problemFound = found, problemExpected = expected, problemHint = hint}

-- | The excerpt of an error at this span in this source.
excerptOf :: Text -> Span -> Maybe Text
excerptOf source sp = excerpt source (ParseFailed (problemAt sp FoundEnd [] Nothing))

-- | The quarter fold as the design prints it, with @edge west@ mistyped as
-- @edge left@ on line 7. Line 6 ends in the brace the design's third example
-- points at.
quarterFoldTyped :: Text
quarterFoldTyped =
  T.unlines
    [ "foldseq 1",
      "title \"A square folded into quarters\"",
      "sheet \"examples/quarter-fold-steps.fold\"",
      "anchor (3/4, 1/4)          # south-east quarter, which neither step moves",
      "",
      "step half \"Fold the left half behind, onto the right.\" {",
      "  fold behind edge left to edge east",
      "}"
    ]

-- | Every message this module can make from a static problem or a hint, each
-- labelled with where it came from.
everyMessage :: [(String, Text)]
everyMessage =
  [("StaticProblem " <> sampledStatic p, explain p) | p <- staticSamples]
    <> [("Hint " <> sampledHint h, explain (problemAt NoSpan FoundEnd [] (Just h))) | h <- hintSamples]

staticSamples :: [StaticProblem]
staticSamples =
  [ UnknownName "tip",
    DuplicateName "c1",
    WrongKind "tip" LineName PointName,
    EmptyStep,
    RatioOutOfRange (3 / 2),
    NotEighths 9,
    NotQuarters 0,
    ParameterOutOfRange 200 (Exclusive 0) (Inclusive 180),
    UnknownRefusalKind (RefusalKind "FlapCoverd"),
    NotASingleMacro "base",
    NotAFigure "names",
    HingeOfSeveralMoves "folds",
    RepeatUnmappable "folds",
    NotANameToken "two words",
    ReservedWordAsName "north-west",
    LayerCountNotPositive 0,
    SignNotAllowed (-90),
    UnfoldNamesNothing
  ]

hintSamples :: [Hint]
hintSamples =
  [ ViewWordForMaterial "left",
    FutureMove "squash",
    ReservedName "front",
    NeedsUnit 90,
    NotDegreeSign '˚',
    StraySign,
    ZeroDenominator,
    UnclosedBlock "step half",
    UnsupportedVersion 2,
    LooksLikeFold,
    FractionAlongEdge,
    DuplicateHeader "title" 2,
    HeaderAfterStep "sheet",
    NotYetSupported "a settle block"
  ]

-- | The constructor's name. Written as a match on every constructor, with no
-- catch-all, so that a constructor added to 'StaticProblem' without a sample
-- in 'staticSamples' at least warns here.
sampledStatic :: StaticProblem -> String
sampledStatic = \case
  UnknownName {} -> "UnknownName"
  DuplicateName {} -> "DuplicateName"
  WrongKind {} -> "WrongKind"
  EmptyStep -> "EmptyStep"
  RatioOutOfRange {} -> "RatioOutOfRange"
  NotEighths {} -> "NotEighths"
  NotQuarters {} -> "NotQuarters"
  ParameterOutOfRange {} -> "ParameterOutOfRange"
  UnknownRefusalKind {} -> "UnknownRefusalKind"
  NotASingleMacro {} -> "NotASingleMacro"
  NotAFigure {} -> "NotAFigure"
  HingeOfSeveralMoves {} -> "HingeOfSeveralMoves"
  RepeatUnmappable {} -> "RepeatUnmappable"
  NotANameToken {} -> "NotANameToken"
  ReservedWordAsName {} -> "ReservedWordAsName"
  LayerCountNotPositive {} -> "LayerCountNotPositive"
  SignNotAllowed {} -> "SignNotAllowed"
  UnfoldNamesNothing -> "UnfoldNamesNothing"

sampledHint :: Hint -> String
sampledHint = \case
  ViewWordForMaterial {} -> "ViewWordForMaterial"
  FutureMove {} -> "FutureMove"
  ReservedName {} -> "ReservedName"
  NeedsUnit {} -> "NeedsUnit"
  NotDegreeSign {} -> "NotDegreeSign"
  StraySign -> "StraySign"
  ZeroDenominator -> "ZeroDenominator"
  UnclosedBlock {} -> "UnclosedBlock"
  UnsupportedVersion {} -> "UnsupportedVersion"
  LooksLikeFold -> "LooksLikeFold"
  FractionAlongEdge -> "FractionAlongEdge"
  DuplicateHeader {} -> "DuplicateHeader"
  HeaderAfterStep {} -> "HeaderAfterStep"
  NotYetSupported {} -> "NotYetSupported"
